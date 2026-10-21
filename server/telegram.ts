import { randomBytes, timingSafeEqual } from 'node:crypto';
import { z } from 'zod';
import { AppError } from './errors.ts';
import type { TelegramStatus } from '../shared/types.ts';
import type { SecretStore } from './secrets.ts';
import type { WorkspaceRepository } from './repository.ts';

export const TELEGRAM_WEBHOOK_PATH = '/api/integrations/telegram/webhook';
const CONFIG_NAME = 'telegram-connection';
const PAIRING_LIFETIME_MS = 10 * 60_000;
const WEBHOOK_VERSION = 2;
const MENU_RU = {
  keyboard: [
    [{ text: '➕ Добавить дело' }, { text: '📋 План на сегодня' }],
    [{ text: '🌙 Итог дня' }, { text: '🔔 Напоминания' }],
  ],
  resize_keyboard: true,
  is_persistent: true,
};
const MENU_EN = {
  ...MENU_RU,
  keyboard: [
    [{ text: '➕ Add task' }, { text: '📋 Today' }],
    [{ text: '🌙 Daily summary' }, { text: '🔔 Reminders' }],
  ],
};
const botTokenSchema = z
  .string()
  .trim()
  .regex(/^\d{6,16}:[A-Za-z0-9_-]{20,128}$/);
