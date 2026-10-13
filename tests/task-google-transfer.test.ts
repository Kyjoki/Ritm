import test, { type TestContext } from 'node:test';
import assert from 'node:assert/strict';
import { createHash, randomUUID } from 'node:crypto';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import type { GoogleCalendarEvent, GoogleEventInput, TaskInput } from '../shared/types.ts';
import { Store } from '../server/store.ts';
import { SqliteRuntimeState } from '../server/runtime-state.ts';
import { SecretStore } from '../server/secrets.ts';
import { AppError } from '../server/errors.ts';
import { createTaskGoogleTransfer } from '../server/task-google-transfer.ts';
import { googleZonedInstant, type GoogleCalendarService } from '../server/google-calendar.ts';

const base: TaskInput = {
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
const code = (value: string) => (error: unknown) =>
  error instanceof AppError && error.code === value;

function fixture(t: TestContext) {
  const dataDir = mkdtempSync(join(tmpdir(), 'ritm-google-transfer-'));
  const stores = [new Store(dataDir, false)],
    state = new SqliteRuntimeState(dataDir);
  const connections: DatabaseSync[] = [];
  const secrets = new SecretStore(dataDir, {}, state);
  const records = new Map<string, { fingerprint: string; event: GoogleCalendarEvent }>();
  const calls: {
    input: GoogleEventInput;
    id: string;
    timeZone: string;
    identity: string;
    transparency?: string;
  }[] = [];
  let identity = 'a'.repeat(64),
    clock = 0;
  const google: Pick<
    GoogleCalendarService,
    'createEvent' | 'connectionIdentity' | 'withConnectionIdentity'
  > = {
    connectionIdentity: async () => identity,
    withConnectionIdentity: async (expected, operation) => {
      const guard = () => {
        if (expected !== identity)
          throw new AppError(
            409,
            'GOOGLE_TRANSFER_CONNECTION_CHANGED',
            'Подключение Google изменилось.',
          );
      };
      guard();
      return operation(guard);
    },
    createEvent: async (input, id, options = {}) => {
      if (options.expectedConnectionIdentity !== identity)
        throw new AppError(
          409,
          'GOOGLE_TRANSFER_CONNECTION_CHANGED',
          'Подключение Google изменилось.',
        );
      const timeZone = options.timeZone!,
        key = identity + ':' + id;
      calls.push({
        input: structuredClone(input),
        id,
        timeZone,
        identity,
        transparency: options.transparency,
      });
      const fingerprint = JSON.stringify({ input, timeZone, transparency: options.transparency });
      const existing = records.get(key);
      if (existing) {
        if (existing.fingerprint !== fingerprint)
          throw new AppError(409, 'CONFLICT', 'Другой payload.');
        return structuredClone(existing.event);
      }
      const start = input.time ? googleZonedInstant(input.date, input.time, timeZone) : 0;
      const event: GoogleCalendarEvent = {
        id: createHash('sha256')
          .update('Ritm:' + id)
          .digest('hex'),
        source: 'google',
        calendarId: 'primary',
        title: input.title,
        description: input.description,
        etag: '"v1"',
        start: input.allDay ? { date: input.date } : { dateTime: new Date(start).toISOString() },
        end: input.allDay
          ? {
              date: new Date(Date.parse(input.date + 'T12:00:00Z') + 86400000)
                .toISOString()
                .slice(0, 10),
            }
          : { dateTime: new Date(start + input.duration * 60_000).toISOString() },
        timeZone,
        allDay: input.allDay,
        busy: options.transparency !== 'transparent',
        readOnly: false,
        ...(input.colorId ? { colorId: input.colorId } : {}),
        recurring: input.repeat !== 'none',
      };
      records.set(key, { fingerprint, event });
      return structuredClone(event);
    },
  };
  const runner = (store = stores[0]) =>
    createTaskGoogleTransfer({ store, leases: secrets, google, clock: () => clock });
  const reload = () => {
    const store = new Store(dataDir, false);
    stores.push(store);
    return runner(store);
  };
  t.after(() => {
    connections.forEach((connection) => connection.close());
    stores.forEach((store) => store.close());
    state.close();
    assert.ok(
      resolve(dataDir).startsWith(resolve(tmpdir())) && dataDir.includes('ritm-google-transfer-'),
    );
    rmSync(dataDir, { recursive: true, force: true });
  });
  return {
    store: stores[0],
    runner: runner(),
    reload,
    google,
    calls,
    records,
    dataDir,
    database: () => {
      const connection = new DatabaseSync(join(dataDir, 'ritm.sqlite'));
      connections.push(connection);
      return connection;
    },
    setIdentity: (value: string) => {
      identity = value;
    },
    advance: (ms: number) => {
      clock += ms;
    },
  };
}

test('migration uses fresh server data, confirms Google, removes local once and returns a durable receipt', async (t) => {
  const f = fixture(t),
    initial = f.store.createTask(base);
  const latest = f.store.updateTask(initial.id, { title: 'Gym: ноги', colorId: '3' });
  const result = await f.runner(initial.id);
  assert.equal(result.transferredTaskId, initial.id);
  assert.equal(result.event.title, latest.title);
  assert.equal(result.event.colorId, '3');
  assert.deepEqual(f.calls[0].input, {
    title: latest.title,
    description: latest.description,
    date: latest.date,
    time: latest.time,
    duration: latest.duration,
    allDay: false,
    colorId: '3',
    repeat: 'none',
  });
  assert.equal(f.calls[0].id, latest.id);
  assert.equal(f.calls[0].timeZone, 'Asia/Qyzylorda');
  assert.equal(f.calls[0].transparency, 'opaque');
  assert.equal(f.store.tasks().length, 0);
  assert.equal(f.records.size, 1);
  assert.deepEqual(await f.reload()(initial.id), result);
  assert.equal(f.calls.length, 1, 'A lost response/restart replays the committed receipt.');
  assert.deepEqual(Object.keys(result).sort(), ['event', 'transferredTaskId']);
  f.setIdentity('b'.repeat(64));
  await assert.rejects(f.runner(initial.id), code('GOOGLE_TRANSFER_CONNECTION_CHANGED'));
  assert.equal(
    f.calls.length,
    1,
    'A completed receipt never leaks into a different Google connection.',
  );
});

test('cached replay rechecks the connection after its database read to close reconnect races', async (t) => {
  const f = fixture(t),
    task = f.store.createTask(base);
  await f.runner(task.id);
  const begin = f.store.beginGoogleTransfer.bind(f.store);
  f.store.beginGoogleTransfer = (...args) => {
    const receipt = begin(...args);
    f.setIdentity('b'.repeat(64));
    return receipt;
  };
  await assert.rejects(f.runner(task.id), code('GOOGLE_TRANSFER_CONNECTION_CHANGED'));
  assert.equal(f.calls.length, 1);
  assert.equal(f.store.tasks().length, 0);
});

test('custom-color migration can gain explicit Google permission after a pre-create refusal', async (t) => {
  const f = fixture(t),
    task = f.store.createTask({ ...base, colorId: '#B71C50' });
  const create = f.google.createEvent;
  f.google.createEvent = async () => {
    throw new AppError(403, 'GOOGLE_EXTENDED_COLORS_REQUIRED', 'Разрешите новые цвета.');
  };
  await assert.rejects(f.runner(task.id), code('GOOGLE_EXTENDED_COLORS_REQUIRED'));
  assert.equal(f.store.task(task.id).colorId, '#b71c50');
  assert.equal(f.store.googleTransfer(task.id), undefined);
  assert.equal(f.records.size, 0);
  f.google.createEvent = create;
  f.setIdentity('b'.repeat(64));
  const result = await f.runner(task.id);
  assert.equal(result.event.colorId, '#b71c50');
  assert.equal(f.records.size, 1);
  assert.equal(f.store.tasks().length, 0);
});

test('unknown Google outcome keeps the original snapshot and stable request ID across retries', async (t) => {
  const f = fixture(t),
    task = f.store.createTask(base),
    create = f.google.createEvent;
  let first = true;
  f.google.createEvent = async (...args) => {
    const event = await create(...args);
    if (first) {
      first = false;
      throw new AppError(504, 'GOOGLE_TIMEOUT', 'Test-only lost response');
    }
    return event;
  };
  await assert.rejects(f.runner(task.id), code('GOOGLE_TIMEOUT'));
  assert.equal(f.store.task(task.id).title, task.title);
  assert.equal(f.store.googleTransfer(task.id)?.attempted, true);
  const result = await f.reload()(task.id);
  assert.equal(result.event.title, task.title);
  assert.equal(f.records.size, 1);
  assert.deepEqual(
    f.calls.map((call) => call.id),
    [task.id, task.id],
  );
  assert.deepEqual(f.calls[0].input, f.calls[1].input);
});

test('conditional deletion and receipt write roll back together and a retry never duplicates Google', async (t) => {
  const f = fixture(t),
    task = f.store.createTask(base),
    sql = f.database();
  sql.exec(`CREATE TRIGGER fail_transfer BEFORE UPDATE OF json ON config
    WHEN NEW.key LIKE 'google-transfer:%' AND json_extract(NEW.json,'$.status')='complete'
    BEGIN SELECT RAISE(FAIL,'test-only failure'); END;`);
  await assert.rejects(f.runner(task.id), code('GOOGLE_TRANSFER_PENDING'));
  assert.equal(f.store.task(task.id).id, task.id);
  assert.equal(f.store.googleTransfer(task.id)?.status, 'pending');
  assert.equal(f.records.size, 1);
  sql.exec('DROP TRIGGER fail_transfer');
  await f.reload()(task.id);
  assert.equal(f.store.tasks().length, 0);
  assert.equal(f.records.size, 1);
});

test('source edits, timezone changes and reconnects after Google creation never delete new local state', async (t) => {
  for (const change of ['task', 'timeZone', 'connection'] as const) {
    const f = fixture(t),
      task = f.store.createTask(base),
      create = f.google.createEvent;
    f.google.createEvent = async (...args) => {
      const event = await create(...args);
      if (change === 'task') f.store.updateTask(task.id, { title: 'Новые правки' });
      if (change === 'timeZone') f.store.updateSettings({ timeZone: 'UTC' });
      if (change === 'connection') f.setIdentity('b'.repeat(64));
      return event;
    };
    await assert.rejects(
      f.runner(task.id),
      code(
        change === 'connection' ? 'GOOGLE_TRANSFER_CONNECTION_CHANGED' : 'GOOGLE_TRANSFER_CHANGED',
      ),
    );
    assert.equal(f.store.tasks().length, 1);
    if (change === 'task') assert.equal(f.store.task(task.id).title, 'Новые правки');
    assert.equal(f.store.googleTransfer(task.id)?.status, 'pending');
    await assert.rejects(f.reload()(task.id));
    assert.equal(f.calls.length, 1);
  }
});

test('in-flight transfer has a shared lease and a late result cannot start local mutations', async (t) => {
  const f = fixture(t),
    task = f.store.createTask(base),
    create = f.google.createEvent;
  let reached!: () => void, release!: () => void;
  const barrier = new Promise<void>((done) => {
    reached = done;
  });
  const pause = new Promise<void>((done) => {
    release = done;
  });
  f.google.createEvent = async (...args) => {
    reached();
    await pause;
    return create(...args);
  };
  const pending = f.runner(task.id);
  await barrier;
  await assert.rejects(f.reload()(task.id), code('GOOGLE_TRANSFER_BUSY'));
  f.advance(45_001);
  release();
  await assert.rejects(pending, code('GOOGLE_TRANSFER_PENDING'));
  assert.equal(f.store.tasks().length, 1);
  assert.equal(f.store.googleTransfer(task.id)?.status, 'pending');
});

test('date-only records preserve free-time semantics; new series preserve repetition and completion history stays local', async (t) => {
  const f = fixture(t),
    allDay = f.store.createTask({ ...base, time: null });
  const result = await f.runner(allDay.id);
  assert.equal(result.event.allDay, true);
  assert.equal(result.event.busy, false);
  assert.equal(f.calls[0].transparency, 'transparent');
  for (const repeat of ['daily', 'weekly', 'monthly'] as const) {
    const task = f.store.createTask({ ...base, repeat });
    await f.runner(task.id);
    assert.equal(f.calls.at(-1)!.input.repeat, repeat);
  }
  const history = f.store.createTask({ ...base, repeat: 'daily' });
  f.store.updateTask(history.id, { completed: true, occurrenceDate: base.date! });
  await assert.rejects(f.runner(history.id), code('GOOGLE_TRANSFER_INELIGIBLE'));
  const completed = f.store.createTask({ ...base, completed: true });
  await assert.rejects(f.runner(completed.id), code('GOOGLE_TRANSFER_INELIGIBLE'));
  const undated = f.store.createTask({ ...base, date: null, time: null });
  await assert.rejects(f.runner(undated.id), code('GOOGLE_TRANSFER_INELIGIBLE'));
  assert.equal(f.store.tasks().length, 3);
});

test('successful receipts are bounded and uncertain deleted-task receipts survive cleanup and restore', async (t) => {
  const f = fixture(t),
    unknown = f.store.createTask(base);
  f.store.beginGoogleTransfer(unknown.id, 'a'.repeat(64));
  f.store.markGoogleTransferAttempt(unknown.id);
  const deleted = f.store.deleteTask(unknown.id);
  const ids: string[] = [];
  for (let index = 0; index < 101; index++) {
    const task = f.store.createTask(base);
    ids.push(task.id);
    await f.runner(task.id);
  }
  assert.equal(f.store.googleTransfer(ids[0]), undefined);
  assert.equal(f.store.googleTransfer(ids.at(-1)!)?.status, 'complete');
  assert.equal(f.store.googleTransfer(unknown.id)?.attempted, true);
  // Use a fresh uncertain deletion still within the bounded undo journal.
  const restorable = f.store.createTask(base);
  f.store.beginGoogleTransfer(restorable.id, 'a'.repeat(64));
  f.store.markGoogleTransferAttempt(restorable.id);
  const snapshot = f.store.deleteTask(restorable.id);
  const another = f.store.createTask(base);
  await f.runner(another.id);
  f.store.restoreTask(snapshot);
  f.setIdentity('b'.repeat(64));
  await assert.rejects(f.runner(restorable.id));
  assert.equal(f.store.googleTransfer(restorable.id)?.connectionIdentity, 'a'.repeat(64));
  assert.equal(deleted.id, unknown.id);
});

test('pending receipt quota blocks only new migrations and an existing uncertain request remains retryable', async (t) => {
  const f = fixture(t),
    existing = f.store.createTask(base);
  const receipt = f.store.beginGoogleTransfer(existing.id, 'a'.repeat(64));
  const sql = f.database();
  const insert = sql.prepare('INSERT INTO config(key,json) VALUES(?,?)');
  for (let index = 0; index < 999; index++) {
    const id = randomUUID();
    insert.run(
      'google-transfer:' + id,
      JSON.stringify({ ...receipt, attempted: true, task: { ...receipt.task, id } }),
    );
  }
  const newest = f.store.createTask(base);
  await assert.rejects(f.runner(newest.id), code('GOOGLE_TRANSFER_LIMIT'));
  assert.equal(f.store.googleTransfer(newest.id), undefined);
  assert.equal(f.calls.length, 0);
  await f.runner(existing.id);
  assert.equal(f.calls.length, 1);
  assert.equal(f.store.task(newest.id).id, newest.id);
});
