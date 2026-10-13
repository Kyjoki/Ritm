import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import {
  createGoogleCalendarService,
  GOOGLE_CALLBACK_PATH,
  GOOGLE_CALENDAR_SCOPE,
  GOOGLE_CALENDAR_LABELS_SCOPE,
  GOOGLE_TASKS_SCOPE,
  normalizeGoogleTaskLink,
  type GoogleRequest,
  type GoogleSecretStorage,
} from '../server/google-calendar.ts';
import { AppError } from '../server/errors.ts';
import { defaultSettings } from '../server/store.ts';
const owner = 'a'.repeat(64),
  now = Date.parse('2026-10-13T05:00:00Z');
const link = 'https://tasks.google.com/task/opaqueTask';
const rawEvent = () => ({
  id: 'event12345',
  summary: 'Поговорить с Paul',
  description: `Измените задачу ${link}.`,
  eventType: 'focusTime',
  etag: '"event1"',
  start: { dateTime: '2026-10-13T05:00:00Z' },
  end: { dateTime: '2026-10-13T06:00:00Z' },
  organizer: { self: true },
  creator: { self: true },
});
class Secrets implements GoogleSecretStorage {
  values = new Map<string, string>();
  leases = new Map<string, string>();
  async getSecret(key: string) {
    return this.values.get(key) ?? null;
  }
  async saveSecret(key: string, value: string) {
    this.values.set(key, value);
  }
  async removeSecret(key: string) {
    this.values.delete(key);
  }
  async consumeSecret(key: string) {
    const value = await this.getSecret(key);
    this.values.delete(key);
    return value;
  }
  async acquireLease(key: string) {
    if (this.leases.has(key)) return null;
    const id = randomUUID();
    this.leases.set(key, id);
    return id;
  }
  async releaseLease(key: string, id: string) {
    if (this.leases.get(key) === id) this.leases.delete(key);
  }
}
function fixture() {
  const secrets = new Secrets(),
    requests: GoogleRequest[] = [];
  let scope = GOOGLE_CALENDAR_SCOPE,
    task = {
      id: 'task123',
      etag: '"task1"',
      webViewLink: link + '?sa=6',
      title: 'Поговорить с Paul',
      status: 'needsAction' as string,
      notes: 'Do not modify',
      due: '2026-10-13T00:00:00Z',
    },
    event = rawEvent(),
    duplicate = false,
    failTasks = false,
    conflictPatch = false,
    endless = false,
    duplicateMirror = false;
  const service = createGoogleCalendarService({
    secrets,
    settings: async () => defaultSettings,
    security: { hasOwnerSession: async (hash) => hash === owner },
    env: {
      GOOGLE_CLIENT_ID: '123-test.apps.googleusercontent.com',
      GOOGLE_CLIENT_SECRET: 'not-a-real-secret',
      GOOGLE_REDIRECT_URI: `http://127.0.0.1:5173${GOOGLE_CALLBACK_PATH}`,
    },
    now: () => now,
    transport: {
      exchangeCode: async () => ({
        access_token: 'test-access',
        refresh_token: 'test-refresh',
        expiry_date: now + 3600000,
        scope,
      }),
      refreshToken: async () => ({
        access_token: 'test-access',
        refresh_token: 'test-refresh',
        expiry_date: now + 3600000,
        scope,
      }),
      request: async (_config, _token, request) => {
        requests.push(structuredClone({ ...request, signal: undefined }));
        if (request.resource === 'tasklists') {
          if (failTasks) throw { response: { status: 403 } };
          return { items: [{ id: 'list1' }], ...(endless ? { nextPageToken: 'same' } : {}) };
        }
        if (request.resource === 'tasks') {
          if (request.method === 'PATCH') {
            if (conflictPatch) throw { response: { status: 412 } };
            assert.equal(request.headers?.['If-Match'], task.etag);
            assert.deepEqual(
              Object.keys(request.body ?? {}).sort(),
              request.body?.status === 'completed' ? ['status'] : ['completed', 'status'],
            );
            task = { ...task, ...request.body, etag: '"task2"' } as typeof task;
            if (task.status === 'needsAction') delete (task as Record<string, unknown>).completed;
            return task;
          }
          if (request.taskId) return { ...task };
          assert.equal(request.query?.showCompleted, true);
          assert.equal(request.query?.showHidden, true);
          return { items: [task, ...(duplicate ? [{ ...task, id: 'task456' }] : [])] };
        }
        if (request.eventId) return { ...event };
        if (request.query?.eventTypes) {
          assert.equal(request.query.eventTypes, 'focusTime');
          assert.equal(request.query.singleEvents, false);
          assert.equal(request.query.q, undefined, 'Google does not reliably search task URLs.');
        }
        return {
          items: [event, ...(duplicateMirror ? [{ ...event, id: 'event67890' }] : [])],
          accessRole: 'owner',
        };
      },
    },
  });
  const start = async (options: { tasks?: boolean; extendedColors?: boolean } = {}) => {
    const flow = await service.connect(owner, options);
    return { ...flow, state: new URL(flow.authorizationUrl).searchParams.get('state')! };
  };
  const connect = async (options: { tasks?: boolean; extendedColors?: boolean } = {}) => {
    const flow = await start(options);
    await service.callback({
      state: flow.state,
      code: 'test-code',
      correlationCookie: flow.correlationCookie,
    });
    return flow;
  };
  const read = () =>
    service.listEvents({
      from: '2026-10-11',
      to: '2026-10-18',
      timeZone: defaultSettings.timeZone,
    });
  return {
    service,
    secrets,
    requests,
    start,
    connect,
    read,
    setScope: (value: string) => {
      scope = value;
    },
    setDuplicate: () => {
      duplicate = true;
    },
    setDuplicateMirror: () => {
      duplicateMirror = true;
    },
    patchTask: (patch: Record<string, unknown>) => {
      task = { ...task, ...patch } as typeof task;
    },
    setFailure: () => {
      failTasks = true;
    },
    setConflict: () => {
      conflictPatch = true;
    },
    setEndless: () => {
      endless = true;
    },
    mutateTask: () => {
      task = { ...task, status: 'completed', etag: '"external"' };
    },
    changeEvent: () => {
      event = { ...event, etag: '"event2"' };
    },
    setDescription: (description: string) => {
      event = { ...event, description };
    },
    patchEvent: (patch: Record<string, unknown>) => {
      event = { ...event, ...patch };
    },
    task: () => task,
  };
}
const fullScope = GOOGLE_CALENDAR_SCOPE + ' ' + GOOGLE_TASKS_SCOPE;
const code = (expected: string) => (error: unknown) =>
  error instanceof AppError && error.code === expected;
