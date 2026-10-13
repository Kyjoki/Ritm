import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash, randomUUID } from 'node:crypto';
import type { Credentials } from 'google-auth-library';
import type { GoogleEventInput, Settings } from '../shared/types.ts';
import { CALENDAR_COLOR_IDS } from '../shared/calendar-colors.ts';
import { AppError } from '../server/errors.ts';
import { defaultSettings } from '../server/store.ts';
import {
  createGoogleCalendarService,
  GOOGLE_CALLBACK_PATH,
  GOOGLE_CALENDAR_SCOPE,
  googleEventInputSchema,
  googleZonedInstant,
  mapGoogleEvent,
  type GoogleRequest,
  type GoogleSecretStorage,
  type GoogleTransport,
} from '../server/google-calendar.ts';

const owner = `${'a'.repeat(64)}:${'b'.repeat(64)}`;
const fakeAccess = 'google-access-only-test',
  fakeRefresh = 'google-refresh-only-test';
const now = Date.parse('2026-10-13T05:00:00Z');
const environment = {
  GOOGLE_CLIENT_ID: '123-test.apps.googleusercontent.com',
  GOOGLE_CLIENT_SECRET: 'not-a-real-client-secret',
  GOOGLE_REDIRECT_URI: `http://127.0.0.1:5173${GOOGLE_CALLBACK_PATH}`,
};
const eventInput: GoogleEventInput = {
  title: 'Презентация проекта',
  description: 'Показать Ritm',
  date: '2026-10-13',
  time: '11:00',
  duration: 60,
  allDay: false,
};
const rawEvent = (patch: Record<string, unknown> = {}) => ({
  id: 'event12345',
  summary: eventInput.title,
  description: eventInput.description,
  etag: '"v1"',
  start: { dateTime: '2026-10-13T11:00:00+05:00' },
  end: { dateTime: '2026-10-13T12:00:00+05:00' },
  organizer: { self: true },
  ...patch,
});

class MemorySecrets implements GoogleSecretStorage {
  values = new Map<string, string>();
  leases = new Map<string, string>();
  async getSecret(name: string) {
    return this.values.get(name) ?? null;
  }
  async saveSecret(name: string, value: string) {
    this.values.set(name, value);
  }
  async removeSecret(name: string) {
    this.values.delete(name);
  }
  async consumeSecret(name: string) {
    const value = this.values.get(name) ?? null;
    this.values.delete(name);
    return value;
  }
  async acquireLease(name: string) {
    if (this.leases.has(name)) return null;
    const token = randomUUID();
    this.leases.set(name, token);
    return token;
  }
  async releaseLease(name: string, token: string) {
    if (this.leases.get(name) === token) this.leases.delete(name);
  }
}
function fixture(
  overrides: Partial<GoogleTransport> = {},
  env: NodeJS.ProcessEnv = environment,
  settings: Settings = defaultSettings,
) {
  const secrets = new MemorySecrets();
  let ownerActive = true,
    clock = now,
    exchanges = 0,
    refreshes = 0;
  const requests: GoogleRequest[] = [];
  const credentials = (): Credentials => ({
    access_token: fakeAccess,
    refresh_token: fakeRefresh,
    expiry_date: clock + 3_600_000,
    scope: GOOGLE_CALENDAR_SCOPE,
  });
  const transport: GoogleTransport = {
    exchangeCode: async () => {
      exchanges++;
      return credentials();
    },
    refreshToken: async () => {
      refreshes++;
      return credentials();
    },
    request: async (_config, _token, request) => {
      requests.push(request);
      return { items: [], accessRole: 'owner' };
    },
    ...overrides,
  };
  const service = createGoogleCalendarService({
    secrets,
    security: { hasOwnerSession: async (hash) => hash === owner && ownerActive },
    settings: async () => settings,
    env,
    transport,
    now: () => clock,
  });
  const start = async () => {
    const flow = await service.connect(owner);
    return { ...flow, state: new URL(flow.authorizationUrl).searchParams.get('state')! };
  };
  const connect = async () => {
    const flow = await start();
    await service.callback({
      state: flow.state,
      code: 'test-code',
      correlationCookie: flow.correlationCookie,
    });
    return flow;
  };
  return {
    service,
    secrets,
    start,
    connect,
    requests,
    counts: () => ({ exchanges, refreshes }),
    setOwnerActive: (value: boolean) => {
      ownerActive = value;
    },
    setClock: (value: number) => {
      clock = value;
    },
  };
}
const rejectsCode = (code: string) => (error: unknown) =>
  error instanceof AppError && error.code === code;

test('missing OAuth config remains unconfigured and does not call Google', async () => {
  const f = fixture({}, {});
  assert.equal((await f.service.status()).status, 'unconfigured');
  await assert.rejects(() => f.service.connect(owner), rejectsCode('GOOGLE_NOT_CONFIGURED'));
  await assert.rejects(
    () => f.service.createEvent(eventInput, randomUUID()),
    rejectsCode('GOOGLE_NOT_CONFIGURED'),
  );
  assert.deepEqual(f.counts(), { exchanges: 0, refreshes: 0 });
  assert.deepEqual(f.requests, []);
});

