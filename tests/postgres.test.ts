import test, { type TestContext } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import type { Pool, PoolClient } from 'pg';
import { DataType, newDb } from 'pg-mem';
import { PostgresStore } from '../server/postgres-store.ts';
import { migrate } from '../migrations/migrate.ts';
import { AppError } from '../server/errors.ts';
import { MAX_WORKSPACE_BYTES, googleTransferKey } from '../server/repository.ts';
import type { ChatMessage, TaskInput, GoogleCalendarEvent } from '../shared/types.ts';

const base: TaskInput = {
  title: 'Подготовить презентацию',
  description: '',
  date: '2099-10-14',
  time: '11:00',
  duration: 60,
  priority: 'high',
  repeat: 'none',
  kind: 'task',
  completed: false,
};
function assistant(): ChatMessage {
  return {
    id: randomUUID(),
    role: 'assistant',
    text: 'Вот предложенный план.',
    steps: [],
    proposals: [],
    createdAt: new Date().toISOString(),
  };
}
const transferredEvent: GoogleCalendarEvent = {
  id: 'testgoogleevent',
  source: 'google',
  calendarId: 'primary',
  title: base.title,
  description: '',
  etag: '"v1"',
  start: { dateTime: '2099-10-14T06:00:00Z' },
  end: { dateTime: '2099-10-14T07:00:00Z' },
  timeZone: 'Asia/Qyzylorda',
  allDay: false,
  busy: true,
  readOnly: false,
};

/**
 * SQL/contract emulator, NOT PostgreSQL or Neon. pg-mem does not implement real
 * advisory locks or transaction rollback. The fixture adds serial snapshot
 * restoration solely to verify that repository failures issue ROLLBACK.
 * Real concurrent isolation remains a release gate against actual PostgreSQL.
 */
async function fixture(t: TestContext) {
  // pg-mem reports unused CREATE TABLE constraints when IF NOT EXISTS skips
  // an existing table. PostgreSQL correctly treats that statement as a no-op.
  const db = newDb({ autoCreateForeignKeyIndices: true, noAstCoverageCheck: true });
  db.public.registerFunction({
    name: 'pg_advisory_xact_lock',
    args: [DataType.integer],
    returns: DataType.integer,
    implementation: () => 0,
    impure: true,
  });
  const adapter = db.adapters.createPg();
  const raw = new adapter.Pool() as unknown as Pool;
  const applied = await migrate(raw);
  let now = Date.parse('2026-10-13T06:00:00Z');
  let failQuery: ((text: string, values: unknown[]) => boolean) | undefined;
  const pool = {
    query: raw.query.bind(raw),
    end: raw.end.bind(raw),
    connect: async () => {
      const client = await raw.connect();
      let backup: ReturnType<typeof db.backup> | undefined;
      return {
        query: async (text: string, values: unknown[] = []) => {
          if (text === 'BEGIN') backup = db.backup();
          if (text === 'ROLLBACK') {
            backup?.restore();
            backup = undefined;
            return { rows: [], rowCount: 0 };
          }
          if (failQuery?.(text, values)) throw new Error('Injected storage failure');
          const result = await client.query(text, values);
          if (text === 'COMMIT') backup = undefined;
          return result;
        },
        release: () => client.release(),
      } as unknown as PoolClient;
    },
  } as unknown as Pool;
  const store = new PostgresStore(pool, { now: () => now });
  t.after(async () => {
    await raw.end();
  });
  return {
    store,
    db,
    raw,
    pool,
    applied,
    advance: (ms: number) => {
      now += ms;
    },
    now: () => now,
    injectFailure: (value?: typeof failQuery) => {
      failQuery = value;
    },
  };
}

test('pg-mem: explicit migrations are repeatable and do not overwrite settings', async (t) => {
  const h = await fixture(t);
  assert.deepEqual(h.applied, ['001-postgres.sql', '002-finance.sql']);
  await h.store.updateSettings({ displayName: 'Владелец', theme: 'light' });
  assert.deepEqual(await migrate(h.raw), []);
  assert.equal((await h.store.settings()).displayName, 'Владелец');
  const second = new PostgresStore(h.pool, { now: h.now });
  assert.equal((await second.settings()).theme, 'light');
  assert.deepEqual(await second.tasks(), []);
  assert.deepEqual(
    (await second.bootstrap({ configured: false, model: 'gpt-6-luna', source: 'none' }))
      .conversations,
    [],
  );
});

