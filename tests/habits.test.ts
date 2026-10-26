import test from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve, sep } from 'node:path';
import type { AddressInfo } from 'node:net';
import { Store } from '../server/store.ts';
import { createApp } from '../server/index.ts';
import { habitInputSchema } from '../server/validation.ts';
import { habitStreak, habitWeek } from '../src/features/habit-utils.ts';
import type { Habit } from '../shared/types.ts';

test('habit names are bounded and the streak tolerates an unfinished today', () => {
  assert.equal(habitInputSchema.safeParse({ title: '  Читать  ' }).data?.title, 'Читать');
  assert.equal(habitInputSchema.safeParse({ title: '', extra: true }).success, false);
  assert.equal(habitInputSchema.safeParse({ title: 'a'.repeat(81) }).success, false);
  const habit = {
    startDate: '2026-10-20',
    completedDates: ['2026-10-23', '2026-10-24', '2026-10-25'],
  } as Habit;
  assert.equal(habitStreak(habit, '2026-10-26'), 3);
  assert.equal(
    habitStreak(
      { ...habit, completedDates: [...habit.completedDates, '2026-10-26'] },
      '2026-10-26',
    ),
    4,
  );
  assert.deepEqual(habitWeek('2026-10-26'), [
    '2026-10-20',
    '2026-10-21',
    '2026-10-22',
    '2026-10-23',
    '2026-10-24',
    '2026-10-25',
    '2026-10-26',
  ]);
});

test('habits persist in SQLite and reject stale revisions and future days', () => {
  const directory = mkdtempSync(join(tmpdir(), 'ritm-habits-'));
  try {
    const first = new Store(directory, false);
    const created = first.createHabit({ title: 'Читать' });
    const marked = first.setHabitDay(created.id, created.startDate, true, created.updatedAt);
    assert.deepEqual(marked.completedDates, [created.startDate]);
    assert.throws(
      () => first.setHabitDay(created.id, created.startDate, false, created.updatedAt),
      (e: unknown) => e instanceof Error && 'status' in e && e.status === 409,
    );
    assert.throws(
      () => first.setHabitDay(created.id, '2099-01-01', true, marked.updatedAt),
      (e: unknown) => e instanceof Error && 'code' in e && e.code === 'HABIT_DATE_INVALID',
    );
    first.close();
    const second = new Store(directory, false);
    assert.deepEqual(second.habits()[0].completedDates, [created.startDate]);
    const renamed = second.updateHabit(created.id, { title: 'Читать 20 минут' }, marked.updatedAt);
    second.deleteHabit(created.id, renamed.updatedAt);
    assert.deepEqual(second.habits(), []);
    second.close();
  } finally {
    assert.ok(resolve(directory).startsWith(resolve(tmpdir()) + sep));
    rmSync(directory, { recursive: true, force: true });
  }
});

test('habit API needs the owner session and keeps day marks', async (t) => {
  const directory = mkdtempSync(join(tmpdir(), 'ritm-habits-api-'));
  const instance = createApp({
    dataDir: directory,
    seed: false,
    env: { NODE_ENV: 'test', APP_PASSWORD: 'habits-test-password' },
  });
  const server = instance.app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(async () => {
    server.closeAllConnections();
    await new Promise<void>((done) => server.close(() => done()));
    await instance.close();
    assert.ok(resolve(directory).startsWith(resolve(tmpdir()) + sep));
    rmSync(directory, { recursive: true, force: true });
  });
  const root = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  assert.equal((await fetch(root + '/api/habits')).status, 401);
  const login = await fetch(root + '/api/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ login: 'maksim', password: 'habits-test-password' }),
  });
  assert.equal(login.status, 200);
  const cookie = login.headers.get('set-cookie')!.split(';')[0];
  const call = (path: string, method = 'GET', body?: unknown) =>
    fetch(root + '/api' + path, {
      method,
      headers: {
        Cookie: cookie,
        ...(method === 'GET' ? {} : { 'Content-Type': 'application/json' }),
      },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
  const created = await call('/habits', 'POST', { title: 'Зарядка' });
  assert.equal(created.status, 201);
  const habit = (await created.json()).habit as Habit;
  assert.equal((await call('/habits', 'POST', { title: '  ' })).status, 400);
  const marked = await call(`/habits/${habit.id}/days/${habit.startDate}`, 'PATCH', {
    completed: true,
    expectedUpdatedAt: habit.updatedAt,
  });
  assert.equal(marked.status, 200);
  const next = (await marked.json()).habit as Habit;
  assert.deepEqual(next.completedDates, [habit.startDate]);
  assert.equal(
    (
      await call(`/habits/${habit.id}/days/${habit.startDate}`, 'PATCH', {
        completed: false,
        expectedUpdatedAt: habit.updatedAt,
      })
    ).status,
    409,
  );
  assert.equal(
    (
      await call(`/habits/${habit.id}/days/2099-01-01`, 'PATCH', {
        completed: true,
        expectedUpdatedAt: next.updatedAt,
      })
    ).status,
    400,
  );
  assert.equal((await (await call('/habits')).json()).habits[0].completedDates[0], habit.startDate);
});
