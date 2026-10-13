import test, { type TestContext } from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { createHash } from 'node:crypto';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import type { AddressInfo } from 'node:net';
import type { GoogleCalendarEvent, GoogleEventInput, TaskInput } from '../shared/types.ts';
import { createApp, type AppOptions } from '../server/index.ts';
import { Store } from '../server/store.ts';
import { AppError } from '../server/errors.ts';

const input: TaskInput = {
  title: 'Gym',
  description: 'Тренировка',
  date: '2099-10-14',
  time: '09:00',
  duration: 90,
  priority: 'normal',
  repeat: 'none',
  kind: 'task',
  completed: false,
  colorId: '10',
};

async function fixture(t: TestContext) {
  const dataDir = mkdtempSync(join(tmpdir(), 'ritm-transfer-http-'));
  const store = new Store(dataDir, false),
    writes: { input: GoogleEventInput; id: string }[] = [];
  const deleted: { id: string; etag: string }[] = [];
  const env = {
    NODE_ENV: 'test',
    APP_ORIGIN: 'https://ritm.example',
    APP_LOGIN: 'owner',
    APP_PASSWORD: 'test-only-owner-password',
    APP_SESSION_SECRET: 'test-only-session-key-'.repeat(3),
  };
  const status = {
    configured: true,
    status: 'connected' as const,
    mode: 'readwrite' as const,
    calendarId: 'primary' as const,
    lastFetchedAt: null,
  };
  let fail = false;
  const unexpected = async () => {
    throw new Error('Unexpected fixture method');
  };
  const google: NonNullable<AppOptions['googleService']> = {
    configuration: async () => ({
      configured: true,
      source: 'saved',
      clientId: 'test.apps.googleusercontent.com',
      hasClientSecret: true,
      redirectUri: env.APP_ORIGIN + '/api/integrations/google/callback',
    }),
    saveConfiguration: unexpected,
    removeConfiguration: unexpected,
    connect: unexpected,
    callback: unexpected,
    listEvents: unexpected,
    updateEvent: unexpected,
    assertFreeSlots: unexpected,
    status: async () => status,
    disconnect: async () => status,
    connectionIdentity: async () => 'a'.repeat(64),
    withConnectionIdentity: async (_identity, operation) => operation(() => {}),
    createEvent: async (value, id, options = {}) => {
      writes.push({ input: value, id });
      assert.equal(options.expectedConnectionIdentity, 'a'.repeat(64));
      assert.equal(options.timeZone, 'Asia/Qyzylorda');
      if (fail) throw new AppError(502, 'GOOGLE_UNAVAILABLE', 'Google не ответил.');
      return {
        id: createHash('sha256')
          .update('Ritm:' + id)
          .digest('hex'),
        title: value.title,
        description: value.description,
        source: 'google',
        calendarId: 'primary',
        etag: '"v1"',
        start: { dateTime: '2099-10-14T04:00:00Z' },
        end: { dateTime: '2099-10-14T05:30:00Z' },
        allDay: false,
        busy: true,
        readOnly: false,
        timeZone: options.timeZone,
        ...(value.colorId ? { colorId: value.colorId } : {}),
      } as GoogleCalendarEvent;
    },
    deleteEvent: async (id, etag) => {
      deleted.push({ id, etag });
      return { deleted: true };
    },
  };
  const instance = createApp({ dataDir, env, repository: store, googleService: google });
  const server = instance.app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(async () => {
    server.closeAllConnections();
    await new Promise<void>((done) => server.close(() => done()));
    await instance.close();
    assert.ok(
      resolve(dataDir).startsWith(resolve(tmpdir())) && dataDir.includes('ritm-transfer-http-'),
    );
    rmSync(dataDir, { recursive: true, force: true });
  });
  const base = 'http://127.0.0.1:' + (server.address() as AddressInfo).port;
  const login = await fetch(base + '/api/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ login: env.APP_LOGIN, password: env.APP_PASSWORD }),
  });
  assert.equal(login.status, 200);
  const cookie = login.headers.get('set-cookie')!.split(';')[0];
  const call = async (
    path: string,
    body: unknown,
    options: { method?: string; cookie?: string; origin?: string } = {},
  ) => {
    const response = await fetch(base + '/api' + path, {
      method: options.method ?? 'POST',
      headers: {
        'Content-Type': 'application/json',
        Cookie: options.cookie ?? cookie,
        Origin: options.origin ?? env.APP_ORIGIN,
      },
      body: JSON.stringify(body),
    });
    return { status: response.status, body: await response.json(), headers: response.headers };
  };
  return {
    store,
    writes,
    deleted,
    call,
    setFail: (value: boolean) => {
      fail = value;
    },
  };
}

test('task migration HTTP accepts only owner-confirmed empty body and returns the confirmed canonical event', async (t) => {
  const f = await fixture(t),
    task = f.store.createTask(input),
    route = '/tasks/' + task.id + '/google';
  assert.equal((await f.call(route, {}, { cookie: '' })).status, 401);
  assert.equal((await f.call(route, {}, { origin: 'https://untrusted.example' })).status, 403);
  for (const body of [{ task }, { title: 'Injected title' }, { requestId: task.id }, []]) {
    const result = await f.call(route, body);
    assert.equal(result.status, 400);
    assert.equal(result.body.code, 'VALIDATION_ERROR');
  }
  assert.equal(f.writes.length, 0);
  assert.equal(f.store.task(task.id).id, task.id);
  f.store.updateTask(task.id, { title: 'Gym: обновлённая тренировка' });
  const result = await f.call(route, {});
  assert.equal(result.status, 200);
  assert.equal(result.headers.get('cache-control'), 'no-store');
  assert.deepEqual(Object.keys(result.body).sort(), ['event', 'transferredTaskId']);
  assert.equal(result.body.event.title, 'Gym: обновлённая тренировка');
  assert.equal(result.body.event.colorId, '10');
  assert.equal(result.body.transferredTaskId, task.id);
  assert.equal(f.writes[0].id, task.id);
  assert.equal(f.writes.length, 1);
  assert.equal(f.store.tasks().length, 0);
  assert.deepEqual((await f.call(route, {})).body, result.body);
  assert.equal(f.writes.length, 1);
  const failed = f.store.createTask(input);
  f.setFail(true);
  const error = await f.call('/tasks/' + failed.id + '/google', {});
  assert.equal(error.status, 502);
  assert.equal(error.body.code, 'GOOGLE_UNAVAILABLE');
  assert.equal(f.store.task(failed.id).id, failed.id);
  assert.equal(f.store.googleTransfer(failed.id)?.status, 'pending');
});

test('Google DELETE HTTP requires authenticated confirmation with a valid ETag and strict body', async (t) => {
  const f = await fixture(t),
    path = '/integrations/google/events/event12345',
    options = { method: 'DELETE' };
  assert.equal((await f.call(path, { etag: '"v1"' }, { ...options, cookie: '' })).status, 401);
  assert.equal(
    (await f.call(path, { etag: '"v1"' }, { ...options, origin: 'https://untrusted.example' }))
      .status,
    403,
  );
  for (const body of [{}, { etag: 'not-a-version' }, { etag: '"v1"', id: 'other' }])
    assert.equal((await f.call(path, body, options)).status, 400);
  assert.equal(f.deleted.length, 0);
  const result = await f.call(path, { etag: '"v1"' }, options);
  assert.equal(result.status, 200);
  assert.deepEqual(result.body, { deleted: true });
  assert.deepEqual(f.deleted, [{ id: 'event12345', etag: '"v1"' }]);
});
