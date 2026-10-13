import test, { type TestContext } from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import type { AddressInfo } from 'node:net';
import type { GoogleCalendarEvent } from '../shared/types.ts';
import { createApp, type AppOptions } from '../server/index.ts';
import { Store } from '../server/store.ts';
import { calendarRange, googleOccurrences } from '../src/features/google-occurrences.ts';

const route = '/integrations/google/events';
const capture = 'integrations/google/events';

async function fixture(t: TestContext, vercel: boolean) {
  const dataDir = mkdtempSync(join(tmpdir(), 'ritm-google-read-'));
  const env = {
    NODE_ENV: 'test',
    APP_ORIGIN: 'https://ritm.example',
    APP_LOGIN: 'owner',
    APP_PASSWORD: 'test-only-owner-password',
    APP_SESSION_SECRET: 'test-only-session-signing-key-'.repeat(3),
    ...(vercel ? { VERCEL: '1' } : {}),
  };
  const reads: { from: string; to: string; timeZone: string }[] = [];
  const event: GoogleCalendarEvent = {
    id: 'event12345',
    source: 'google',
    calendarId: 'primary',
    title: 'Встреча по проекту',
    description: '',
    etag: '"v1"',
    start: { dateTime: '2026-10-13T11:00:00+05:00' },
    end: { dateTime: '2026-10-13T12:00:00+05:00' },
    timeZone: 'Asia/Qyzylorda',
    allDay: false,
    busy: true,
    readOnly: false,
  };
  const unexpected = async () => {
    throw new Error('Unexpected operation outside Google read fixture');
  };
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
      source: 'saved',
      clientId: 'test.apps.googleusercontent.com',
      hasClientSecret: true,
      redirectUri: env.APP_ORIGIN + '/api/integrations/google/callback',
    }),
    saveConfiguration: unexpected,
    removeConfiguration: unexpected,
    status: async () => status,
    connect: unexpected,
    callback: unexpected,
    createEvent: unexpected,
    updateEvent: unexpected,
    disconnect: unexpected,
    assertFreeSlots: unexpected,
    listEvents: async (input) => {
      reads.push(input);
      return { ...input, events: [event], fetchedAt: '2026-10-13T06:00:00Z', partial: false };
    },
  };
  const instance = createApp({
    dataDir,
    env,
    repository: new Store(dataDir, false),
    googleService: google,
  });
  const server = instance.app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(async () => {
    server.closeAllConnections();
    await new Promise<void>((done) => server.close(() => done()));
    await instance.close();
    assert.ok(
      resolve(dataDir).startsWith(resolve(tmpdir())) && dataDir.includes('ritm-google-read-'),
    );
    rmSync(dataDir, { recursive: true, force: true });
  });
  const base = 'http://127.0.0.1:' + (server.address() as AddressInfo).port;
  const login = await fetch(base + '/api/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ login: env.APP_LOGIN, password: env.APP_PASSWORD }),
  });
  assert.equal(login.status, 200);
  const ownerCookie = login.headers.get('set-cookie')!.split(';')[0];
  const get = async (query: string, cookie = ownerCookie, headers: Record<string, string> = {}) => {
    const response = await fetch(base + '/api' + route + '?' + query, {
      headers: { ...(cookie ? { Cookie: cookie } : {}), ...headers },
    });
    return { status: response.status, body: await response.json(), headers: response.headers };
  };
  return { get, reads, event };
}

test('Vercel Google events read accepts exact routing metadata for calendar day, week and month', async (t) => {
  const f = await fixture(t, true);
  for (const view of ['day', 'week', 'month'] as const) {
    const range = calendarRange(view, '2026-10-13');
    const query = new URLSearchParams({ ...range, timeZone: 'Asia/Qyzylorda' });
    for (const routing of [false, true]) {
      if (routing) query.set('path', capture);
      const result = await f.get(query.toString());
      assert.equal(result.status, 200, `${view} / routing ${routing}`);
      assert.equal(result.headers.get('cache-control'), 'no-store');
      assert.deepEqual(f.reads.at(-1), { ...range, timeZone: 'Asia/Qyzylorda' });
      assert.deepEqual(result.body.events, [f.event]);
      assert.equal(googleOccurrences(result.body.events, '2026-10-13', 'Asia/Qyzylorda').length, 1);
    }
  }
  assert.equal(f.reads.length, 6);
  const withoutZone = await f.get(
    'from=2026-10-13&to=2026-10-14&path=' + encodeURIComponent(capture),
  );
  assert.equal(withoutZone.status, 200);
  assert.deepEqual(f.reads.at(-1), {
    from: '2026-10-13',
    to: '2026-10-14',
    timeZone: 'Asia/Qyzylorda',
  });
});

test('routing normalization preserves strict query validation, duplicates and owner authentication', async (t) => {
  const f = await fixture(t, true);
  const valid = 'from=2026-10-13&to=2026-10-14&timeZone=Asia%2FQyzylorda';
  const metadata = '&path=' + encodeURIComponent(capture);
  for (const query of [
    valid + metadata + '&unknown=1',
    valid + '&path=another%2Froute',
    valid + metadata + metadata,
    valid + metadata + '&from=2026-10-12',
    valid + metadata + '&to=2026-10-15',
    valid + metadata + '&timeZone=Asia%2FQyzylorda',
    'to=2026-10-14&timeZone=Asia%2FQyzylorda' + metadata,
    'from=2026-02-30&to=2026-03-02' + metadata,
    'from=13.10.2026&to=2026-10-14' + metadata,
    valid + metadata + '&path%5Bextra%5D=another-route',
  ]) {
    const result = await f.get(query);
    assert.equal(result.status, 400, query);
    assert.equal(result.body.code, 'VALIDATION_ERROR');
  }
  const timezone = await f.get('from=2026-10-13&to=2026-10-14&timeZone=UTC' + metadata);
  assert.equal(timezone.status, 400);
  assert.equal(timezone.body.code, 'GOOGLE_TIMEZONE');
  assert.equal((await f.get(valid + metadata, '')).status, 401);
  assert.equal(f.reads.length, 0, 'Invalid user input must not reach Google.');
});

test('ordinary Express never trusts Vercel routing captures supplied as user parameters or headers', async (t) => {
  const f = await fixture(t, false);
  const valid = 'from=2026-10-13&to=2026-10-14&timeZone=Asia%2FQyzylorda';
  assert.equal((await f.get(valid)).status, 200);
  const injectedHeaders: Record<string, string>[] = [
    {},
    { 'x-vercel-id': 'spoofed', 'x-vercel-deployment-url': 'ritm.vercel.app' },
  ];
  for (const headers of injectedHeaders) {
    const result = await f.get(valid + '&path=' + encodeURIComponent(capture), undefined, headers);
    assert.equal(result.status, 400);
    assert.equal(result.body.code, 'VALIDATION_ERROR');
  }
  assert.equal(f.reads.length, 1);
});