test('OAuth uses S256, narrow scopes, bound cookie/session, and one-use durable state', async () => {
  const f = fixture(),
    flow = await f.start(),
    url = new URL(flow.authorizationUrl);
  assert.equal(url.origin, 'https://accounts.google.com');
  assert.equal(url.searchParams.get('scope'), GOOGLE_CALENDAR_SCOPE);
  assert.equal(url.searchParams.get('code_challenge_method'), 'S256');
  assert.equal(url.searchParams.get('access_type'), 'offline');
  assert.equal(url.searchParams.get('include_granted_scopes'), 'false');
  assert.equal(flow.authorizationUrl.includes(environment.GOOGLE_CLIENT_SECRET), false);
  const stored = JSON.parse(
    [...f.secrets.values.entries()].find(([key]) => key.startsWith('google.oauth.flow.'))![1],
  );
  assert.equal(stored.ownerSessionHash, owner);
  assert.equal(
    url.searchParams.get('code_challenge'),
    createHash('sha256').update(stored.codeVerifier).digest('base64url'),
  );
  await assert.rejects(
    () => f.service.callback({ state: flow.state, code: 'test-code' }),
    rejectsCode('GOOGLE_INVALID_STATE'),
  );
  await assert.rejects(
    () =>
      f.service.callback({
        state: flow.state,
        code: 'test-code',
        correlationCookie: 'z'.repeat(43),
      }),
    rejectsCode('GOOGLE_INVALID_STATE'),
  );
  f.setOwnerActive(false);
  await assert.rejects(
    () =>
      f.service.callback({
        state: flow.state,
        code: 'test-code',
        correlationCookie: flow.correlationCookie,
      }),
    rejectsCode('GOOGLE_INVALID_STATE'),
  );
  assert.equal(f.counts().exchanges, 0);
  f.setOwnerActive(true);
  const result = await f.service.callback({
    state: flow.state,
    code: 'test-code',
    correlationCookie: flow.correlationCookie,
  });
  assert.equal(result.status, 'connected');
  assert.equal(JSON.stringify(result).includes(fakeRefresh), false);
  await assert.rejects(
    () =>
      f.service.callback({
        state: flow.state,
        code: 'test-code',
        correlationCookie: flow.correlationCookie,
      }),
    rejectsCode('GOOGLE_INVALID_STATE'),
  );
  assert.equal(f.counts().exchanges, 1);
});

test('expired/denied/cancelled OAuth flows cannot replace a connection', async () => {
  const f = fixture(),
    expired = await f.start();
  f.setClock(now + 600_001);
  await assert.rejects(
    () =>
      f.service.callback({
        state: expired.state,
        code: 'test-code',
        correlationCookie: expired.correlationCookie,
      }),
    rejectsCode('GOOGLE_INVALID_STATE'),
  );
  f.setClock(now);
  const denied = await f.start();
  await assert.rejects(
    () =>
      f.service.callback({
        state: denied.state,
        error: 'access_denied',
        correlationCookie: denied.correlationCookie,
      }),
    rejectsCode('GOOGLE_CONSENT_DENIED'),
  );
  const pending = await f.start();
  await f.service.disconnect();
  await assert.rejects(
    () =>
      f.service.callback({
        state: pending.state,
        code: 'test-code',
        correlationCookie: pending.correlationCookie,
      }),
    rejectsCode('CONFLICT'),
  );
  assert.equal(f.counts().exchanges, 0);
  assert.equal((await f.service.status()).status, 'disconnected');
});

test('a superseded callback cannot remove or replace a newer OAuth flow', async () => {
  const f = fixture(),
    first = await f.start();
  const originalConsume = f.secrets.consumeSecret.bind(f.secrets);
  let consumed!: () => void, release!: () => void;
  const reached = new Promise<void>((done) => {
    consumed = done;
  });
  const pause = new Promise<void>((done) => {
    release = done;
  });
  let firstConsume = true;
  f.secrets.consumeSecret = async (name) => {
    const value = await originalConsume(name);
    if (firstConsume) {
      firstConsume = false;
      consumed();
      await pause;
    }
    return value;
  };
  const oldCallback = f.service.callback({
    state: first.state,
    code: 'old-code',
    correlationCookie: first.correlationCookie,
  });
  await reached;
  const newer = await f.start();
  release();
  await assert.rejects(() => oldCallback, rejectsCode('CONFLICT'));
  assert.equal(f.counts().exchanges, 0);
  await f.service.callback({
    state: newer.state,
    code: 'new-code',
    correlationCookie: newer.correlationCookie,
  });
  assert.equal(f.counts().exchanges, 1);
  assert.equal((await f.service.status()).status, 'connected');
});

