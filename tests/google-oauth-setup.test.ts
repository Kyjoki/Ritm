import test, { type TestContext } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { AppError } from '../server/errors.ts';
import { SqliteRuntimeState } from '../server/runtime-state.ts';
import { SecretStore } from '../server/secrets.ts';
import { defaultSettings } from '../server/store.ts';
import {
  createGoogleCalendarService,
  GOOGLE_CALLBACK_PATH,
  GOOGLE_CALENDAR_SCOPE,
  type GoogleCalendarService,
  type GoogleTransport,
} from '../server/google-calendar.ts';

const clientA = '123-client-a.apps.googleusercontent.com';
const clientB = '456-client-b.apps.googleusercontent.com';
const secretA = 'test-only-client-a-secret';
const secretB = 'test-only-client-b-secret';
const owner = `${'a'.repeat(64)}:${'b'.repeat(64)}`;
const rejectsCode = (code: string) => (error: unknown) =>
  error instanceof AppError && error.code === code;

function fixture(
  t: TestContext,
  envOverrides: NodeJS.ProcessEnv = {},
  transportOverrides: Partial<GoogleTransport> = {},
) {
  const dataDir = mkdtempSync(join(tmpdir(), 'ritm-google-setup-'));
  const states = [new SqliteRuntimeState(dataDir), new SqliteRuntimeState(dataDir)];
  const env: NodeJS.ProcessEnv = {
    APP_ORIGIN: 'https://ritm.example',
    SECRET_ENCRYPTION_KEY: Buffer.alloc(32, 19).toString('base64'),
    ...envOverrides,
  };
  const secrets = states.map((state) => new SecretStore(dataDir, env, state, true));
  let clock = Date.parse('2026-10-13T05:00:00Z'),
    exchanges = 0,
    refreshes = 0;
  const transport: GoogleTransport = {
    exchangeCode: async () => {
      exchanges++;
      return {
        access_token: 'test-only-google-access',
        refresh_token: 'test-only-google-refresh',
        expiry_date: clock + 3_600_000,
        scope: GOOGLE_CALENDAR_SCOPE,
      };
    },
    refreshToken: async () => {
      refreshes++;
      return {
        access_token: 'test-only-google-access-refreshed',
        expiry_date: clock + 3_600_000,
        scope: GOOGLE_CALENDAR_SCOPE,
      };
    },
    request: async () => ({ items: [], accessRole: 'owner' }),
    ...transportOverrides,
  };
  const create = (index: number, environment = env) =>
    createGoogleCalendarService({
      secrets: secrets[index],
      security: { hasOwnerSession: async (hash) => hash === owner },
      settings: async () => defaultSettings,
      env: environment,
      transport,
      now: () => clock,
    });
  const services = [create(0), create(1)];
  const reload = () => {
    const state = new SqliteRuntimeState(dataDir);
    states.push(state);
    return createGoogleCalendarService({
      secrets: new SecretStore(dataDir, env, state, true),
      security: { hasOwnerSession: async (hash) => hash === owner },
      settings: async () => defaultSettings,
      env,
      transport,
      now: () => clock,
    });
  };
  const start = async (service: GoogleCalendarService = services[0]) => {
    const flow = await service.connect(owner);
    return { ...flow, state: new URL(flow.authorizationUrl).searchParams.get('state')! };
  };
  const connect = async (service: GoogleCalendarService = services[0]) => {
    const flow = await start(service);
    await service.callback({
      state: flow.state,
      code: 'test-only-code',
      correlationCookie: flow.correlationCookie,
    });
    return flow;
  };
  t.after(() => {
    states.forEach((state) => state.close());
    assert.ok(
      resolve(dataDir).startsWith(resolve(tmpdir())) && dataDir.includes('ritm-google-setup-'),
    );
    rmSync(dataDir, { recursive: true, force: true });
  });
  return {
    services,
    secrets,
    states,
    create,
    reload,
    env,
    start,
    connect,
    counts: () => ({ exchanges, refreshes }),
    expireToken: () => {
      clock += 3_600_001;
    },
  };
}

