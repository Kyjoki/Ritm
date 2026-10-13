import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';
import { existsSync, readFileSync, renameSync, unlinkSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import type { AiStatus } from '../shared/types.ts';
import { AppError } from './errors.ts';
import type { RuntimeState } from './runtime-state.ts';

export const defaultModel = 'gpt-6-luna';
interface SavedSecret {
  apiKey: string;
  model: string;
}
interface Envelope {
  version: 1 | 2;
  iv: string;
  tag: string;
  ciphertext: string;
}

/** Encrypted blobs in shared PostgreSQL or local ignored storage. */
export class SecretStore {
  constructor(
    private dataDir: string,
    private env: NodeJS.ProcessEnv = process.env,
    private state?: RuntimeState,
    private shared = false,
  ) {}
  private name(value: string) {
    if (!/^[a-zA-Z0-9._:-]{1,180}$/.test(value)) throw new Error('Invalid secret name.');
    return value;
  }
  private key(): Buffer {
    if (this.env.SECRET_ENCRYPTION_KEY) {
      const text = this.env.SECRET_ENCRYPTION_KEY;
      const value = /^[a-fA-F0-9]{64}$/.test(text)
        ? Buffer.from(text, 'hex')
        : Buffer.from(text, 'base64');
      if (value.length !== 32)
        throw new AppError(
          503,
          'SECRET_STORE_ERROR',
          'Настройте SECRET_ENCRYPTION_KEY: 32 случайных байта в base64 или hex.',
        );
      return value;
    }
    if (this.shared)
      throw new AppError(
        503,
        'SECRET_STORE_ERROR',
        'Серверное шифрование ещё не настроено. Добавьте SECRET_ENCRYPTION_KEY.',
      );
    const path = join(this.dataDir, '.secret-key');
    if (!existsSync(path)) writeFileSync(path, randomBytes(32), { flag: 'wx', mode: 0o600 });
    const value = readFileSync(path);
    if (value.length !== 32)
      throw new AppError(500, 'SECRET_STORE_ERROR', 'Не удалось прочитать защищённое хранилище.');
    return value;
  }
  private encrypt(name: string, text: string): string {
    const iv = randomBytes(12),
      cipher = createCipheriv('aes-256-gcm', this.key(), iv);
    cipher.setAAD(Buffer.from(name));
    const ciphertext = Buffer.concat([cipher.update(text, 'utf8'), cipher.final()]);
    const envelope: Envelope = {
      version: 2,
      iv: iv.toString('base64'),
      tag: cipher.getAuthTag().toString('base64'),
      ciphertext: ciphertext.toString('base64'),
    };
    return JSON.stringify(envelope);
  }
  private decrypt(name: string, blob: string): string {
    try {
      const envelope = JSON.parse(blob) as Envelope;
      if (envelope.version !== 2 && !(envelope.version === 1 && name === 'openai'))
        throw new Error('Invalid envelope');
      const decipher = createDecipheriv(
        'aes-256-gcm',
        this.key(),
        Buffer.from(envelope.iv, 'base64'),
      );
      if (envelope.version === 2) decipher.setAAD(Buffer.from(name));
      decipher.setAuthTag(Buffer.from(envelope.tag, 'base64'));
      return Buffer.concat([
        decipher.update(Buffer.from(envelope.ciphertext, 'base64')),
        decipher.final(),
      ]).toString('utf8');
    } catch (error) {
      if (error instanceof AppError) throw error;
      throw new AppError(
        500,
        'SECRET_STORE_ERROR',
        'Не удалось прочитать сохранённый секрет. Проверьте ключ шифрования или настройте подключение заново.',
      );
    }
  }
  private useFile(name: string) {
    return !this.shared && name === 'openai';
  }
  async getSecret(name: string): Promise<string | null> {
    this.name(name);
    const path = join(this.dataDir, 'openai-secret.json');
    const blob = this.useFile(name)
      ? existsSync(path)
        ? readFileSync(path, 'utf8')
        : null
      : ((await this.state?.getServerSecret(name)) ?? null);
    return blob ? this.decrypt(name, blob) : null;
  }
  async saveSecret(name: string, value: string): Promise<void> {
    this.name(name);
    const ciphertext = this.encrypt(name, value);
    if (this.useFile(name)) {
      const path = join(this.dataDir, 'openai-secret.json'),
        temporary = path + '.' + randomBytes(8).toString('hex') + '.tmp';
      writeFileSync(temporary, ciphertext, { flag: 'wx', mode: 0o600 });
      try {
        renameSync(temporary, path);
      } catch (error) {
        unlinkSync(temporary);
        throw error;
      }
    } else {
      if (!this.state)
        throw new AppError(503, 'SECRET_STORE_ERROR', 'Хранилище подключения ещё не настроено.');
      await this.state.setServerSecret(name, ciphertext);
    }
  }
  async removeSecret(name: string): Promise<void> {
    this.name(name);
    if (this.useFile(name)) {
      const path = join(this.dataDir, 'openai-secret.json');
      if (existsSync(path)) unlinkSync(path);
    } else await this.state?.deleteServerSecret(name);
  }
  async consumeSecret(name: string): Promise<string | null> {
    this.name(name);
    if (this.useFile(name)) {
      const value = await this.getSecret(name);
      await this.removeSecret(name);
      return value;
    }
    const blob = (await this.state?.consumeServerSecret(name)) ?? null;
    return blob ? this.decrypt(name, blob) : null;
  }
  async acquireLease(name: string, ttlMs: number) {
    if (!this.state) return null;
    return this.state.acquireLease(this.name(name), ttlMs);
  }
  async releaseLease(name: string, token: string) {
    await this.state?.releaseLease(this.name(name), token);
  }
  async credentials(): Promise<SavedSecret | null> {
    const environment = this.env.OPENAI_API_KEY?.trim();
    if (environment)
      return { apiKey: environment, model: this.env.OPENAI_MODEL?.trim() || defaultModel };
    const blob = await this.getSecret('openai');
    if (!blob) return null;
    const value = JSON.parse(blob) as SavedSecret;
    if (typeof value.apiKey !== 'string' || typeof value.model !== 'string')
      throw new AppError(500, 'SECRET_STORE_ERROR', 'Не удалось прочитать ключ ИИ.');
    return value;
  }
  async status(): Promise<AiStatus> {
    const credential = await this.credentials();
    return {
      configured: Boolean(credential),
      model: credential?.model || this.env.OPENAI_MODEL?.trim() || defaultModel,
      source: this.env.OPENAI_API_KEY?.trim() ? 'environment' : credential ? 'saved' : 'none',
    };
  }
  async save(value: SavedSecret): Promise<AiStatus> {
    if (this.env.OPENAI_API_KEY?.trim())
      throw new AppError(
        409,
        'ENVIRONMENT_KEY',
        'Ключ задан на сервере через OPENAI_API_KEY. Измените серверную переменную и перезапустите приложение.',
      );
    await this.saveSecret('openai', JSON.stringify(value));
    return this.status();
  }
  async remove(): Promise<AiStatus> {
    if (this.env.OPENAI_API_KEY?.trim())
      throw new AppError(
        409,
        'ENVIRONMENT_KEY',
        'Ключ задан через OPENAI_API_KEY. Удалите серверную переменную и перезапустите приложение.',
      );
    await this.removeSecret('openai');
    return this.status();
  }
}
