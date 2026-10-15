import { randomBytes, timingSafeEqual } from 'node:crypto';
import { z } from 'zod';
import { AppError } from './errors.ts';
import type { TelegramStatus } from '../shared/types.ts';
import type { SecretStore } from './secrets.ts';

export const TELEGRAM_WEBHOOK_PATH = '/api/integrations/telegram/webhook';
const CONFIG_NAME = 'telegram-connection';
const PAIRING_LIFETIME_MS = 10 * 60_000;
const botTokenSchema = z
  .string()
  .trim()
  .regex(/^\d{6,16}:[A-Za-z0-9_-]{20,128}$/);
const configurationSchema = z.object({
  botToken: botTokenSchema,
  botUsername: z.string().regex(/^[A-Za-z0-9_]{5,32}$/),
  webhookSecret: z.string().regex(/^[A-Za-z0-9_-]{32,128}$/),
  pending: z.object({ token: z.string(), expiresAt: z.number() }).optional(),
  account: z
    .object({
      userId: z.number().int(),
      chatId: z.number().int(),
      username: z.string().optional(),
      firstName: z.string().max(128),
    })
    .optional(),
});
const updateSchema = z.object({
  update_id: z.number().int(),
  message: z
    .object({
      text: z.string().max(256).optional(),
      from: z.object({
        id: z.number().int(),
        is_bot: z.boolean().optional(),
        username: z.string().max(32).optional(),
        first_name: z.string().max(128),
      }),
      chat: z.object({ id: z.number().int(), type: z.string() }),
    })
    .optional(),
});
type Configuration = z.infer<typeof configurationSchema>;

function equals(left: string, right: string) {
  const a = Buffer.from(left),
    b = Buffer.from(right);
  return a.length === b.length && timingSafeEqual(a, b);
}