test('logout during token exchange prevents saving a new Google grant', async () => {
  let started!: () => void, release!: () => void;
  const reached = new Promise<void>((done) => {
    started = done;
  });
  const pause = new Promise<void>((done) => {
    release = done;
  });
  const f = fixture({
    exchangeCode: async () => {
      started();
      await pause;
      return {
        access_token: fakeAccess,
        refresh_token: fakeRefresh,
        expiry_date: now + 3_600_000,
        scope: GOOGLE_CALENDAR_SCOPE,
      };
    },
  });
  const flow = await f.start();
  const callback = f.service.callback({
    state: flow.state,
    code: 'test-code',
    correlationCookie: flow.correlationCookie,
  });
  await reached;
  f.setOwnerActive(false);
  release();
  await assert.rejects(() => callback, rejectsCode('AUTH_REQUIRED'));
  assert.equal(f.secrets.values.has('google.tokens'), false);
  assert.equal((await f.service.status()).status, 'disconnected');
});

test('refresh is coordinated, preserves omitted refresh tokens, and invalid_grant becomes reauth_required', async () => {
  let refreshCalls = 0;
  const f = fixture({
    refreshToken: async () => {
      refreshCalls++;
      await new Promise<void>((done) => setTimeout(done, 15));
      return { access_token: 'refreshed-access-only-test', expiry_date: now + 3_600_000 };
    },
  });
  await f.connect();
  const slot = JSON.parse(f.secrets.values.get('google.tokens')!);
  slot.expiresAt = now - 1;
  await f.secrets.saveSecret('google.tokens', JSON.stringify(slot));
  const period = { from: '2026-10-13', to: '2026-10-14', timeZone: 'Asia/Qyzylorda' };
  await Promise.all([f.service.listEvents(period), f.service.listEvents(period)]);
  assert.equal(refreshCalls, 1);
  assert.equal(JSON.parse(f.secrets.values.get('google.tokens')!).refreshToken, fakeRefresh);
  const invalid = fixture({
    refreshToken: async () => {
      throw { response: { status: 400, data: { error: 'invalid_grant', secret: fakeRefresh } } };
    },
  });
  await invalid.connect();
  const old = JSON.parse(invalid.secrets.values.get('google.tokens')!);
  old.expiresAt = now - 1;
  await invalid.secrets.saveSecret('google.tokens', JSON.stringify(old));
  await assert.rejects(
    () => invalid.service.listEvents(period),
    (error: unknown) =>
      error instanceof AppError &&
      error.code === 'GOOGLE_REAUTH_REQUIRED' &&
      !error.message.includes(fakeRefresh),
  );
  assert.equal((await invalid.service.status()).status, 'reauth_required');
});

test('pagination handles empty pages, expands ranges safely and keeps all-day end exclusive', async () => {
  const requests: GoogleRequest[] = [];
  const f = fixture({
    request: async (_config, _token, request) => {
      requests.push(request);
      if (!request.query?.pageToken)
        return { items: [], nextPageToken: 'second', accessRole: 'owner' };
      return {
        accessRole: 'owner',
        items: [
          rawEvent({
            id: 'allday1234',
            start: { date: '2026-10-13' },
            end: { date: '2026-10-14' },
          }),
          rawEvent({
            id: 'overnight12',
            start: { dateTime: '2026-10-12T23:00:00Z' },
            end: { dateTime: '2026-10-13T00:00:00Z' },
          }),
          rawEvent({
            id: 'before1234',
            start: { dateTime: '2026-10-12T18:30:00Z' },
            end: { dateTime: '2026-10-12T19:00:00Z' },
          }),
          { id: 'cancelled1', status: 'cancelled' },
        ],
      };
    },
  });
  await f.connect();
  const result = await f.service.listEvents({
    from: '2026-10-13',
    to: '2026-10-14',
    timeZone: 'Asia/Qyzylorda',
  });
  assert.equal(result.partial, false);
  assert.deepEqual(
    result.events.map((event) => event.id),
    ['allday1234', 'overnight12'],
  );
  assert.equal(result.events[0].end.date, '2026-10-14');
  assert.equal(result.events[0].allDay, true);
  assert.equal(requests.length, 2);
  assert.equal(requests[0].query?.singleEvents, true);
  assert.equal(requests[1].query?.pageToken, 'second');
  assert.equal(requests[0].query?.syncToken, undefined);
  await assert.rejects(
    () => f.service.listEvents({ from: '2026-01-01', to: '2026-12-31', timeZone: 'UTC' }),
    rejectsCode('GOOGLE_RANGE'),
  );
});

