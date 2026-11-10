import test from 'node:test';
import assert from 'node:assert/strict';
import {
  addExercise,
  applyTo,
  canStepSession,
  changeFrom,
  finishSession,
  removeExercise,
  removeLastOpenSet,
  replaceExercise,
  startSession,
  stepSession,
  toggleSet,
  typeReps,
  typeWeight,
  type Session,
} from '../src/features/workouts/session.ts';
import {
  normalizedWeight,
  parseReps,
  parseWeight,
  stepReps,
  stepWeight,
} from '../src/features/workouts/numbers.ts';
import {
  WorkoutConflictNotice,
  WorkoutsClient,
  type WorkoutsTransport,
} from '../src/features/workouts/client.ts';
import type { WorkoutDoc, WorkoutsSnapshot } from '../shared/types.ts';
import type { Program, WorkoutRecord } from '../src/features/workouts/model.ts';

const program: Program = {
  id: 'P1',
  name: 'Грудь',
  colorIndex: 0,
  items: [
    { id: 'i1', exerciseID: 'builtin.bench', sets: 3, reps: 8, restSeconds: 120 },
    { id: 'i2', exerciseID: 'builtin.fly', sets: 2, reps: 12, restSeconds: 60 },
  ],
};
const history: WorkoutRecord[] = [
  {
    id: 'h1',
    programID: 'P1',
    programName: 'Грудь',
    startedAt: '2026-10-20T09:00:00Z',
    endedAt: '2026-10-20T10:00:00Z',
    exercises: [
      {
        exerciseID: 'builtin.bench',
        name: 'Жим лёжа',
        sets: [
          { weight: 80, reps: 8 },
          { weight: 82.5, reps: 6 },
        ],
      },
    ],
  },
];
const start = (): Session =>
  startSession(program, history, (id) => id, new Date('2026-10-29T10:00:00.456Z'))!;

test('typed numbers are cleaned like on the iPhone', () => {
  assert.equal(normalizedWeight('22,'), '22');
  assert.equal(normalizedWeight('.5'), '0.5');
  assert.equal(normalizedWeight('2,50'), '2,50');
  for (const bad of ['', '.', '2.5.', '12345', '1.234', 'a'])
    assert.equal(normalizedWeight(bad), null, bad);
  assert.equal(parseWeight('62,5'), 62.5);
  assert.equal(parseReps('0'), null);
  assert.equal(parseReps('1000'), null);
  assert.equal(stepWeight('0', -2.5), '0');
  assert.equal(stepWeight('60', 2.5), '62,5');
  assert.equal(stepReps('', -1), '1');
});

test('a workout starts as a snapshot prefilled from the last result, with whole-second dates', () => {
  const session = start();
  assert.equal(session.startedAt, '2026-10-29T10:00:00Z');
  const [bench, fly] = session.items;
  assert.deepEqual(
    bench.sets.map((s) => s.weight),
    ['80', '82.5', '82.5'],
  );
  assert.deepEqual(
    bench.sets.map((s) => s.reps),
    ['8', '6', '6'],
  );
  assert.deepEqual(
    fly.sets.map((s) => [s.weight, s.reps]),
    [
      ['', '12'],
      ['', '12'],
    ],
  );
  assert.ok(session.items.every((item) => item.sets.every((set) => !set.done)));
  assert.equal(
    startSession({ ...program, items: [] }, [], (id) => id, new Date()),
    null,
  );
});

test('the leading weight fills the other open sets, edited ones keep their own', () => {
  let session = start();
  const [a, b, c] = session.items[0].sets;
  session = typeWeight(session, session.items[0].id, b.id, '90');
  assert.equal(session.items[0].sets[1].edited, true);
  session = typeWeight(session, session.items[0].id, a.id, '85');
  const sets = session.items[0].sets;
  assert.deepEqual(
    sets.map((s) => s.weight),
    ['85', '90', '85'],
  );
  assert.equal(sets[2].id, c.id);
  assert.equal(session.items[0].sharedWeight, '85');
});