test('pg-mem: finance records persist separately from tasks and reject invalid changes', async (t) => {
  const { store } = await fixture(t);
  const income = await store.createFinanceEntry({
    type: 'income',
    amountMinor: 125050,
    currency: 'KZT',
    date: '2026-10-14',
    category: 'Salary',
    note: '',
  });
  const deposit = await store.createFinanceEntry({
    type: 'deposit',
    name: 'Savings',
    valueMinor: 700000,
    currency: 'USD',
    asOf: '2026-10-14',
    note: 'Manual valuation',
  });
  assert.equal((await store.financeEntries()).length, 2);
  assert.deepEqual(await store.tasks(), []);
  await assert.rejects(
    store.updateFinanceEntry(
      income.id,
      {
        type: 'expense',
        amountMinor: 1,
        currency: 'KZT',
        date: '2026-10-14',
        category: 'Other',
        note: '',
      },
      income.updatedAt,
    ),
    (error: unknown) => error instanceof AppError && error.code === 'FINANCE_TYPE_IMMUTABLE',
  );
  assert.equal(
    (await store.financeEntries()).find((entry) => entry.id === income.id)?.type,
    'income',
  );
  const revised = await store.updateFinanceEntry(
    deposit.id,
    {
      type: 'deposit',
      name: 'Savings',
      valueMinor: 750000,
      currency: 'USD',
      asOf: '2026-10-14',
      note: '',
    },
    deposit.updatedAt,
  );
  assert.equal(revised.type === 'deposit' ? revised.valueMinor : 0, 750000);
  await assert.rejects(
    store.updateFinanceEntry(
      deposit.id,
      {
        type: 'deposit',
        name: 'Stale',
        valueMinor: 1,
        currency: 'USD',
        asOf: '2026-10-14',
        note: '',
      },
      deposit.updatedAt,
    ),
    (error: unknown) => error instanceof AppError && error.status === 409,
  );
  await assert.rejects(
    store.deleteFinanceEntry(deposit.id, deposit.updatedAt),
    (error: unknown) => error instanceof AppError && error.status === 409,
  );
  assert.equal(
    (await store.financeEntries()).find((entry) => entry.id === deposit.id)?.updatedAt,
    revised.updatedAt,
  );
  await store.deleteFinanceEntry(income.id, income.updatedAt);
  assert.equal((await store.financeEntries()).length, 1);
});

test('pg-mem: restoring a task cannot bypass the quota and the rejected undo is retryable', async (t) => {
  const { store, db } = await fixture(t);
  const deleted = await store.deleteTask((await store.createTask(base)).id);
  const table = db.public.getTable('ritm_tasks');
  let one = '';
  for (let index = 0; index < 2000; index++) {
    const value = { ...deleted, id: randomUUID() };
    one = value.id;
    table.insert({ id: value.id, json: value });
  }
  await assert.rejects(
    store.restoreTask(deleted),
    (error: unknown) => error instanceof AppError && error.code === 'TASK_LIMIT',
  );
  assert.equal((await store.tasks()).length, 2000);
  await store.deleteTask(one);
  assert.equal((await store.restoreTask(deleted)).id, deleted.id);
  assert.equal((await store.tasks()).length, 2000);
});

test('pg-mem serial rollback fixture: over-budget chat is atomic and its request can be recovered', async (t) => {
  const { store } = await fixture(t);
  const request = randomUUID();
  const claim = await store.startRequest(request, 'fingerprint', null);
  const oversized = { ...assistant(), text: 'x'.repeat(MAX_WORKSPACE_BYTES) };
  await assert.rejects(
    store.finishChat(request, undefined, 'План', oversized, claim.leaseToken),
    (error: unknown) => error instanceof AppError && error.code === 'STORAGE_LIMIT',
  );
  assert.deepEqual(await store.conversations(), []);
  assert.equal((await store.request(request))?.status, 'running');
  await store.abandonRequest(request, claim.leaseToken);
  assert.equal(await store.request(request), undefined);
  const replacement = await store.startRequest(request, 'fingerprint', null);
  const completed = await store.finishChat(
    request,
    undefined,
    'План',
    assistant(),
    replacement.leaseToken,
  );
  assert.equal(completed.messages.length, 2);
  assert.equal((await store.request(request))?.status, 'complete');
});

