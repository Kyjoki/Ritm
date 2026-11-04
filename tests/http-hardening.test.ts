import test, { type TestContext } from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import type { AddressInfo } from 'node:net';
import { gzipSync } from 'node:zlib';
import { createApp } from '../server/index.ts';
import { createSecurityAudit, type SecurityRecord } from '../server/http-security.ts';

async function harness(t: TestContext, production = false) {
  const dir = mkdtempSync(join(tmpdir(), 'ritm-http-security-'));
  const records: SecurityRecord[] = [];
  const instance = createApp({
    dataDir: dir,
    seed: false,
    env: {
      NODE_ENV: production ? 'production' : 'test',
      APP_ORIGIN: 'https://ritm.example',
      APP_LOGIN: 'owner',
      APP_PASSWORD: 'test-only-password-very-long',
      APP_SESSION_SECRET: 'test-only-32-characters-session-secret',
    },
    securityLogger: (record) => records.push(record),
  });
  const server = instance.app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const url = 'http://127.0.0.1:' + (server.address() as AddressInfo).port;
  t.after(async () => {
    server.closeAllConnections();
    await new Promise<void>((done) => server.close(() => done()));
    await instance.close();
    assert.ok(resolve(dir).startsWith(resolve(tmpdir())) && dir.includes('ritm-http-security-'));
    rmSync(dir, { recursive: true, force: true });
  });
  const call = (path: string, options: RequestInit = {}) => fetch(url + '/api' + path, options);
  const login = async () => {
    const response = await call('/login', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ login: 'owner', password: 'test-only-password-very-long' }),
    });
    assert.equal(response.status, 200);
    return response.headers.get('set-cookie')!.split(';')[0];
  };
  return { call, login, records };
}

test('compressed input is rejected and protected bodies are authenticated before parsing', async (t) => {
  const h = await harness(t);
  const compressed = await h.call('/login', {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'content-encoding': 'gzip' },
    body: gzipSync(JSON.stringify({ password: 'a'.repeat(200_000) })),
  });
  assert.equal(compressed.status, 415);
  assert.equal((await compressed.json()).code, 'ENCODING_NOT_ALLOWED');
  const invalid = { method: 'PATCH', headers: { 'content-type': 'application/json' }, body: '{' };
  const anonymous = await h.call('/settings', invalid);
  assert.equal(anonymous.status, 401);
  assert.equal((await anonymous.json()).code, 'AUTH_REQUIRED');
  const cookie = await h.login();
  const owner = await h.call('/settings', { ...invalid, headers: { ...invalid.headers, cookie } });
  assert.equal(owner.status, 400);
  assert.equal((await owner.json()).code, 'INVALID_JSON');
  assert.equal(
    (
      await h.call('/settings', {
        method: 'PATCH',
        headers: { 'content-type': 'application/json', cookie, 'content-encoding': 'identity' },
        body: JSON.stringify({ displayName: 'Максим' }),
      })
    ).status,
    200,
  );
});

test('unsafe methods, oversized input and long URLs fail with uncached safe errors', async (t) => {
  const h = await harness(t);
  for (const method of ['PUT', 'OPTIONS']) {
    const response = await h.call('/login', { method });
    assert.equal(response.status, 405);
    assert.equal(response.headers.get('cache-control'), 'no-store');
    assert.equal((await response.json()).code, 'METHOD_NOT_ALLOWED');
  }
  const large = await h.call('/login', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ login: 'owner', password: 'x'.repeat(140_000) }),
  });
  assert.equal(large.status, 413);
  const largeLogin = await h.call('/login', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ login: 'owner', password: 'x'.repeat(5000) }),
  });
  assert.equal(largeLogin.status, 413);
  const charset = await h.call('/login', {
    method: 'POST',
    headers: { 'content-type': 'application/json; charset=iso-8859-1' },
    body: '{}',
  });
  assert.equal(charset.status, 415);
  assert.equal((await charset.json()).code, 'INVALID_ENCODING');
  const long = await h.call('/health?probe=' + 'x'.repeat(9000));
  assert.equal(long.status, 414);
  assert.equal(long.headers.get('cache-control'), 'no-store');
  assert.equal((await h.call('/health', { method: 'HEAD' })).status, 200);
  const foreign = await h.call('/health', { headers: { origin: 'https://attacker.example' } });
  assert.equal(foreign.status, 403);
  assert.equal(foreign.headers.get('cache-control'), 'no-store');
});

