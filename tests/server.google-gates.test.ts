import test from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { randomUUID } from 'node:crypto';
import type { AddressInfo } from 'node:net';
import type { Conversation, GoogleCalendarResult, Task, TaskInput } from '../shared/types.ts';
import { createApp, type AppOptions } from '../server/index.ts';
import { AppError } from '../server/errors.ts';
import { prepareAssistantInput, MAX_ASSISTANT_CONTEXT_CHARS } from '../server/assistant.ts';
import { defaultSettings } from '../server/store.ts';

test('connected Google snapshot reaches AI; confirmation checks fresh busy slots and never writes Google', async (t) => {
  const dataDir = mkdtempSync(join(tmpdir(), 'ritm-google-gates-'));
  let blocks = true,
    assertions = 0,
    snapshotRead = 0,
    writes = 0;
  const status = {
    configured: true,
    status: 'connected' as const,
    mode: 'readwrite' as const,
    calendarId: 'primary' as const,
    lastFetchedAt: null,
  };
  const google: NonNullable<AppOptions['googleService']> = {
    configuration: async () => ({
      configured: true,
      source: 'environment',
      clientId: 'test.apps.googleusercontent.com',
      hasClientSecret: true,
      redirectUri: 'https://ritm.example/api/integrations/google/callback',
    }),
    saveConfiguration: async () => {
      throw new Error('not in this scenario');
    },
    removeConfiguration: async () => {
      throw new Error('not in this scenario');
    },
    status: async () => status,
    connect: async () => {
      throw new Error('not in this scenario');
    },
    callback: async () => {
      throw new Error('not in this scenario');
    },
    listEvents: async ({ from, to, timeZone }) => {
      snapshotRead++;
      return {
        events: [],
        from,
        to,
        timeZone,
        fetchedAt: new Date().toISOString(),
        partial: false,
      };
    },
    createEvent: async () => {
      writes++;
      throw new Error('unexpected Google write');
    },
    updateEvent: async () => {
      writes++;
      throw new Error('unexpected Google write');
    },
    disconnect: async () => status,
    deleteEvent: async () => {
      throw new Error('unexpected Google deletion');
    },
    connectionIdentity: async () => 'a'.repeat(64),
    withConnectionIdentity: async (_identity, operation) => operation(() => {}),
    assertFreeSlots: async (slots) => {
      assertions++;
      assert.equal(slots.length, 1);
      if (blocks) throw new AppError(409, 'CONFLICT', 'Время занято в Google Calendar.');
    },
  };
  const instance = createApp({
    dataDir,
    seed: false,
    env: { NODE_ENV: 'test', OPENAI_API_KEY: 'sk-test-server-only-abcdefghijklmnopqrstuvwxyz' },
    googleService: google,
    assistant: async (context) => {
      assert.equal(context.googleCalendarStatus, 'connected');
      assert.ok(context.googleCalendar?.fetchedAt);
      assert.equal(context.googleCalendar?.timeZone, 'Asia/Qyzylorda');
      return {
        text: 'Предлагаю новое время; выберите изменение.',
        steps: [],
        proposals: [
          {
            taskId: context.tasks[0].id,
            date: '2099-10-15',
            time: '12:00',
            duration: 60,
            reason: 'Удобнее для концентрации',
          },
        ],
      };
    },
  });
  const server = instance.app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(async () => {
    server.closeAllConnections();
    await new Promise<void>((done) => server.close(() => done()));
    await instance.close();
    assert.ok(
      resolve(dataDir).startsWith(resolve(tmpdir())) && dataDir.includes('ritm-google-gates-'),
    );
    rmSync(dataDir, { recursive: true, force: true });
  });
  const call = async (path: string, body: unknown) => {
    const response = await fetch(
      'http://127.0.0.1:' + (server.address() as AddressInfo).port + '/api' + path,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      },
    );
    return { status: response.status, body: (await response.json()) as any };
  };
  const input: TaskInput = {
    title: 'Подготовить презентацию',
    description: '',
    date: '2099-10-14',
    time: '11:00',
    duration: 60,
    priority: 'normal',
    repeat: 'none',
    kind: 'task',
    completed: false,
  };
  const task = await instance.store.createTask(input);
  const chat = await call('/chat', { message: 'Спланируй день', requestId: randomUUID() });
  assert.equal(chat.status, 200);
  assert.equal(snapshotRead, 1);
  assert.equal(writes, 0);
  assert.equal((await instance.store.tasks()).length, 1);
  const message = chat.body.messages[1];
  const action = {
    conversationId: chat.body.id,
    messageId: message.id,
    proposalIds: [message.proposals[0].id],
  };
  assert.equal((await call('/proposals/apply', action)).status, 409);
  assert.equal((await instance.store.task(task.id)).date, input.date);
  assert.equal(
    (await instance.store.conversation(chat.body.id)).messages[1].proposals[0].status,
    'pending',
  );
  blocks = false;
  assert.equal((await call('/proposals/apply', action)).status, 200);
  assert.equal(assertions, 2);
  assert.equal(writes, 0);
  assert.equal((await instance.store.task(task.id)).date, '2099-10-15');
});