async function enabled() {
  const f = fixture();
  f.setScope(fullScope);
  await f.connect({ tasks: true });
  return f;
}
function input(
  event: Awaited<ReturnType<ReturnType<typeof fixture>['read']>>['events'][number],
  completed: boolean,
) {
  return {
    etag: event.etag,
    taskEtag: event.googleTask!.etag,
    connectionId: event.googleTask!.connectionId,
    completed,
  };
}
test('Tasks URL normalization accepts exact official link only', () => {
  assert.equal(normalizeGoogleTaskLink(link + '/'), link);
  assert.equal(normalizeGoogleTaskLink(link + '?sa=6'), link);
  assert.equal(normalizeGoogleTaskLink(link + '/?sa=6'), link);
  for (const url of [
    'http://tasks.google.com/task/x',
    'https://tasks.google.com.evil.test/task/x',
    'https://evil.test/task/x',
    'https://tasks.google.com/task/x?q=1',
    'https://tasks.google.com/task/x?sa=7',
    'https://tasks.google.com/task/x?sa=6&sa=6',
    'https://tasks.google.com/task/x?sa=6&q=1',
    'https://tasks.google.com/task/x?q=1&sa=6',
    'https://tasks.google.com/task/x?sa=6&',
    'https://tasks.google.com/task/x?sa=6#other',
    'https://tasks.google.com/task/x#x',
    'https://user@tasks.google.com/task/x',
    'https://tasks.google.com:444/task/x',
  ])
    assert.equal(normalizeGoogleTaskLink(url), null);
});
test('old grants never silently request Tasks and calendar read remains available', async () => {
  const f = fixture();
  const flow = await f.connect();
  assert.equal(new URL(flow.authorizationUrl).searchParams.get('scope'), GOOGLE_CALENDAR_SCOPE);
  const result = await f.read();
  assert.equal(result.events.length, 1);
  assert.equal(result.tasks?.status, 'permission_required');
  assert.equal(result.events[0].googleTask, undefined);
  assert.equal(
    f.requests.some((request) => request.resource === 'tasks'),
    false,
  );
});
test('Tasks opt-in requires granted scope and preserves previous working grant on denial', async () => {
  const f = fixture();
  await f.connect();
  const prior = f.secrets.values.get('google.tokens');
  const flow = await f.start({ tasks: true });
  assert.ok(new URL(flow.authorizationUrl).searchParams.get('scope')?.includes(GOOGLE_TASKS_SCOPE));
  await assert.rejects(
    f.service.callback({
      state: flow.state,
      code: 'test-code',
      correlationCookie: flow.correlationCookie,
    }),
    code('GOOGLE_TASKS_SCOPE_REQUIRED'),
  );
  assert.equal(f.secrets.values.get('google.tokens'), prior);
  const denied = await f.start({ tasks: true });
  await assert.rejects(
    f.service.callback({
      state: denied.state,
      error: 'access_denied',
      correlationCookie: denied.correlationCookie,
    }),
    code('GOOGLE_CONSENT_DENIED'),
  );
  assert.equal(f.secrets.values.get('google.tokens'), prior);
});
test('Tasks opt-in retains label permission and ordinary reconnect retains approved Tasks', async () => {
  const f = fixture();
  f.setScope(GOOGLE_CALENDAR_SCOPE + ' ' + GOOGLE_CALENDAR_LABELS_SCOPE);
  await f.connect({ extendedColors: true });
  f.setScope(fullScope + ' ' + GOOGLE_CALENDAR_LABELS_SCOPE);
  const flow = await f.connect({ tasks: true });
  const requested = new URL(flow.authorizationUrl).searchParams.get('scope')!;
  assert.ok(requested.includes(GOOGLE_TASKS_SCOPE));
  assert.ok(requested.includes(GOOGLE_CALENDAR_LABELS_SCOPE));
  const again = await f.start({ tasks: false, extendedColors: false });
  assert.ok(
    new URL(again.authorizationUrl).searchParams.get('scope')?.includes(GOOGLE_TASKS_SCOPE),
  );
  assert.ok(
    new URL(again.authorizationUrl).searchParams
      .get('scope')
      ?.includes(GOOGLE_CALENDAR_LABELS_SCOPE),
  );
});
test('completion and reopening patch only native status and preserve Calendar schedule', async () => {
  const f = await enabled();
  const result = await f.read(),
    event = result.events[0];
  assert.equal(event.googleTask?.status, 'needsAction');
  assert.equal(event.readOnly, true);
  const completed = await f.service.completeTask(event.id, input(event, true));
  assert.equal(completed.event.googleTask?.status, 'completed');
  assert.deepEqual(completed.event.start, event.start);
  assert.equal(f.task().notes, 'Do not modify');
  const reopened = await f.service.completeTask(event.id, input(completed.event, false));
  assert.equal(reopened.event.googleTask?.status, 'needsAction');
  assert.deepEqual(reopened.event.end, event.end);
  assert.equal(
    f.requests.some((request) => request.method === 'PATCH' && !request.resource),
    false,
  );
});
test('external Google completion is reflected by the next ordinary Calendar refresh', async () => {
  const f = await enabled();
  f.mutateTask();
  const result = await f.read();
  assert.equal(result.events[0].googleTask?.status, 'completed');
});
test('ambiguous provider links disable completion instead of guessing by title', async () => {
  const f = await enabled();
  f.setDuplicate();
  const result = await f.read();
  assert.equal(result.events[0].googleTask, undefined);
  await assert.rejects(
    f.service.completeTask(result.events[0].id, {
      etag: result.events[0].etag,
      taskEtag: '"task1"',
      completed: true,
      connectionId: await f.service.connectionIdentity(),
    }),
    code('GOOGLE_TASK_NOT_LINKED'),
  );
  assert.equal(
    f.requests.some((request) => request.method === 'PATCH'),
    false,
  );
});
test('stale task and Calendar versions and changed connection prevent mutation', async () => {
  const f = await enabled();
  const event = (await f.read()).events[0];
  f.mutateTask();
  await assert.rejects(f.service.completeTask(event.id, input(event, true)), code('CONFLICT'));
  f.changeEvent();
  await assert.rejects(f.service.completeTask(event.id, input(event, true)), code('CONFLICT'));
  await f.connect({ tasks: true });
  await assert.rejects(f.service.completeTask(event.id, input(event, true)), code('CONFLICT'));
  assert.equal(
    f.requests.some((request) => request.method === 'PATCH'),
    false,
  );
});
test('provider ETag rejection remains a conflict', async () => {
  const f = await enabled();
  const event = (await f.read()).events[0];
  f.setConflict();
  await assert.rejects(f.service.completeTask(event.id, input(event, true)), code('CONFLICT'));
});
test('disabled Tasks API and incomplete pagination preserve Calendar and disable checkboxes', async () => {
  for (const scenario of ['forbidden', 'pages']) {
    const f = await enabled();
    if (scenario === 'forbidden') f.setFailure();
    else f.setEndless();
    const result = await f.read();
    assert.equal(result.events.length, 1);
    assert.equal(result.events[0].googleTask, undefined);
    assert.equal(result.tasks?.status, scenario === 'forbidden' ? 'unavailable' : 'partial');
  }
});