const configurationSchema = z.object({
  botToken: botTokenSchema,
  botUsername: z.string().regex(/^[A-Za-z0-9_]{5,32}$/),
  webhookSecret: z.string().regex(/^[A-Za-z0-9_-]{32,128}$/),
  webhookVersion: z.number().int().optional(),
  pending: z.object({ token: z.string(), expiresAt: z.number() }).optional(),
  draft: z
    .object({ title: z.string(), date: z.string(), token: z.string(), expiresAt: z.number() })
    .optional(),
  awaitingTask: z.boolean().optional(),
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
  callback_query: z
    .object({
      id: z.string().max(256),
      from: z.object({ id: z.number().int(), is_bot: z.boolean().optional() }),
      data: z.string().max(128).optional(),
      message: z.object({ chat: z.object({ id: z.number().int(), type: z.string() }) }).optional(),
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
  store,
}: {
  secrets: SecretStore;
  origin?: string;
  transport?: typeof fetch;
  now?: () => number;
  store?: WorkspaceRepository;
}) {
  async function english() {
    return (await store?.settings())?.language === 'en';
  }
  async function phrase(ru: string, en: string) {
    return (await english()) ? en : ru;
  }
  async function send(config: Configuration, text: string, reply_markup?: object) {
    await call(config.botToken, 'sendMessage', {
      chat_id: config.account!.chatId,
      text,
      reply_markup: reply_markup ?? ((await english()) ? MENU_EN : MENU_RU),
      link_preview_options: { is_disabled: true },
    });
  }
  function localDay(timeZone: string, offset = 0) {
    const date = new Date(now());
    const parts = new Intl.DateTimeFormat('en', {
      timeZone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).formatToParts(date);
    const value = (type: string) => parts.find((part) => part.type === type)!.value;
    const today = `${value('year')}-${value('month')}-${value('day')}`;
    if (!offset) return today;
    return new Date(Date.parse(`${today}T00:00:00Z`) + offset * 86_400_000)
      .toISOString()
      .slice(0, 10);
  }
  async function dayReport(config: Configuration, summary: boolean) {
    if (!store) return;
    const settings = await store.settings();
    const today = localDay(settings.timeZone);
    const tasks = (await store.tasks()).filter(
      (task) => task.date === today && task.calendarEntry === false,
    );
    const done = tasks.filter((task) => task.completed);
    const pending = tasks.filter((task) => !task.completed);
    const en = await english();
    const list = (items: typeof tasks) =>
      items.length
        ? items
            .slice(0, 20)
            .map((task) => `• ${task.title}`)
            .join('\n')
        : en
          ? 'None'
          : 'Нет';
    await send(
      config,
      summary
        ? en
          ? `Daily summary · ${today}\n\nCompleted (${done.length}):\n${list(done)}\n\nRemaining (${pending.length}):\n${list(pending)}`
          : `Итог дня · ${today}\n\nВыполнено (${done.length}):\n${list(done)}\n\nОсталось (${pending.length}):\n${list(pending)}`
        : en
          ? `Today · ${today}\n\nQuick tasks (${pending.length}):\n${list(pending)}\n\nOpen Ritm to see your Google Calendar schedule.`
          : `План на сегодня · ${today}\n\nБыстрые дела (${pending.length}):\n${list(pending)}\n\nОткрой Ritm, чтобы увидеть расписание Google Calendar.`,
    );
  }
  async function handleTaskText(config: Configuration, raw: string) {
    if (!store) return;
    const settings = await store.settings();
    const tomorrow = /(?:^|\s)(?:завтра|tomorrow)\s*$/i.test(raw);
    const title = raw.replace(/(?:^|\s)(?:завтра|tomorrow)\s*$/i, '').trim();
    if (!title || title.length > 160) {
      await send(
        config,
        await phrase(
          'Напиши название дела до 160 символов. Например: Купить лекарства завтра',
          'Write a task title up to 160 characters. For example: Buy medicine tomorrow',
        ),
      );
      return;
    }
    const date = localDay(settings.timeZone, tomorrow ? 1 : 0);
    const token = randomBytes(16).toString('base64url');
    await write({
      ...config,
      awaitingTask: false,
      draft: { title, date, token, expiresAt: now() + 10 * 60_000 },
    });
    await send(
      config,
      (await english())
        ? `Save to My Day?\n${title}\nDate: ${date}`
        : `Сохранить дело в «Мой день»?\n${title}\nДата: ${date}`,
      {
        inline_keyboard: [
          [
            { text: await phrase('✅ Сохранить', '✅ Save'), callback_data: `save:${token}` },
            { text: await phrase('Отмена', 'Cancel'), callback_data: `cancel:${token}` },
          ],
        ],
      },
    );
  }
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
  async function ensureWebhook(config: Configuration | null): Promise<Configuration | null> {
    if (!config || config.webhookVersion === WEBHOOK_VERSION) return config;
    if (!origin || !origin.startsWith('https://'))
      throw new AppError(
        503,
        'TELEGRAM_ORIGIN_REQUIRED',
        'Для Telegram нужен публичный HTTPS-адрес Ritm.',
      );
    const lease = await secrets.acquireLease('telegram-pairing', 15_000);
    if (!lease) return config;
    try {
      const latest = await read();
      if (!latest || latest.webhookVersion === WEBHOOK_VERSION) return latest;
      await call<boolean>(latest.botToken, 'setWebhook', {
        url: origin + TELEGRAM_WEBHOOK_PATH,
        secret_token: latest.webhookSecret,
        allowed_updates: ['message', 'callback_query'],
        drop_pending_updates: false,
        max_connections: 1,
      });
      const next = { ...latest, webhookVersion: WEBHOOK_VERSION };
      await write(next);
      return next;
    } finally {
      await secrets.releaseLease('telegram-pairing', lease);
    }
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
    return statusOf(await ensureWebhook(await read()));
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
      webhookVersion: WEBHOOK_VERSION,
      ...(existing?.botToken === token && existing.account ? { account: existing.account } : {}),
    };
    await call<boolean>(token, 'setWebhook', {
      url: origin + TELEGRAM_WEBHOOK_PATH,
      secret_token: next.webhookSecret,
      allowed_updates: ['message', 'callback_query'],
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
    let config = await read();
    if (!config || !secret || !equals(secret, config.webhookSecret))
      throw new AppError(403, 'TELEGRAM_WEBHOOK_FORBIDDEN', 'Недопустимый запрос Telegram.');
    if (config.webhookVersion !== WEBHOOK_VERSION) {
      config = await ensureWebhook(config);
      if (!config || !equals(secret, config.webhookSecret)) return;
    }
    const update = updateSchema.parse(input);
    const callback = update.callback_query;
    if (callback) {
      if (
        !config.account ||
        !callback.message ||
        callback.message.chat.type !== 'private' ||
        callback.message.chat.id !== config.account.chatId ||
        callback.from.id !== config.account.userId ||
        callback.from.is_bot
      )
        return;
      const lease = await secrets.acquireLease('telegram-pairing', 15_000);
      if (!lease)
        throw new AppError(503, 'TELEGRAM_BUSY', 'Telegram обрабатывает предыдущий запрос.');
      try {
        const current = await read();
        const draft = current?.draft;
        if (!current?.account) return;
        if (!draft || draft.expiresAt <= now()) {
          if (draft) await write({ ...current, draft: undefined });
          await call(current.botToken, 'answerCallbackQuery', {
            callback_query_id: callback.id,
            text: await phrase(
              'Подтверждение устарело. Добавь дело заново.',
              'This confirmation expired. Add the task again.',
            ),
            show_alert: true,
          });
          return;
        }
        if (callback.data === `cancel:${draft.token}`) {
          await call(current.botToken, 'answerCallbackQuery', { callback_query_id: callback.id });
          await write({ ...current, draft: undefined });
          await send(current, await phrase('Дело не сохранено.', 'Task was not saved.'));
        } else if (callback.data === `save:${draft.token}` && store) {
          await call(current.botToken, 'answerCallbackQuery', { callback_query_id: callback.id });
          await write({ ...current, draft: undefined });
          try {
            await store.createTask({
              title: draft.title,
              description: '',
              date: draft.date,
              time: null,
              duration: 30,
              priority: 'normal',
              repeat: 'none',
              kind: 'task',
              completed: false,
              calendarEntry: false,
            });
          } catch {
            await write({ ...current, draft });
            await send(
              current,
              await phrase(
                'Не удалось сохранить дело. Проверь Ritm и нажми «Сохранить» ещё раз.',
                'Could not save the task. Check Ritm and tap Save again.',
              ),
            );
            return;
          }
          await send(
            current,
            (await english())
              ? `Saved to My Day for ${draft.date}: ${draft.title}`
              : `Сохранено в «Мой день» на ${draft.date}: ${draft.title}`,
          );
        } else {
          await call(current.botToken, 'answerCallbackQuery', {
            callback_query_id: callback.id,
            text: await phrase(
              'Это подтверждение уже неактуально.',
              'This confirmation is no longer active.',
            ),
          });
        }
      } finally {
        await secrets.releaseLease('telegram-pairing', lease);
      }
      return;
    }
    const message = update.message;
    if (
      !message ||
      message.chat.type !== 'private' ||
      message.chat.id !== message.from.id ||
      message.from.is_bot
    )
      return;
    const match = message.text?.match(/^\/start ([A-Za-z0-9_-]{32,64})$/);
    if (!match) {
      if (
        !config.account ||
        message.chat.id !== config.account.chatId ||
        message.from.id !== config.account.userId
      )
        return;
      const text = message.text?.trim() ?? '';
      if (text === '/start' || text === '/menu' || text === 'Меню') {
        await send(
          config,
          await phrase(
            'Ritm готов. Выбери действие на клавиатуре ниже.',
            'Ritm is ready. Choose an action below.',
          ),
        );
      } else if (['➕ Добавить дело', '➕ Add task', '/add'].includes(text)) {
        await write({ ...config, awaitingTask: true, draft: undefined });
        await send(
          config,
          await phrase(
            'Напиши дело одним сообщением. Для завтра добавь слово «завтра» в конце.',
            'Write a task in one message. Add “tomorrow” at the end for tomorrow.',
          ),
        );
      } else if (text.startsWith('/add ')) {
        await handleTaskText(config, text.slice(5));
      } else if (['🌙 Итог дня', '🌙 Daily summary', '/summary'].includes(text)) {
        await dayReport(config, true);
      } else if (['📋 План на сегодня', '📋 Today', '/today'].includes(text)) {
        await dayReport(config, false);
      } else if (['🔔 Напоминания', '🔔 Reminders', '/reminders'].includes(text)) {
        await send(
          config,
          await phrase(
            'Автоматические сообщения пока не включены. На текущем Vercel Hobby запуск бывает не чаще раза в день и может задержаться до часа. Для напоминаний перед событиями нужен отдельный планировщик.',
            'Automatic messages are not enabled yet. Vercel Hobby runs scheduled jobs at most daily, with up to an hour of delay. Event reminders need another scheduler.',
          ),
        );
      } else if (config.awaitingTask && text && !text.startsWith('/')) {
        await handleTaskText(config, text);
      } else if (text) {
        await send(
          config,
          await phrase(
            'Выбери действие на клавиатуре или напиши /menu.',
            'Choose an action below or type /menu.',
          ),
        );
      }
      return;
    }
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
      await send(
        {
          ...current,
          account: {
            userId: message.from.id,
            chatId: message.chat.id,
            username: message.from.username,
            firstName: message.from.first_name,
          },
        },
        await phrase(
          'Чат подключён к Ritm. Выбери действие на клавиатуре ниже.',
          'Chat linked to Ritm. Choose an action below.',
        ),
      );
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