test('AI Google context is bounded, coverage labeled and event IDs are not editable task IDs', () => {
  const snapshot: GoogleCalendarResult = {
    from: '2026-10-13',
    to: '2026-10-27',
    timeZone: 'Asia/Qyzylorda',
    fetchedAt: '2026-10-13T09:00:00Z',
    partial: false,
    events: Array.from({ length: 500 }, (_, i) => ({
      id: 'google-event-' + i,
      source: 'google' as const,
      calendarId: 'primary' as const,
      title: 'Встреча '.repeat(50),
      description: 'private description'.repeat(500),
      etag: '"v1"',
      start: { dateTime: '2026-10-14T10:00:00+05:00' },
      end: { dateTime: '2026-10-14T11:00:00+05:00' },
      timeZone: 'Asia/Qyzylorda',
      allDay: false,
      busy: true,
      readOnly: true,
    })),
  };
  const input = prepareAssistantInput({
    apiKey: 'not-used',
    model: 'gpt-6-luna',
    settings: defaultSettings,
    tasks: [],
    message: 'Что сегодня?',
    googleCalendar: snapshot,
  });
  assert.ok(JSON.stringify(input).length <= MAX_ASSISTANT_CONTEXT_CHARS);
  assert.match(input.messages[0].content, /"calendarIntegration":"connected"/);
  assert.match(input.messages[0].content, /"partial":true/);
  assert.match(input.messages[0].content, /"eventsTotal":500/);
  assert.equal(input.messages[0].content.includes('google-event-'), false);
  assert.equal(input.messages[0].content.includes('private description'), false);
});

test('escaped Google titles share the complete budget with history, the full latest request and tasks', () => {
  const stamp = '2026-10-13T09:00:00Z';
  const conversation: Conversation = {
    id: randomUUID(),
    title: 'История',
    createdAt: stamp,
    updatedAt: stamp,
    messages: Array.from({ length: 40 }, (_, index) => ({
      id: randomUUID(),
      role: index % 2 ? 'assistant' : 'user',
      text: '"\\\n'.repeat(3000),
      proposals: [],
      steps: [],
      createdAt: stamp,
    })),
  };
  const snapshot: GoogleCalendarResult = {
    from: '2026-10-13',
    to: '2026-10-27',
    timeZone: 'Asia/Qyzylorda',
    fetchedAt: stamp,
    partial: false,
    events: Array.from({ length: 100 }, (_, index) => ({
      id: 'external-' + index,
      source: 'google',
      calendarId: 'primary',
      title: (index < 50 ? 'Свободно ' : 'Занято ') + '"'.repeat(160),
      description: '',
      etag: '"v1"',
      start: { dateTime: '2026-10-14T10:00:00+05:00' },
      end: { dateTime: '2026-10-14T11:00:00+05:00' },
      timeZone: 'Asia/Qyzylorda',
      allDay: false,
      busy: index >= 50,
      readOnly: true,
    })),
  };
  const tasks: Task[] = Array.from({ length: 400 }, (_, index) => ({
    id: randomUUID(),
    title: '"'.repeat(160),
    description: '\\"'.repeat(2000),
    date: '2026-10-14',
    time: '12:00',
    duration: 60,
    priority: 'high',
    repeat: 'none',
    kind: index ? 'task' : 'event',
    completed: false,
    completedDates: [],
    createdAt: stamp,
    updatedAt: stamp,
  }));
  for (const message of ['"'.repeat(6000), '"\\\0'.repeat(2000)]) {
    const input = prepareAssistantInput(
      {
        apiKey: 'never-in-context',
        model: 'unused',
        settings: defaultSettings,
        tasks,
        conversation,
        message,
        googleCalendar: snapshot,
      },
      new Date(stamp),
    );
    assert.ok(JSON.stringify(input).length <= MAX_ASSISTANT_CONTEXT_CHARS);
    assert.equal(input.messages.at(-1)?.content, message);
    const data = JSON.parse(
      input.messages[0].content.slice(input.messages[0].content.lastIndexOf('\n') + 1),
    );
    assert.equal(data.googleCalendar.from, snapshot.from);
    assert.equal(data.googleCalendar.to, snapshot.to);
    assert.equal(data.googleCalendar.fetchedAt, stamp);
    assert.equal(data.googleCalendar.timeZone, snapshot.timeZone);
    assert.equal(data.googleCalendar.eventsTotal, 100);
    assert.equal(data.googleCalendar.partial, true);
    assert.equal(data.googleCalendar.eventsIncluded, data.googleCalendar.events.length);
    assert.ok(data.googleCalendar.eventsIncluded < 100);
    assert.ok(data.googleCalendar.events.every((event: { busy: boolean }) => event.busy));
    assert.ok(data.tasks.length > 0 && data.tasks.length < tasks.length);
    assert.equal(data.tasks[0].kind, 'event');
    assert.equal(data.contextLimit.tasksOmitted, true);
    assert.equal(data.contextLimit.historyShortened, true);
    assert.equal(input.instructions.includes('never-in-context'), false);
  }
});
