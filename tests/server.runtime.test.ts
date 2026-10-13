import test from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { mkdtempSync, existsSync, rmSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import type { AddressInfo } from 'node:net';
import { createApp } from '../server/index.ts';
import { SqliteRuntimeState } from '../server/runtime-state.ts';
import { SecretStore } from '../server/secrets.ts';
import { Security } from '../server/security.ts';
import { AppError } from '../server/errors.ts';
import type { Request, Response } from 'express';
import type { WorkspaceRepository } from '../server/repository.ts';
import type { RuntimeState } from '../server/runtime-state.ts';

test('signed owner sessions survive another instance, revoke on logout and reject bad login', async (t) => {
  const dataDir = mkdtempSync(join(tmpdir(), 'ritm-runtime-'));
  const env = {
    NODE_ENV: 'test',
    APP_LOGIN: 'owner',
    APP_PASSWORD: 'long-test-password',
    APP_SESSION_SECRET: 'test-only-32-characters-secret-for-sessions',
  };
  const instances = [
    createApp({ dataDir, env, seed: false }),
    createApp({ dataDir, env, seed: false }),
  ];
  const servers = instances.map((instance) => instance.app.listen(0, '127.0.0.1'));
  await Promise.all(servers.map((server) => once(server, 'listening')));
  const call = async (
    index: number,
    path: string,
    method = 'GET',
    body?: unknown,
    cookie?: string,
  ) => {
    const url =
      'http://127.0.0.1:' + (servers[index].address() as AddressInfo).port + '/api' + path;
    return fetch(url, {
      method,
      headers: {
        ...(method !== 'GET' ? { 'Content-Type': 'application/json' } : {}),
        ...(cookie ? { Cookie: cookie } : {}),
      },
      ...(body ? { body: JSON.stringify(body) } : {}),
    });
  };
  t.after(async () => {
    for (let i = 0; i < servers.length; i++) {
      servers[i].closeAllConnections();
      await new Promise<void>((done) => servers[i].close(() => done()));
      await instances[i].close();
    }
    assert.ok(resolve(dataDir).startsWith(resolve(tmpdir())) && dataDir.includes('ritm-runtime-'));
    rmSync(dataDir, { recursive: true, force: true });
  });
  assert.equal(
    (await call(0, '/login', 'POST', { login: 'someone', password: env.APP_PASSWORD })).status,
    401,
  );
  const login = await call(0, '/login', 'POST', { login: 'OwNeR', password: env.APP_PASSWORD });
  assert.equal(login.status, 200);
  const cookie = login.headers.get('set-cookie')!.split(';')[0];
  assert.equal((await call(1, '/bootstrap', 'GET', undefined, cookie)).status, 200);
  assert.equal((await call(1, '/bootstrap', 'GET', undefined, cookie + 'tampered')).status, 401);
  assert.equal((await call(1, '/logout', 'POST', undefined, cookie)).status, 200);
  assert.equal((await call(0, '/bootstrap', 'GET', undefined, cookie)).status, 401);
  // Login attempts are shared across instance sockets, not reset per process.
  for (let i = 0; i < 8; i++)
    assert.equal(
      (await call(i % 2, '/login', 'POST', { login: 'owner', password: 'wrong' })).status,
      401,
    );
  assert.equal(
    (await call(1, '/login', 'POST', { login: 'owner', password: env.APP_PASSWORD })).status,
    429,
  );
});

test('shared ciphertext is portable, purpose bound, consumed once and lease owner protected', async (t) => {
  const dataDir = mkdtempSync(join(tmpdir(), 'ritm-runtime-'));
  const first = new SqliteRuntimeState(dataDir),
    second = new SqliteRuntimeState(dataDir);
  const env = { SECRET_ENCRYPTION_KEY: Buffer.alloc(32, 7).toString('base64') };
  const a = new SecretStore(dataDir, env, first, true),
    b = new SecretStore(dataDir, env, second, true);
  t.after(() => {
    first.close();
    second.close();
    assert.ok(resolve(dataDir).startsWith(resolve(tmpdir())) && dataDir.includes('ritm-runtime-'));
    rmSync(dataDir, { recursive: true, force: true });
  });
  await a.saveSecret('google-state.123', 'private-google-state');
  assert.equal(await b.getSecret('google-state.123'), 'private-google-state');
  const ciphertext = first.getServerSecret('google-state.123')!;
  assert.equal(ciphertext.includes('private-google-state'), false);
  second.setServerSecret('other-purpose', ciphertext);
  await assert.rejects(b.getSecret('other-purpose'));
  assert.equal(await a.consumeSecret('google-state.123'), 'private-google-state');
  assert.equal(await b.consumeSecret('google-state.123'), null);
  const lease = await a.acquireLease('google-refresh', 10_000);
  assert.ok(lease);
  assert.equal(await b.acquireLease('google-refresh', 10_000), null);
  await b.releaseLease('google-refresh', 'wrong-token');
  assert.equal(await b.acquireLease('google-refresh', 10_000), null);
  await a.releaseLease('google-refresh', lease!);
  assert.ok(await b.acquireLease('google-refresh', 10_000));
  await a.save({ apiKey: 'sk-test-server-only-abcdefghijklmnopqrstuvwxyz', model: 'gpt-6-luna' });
  assert.equal((await b.status()).source, 'saved');
  assert.equal(existsSync(join(dataDir, '.secret-key')), false);
  assert.equal(existsSync(join(dataDir, 'openai-secret.json')), false);
});

test('serverless health is database independent and never falls back to local data files', async (t) => {
  const dataDir = join(tmpdir(), 'ritm-no-files-' + crypto.randomUUID());
  let queries = 0;
  const repository = new Proxy(
    { close: async () => {} },
    {
      get(target, name) {
        if (name === 'close') return target.close;
        return async () => {
          queries++;
          throw new Error('Database should not be queried for health.');
        };
      },
    },
  ) as WorkspaceRepository & RuntimeState;
  const instance = createApp({
    dataDir,
    repository,
    env: {
      VERCEL: '1',
      NODE_ENV: 'production',
      DATABASE_URL: 'postgresql://not-used.invalid/ritm',
      APP_LOGIN: 'owner',
      APP_PASSWORD: 'long-test-password',
      APP_SESSION_SECRET: 'test-only-32-characters-secret-for-sessions',
      APP_ORIGIN: 'https://ritm.example',
    },
  });
  const server = instance.app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(async () => {
    server.closeAllConnections();
    await new Promise<void>((done) => server.close(() => done()));
    await instance.close();
  });
  const response = await fetch(
    'http://127.0.0.1:' + (server.address() as AddressInfo).port + '/api/health',
  );
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { status: 'ok' });
  assert.equal(queries, 0);
  assert.equal(existsSync(dataDir), false);
});

