import express, { type ErrorRequestHandler } from 'express';
import { createHash } from 'node:crypto';
import { existsSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { z } from 'zod';
import { Store } from './store.ts';
import { SecretStore } from './secrets.ts';
import { Security } from './security.ts';
import { AppError, conflict } from './errors.ts';
import { assistantMessage, runAssistant, type AssistantRunner } from './assistant.ts';
import {
  chatSchema,
  idSchema,
  proposalActionSchema,
  secretSchema,
  settingsPatchSchema,
  taskInputSchema,
  taskPatchSchema,
  taskSchema,
} from './validation.ts';

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
export interface AppOptions {
  dataDir?: string;
  clientDir?: string;
  env?: NodeJS.ProcessEnv;
  seed?: boolean;
  assistant?: AssistantRunner;
}

export function createApp(options: AppOptions = {}) {
  const env = options.env ?? process.env;
  const security = new Security(env);
  const dataDir = resolve(options.dataDir ?? env.DATA_DIR ?? resolve(projectRoot, 'data'));
  const store = new Store(dataDir, options.seed ?? env.SEED_DEMO !== 'false');
  const secrets = new SecretStore(dataDir, env);
  const assistant = options.assistant ?? runAssistant;
  const app = express();
  app.disable('x-powered-by');
  app.set('trust proxy', false);
  app.use((_req, res, next) => {
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Referrer-Policy', 'same-origin');
    res.setHeader('X-Frame-Options', 'DENY');
    res.setHeader('Permissions-Policy', 'camera=(), microphone=(), geolocation=()');
    if (env.NODE_ENV === 'production') {
      res.setHeader(
        'Content-Security-Policy',
        "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'",
      );
    }
    next();
  });
  app.use('/api', security.originGuard, express.json({ limit: '128kb' }));
  app.use('/api', (_req, res, next) => {
    res.setHeader('Cache-Control', 'no-store');
    next();
  });
  app.get('/api/session', (req, res) => {
    res.json(security.session(req));
  });
  app.get('/api/health', (_req, res) => {
    res.json({ status: 'ok' });
  });
  app.post('/api/login', (req, res) => {
    const { password } = z
      .object({ password: z.string().max(512) })
      .strict()
      .parse(req.body);
    res.json(security.login(req, res, password));
  });
  app.post('/api/logout', (req, res) => {
    res.json(security.logout(req, res));
  });
  app.use('/api', security.requireAuth);
  app.use('/api', (req, _res, next) => {
    try {
      if (!['GET', 'HEAD'].includes(req.method)) security.limit(req, 'mutation', 120, 60_000);
      next();
    } catch (error) {
      next(error);
    }
  });
  app.get('/api/bootstrap', (_req, res) => {
    res.json(store.bootstrap(secrets.status()));
  });
  app.post('/api/tasks', (req, res) => {
    res.status(201).json(store.createTask(taskInputSchema.parse(req.body)));
  });
  app.patch('/api/tasks/:id', (req, res) => {
    res.json(store.updateTask(idSchema.parse(req.params.id), taskPatchSchema.parse(req.body)));
  });
  app.delete('/api/tasks/:id', (req, res) => {
    res.json({ deletedTask: store.deleteTask(idSchema.parse(req.params.id)) });
  });
  app.post('/api/tasks/restore', (req, res) => {
    const { task } = z.object({ task: taskSchema }).strict().parse(req.body);
    res.json(store.restoreTask(task));
  });
  app.patch('/api/settings', (req, res) => {
    res.json(store.updateSettings(settingsPatchSchema.parse(req.body)));
  });
  app.post('/api/settings/openai', (req, res) => {
    security.limit(req, 'secret', 10, 60_000);
    res.json(secrets.save(secretSchema.parse(req.body)));
  });
  app.delete('/api/settings/openai', (req, res) => {
    res.json(secrets.remove());
  });
  app.post('/api/conversations', (req, res) => {
    z.object({}).strict().parse(req.body);
    res.status(201).json(store.createConversation());
  });
  const busyConversations = new Set<string>();
  app.delete('/api/conversations/:id', (req, res) => {
    const id = idSchema.parse(req.params.id);
    if (busyConversations.has(id))
      throw conflict('Дождитесь ответа помощника перед удалением диалога.');
    store.deleteConversation(id);
    res.json({ deleted: true });
  });
  app.post('/api/chat', async (req, res) => {
    const input = chatSchema.parse(req.body);
    const fingerprint = createHash('sha256')
      .update(
        JSON.stringify({ conversationId: input.conversationId ?? null, message: input.message }),
      )
      .digest('hex');
    const existing = store.request(input.requestId);
    if (existing) {
      if (existing.fingerprint !== fingerprint)
        throw conflict('Этот идентификатор запроса уже использован для другого сообщения.');
      if (existing.status === 'complete' && existing.conversationId) {
        res.json(store.conversation(existing.conversationId));
        return;
      }
      throw conflict('Помощник уже обрабатывает этот запрос. Дождитесь ответа.');
    }
    const credential = secrets.credentials();
    if (!credential)
      throw new AppError(
        503,
        'AI_NOT_CONFIGURED',
        'Подключите OpenAI в настройках, чтобы начать разговор.',
      );
    security.limit(req, 'chat', 10, 60_000);
    const conversation = input.conversationId
      ? store.conversation(input.conversationId)
      : undefined;
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
    try {
      store.startRequest(input.requestId, fingerprint, input.conversationId ?? null);
      const snapshot = store.tasks();
      const reply = await assistant({
        ...credential,
        settings: store.settings(),
        tasks: snapshot,
        conversation,
        message: input.message,
        signal: controller.signal,
      });
      if (controller.signal.aborted)
        throw new AppError(499, 'REQUEST_CANCELLED', 'Запрос отменён.');
      const message = assistantMessage(reply, snapshot, store.settings().timeZone);
      res.json(store.finishChat(input.requestId, input.conversationId, input.message, message));
    } catch (error) {
      store.abandonRequest(input.requestId);
      throw error;
    } finally {
      busyConversations.delete(busyId);
      res.off('close', onDisconnect);
    }
  });
  for (const action of ['apply', 'undo', 'reject'] as const) {
    app.post(`/api/proposals/${action}`, (req, res) => {
      const { conversationId, messageId, proposalIds } = proposalActionSchema.parse(req.body);
      const result = store.proposalAction(action, conversationId, messageId, proposalIds);
      res.json(action === 'reject' ? result.conversation : result);
    });
  }
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
    if (error instanceof AppError) {
      res.status(error.status).json({ error: error.message, code: error.code });
      return;
    }
    if (error instanceof z.ZodError) {
      const path = req.originalUrl.split('?')[0];
      const message =
        path === '/api/settings/openai'
          ? 'Проверьте ключ OpenAI (начинается с sk-) и название модели.'
          : path === '/api/settings'
            ? 'Проверьте имя, почту, часовой пояс и время рабочего дня.'
            : path === '/api/login'
              ? 'Введите пароль приложения.'
              : path === '/api/chat'
                ? 'Введите сообщение длиной до 6000 символов.'
                : path.startsWith('/api/proposals/')
                  ? 'Не удалось выбрать изменения. Обновите диалог и повторите.'
                  : 'Проверьте заполненные поля: название, дату, время и длительность.';
      res.status(400).json({ error: message, code: 'VALIDATION_ERROR' });
      return;
    }
    if (error?.type === 'entity.too.large') {
      res
        .status(413)
        .json({ error: 'Запрос слишком большой. Сократите текст.', code: 'REQUEST_TOO_LARGE' });
      return;
    }
    if (error instanceof SyntaxError && 'body' in error) {
      res
        .status(400)
        .json({ error: 'Не удалось прочитать запрос. Попробуйте снова.', code: 'INVALID_JSON' });
      return;
    }
    res.status(500).json({
      error:
        'Не удалось выполнить действие. Ваши сохранённые данные доступны после обновления страницы.',
      code: 'SERVER_ERROR',
    });
  };
  app.use(errorHandler);
  return { app, store, close: () => store.close() };
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
    console.log(`Ritm server ready on port ${port}.`);
  });
  const shutdown = () => {
    server.close(() => {
      instance.close();
      process.exit(0);
    });
  };
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}