test('production headers and audit records do not reflect attacker text or credentials', async (t) => {
  const h = await harness(t, true);
  const response = await h.call('/login?secret=never-log-query', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-request-id': 'attacker-controlled-id',
      'user-agent': 'attacker-log-injection',
    },
    body: JSON.stringify({ login: 'never-log-login', password: 'never-log-password' }),
  });
  assert.equal(response.status, 401);
  const id = response.headers.get('x-request-id');
  assert.match(id!, /^[0-9a-f-]{36}$/);
  assert.notEqual(id, 'attacker-controlled-id');
  assert.match(response.headers.get('content-security-policy')!, /object-src 'none'/);
  assert.match(response.headers.get('content-security-policy')!, /frame-ancestors 'none'/);
  assert.equal(
    response.headers.get('strict-transport-security'),
    'max-age=31536000; includeSubDomains',
  );
  assert.equal(response.headers.get('cross-origin-resource-policy'), 'same-origin');
  assert.equal(h.records.length, 1);
  assert.equal(h.records[0].requestId, id);
  assert.equal(h.records[0].event, 'request_blocked');
  assert.equal(h.records[0].status, 401);
  assert.doesNotMatch(JSON.stringify(h.records), /attacker|never-log|test-only|cookie|password/i);
  await h.login();
  assert.equal(h.records.at(-1)!.event, 'login_success');
});

test('public session and OAuth callback have independent limits before external service handling', async (t) => {
  const h = await harness(t);
  for (let i = 0; i < 20; i++) {
    const response = await h.call('/integrations/google/callback?state=fake-state&code=fake-code', {
      redirect: 'manual',
    });
    assert.equal(response.status, 303);
    assert.doesNotMatch(response.headers.get('location')!, /RATE_LIMIT/);
    await response.text();
  }
  const blocked = await h.call('/integrations/google/callback?state=fake-state&code=fake-code', {
    redirect: 'manual',
  });
  assert.match(blocked.headers.get('location')!, /code=RATE_LIMIT/);
  for (let i = 0; i < 120; i++) {
    const response = await h.call('/session');
    assert.equal(response.status, 200);
    await response.json();
  }
  const sessionBlocked = await h.call('/session');
  assert.equal(sessionBlocked.status, 429);
  assert.equal(sessionBlocked.headers.get('cache-control'), 'no-store');
  // Anonymous metadata quotas never lock the owner's separate login bucket.
  await h.login();
  assert.equal((await h.call('/health')).status, 200);
});

test('a log flood is bounded and failing sync/async audit sinks cannot interrupt protection', async () => {
  let now = 0;
  const records: SecurityRecord[] = [];
  const audit = createSecurityAudit(
    (record) => records.push(record),
    () => now,
  );
  const res = { statusCode: 401, locals: { requestId: crypto.randomUUID() } };
  for (let i = 0; i < 1000; i++) audit(res, 'request_blocked');
  assert.equal(records.length, 60);
  now = 60_001;
  audit(res, 'login_success', 200);
  assert.equal(records.length, 61);
  const broken = createSecurityAudit(() => {
    throw new Error('Log sink unavailable');
  });
  assert.doesNotThrow(() => broken(res, 'request_blocked'));
  const asyncBroken = createSecurityAudit(async () => {
    throw new Error('Async log sink unavailable');
  });
  asyncBroken(res, 'request_blocked');
  await new Promise<void>((done) => setImmediate(done));
});

test('paid model concurrency is bounded across instances and capacity returns after failure', async (t) => {
  const dir = mkdtempSync(join(tmpdir(), 'ritm-http-security-'));
  let count = 0;
  let release!: () => void;
  let ready!: () => void;
  const gate = new Promise<void>((resolve) => {
    release = resolve;
  });
  const twoRunning = new Promise<void>((resolve) => {
    ready = resolve;
  });
  const instances = [0, 1].map(() =>
    createApp({
      dataDir: dir,
      seed: false,
      env: { NODE_ENV: 'test', OPENAI_API_KEY: 'sk-test-server-only-abcdefghijklmnopqrstuvwxyz' },
      assistant: async () => {
        const call = ++count;
        if (count === 2) ready();
        await gate;
        if (call === 1) throw new Error('test-only provider failure');
        return { text: 'Готово', steps: [], proposals: [] };
      },
    }),
  );
  const servers = instances.map((instance) => instance.app.listen(0, '127.0.0.1'));
  await Promise.all(servers.map((server) => once(server, 'listening')));
  t.after(async () => {
    release();
    for (let i = 0; i < servers.length; i++) {
      servers[i].closeAllConnections();
      await new Promise<void>((done) => servers[i].close(() => done()));
      await instances[i].close();
    }
    assert.ok(resolve(dir).startsWith(resolve(tmpdir())) && dir.includes('ritm-http-security-'));
    rmSync(dir, { recursive: true, force: true });
  });
  const call = (index: number, id: string) =>
    fetch('http://127.0.0.1:' + (servers[index].address() as AddressInfo).port + '/api/chat', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ requestId: id, message: 'Спланируй день' }),
    });
  const first = call(0, crypto.randomUUID()),
    second = call(1, crypto.randomUUID());
  await twoRunning;
  const thirdId = crypto.randomUUID();
  const blocked = await call(0, thirdId);
  assert.equal(blocked.status, 429);
  assert.equal((await blocked.json()).code, 'AI_BUSY');
  assert.equal(count, 2);
  release();
  const responses = await Promise.all([first, second]);
  assert.deepEqual(responses.map((response) => response.status).sort(), [200, 500]);
  for (const response of responses) await response.text();
  assert.equal((await call(1, thirdId)).status, 200);
  assert.equal(count, 3);
});
