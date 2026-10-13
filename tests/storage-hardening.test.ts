import test, { type TestContext } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, relative, isAbsolute } from 'node:path';
import { Store } from '../server/store.ts';
import { AppError } from '../server/errors.ts';
import { assertWorkspaceStorage, MAX_WORKSPACE_BYTES } from '../server/repository.ts';
import { settingsPatchSchema, taskInputSchema, taskPatchSchema } from '../server/validation.ts';
import type { ChatMessage, Conversation, TaskInput } from '../shared/types.ts';

const base: TaskInput = {
  title: 'Проверить план',
  description: '',
  date: null,
  time: null,
  duration: 30,
  priority: 'normal',
  repeat: 'none',
  kind: 'task',
  completed: false,
};
const limit = (code: string) => (error: unknown) =>
  error instanceof AppError && error.code === code;
const assistant = (text = 'План готов.'): ChatMessage => ({
  id: randomUUID(),
  role: 'assistant',
  text,
  steps: [],
  proposals: [],
  createdAt: new Date().toISOString(),
});

function fixture(t: TestContext) {
  const directory = mkdtempSync(join(tmpdir(), 'ritm-storage-test-'));
  let store = new Store(directory, false);
  const raw = new DatabaseSync(join(directory, 'ritm.sqlite'));
  t.after(() => {
    raw.close();
    store.close();
    const child = relative(tmpdir(), directory);
    assert.ok(
      !isAbsolute(child) && !child.startsWith('..') && child.startsWith('ritm-storage-test-'),
    );
    rmSync(directory, { recursive: true, force: true });
  });
  return {
    get store() {
      return store;
    },
    raw,
    reopen() {
      store.close();
      store = new Store(directory, false);
    },
  };
}

test('storage budget counts UTF-8 serialized bytes including escaping and accepts the exact boundary', () => {
  const conversation: Conversation = {
    id: randomUUID(),
    title: 'План',
    messages: [assistant('')],
    createdAt: '2026-10-13T00:00:00.000Z',
    updatedAt: '2026-10-13T00:00:00.000Z',
  };
  const overhead = Buffer.byteLength(
    JSON.stringify({ tasks: [], conversations: [conversation] }),
    'utf8',
  );
  conversation.messages[0].text = 'x'.repeat(MAX_WORKSPACE_BYTES - overhead - 4) + '🎵';
  assert.equal(
    Buffer.byteLength(JSON.stringify({ tasks: [], conversations: [conversation] }), 'utf8'),
    MAX_WORKSPACE_BYTES,
  );
  assert.doesNotThrow(() => assertWorkspaceStorage([], [conversation]));
  conversation.messages[0].text += '"'; // Serialized as two bytes, not one JS character.
  assert.throws(() => assertWorkspaceStorage([], [conversation]), limit('STORAGE_LIMIT'));
});

test('SQLite: restoring a deleted task cannot bypass the active task quota and rejected undo is retryable', (t) => {
  const h = fixture(t);
  const deleted = h.store.deleteTask(h.store.createTask(base).id);
  const insert = h.raw.prepare('INSERT INTO tasks(id,json) VALUES(?,?)');
  let one = '';
  h.raw.exec('BEGIN');
  for (let index = 0; index < 2000; index++) {
    const value = { ...deleted, id: randomUUID() };
    one = value.id;
    insert.run(value.id, JSON.stringify(value));
  }
  h.raw.exec('COMMIT');
  assert.throws(() => h.store.restoreTask(deleted), limit('TASK_LIMIT'));
  assert.equal(h.store.tasks().length, 2000);
  h.store.deleteTask(one);
  assert.equal(h.store.restoreTask(deleted).id, deleted.id);
  assert.equal(h.store.tasks().length, 2000);
});

test('SQLite: over-budget chat rolls back the new conversation and permits request recovery', (t) => {
  const { store } = fixture(t);
  const request = randomUUID();
  store.startRequest(request, 'fingerprint', null);
  assert.throws(
    () => store.finishChat(request, undefined, 'План', assistant('x'.repeat(MAX_WORKSPACE_BYTES))),
    limit('STORAGE_LIMIT'),
  );
  assert.deepEqual(store.conversations(), []);
  assert.equal(store.request(request)?.status, 'running');
  store.abandonRequest(request);
  assert.equal(store.request(request), undefined);
  store.startRequest(request, 'fingerprint', null);
  const completed = store.finishChat(request, undefined, 'План', assistant());
  assert.equal(completed.messages.length, 2);
  assert.equal(store.request(request)?.status, 'complete');
});

test('SQLite: over-budget legacy workspaces remain openable and deletable, failed writes leave no changes', (t) => {
  const h = fixture(t);
  const task = h.store.createTask(base);
  const conversation = h.store.createConversation();
  conversation.messages.push(assistant('x'.repeat(MAX_WORKSPACE_BYTES)));
  h.raw
    .prepare('UPDATE conversations SET json=? WHERE id=?')
    .run(JSON.stringify(conversation), conversation.id);
  const legacy = { ...task };
  delete (legacy as Partial<typeof legacy>).completedDates;
  h.raw.prepare('UPDATE tasks SET json=? WHERE id=?').run(JSON.stringify(legacy), task.id);
  h.reopen();
  assert.deepEqual(h.store.task(task.id).completedDates, []);
  assert.throws(
    () => h.store.updateTask(task.id, { title: 'Новое название' }),
    limit('STORAGE_LIMIT'),
  );
  assert.equal(h.store.task(task.id).title, base.title);
  assert.throws(() => h.store.createTask(base), limit('STORAGE_LIMIT'));
  assert.equal(h.store.tasks().length, 1);
  assert.throws(() => h.store.createConversation(), limit('STORAGE_LIMIT'));
  assert.equal(h.store.conversations().length, 1);
  assert.equal(h.store.deleteTask(task.id).id, task.id);
  assert.deepEqual(h.store.tasks(), []);
  h.store.deleteConversation(conversation.id);
  assert.equal(h.store.createTask(base).title, base.title);
});

test('SQLite SQL metacharacters remain data, and strict API schemas reject prototype keys', (t) => {
  const { store } = fixture(t);
  const title = "'); DROP TABLE tasks; --";
  const task = store.createTask({ ...base, title, description: '<script>alert(1)</script>' });
  assert.equal(store.task(task.id).title, title);
  assert.throws(() => store.task("' OR 1=1 --"), limit('NOT_FOUND'));
  assert.equal(store.tasks().length, 1);
  for (const key of ['__proto__', 'constructor', 'prototype']) {
    const malicious = JSON.parse(`{"${key}":{"ritmPolluted":true}}`);
    assert.equal(taskInputSchema.safeParse({ ...base, ...malicious }).success, false);
    assert.equal(taskPatchSchema.safeParse({ title: 'Название', ...malicious }).success, false);
    assert.equal(
      settingsPatchSchema.safeParse({ displayName: 'Максим', ...malicious }).success,
      false,
    );
  }
  assert.equal(({} as { ritmPolluted?: boolean }).ritmPolluted, undefined);
});
