import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash, randomUUID } from 'node:crypto';
import type { Credentials } from 'google-auth-library';
import type { GoogleEventInput } from '../shared/types.ts';
import { AppError } from '../server/errors.ts';
import { defaultSettings } from '../server/store.ts';
import {
  createGoogleCalendarService,
  GOOGLE_CALLBACK_PATH,
  GOOGLE_CALENDAR_SCOPE,
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
function fixture(overrides: Partial<GoogleTransport> = {}, env: NodeJS.ProcessEnv = environment) {
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
    settings: async () => defaultSettings,
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

test('expanded repeats and DST folds remain read-only on both mapping and direct update', async () => {
  const recurring = rawEvent({ recurringEventId: 'series1234' });
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
