import express, { type ErrorRequestHandler } from 'express';
import { createHash, timingSafeEqual } from 'node:crypto';
import { existsSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { z } from 'zod';
import { Store, localDate } from './store.ts';
import { PostgresStore } from './postgres-store.ts';
import {
  createGoogleCalendarService,
  GOOGLE_CALLBACK_PATH,
  GOOGLE_OAUTH_COOKIE,
  googleEventInputSchema,
  googleEventIdSchema,
  googleEtagSchema,
  googleOAuthSetupInputSchema,
  type GoogleCalendarService,
  type GoogleTransport,
} from './google-calendar.ts';
import type { WorkspaceRepository } from './repository.ts';
import { SqliteRuntimeState, type RuntimeState } from './runtime-state.ts';
import { SecretStore } from './secrets.ts';
import { createTelegramService, TELEGRAM_WEBHOOK_PATH } from './telegram.ts';
import { createTelegramReminderRunner } from './telegram-reminders.ts';
import { verifyQstashSignature } from './qstash-signature.ts';
import type { VoiceInterpreter } from './telegram-voice.ts';
import { Security } from './security.ts';
import { AppError, conflict } from './errors.ts';
import {
  localizeError,
  localizeGoogleEvent,
  localizeGoogleResult,
  requestLanguage,
} from './localization.ts';
import {
  apiRequestGuard,
  createSecurityAudit,
  requestIdentity,
  type SecurityLogger,
} from './http-security.ts';
import { assistantMessage, runAssistant, type AssistantRunner } from './assistant.ts';
import {
  buildIdeaDiscussion,
  ideaReviewMessage,
  runIdeaReview,
  type IdeaReviewRunner,
} from './idea-review.ts';
import { createTaskGoogleTransfer } from './task-google-transfer.ts';
import {
  chatSchema,
  dateValue,
  financeEntryInputSchema,
  habitInputSchema,
  idSchema,
  proposalActionSchema,
  secretSchema,
  settingsPatchSchema,
  taskInputSchema,
  taskPatchSchema,
  taskSchema,
} from './validation.ts';

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
type AppGoogleService = Pick<
  GoogleCalendarService,
  | 'status'
  | 'connect'
  | 'callback'
  | 'listEvents'
  | 'createEvent'
  | 'updateEvent'
  | 'deleteEvent'
  | 'connectionIdentity'
  | 'withConnectionIdentity'
  | 'disconnect'
  | 'assertFreeSlots'
  | 'connectionIdentity'
  | 'withConnectionIdentity'
  | 'configuration'
  | 'saveConfiguration'
  | 'removeConfiguration'
> &
  Partial<Pick<GoogleCalendarService, 'completeTask'>>;
export interface AppOptions {
  dataDir?: string;
  clientDir?: string;
  env?: NodeJS.ProcessEnv;
  seed?: boolean;
  assistant?: AssistantRunner;
  ideaReviewer?: IdeaReviewRunner;
  repository?: WorkspaceRepository;
  runtimeState?: RuntimeState;
  googleTransport?: GoogleTransport;
  googleService?: AppGoogleService;
  telegramTransport?: typeof fetch;
  telegramVoiceInterpreter?: VoiceInterpreter;
  securityLogger?: SecurityLogger;
}

export function createApp(options: AppOptions = {}) {
  const env = options.env ?? process.env;
  const shared = Boolean(env.DATABASE_URL) || options.repository instanceof PostgresStore;
  if (env.VERCEL === '1' && !shared && !options.repository)
    throw new Error('DATABASE_URL is required on Vercel. Local SQLite is not durable there.');
  const dataDir = resolve(options.dataDir ?? env.DATA_DIR ?? resolve(projectRoot, 'data'));
  const postgres = shared && !options.repository ? new PostgresStore(env.DATABASE_URL!) : undefined;
  const candidate = options.repository as (WorkspaceRepository & Partial<RuntimeState>) | undefined;
  const repositoryState =
    candidate &&
    [
      'createSession',
      'hasSession',
      'deleteSession',
      'consumeRateLimit',
      'getServerSecret',
      'setServerSecret',
      'deleteServerSecret',
      'consumeServerSecret',
      'acquireLease',
      'releaseLease',
    ].every((name) => typeof (candidate as unknown as Record<string, unknown>)[name] === 'function')
      ? (candidate as RuntimeState)
      : undefined;
  if (shared && options.repository && !options.runtimeState && !repositoryState)
    throw new Error('A shared repository must provide durable runtime state.');
  const localState =
    !options.runtimeState && !postgres && !repositoryState
      ? new SqliteRuntimeState(dataDir)
      : undefined;
  const state: RuntimeState = options.runtimeState ?? postgres ?? repositoryState ?? localState!;
  let security: Security;
  try {
    security = new Security(env, state, dataDir);
  } catch (error) {
    localState?.close();
    void postgres?.close();
    throw error;
  }
  // Constructors never migrate/query PostgreSQL. Migrations are explicit.
  const store: WorkspaceRepository =
    options.repository ?? postgres ?? new Store(dataDir, options.seed ?? env.SEED_DEMO !== 'false');
  const secrets = new SecretStore(dataDir, env, state, shared);
  const google =
    options.googleService ??
    createGoogleCalendarService({
      secrets,
      security,
      settings: async () => await store.settings(),
      env,
      transport: options.googleTransport,
    });
  const telegram = createTelegramService({
    secrets,
    store,
    google,
    origin: env.APP_ORIGIN,
    transport: options.telegramTransport,
    interpretVoice: options.telegramVoiceInterpreter,
    schedulerState: state,
    schedulerConfigured: Boolean(
      (env.QSTASH_CURRENT_SIGNING_KEY && env.QSTASH_NEXT_SIGNING_KEY) ||
      (env.REMINDER_SCHEDULER_SECRET && env.REMINDER_SCHEDULER_SECRET.length >= 32),
    ),
  });
  const runTelegramReminders = createTelegramReminderRunner({ state, telegram, store, google });
  const assistant = options.assistant ?? runAssistant;
  const transferTaskToGoogle = createTaskGoogleTransfer({ store, leases: secrets, google });
  const app = express();
  const audit = createSecurityAudit(
    options.securityLogger ??
      (env.NODE_ENV === 'test' ? () => {} : (record) => console.warn(JSON.stringify(record))),
  );
  app.disable('x-powered-by');
  app.set('trust proxy', false);
  app.use(requestIdentity);
  app.use((_req, res, next) => {
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Referrer-Policy', 'same-origin');
    res.setHeader('X-Frame-Options', 'DENY');
    res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
    res.setHeader('Cross-Origin-Resource-Policy', 'same-origin');
    res.setHeader('X-Permitted-Cross-Domain-Policies', 'none');
    res.setHeader('Permissions-Policy', 'camera=(), microphone=(), geolocation=()');
    if (env.NODE_ENV === 'production' || env.VERCEL === '1')
      res.setHeader(
        'Content-Security-Policy',
        "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self'; object-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",
      );
    if (env.APP_ORIGIN?.startsWith('https://'))
      res.setHeader('Strict-Transport-Security', 'max-age=31536000');
    next();
  });
  app.use('/api', (_req, res, next) => {
    res.setHeader('Cache-Control', 'no-store');
    next();
  });
  app.use('/api', apiRequestGuard, security.originGuard);
  app.use('/api', (req, _res, next) => {
    // The Vercel /api/:path* -> /api rewrite appends its unused capture
    // to query parameters. It is transport metadata only when it matches
    // this exact route. User parameters still pass through strict schemas.
    const route = req.originalUrl.split('?')[0],
      query = req.query;
    if (
      env.VERCEL === '1' &&
      route.startsWith('/api/') &&
      typeof query.path === 'string' &&
      query.path === route.slice('/api/'.length)
    ) {
      const { path: _routingCapture, ...parameters } = query;
      // Express 5 calculates query through a getter; deleting req.query.path
      // would be lost on the next read. Override only this request's value.
      Object.defineProperty(req, 'query', { value: parameters, configurable: true });
    }
    next();
  });
  // Anonymous clients only need these exact routes. Protected requests are
  // authenticated before reading/parsing their body, including unknown routes.
  app.use('/api', (req, res, next) => {
    const path = req.originalUrl.split('?')[0];
    const publicRoute =
      (['GET', 'HEAD'].includes(req.method) && ['/api/health', '/api/session'].includes(path)) ||
      (req.method === 'POST' && path === '/api/login') ||
      (req.method === 'GET' && path === GOOGLE_CALLBACK_PATH) ||
      (req.method === 'POST' &&
        [TELEGRAM_WEBHOOK_PATH, '/api/integrations/telegram/reminders/run'].includes(path));
    if (publicRoute) next();
    else void security.requireAuth(req, res, next);
  });
  const loginJson = express.json({ limit: '4kb', inflate: false });
  const apiJson = express.json({
    limit: '128kb',
    inflate: false,
    verify: (req, _res, body) => {
      if (req.url?.split('?')[0] === '/integrations/telegram/reminders/run')
        (req as typeof req & { rawBody?: Buffer }).rawBody = Buffer.from(body);
    },
  });
  app.use('/api', (req, res, next) => {
    const parser =
      req.method === 'POST' && req.originalUrl.split('?')[0] === '/api/login' ? loginJson : apiJson;
    parser(req, res, next);
  });
  app.get('/api/health', (_req, res) => {
    res.json({ status: 'ok' });
  });
  app.post(TELEGRAM_WEBHOOK_PATH, async (req, res) => {
    await security.limit(req, 'telegram-webhook', 120, 60_000);
    await telegram.webhook(req.get('x-telegram-bot-api-secret-token'), req.body);
    res.json({ ok: true });
  });
  app.post('/api/integrations/telegram/reminders/run', async (req, res) => {
    const expected = env.REMINDER_SCHEDULER_SECRET;
    const supplied = req.get('x-ritm-reminder-secret') ?? '';
    const sharedSecretValid = Boolean(
      expected &&
      expected.length >= 32 &&
      Buffer.byteLength(supplied) === Buffer.byteLength(expected) &&
      timingSafeEqual(Buffer.from(supplied), Buffer.from(expected)),
    );
    const signatureValid = await verifyQstashSignature({
      signature: req.get('upstash-signature') ?? '',
      body: (req as typeof req & { rawBody?: Buffer }).rawBody ?? Buffer.alloc(0),
      url: `${env.APP_ORIGIN?.replace(/\/$/, '')}/api/integrations/telegram/reminders/run`,
      currentKey: env.QSTASH_CURRENT_SIGNING_KEY,
      nextKey: env.QSTASH_NEXT_SIGNING_KEY,
    });
    if (
      req.get('upstash-schedule-id') !== 'ritm-telegram-reminders' ||
      (!sharedSecretValid && !signatureValid)
    )
      throw new AppError(401, 'REMINDER_AUTH_REQUIRED', 'Планировщик не авторизован.');
    res.json(await runTelegramReminders(signatureValid));
  });
  app.get('/api/session', async (req, res) => {
    await security.limit(req, 'public-session', 120, 60_000);
    res.json(await security.session(req));
  });
  app.post('/api/login', async (req, res) => {
    const { login, password } = z
      .object({ login: z.string().trim().min(1).max(100), password: z.string().max(512) })
      .strict()
      .parse(req.body);
    const session = await security.login(req, res, login, password);
    audit(res, 'login_success', 200);
    res.json(session);
  });
  app.post('/api/logout', async (req, res) => {
    const session = await security.logout(req, res);
    audit(res, 'logout', 200);
    res.json(session);
  });
  app.get(GOOGLE_CALLBACK_PATH, async (req, res) => {
    res.setHeader('Referrer-Policy', 'no-referrer');
    try {
      await security.limit(req, 'oauth-callback', 20, 60_000);
      const input = z
        .object({
          state: z.string().max(128),
          code: z.string().max(2048).optional(),
          error: z.string().max(100).optional(),
        })
        .parse(req.query);
      const cookies = req.headers.cookie
        ?.split(';')
        .map((part) => part.trim())
        .filter((part) => part.startsWith(GOOGLE_OAUTH_COOKIE + '='));
      const cookie =
        cookies?.length === 1 ? cookies[0].slice(GOOGLE_OAUTH_COOKIE.length + 1) : undefined;
      await google.callback({ ...input, correlationCookie: cookie });
      audit(res, 'google_connected', 303);
      res.clearCookie(GOOGLE_OAUTH_COOKIE, {
        path: GOOGLE_CALLBACK_PATH,
        httpOnly: true,
        sameSite: 'lax',
        secure: (env.APP_ORIGIN || env.GOOGLE_REDIRECT_URI)?.startsWith('https://') ?? false,
      });
      res.redirect(303, '/?section=settings&google=connected');
    } catch (error) {
      audit(res, 'request_blocked', error instanceof AppError ? error.status : 500);
      res.redirect(
        303,
        '/?section=settings&google=error&code=' +
          encodeURIComponent(error instanceof AppError ? error.code : 'GOOGLE_ERROR'),
      );
    }
  });
  app.use('/api', async (req, _res, next) => {
    try {
      if (!['GET', 'HEAD'].includes(req.method)) await security.limit(req, 'mutation', 120, 60_000);
      else await security.limit(req, 'read', 600, 60_000);
      next();
    } catch (error) {
      next(error);
    }
  });
  app.get('/api/bootstrap', async (_req, res) => {
    res.json(await store.bootstrap(await secrets.status()));
  });
  app.get('/api/integrations/google/status', async (_req, res) => {
    res.json(await google.status());
  });
  app.get('/api/integrations/telegram/status', async (_req, res) => {
    res.json(await telegram.status());
  });
  app.patch('/api/integrations/telegram/reminders', async (req, res) => {
    const input = z
      .object({
        enabled: z.boolean(),
        leadMinutes: z.union([
          z.literal(0),
          z.literal(5),
          z.literal(10),
          z.literal(15),
          z.literal(30),
          z.literal(60),
        ]),
      })
      .strict()
      .parse(req.body);
    res.json(await telegram.saveReminderSettings(input));
  });
  app.post('/api/integrations/telegram/reminders/test', async (_req, res) => {
    await security.limit(_req, 'telegram-reminder-test', 3, 60_000);
    res.json(await telegram.testReminder());
  });
  app.post('/api/integrations/telegram/configuration', async (req, res) => {
    await security.limit(req, 'telegram-configuration', 5, 60_000);
    const { botToken } = z
      .object({ botToken: z.string().max(160) })
      .strict()
      .parse(req.body);
    res.json(await telegram.configure(botToken));
  });
  app.post('/api/integrations/telegram/pairing', async (req, res) => {
    await security.limit(req, 'telegram-pairing', 5, 60_000);
    res.json(await telegram.createPairing());
  });
  app.delete('/api/integrations/telegram/connection', async (req, res) => {
    await security.limit(req, 'telegram-configuration', 5, 60_000);
    res.json(await telegram.disconnect());
  });
  app.get('/api/integrations/google/configuration', async (_req, res) => {
    res.json(await google.configuration());
  });
  app.post('/api/integrations/google/configuration', async (req, res) => {
    const input = googleOAuthSetupInputSchema.parse(req.body);
    await security.limit(req, 'google-configuration', 10, 60_000);
    res.json(await google.saveConfiguration(input));
  });
  app.delete('/api/integrations/google/configuration', async (req, res) => {
    await security.limit(req, 'google-configuration', 10, 60_000);
    res.json(await google.removeConfiguration());
  });
  app.post('/api/integrations/google/connect', async (req, res) => {
    const input = z
      .object({ extendedColors: z.boolean().optional(), tasks: z.boolean().optional() })
      .strict()
      .parse(req.body ?? {});
    await security.limit(req, 'google-connect', 10, 60_000);
    const owner = await security.ownerSession(req);
    if (!owner)
      throw new AppError(401, 'AUTH_REQUIRED', 'Войдите в Ritm перед подключением Google.');
    const connection = await google.connect(owner, input);
    res.cookie(GOOGLE_OAUTH_COOKIE, connection.correlationCookie, {
      httpOnly: true,
      sameSite: 'lax',
      secure: connection.secureCookie,
      path: GOOGLE_CALLBACK_PATH,
      maxAge: Math.max(0, connection.expiresAt - Date.now()),
    });
    res.json({ authorizationUrl: connection.authorizationUrl });
  });
  app.get('/api/integrations/google/events', async (req, res) => {
    const input = z
      .object({ from: dateValue, to: dateValue, timeZone: z.string().max(80).optional() })
      .strict()
      .parse(req.query);
    const settings = await store.settings();
    if (input.timeZone && input.timeZone !== settings.timeZone)
      throw new AppError(400, 'GOOGLE_TIMEZONE', 'Используйте часовой пояс из настроек Ritm.');
    await security.limit(req, 'google-read', 60, 60_000);
    res.json(
      localizeGoogleResult(
        await google.listEvents({ ...input, timeZone: settings.timeZone }),
        requestLanguage(req.get('Accept-Language')),
      ),
    );
  });
  app.post('/api/integrations/google/events', async (req, res) => {
    const { event, requestId } = z
      .object({ event: googleEventInputSchema, requestId: idSchema })
      .strict()
      .parse(req.body);
    await security.limit(req, 'google-write', 20, 60_000);
    res
      .status(201)
      .json(
        localizeGoogleEvent(
          await google.createEvent(event, requestId),
          requestLanguage(req.get('Accept-Language')),
        ),
      );
  });
  app.patch('/api/integrations/google/events/:id', async (req, res) => {
    const { event, etag } = z
      .object({ event: googleEventInputSchema, etag: googleEtagSchema })
      .strict()
      .parse(req.body);
    await security.limit(req, 'google-write', 20, 60_000);
    res.json(
      localizeGoogleEvent(
        await google.updateEvent(googleEventIdSchema.parse(req.params.id), event, etag),
        requestLanguage(req.get('Accept-Language')),
      ),
    );
  });
  app.patch('/api/integrations/google/events/:id/task', async (req, res) => {
    const input = z
      .object({
        etag: googleEtagSchema,
        taskEtag: googleEtagSchema,
        completed: z.boolean(),
        connectionId: z.string().regex(/^[a-f0-9]{64}$/),
      })
      .strict()
      .parse(req.body);
    await security.limit(req, 'google-write', 20, 60_000);
    if (!google.completeTask)
      throw new AppError(503, 'GOOGLE_TASKS_UNAVAILABLE', 'Google Tasks пока недоступен.');
    const result = await google.completeTask(googleEventIdSchema.parse(req.params.id), input);
    res.json({
      ...result,
      event: localizeGoogleEvent(result.event, requestLanguage(req.get('Accept-Language'))),
    });
  });
  app.delete('/api/integrations/google/connection', async (req, res) => {
    await security.limit(req, 'google-connect', 10, 60_000);
    const result = await google.disconnect();
    audit(res, 'google_disconnected', 200);
    res.json(result);
  });
  app.delete('/api/integrations/google/events/:id', async (req, res) => {
    const { etag } = z.object({ etag: googleEtagSchema }).strict().parse(req.body);
    await security.limit(req, 'google-write', 20, 60_000);
    res.json(await google.deleteEvent(googleEventIdSchema.parse(req.params.id), etag));
  });
  app.post('/api/tasks', async (req, res) => {
    res.status(201).json(await store.createTask(taskInputSchema.parse(req.body)));
  });
  app.get('/api/habits', async (_req, res) => {
    res.json({ habits: await store.habits() });
  });
  app.post('/api/habits', async (req, res) => {
    await security.limit(req, 'habit-write', 60, 60_000);
    res.status(201).json({ habit: await store.createHabit(habitInputSchema.parse(req.body)) });
  });
  app.patch('/api/habits/:id', async (req, res) => {
    const id = idSchema.parse(req.params.id);
    const { habit, expectedUpdatedAt } = z
      .object({ habit: habitInputSchema, expectedUpdatedAt: z.iso.datetime() })
      .strict()
      .parse(req.body);
    await security.limit(req, 'habit-write', 60, 60_000);
    res.json({ habit: await store.updateHabit(id, habit, expectedUpdatedAt) });
  });
  app.patch('/api/habits/:id/days/:date', async (req, res) => {
    const id = idSchema.parse(req.params.id);
    const date = dateValue.parse(req.params.date);
    const { completed, expectedUpdatedAt } = z
      .object({ completed: z.boolean(), expectedUpdatedAt: z.iso.datetime() })
      .strict()
      .parse(req.body);
    await security.limit(req, 'habit-write', 60, 60_000);
    res.json({ habit: await store.setHabitDay(id, date, completed, expectedUpdatedAt) });
  });
  app.patch('/api/habits/:id/days/:date/progress', async (req, res) => {
    const id = idSchema.parse(req.params.id);
    const date = dateValue.parse(req.params.date);
    const { count, expectedUpdatedAt } = z
      .object({ count: z.number().int().min(0).max(10_000), expectedUpdatedAt: z.iso.datetime() })
      .strict()
      .parse(req.body);
    await security.limit(req, 'habit-write', 60, 60_000);
    res.json({ habit: await store.setHabitProgress(id, date, count, expectedUpdatedAt) });
  });
  app.delete('/api/habits/:id', async (req, res) => {
    const id = idSchema.parse(req.params.id);
    const { expectedUpdatedAt } = z
      .object({ expectedUpdatedAt: z.iso.datetime() })
      .strict()
      .parse(req.body);
    await security.limit(req, 'habit-write', 60, 60_000);
    await store.deleteHabit(id, expectedUpdatedAt);
    res.json({ deleted: true });
  });
  app.get('/api/finance', async (_req, res) => {
    res.json({ entries: await store.financeEntries() });
  });
  app.post('/api/finance', async (req, res) => {
    const input = financeEntryInputSchema.parse(req.body);
    await security.limit(req, 'finance-write', 60, 60_000);
    res.status(201).json({ entry: await store.createFinanceEntry(input) });
  });
  app.patch('/api/finance/:id', async (req, res) => {
    const id = idSchema.parse(req.params.id);
    const { entry, expectedUpdatedAt } = z
      .object({
        entry: financeEntryInputSchema,
        expectedUpdatedAt: z.iso.datetime(),
      })
      .strict()
      .parse(req.body);
    await security.limit(req, 'finance-write', 60, 60_000);
    res.json({ entry: await store.updateFinanceEntry(id, entry, expectedUpdatedAt) });
  });
  app.delete('/api/finance/:id', async (req, res) => {
    const id = idSchema.parse(req.params.id);
    const { expectedUpdatedAt } = z
      .object({ expectedUpdatedAt: z.iso.datetime() })
      .strict()
      .parse(req.body);
    await security.limit(req, 'finance-write', 60, 60_000);
    await store.deleteFinanceEntry(id, expectedUpdatedAt);
    res.json({ deleted: true });
  });
  app.post('/api/tasks/:id/google', async (req, res) => {
    z.object({}).strict().parse(req.body);
    const id = idSchema.parse(req.params.id);
    await security.limit(req, 'google-write', 20, 60_000);
    const result = await transferTaskToGoogle(id);
    res.json({
      ...result,
      event: localizeGoogleEvent(result.event, requestLanguage(req.get('Accept-Language'))),
    });
  });
  app.patch('/api/tasks/:id', async (req, res) => {
    res.json(
      await store.updateTask(idSchema.parse(req.params.id), taskPatchSchema.parse(req.body)),
    );
  });
  app.delete('/api/tasks/:id', async (req, res) => {
    res.json({ deletedTask: await store.deleteTask(idSchema.parse(req.params.id)) });
  });
  app.post('/api/tasks/restore', async (req, res) => {
    const { task } = z.object({ task: taskSchema }).strict().parse(req.body);
    res.json(await store.restoreTask(task));
  });
  app.patch('/api/settings', async (req, res) => {
    res.json(await store.updateSettings(settingsPatchSchema.parse(req.body)));
  });
  app.post('/api/settings/openai', async (req, res) => {
    await security.limit(req, 'secret', 10, 60_000);
    const status = await secrets.save(secretSchema.parse(req.body));
    audit(res, 'openai_saved', 200);
    res.json(status);
  });
  app.delete('/api/settings/openai', async (_req, res) => {
    const status = await secrets.remove();
    audit(res, 'openai_removed', 200);
    res.json(status);
  });
  app.post('/api/conversations', async (req, res) => {
    z.object({}).strict().parse(req.body);
    res.status(201).json(await store.createConversation());
  });
  const busyConversations = new Set<string>();
  app.delete('/api/conversations/:id', async (req, res) => {
    const id = idSchema.parse(req.params.id);
    if (busyConversations.has(id))
      throw conflict('Дождитесь ответа помощника перед удалением диалога.');
    await store.deleteConversation(id);
    res.json({ deleted: true });
  });
  app.post('/api/chat', async (req, res) => {
    const input = chatSchema.parse(req.body);
    const reviewingIdea = input.mode === 'idea_review';
    const fingerprint = createHash('sha256')
      .update(
        JSON.stringify({
          conversationId: input.conversationId ?? null,
          message: input.message,
          ...(reviewingIdea ? { mode: 'idea_review' } : {}),
          ...(input.reviewMessageId ? { reviewMessageId: input.reviewMessageId } : {}),
        }),
      )
      .digest('hex');
    const existing = await store.request(input.requestId);
    if (existing) {
      if (existing.fingerprint !== fingerprint)
        throw conflict('Этот идентификатор запроса уже использован для другого сообщения.');
      if (existing.status === 'complete' && existing.conversationId) {
        res.json(await store.conversation(existing.conversationId));
        return;
      }
      throw conflict('Помощник уже обрабатывает этот запрос. Дождитесь ответа.');
    }
    const credential = await secrets.credentials();
    if (!credential)
      throw new AppError(
        503,
        'AI_NOT_CONFIGURED',
        'Подключите OpenAI в настройках, чтобы начать разговор.',
      );
    await security.limit(req, 'chat', 10, 60_000);
    if (reviewingIdea) await security.limit(req, 'idea-review', 6, 60_000);
    const conversation = input.conversationId
      ? await store.conversation(input.conversationId)
      : undefined;
    if (input.reviewMessageId)
      buildIdeaDiscussion(conversation!, input.reviewMessageId, input.message);
    if (conversation && conversation.messages.length >= 200)
      throw new AppError(
        400,
        'MESSAGE_LIMIT',
        'В этом диалоге уже 100 запросов. Начните новый диалог.',
      );
    if (input.conversationId && busyConversations.has(input.conversationId))
      throw conflict('В этом диалоге помощник уже отвечает. Дождитесь завершения.');
    const busyId = input.conversationId ?? input.requestId;
    busyConversations.add(busyId);
    const controller = new AbortController();
    const onDisconnect = () => {
      if (!res.writableEnded) controller.abort();
    };
    res.on('close', onDisconnect);
    const modelSlots: { key: string; token: string }[] = [];
    let discussionLease: { key: string; token: string } | undefined;
    let leaseToken: string | undefined,
      acquired = false;
    try {
      const snapshot = await store.tasks(),
        settings = await store.settings();
      const googleStatus = reviewingIdea ? undefined : await google.status();
      const today = localDate(new Date(), settings.timeZone),
        until = new Date(today + 'T12:00:00Z');
      until.setUTCDate(until.getUTCDate() + 14);
      const googleCalendar =
        googleStatus?.status === 'connected'
          ? await google.listEvents({
              from: today,
              to: until.toISOString().slice(0, 10),
              timeZone: settings.timeZone,
            })
          : undefined;
      if (controller.signal.aborted)
        throw new AppError(499, 'REQUEST_CANCELLED', 'Запрос отменён.');
      // One owner may use multiple conversations and server instances. Bound
      // paid generations across them, independently of per-minute quotas.
      for (let slot = 0; slot < 2; slot++) {
        const key = 'ritm:ai:slot:' + slot;
        const token = await state.acquireLease(key, 180_000);
        if (token) {
          modelSlots.push({ key, token });
          if (!reviewingIdea) break;
        }
      }
      if (modelSlots.length < (reviewingIdea ? 2 : 1))
        throw new AppError(429, 'AI_BUSY', 'Помощник уже отвечает. Дождитесь завершения ответа.');
      if (reviewingIdea && input.conversationId) {
        const key = 'ritm:idea-discussion:' + input.conversationId;
        const token = await state.acquireLease(key, 180_000);
        if (!token) throw conflict('В этом диалоге помощник уже отвечает. Дождитесь завершения.');
        discussionLease = { key, token };
      }
      // Reserve the paid model generation after read-only calendar loading, so
      // Google latency does not consume the database claim lease.
      const claim = await store.startRequest(
        input.requestId,
        fingerprint,
        input.conversationId ?? null,
      );
      if (claim?.completedConversationId) {
        res.json(await store.conversation(claim.completedConversationId));
        return;
      }
      leaseToken = claim?.leaseToken;
      acquired = true;
      const freshConversation = input.conversationId
        ? await store.conversation(input.conversationId)
        : undefined;
      const discussion = input.reviewMessageId
        ? buildIdeaDiscussion(freshConversation!, input.reviewMessageId, input.message)
        : undefined;
      const message = reviewingIdea
        ? ideaReviewMessage(
            await (options.ideaReviewer ?? runIdeaReview)({
              ...credential,
              message: input.message,
              language: settings.language,
              signal: controller.signal,
              ...(discussion ? { discussion } : {}),
            }),
            discussion,
          )
        : assistantMessage(
            await assistant({
              ...credential,
              settings,
              tasks: snapshot,
              conversation: freshConversation,
              message: input.message,
              signal: controller.signal,
              googleCalendar,
              googleCalendarStatus: googleStatus!.status,
            }),
            snapshot,
            settings.timeZone,
          );
      if (controller.signal.aborted)
        throw new AppError(499, 'REQUEST_CANCELLED', 'Запрос отменён.');
      if (input.reviewMessageId)
        buildIdeaDiscussion(
          await store.conversation(input.conversationId!),
          input.reviewMessageId,
          input.message,
        );
      res.json(
        await store.finishChat(
          input.requestId,
          input.conversationId,
          input.message,
          message,
          leaseToken,
        ),
      );
    } catch (error) {
      if (acquired) await store.abandonRequest(input.requestId, leaseToken);
      throw error;
    } finally {
      busyConversations.delete(busyId);
      if (discussionLease) {
        try {
          await state.releaseLease(discussionLease.key, discussionLease.token);
        } catch {
          audit(res, 'server_error', 503);
        }
      }
      res.off('close', onDisconnect);
      for (const modelSlot of modelSlots) {
        try {
          await state.releaseLease(modelSlot.key, modelSlot.token);
        } catch {
          // A crashed/unavailable database cannot free capacity early; the
          // durable lease expires automatically, without exposing its token.
          audit(res, 'server_error', 503);
        }
      }
    }
  });
  for (const action of ['apply', 'undo', 'reject'] as const)
    app.post('/api/proposals/' + action, async (req, res) => {
      const { conversationId, messageId, proposalIds } = proposalActionSchema.parse(req.body);
      if (action === 'apply') {
        const conversation = await store.conversation(conversationId);
        const message = conversation.messages.find(
          (item) => item.id === messageId && item.role === 'assistant',
        );
        const selected = proposalIds.map((id) =>
          message?.proposals.find((proposal) => proposal.id === id),
        );
        if (selected.some((proposal) => !proposal || proposal.status !== 'pending'))
          throw conflict('Предложение уже обработано или удалено. Обновите диалог.');
        await google.assertFreeSlots(
          selected.map((proposal) => ({ ...proposal!.after, title: proposal!.title })),
          (await store.settings()).timeZone,
        );
      }
      const result = await store.proposalAction(action, conversationId, messageId, proposalIds);
      res.json(action === 'reject' ? result.conversation : result);
    });
  app.use('/api', (_req, _res, next) => {
    next(new AppError(404, 'NOT_FOUND', 'Этот запрос не найден.'));
  });
  const clientDir = resolve(options.clientDir ?? resolve(projectRoot, 'build/client'));
  if (existsSync(resolve(clientDir, 'index.html'))) {
    app.use(express.static(clientDir, { index: false, dotfiles: 'deny' }));
    app.get('/{*path}', (_req, res) => {
      res.sendFile(resolve(clientDir, 'index.html'));
    });
  }
  const errorHandler: ErrorRequestHandler = (error, req, res, _next) => {
    if (res.headersSent) return;
    const language = requestLanguage(req.get('Accept-Language'));
    if (error instanceof AppError && [401, 403, 405, 413, 414, 415, 429].includes(error.status))
      audit(res, 'request_blocked', error.status);
    else if (error?.type === 'entity.too.large') audit(res, 'request_blocked', 413);
    else if (['encoding.unsupported', 'charset.unsupported'].includes(error?.type))
      audit(res, 'request_blocked', 415);
    else if (!(
      error instanceof AppError ||
      error instanceof z.ZodError ||
      error instanceof SyntaxError
    ))
      audit(res, 'server_error', 500);
    if (error instanceof AppError) {
      const retryAfterSeconds =
        error.status === 429 &&
        Number.isInteger(error.retryAfterSeconds) &&
        error.retryAfterSeconds! > 0 &&
        error.retryAfterSeconds! <= 3600
          ? error.retryAfterSeconds
          : undefined;
      if (retryAfterSeconds !== undefined) res.setHeader('Retry-After', String(retryAfterSeconds));
      res.status(error.status).json({
        error: localizeError(error.message, error.code, language),
        code: error.code,
        ...(retryAfterSeconds === undefined ? {} : { retryAfterSeconds }),
      });
      return;
    }
    if (error instanceof z.ZodError) {
      const path = req.originalUrl.split('?')[0];
      const message =
        path === '/api/settings/openai'
          ? 'Проверьте ключ OpenAI (начинается с sk-) и название модели.'
          : path === '/api/integrations/google/configuration'
            ? 'Введите Client ID Google и Client Secret без пробелов. Callback URL задаётся сервером.'
            : path === '/api/settings'
              ? 'Проверьте имя, почту, часовой пояс и время рабочего дня.'
              : path === '/api/login'
                ? 'Введите логин и пароль приложения.'
                : path.startsWith('/api/finance')
                  ? 'Проверьте сумму, валюту, дату и описание финансовой записи.'
                  : path.startsWith('/api/habits')
                    ? 'Проверьте название привычки и выбранную дату.'
                    : path === '/api/chat'
                      ? 'Введите сообщение длиной до 6000 символов.'
                      : path.startsWith('/api/proposals/')
                        ? 'Не удалось выбрать изменения. Обновите диалог и повторите.'
                        : 'Проверьте заполненные поля: название, дату, время и длительность.';
      res.status(400).json({
        error: localizeError(message, 'VALIDATION_ERROR', language),
        code: 'VALIDATION_ERROR',
      });
      return;
    }
    if (error?.type === 'entity.too.large') {
      res.status(413).json({
        error: localizeError(
          'Запрос слишком большой. Сократите текст.',
          'REQUEST_TOO_LARGE',
          language,
        ),
        code: 'REQUEST_TOO_LARGE',
      });
      return;
    }
    if (['encoding.unsupported', 'charset.unsupported'].includes(error?.type)) {
      res.status(415).json({
        error: localizeError('Отправьте JSON в UTF-8 без сжатия.', 'INVALID_ENCODING', language),
        code: 'INVALID_ENCODING',
      });
      return;
    }
    if (error instanceof SyntaxError && 'body' in error) {
      res.status(400).json({
        error: localizeError(
          'Не удалось прочитать запрос. Попробуйте снова.',
          'INVALID_JSON',
          language,
        ),
        code: 'INVALID_JSON',
      });
      return;
    }
    res.status(500).json({
      error: localizeError(
        'Не удалось выполнить действие. Ваши сохранённые данные доступны после обновления страницы.',
        'SERVER_ERROR',
        language,
      ),
      code: 'SERVER_ERROR',
    });
  };
  app.use(errorHandler);
  return {
    app,
    store,
    secrets,
    security,
    google,
    close: async () => {
      await store.close();
      localState?.close();
    },
  };
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  if (Number(process.versions.node.split('.')[0]) < 24)
    throw new Error('Для Ritm нужен Node.js 24 или новее. Версия указана в .nvmrc.');
  if (existsSync(resolve(projectRoot, '.env'))) process.loadEnvFile(resolve(projectRoot, '.env'));
  const port = Number(process.env.PORT || '3001');
  if (!Number.isInteger(port) || port < 1 || port > 65535)
    throw new Error('PORT must be between 1 and 65535.');
  const instance = createApp();
  const server = instance.app.listen(port, process.env.HOST || '127.0.0.1', () => {
    console.log('Ritm server ready on port ' + port + '.');
  });
  server.headersTimeout = 15_000;
  server.requestTimeout = 30_000;
  server.keepAliveTimeout = 5_000;
  server.maxRequestsPerSocket = 100;
  const shutdown = () => {
    server.close(() => {
      void instance.close().then(() => process.exit(0));
    });
  };
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}