test('capped provider data is flagged partial and cannot authorize an AI free slot', async () => {
  const f = fixture({
    request: async () => ({
      accessRole: 'owner',
      items: Array.from({ length: 1500 }, (_, index) =>
        rawEvent({ id: `event${index.toString().padStart(5, '0')}` }),
      ),
    }),
  });
  await f.connect();
  const result = await f.service.listEvents({
    from: '2026-10-13',
    to: '2026-10-14',
    timeZone: 'Asia/Qyzylorda',
  });
  assert.equal(result.events.length, 1000);
  assert.equal(result.partial, true);
  await assert.rejects(
    () =>
      f.service.assertFreeSlots(
        [{ date: '2026-10-13', time: '13:00', duration: 30, title: 'Презентация' }],
        'Asia/Qyzylorda',
      ),
    rejectsCode('CONFLICT'),
  );
});

test('Google writes require explicit methods, create retries are idempotent, and guests remain protected', async () => {
  const records = new Map<string, Record<string, unknown>>(),
    requests: GoogleRequest[] = [];
  const f = fixture({
    request: async (_config, _token, request) => {
      requests.push(request);
      if (request.method === 'POST') {
        const id = request.body!.id as string;
        if (records.has(id)) throw { response: { status: 409 } };
        const value = { ...request.body!, etag: '"v1"', organizer: { self: true } };
        records.set(id, value);
        return value;
      }
      if (request.method === 'GET' && request.eventId) return records.get(request.eventId);
      if (request.method === 'PATCH') {
        const value = { ...records.get(request.eventId!)!, ...request.body!, etag: '"v2"' };
        records.set(request.eventId!, value);
        return value;
      }
      return { items: [], accessRole: 'owner' };
    },
  });
  await f.connect();
  assert.equal(requests.length, 0);
  const requestId = randomUUID(),
    created = await f.service.createEvent(eventInput, requestId);
  assert.equal(created.readOnly, false);
  assert.match(created.id, /^[a-f0-9]{64}$/);
  assert.equal((await f.service.createEvent(eventInput, requestId)).id, created.id);
  assert.equal(records.size, 1);
  assert.equal(requests[0].body?.attendees, undefined);
  assert.equal(requests[0].query?.sendUpdates, 'none');
  await assert.rejects(
    () => f.service.createEvent({ ...eventInput, title: 'Другая задача' }, requestId),
    rejectsCode('CONFLICT'),
  );
  const updated = await f.service.updateEvent(
    created.id,
    { ...eventInput, time: '14:00' },
    created.etag,
  );
  assert.equal(updated.etag, '"v2"');
  assert.equal(
    requests.find((request) => request.method === 'PATCH')?.headers?.['If-Match'],
    '"v1"',
  );
  await assert.rejects(
    () => f.service.updateEvent(created.id, eventInput, created.etag),
    rejectsCode('CONFLICT'),
  );
  records.set(created.id, {
    ...records.get(created.id)!,
    attendees: [{ self: true }, { self: false }],
  });
  const patchCount = requests.filter((request) => request.method === 'PATCH').length;
  await assert.rejects(
    () => f.service.updateEvent(created.id, eventInput, updated.etag),
    rejectsCode('GOOGLE_EVENT_READ_ONLY'),
  );
  assert.equal(requests.filter((request) => request.method === 'PATCH').length, patchCount);
  await f.service.disconnect();
  assert.equal((await f.service.status()).status, 'disconnected');
  assert.equal(
    requests.some((request) => (request.method as string) === 'DELETE'),
    false,
  );
});

test('ETag provider races map to conflict and malformed event data never claims availability', async () => {
  const f = fixture({
    request: async (_config, _token, request) => {
      if (request.method === 'GET' && request.eventId) return rawEvent();
      throw { response: { status: 412, data: { secret: fakeAccess } } };
    },
  });
  await f.connect();
  await assert.rejects(
    () => f.service.updateEvent('event12345', eventInput, '"v1"'),
    (error: unknown) =>
      error instanceof AppError && error.status === 409 && !error.message.includes(fakeAccess),
  );
  assert.throws(
    () =>
      mapGoogleEvent(
        rawEvent({ end: { dateTime: '2026-10-13T10:00:00+05:00' } }),
        'Asia/Qyzylorda',
      ),
    rejectsCode('GOOGLE_INVALID_EVENT'),
  );
  assert.equal(mapGoogleEvent(rawEvent({ locked: true }), 'Asia/Qyzylorda')!.readOnly, true);
  assert.equal(
    mapGoogleEvent(rawEvent({ eventType: 'outOfOffice' }), 'Asia/Qyzylorda')!.readOnly,
    true,
  );
});

test('timezone conversion is independent of server zone and rejects DST gaps and ambiguous times', () => {
  assert.equal(
    new Date(googleZonedInstant('2026-10-13', '11:00', 'Asia/Qyzylorda')).toISOString(),
    '2026-10-13T06:00:00.000Z',
  );
  assert.equal(
    new Date(googleZonedInstant('2026-03-29', '01:30', 'Europe/Berlin')).toISOString(),
    '2026-03-29T00:30:00.000Z',
  );
  assert.throws(
    () => googleZonedInstant('2026-03-29', '02:30', 'Europe/Berlin'),
    rejectsCode('GOOGLE_TIME_GAP'),
  );
  assert.throws(
    () => googleZonedInstant('2026-10-25', '02:30', 'Europe/Berlin'),
    rejectsCode('GOOGLE_TIME_AMBIGUOUS'),
  );
});

