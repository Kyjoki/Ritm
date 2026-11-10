import test from 'node:test';
import assert from 'node:assert/strict';
import { readStored } from '../src/features/workouts/useActiveWorkout.ts';
import {
  saveFinishedWorkout,
  shouldTickHabit,
  tickLinkedHabit,
} from '../src/features/workouts/finish.ts';
import {
  EMPTY_STATE,
  WorkoutsClient,
  type WorkoutsTransport,
  type WorkoutsState,
} from '../src/features/workouts/client.ts';
import {
  startSession,
  stepSession,
  toggleSet,
  typeReps,
  typeWeight,
} from '../src/features/workouts/session.ts';
import type { Habit } from '../shared/types.ts';
import type { Program, WorkoutRecord } from '../src/features/workouts/model.ts';

const program: Program = {
  id: 'P1',
  name: 'Грудь',
  colorIndex: 0,
  items: [{ id: 'i1', exerciseID: 'builtin.bench', sets: 2, reps: 8, restSeconds: 120 }],
};
const earlier: WorkoutRecord = {
  id: 'old',
  programID: 'P1',
  programName: 'Грудь',
  startedAt: '2026-10-20T09:00:00Z',
  endedAt: '2026-10-20T10:00:00Z',
  exercises: [{ exerciseID: 'builtin.bench', name: 'Жим лёжа', sets: [{ weight: 70, reps: 8 }] }],
};
const state: WorkoutsState = { ...EMPTY_STATE, programs: [program], records: [earlier] };

function readySession(weight: string, extraRest = false) {
  let session = startSession(
    program,
    [earlier],
    () => 'Жим лёжа',
    new Date('2026-10-29T10:00:00Z'),
  )!;
  const item = session.items[0];
  session = typeWeight(session, item.id, item.sets[0].id, weight);
  session = typeReps(session, item.id, item.sets[0].id, '8');
  session = toggleSet(session, item.id, item.sets[0].id).session;
  if (extraRest) session = stepSession(session, item.id, 'rest', 1);
  return session;
}
const recorder = () => {
  const calls: string[] = [];
  const transport: WorkoutsTransport = {
    load: async () => ({ programs: [], sessions: [], records: [], settings: [] }),
    put: async (kind, id, data) => {
      calls.push(`${kind}/${id}`);
      return { id, updatedAt: '2026-10-29T10:00:01.000Z', data };
    },
    remove: async () => undefined,
  };
  return { calls, client: new WorkoutsClient(transport) };
};
const write = async <T>(job: () => Promise<T>) => job();

test('finishing stores the workout, the record it beat and optionally the edited program', async () => {
  const { calls, client } = recorder();
  await client.load();
  const session = readySession('75', true);
  const done = await saveFinishedWorkout({
    session,
    state,
    client,
    write,
    saveToProgram: true,
    now: new Date('2026-10-29T11:00:00Z'),
  });
  assert.ok(done);
  assert.equal(done.beats[0].previousWeight, 70);
  assert.equal(done.programSaved, true);
  assert.deepEqual(calls, [`sessions/${session.id}`, 'records/rec-builtin-bench']);
});

test('a failed write keeps the running workout: nothing is reported as finished', async () => {
  const { client } = recorder();
  const failing = async () => undefined;
  const done = await saveFinishedWorkout({
    session: readySession('75'),
    state,
    client,
    write: failing,
    saveToProgram: false,
    now: new Date(),
  });
  assert.equal(done, null);
  const nothing = await saveFinishedWorkout({
    session: startSession(program, [], () => 'x', new Date())!,
    state,
    client,
    write,
    saveToProgram: false,
    now: new Date(),
  });
  assert.equal(nothing, null, 'nothing ticked');
});

const habit = (over: Partial<Habit> = {}): Habit =>
  ({
    id: 'h1',
    title: 'Gym',
    startDate: '2026-01-01',
    completedDates: [],
    weekdays: [0, 1, 2, 3, 4, 5, 6],
    target: null,
    createdAt: '',
    updatedAt: '2026-10-01T00:00:00.000Z',
    ...over,
  }) as Habit;

test('the linked habit is ticked once a day, only when it can be marked and is not complete', () => {
  const settings = { linkedHabitID: 'h1', lastTickedDay: null };
  assert.equal(shouldTickHabit(habit(), settings, '2026-10-29'), true);
  assert.equal(
    shouldTickHabit(habit(), { ...settings, lastTickedDay: '2026-10-29' }, '2026-10-29'),
    false,
  );
  assert.equal(
    shouldTickHabit(habit({ completedDates: ['2026-10-29'] }), settings, '2026-10-29'),
    false,
  );
  assert.equal(shouldTickHabit(habit({ archived: true }), settings, '2026-10-29'), false);
  assert.equal(
    shouldTickHabit(habit({ weekdays: [1] }), settings, '2026-10-29'),
    false,
    'Thursday is not scheduled',
  );
  assert.equal(shouldTickHabit(habit({ id: 'other' }), settings, '2026-10-29'), false);
});

test('ticking reads habits fresh and sets the progress to the target with that version', async () => {
  const seen: Array<[string, string, number]> = [];
  const outcome = await tickLinkedHabit({
    settings: { linkedHabitID: 'h1', lastTickedDay: null },
    today: '2026-10-29',
    readHabits: async () => [habit({ target: 3, unit: 'x' })],
    setProgress: async (current, date, count) => {
      seen.push([current.updatedAt, date, count]);
      return { ...current, completedDates: [date] };
    },
  });
  assert.deepEqual(seen, [['2026-10-01T00:00:00.000Z', '2026-10-29', 3]]);
  assert.ok(outcome && 'habit' in outcome);
  const none = await tickLinkedHabit({
    settings: { linkedHabitID: null, lastTickedDay: null },
    today: '2026-10-29',
    readHabits: async () => assert.fail('no habit is linked'),
    setProgress: async () => assert.fail('no habit is linked'),
  });
  assert.equal(none, null);
});

test('a stored running workout is restored when valid and dropped when damaged', () => {
  const session = readySession('75');
  const stored = JSON.stringify({ session, rest: { endsAt: 5, length: 60 } });
  assert.equal(readStored(stored).session?.id, session.id);
  assert.deepEqual(readStored(stored).rest, { endsAt: 5, length: 60 });
  assert.deepEqual(readStored('{nope'), { session: null, rest: null });
  assert.equal(readStored(JSON.stringify({ session: { id: 'x', items: [] } })).session, null);
  assert.equal(readStored(null).session, null);
});