test('pg-mem: legacy over-budget data stays deletable and rejected writes leave no changes', async (t) => {
  const { store, db, raw } = await fixture(t);
  const task = await store.createTask(base);
  const conversation = await store.createConversation();
  conversation.messages.push({ ...assistant(), text: 'x'.repeat(MAX_WORKSPACE_BYTES) });
  await raw.query('DELETE FROM ritm_conversations WHERE id=$1', [conversation.id]);
  db.public.getTable('ritm_conversations').insert({ id: conversation.id, json: conversation });
  const storageLimit = (error: unknown) =>
    error instanceof AppError && error.code === 'STORAGE_LIMIT';
  await assert.rejects(store.updateTask(task.id, { title: 'Изменённый план' }), storageLimit);
  assert.equal((await store.task(task.id)).title, base.title);
  await assert.rejects(store.createTask(base), storageLimit);
  assert.equal((await store.tasks()).length, 1);
  await assert.rejects(store.createConversation(), storageLimit);
  assert.equal((await store.conversations()).length, 1);
  await store.deleteTask(task.id);
  await store.deleteConversation(conversation.id);
  assert.equal((await store.createTask(base)).title, base.title);
});

test('pg-mem: SQL metacharacters in values never become query syntax', async (t) => {
  const { store } = await fixture(t);
  const title = "'); DROP TABLE ritm_tasks; --";
  const task = await store.createTask({ ...base, title, description: '<script>alert(1)</script>' });
  assert.equal((await store.task(task.id)).title, title);
  await assert.rejects(store.task("' OR 1=1 --"), /uuid/);
  assert.equal((await store.tasks()).length, 1);
});

test('pg-mem: task CRUD, occurrence completion, semantic restore and validation', async (t) => {
  const { store } = await fixture(t);
  const task = await store.createTask(base);
  assert.deepEqual(task.completedDates, []);
  const edited = await store.updateTask(task.id, { title: 'Проверить слайды' });
  assert.ok(edited.updatedAt > task.updatedAt);
  await assert.rejects(store.updateTask(task.id, { date: null }), /Задайте дату/);
  await assert.rejects(store.createTask({ ...base, date: '2099-02-30' }));
  const recurring = await store.createTask({ ...base, repeat: 'weekly' });
  await assert.rejects(store.updateTask(recurring.id, { completed: true }), AppError);
  await assert.rejects(
    store.updateTask(recurring.id, { completed: true, occurrenceDate: '2099-10-15' }),
    AppError,
  );
  const done = await store.updateTask(recurring.id, {
    completed: true,
    occurrenceDate: '2099-10-21',
  });
  assert.equal(done.completed, false);
  assert.deepEqual(done.completedDates, ['2099-10-21']);
  const deleted = await store.deleteTask(done.id);
  await assert.rejects(store.restoreTask({ ...deleted, title: 'Подменённое задание' }), AppError);
  // PostgreSQL JSONB can reorder object keys; restoring the same data must work.
  const reordered = Object.fromEntries(Object.entries(deleted).reverse()) as typeof deleted;
  const restored = await store.restoreTask(reordered);
  assert.deepEqual(restored.completedDates, ['2099-10-21']);
  await assert.rejects(store.restoreTask(reordered), AppError);
  assert.deepEqual(
    (await store.updateTask(restored.id, { completed: false, occurrenceDate: '2099-10-21' }))
      .completedDates,
    [],
  );
  await assert.rejects(
    store.updateSettings({ workDayStart: '18:00', workDayEnd: '09:00' }),
    AppError,
  );
});

