import test, { type TestContext } from 'node:test';
import assert from 'node:assert/strict';
import { createHash, createHmac, randomUUID } from 'node:crypto';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { SignJWT } from 'jose';
import type { Request, Response } from 'express';
import { Security } from '../server/security.ts';
import { SqliteRuntimeState } from '../server/runtime-state.ts';
import { AppError } from '../server/errors.ts';

function fixture(t: TestContext, publicHttps = false) {
  const dataDir = mkdtempSync(join(tmpdir(), 'ritm-auth-hardening-'));
  const state = new SqliteRuntimeState(dataDir);
  const env = {
    APP_LOGIN: 'owner',
    APP_PASSWORD: 'long-test-password',
    APP_SESSION_SECRET: 'test-only-session-key-'.repeat(4),
    ...(publicHttps ? { VERCEL: '1', APP_ORIGIN: 'https://ritm.example' } : {}),
  };
  const security = new Security(env, state, dataDir);
  const cookies: { name: string; value: string; options: Record<string, unknown> }[] = [];
  const response = {
    cookie: (name: string, value: string, options: Record<string, unknown>) => {
      cookies.push({ name, value, options });
    },
    clearCookie: () => {},
  } as unknown as Response;
  t.after(() => {
    state.close();
    assert.ok(
      resolve(dataDir).startsWith(resolve(tmpdir())) && dataDir.includes('ritm-auth-hardening-'),
    );
    rmSync(dataDir, { recursive: true, force: true });
  });
  return { security, state, env, cookies, response };
}
function request(
  headers: Record<string, string> = {},
  path = '/api/session',
  method = 'GET',
): Request {
  const values = { host: 'localhost:3001', ...headers };
  return {
    headers: values,
    get: (name: string) => values[name.toLowerCase() as keyof typeof values],
    socket: { remoteAddress: '127.0.0.1' },
    originalUrl: path,
    method,
  } as unknown as Request;
}
function guard(security: Security, req: Request): unknown {
  let result: unknown;
  security.originGuard(req, {} as Response, (error?: unknown) => {
    result = error;
  });
  return result;
}

test('Host guard rejects credentials, paths, fragments and noncanonical loopback aliases', (t) => {
  const { security } = fixture(t);
  for (const host of [
    'evil@localhost:3001',
    'localhost:3001/path',
    'localhost:3001?extra=1',
    'localhost:3001#fragment',
    'localhost:3001\\evil',
    ' localhost:3001',
    '127.1:3001',
    '2130706433:3001',
  ]) {
    const error = guard(security, request({ host }));
    assert.ok(error instanceof AppError && error.status === 403, 'Rejected authority: ' + host);
  }
  for (const host of ['localhost:3001', '127.0.0.1:3001', '[::1]:3001'])
    assert.equal(guard(security, request({ host })), undefined);
});

test('CSRF rejects opaque/spoofed origins and simple form bodies; OAuth exception stays exact and GET only', (t) => {
  const { security } = fixture(t);
  const bad = [
    request({ origin: 'null', 'content-type': 'application/json' }, '/api/tasks', 'POST'),
    request(
      { origin: 'http://localhost:3001.evil.example', 'content-type': 'application/json' },
      '/api/tasks',
      'POST',
    ),
    request(
      { origin: 'https://evil.example', 'content-type': 'application/json' },
      '/api/tasks',
      'POST',
    ),
    request(
      { origin: 'http://localhost:3001', 'content-type': 'text/plain' },
      '/api/tasks',
      'POST',
    ),
    request(
      { origin: 'http://localhost:3001', 'content-type': 'application/x-www-form-urlencoded' },
      '/api/login',
      'POST',
    ),
    request({ 'sec-fetch-site': 'cross-site' }, '/api/session'),
    request({ 'sec-fetch-site': 'cross-site' }, '/api/integrations/google/callback/'),
    request(
      { 'sec-fetch-site': 'cross-site', 'content-type': 'application/json' },
      '/api/integrations/google/callback',
      'POST',
    ),
  ];
  for (const req of bad) assert.ok(guard(security, req) instanceof AppError);
  assert.equal(
    guard(
      security,
      request({ 'sec-fetch-site': 'cross-site' }, '/api/integrations/google/callback?state=opaque'),
    ),
    undefined,
  );
  assert.equal(
    guard(
      security,
      request(
        { origin: 'http://localhost:3001', 'content-type': 'application/json' },
        '/api/tasks',
        'POST',
      ),
    ),
    undefined,
  );
});