test('master series and DST folds remain read-only on both mapping and direct update', async () => {
  const recurring = rawEvent({ recurrence: ['RRULE:FREQ=WEEKLY'] });
  assert.equal(mapGoogleEvent(recurring, 'Asia/Qyzylorda')!.readOnly, true);
  const fold = rawEvent({
    start: { dateTime: '2026-10-25T02:15:00+02:00' },
    end: { dateTime: '2026-10-25T02:45:00+02:00' },
  });
  const clockChange = rawEvent({
    start: { dateTime: '2026-03-29T01:30:00+01:00' },
    end: { dateTime: '2026-03-29T03:30:00+02:00' },
  });
  assert.equal(mapGoogleEvent(fold, 'Europe/Berlin')!.readOnly, true);
  assert.equal(mapGoogleEvent(clockChange, 'Europe/Berlin')!.readOnly, true);
  let patches = 0;
  const f = fixture({
    request: async (_config, _token, request) => {
      if (request.method === 'GET') return recurring;
      patches++;
      return rawEvent();
    },
  });
  await f.connect();
  await assert.rejects(
    () => f.service.updateEvent('event12345', eventInput, '"v1"'),
    rejectsCode('GOOGLE_EVENT_READ_ONLY'),
  );
  assert.equal(patches, 0);
});

test('an expanded recurring instance is read and patched by its exact ID with version protection', async () => {
  const id = 'series1234_20261013T060000Z';
  const metadata = {
    location: 'Переговорная',
    visibility: 'private',
    reminders: { useDefault: false, overrides: [{ method: 'popup', minutes: 15 }] },
    conferenceData: { conferenceId: 'test-only-conference-id' },
    extendedProperties: { private: { keep: 'test-only-metadata' } },
    attendees: [{ self: true }],
  };
  let record: Record<string, unknown> = rawEvent({
    ...metadata,
    id,
    recurringEventId: 'series1234',
    originalStartTime: { dateTime: '2026-10-13T11:00:00+05:00' },
    colorId: '2',
  });
  const requests: GoogleRequest[] = [];
  const f = fixture({
    request: async (_config, _token, request) => {
      requests.push(request);
      assert.equal(request.eventId, id, 'Only the selected instance may be addressed.');
      if (request.method === 'GET') return record;
      assert.equal(request.method, 'PATCH');
      assert.equal(request.headers?.['If-Match'], record.etag);
      assert.equal(request.body?.recurrence, undefined);
      assert.equal(request.body?.recurringEventId, undefined);
      assert.deepEqual(Object.keys(request.body!).sort(), [
        'colorId',
        'description',
        'end',
        'start',
        'summary',
      ]);
      record = { ...record, ...request.body, etag: '"v2"' };
      return record;
    },
  });
  await f.connect();
  const mapped = mapGoogleEvent(record, 'Asia/Qyzylorda')!;
  assert.equal(mapped.recurring, true);
  assert.equal(mapped.readOnly, false);
  assert.equal(mapped.readOnlyReason, undefined);
  const updated = await f.service.updateEvent(
    id,
    { ...eventInput, title: 'Перенесённая презентация', time: '14:00', colorId: '11' },
    '"v1"',
  );
  assert.equal(updated.id, id);
  assert.equal(updated.recurring, true);
  assert.equal(updated.readOnly, false);
  assert.equal(updated.colorId, '11');
  assert.equal(updated.start.dateTime, '2026-10-13T09:00:00.000Z');
  assert.deepEqual(
    requests.map((request) => request.method),
    ['GET', 'PATCH'],
  );
  assert.equal(requests[1].query?.sendUpdates, 'none');
  for (const [field, value] of Object.entries(metadata)) assert.deepEqual(record[field], value);
  await assert.rejects(f.service.updateEvent(id, eventInput, '"v1"'), rejectsCode('CONFLICT'));
  assert.equal(requests.filter((request) => request.method === 'PATCH').length, 1);
});