test('pg-mem: durable request claims survive another repository instance and expire safely', async (t) => {
  const h = await fixture(t);
  const second = new PostgresStore(h.pool, { now: h.now });
  const conversation = await h.store.createConversation();
  const id = randomUUID();
  const claim = await h.store.startRequest(id, 'same-fingerprint', conversation.id);
  assert.ok(claim.leaseToken);
  assert.equal((await second.request(id))?.status, 'running');
  await assert.rejects(second.startRequest(id, 'same-fingerprint', conversation.id), AppError);
  await assert.rejects(
    second.startRequest(randomUUID(), 'other-fingerprint', conversation.id),
    AppError,
  );
  await assert.rejects(second.deleteConversation(conversation.id), AppError);
  h.advance(180_001);
  assert.equal(await second.request(id), undefined);
  await assert.rejects(second.startRequest(id, 'changed-fingerprint', conversation.id), AppError);
  const replacement = await second.startRequest(id, 'same-fingerprint', conversation.id);
  assert.ok(replacement.leaseToken);
  assert.notEqual(replacement.leaseToken, claim.leaseToken);
  await h.store.abandonRequest(id, claim.leaseToken);
  assert.equal((await second.request(id))?.status, 'running');
  await assert.rejects(
    h.store.finishChat(id, conversation.id, 'План', assistant(), claim.leaseToken),
    AppError,
  );
  const finished = await second.finishChat(
    id,
    conversation.id,
    'План',
    assistant(),
    replacement.leaseToken,
  );
  assert.equal(finished.messages.length, 2);
  const replay = await h.store.startRequest(id, 'same-fingerprint', conversation.id);
  assert.equal(replay.completedConversationId, conversation.id);
  assert.equal((await h.store.conversation(conversation.id)).messages.length, 2);
  await h.store.deleteConversation(conversation.id);
  assert.equal(await second.request(id), undefined);
});

test('pg-mem: request without existing conversation creates durable history only on finish', async (t) => {
  const { store } = await fixture(t);
  const id = randomUUID();
  const claim = await store.startRequest(id, 'fingerprint', null);
  assert.deepEqual(await store.conversations(), []);
  await assert.rejects(store.finishChat(id, undefined, 'Привет', assistant()), AppError);
  const conversation = await store.finishChat(
    id,
    undefined,
    'Привет',
    assistant(),
    claim.leaseToken,
  );
  assert.equal(conversation.title, 'Привет');
  assert.equal((await store.request(id))?.conversationId, conversation.id);
  await store.abandonRequest(id, claim.leaseToken);
  assert.equal((await store.request(id))?.status, 'complete');
});

test('pg-mem: shared sessions, bounded rate windows, single-use secrets and owner leases', async (t) => {
  const h = await fixture(t);
  const second = new PostgresStore(h.pool, { now: h.now });
  await h.store.createSession('token-hash', h.now() + 1000);
  assert.equal(await second.hasSession('token-hash'), true);
  await second.deleteSession('token-hash');
  assert.equal(await h.store.hasSession('token-hash'), false);
  await h.store.createSession('expiring', h.now() + 1000);
  const first = await h.store.consumeRateLimit('owner:chat', 2, 1000);
  assert.equal(first.allowed, true);
  assert.equal((await second.consumeRateLimit('owner:chat', 2, 1000)).allowed, true);
  const limited = await second.consumeRateLimit('owner:chat', 2, 1000);
  assert.equal(limited.allowed, false);
  assert.equal(limited.retryAfterMs, 1000);
  await h.store.setServerSecret('google:state', 'encrypted-envelope');
  assert.equal(await second.consumeServerSecret('google:state'), 'encrypted-envelope');
  assert.equal(await h.store.consumeServerSecret('google:state'), null);
  assert.equal(await h.store.getServerSecret('google:state'), null);
  const lease = await h.store.acquireLease('google:refresh', 1000);
  assert.ok(lease);
  assert.equal(await second.acquireLease('google:refresh', 1000), null);
  await second.releaseLease('google:refresh', randomUUID());
  assert.equal(await h.store.acquireLease('google:refresh', 1000), null);
  h.advance(1001);
  assert.equal(await second.hasSession('expiring'), false);
  assert.equal((await second.consumeRateLimit('owner:chat', 2, 1000)).allowed, true);
  const newer = await second.acquireLease('google:refresh', 1000);
  assert.ok(newer);
  assert.notEqual(newer, lease);
  await h.store.releaseLease('google:refresh', lease);
  assert.equal(await second.acquireLease('google:refresh', 1000), null);
  await second.releaseLease('google:refresh', newer);
  assert.ok(await h.store.acquireLease('google:refresh', 1000));
});