test('ticking needs weight and reps, can be undone, and finishing keeps only done sets', () => {
  let session = start();
  const item = session.items[1];
  assert.equal(toggleSet(session, item.id, item.sets[0].id).result, 'needsWeight');
  session = typeWeight(session, item.id, item.sets[0].id, '16,');
  session = typeReps(session, item.id, item.sets[0].id, '');
  assert.equal(toggleSet(session, item.id, item.sets[0].id).result, 'needsReps');
  session = typeReps(session, item.id, item.sets[0].id, '12');
  const ticked = toggleSet(session, item.id, item.sets[0].id);
  assert.equal(ticked.result, 'done');
  assert.equal(ticked.session.items[1].sets[0].weight, '16');
  assert.equal(toggleSet(ticked.session, item.id, item.sets[0].id).result, 'undone');
  const record = finishSession(ticked.session, new Date('2026-10-29T11:00:00.999Z'))!;
  assert.deepEqual(record.exercises, [
    { exerciseID: 'builtin.fly', name: 'builtin.fly', sets: [{ weight: 16, reps: 12 }] },
  ]);
  assert.equal(record.endedAt, '2026-10-29T11:00:00Z');
  assert.equal(finishSession(start(), new Date()), null);
});

test('editing the plan during a workout never drops done sets', () => {
  let session = start();
  const bench = session.items[0];
  session = toggleSet(session, bench.id, bench.sets[0].id).session;
  assert.equal(session.items[0].sets[0].done, true);
  assert.equal(canStepSession(session.items[0], 'sets', -1), true);
  session = stepSession(session, bench.id, 'sets', -1);
  session = stepSession(session, bench.id, 'sets', -1);
  assert.equal(session.items[0].sets.length, 1);
  assert.equal(canStepSession(session.items[0], 'sets', -1), false);
  session = stepSession(session, bench.id, 'reps', 1);
  assert.equal(session.items[0].plannedReps, 9);
  assert.equal(removeLastOpenSet(session, bench.id).items[0].sets.length, 1);
});

test('replace keeps done sets under the old exercise; add and remove respect the rules', () => {
  let session = start();
  const bench = session.items[0];
  session = toggleSet(session, bench.id, bench.sets[0].id).session;
  const replaced = replaceExercise(
    session,
    bench.id,
    'builtin.incline',
    'Жим на наклонной',
    history,
  )!;
  assert.equal(replaced.session.items[0].keptForLog, true);
  assert.equal(replaced.session.items[0].sets.length, 1);
  assert.equal(replaced.session.items[1].exerciseID, 'builtin.incline');
  assert.equal(
    replaceExercise(session, bench.id, 'builtin.fly', 'x', history),
    null,
    'already in the workout',
  );
  assert.equal(addExercise(session, 'builtin.fly', 'x', history), null);
  const added = addExercise(session, 'builtin.dips', 'Брусья', history, 0)!;
  assert.equal(added.session.items[1].exerciseID, 'builtin.dips');
  assert.equal(added.session.items[1].sets.length, 3);
  let single: Session = { ...session, items: [session.items[0]] };
  single = removeExercise(single, single.items[0].id);
  assert.equal(single.items.length, 1, 'a workout keeps at least one exercise');
});

test('the program diff and «save to program» match the iPhone', () => {
  let session = start();
  assert.equal(changeFrom(session, program), null);
  session = stepSession(session, session.items[0].id, 'rest', 1);
  session = addExercise(session, 'builtin.dips', 'Брусья', history)!.session;
  session = removeExercise(session, session.items[1].id);
  assert.deepEqual(changeFrom(session, program), {
    added: 1,
    removed: 1,
    modified: 1,
    reordered: false,
  });
  const applied = applyTo(session, program);
  assert.deepEqual(
    applied.items.map((i) => i.exerciseID),
    ['builtin.bench', 'builtin.dips'],
  );
  assert.equal(applied.items[0].id, 'i1', 'an existing item keeps its id');
  assert.equal(applied.items[0].restSeconds, 135);
  assert.equal(applied.name, 'Грудь');
});