test('instance ownership, master recurrence, guest, special, locked and complex event constraints stay protected', async () => {
  for (const patch of [
    { recurrence: ['RRULE:FREQ=DAILY'] },
    { recurrence: [] },
    { organizer: { self: false } },
    { attendees: [{ self: true }, { self: false }] },
    { locked: true },
    { eventType: 'outOfOffice' },
    {
      start: { dateTime: '2026-10-13T23:30:00+05:00' },
      end: { dateTime: '2026-10-14T01:00:00+05:00' },
    },
    { start: { date: '2026-10-13' }, end: { date: '2026-10-15' } },
  ]) {
    let patches = 0;
    const record = rawEvent({ recurringEventId: 'series1234', ...patch });
    const mapped = mapGoogleEvent(record, 'Asia/Qyzylorda')!;
    assert.equal(mapped.readOnly, true);
    assert.ok(mapped.readOnlyReason);
    const f = fixture({
      request: async (_config, _token, request) => {
        if (request.method === 'GET') return record;
        patches++;
        return record;
      },
    });
    await f.connect();
    await assert.rejects(
      f.service.updateEvent('event12345', eventInput, '"v1"'),
      (error: unknown) =>
        error instanceof AppError &&
        error.code === 'GOOGLE_EVENT_READ_ONLY' &&
        error.message === mapped.readOnlyReason,
    );
    assert.equal(patches, 0);
  }
  const fold = rawEvent({
    recurringEventId: 'series1234',
    start: { dateTime: '2026-10-25T02:15:00+02:00' },
    end: { dateTime: '2026-10-25T02:45:00+02:00' },
  });
  const dst = fixture(
    {
      request: async (_config, _token, request) => {
        assert.equal(request.method, 'GET', 'No write may happen to a DST-ambiguous instance.');
        return fold;
      },
    },
    environment,
    { ...defaultSettings, timeZone: 'Europe/Berlin' },
  );
  await dst.connect();
  await assert.rejects(
    dst.service.updateEvent('event12345', eventInput, '"v1"'),
    rejectsCode('GOOGLE_EVENT_READ_ONLY'),
  );
});

test('colors are read from list metadata, written to Google and preserved or reset explicitly', async () => {
  const records = new Map<string, Record<string, unknown>>(),
    requests: GoogleRequest[] = [];
  const f = fixture({
    request: async (_config, _token, request) => {
      requests.push(request);
      if (request.method === 'POST') {
        const id = request.body!.id as string;
        if (records.has(id)) throw { response: { status: 409 } };
        const record = { ...request.body!, etag: '"v1"', organizer: { self: true } };
        records.set(id, record);
        return record;
      }
      if (request.method === 'GET' && request.eventId) return records.get(request.eventId);
      if (request.method === 'GET') {
        assert.ok(String(request.query?.fields).includes('colorId'));
        return { accessRole: 'owner', items: [...records.values()] };
      }
      const record: Record<string, unknown> = {
        ...records.get(request.eventId!)!,
        ...request.body!,
        etag: '"v2"',
      };
      if (record.colorId === null) delete record.colorId;
      records.set(request.eventId!, record);
      return record;
    },
  });
  await f.connect();
  const requestId = randomUUID();
  const created = await f.service.createEvent({ ...eventInput, colorId: '5' }, requestId);
  assert.equal(created.colorId, '5');
  const listed = await f.service.listEvents({
    from: '2026-10-13',
    to: '2026-10-14',
    timeZone: 'Asia/Qyzylorda',
  });
  assert.equal(listed.events[0].colorId, '5');
  assert.equal(
    (await f.service.createEvent({ ...eventInput, colorId: '5' }, requestId)).id,
    created.id,
  );
  await assert.rejects(
    f.service.createEvent({ ...eventInput, colorId: '6' }, requestId),
    rejectsCode('CONFLICT'),
  );
  const recolored = await f.service.updateEvent(
    created.id,
    { ...eventInput, colorId: '11' },
    created.etag,
  );
  assert.equal(recolored.colorId, '11');
  const preserved = await f.service.updateEvent(
    created.id,
    { ...eventInput, title: 'Новое название' },
    recolored.etag,
  );
  assert.equal(preserved.colorId, '11');
  const lastPatch = requests.filter((request) => request.method === 'PATCH').at(-1)!;
  assert.equal(Object.hasOwn(lastPatch.body!, 'colorId'), false);
  const reset = await f.service.updateEvent(
    created.id,
    { ...eventInput, colorId: null },
    preserved.etag,
  );
  assert.equal(reset.colorId, undefined);
  assert.equal(
    requests.filter((request) => request.method === 'PATCH').at(-1)!.body!.colorId,
    null,
  );
  const allDay = await f.service.createEvent(
    { ...eventInput, allDay: true, time: null, colorId: '3' },
    randomUUID(),
  );
  assert.equal(allDay.colorId, '3');
  assert.equal(allDay.allDay, true);
});