test('pg-mem: proposals validate whole plan, reject stale state and preserve manual edits', async (t) => {
  const h = await fixture(t);
  const one = await h.store.createTask(base);
  const two = await h.store.createTask({ ...base, title: 'Подготовить отчёт', time: '13:00' });
  const conversation = await h.store.createConversation();
  const message = assistant();
  message.proposals = [one, two].map((task, index) => ({
    id: randomUUID(),
    taskId: task.id,
    title: task.title,
    before: { date: task.date, time: task.time, duration: task.duration },
    after: { date: '2099-10-15', time: index ? '12:00' : '10:00', duration: task.duration },
    reason: 'Свободный интервал',
    status: 'pending',
    taskUpdatedAt: task.updatedAt,
  }));
  conversation.messages.push(message);
  await h.store.saveConversation(conversation);
  const ids = message.proposals.map((proposal) => proposal.id);
  await h.store.updateTask(two.id, { description: 'Изменено вручную' });
  await assert.rejects(h.store.proposalAction('apply', conversation.id, message.id, ids), AppError);
  assert.equal((await h.store.task(one.id)).date, base.date);
  await h.store.proposalAction('apply', conversation.id, message.id, [ids[0]]);
  assert.equal((await h.store.task(one.id)).time, '10:00');
  await h.store.updateTask(one.id, { time: '16:00' });
  await assert.rejects(
    h.store.proposalAction('undo', conversation.id, message.id, [ids[0]]),
    AppError,
  );
  assert.equal((await h.store.task(one.id)).time, '16:00');
  await h.store.proposalAction('reject', conversation.id, message.id, [ids[1]]);
  assert.equal(
    (await h.store.conversation(conversation.id)).messages[0].proposals[1].status,
    'rejected',
  );
});

test('pg-mem: event colors survive updates, another repository and restore without changing the schedule', async (t) => {
  const h = await fixture(t);
  const created = await h.store.createTask({ ...base, colorId: '9' });
  await h.store.updateTask(created.id, { colorId: '11' });
  const other = new PostgresStore(h.pool);
  const saved = await other.task(created.id);
  assert.equal(saved.colorId, '11');
  assert.equal(saved.time, base.time);
  assert.equal(saved.duration, base.duration);
  await other.updateTask(created.id, { title: 'Новое название' });
  assert.equal((await h.store.task(created.id)).colorId, '11');
  const deleted = await h.store.deleteTask(created.id);
  const restored = await h.store.restoreTask(deleted);
  assert.equal(restored.colorId, '11');
  assert.equal(restored.title, 'Новое название');
  await h.store.updateTask(created.id, { colorId: null });
  assert.equal((await other.task(created.id)).colorId, null);
  await assert.rejects(h.store.updateTask(created.id, { colorId: '99' }));
  assert.equal((await other.task(created.id)).colorId, null);
});

test('pg-mem: Google transfer receipts survive instances and replay only for the current connection', async (t) => {
  const h = await fixture(t),
    identity = 'a'.repeat(64);
  const task = await h.store.createTask({ ...base, colorId: '10', repeat: 'weekly' });
  const receipt = await h.store.beginGoogleTransfer(task.id, identity);
  assert.equal(receipt.task.repeat, 'weekly');
  assert.equal(receipt.task.colorId, '10');
  assert.equal(receipt.timeZone, 'Asia/Qyzylorda');
  await h.store.markGoogleTransferAttempt(task.id);
  const second = new PostgresStore(h.pool, { now: h.now });
  assert.equal((await second.googleTransfer(task.id))?.attempted, true);
  const result = await second.finishGoogleTransfer(task.id, transferredEvent, identity);
  assert.deepEqual(result, { event: transferredEvent, transferredTaskId: task.id });
  assert.deepEqual(await h.store.tasks(), []);
  const completed = await h.store.beginGoogleTransfer(task.id, identity);
  assert.equal(completed.status, 'complete');
  assert.deepEqual(completed.result, result);
  for (const action of [
    () => h.store.beginGoogleTransfer(task.id, 'b'.repeat(64)),
    () => h.store.finishGoogleTransfer(task.id, transferredEvent, 'b'.repeat(64)),
  ])
    await assert.rejects(
      action,
      (error: unknown) =>
        error instanceof AppError && error.code === 'GOOGLE_TRANSFER_CONNECTION_CHANGED',
    );
  await h.store.restoreTask(task);
  await assert.rejects(
    h.store.beginGoogleTransfer(task.id, identity),
    (error: unknown) => error instanceof AppError && error.status === 409,
  );
  assert.equal((await h.store.task(task.id)).id, task.id);
});

