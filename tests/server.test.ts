import test, { type TestContext } from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { request as httpRequest } from 'node:http';
import { mkdtempSync, readFileSync, readdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { randomUUID } from 'node:crypto';
import type { AddressInfo } from 'node:net';
import type { Bootstrap, Conversation, Task, TaskInput } from '../shared/types.ts';
import { createApp, type AppOptions } from '../server/index.ts';
import { AppError } from '../server/errors.ts';
import { Store, localDate } from '../server/store.ts';
import { assistantMessage } from '../server/assistant.ts';
import type { AssistantReply } from '../server/validation.ts';

const baseTask: TaskInput = {
  title: 'Подготовить презентацию',
  description: 'Прототип для команды',
  date: '2099-10-14',
  time: '11:00',
  duration: 60,
  priority: 'high',
  repeat: 'none',
  kind: 'task',
  completed: false,
};
const fakeKey = 'sk-test-server-only-abcdefghijklmnopqrstuvwxyz';
const okayReply: AssistantReply = { text: 'Вот план для ваших задач.', steps: [], proposals: [] };

async function harness(t: TestContext, options: AppOptions = {}) {
  const dataDir = mkdtempSync(join(tmpdir(), 'ritm-test-'));
  const instance = createApp({ dataDir, seed: false, env: { NODE_ENV: 'test' }, ...options });
  const server = instance.app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const url = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  t.after(async () => {
    server.closeAllConnections();
    await new Promise<void>((done) => server.close(() => done()));
    await instance.close();
    // This is our own mkdtemp directory, verified before recursive cleanup.
    assert.ok(
      resolve(dataDir).startsWith(resolve(tmpdir()) + '\\') ||
        resolve(dataDir).startsWith(resolve(tmpdir()) + '/'),
    );
    assert.ok(dataDir.includes('ritm-test-'));
    rmSync(dataDir, { recursive: true, force: true });
  });
  const call = async (
    path: string,
    method = 'GET',
    body?: unknown,
    headers: Record<string, string> = {},
  ) => {
    const response = await fetch(`${url}/api${path}`, {
      method,
      headers: { ...(method !== 'GET' ? { 'Content-Type': 'application/json' } : {}), ...headers },
      ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
    });
    return { response, status: response.status, body: (await response.json()) as any };
  };
  return { ...instance, store: instance.store as Store, dataDir, call, url };
}

test('SQLite CRUD, validation, deletion undo and persistence are real', async (t) => {
  const h = await harness(t);
  const initial = await h.call('/bootstrap');
  assert.equal(initial.status, 200);
  assert.deepEqual(initial.body.tasks, []);
  assert.equal(initial.body.aiStatus.configured, false);
  const created = await h.call('/tasks', 'POST', baseTask);
  assert.equal(created.status, 201);
  const task = created.body as Task;
  assert.equal(task.title, baseTask.title);
  assert.deepEqual(task.completedDates, []);
  const changed = await h.call(`/tasks/${task.id}`, 'PATCH', {
    title: 'Проверить презентацию',
    completed: true,
  });
  assert.equal(changed.status, 200);
  assert.equal(changed.body.completed, true);
  assert.notEqual(changed.body.updatedAt, task.updatedAt);
  assert.equal((await h.call(`/tasks/${task.id}`, 'PATCH', { date: '2026-02-30' })).status, 400);
  assert.equal(
    (await h.call(`/tasks/${task.id}`, 'PATCH', { date: null, time: '15:00' })).status,
    400,
  );
  assert.equal(
    (await h.call('/tasks', 'POST', { ...baseTask, time: '23:30', duration: 60 })).status,
    400,
  );
  assert.equal((await h.call('/tasks', 'POST', { ...baseTask, apiKey: fakeKey })).status, 400);
  const deleted = await h.call(`/tasks/${task.id}`, 'DELETE');
  assert.equal(deleted.status, 200);
  assert.deepEqual((await h.call('/bootstrap')).body.tasks, []);
  const forged = { ...deleted.body.deletedTask, title: 'Подменённое задание' };
  assert.equal((await h.call('/tasks/restore', 'POST', { task: forged })).status, 409);
  const restored = await h.call('/tasks/restore', 'POST', { task: deleted.body.deletedTask });
  assert.equal(restored.status, 200);
  assert.equal(restored.body.id, task.id);
  assert.notEqual(restored.body.updatedAt, deleted.body.deletedTask.updatedAt);
  assert.equal(
    (await h.call('/tasks/restore', 'POST', { task: deleted.body.deletedTask })).status,
    409,
  );
  assert.equal(
    (await h.call('/settings', 'PATCH', { theme: 'light', timeZone: 'Asia/Qyzylorda' })).status,
    200,
  );
  assert.equal((await h.call('/settings', 'PATCH', { timeZone: 'Unreal/Zone' })).status, 400);
  assert.equal(
    (await h.call('/settings', 'PATCH', { workDayStart: '18:00', workDayEnd: '09:00' })).status,
    400,
  );
  const secondReader = new Store(h.dataDir, true);
  try {
    assert.equal(secondReader.tasks().length, 1);
    assert.equal(secondReader.settings().theme, 'light');
  } finally {
    secondReader.close();
  }
});

test('seed is relative to Qyzylorda today and runs only once', async (t) => {
  const h = await harness(t, { seed: true });
  const tasks = (await h.call('/bootstrap')).body.tasks as Task[];
  assert.equal(tasks.length, 7);
  const today = localDate(new Date(), 'Asia/Qyzylorda');
  assert.equal(tasks.filter((task) => task.date === today).length, 5);
  for (const task of tasks) await h.call(`/tasks/${task.id}`, 'DELETE');
  const second = new Store(h.dataDir, true);
  try {
    assert.equal(second.tasks().length, 0);
  } finally {
    second.close();
  }
});

test('recurring completion affects one occurrence and survives edits/restore', async (t) => {
  const h = await harness(t);
  const created = await h.call('/tasks', 'POST', { ...baseTask, repeat: 'weekly' });
  assert.equal(created.status, 201);
  const task = created.body as Task;
  assert.equal((await h.call(`/tasks/${task.id}`, 'PATCH', { completed: true })).status, 400);
  assert.equal(
    (await h.call(`/tasks/${task.id}`, 'PATCH', { completed: true, occurrenceDate: '2099-10-15' }))
      .status,
    400,
  );
  const completed = await h.call(`/tasks/${task.id}`, 'PATCH', {
    completed: true,
    occurrenceDate: '2099-10-21',
  });
  assert.equal(completed.status, 200);
  assert.equal(completed.body.completed, false);
  assert.deepEqual(completed.body.completedDates, ['2099-10-21']);
  const edited = await h.call(`/tasks/${task.id}`, 'PATCH', { title: 'Повторяющаяся презентация' });
  assert.deepEqual(edited.body.completedDates, ['2099-10-21']);
  const removed = await h.call(`/tasks/${task.id}`, 'DELETE');
  const restored = await h.call('/tasks/restore', 'POST', { task: removed.body.deletedTask });
  assert.equal(restored.status, 200);
  assert.deepEqual(restored.body.completedDates, ['2099-10-21']);
  const undone = await h.call(`/tasks/${task.id}`, 'PATCH', {
    completed: false,
    occurrenceDate: '2099-10-21',
  });
  assert.deepEqual(undone.body.completedDates, []);
});

test('password sessions, hostile Origin/Host and secret non-exposure', async (t) => {
  const h = await harness(t, { env: { NODE_ENV: 'test', APP_PASSWORD: 'a-long-test-password' } });
  assert.equal((await h.call('/session')).body.authenticated, false);
  assert.equal((await h.call('/bootstrap')).status, 401);
  assert.equal(
    (await h.call('/login', 'POST', { login: 'maksim', password: 'wrong' })).status,
    401,
  );
  const login = await h.call('/login', 'POST', {
    login: 'MaKsim',
    password: 'a-long-test-password',
  });
  assert.equal(login.status, 200);
  const setCookie = login.response.headers.get('set-cookie')!;
  assert.match(setCookie, /HttpOnly/);
  assert.match(setCookie, /SameSite=Strict/);
  const cookie = setCookie.split(';')[0];
  const auth = { Cookie: cookie };
  assert.equal((await h.call('/bootstrap', 'GET', undefined, auth)).status, 200);
  assert.equal(
    (await h.call('/tasks', 'POST', baseTask, { ...auth, Origin: 'https://evil.example' })).status,
    403,
  );
  const hostileHostStatus = await new Promise<number>((done, reject) => {
    // Node fetch normalizes Host, so send the hostile header with raw HTTP.
    const request = httpRequest(
      `${h.url}/api/bootstrap`,
      { headers: { ...auth, Host: 'evil.example' } },
      (response) => {
        response.resume();
        done(response.statusCode!);
      },
    );
    request.on('error', reject);
    request.end();
  });
  assert.equal(hostileHostStatus, 403);
  assert.equal(
    (await h.call('/tasks', 'POST', baseTask, { ...auth, 'Content-Type': 'text/plain' })).status,
    415,
  );
  const saved = await h.call(
    '/settings/openai',
    'POST',
    { apiKey: fakeKey, model: 'gpt-6-luna' },
    auth,
  );
  assert.equal(saved.status, 200);
  assert.equal(saved.body.source, 'saved');
  assert.equal(JSON.stringify(saved.body).includes(fakeKey), false);
  const bootstrap = await h.call('/bootstrap', 'GET', undefined, auth);
  assert.equal(JSON.stringify(bootstrap.body).includes(fakeKey), false);
  assert.equal(
    readFileSync(join(h.dataDir, 'openai-secret.json'), 'utf8').includes(fakeKey),
    false,
  );
  assert.equal(readFileSync(join(h.dataDir, '.secret-key')).length, 32);
  assert.equal(readFileSync(join(h.dataDir, 'ritm.sqlite')).includes(Buffer.from(fakeKey)), false);
  assert.equal(
    (await h.call('/settings/openai', 'DELETE', undefined, auth)).body.configured,
    false,
  );
  assert.equal((await h.call('/logout', 'POST', undefined, auth)).status, 200);
  assert.equal((await h.call('/bootstrap', 'GET', undefined, auth)).status, 401);
});

test('public/production binds fail closed without password; env key is honest', async (t) => {
  assert.throws(() => createApp({ env: { HOST: '0.0.0.0' } }), /APP_PASSWORD/);
  assert.throws(() => createApp({ env: { NODE_ENV: 'production' } }), /APP_PASSWORD/);
  assert.throws(
    () =>
      createApp({
        env: {
          HOST: '0.0.0.0',
          APP_PASSWORD: 'long-test-password',
          APP_ORIGIN: 'http://ritm.example',
        },
      }),
    /HTTPS/,
  );
  const h = await harness(t, {
    env: { NODE_ENV: 'test', OPENAI_API_KEY: fakeKey, OPENAI_MODEL: 'gpt-6-luna' },
  });
  const bootstrap = await h.call('/bootstrap');
  assert.equal(bootstrap.body.aiStatus.source, 'environment');
  assert.equal(JSON.stringify(bootstrap.body).includes(fakeKey), false);
  assert.equal((await h.call('/settings/openai', 'DELETE')).status, 409);
  assert.equal(
    (await h.call('/settings/openai', 'POST', { apiKey: fakeKey, model: 'another-model' })).status,
    409,
  );
  assert.equal(readdirSync(h.dataDir).includes('.secret-key'), false);
});

test('chat without key has honest error; provider failure is retryable and idempotent', async (t) => {
  const unavailable = await harness(t);
  assert.equal(
    (
      await unavailable.call('/chat', 'POST', {
        message: 'Что у меня сегодня?',
        requestId: randomUUID(),
      })
    ).status,
    503,
  );
  assert.deepEqual((await unavailable.call('/bootstrap')).body.conversations, []);
  let calls = 0;
  const h = await harness(t, {
    env: { NODE_ENV: 'test', OPENAI_API_KEY: fakeKey },
    assistant: async () => {
      if (++calls === 1) throw new AppError(502, 'AI_UNAVAILABLE', 'Повторите позже.');
      return okayReply;
    },
  });
  const input = { message: 'Разбей задачу на шаги', requestId: randomUUID() };
  assert.equal((await h.call('/chat', 'POST', input)).status, 502);
  assert.deepEqual((await h.call('/bootstrap')).body.conversations, []);
  const success = await h.call('/chat', 'POST', input);
  assert.equal(success.status, 200);
  assert.equal(success.body.messages.length, 2);
  assert.equal((await h.call('/chat', 'POST', input)).body.messages.length, 2);
  assert.equal(calls, 2);
  assert.equal((await h.call('/chat', 'POST', { ...input, message: 'Другой запрос' })).status, 409);
  const reader = new Store(h.dataDir, false);
  try {
    assert.equal(reader.conversations()[0].messages.length, 2);
  } finally {
    reader.close();
  }
});

test('selected AI changes apply atomically, undo is safe, stale/colliding plans rollback', async (t) => {
  let targets: Task[] = [];
  const h = await harness(t, {
    env: { NODE_ENV: 'test', OPENAI_API_KEY: fakeKey },
    assistant: async (context) => ({
      ...okayReply,
      proposals: targets.map((task, index) => ({
        taskId: task.id,
        date: '2099-10-15',
        time: index === 0 ? '10:00' : '12:00',
        duration: task.duration,
        reason: 'Свободное окно',
      })),
    }),
  });
  const one = (await h.call('/tasks', 'POST', baseTask)).body as Task;
  const two = (
    await h.call('/tasks', 'POST', { ...baseTask, title: 'Подготовить отчёт', time: '13:00' })
  ).body as Task;
  targets = [one, two];
  const conversation = (
    await h.call('/chat', 'POST', { message: 'Спланируй день', requestId: randomUUID() })
  ).body as Conversation;
  const message = conversation.messages[1];
  assert.equal(h.store.task(one.id).date, '2099-10-14'); // Generation did not mutate data.
  const action = {
    conversationId: conversation.id,
    messageId: message.id,
    proposalIds: message.proposals.map((p) => p.id),
  };
  await h.call(`/tasks/${two.id}`, 'PATCH', { description: 'Ручное изменение после ответа' });
  assert.equal((await h.call('/proposals/apply', 'POST', action)).status, 409);
  assert.equal(h.store.task(one.id).date, '2099-10-14'); // No partial apply.
  const selected = { ...action, proposalIds: [message.proposals[0].id] };
  assert.equal((await h.call('/proposals/apply', 'POST', selected)).status, 200);
  assert.equal(h.store.task(one.id).time, '10:00');
  assert.equal(h.store.task(two.id).date, '2099-10-14');
  assert.equal((await h.call('/proposals/undo', 'POST', selected)).status, 200);
  assert.equal(h.store.task(one.id).time, '11:00');
  assert.equal((await h.call('/proposals/undo', 'POST', selected)).status, 409);

  targets = [h.store.task(one.id)];
  const newer = (
    await h.call('/chat', 'POST', {
      conversationId: conversation.id,
      message: 'Ещё вариант',
      requestId: randomUUID(),
    })
  ).body as Conversation;
  const last = newer.messages.at(-1)!;
  const nextAction = {
    conversationId: newer.id,
    messageId: last.id,
    proposalIds: [last.proposals[0].id],
  };
  const blocker = (
    await h.call('/tasks', 'POST', {
      ...baseTask,
      title: 'Фиксированная встреча',
      kind: 'event',
      date: '2099-10-15',
      time: '10:30',
    })
  ).body as Task;
  assert.equal((await h.call('/proposals/apply', 'POST', nextAction)).status, 409);
  assert.equal(h.store.task(one.id).date, '2099-10-14');
  await h.call(`/tasks/${blocker.id}`, 'DELETE');
  assert.equal((await h.call('/proposals/apply', 'POST', nextAction)).status, 200);
  await h.call(`/tasks/${one.id}`, 'PATCH', { time: '16:00' });
  assert.equal((await h.call('/proposals/undo', 'POST', nextAction)).status, 409);
  assert.equal(h.store.task(one.id).time, '16:00');
  assert.equal(
    (
      await h.call('/proposals/reject', 'POST', {
        ...action,
        proposalIds: [message.proposals[1].id],
      })
    ).status,
    200,
  );
  assert.equal(h.store.task(two.id).date, '2099-10-14');
});

test('task color API persists across reload and restore, rejects injected colors and supports default reset', async (t) => {
  const h = await harness(t);
  const created = await h.call('/tasks', 'POST', { ...baseTask, colorId: '8' });
  assert.equal(created.status, 201);
  const id = created.body.id;
  const changed = await h.call(`/tasks/${id}`, 'PATCH', { colorId: '10' });
  assert.equal(changed.status, 200);
  const bootstrap = await h.call('/bootstrap');
  assert.equal(bootstrap.body.tasks[0].colorId, '10');
  assert.equal(bootstrap.body.tasks[0].time, baseTask.time);
  const custom = await h.call(`/tasks/${id}`, 'PATCH', { colorId: '#E91E63' });
  assert.equal(custom.status, 200);
  assert.equal(custom.body.colorId, '#e91e63');
  assert.equal(
    (await h.call(`/tasks/${id}`, 'PATCH', { colorId: '#ff0000; color:red' })).status,
    400,
  );
  assert.equal((await h.call(`/tasks/${id}`, 'PATCH', { colorId: '99' })).status, 400);
  assert.equal((await h.call(`/tasks/${id}`, 'PATCH', { colorId: { style: 'red' } })).status, 400);
  assert.equal(h.store.task(id).colorId, '#e91e63');
  const deleted = await h.call(`/tasks/${id}`, 'DELETE');
  assert.equal(
    (await h.call('/tasks/restore', 'POST', { task: deleted.body.deletedTask })).body.colorId,
    '#e91e63',
  );
  assert.equal((await h.call(`/tasks/${id}`, 'PATCH', { colorId: null })).body.colorId, null);
});

test('malformed AI proposals never enter history; past/no-op/types are rejected', async (t) => {
  const h = await harness(t);
  const task = h.store.createTask(baseTask);
  const change = {
    taskId: task.id,
    date: '2099-10-15',
    time: '09:00',
    duration: 60,
    reason: 'Свободное время',
  };
  const message = (proposal: Record<string, unknown>, tasks: Task[] = [task]) =>
    assistantMessage(
      { ...okayReply, proposals: [{ ...change, ...proposal }] } as AssistantReply,
      tasks,
    );
  assert.throws(() => message({ taskId: randomUUID() }), AppError);
  assert.throws(() => message({ date: '2099-02-30' }), AppError);
  assert.throws(() => message({ date: null, time: '10:00' }), AppError);
  assert.throws(() => message({ time: '23:30', duration: 60 }), AppError);
  assert.throws(() => message({ date: '2000-01-01' }), AppError);
  assert.throws(() => message({ date: task.date, time: task.time }), AppError);
  assert.throws(() => message({}, [{ ...task, completed: true }]), AppError);
  assert.throws(() => message({}, [{ ...task, kind: 'event' }]), AppError);
  assert.throws(() => message({}, [{ ...task, repeat: 'daily' }]), AppError);
  assert.equal(message({}).proposals[0].status, 'pending');
});