test('unknown color IDs and event identity mismatches are rejected before writing', async () => {
  for (const colorId of CALENDAR_COLOR_IDS)
    assert.equal(googleEventInputSchema.safeParse({ ...eventInput, colorId }).success, true);
  for (const colorId of ['0', '12', '01', '', 'violet', '#ff0000', ' 1', 1])
    assert.equal(googleEventInputSchema.safeParse({ ...eventInput, colorId }).success, false);
  assert.equal(googleEventInputSchema.safeParse({ ...eventInput, colorId: null }).success, true);
  assert.equal(googleEventInputSchema.safeParse(eventInput).success, true);
  for (const duration of [4, 721])
    assert.equal(
      googleEventInputSchema.safeParse({ ...eventInput, duration, colorId: '1' }).success,
      false,
    );
  assert.equal(
    googleEventInputSchema.safeParse({ ...eventInput, time: '23:30', colorId: '1' }).success,
    false,
  );
  let writes = 0,
    reads = 0;
  const f = fixture({
    request: async (_config, _token, request) => {
      if (request.method === 'GET') {
        reads++;
        return rawEvent({ id: 'another-instance', recurringEventId: 'series1234' });
      }
      writes++;
      return rawEvent();
    },
  });
  await f.connect();
  await assert.rejects(
    f.service.updateEvent('event12345', eventInput, '"v1"'),
    rejectsCode('GOOGLE_INVALID_EVENT'),
  );
  assert.equal(writes, 0);
  const before = reads;
  await assert.rejects(
    f.service.updateEvent('event12345', { ...eventInput, colorId: '12' }, '"v1"'),
  );
  assert.equal(reads, before);
});

test('AI confirmation fails closed on real busy events and reauthorization', async () => {
  const f = fixture({ request: async () => ({ accessRole: 'owner', items: [rawEvent()] }) });
  await f.connect();
  await assert.rejects(
    () =>
      f.service.assertFreeSlots(
        [{ date: '2026-10-13', time: '11:30', duration: 30, title: 'Отчёт' }],
        'Asia/Qyzylorda',
      ),
    rejectsCode('CONFLICT'),
  );
  await f.service.assertFreeSlots(
    [{ date: '2026-10-13', time: '12:00', duration: 30, title: 'Отчёт' }],
    'Asia/Qyzylorda',
  );
  const tokens = JSON.parse(f.secrets.values.get('google.tokens')!);
  tokens.needsReauth = true;
  await f.secrets.saveSecret('google.tokens', JSON.stringify(tokens));
  await assert.rejects(
    () =>
      f.service.assertFreeSlots(
        [{ date: '2026-10-13', time: '12:00', duration: 30, title: 'Отчёт' }],
        'Asia/Qyzylorda',
      ),
    rejectsCode('GOOGLE_REAUTH_REQUIRED'),
  );
});

test('new Google series use create-only RRULE and freeze migration timezone, color and transparency', async () => {
  const records = new Map<string, Record<string, unknown>>(),
    requests: GoogleRequest[] = [];
  const f = fixture(
    {
      request: async (_config, _token, request) => {
        requests.push(request);
        if (request.method === 'GET') return records.get(request.eventId!);
        const id = request.body!.id as string;
        if (records.has(id)) throw { response: { status: 409 } };
        const result = { ...request.body!, etag: '"v1"', organizer: { self: true } };
        records.set(id, result);
        return result;
      },
    },
    environment,
    { ...defaultSettings, timeZone: 'UTC' },
  );
  await f.connect();
  const identity = await f.service.connectionIdentity();
  assert.match(identity, /^[a-f0-9]{64}$/);
  assert.equal(identity.includes(fakeAccess), false);
  for (const repeat of ['daily', 'weekly', 'monthly'] as const) {
    for (const allDay of [false, true]) {
      const input = { ...eventInput, repeat, allDay, time: allDay ? null : '11:00', colorId: '10' };
      const requestId = randomUUID(),
        options = {
          timeZone: 'Asia/Qyzylorda',
          expectedConnectionIdentity: identity,
          transparency: allDay ? ('transparent' as const) : ('opaque' as const),
        };
      const created = await f.service.createEvent(input, requestId, options);
      const body = requests.at(-1)!.body!;
      assert.deepEqual(body.recurrence, ['RRULE:FREQ=' + repeat.toUpperCase()]);
      assert.equal((body.start as { timeZone: string }).timeZone, 'Asia/Qyzylorda');
      assert.equal((body.end as { timeZone: string }).timeZone, 'Asia/Qyzylorda');
      assert.equal(created.colorId, '10');
      assert.equal(created.recurring, true);
      assert.equal(created.busy, !allDay);
      if (!allDay) assert.equal(created.start.dateTime, '2026-10-13T06:00:00.000Z');
      assert.equal((await f.service.createEvent(input, requestId, options)).id, created.id);
      await assert.rejects(
        f.service.createEvent(input, requestId, {
          ...options,
          transparency: allDay ? 'opaque' : 'transparent',
        }),
        rejectsCode('CONFLICT'),
      );
    }
  }
  const native = await f.service.createEvent(
    { ...eventInput, allDay: true, time: null },
    randomUUID(),
  );
  assert.equal(native.busy, true);
  assert.equal(Object.hasOwn(requests.at(-1)!.body!, 'transparency'), false);
  assert.equal(Object.hasOwn(requests.at(-1)!.body!, 'recurrence'), false);
  const before = requests.length;
  for (const repeat of ['none', 'daily', 'weekly', 'monthly'] as const)
    await assert.rejects(
      f.service.updateEvent(native.id, { ...eventInput, repeat }, native.etag),
      rejectsCode('GOOGLE_SERIES_READ_ONLY'),
    );
  assert.equal(requests.length, before, 'Recurrence changes never reach instance PATCH.');
  await f.service.disconnect();
  await f.connect();
  const changed = await f.service.connectionIdentity();
  assert.notEqual(changed, identity);
  await assert.rejects(
    f.service.withConnectionIdentity(identity, async () => true),
    rejectsCode('GOOGLE_TRANSFER_CONNECTION_CHANGED'),
  );
  const reads = requests.length;
  await assert.rejects(
    f.service.createEvent(eventInput, randomUUID(), { expectedConnectionIdentity: identity }),
    rejectsCode('GOOGLE_TRANSFER_CONNECTION_CHANGED'),
  );
  assert.equal(requests.length, reads);
});

