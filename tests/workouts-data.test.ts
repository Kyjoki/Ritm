import test from 'node:test';
import assert from 'node:assert/strict';
import {
  readBest,
  readProgram,
  readRecord,
  readSettings,
  writeBest,
  writeProgram,
  writeRecord,
  writeSettings,
} from '../src/features/workouts/codec.ts';
import {
  dateKey,
  toWireDate,
  weekKeys,
  weekStart,
  zonedNoon,
} from '../src/features/workouts/dates.ts';
import {
  bestSetIndex,
  derivedRecords,
  recordSets,
  recordUpdates,
  recordVolume,
  resolveRecords,
  streakWeeks,
  volumeTrend,
  weekState,
  weeklyGoal,
} from '../src/features/workouts/stats.ts';
import {
  builtinID,
  newId,
  recordDocId,
  type Best,
  type WorkoutRecord,
} from '../src/features/workouts/model.ts';
import {
  nextProgram,
  saveDraft,
  stepItem,
  draftOf,
  moving,
} from '../src/features/workouts/library.ts';
import type { Habit } from '../shared/types.ts';

const ZONE = 'Asia/Qyzylorda';
const record = (
  id: string,
  endedAt: string,
  sets: Array<[number, number]>,
  programID = 'p1',
  exerciseID = builtinID('bench'),
): WorkoutRecord => ({
  id,
  programID,
  programName: 'Грудь',
  startedAt: endedAt,
  endedAt,
  exercises: [
    { exerciseID, name: 'Жим лёжа', sets: sets.map(([weight, reps]) => ({ weight, reps })) },
  ],
});

test('program doc keeps the iPhone shape, unknown keys and order', () => {
  const raw = {
    id: 'ignored',
    name: 'Спина',
    colorIndex: 9,
    order: 2,
    extra: 'keep',
    items: [
      { id: 'i1', exerciseID: 'builtin.row', sets: 99, reps: 0, restSeconds: 5 },
      { bad: true },
    ],
    exercises: [
      { id: 'custom.A', name: 'Т-гриф', muscle: 'back' },
      { id: 'custom.B', name: 'X' },
    ],
  };
  const read = readProgram('P-1', raw)!;
  assert.equal(read.program.id, 'P-1');
  assert.equal(read.program.colorIndex, 5, 'colour is clamped');
  assert.deepEqual(read.program.items, [
    { id: 'i1', exerciseID: 'builtin.row', sets: 10, reps: 1, restSeconds: 15 },
  ]);
  assert.equal(read.order, 2);
  assert.deepEqual(read.exercises[1], { id: 'custom.B', name: 'X', muscle: null });
  const written = writeProgram(read.program, 4, read.exercises, raw);
  assert.equal(written.extra, 'keep');
  assert.equal(written.order, 4);
  assert.deepEqual(written.exercises, [
    { id: 'custom.A', name: 'Т-гриф', muscle: 'back' },
    { id: 'custom.B', name: 'X', muscle: null },
  ]);
});

test('records, bests and settings docs round-trip', () => {
  const finished = record('R1', '2026-10-29T10:00:00Z', [[80, 8]]);
  assert.deepEqual(readRecord('R1', writeRecord(finished)), finished);
  assert.equal(readRecord('R1', { endedAt: 'nonsense' }), null);
  const best: Best = {
    exerciseID: 'builtin.bench',
    name: 'Жим лёжа',
    weight: 82.5,
    reps: 5,
    date: '2026-10-29T10:00:00Z',
    deleted: false,
  };
  assert.deepEqual(readBest(writeBest(best)), best);
  assert.equal(recordDocId('builtin.bench'), 'rec-builtin-bench');
  assert.deepEqual(writeSettings({ linkedHabitID: null, lastTickedDay: null }), {});
  assert.deepEqual(writeSettings({ linkedHabitID: 'h', lastTickedDay: '2026-10-29' }), {
    linkedHabitID: 'h',
    lastTickedDay: '2026-10-29',
  });
  assert.deepEqual(readSettings({ linkedHabitID: 5 }), {
    linkedHabitID: null,
    lastTickedDay: null,
  });
});

test('dates written for the iPhone have no milliseconds and ids pass the server rule', () => {
  assert.equal(toWireDate(new Date('2026-10-29T10:00:00.123Z')), '2026-10-29T10:00:00Z');
  assert.match(newId(), /^[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}$/);
  assert.match(newId(), /^[A-Za-z0-9_-]{1,64}$/);
});

test('weeks start on Sunday and a date key follows the account zone', () => {
  assert.equal(weekStart('2026-10-29'), '2026-10-25');
  assert.deepEqual(weekKeys('2026-10-29').slice(0, 2), ['2026-10-25', '2026-10-26']);
  assert.equal(weekStart('2026-10-25'), '2026-10-25');
  assert.equal(dateKey('2026-10-29T20:30:00Z', ZONE), '2026-10-30');
  assert.equal(dateKey('2026-10-29T20:30:00Z', 'UTC'), '2026-10-29');
  for (const zone of [ZONE, 'America/Los_Angeles', 'Pacific/Auckland', 'UTC'])
    assert.equal(dateKey(zonedNoon('2026-03-29', zone), zone), '2026-03-29', zone);
});