// --- server documents and the 409 rule --------------------------------------------------------
const doc = (id: string, updatedAt: string, data: Record<string, unknown> = {}): WorkoutDoc => ({
  id,
  updatedAt,
  data,
});
function fake(snapshot: WorkoutsSnapshot, failWith?: number) {
  const calls: string[] = [];
  let loads = 0;
  let current = snapshot;
  const transport: WorkoutsTransport = {
    async load() {
      loads++;
      return current;
    },
    async put(kind, id, data, expected) {
      calls.push(`PUT ${kind}/${id} ${expected}`);
      if (failWith) throw Object.assign(new Error('x'), { status: failWith });
      return doc(id, '2026-10-29T10:00:01.000Z', data);
    },
    async remove(kind, id, expected) {
      calls.push(`DELETE ${kind}/${id} ${expected}`);
      if (failWith) throw Object.assign(new Error('x'), { status: failWith });
    },
  };
  return {
    transport,
    calls,
    loads: () => loads,
    serve: (next: WorkoutsSnapshot) => (current = next),
  };
}
const programDoc = doc('P1', '2026-10-29T09:00:00.000Z', {
  name: 'Грудь',
  colorIndex: 1,
  order: 0,
  items: [],
  exercises: [],
});
const snapshot = (programs: WorkoutDoc[] = [programDoc]): WorkoutsSnapshot => ({
  programs,
  sessions: [],
  records: [],
  settings: [],
});

test('writes carry the last seen version; new docs carry null', async () => {
  const f = fake(snapshot());
  const client = new WorkoutsClient(f.transport);
  await client.load();
  const renamed = { ...client.state.programs[0], name: 'Грудь+' };
  await client.saveProgramList([renamed, { id: 'NEW', name: 'Ноги', colorIndex: 0, items: [] }]);
  assert.deepEqual(f.calls, ['PUT programs/P1 2026-10-29T09:00:00.000Z', 'PUT programs/NEW null']);
  assert.equal(client.state.programs[1].name, 'Ноги');
  await client.saveProgramList([renamed]);
  assert.equal(f.calls.at(-1), 'DELETE programs/NEW 2026-10-29T10:00:01.000Z');
});

test('a 409 reloads the snapshot, tells the caller, and never retries on its own', async () => {
  const f = fake(snapshot(), 409);
  const client = new WorkoutsClient(f.transport);
  await client.load();
  f.serve(
    snapshot([
      doc('P1', '2026-10-29T09:30:00.000Z', {
        name: 'С телефона',
        colorIndex: 1,
        order: 0,
        items: [],
      }),
    ]),
  );
  await assert.rejects(
    client.saveProgramList([{ ...client.state.programs[0], name: 'С сайта' }]),
    WorkoutConflictNotice,
  );
  assert.equal(f.calls.length, 1, 'no automatic second attempt');
  assert.equal(f.loads(), 2);
  assert.equal(
    client.state.programs[0].name,
    'С телефона',
    'the phone version is shown after the reload',
  );
});

test('settings doc is removed while everything is default; other errors are not hidden', async () => {
  const f = fake({
    ...snapshot(),
    settings: [doc('workouts', '2026-10-29T08:00:00.000Z', { linkedHabitID: 'h' })],
  });
  const client = new WorkoutsClient(f.transport);
  await client.load();
  assert.equal(client.state.settings.linkedHabitID, 'h');
  await client.saveSettings({ linkedHabitID: null, lastTickedDay: null });
  assert.equal(f.calls[0], 'DELETE settings/workouts 2026-10-29T08:00:00.000Z');
  const broken = new WorkoutsClient(fake(snapshot(), 500).transport);
  await broken.load();
  await assert.rejects(
    broken.saveBest({
      exerciseID: 'builtin.bench',
      name: 'b',
      weight: 1,
      reps: 1,
      date: '2026-10-29T00:00:00Z',
      deleted: false,
    }),
    /x/,
  );
});