test('saved OAuth configuration is encrypted, write-only, shared across instances and reloads', async (t) => {
  const f = fixture(t),
    [a, b] = f.services;
  assert.deepEqual(await a.configuration(), {
    configured: false,
    source: 'none',
    clientId: '',
    hasClientSecret: false,
    redirectUri: 'https://ritm.example' + GOOGLE_CALLBACK_PATH,
  });
  const saved = await a.saveConfiguration({ clientId: clientA, clientSecret: secretA });
  assert.equal(saved.source, 'saved');
  assert.equal(saved.configured, true);
  assert.equal(saved.clientId, clientA);
  assert.equal(saved.hasClientSecret, true);
  assert.deepEqual(await b.configuration(), saved);
  assert.deepEqual(await f.create(1).configuration(), saved);
  assert.deepEqual(await f.reload().configuration(), saved);
  const ciphertext = f.states[0].getServerSecret('google.oauth.configuration')!;
  assert.equal(ciphertext.includes(clientA), false);
  assert.equal(ciphertext.includes(secretA), false);
  assert.equal(JSON.stringify(saved).includes(secretA), false);
  assert.deepEqual(Object.keys(saved).sort(), [
    'clientId',
    'configured',
    'hasClientSecret',
    'redirectUri',
    'source',
  ]);
  const flow = await f.start(b),
    url = new URL(flow.authorizationUrl);
  assert.equal(url.searchParams.get('client_id'), clientA);
  assert.equal(url.searchParams.get('redirect_uri'), saved.redirectUri);
  assert.equal(flow.authorizationUrl.includes(secretA), false);
});

test('empty secret preserves only the same client and invalid input never disconnects', async (t) => {
  const f = fixture(t),
    [a] = f.services;
  await a.saveConfiguration({ clientId: clientA, clientSecret: secretA });
  await f.connect();
  const epoch = await f.secrets[0].getSecret('google.connection-epoch');
  for (const value of [
    { clientId: clientA },
    { clientId: clientA, clientSecret: '   ' },
    { clientId: clientA, clientSecret: secretA },
  ]) {
    assert.equal((await a.saveConfiguration(value)).configured, true);
    assert.equal((await a.status()).status, 'connected');
    assert.equal(await f.secrets[0].getSecret('google.connection-epoch'), epoch);
  }
  for (const value of [{ clientId: clientB }, { clientId: clientB, clientSecret: '' }])
    await assert.rejects(a.saveConfiguration(value), rejectsCode('GOOGLE_CLIENT_SECRET_REQUIRED'));
  for (const value of [
    { clientId: 'evil.example', clientSecret: secretB },
    { clientId: clientB, clientSecret: 'contains space' },
    { clientId: clientB, clientSecret: 'x'.repeat(2049) },
    { clientId: clientA, redirectUri: 'https://evil.example/callback' },
    { clientId: clientA, clientSecret: secretA, clientType: 'installed' },
  ])
    await assert.rejects(a.saveConfiguration(value), rejectsCode('GOOGLE_SETUP_INVALID'));
  assert.equal((await a.status()).status, 'connected');
  assert.equal(await f.secrets[0].getSecret('google.connection-epoch'), epoch);
});