test('pg-mem serial rollback fixture: Google-confirmed transfer deletion and receipt are atomic', async (t) => {
  const h = await fixture(t),
    identity = 'a'.repeat(64),
    task = await h.store.createTask(base);
  await h.store.beginGoogleTransfer(task.id, identity);
  await h.store.markGoogleTransferAttempt(task.id);
  h.injectFailure(
    (text, values) =>
      text.startsWith('INSERT INTO ritm_config') &&
      values[0] === googleTransferKey(task.id) &&
      JSON.parse(values[1] as string).status === 'complete',
  );
  await assert.rejects(
    h.store.finishGoogleTransfer(task.id, transferredEvent, identity),
    /Injected storage failure/,
  );
  h.injectFailure();
  assert.equal((await h.store.task(task.id)).id, task.id);
  assert.equal((await h.store.googleTransfer(task.id))?.status, 'pending');
  await h.store.updateTask(task.id, { title: 'Новая редакция' });
  await assert.rejects(
    h.store.finishGoogleTransfer(task.id, transferredEvent, identity),
    (error: unknown) => error instanceof AppError && error.code === 'GOOGLE_TRANSFER_CHANGED',
  );
  assert.equal((await h.store.task(task.id)).title, 'Новая редакция');
});

test('pg-mem: completed Google receipts are bounded while uncertain deleted receipts retain identity', async (t) => {
  const h = await fixture(t),
    identity = 'a'.repeat(64),
    unknown = await h.store.createTask(base);
  const pending = await h.store.beginGoogleTransfer(unknown.id, identity);
  await h.store.markGoogleTransferAttempt(unknown.id);
  const snapshot = await h.store.deleteTask(unknown.id);
  const table = h.db.public.getTable('ritm_config');
  for (let index = 0; index < 101; index++) {
    const id = randomUUID();
    table.insert({
      key: googleTransferKey(id),
      json: {
        ...pending,
        status: 'complete',
        task: { ...pending.task, id },
        completedAt: new Date(h.now() + index).toISOString(),
        result: { event: transferredEvent, transferredTaskId: id },
      },
    });
  }
  const fresh = await h.store.createTask(base);
  await h.store.beginGoogleTransfer(fresh.id, identity);
  await h.store.finishGoogleTransfer(fresh.id, transferredEvent, identity);
  const rows = (
    await h.raw.query("SELECT json FROM ritm_config WHERE key LIKE 'google-transfer:%'")
  ).rows;
  assert.equal(rows.filter((row) => row.json.status === 'complete').length, 100);
  assert.equal((await h.store.googleTransfer(unknown.id))?.attempted, true);
  await h.store.restoreTask(snapshot);
  await assert.rejects(
    h.store.beginGoogleTransfer(unknown.id, 'b'.repeat(64)),
    (error: unknown) => error instanceof AppError && error.status === 409,
  );
});

test('pg-mem serial rollback fixture: a storage failure rolls back partial proposal writes', async (t) => {
  const h = await fixture(t);
  const one = await h.store.createTask(base);
  const two = await h.store.createTask({ ...base, time: '13:00' });
  const conversation = await h.store.createConversation();
  const message = assistant();
  message.proposals = [one, two].map((task, index) => ({
    id: randomUUID(),
    taskId: task.id,
    title: task.title,
    before: { date: task.date, time: task.time, duration: task.duration },
    after: { date: '2099-10-15', time: index ? '12:00' : '10:00', duration: task.duration },
    reason: 'Свободное время',
    status: 'pending',
    taskUpdatedAt: task.updatedAt,
  }));
  conversation.messages.push(message);
  await h.store.saveConversation(conversation);
  h.injectFailure(
    (text, values) => text.startsWith('INSERT INTO ritm_tasks') && values[0] === two.id,
  );
  await assert.rejects(
    h.store.proposalAction(
      'apply',
      conversation.id,
      message.id,
      message.proposals.map((proposal) => proposal.id),
    ),
    /Injected storage failure/,
  );
  h.injectFailure();
  assert.equal((await h.store.task(one.id)).date, base.date);
  assert.equal((await h.store.task(two.id)).date, base.date);
  assert.deepEqual(
    (await h.store.conversation(conversation.id)).messages[0].proposals.map(
      (proposal) => proposal.status,
    ),
    ['pending', 'pending'],
  );
});