test('deletion targets one editable instance with If-Match, and lost responses are retryable', async () => {
  const id = 'instance20261013',
    requests: GoogleRequest[] = [];
  let deleted = false,
    first = true;
  const f = fixture({
    request: async (_config, _token, request) => {
      requests.push(request);
      assert.equal(request.eventId, id);
      if (request.method === 'GET') {
        if (deleted) throw { response: { status: 404 } };
        return rawEvent({ id, recurringEventId: 'series1234' });
      }
      assert.equal(request.method, 'DELETE');
      assert.equal(request.body, undefined);
      assert.deepEqual(request.headers, { 'If-Match': '"v1"' });
      assert.deepEqual(request.query, { sendUpdates: 'none' });
      deleted = true;
      if (first) {
        first = false;
        throw new Error('Test-only lost deletion response');
      }
      return {};
    },
  });
  await f.connect();
  await assert.rejects(f.service.deleteEvent(id, '"v1"'), rejectsCode('GOOGLE_UNAVAILABLE'));
  assert.deepEqual(await f.service.deleteEvent(id, '"v1"'), { deleted: true });
  assert.deepEqual(
    requests.map((request) => request.method),
    ['GET', 'DELETE', 'GET'],
  );
  for (const status of [404, 410, 'cancelled'] as const) {
    const missing = fixture({
      request: async (_config, _token, request) => {
        assert.equal(request.method, 'GET');
        assert.equal(request.eventId, id);
        if (typeof status === 'number') throw { response: { status } };
        return { id, status };
      },
    });
    await missing.connect();
    assert.deepEqual(await missing.service.deleteEvent(id, '"v1"'), { deleted: true });
  }
});

test('Google deletion preserves series, ownership, locks and stale-version barriers', async () => {
  for (const patch of [
    { recurrence: ['RRULE:FREQ=DAILY'] },
    { organizer: { self: false } },
    { attendees: [{ self: false }] },
    { locked: true },
    { eventType: 'outOfOffice' },
  ]) {
    let writes = 0;
    const f = fixture({
      request: async (_config, _token, request) => {
        if (request.method !== 'GET') writes++;
        return rawEvent(patch);
      },
    });
    await f.connect();
    await assert.rejects(
      f.service.deleteEvent('event12345', '"v1"'),
      rejectsCode('GOOGLE_EVENT_READ_ONLY'),
    );
    assert.equal(writes, 0);
  }
  for (const changed of ['preflight', 'provider', 'identity'] as const) {
    let writes = 0;
    const f = fixture({
      request: async (_config, _token, request) => {
        if (request.method === 'GET')
          return rawEvent(
            changed === 'preflight'
              ? { etag: '"v2"' }
              : changed === 'identity'
                ? { id: 'wrong-instance' }
                : {},
          );
        writes++;
        throw { response: { status: 412 } };
      },
    });
    await f.connect();
    await assert.rejects(
      f.service.deleteEvent('event12345', '"v1"'),
      rejectsCode(changed === 'identity' ? 'GOOGLE_INVALID_EVENT' : 'CONFLICT'),
    );
    assert.equal(writes, changed === 'provider' ? 1 : 0);
  }
  const f = fixture({ request: async () => ({ id: 'wrong-instance', status: 'cancelled' }) });
  await f.connect();
  await assert.rejects(
    f.service.deleteEvent('event12345', '"v1"'),
    rejectsCode('GOOGLE_INVALID_EVENT'),
  );
});

test('read deadline aborts the transport and never returns stale availability', async () => {
  let signal: AbortSignal | undefined;
  const f = fixture({
    request: async (_config, _token, request) => {
      signal = request.signal;
      await new Promise<void>((done) => setTimeout(done, 50));
      return { items: [], accessRole: 'owner' };
    },
  });
  await f.connect();
  await assert.rejects(
    () =>
      f.service.listEvents(
        { from: '2026-10-13', to: '2026-10-14', timeZone: 'UTC' },
        { signal: AbortSignal.timeout(10) },
      ),
    rejectsCode('GOOGLE_TIMEOUT'),
  );
  assert.equal(signal?.aborted, true);
  assert.equal((await f.service.status()).lastFetchedAt, null);
});