test('environment credentials are read-only and partial environment never mixes with saved credentials', async (t) => {
  const f = fixture(t),
    [a] = f.services;
  await a.saveConfiguration({ clientId: clientA, clientSecret: secretA });
  const envService = f.create(1, {
    ...f.env,
    GOOGLE_CLIENT_ID: clientB,
    GOOGLE_CLIENT_SECRET: secretB,
  });
  assert.deepEqual(await envService.configuration(), {
    configured: true,
    source: 'environment',
    clientId: clientB,
    hasClientSecret: true,
    redirectUri: 'https://ritm.example' + GOOGLE_CALLBACK_PATH,
  });
  await assert.rejects(
    envService.saveConfiguration({ clientId: clientA, clientSecret: secretA }),
    rejectsCode('GOOGLE_ENVIRONMENT_CONFIGURATION'),
  );
  await assert.rejects(
    envService.removeConfiguration(),
    rejectsCode('GOOGLE_ENVIRONMENT_CONFIGURATION'),
  );
  for (const override of [
    { GOOGLE_CLIENT_ID: clientB },
    { GOOGLE_CLIENT_SECRET: secretB },
    { GOOGLE_CLIENT_ID: '' },
  ]) {
    const partial = f.create(1, { ...f.env, ...override });
    const setup = await partial.configuration();
    assert.equal(setup.source, 'environment');
    assert.equal(setup.configured, false);
    await assert.rejects(partial.connect(owner), rejectsCode('GOOGLE_NOT_CONFIGURED'));
    await assert.rejects(
      partial.removeConfiguration(),
      rejectsCode('GOOGLE_ENVIRONMENT_CONFIGURATION'),
    );
  }
  assert.equal((await a.configuration()).clientId, clientA);
  assert.deepEqual(f.counts(), { exchanges: 0, refreshes: 0 });
});

test('callback comes only from trusted server origins and unconfigured local origin refuses save', async (t) => {
  const f = fixture(t, { APP_ORIGIN: undefined });
  assert.equal((await f.services[0].configuration()).redirectUri, null);
  await assert.rejects(
    f.services[0].saveConfiguration({ clientId: clientA, clientSecret: secretA }),
    rejectsCode('GOOGLE_ORIGIN_REQUIRED'),
  );
  const local = f.create(1, {
    ...f.env,
    GOOGLE_REDIRECT_URI: 'http://127.0.0.1:5173' + GOOGLE_CALLBACK_PATH,
  });
  assert.equal(
    (await local.saveConfiguration({ clientId: clientA, clientSecret: secretA })).redirectUri,
    'http://127.0.0.1:5173' + GOOGLE_CALLBACK_PATH,
  );
  for (const env of [
    { ...f.env, GOOGLE_REDIRECT_URI: 'https://evil.example' + GOOGLE_CALLBACK_PATH },
    {
      ...f.env,
      APP_ORIGIN: 'https://ritm.example',
      GOOGLE_REDIRECT_URI: 'http://localhost:5173' + GOOGLE_CALLBACK_PATH,
    },
    { ...f.env, APP_ORIGIN: 'https://ritm.example/path' },
    { ...f.env, APP_ORIGIN: 'http://ritm.example' },
    {
      ...f.env,
      NODE_ENV: 'production',
      GOOGLE_REDIRECT_URI: 'http://localhost:5173' + GOOGLE_CALLBACK_PATH,
    },
  ])
    assert.throws(() => f.create(1, env));
});

test('rotation A to B to A and deletion invalidate old flows and tokens without Google revocation', async (t) => {
  const f = fixture(t),
    [a, b] = f.services;
  await a.saveConfiguration({ clientId: clientA, clientSecret: secretA });
  const old = await f.start();
  await b.saveConfiguration({ clientId: clientB, clientSecret: secretB });
  await b.saveConfiguration({ clientId: clientA, clientSecret: secretA });
  await assert.rejects(
    a.callback({
      state: old.state,
      code: 'test-only-code',
      correlationCookie: old.correlationCookie,
    }),
    rejectsCode('CONFLICT'),
  );
  assert.equal(f.counts().exchanges, 0);
  await f.connect();
  assert.equal((await a.status()).status, 'connected');
  await b.saveConfiguration({ clientId: clientA, clientSecret: secretB });
  assert.equal((await a.status()).status, 'disconnected');
  assert.equal(await f.secrets[0].getSecret('google.tokens'), null);
  const pending = await f.start();
  const removed = await b.removeConfiguration();
  assert.equal(removed.source, 'none');
  assert.equal(removed.configured, false);
  assert.equal(removed.hasClientSecret, false);
  await assert.rejects(
    a.callback({
      state: pending.state,
      code: 'test-only-code',
      correlationCookie: pending.correlationCookie,
    }),
    rejectsCode('CONFLICT'),
  );
  assert.equal((await a.status()).status, 'unconfigured');
  assert.deepEqual(f.counts(), { exchanges: 1, refreshes: 0 });
});