test('week volume, trend against the whole last week and the weekly streak', () => {
  const history = [
    record('a', '2026-10-27T10:00:00Z', [[100, 10]]),
    record('b', '2026-10-20T10:00:00Z', [[50, 10]]),
    record('c', '2026-10-13T10:00:00Z', [[50, 10]]),
  ];
  const trend = volumeTrend(history, '2026-10-29', 'UTC');
  assert.deepEqual(trend, { volume: 1000, percent: 100 });
  assert.equal(volumeTrend(history, '2026-10-08', 'UTC').percent, null);
  assert.equal(streakWeeks(history, '2026-10-29', 'UTC'), 3);
  assert.equal(
    streakWeeks(history, '2026-11-05', 'UTC'),
    3,
    'the empty current week does not break it',
  );
  assert.equal(streakWeeks(history, '2026-11-12', 'UTC'), 0);
});

test('week ring: linked habit days and the goal of four without a habit', () => {
  const none = weekState(
    null,
    [record('a', '2026-10-27T10:00:00Z', [[1, 1]])],
    '2026-10-29',
    'UTC',
  );
  assert.equal(none.goal, 4);
  assert.equal(none.done, 1);
  assert.equal(none.days[2].isDone, true);
  const habit = {
    id: 'h',
    title: 'Gym',
    weekdays: [1, 3, 5],
    startDate: '2026-01-01',
    completedDates: ['2026-10-26', '2026-10-27'],
  } as unknown as Habit;
  const linked = weekState(habit, [], '2026-10-29', 'UTC');
  assert.equal(linked.goal, 3);
  assert.equal(linked.done, 1, 'only scheduled completed days count');
  assert.equal(weeklyGoal({ ...habit, weekdays: [] } as unknown as Habit), 1);
});

test('records: best set, derived, manual override, tombstone and beats', () => {
  assert.equal(
    bestSetIndex([
      { weight: 60, reps: 8 },
      { weight: 60, reps: 9 },
      { weight: 55, reps: 12 },
    ]),
    1,
  );
  const history = [
    record('old', '2026-10-01T10:00:00Z', [[70, 5]]),
    record('new', '2026-10-20T10:00:00Z', [
      [60, 8],
      [75, 3],
    ]),
  ];
  assert.equal(derivedRecords(history).get('builtin.bench')!.weight, 75);
  assert.deepEqual(recordSets(history[1], history), { 'builtin.bench': 1 });
  assert.deepEqual(recordSets(history[0], history), {}, 'a first lift has nothing to beat');
  const manual: Best = {
    exerciseID: 'builtin.bench',
    name: 'Жим лёжа',
    weight: 90,
    reps: 1,
    date: '2026-10-25T10:00:00Z',
    deleted: false,
  };
  assert.equal(resolveRecords(history, [manual])[0].weight, 90);
  assert.equal(resolveRecords(history, [{ ...manual, deleted: true }]).length, 0);
  const before = resolveRecords(history, []);
  const next = record('x', '2026-10-30T10:00:00Z', [[80, 2]]);
  const update = recordUpdates(next, before, []);
  assert.equal(update.beats[0].previousWeight, 75);
  assert.equal(update.changed[0].weight, 80);
  assert.equal(
    recordUpdates(record('y', '2026-10-30T10:00:00Z', [[70, 2]]), before, []).changed.length,
    0,
  );
  assert.equal(recordVolume(history[1]), 60 * 8 + 75 * 3);
});

test('program editing: draft steps stay in range, save keeps order, next program is the least recent', () => {
  let draft = { ...draftOf(), name: '  Ноги   и  плечи ' };
  assert.equal(saveDraft([], draft, 'p'), null, 'needs an exercise');
  draft = {
    ...draft,
    items: [{ id: 'i', exerciseID: 'builtin.squat', sets: 10, reps: 1, restSeconds: 15 }],
  };
  assert.equal(stepItem(draft, 'i', 'sets', 1).items[0].sets, 10);
  assert.equal(stepItem(draft, 'i', 'reps', -1).items[0].reps, 1);
  assert.equal(stepItem(draft, 'i', 'rest', 1).items[0].restSeconds, 30);
  const saved = saveDraft([], draft, 'p')!;
  assert.equal(saved[0].name, 'Ноги и плечи');
  assert.deepEqual(moving([1, 2, 3], 0, 2), [2, 3, 1]);
  const programs = [
    { id: 'a', name: 'A', items: [], colorIndex: 0 },
    { id: 'b', name: 'B', items: [], colorIndex: 1 },
  ];
  assert.equal(
    nextProgram(programs, [record('r', '2026-10-01T10:00:00Z', [[1, 1]], 'a')])!.id,
    'b',
  );
});