test('HTTPS sessions use host-only prefix and ignore legacy cookies; duplicates never choose an identity', async (t) => {
  const { security, env, cookies, response } = fixture(t, true);
  await security.login(request(), response, env.APP_LOGIN, env.APP_PASSWORD);
  const cookie = cookies[0];
  assert.equal(cookie.name, '__Host-ritm_session');
  assert.equal(cookie.options.secure, true);
  assert.equal(cookie.options.httpOnly, true);
  assert.equal(cookie.options.sameSite, 'strict');
  assert.equal(cookie.options.path, '/');
  assert.equal('domain' in cookie.options, false);
  assert.equal(
    await security.authenticated(request({ cookie: cookie.name + '=' + cookie.value })),
    true,
  );
  assert.equal(
    await security.authenticated(request({ cookie: 'ritm_session=' + cookie.value })),
    false,
  );
  assert.equal(
    await security.authenticated(
      request({
        cookie: cookie.name + '=' + cookie.value + '; ' + cookie.name + '=' + cookie.value,
      }),
    ),
    false,
  );
  assert.equal(
    await security.authenticated(
      request({ cookie: 'ritm_session=attacker; ' + cookie.name + '=' + cookie.value }),
    ),
    true,
  );
});

test('password checking leaves the event loop responsive and bounds simultaneous expensive checks', async (t) => {
  const { security, env, response } = fixture(t, true);
  let settled = false;
  const pending = security.login(request(), response, env.APP_LOGIN, 'wrong').catch((error) => {
    settled = true;
    assert.ok(error instanceof AppError && error.code === 'INVALID_PASSWORD');
  });
  await new Promise<void>((done) => setImmediate(done));
  assert.equal(
    settled,
    false,
    'Password hashing must not finish synchronously before the event loop is serviced.',
  );
  await pending;
  const attempts = await Promise.allSettled(
    Array.from({ length: 6 }, (_, index) =>
      security.login(
        request({ 'x-vercel-forwarded-for': '203.0.113.' + (index + 1) }),
        response,
        env.APP_LOGIN,
        'wrong',
      ),
    ),
  );
  const codes = attempts.map((result) =>
    result.status === 'rejected' && result.reason instanceof AppError
      ? result.reason.code
      : 'unexpected',
  );
  assert.equal(codes.filter((code) => code === 'AUTH_BUSY').length, 2);
  assert.equal(codes.filter((code) => code === 'INVALID_PASSWORD').length, 4);
});

test('signed tokens still require algorithm, issuer, audience, owner, expiry and a live server session', async (t) => {
  const { security, state, env } = fixture(t);
  const key = Buffer.from(env.APP_SESSION_SECRET),
    version = createHmac('sha256', key)
      .update(env.APP_LOGIN + '\0' + env.APP_PASSWORD)
      .digest('hex');
  const jti = randomUUID(),
    sessionHash = version + ':' + createHash('sha256').update(jti).digest('hex');
  state.createSession(sessionHash, Date.now() + 60_000);
  const sign = async (
    patch: {
      issuer?: string;
      audience?: string;
      subject?: string;
      algorithm?: string;
      expired?: boolean;
    } = {},
  ) =>
    new SignJWT({ version })
      .setProtectedHeader({ alg: patch.algorithm ?? 'HS256' })
      .setIssuer(patch.issuer ?? 'ritm')
      .setAudience(patch.audience ?? 'ritm-owner')
      .setSubject(patch.subject ?? 'owner')
      .setJti(jti)
      .setIssuedAt()
      .setExpirationTime(Math.floor(Date.now() / 1000) + (patch.expired ? -30 : 60))
      .sign(key);
  const valid = await sign();
  assert.equal(await security.authenticated(request({ cookie: 'ritm_session=' + valid })), true);
  for (const patch of [
    { issuer: 'attacker' },
    { audience: 'other-app' },
    { subject: 'admin' },
    { algorithm: 'HS384' },
    { expired: true },
  ])
    assert.equal(
      await security.authenticated(request({ cookie: 'ritm_session=' + (await sign(patch)) })),
      false,
    );
  state.deleteSession(sessionHash);
  assert.equal(await security.authenticated(request({ cookie: 'ritm_session=' + valid })), false);
});

test('public session and OAuth callback quotas isolate trusted clients', async (t) => {
  const { security } = fixture(t, true);
  const first = request({ 'x-vercel-forwarded-for': '203.0.113.41' });
  const second = request({ 'x-vercel-forwarded-for': '198.51.100.52' });
  for (const key of ['public-session', 'oauth-callback']) {
    await security.limit(first, key, 2, 60_000);
    await security.limit(first, key, 2, 60_000);
    await assert.rejects(
      security.limit(first, key, 2, 60_000),
      (error: unknown) => error instanceof AppError && error.code === 'RATE_LIMIT',
    );
    await security.limit(second, key, 2, 60_000);
    await security.limit(second, key, 2, 60_000);
    await assert.rejects(
      security.limit(second, key, 2, 60_000),
      (error: unknown) => error instanceof AppError && error.code === 'RATE_LIMIT',
    );
  }
});

test('login, public session and OAuth callback keep separate client quotas', async (t) => {
  const { security } = fixture(t, true);
  const client = request({ 'x-vercel-forwarded-for': '203.0.113.63' });
  for (const key of ['login', 'public-session', 'oauth-callback']) {
    await security.limit(client, key, 1, 60_000);
    await assert.rejects(
      security.limit(client, key, 1, 60_000),
      (error: unknown) => error instanceof AppError && error.code === 'RATE_LIMIT',
    );
  }
});