test('multiple task URLs and lookalike hosts never authorize native completion', async () => {
  for (const description of [
    link + ' https://tasks.google.com/task/otherTask',
    'https://tasks.google.com.evil.test/task/opaqueTask',
    'https://tasks.google.com/task/opaqueTask?other=1',
  ]) {
    const f = await enabled();
    f.setDescription(description);
    const event = (await f.read()).events[0];
    assert.equal(event.googleTask, undefined);
    await assert.rejects(
      f.service.completeTask(event.id, {
        etag: event.etag,
        taskEtag: '"task1"',
        connectionId: await f.service.connectionIdentity(),
        completed: true,
      }),
      code('GOOGLE_TASK_NOT_LINKED'),
    );
    assert.equal(
      f.requests.some((request) => request.method === 'PATCH'),
      false,
    );
  }
});

test('ordinary, special, protected and recurrent Calendar records cannot mark unrelated Tasks', async () => {
  for (const patch of [
    { eventType: 'default' },
    { eventType: 'fromGmail' },
    { eventType: 'birthday' },
    { creator: { self: false } },
    { organizer: { self: false } },
    { attendees: [{ self: false }] },
    { locked: true },
    { recurrence: ['RRULE:FREQ=DAILY'] },
    { recurringEventId: 'master123' },
  ]) {
    const f = await enabled();
    f.patchEvent(patch);
    const event = (await f.read()).events[0];
    assert.equal(event.googleTask, undefined);
    await assert.rejects(
      f.service.completeTask(event.id, {
        etag: event.etag,
        taskEtag: '"task1"',
        connectionId: await f.service.connectionIdentity(),
        completed: true,
      }),
      code('GOOGLE_TASK_NOT_LINKED'),
    );
    assert.equal(
      f.requests.some((request) => request.method === 'PATCH'),
      false,
    );
  }
});

