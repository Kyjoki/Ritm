import test from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import type { AddressInfo } from 'node:net';
import { createApp } from '../server/index.ts';
import {
  GOOGLE_CALLBACK_PATH,
  GOOGLE_CALENDAR_SCOPE,
  GOOGLE_OAUTH_COOKIE,
} from '../server/google-calendar.ts';

test('OAuth setup API is owner-only, strict, CSRF protected and never returns or audits secrets', async (t) => {
  const dataDir = mkdtempSync(join(tmpdir(), 'ritm-google-configuration-'));
  const clientId = '123-browser-setup.apps.googleusercontent.com',
    clientSecret = 'test-only-browser-setup-client-secret';
  const audit: unknown[] = [];
  let exchanges = 0;
  const env = {
    NODE_ENV: 'test',
    APP_ORIGIN: 'https://ritm.example',
    APP_LOGIN: 'owner',
    APP_PASSWORD: 'test-only-long-password',
    APP_SESSION_SECRET: 'test-only-session-signing-key-'.repeat(3),
    SECRET_ENCRYPTION_KEY: Buffer.alloc(32, 23).toString('base64'),
  };
  const instance = createApp({
    dataDir,
    seed: false,
    env,
    securityLogger: (event) => {
      audit.push(event);
    },
    googleTransport: {
      exchangeCode: async (config) => {
        exchanges++;
        assert.equal(config.clientId, clientId);
        assert.equal(config.clientSecret, clientSecret);
        assert.equal(config.redirectUri, env.APP_ORIGIN + GOOGLE_CALLBACK_PATH);
        return {
          access_token: 'test-only-access-token',
          refresh_token: 'test-only-refresh-token',
          expiry_date: Date.now() + 3_600_000,
          scope: GOOGLE_CALENDAR_SCOPE,
        };
      },
      refreshToken: async () => {
        throw new Error('Unexpected refresh');
      },
      request: async () => {
        throw new Error('Unexpected Google API call');
      },
    },
  });
  const server = instance.app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(async () => {
    server.closeAllConnections();
    await new Promise<void>((done) => server.close(() => done()));
    await instance.close();
    assert.ok(
      resolve(dataDir).startsWith(resolve(tmpdir())) &&
        dataDir.includes('ritm-google-configuration-'),
    );
    rmSync(dataDir, { recursive: true, force: true });
  });
  const base = 'http://127.0.0.1:' + (server.address() as AddressInfo).port;
  const call = async (
    path: string,
    method = 'GET',
    body?: unknown,
    cookie?: string,
    extraHeaders: Record<string, string> = {},
  ) => {
    const response = await fetch(base + '/api' + path, {
      method,
      redirect: 'manual',
      headers: {
        ...(method !== 'GET' ? { 'Content-Type': 'application/json' } : {}),
        ...(cookie ? { Cookie: cookie } : {}),
        ...extraHeaders,
      },
      ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
    });
    const raw = await response.text();
    assert.equal(raw.includes(clientSecret), false);
    assert.equal(raw.includes('test-only-access-token'), false);
    assert.equal(raw.includes('test-only-refresh-token'), false);
    return { response, body: raw.startsWith('{') ? JSON.parse(raw) : null };
  };
  const path = '/integrations/google/configuration';
  assert.equal((await call(path)).response.status, 401);
  assert.equal((await call(path, 'POST', { clientId, clientSecret })).response.status, 401);
  assert.equal((await call(path, 'DELETE')).response.status, 401);
  const login = await call('/login', 'POST', { login: env.APP_LOGIN, password: env.APP_PASSWORD });
  assert.equal(login.response.status, 200);
  const ownerCookie = login.response.headers.get('set-cookie')!.split(';')[0];
  const initial = await call(path, 'GET', undefined, ownerCookie);
  assert.deepEqual(initial.body, {
    configured: false,
    source: 'none',
    clientId: '',
    hasClientSecret: false,
    redirectUri: env.APP_ORIGIN + GOOGLE_CALLBACK_PATH,
  });
  const foreign = await call(path, 'POST', { clientId, clientSecret }, ownerCookie, {
    Origin: 'https://evil.example',
  });
  assert.equal(foreign.response.status, 403);
  const injected = await call(
    path,
    'POST',
    { clientId, clientSecret, redirectUri: 'https://evil.example' },
    ownerCookie,
  );
  assert.equal(injected.response.status, 400);
  assert.equal((await call(path, 'GET', undefined, ownerCookie)).body.configured, false);
  const saved = await call(path, 'POST', { clientId, clientSecret }, ownerCookie, {
    Origin: env.APP_ORIGIN,
  });
  assert.equal(saved.response.status, 200);
  assert.equal(saved.response.headers.get('cache-control'), 'no-store');
  assert.deepEqual(saved.body, {
    configured: true,
    source: 'saved',
    clientId,
    hasClientSecret: true,
    redirectUri: env.APP_ORIGIN + GOOGLE_CALLBACK_PATH,
  });
  assert.equal(
    (await call('/integrations/google/status', 'GET', undefined, ownerCookie)).body.status,
    'disconnected',
    'Saving a client never claims that Google consent has completed.',
  );
  assert.equal(exchanges, 0);
  const missingSecret = await call(
    path,
    'POST',
    { clientId: '456-new.apps.googleusercontent.com' },
    ownerCookie,
  );
  assert.equal(missingSecret.response.status, 400);
  assert.equal(missingSecret.body.code, 'GOOGLE_CLIENT_SECRET_REQUIRED');
  assert.equal(
    (await call(path, 'POST', { clientId, clientSecret: '' }, ownerCookie)).response.status,
    200,
  );
  assert.equal((await call('/bootstrap', 'GET', undefined, ownerCookie)).response.status, 200);

  const connected = await call('/integrations/google/connect', 'POST', {}, ownerCookie);
  assert.equal(connected.response.status, 200);
  const authorization = new URL(connected.body.authorizationUrl);
  assert.equal(authorization.searchParams.get('client_id'), clientId);
  assert.equal(authorization.searchParams.get('redirect_uri'), saved.body.redirectUri);
  const flowCookie = connected.response.headers.get('set-cookie')!.split(';')[0];
  const callback =
    '/integrations/google/callback?state=' +
    authorization.searchParams.get('state') +
    '&code=test-only-code';
  const ambiguous = await call(
    callback,
    'GET',
    undefined,
    flowCookie + '; ' + GOOGLE_OAUTH_COOKIE + '=attacker',
    { 'Sec-Fetch-Site': 'cross-site' },
  );
  assert.equal(ambiguous.response.status, 303);
  assert.match(ambiguous.response.headers.get('location')!, /code=GOOGLE_INVALID_STATE/);
  assert.equal(exchanges, 0);
  const valid = await call(callback, 'GET', undefined, flowCookie, {
    'Sec-Fetch-Site': 'cross-site',
  });
  assert.equal(valid.response.status, 303);
  assert.equal(valid.response.headers.get('location'), '/?section=settings&google=connected');
  assert.equal(valid.response.headers.get('referrer-policy'), 'no-referrer');
  assert.match(valid.response.headers.get('set-cookie')!, /Secure/);
  assert.equal(exchanges, 1);
  assert.equal(
    (await call('/integrations/google/status', 'GET', undefined, ownerCookie)).body.status,
    'connected',
  );
  assert.equal((await call(path, 'DELETE', undefined, undefined)).response.status, 401);
  assert.equal(
    (await call(path, 'DELETE', undefined, ownerCookie, { Origin: 'https://evil.example' }))
      .response.status,
    403,
  );
  assert.equal(
    (await call('/integrations/google/status', 'GET', undefined, ownerCookie)).body.status,
    'connected',
  );
  const removed = await call(path, 'DELETE', undefined, ownerCookie, { Origin: env.APP_ORIGIN });
  assert.equal(removed.response.status, 200);
  assert.deepEqual(removed.body, initial.body);
  assert.equal(
    (await call('/integrations/google/status', 'GET', undefined, ownerCookie)).body.status,
    'unconfigured',
  );
  const auditJson = JSON.stringify(audit);
  for (const value of [clientId, clientSecret, 'test-only-access-token', 'test-only-refresh-token'])
    assert.equal(auditJson.includes(value), false);
});
