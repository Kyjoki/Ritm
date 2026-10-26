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
import {
  assertHabitDay,
  habitBestStreak as serverHabitBestStreak,
  isHabitScheduled,
  updateHabitDefinition,
  updateHabitProgress,
} from '../server/habits.ts';
import {
  habitBestStreak,
  habitCompleteOn,
  habitProgress,
  habitScheduledOn,
  habitStreak,
  habitWeek,
} from '../src/features/habit-utils.ts';
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
    '2026-10-25',
    '2026-10-26',
    '2026-10-27',
    '2026-10-28',
    '2026-10-29',
    '2026-10-30',
    '2026-10-31',
  ]);
});

test('scheduled days, partial goals and rest days determine streaks without losing records', () => {
  const habit = {
    id: 'frontend-test',
    title: 'Read',
    startDate: '2026-10-19',
    weekdays: [1, 3, 5],
    target: 20,
    completedDates: ['2026-10-19', '2026-10-21', '2026-10-23'],
    progressByDate: { '2026-10-26': 12 },
    createdAt: '',
    updatedAt: '',
  } satisfies Habit;
  assert.equal(habitScheduledOn(habit, '2026-10-25'), false);
  assert.equal(habitProgress(habit, '2026-10-19'), 20);
  assert.equal(habitCompleteOn(habit, '2026-10-26'), false);
  assert.equal(habitStreak(habit, '2026-10-26'), 3);
  assert.equal(habitBestStreak(habit, '2026-10-26'), 3);
  const completed = {
    ...habit,
    completedDates: [...habit.completedDates, '2026-10-26'],
    progressByDate: { '2026-10-26': 20 },
  };
  assert.equal(habitStreak(completed, '2026-10-26'), 4);
  assert.equal(
    habitStreak({ ...habit, completedDates: ['2026-10-19', '2026-10-23'] }, '2026-10-26'),
    1,
  );
});

test('scheduled streaks skip rest days and milestones are earned only once', () => {
  assert.equal(
    habitInputSchema.safeParse({ title: 'Read', weekdays: [1, 1], target: 20 }).success,
    false,
  );
  assert.equal(
    habitInputSchema.safeParse({ title: 'Read', weekdays: [1], target: 0 }).success,
    false,
  );
  const habit = {
    title: 'Read',
    id: 'test',
    startDate: '2026-10-19',
    weekdays: [1, 4],
    target: 3,
    completedDates: ['2026-10-19', '2026-10-22'],
    progressByDate: { '2026-10-19': 3, '2026-10-22': 3 },
    achievements: [],
    createdAt: '',
    updatedAt: '',
  } satisfies Habit;
  assert.equal(serverHabitBestStreak(habit), 2);
  assert.throws(
    () => assertHabitDay(habit, '2026-10-20', '2026-10-26'),
    (e: unknown) => e instanceof Error && 'code' in e && e.code === 'HABIT_DAY_UNSCHEDULED',
  );
  const completed = updateHabitProgress(habit, '2026-10-26', 3);
  assert.equal(serverHabitBestStreak(completed), 3);
  assert.deepEqual(completed.achievements, [3]);
  const cancelled = updateHabitProgress(completed, '2026-10-26', 0);
  assert.equal(serverHabitBestStreak(cancelled), 2);
  assert.deepEqual(cancelled.achievements, [3]);
  assert.deepEqual(updateHabitProgress(cancelled, '2026-10-26', 3).achievements, [3]);
});