test('duplicate Calendar mirrors suppress checkboxes and direct completion mutations', async () => {
  const f = await enabled(),
    old = (await f.read()).events[0];
  f.setDuplicateMirror();
  const events = (await f.read()).events;
  assert.equal(events.length, 2);
  assert.ok(events.every((event) => !event.googleTask));
  await assert.rejects(
    f.service.completeTask(old.id, input(old, true)),
    code('GOOGLE_TASK_NOT_LINKED'),
  );
  assert.equal(
    f.requests.some((request) => request.method === 'PATCH'),
    false,
  );
});

test('exact Task URL identity also requires native title and scheduled-day integrity', async () => {
  for (const patch of [
    { title: 'Different task' },
    { due: '2026-10-14T00:00:00Z' },
    { due: undefined },
  ]) {
    const f = await enabled();
    const old = (await f.read()).events[0];
    f.patchTask(patch);
    assert.equal((await f.read()).events[0].googleTask, undefined);
    await assert.rejects(
      f.service.completeTask(old.id, input(old, true)),
      code('GOOGLE_TASK_NOT_LINKED'),
    );
    assert.equal(
      f.requests.some((request) => request.method === 'PATCH'),
      false,
    );
  }
});

test('actual provider sa=6 links match plain Calendar links across read, completion and refresh', async () => {
  const f = await enabled();
  assert.equal(f.task().webViewLink, link + '?sa=6');
  const original = (await f.read()).events[0];
  assert.ok(original.description.includes(link + '.'));
  assert.equal(original.googleTask?.id, 'task123');
  const result = await f.service.completeTask(original.id, input(original, true));
  assert.equal(result.event.googleTask?.status, 'completed');
  assert.equal((await f.read()).events[0].googleTask?.status, 'completed');
  const write = f.requests.find(
    (request) => request.resource === 'tasks' && request.method === 'PATCH',
  );
  assert.equal(write?.taskId, 'task123');
  assert.equal(write?.taskListId, 'list1');
  assert.deepEqual(write?.body, { status: 'completed' });
  assert.deepEqual(result.event.start, original.start);
  assert.deepEqual(result.event.end, original.end);
});