export function createTelegramService({
  secrets,
  origin,
  transport = fetch,
  now = Date.now,
}: {
  secrets: SecretStore;
  origin?: string;
  transport?: typeof fetch;
  now?: () => number;
}) {
  async function read(): Promise<Configuration | null> {
    const value = await secrets.getSecret(CONFIG_NAME);
    if (!value) return null;
    try {
      return configurationSchema.parse(JSON.parse(value));
    } catch {
      throw new AppError(
        500,
        'TELEGRAM_CONFIGURATION_ERROR',
        'Не удалось прочитать подключение Telegram.',
      );
    }
  }
  async function write(value: Configuration) {
    await secrets.saveSecret(CONFIG_NAME, JSON.stringify(value));
  }
  async function call<T>(token: string, method: string, body: object): Promise<T> {
    try {
      const response = await transport(`https://api.telegram.org/bot${token}/${method}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(10_000),
      });
      const result = (await response.json()) as { ok?: boolean; result?: T };
      if (!response.ok || !result.ok || result.result === undefined || result.result === false)
        throw new Error('Telegram rejected request');
      return result.result;
    } catch {
      throw new AppError(
        502,
        'TELEGRAM_UNAVAILABLE',
        'Telegram не принял настройку. Проверьте токен бота и повторите попытку.',
      );
    }
  }
  function statusOf(config: Configuration | null): TelegramStatus {
    if (!config) return { configured: false, linked: false };
    return {
      configured: true,
      linked: Boolean(config.account),
      botUsername: config.botUsername,
      account: config.account
        ? { username: config.account.username, firstName: config.account.firstName }
        : undefined,
      pairingUrl:
        config.pending && config.pending.expiresAt > now()
          ? `https://t.me/${config.botUsername}?start=${config.pending.token}`
          : undefined,
      pairingExpiresAt:
        config.pending && config.pending.expiresAt > now() ? config.pending.expiresAt : undefined,
    };
  }
  async function status() {
    return statusOf(await read());
  }
  async function configure(botToken: string): Promise<TelegramStatus> {
    const token = botTokenSchema.parse(botToken);
    if (!origin || !origin.startsWith('https://'))
      throw new AppError(
        503,
        'TELEGRAM_ORIGIN_REQUIRED',
        'Для Telegram настройте публичный HTTPS-адрес Ritm.',
      );
    const me = await call<{ id: number; is_bot: boolean; username?: string }>(token, 'getMe', {});
    if (!me.is_bot || !me.username || !/^[A-Za-z0-9_]{5,32}$/.test(me.username))
      throw new AppError(
        400,
        'TELEGRAM_INVALID_BOT',
        'Этот токен не принадлежит Telegram-боту с публичным именем.',
      );
    const existing = await read();
    const next: Configuration = {
      botToken: token,
      botUsername: me.username,
      webhookSecret: randomBytes(32).toString('base64url'),
      ...(existing?.botToken === token && existing.account ? { account: existing.account } : {}),
    };
    await call<boolean>(token, 'setWebhook', {
      url: origin + TELEGRAM_WEBHOOK_PATH,
      secret_token: next.webhookSecret,
      allowed_updates: ['message'],
      drop_pending_updates: true,
      max_connections: 1,
    });
    await write(next);
    if (existing && existing.botToken !== token)
      void call<boolean>(existing.botToken, 'deleteWebhook', { drop_pending_updates: true }).catch(
        () => {},
      );
    return statusOf(next);
  }
  async function createPairing(): Promise<TelegramStatus> {
    const lease = await secrets.acquireLease('telegram-pairing', 15_000);
    if (!lease)
      throw new AppError(
        409,
        'TELEGRAM_BUSY',
        'Подключение Telegram уже обновляется. Повторите попытку.',
      );
    try {
      const config = await read();
      if (!config)
        throw new AppError(409, 'TELEGRAM_NOT_CONFIGURED', 'Сначала настройте Telegram-бота.');
      if (config.account)
        throw new AppError(409, 'TELEGRAM_ALREADY_LINKED', 'Личный чат уже привязан.');
      const next = {
        ...config,
        pending: {
          token: randomBytes(32).toString('base64url'),
          expiresAt: now() + PAIRING_LIFETIME_MS,
        },
      };
      await write(next);
      return statusOf(next);
    } finally {
      await secrets.releaseLease('telegram-pairing', lease);
    }
  }
  async function webhook(secret: string | undefined, input: unknown) {
    const config = await read();
    if (!config || !secret || !equals(secret, config.webhookSecret))
      throw new AppError(403, 'TELEGRAM_WEBHOOK_FORBIDDEN', 'Недопустимый запрос Telegram.');
    const update = updateSchema.parse(input);
    const message = update.message;
    if (
      !message ||
      message.chat.type !== 'private' ||
      message.chat.id !== message.from.id ||
      message.from.is_bot
    )
      return;
    const match = message.text?.match(/^\/start ([A-Za-z0-9_-]{32,64})$/);
    if (!match) return;
    const lease = await secrets.acquireLease('telegram-pairing', 15_000);
    if (!lease) throw new AppError(503, 'TELEGRAM_BUSY', 'Подключение Telegram обрабатывается.');
    try {
      const current = await read();
      if (!current || !equals(secret, current.webhookSecret)) return;
      if (
        !current.pending ||
        current.pending.expiresAt <= now() ||
        !equals(match[1], current.pending.token)
      )
        return;
      await write({
        ...current,
        pending: undefined,
        account: {
          userId: message.from.id,
          chatId: message.chat.id,
          username: message.from.username,
          firstName: message.from.first_name,
        },
      });
    } finally {
      await secrets.releaseLease('telegram-pairing', lease);
    }
  }
  async function disconnect() {
    const config = await read();
    if (config)
      await call<boolean>(config.botToken, 'deleteWebhook', { drop_pending_updates: true }).catch(
        () => {},
      );
    await secrets.removeSecret(CONFIG_NAME);
    return { configured: false, linked: false } satisfies TelegramStatus;
  }
  return { status, configure, createPairing, webhook, disconnect };
}