test('rotation between flow consumption and connection lease rejects the old code before exchange', async (t) => {
  const f = fixture(t),
    [a, b] = f.services;
  await a.saveConfiguration({ clientId: clientA, clientSecret: secretA });
  const flow = await f.start();
  let reached!: () => void, release!: () => void;
  const barrier = new Promise<void>((done) => {
    reached = done;
  });
  const pause = new Promise<void>((done) => {
    release = done;
  });
  const originalConsume = f.secrets[0].consumeSecret.bind(f.secrets[0]);
  f.secrets[0].consumeSecret = async (name) => {
    const value = await originalConsume(name);
    reached();
    await pause;
    return value;
  };
  const callback = a.callback({
    state: flow.state,
    code: 'test-only-code',
    correlationCookie: flow.correlationCookie,
  });
  await barrier;
  await b.saveConfiguration({ clientId: clientB, clientSecret: secretB });
  release();
  await assert.rejects(callback, rejectsCode('CONFLICT'));
  assert.equal(f.counts().exchanges, 0);
  assert.equal((await a.configuration()).clientId, clientB);
  assert.equal(await f.secrets[0].getSecret('google.tokens'), null);
});

test('configuration rotation serializes after an active callback and removes its grant', async (t) => {
  let reached!: () => void, release!: () => void;
  const barrier = new Promise<void>((done) => {
    reached = done;
  });
  const pause = new Promise<void>((done) => {
    release = done;
  });
  const f = fixture(
      t,
      {},
      {
        exchangeCode: async () => {
          reached();
          await pause;
          return {
            access_token: 'old-grant-access',
            refresh_token: 'old-grant-refresh',
            expiry_date: Date.parse('2026-10-13T07:00:00Z'),
            scope: GOOGLE_CALENDAR_SCOPE,
          };
        },
      },
    ),
    [a, b] = f.services;
  await a.saveConfiguration({ clientId: clientA, clientSecret: secretA });
  const flow = await f.start();
  const callback = a.callback({
    state: flow.state,
    code: 'test-only-code',
    correlationCookie: flow.correlationCookie,
  });
  await barrier;
  let rotated = false;
  const rotation = b.saveConfiguration({ clientId: clientB, clientSecret: secretB }).then(() => {
    rotated = true;
  });
  await new Promise<void>((done) => setImmediate(done));
  assert.equal(rotated, false);
  release();
  await Promise.all([callback, rotation]);
  assert.equal((await a.configuration()).clientId, clientB);
  assert.equal((await a.status()).status, 'disconnected');
  assert.equal(await f.secrets[0].getSecret('google.tokens'), null);
});

test('refresh resolves the current configuration after obtaining the shared lease', async (t) => {
  const f = fixture(t),
    [a, b] = f.services;
  await a.saveConfiguration({ clientId: clientA, clientSecret: secretA });
  await f.connect();
  f.expireToken();
  let reached!: () => void, release!: () => void;
  const barrier = new Promise<void>((done) => {
    reached = done;
  });
  const pause = new Promise<void>((done) => {
    release = done;
  });
  const originalAcquire = f.secrets[0].acquireLease.bind(f.secrets[0]);
  let first = true;
  f.secrets[0].acquireLease = async (name, ttl) => {
    if (first) {
      first = false;
      reached();
      await pause;
    }
    return originalAcquire(name, ttl);
  };
  const listing = a.listEvents({
    from: '2026-10-13',
    to: '2026-10-14',
    timeZone: 'Asia/Qyzylorda',
  });
  await barrier;
  await b.saveConfiguration({ clientId: clientB, clientSecret: secretB });
  release();
  await assert.rejects(listing, rejectsCode('GOOGLE_NOT_CONNECTED'));
  assert.equal(f.counts().refreshes, 0);
  assert.equal(await f.secrets[0].getSecret('google.tokens'), null);
});