test('trusted Vercel client login limits are shared while a different client can still sign in', async (t) => {
  const dataDir = mkdtempSync(join(tmpdir(), 'ritm-runtime-'));
  const states = [new SqliteRuntimeState(dataDir), new SqliteRuntimeState(dataDir)];
  const env = {
    VERCEL: '1',
    APP_LOGIN: 'owner',
    APP_PASSWORD: 'long-test-password',
    APP_SESSION_SECRET: 'test-only-32-characters-secret-for-sessions',
    APP_ORIGIN: 'https://ritm.example',
  };
  const security = states.map((state) => new Security(env, state, dataDir));
  const request = (socket: string, headers: Record<string, string>): Request =>
    ({
      socket: { remoteAddress: socket },
      get: (name: string) => headers[name.toLowerCase()],
    }) as unknown as Request;
  const response = { cookie: () => {}, clearCookie: () => {} } as unknown as Response;
  t.after(() => {
    states.forEach((state) => state.close());
    assert.ok(resolve(dataDir).startsWith(resolve(tmpdir())) && dataDir.includes('ritm-runtime-'));
    rmSync(dataDir, { recursive: true, force: true });
  });
  for (let i = 0; i < 10; i++) {
    await assert.rejects(
      security[i % 2].login(
        request(i % 2 ? '10.0.0.1' : '10.0.0.2', { 'x-vercel-forwarded-for': '203.0.113.9' }),
        response,
        'owner',
        'wrong',
      ),
      (error: unknown) => error instanceof AppError && error.code === 'INVALID_PASSWORD',
    );
  }
  await assert.rejects(
    security[1].login(
      request('10.0.0.3', { 'x-vercel-forwarded-for': '203.0.113.9' }),
      response,
      'owner',
      env.APP_PASSWORD,
    ),
    (error: unknown) => error instanceof AppError && error.code === 'RATE_LIMIT',
  );
  assert.equal(
    (
      await security[1].login(
        request('10.0.0.1', { 'x-vercel-forwarded-for': '198.51.100.22' }),
        response,
        'owner',
        env.APP_PASSWORD,
      )
    ).authenticated,
    true,
  );
});

test('spoofed forwarding headers outside Vercel and invalid Vercel IP lists cannot reset login limits', async (t) => {
  const dataDir = mkdtempSync(join(tmpdir(), 'ritm-runtime-'));
  const state = new SqliteRuntimeState(dataDir);
  const base = {
    APP_LOGIN: 'owner',
    APP_PASSWORD: 'long-test-password',
    APP_SESSION_SECRET: 'test-only-32-characters-secret-for-sessions',
    APP_ORIGIN: 'https://ritm.example',
  };
  const regular = new Security(base, state, dataDir),
    vercel = new Security({ ...base, VERCEL: '1' }, state, dataDir);
  const request = (headers: Record<string, string>): Request =>
    ({
      socket: { remoteAddress: '192.0.2.8' },
      get: (name: string) => headers[name.toLowerCase()],
    }) as unknown as Request;
  const response = { cookie: () => {}, clearCookie: () => {} } as unknown as Response;
  t.after(() => {
    state.close();
    assert.ok(resolve(dataDir).startsWith(resolve(tmpdir())) && dataDir.includes('ritm-runtime-'));
    rmSync(dataDir, { recursive: true, force: true });
  });
  for (let i = 0; i < 10; i++) {
    await assert.rejects(
      regular.login(
        request({
          'x-vercel-forwarded-for': '203.0.113.' + (i + 1),
          'x-forwarded-for': '198.51.100.' + i,
        }),
        response,
        'owner',
        'wrong',
      ),
      (error: unknown) => error instanceof AppError && error.code === 'INVALID_PASSWORD',
    );
  }
  const spoofedHeaders: Record<string, string>[] = [
    { 'x-vercel-forwarded-for': '198.51.100.10' },
    { 'x-forwarded-for': '198.51.100.11' },
  ];
  for (const headers of spoofedHeaders) {
    await assert.rejects(
      regular.login(request(headers), response, 'owner', base.APP_PASSWORD),
      (error: unknown) => error instanceof AppError && error.code === 'RATE_LIMIT',
    );
  }
  for (const forwarded of ['', '198.51.100.9, 203.0.113.8', 'not-an-ip']) {
    await assert.rejects(
      vercel.login(
        request({ 'x-vercel-forwarded-for': forwarded }),
        response,
        'owner',
        base.APP_PASSWORD,
      ),
      (error: unknown) => error instanceof AppError && error.code === 'RATE_LIMIT',
    );
  }
});
