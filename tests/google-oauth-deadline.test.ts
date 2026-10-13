import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import type { Credentials } from 'google-auth-library';
import { AppError } from '../server/errors.ts';
import { defaultSettings } from '../server/store.ts';
import {
  createGoogleCalendarService,
  GOOGLE_CALLBACK_PATH,
  GOOGLE_CALENDAR_SCOPE,
  type GoogleCalendarService,
  type GoogleSecretStorage,
  type GoogleTransport,
} from '../server/google-calendar.ts';

const owner = 'a'.repeat(64);

function deferred() {
  let resolve!: () => void;
  const promise = new Promise<void>((done) => {
    resolve = done;
  });
  return { promise, resolve };
}

class ExpiringMemorySecrets implements GoogleSecretStorage {
  clock = 0;
  values = new Map<string, string>();
  leases = new Map<string, { token: string; expiresAt: number }>();
  mutations: string[] = [];
  async getSecret(name: string) {
    return this.values.get(name) ?? null;
  }
  async saveSecret(name: string, value: string) {
    this.mutations.push(`save:${name}`);
    this.values.set(name, value);
  }
  async removeSecret(name: string) {
    this.mutations.push(`remove:${name}`);
    this.values.delete(name);
  }
  async consumeSecret(name: string) {
    this.mutations.push(`consume:${name}`);
    const value = this.values.get(name) ?? null;
    this.values.delete(name);
    return value;
  }
  async acquireLease(name: string, ttlMs: number) {
    const previous = this.leases.get(name);
    if (previous && previous.expiresAt > this.clock) return null;
    const token = randomUUID();
    this.leases.set(name, { token, expiresAt: this.clock + ttlMs });
    return token;
  }
  async releaseLease(name: string, token: string) {
    if (this.leases.get(name)?.token === token) this.leases.delete(name);
  }
}

function fixture(overrides: Partial<GoogleTransport> = {}) {
  const secrets = new ExpiringMemorySecrets();
  let wallClock = Date.parse('2026-10-13T05:00:00Z');
  const calls = { exchange: 0, refresh: 0, request: 0 };
  const credentials = (): Credentials => ({
    access_token: 'test-only-access',
    refresh_token: 'test-only-refresh',
    expiry_date: wallClock + 3_600_000,
    scope: GOOGLE_CALENDAR_SCOPE,
  });
  const transport: GoogleTransport = {
    exchangeCode: async () => {
      calls.exchange++;
      return credentials();
    },
    refreshToken: async () => {
      calls.refresh++;
      return credentials();
    },
    request: async () => {
      calls.request++;
      return { items: [], accessRole: 'owner' };
    },
    ...overrides,
  };
  const options = {
    secrets,
    security: { hasOwnerSession: async (hash: string) => hash === owner },
    settings: async () => defaultSettings,
    now: () => wallClock,
    leaseClock: () => secrets.clock,
    env: {
      APP_ORIGIN: 'http://127.0.0.1:5173',
      GOOGLE_CLIENT_ID: '123-test.apps.googleusercontent.com',
      GOOGLE_CLIENT_SECRET: 'test-only-client-secret',
      GOOGLE_REDIRECT_URI: `http://127.0.0.1:5173${GOOGLE_CALLBACK_PATH}`,
    },
    transport,
  };
  const services = [createGoogleCalendarService(options), createGoogleCalendarService(options)];
  const start = async (service: GoogleCalendarService = services[0]) => {
    const flow = await service.connect(owner);
    return { ...flow, state: new URL(flow.authorizationUrl).searchParams.get('state')! };
  };
  const connect = async () => {
    const flow = await start();
    await services[0].callback({
      state: flow.state,
      code: 'test-only-code',
      correlationCookie: flow.correlationCookie,
    });
  };
  return {
    secrets,
    services,
    calls,
    credentials,
    start,
    connect,
    expireAccessToken: () => {
      wallClock += 3_600_001;
    },
  };
}

test('a refresh that outlives its lease cannot restore a disconnected grant', async () => {
  const entered = deferred(),
    finish = deferred();
  const f = fixture({
    refreshToken: async () => {
      entered.resolve();
      await finish.promise;
      return f.credentials();
    },
  });
  const [a, b] = f.services;
  await f.connect();
  f.expireAccessToken();
  const pending = a.listEvents({
    from: '2026-10-13',
    to: '2026-10-14',
    timeZone: defaultSettings.timeZone,
  });
  await entered.promise;
  f.secrets.clock += 180_001;
  await b.disconnect();
  const mutationsAfterDisconnect = f.secrets.mutations.length;
  assert.equal((await b.status()).status, 'disconnected');
  finish.resolve();
  await assert.rejects(
    pending,
    (error: unknown) =>
      error instanceof AppError && ['CONFLICT', 'GOOGLE_OPERATION_TIMEOUT'].includes(error.code),
  );
  assert.equal(f.secrets.mutations.length, mutationsAfterDisconnect);
  assert.equal(f.secrets.values.has('google.tokens'), false);
  assert.equal((await b.status()).status, 'disconnected');
  assert.equal(f.calls.request, 0);
  assert.equal(f.secrets.leases.size, 0);
});

test('a delayed OAuth exchange hits the operation deadline without saving a grant', async () => {
  const entered = deferred(),
    finish = deferred();
  const f = fixture({
    exchangeCode: async () => {
      entered.resolve();
      await finish.promise;
      return f.credentials();
    },
  });
  const flow = await f.start();
  const pending = f.services[0].callback({
    state: flow.state,
    code: 'test-only-code',
    correlationCookie: flow.correlationCookie,
  });
  await entered.promise;
  const mutationsBeforeResponse = f.secrets.mutations.length;
  f.secrets.clock += 45_001;
  finish.resolve();
  await assert.rejects(
    pending,
    (error: unknown) => error instanceof AppError && error.code === 'GOOGLE_OPERATION_TIMEOUT',
  );
  assert.equal(f.secrets.mutations.length, mutationsBeforeResponse);
  assert.equal(f.secrets.values.has('google.tokens'), false);
  assert.equal((await f.services[0].status()).status, 'disconnected');
  assert.equal(f.secrets.leases.size, 0);
});

test('lease acquisition consumes the deadline before any secret mutation or provider call', async () => {
  const f = fixture(),
    originalAcquire = f.secrets.acquireLease.bind(f.secrets);
  f.secrets.acquireLease = async (name, ttlMs) => {
    const token = await originalAcquire(name, ttlMs);
    f.secrets.clock += 45_001;
    return token;
  };
  await assert.rejects(
    f.services[0].connect(owner),
    (error: unknown) => error instanceof AppError && error.code === 'GOOGLE_OPERATION_TIMEOUT',
  );
  assert.deepEqual(f.secrets.mutations, []);
  assert.deepEqual(f.calls, { exchange: 0, refresh: 0, request: 0 });
  assert.equal(f.secrets.values.size, 0);
  assert.equal(f.secrets.leases.size, 0);
});
