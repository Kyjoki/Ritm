import test, { type TestContext } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { once } from 'node:events';
import { mkdtempSync, rmSync } from 'node:fs';
import type { AddressInfo } from 'node:net';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { SignJWT } from 'jose';
import { createApp } from '../server/index.ts';
import { SqliteRuntimeState } from '../server/runtime-state.ts';
import { Store } from '../server/store.ts';
import { REMINDER_HEARTBEAT_NAME } from '../server/telegram.ts';

const route = '/api/integrations/telegram/reminders/run';
const origin = 'https://ritm.example.com';
const currentKey = 'test-only-current-qstash-signing-key';
const nextKey = 'test-only-next-qstash-signing-key';

async function signature(body: string, key = currentKey, subject = origin + route) {
  return new SignJWT({ body: createHash('sha256').update(body).digest('base64url') })
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuer('Upstash')
    .setSubject(subject)
    .setIssuedAt()
    .setExpirationTime('5m')
    .sign(new TextEncoder().encode(key));
}

async function fixture(t: TestContext) {
  const dataDir = mkdtempSync(join(tmpdir(), 'ritm-reminder-http-'));
  const state = new SqliteRuntimeState(dataDir);
  const instance = createApp({
    dataDir,
    seed: false,
    repository: new Store(dataDir, false),
    runtimeState: state,
    env: {
      NODE_ENV: 'test',
      VERCEL: '1',
      APP_ORIGIN: origin,
      APP_LOGIN: 'owner',
      APP_PASSWORD: 'test-only-owner-password',
      APP_SESSION_SECRET: 'test-only-session-signing-key-'.repeat(3),
      SECRET_ENCRYPTION_KEY: Buffer.alloc(32, 4).toString('base64'),
      QSTASH_CURRENT_SIGNING_KEY: currentKey,
      QSTASH_NEXT_SIGNING_KEY: nextKey,
    },
    telegramTransport: async () => {
      throw new Error('HTTP signature tests must not contact Telegram');
    },
  });
  // A normal IncomingMessage is the contract after disabling Vercel helpers.
  // Express must parse JSON while preserving the exact bytes for QStash.
  const server = instance.app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(async () => {
    server.closeAllConnections();
    await new Promise<void>((done) => server.close(() => done()));
    await instance.close();
    state.close();
    assert.ok(
      resolve(dataDir).startsWith(resolve(tmpdir())) && dataDir.includes('ritm-reminder-http-'),
    );
    rmSync(dataDir, { recursive: true, force: true });
  });
  const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  const call = (body: string, token?: string, schedule = 'ritm-telegram-reminders', query = '') =>
    fetch(base + route + query, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Upstash-Schedule-Id': schedule,
        ...(token ? { 'Upstash-Signature': token } : {}),
      },
      body,
    });
  return { call, state };
}

test('HTTP reminders preserve signed JSON bytes and accept both QStash rotation keys', async (t) => {
  const f = await fixture(t);
  const body = '{\n  "message": "Проверка ✓", "value": 1\n}\n';
  for (const key of [currentKey, nextKey]) {
    f.state.deleteServerSecret(REMINDER_HEARTBEAT_NAME);
    const response = await f.call(
      body,
      await signature(body, key),
      'ritm-telegram-reminders',
      '?path=integrations%2Ftelegram%2Freminders%2Frun',
    );
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { busy: false, sent: 0 });
    assert.ok(Number(f.state.getServerSecret(REMINDER_HEARTBEAT_NAME)) > 0);
  }
});

test('HTTP reminders reject byte changes, missing signatures and incorrect destination or schedule', async (t) => {
  const f = await fixture(t);
  const signed = await signature('{"value":1}');
  const cases = [
    { body: '{ "value": 1 }', token: signed },
    { body: '{"value":2}', token: signed },
    { body: '{"value":1}', token: undefined },
    { body: '{"value":1}', token: 'malformed-token' },
    {
      body: '{"value":1}',
      token: await signature('{"value":1}', currentKey, origin + '/other'),
    },
    { body: '{"value":1}', token: signed, schedule: 'another-schedule' },
  ];
  for (const entry of cases) {
    const response = await f.call(entry.body, entry.token, entry.schedule);
    assert.equal(response.status, 401);
    assert.equal((await response.json()).code, 'REMINDER_AUTH_REQUIRED');
    assert.equal(f.state.getServerSecret(REMINDER_HEARTBEAT_NAME), null);
  }
});

test('HTTP reminder JSON parsing and size limits remain enforced without platform helpers', async (t) => {
  const f = await fixture(t);
  const malformed = '{"value":';
  assert.equal((await f.call(malformed, await signature(malformed))).status, 400);
  const oversized = JSON.stringify({ value: 'x'.repeat(128 * 1024) });
  assert.equal((await f.call(oversized, await signature(oversized))).status, 413);
  assert.equal(f.state.getServerSecret(REMINDER_HEARTBEAT_NAME), null);
});
