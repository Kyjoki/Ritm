import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';
import { existsSync, readFileSync, renameSync, unlinkSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import type { AiStatus } from '../shared/types.ts';
import { AppError } from './errors.ts';

export const defaultModel = 'gpt-6-luna';

interface SavedSecret {
  apiKey: string;
  model: string;
}
interface Envelope {
  version: 1;
  iv: string;
  tag: string;
  ciphertext: string;
}

/** Credentials never enter SQLite, bootstrap payloads, client code, or logs. */
export class SecretStore {
  private secretPath: string;
  private keyPath: string;
  constructor(
    dataDir: string,
    private env: NodeJS.ProcessEnv = process.env,
  ) {
    this.secretPath = join(dataDir, 'openai-secret.json');
    this.keyPath = join(dataDir, '.secret-key');
  }
  private key(): Buffer {
    if (!existsSync(this.keyPath)) {
      writeFileSync(this.keyPath, randomBytes(32), { flag: 'wx', mode: 0o600 });
    }
    const value = readFileSync(this.keyPath);
    if (value.length !== 32)
      throw new AppError(
        500,
        'SECRET_STORE_ERROR',
        'Не удалось прочитать защищённое хранилище. Проверьте серверную конфигурацию.',
      );
    return value;
  }
  private saved(): SavedSecret | null {
    if (!existsSync(this.secretPath)) return null;
    try {
      const envelope = JSON.parse(readFileSync(this.secretPath, 'utf8')) as Envelope;
      if (envelope.version !== 1 || !existsSync(this.keyPath)) throw new Error('Invalid envelope');
      const decipher = createDecipheriv(
        'aes-256-gcm',
        this.key(),
        Buffer.from(envelope.iv, 'base64'),
      );
      decipher.setAuthTag(Buffer.from(envelope.tag, 'base64'));
      const text = Buffer.concat([
        decipher.update(Buffer.from(envelope.ciphertext, 'base64')),
        decipher.final(),
      ]).toString('utf8');
      const value = JSON.parse(text) as SavedSecret;
      if (typeof value.apiKey !== 'string' || typeof value.model !== 'string')
        throw new Error('Invalid secret');
      return value;
    } catch {
      throw new AppError(
        500,
        'SECRET_STORE_ERROR',
        'Не удалось прочитать ключ ИИ. Восстановите data/.secret-key из резервной копии или настройте ключ заново.',
      );
    }
  }
  credentials(): SavedSecret | null {
    const environment = this.env.OPENAI_API_KEY?.trim();
    if (environment)
      return { apiKey: environment, model: this.env.OPENAI_MODEL?.trim() || defaultModel };
    return this.saved();
  }
  status(): AiStatus {
    const credential = this.credentials();
    return {
      configured: Boolean(credential),
      model: credential?.model || this.env.OPENAI_MODEL?.trim() || defaultModel,
      source: this.env.OPENAI_API_KEY?.trim() ? 'environment' : credential ? 'saved' : 'none',
    };
  }
  save(value: SavedSecret): AiStatus {
    if (this.env.OPENAI_API_KEY?.trim()) {
      throw new AppError(
        409,
        'ENVIRONMENT_KEY',
        'Ключ задан на сервере через OPENAI_API_KEY. Измените серверную переменную и перезапустите приложение.',
      );
    }
    const iv = randomBytes(12);
    const cipher = createCipheriv('aes-256-gcm', this.key(), iv);
    const ciphertext = Buffer.concat([
      cipher.update(JSON.stringify(value), 'utf8'),
      cipher.final(),
    ]);
    const envelope: Envelope = {
      version: 1,
      iv: iv.toString('base64'),
      tag: cipher.getAuthTag().toString('base64'),
      ciphertext: ciphertext.toString('base64'),
    };
    const temporary = `${this.secretPath}.${randomBytes(8).toString('hex')}.tmp`;
    writeFileSync(temporary, JSON.stringify(envelope), { flag: 'wx', mode: 0o600 });
    try {
      renameSync(temporary, this.secretPath);
    } catch (error) {
      unlinkSync(temporary);
      throw error;
    }
    return this.status();
  }
  remove(): AiStatus {
    if (this.env.OPENAI_API_KEY?.trim()) {
      throw new AppError(
        409,
        'ENVIRONMENT_KEY',
        'Ключ задан через OPENAI_API_KEY. Удалите серверную переменную и перезапустите приложение.',
      );
    }
    if (existsSync(this.secretPath)) unlinkSync(this.secretPath);
    return this.status();
  }
}
