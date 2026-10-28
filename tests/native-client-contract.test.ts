import test from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve, sep } from 'node:path';
import type { AddressInfo } from 'node:net';
import { createApp } from '../server/index.ts';
import type { Bootstrap, Habit, Task } from '../shared/types.ts';

// Native clients have no browser fetch metadata. This fixture exercises their
// HTTP contract against the real app, without contacting production or providers.
test('native JSON clients share data while sessions, origins and habit versions stay protected', async (t) => {
  const directory = mkdtempSync(join(tmpdir(), 'ritm-native-contract-'));
  const app = createApp({
    dataDir: directory,
    seed: false,
    env: {
      NODE_ENV: 'test',
      APP_ORIGIN: 'https://ritm.example',
      APP_LOGIN: 'test-owner',
      APP_PASSWORD: 'native-contract-test-password',
      APP_SESSION_SECRET: 'native-contract-test-secret-'.repeat(3),
    },
    securityLogger: () => {},
  });
  const server = app.app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  t.after(async () => {
    server.closeAllConnections();
    await new Promise<void>((done) => server.close(() => done()));
    await app.close();
    const target = resolve(directory);
    assert.ok(target.startsWith(resolve(tmpdir()) + sep));
    assert.ok(target.includes('ritm-native-contract-'));
    rmSync(target, { recursive: true, force: true });
  });
  const call = (
    path: string,
    method = 'GET',
    cookie?: string,
    body?: unknown,
    origin = 'https://ritm.example',
  ) =>
    fetch(base + path, {
      method,
      redirect: 'error',
      headers: {
        Origin: origin,
        'Accept-Language': 'en',
        ...(cookie ? { Cookie: cookie } : {}),
        ...(method === 'GET' ? {} : { 'Content-Type': 'application/json' }),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  const login = async () => {
    const response = await call('/api/login', 'POST', undefined, {
      login: 'test-owner',
      password: 'native-contract-test-password',
    });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { authenticated: true, requiresLogin: true });
    const cookie = response.headers.get('set-cookie');
    assert.ok(cookie);
    assert.match(cookie, /^__Host-ritm_session=/);
    assert.match(cookie, /; Path=\//);
    assert.match(cookie, /; HttpOnly/);
    assert.match(cookie, /; Secure/);
    assert.match(cookie, /; SameSite=Strict/);
    assert.match(cookie, /; Max-Age=28800/);
    assert.doesNotMatch(cookie, /; Domain=/i);
    return cookie.split(';')[0];
  };

  const anonymous = await call('/api/session');
  assert.deepEqual(await anonymous.json(), { authenticated: false, requiresLogin: true });
  assert.equal((await call('/api/bootstrap')).status, 401);
  const phone = await login();
  const desktop = await login();
  assert.notEqual(phone, desktop);

  const bootstrap = await call('/api/bootstrap', 'GET', phone);
  assert.equal(bootstrap.status, 200);
  assert.equal(bootstrap.headers.get('cache-control'), 'no-store');
  const initial = (await bootstrap.json()) as Bootstrap;
  assert.ok(initial.settings.timeZone);
  assert.equal(initial.tasks.length, 0);

  const created = await call('/api/tasks', 'POST', phone, {
    title: 'Native contract task',
    description: '',
    date: '2026-10-28',
    time: null,
    duration: 30,
    priority: 'normal',
    repeat: 'none',
    kind: 'task',
    completed: false,
    calendarEntry: false,
  });
  assert.equal(created.status, 201);
  const task = (await created.json()) as Task;
  const desktopSnapshot = (await (
    await call('/api/bootstrap', 'GET', desktop)
  ).json()) as Bootstrap;
  assert.equal(desktopSnapshot.tasks[0].id, task.id);
  const completed = await call(`/api/tasks/${task.id}`, 'PATCH', desktop, { completed: true });
  assert.equal(completed.status, 200);
  const phoneSnapshot = (await (await call('/api/bootstrap', 'GET', phone)).json()) as Bootstrap;
  assert.equal(phoneSnapshot.tasks[0].completed, true);

  const createdHabit = await call('/api/habits', 'POST', phone, { title: 'Native contract habit' });
  assert.equal(createdHabit.status, 201);
  const { habit } = (await createdHabit.json()) as { habit: Habit };
  const marked = await call(`/api/habits/${habit.id}/days/${habit.startDate}`, 'PATCH', phone, {
    completed: true,
    expectedUpdatedAt: habit.updatedAt,
  });
  assert.equal(marked.status, 200);
  const stale = await call(`/api/habits/${habit.id}/days/${habit.startDate}`, 'PATCH', desktop, {
    completed: false,
    expectedUpdatedAt: habit.updatedAt,
  });
  assert.equal(stale.status, 409);
  const sharedHabits = (await (await call('/api/habits', 'GET', desktop)).json()) as {
    habits: Habit[];
  };
  assert.ok(sharedHabits.habits[0].completedDates.includes(habit.startDate));

  assert.equal(
    (await call('/api/tasks', 'POST', phone, {}, 'https://untrusted.example')).status,
    403,
  );
  assert.equal((await call('/api/logout', 'POST', phone, {})).status, 200);
  assert.equal((await call('/api/bootstrap', 'GET', phone)).status, 401);
  assert.equal((await call('/api/bootstrap', 'GET', desktop)).status, 200);
});
