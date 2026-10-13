import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';
import { existsSync, readFileSync, renameSync, unlinkSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import type { AiStatus } from '../shared/types.ts';
import { AppError } from './errors.ts';
import type { RuntimeState } from './runtime-state.ts';
import { secretSchema } from './validation.ts';
import { z } from 'zod';

const MAX_SECRET_BYTES = 64 * 1024;
const base64Value = z
  .string()
  .regex(/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/);
const envelopeSchema = z
  .object({
    version: z.union([z.literal(1), z.literal(2)]),
    iv: base64Value.max(16),
    tag: base64Value.max(24),
    ciphertext: base64Value.max(4 * Math.ceil(MAX_SECRET_BYTES / 3)),
  })
  .strict();
function decodeBase64(value: string) {
  const buffer = Buffer.from(value, 'base64');
  if (buffer.toString('base64') !== value) throw new Error('Invalid encoding');
  return buffer;
}

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
        : /^[A-Za-z0-9+/]{43}=?$/.test(text) &&
            Buffer.from(text, 'base64').toString('base64').replace(/=$/, '') ===
              text.replace(/=$/, '')
          ? Buffer.from(text, 'base64')
          : Buffer.alloc(0);
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
    if (Buffer.byteLength(text, 'utf8') > MAX_SECRET_BYTES)
      throw new AppError(
        400,
        'SECRET_TOO_LARGE',
        'Сохранённый секрет превышает допустимый размер.',
      );
    const iv = randomBytes(12),
      cipher = createCipheriv('aes-256-gcm', this.key(), iv, { authTagLength: 16 });
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
      if (blob.length > 90_000) throw new Error('Oversized envelope');
      const envelope = envelopeSchema.parse(JSON.parse(blob));
      if (envelope.version !== 2 && !(envelope.version === 1 && name === 'openai'))
        throw new Error('Invalid envelope');
      const iv = decodeBase64(envelope.iv),
        tag = decodeBase64(envelope.tag),
        ciphertext = decodeBase64(envelope.ciphertext);
      if (iv.length !== 12 || tag.length !== 16 || ciphertext.length > MAX_SECRET_BYTES)
        throw new Error('Invalid envelope parameters');
      const decipher = createDecipheriv('aes-256-gcm', this.key(), iv, { authTagLength: 16 });
      if (envelope.version === 2) decipher.setAAD(Buffer.from(name));
      decipher.setAuthTag(tag);
      return Buffer.concat([decipher.update(ciphertext), decipher.final()]).toString('utf8');
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
    try {
      return secretSchema.parse(JSON.parse(blob));
    } catch {
      throw new AppError(500, 'SECRET_STORE_ERROR', 'Не удалось прочитать ключ ИИ.');
    }
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
    const parsed = secretSchema.safeParse(value);
    if (!parsed.success)
      throw new AppError(400, 'SECRET_INVALID', 'Проверьте формат ключа OpenAI и название модели.');
    await this.saveSecret('openai', JSON.stringify(parsed.data));
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
