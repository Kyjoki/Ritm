import './clock.mjs';
import { build } from 'vite';
import react from '@vitejs/plugin-react';
import express from 'express';
import { mkdtempSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve, join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { createApp } from '../../server/index.ts';
const variant = process.argv[2] || 'after';
if (!['before', 'after', 'stress'].includes(variant))
  throw new Error('Use before, after or stress');
const root = process.cwd();
const port = variant === 'before' ? 4180 : variant === 'stress' ? 4182 : 4181;
const dataDir = mkdtempSync(join(tmpdir(), 'ritm-visual-preview-perf-'));
const env = {
  PATH: process.env.PATH,
  SystemRoot: process.env.SystemRoot,
  TEMP: process.env.TEMP,
  TMP: process.env.TMP,
  NODE_ENV: 'development',
  DATA_DIR: dataDir,
  SEED_DEMO: 'true',
  HOST: '127.0.0.1',
  PORT: String(port),
  APP_ORIGIN: `http://127.0.0.1:${port}`,
};
const seed = spawnSync(
  process.execPath,
  [
    '--import',
    './scripts/performance/clock.mjs',
    '--import',
    'tsx',
    'scripts/seed-visual-preview.ts',
  ],
  {
    env,
    stdio: 'inherit',
  },
);
if (seed.status !== 0) throw new Error('Seed failed');
const outDir = resolve(root, `build/perf-${variant === 'stress' ? 'after' : variant}`);
if (variant === 'before' && !process.argv.includes('--no-build'))
  throw new Error(
    'Baseline is immutable. Restart it with before --no-build; capture a new baseline only from the original checkout.',
  );
if (!process.argv.includes('--no-build'))
  await build({
    configFile: false,
    envDir: dataDir,
    root,
    plugins: [react()],
    build: { outDir, emptyOutDir: true },
  });
const instance = createApp({ env, dataDir, clientDir: outDir });
if (variant === 'stress') {
  const { id, createdAt, updatedAt, completedDates, ...sample } = (await instance.store.tasks())[0];
  for (let i = 0; i < 100; i++)
    await instance.store.createTask({
      ...sample,
      title: `Демонстрационная задача ${i + 1}`,
      date: '2026-10-27',
      time: null,
      repeat: 'none',
      completed: false,
      calendarEntry: false,
    });
  const conversation = await instance.store.createConversation();
  conversation.title = 'Локальная проверка длинной переписки';
  conversation.messages = Array.from({ length: 80 }, (_, i) => ({
    id: `stress-message-${i}`,
    steps: [],
    role: i % 2 ? ('assistant' as const) : ('user' as const),
    text: `Сообщение ${i + 1}. Это локальный пример истории. Проверяем плавность прокрутки и сохранение позиции при переходе между разделами.`,
    createdAt: new Date(Date.now() + i).toISOString(),
    proposals: [],
  }));
  await instance.store.saveConversation(conversation);
}
const app = express();
// Synthetic Google-shaped fixtures; no OAuth grant or external request is used.
// Existing demo tasks remain local, preventing automatic transfers to a real provider.
for (const task of await instance.store.tasks())
  if (task.date) await instance.store.updateTask(task.id, { calendarEntry: false });
const fixtureEvents = Array.from({ length: 28 }, (_, i) => {
  const date = `2026-10-${25 + Math.floor(i / 4)}`;
  const hour = [9, 11, 11, 16][i % 4];
  const duration = [60, 120, 30, 90][i % 4];
  const start = new Date(`${date}T${String(hour).padStart(2, '0')}:00:00+05:00`);
  return {
    id: `perf-event-${i}`,
    source: 'google',
    calendarId: 'primary',
    title: ['Работа над проектом — длинное название события', 'Учёба', 'Короткая встреча', 'Gym'][
      i % 4
    ],
    description: 'Локальные демонстрационные данные, не настоящий Google Calendar.',
    etag: `"perf-${i}"`,
    start: { dateTime: start.toISOString() },
    end: { dateTime: new Date(start.getTime() + duration * 60000).toISOString() },
    timeZone: 'Asia/Qyzylorda',
    allDay: false,
    busy: true,
    readOnly: false,
    colorId: String((i % 11) + 1),
  };
});
app.get('/api/integrations/google/status', (_req, res) =>
  res.json({
    configured: true,
    status: 'connected',
    mode: 'readwrite',
    calendarId: 'primary',
    lastFetchedAt: new Date().toISOString(),
  }),
);
app.get('/api/integrations/google/events', (req, res) =>
  res.json({
    events: fixtureEvents,
    from: req.query.from,
    to: req.query.to,
    timeZone: req.query.timeZone,
    fetchedAt: new Date().toISOString(),
    partial: false,
  }),
);
app.patch('/api/integrations/google/events/:id', express.json(), (req, res) => {
  const event = fixtureEvents.find((e) => e.id === req.params.id);
  if (!event || req.body.etag !== event.etag)
    return res.status(409).json({ error: 'Demo conflict' });
  const input = req.body.event;
  const start = new Date(`${input.date}T${input.time}:00+05:00`);
  if (!Number.isFinite(start.getTime()))
    return res.status(400).json({ error: 'Invalid demo time' });
  Object.assign(event, {
    title: input.title,
    description: input.description,
    start: { dateTime: start.toISOString() },
    end: { dateTime: new Date(start.getTime() + input.duration * 60000).toISOString() },
    etag: `"perf-${Date.now()}"`,
  });
  res.json(event);
});
app.get('/__perf/probe.js', (_req, res) =>
  res
    .type('js')
    .send(
      readFileSync(resolve(root, 'scripts/performance/clock.mjs'), 'utf8') +
        '\n' +
        readFileSync(resolve(root, 'scripts/performance/probe.js'), 'utf8'),
    ),
);
app.get('/', (_req, res) =>
  res
    .type('html')
    .send(
      readFileSync(join(outDir, 'index.html'), 'utf8').replace(
        '<head>',
        '<head><script src="/__perf/probe.js"></script>',
      ),
    ),
);
app.use(instance.app);
const server = app.listen(port, '127.0.0.1', () =>
  console.log(`Isolated PRODUCTION frontend ${variant}: http://127.0.0.1:${port}/#day`),
);
const close = () => server.close(() => void instance.close().then(() => process.exit(0)));
process.on('SIGINT', close);
process.on('SIGTERM', close);