test('schedule and archive edits preserve earlier eligible days and replace same-day periods', () => {
  const original = {
    id: 'timeline-test',
    title: 'Read',
    startDate: '2026-10-19',
    weekdays: [1, 3, 5],
    completedDates: ['2026-10-19', '2026-10-21', '2026-10-23'],
    createdAt: '',
    updatedAt: '',
  } satisfies Habit;
  const archived = updateHabitDefinition(original, { title: 'Read', archived: true }, '2026-10-26');
  assert.deepEqual(archived.periods, [
    { from: '2026-10-19', weekdays: [1, 3, 5], archived: false },
    { from: '2026-10-26', weekdays: [1, 3, 5], archived: true },
  ]);
  assert.equal(isHabitScheduled(archived, '2026-10-23'), true);
  assert.equal(isHabitScheduled(archived, '2026-10-26'), false);
  assert.equal(serverHabitBestStreak(archived), 3);

  const rescheduled = updateHabitDefinition(
    original,
    { title: 'Read', weekdays: [2, 4] },
    '2026-10-26',
  );
  assert.equal(isHabitScheduled(rescheduled, '2026-10-23'), true);
  assert.equal(isHabitScheduled(rescheduled, '2026-10-27'), true);
  assert.equal(isHabitScheduled(rescheduled, '2026-10-28'), false);
  assert.equal(serverHabitBestStreak(rescheduled), 3);
  const changedAgain = updateHabitDefinition(
    rescheduled,
    { title: 'Read', weekdays: [0, 6] },
    '2026-10-26',
  );
  assert.equal(changedAgain.periods?.length, 2);
  assert.deepEqual(changedAgain.periods?.[1], {
    from: '2026-10-26',
    weekdays: [0, 6],
    archived: false,
  });
});

test('quantity progress, archive and history persist in SQLite', () => {
  const directory = mkdtempSync(join(tmpdir(), 'ritm-habits-progress-'));
  try {
    const first = new Store(directory, false);
    const today = first.createHabit({ title: 'Read', target: 3, unit: 'pages' });
    const weekday = new Date(`${today.startDate}T12:00:00Z`).getUTCDay();
    const scheduled = first.updateHabit(
      today.id,
      { title: 'Read', weekdays: [weekday], target: 3, unit: 'pages' },
      today.updatedAt,
    );
    assert.throws(
      () => first.setHabitProgress(today.id, today.startDate, 4, scheduled.updatedAt),
      (e: unknown) => e instanceof Error && 'code' in e && e.code === 'HABIT_PROGRESS_INVALID',
    );
    const partial = first.setHabitProgress(today.id, today.startDate, 2, scheduled.updatedAt);
    assert.deepEqual(partial.completedDates, []);
    assert.equal(
      first.setHabitProgress(today.id, today.startDate, 2, partial.updatedAt).updatedAt,
      partial.updatedAt,
    );
    const complete = first.setHabitProgress(today.id, today.startDate, 3, partial.updatedAt);
    assert.deepEqual(complete.completedDates, [today.startDate]);
    const higherGoal = first.updateHabit(
      today.id,
      { title: 'Read', target: 4 },
      complete.updatedAt,
    );
    assert.deepEqual(higherGoal.completedDates, [today.startDate]);
    assert.equal(higherGoal.progressByDate?.[today.startDate], 3);
    const archived = first.updateHabit(
      today.id,
      { title: 'Read', archived: true },
      higherGoal.updatedAt,
    );
    assert.deepEqual(archived.periods, [
      { from: today.startDate, weekdays: [weekday], archived: true },
    ]);
    assert.throws(
      () => first.setHabitProgress(today.id, today.startDate, 4, archived.updatedAt),
      (e: unknown) => e instanceof Error && 'code' in e && e.code === 'HABIT_ARCHIVED',
    );
    first.close();
    const second = new Store(directory, false);
    assert.equal(second.habits()[0].progressByDate?.[today.startDate], 3);
    assert.equal(second.habits()[0].archived, true);
    assert.deepEqual(second.habits()[0].periods, archived.periods);
    second.close();
  } finally {
    assert.ok(resolve(directory).startsWith(resolve(tmpdir()) + sep));
    rmSync(directory, { recursive: true, force: true });
  }
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
  const quantified = await call('/habits', 'POST', {
    title: 'Read',
    icon: 'book',
    target: 8,
    unit: 'pages',
  });
  assert.equal(quantified.status, 201);
  const reading = (await quantified.json()).habit as Habit;
  assert.equal(
    (
      await call(`/habits/${reading.id}/days/${reading.startDate}/progress`, 'PATCH', {
        count: 9,
        expectedUpdatedAt: reading.updatedAt,
      })
    ).status,
    400,
  );
  const progress = await call(`/habits/${reading.id}/days/${reading.startDate}/progress`, 'PATCH', {
    count: 8,
    expectedUpdatedAt: reading.updatedAt,
  });
  assert.equal(progress.status, 200);
  assert.deepEqual(((await progress.json()).habit as Habit).completedDates, [reading.startDate]);
});
