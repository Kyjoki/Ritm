import test, { type TestContext } from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve, sep } from 'node:path';
import type { AddressInfo } from 'node:net';
import { createApp } from '../server/index.ts';
import { SqliteRuntimeState } from '../server/runtime-state.ts';
import {
  FAILURE_BUDGET,
  LoginThrottle,
  MAX_DELAY_MS,
  lockoutDelayMs,
} from '../server/login-throttle.ts';
import {
  cleanDeviceName,
  deviceNameFromUserAgent,
  sessionPolicy,
} from '../server/session-policy.ts';
import { base32Decode, base32Encode, hotp, totpCode, verifyTotp } from '../server/totp.ts';

const password = 'two-factor-test-password-long';
const HOUR = 3_600_000;
const DAY = 24 * HOUR;
const start = Date.parse('2026-11-01T08:00:00Z');

test('TOTP matches the RFC 6238 SHA-1 vectors and base32 round-trips', () => {
  const secret = Buffer.from('12345678901234567890');
  const vectors: Array<[number, string]> = [
    [59, '94287082'],
    [1111111109, '07081804'],
    [1111111111, '14050471'],
    [1234567890, '89005924'],
    [2000000000, '69279037'],
    [20000000000, '65353130'],
  ];
  for (const [seconds, expected] of vectors)
    assert.equal(hotp(secret, Math.floor(seconds / 30), 8), expected);
  const encoded = base32Encode(secret);
  assert.equal(encoded, 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ');
  assert.deepEqual(base32Decode(encoded.toLowerCase()), secret);
  assert.equal(totpCode(encoded, 59_000), '287082');
});

test('TOTP accepts one step of clock drift and nothing wider', () => {
  const secret = base32Encode(Buffer.from('12345678901234567890'));
  const now = 1_700_000_000_000;
  assert.equal(verifyTotp(secret, totpCode(secret, now), now), Math.floor(now / 30_000));
  assert.equal(
    verifyTotp(secret, totpCode(secret, now - 30_000), now),
    Math.floor(now / 30_000) - 1,
  );
  assert.equal(
    verifyTotp(secret, totpCode(secret, now + 30_000), now),
    Math.floor(now / 30_000) + 1,
  );
  assert.equal(verifyTotp(secret, totpCode(secret, now - 60_000), now), null);
  assert.equal(verifyTotp(secret, 'abcdef', now), null);
  assert.equal(verifyTotp(secret, '12345', now), null);
});

test('lockout delay grows exponentially, is capped at 15 minutes and starts after the budget', () => {
  assert.equal(lockoutDelayMs(1), 0);
  assert.equal(lockoutDelayMs(FAILURE_BUDGET), 0);
  assert.equal(lockoutDelayMs(FAILURE_BUDGET + 1), 15_000);
  assert.equal(lockoutDelayMs(FAILURE_BUDGET + 2), 30_000);
  assert.equal(lockoutDelayMs(FAILURE_BUDGET + 3), 60_000);
  assert.equal(lockoutDelayMs(FAILURE_BUDGET + 7), MAX_DELAY_MS);
  assert.equal(lockoutDelayMs(FAILURE_BUDGET + 5000), MAX_DELAY_MS);
});

test('failure budget blocks temporarily, recovers by itself and resets after success', async (t) => {
  const directory = mkdtempSync(join(tmpdir(), 'ritm-throttle-test-'));
  const state = new SqliteRuntimeState(directory);
  t.after(() => {
    state.close();
    rmSync(directory, { recursive: true, force: true });
  });
  let now = start;
  const throttle = new LoginThrottle(state, () => now);
  for (let index = 0; index < FAILURE_BUDGET; index++) {
    await throttle.assertOpen();
    await throttle.recordFailure();
  }
  await throttle.assertOpen();
  await throttle.recordFailure();
  await assert.rejects(
    throttle.assertOpen(),
    (error: { status: number; retryAfterSeconds: number }) => {
      assert.equal(error.status, 429);
      assert.equal(error.retryAfterSeconds, 15);
      return true;
    },
  );
  now += 15_001;
  await throttle.assertOpen();
  for (let index = 0; index < 30; index++) {
    await throttle.recordFailure();
    now += 1;
  }
  await assert.rejects(throttle.assertOpen());
  now += MAX_DELAY_MS + 1;
  await throttle.assertOpen();
  await throttle.recordSuccess();
  await throttle.recordFailure();
  await throttle.assertOpen();
  // An old window is forgotten entirely.
  now += 2 * HOUR;
  await throttle.recordFailure();
  await throttle.assertOpen();
});

test('device names are bounded, cleaned and derived from the User-Agent', () => {
  assert.equal(cleanDeviceName('  Мой\u0000 iPhone\n 15  '), 'Мой iPhone 15');
  assert.equal(cleanDeviceName('x'.repeat(200)).length, 60);
  assert.equal(
    deviceNameFromUserAgent(
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile Safari/604.1',
    ),
    'Safari на iPhone',
  );
  assert.equal(deviceNameFromUserAgent(undefined), 'Неизвестное устройство');
  assert.deepEqual(sessionPolicy.web, { slidingMs: 12 * HOUR, absoluteMs: 7 * DAY });
  assert.deepEqual(sessionPolicy.ios, { slidingMs: 365 * DAY, absoluteMs: 3650 * DAY });
  assert.deepEqual(sessionPolicy['web-remembered'], {
    slidingMs: 60 * DAY,
    absoluteMs: 365 * DAY,
  });
});

async function fixture(t: TestContext, mockDate = false) {
  const directory = mkdtempSync(join(tmpdir(), 'ritm-two-factor-'));
  if (mockDate) t.mock.timers.enable({ apis: ['Date'], now: start });
  const app = createApp({
    dataDir: directory,
    seed: false,
    env: {
      NODE_ENV: 'test',
      APP_ORIGIN: 'https://ritm.example',
      APP_LOGIN: 'test-owner',
      APP_PASSWORD: password,
      APP_SESSION_SECRET: 'two-factor-test-session-secret-'.repeat(2),
    },
    securityLogger: () => {},
  });
  const server = app.app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  t.after(async () => {
    server.closeAllConnections();
    await new Promise<void>((done) => server.close(() => done()));
    await app.close();
    const target = resolve(directory);
    assert.ok(target.startsWith(resolve(tmpdir()) + sep) && target.includes('ritm-two-factor-'));
    rmSync(target, { recursive: true, force: true });
  });
  const call = (path: string, method = 'GET', cookie?: string, body?: unknown) =>
    fetch(base + path, {
      method,
      headers: {
        Origin: 'https://ritm.example',
        ...(cookie ? { Cookie: cookie } : {}),
        ...(method === 'GET' ? {} : { 'Content-Type': 'application/json' }),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  const login = async (extra: Record<string, unknown> = {}) => {
    const response = await call('/api/login', 'POST', undefined, {
      login: 'test-owner',
      password,
      ...extra,
    });
    return {
      response,
      cookie: response.headers.get('set-cookie')?.split(';')[0],
      body: (await response.json()) as Record<string, unknown>,
    };
  };
  const signedIn = async (extra: Record<string, unknown> = {}) => {
    const { response, cookie } = await login(extra);
    assert.equal(response.status, 200);
    assert.ok(cookie);
    return cookie;
  };
  return { call, login, signedIn };
}

test('two-factor login: opt-in, required code, replay refusal, recovery codes and disable', async (t) => {
  const { call, login, signedIn } = await fixture(t, true);
  const owner = await signedIn();
  const before = await (await call('/api/security', 'GET', owner)).json();
  assert.deepEqual(
    { totpEnabled: before.totpEnabled, recoveryCodesLeft: before.recoveryCodesLeft },
    { totpEnabled: false, recoveryCodesLeft: 0 },
  );
  assert.equal((await call('/api/security')).status, 401);

  const setup = await (await call('/api/security/totp/setup', 'POST', owner, {})).json();
  assert.match(setup.otpauthUrl, /^otpauth:\/\/totp\/Ritm:test-owner\?/);
  assert.match(setup.secret, /^[A-Z2-7]{32}$/);
  // A newer pending secret replaces the older one.
  const replaced = await (await call('/api/security/totp/setup', 'POST', owner, {})).json();
  assert.notEqual(replaced.secret, setup.secret);
  // Still off until confirmed.
  assert.equal((await login()).response.status, 200);
  const wrong = await call('/api/security/totp/confirm', 'POST', owner, { code: '000000' });
  assert.equal(wrong.status, 401);
  assert.equal((await wrong.json()).code, 'TOTP_INVALID');
  const confirmed = await call('/api/security/totp/confirm', 'POST', owner, {
    code: totpCode(replaced.secret, Date.now()),
  });
  assert.equal(confirmed.status, 200);
  const { recoveryCodes } = (await confirmed.json()) as { recoveryCodes: string[] };
  assert.equal(recoveryCodes.length, 10);
  assert.equal(new Set(recoveryCodes).size, 10);
  assert.match(recoveryCodes[0], /^[A-Z2-9]{5}-[A-Z2-9]{5}$/);
  const overview = await (await call('/api/security', 'GET', owner)).json();
  assert.equal(overview.totpEnabled, true);
  assert.equal(overview.recoveryCodesLeft, 10);

  // The code used to confirm is spent: it cannot also sign in (replay).
  const missing = await login();
  assert.equal(missing.response.status, 401);
  assert.equal(missing.body.code, 'TOTP_REQUIRED');
  const replay = await login({ totp: totpCode(replaced.secret, Date.now()) });
  assert.equal(replay.response.status, 401);
  assert.equal(replay.body.code, 'TOTP_INVALID');
  t.mock.timers.setTime(Date.now() + 30_000);
  const code = totpCode(replaced.secret, Date.now());
  assert.equal((await login({ totp: code })).response.status, 200);
  const reused = await login({ totp: code });
  assert.equal(reused.body.code, 'TOTP_INVALID');

  // Recovery code works exactly once.
  assert.equal(
    (await login({ recoveryCode: recoveryCodes[0].toLowerCase() })).response.status,
    200,
  );
  assert.equal((await login({ recoveryCode: recoveryCodes[0] })).body.code, 'TOTP_INVALID');
  const afterRecovery = await (await call('/api/security', 'GET', owner)).json();
  assert.equal(afterRecovery.recoveryCodesLeft, 9);
  assert.ok(!JSON.stringify(afterRecovery).includes(recoveryCodes[1]));

  // Regenerating invalidates the old set; the owner session stays valid.
  t.mock.timers.setTime(Date.now() + 30_000);
  const fresh = await call('/api/security/recovery-codes', 'POST', owner, {
    code: totpCode(replaced.secret, Date.now()),
  });
  assert.equal(fresh.status, 200);
  const newCodes = ((await fresh.json()) as { recoveryCodes: string[] }).recoveryCodes;
  assert.equal(newCodes.length, 10);
  assert.equal((await login({ recoveryCode: recoveryCodes[2] })).body.code, 'TOTP_INVALID');

  // Disabling needs the password and a second factor.
  const noFactor = await call('/api/security/totp/disable', 'POST', owner, { password });
  assert.equal(noFactor.status, 401);
  const badPassword = await call('/api/security/totp/disable', 'POST', owner, {
    password: 'not-the-password-at-all',
    recoveryCode: newCodes[0],
  });
  assert.equal(badPassword.status, 401);
  const disabled = await call('/api/security/totp/disable', 'POST', owner, {
    password,
    recoveryCode: newCodes[0],
  });
  assert.deepEqual(await disabled.json(), { totpEnabled: false });
  assert.equal((await login()).response.status, 200);
});

test('device sessions record the client, list safely and can be revoked individually or in bulk', async (t) => {
  const { call, login, signedIn } = await fixture(t, true);
  const web = await signedIn({ deviceName: 'Рабочий ноутбук' });
  const ios = await signedIn({ client: 'ios', deviceName: 'x'.repeat(100) });
  const third = await signedIn({ client: 'ios', deviceName: 'iPad' });
  assert.equal((await login({ client: 'android' })).response.status, 400);
  const list = (await (await call('/api/security', 'GET', web)).json()) as {
    sessions: Array<{
      id: string;
      client: string;
      deviceName: string;
      createdAt: string;
      lastSeenAt: string;
      current: boolean;
    }>;
  };
  assert.equal(list.sessions.length, 3);
  const mine = list.sessions.filter((session) => session.current);
  assert.equal(mine.length, 1);
  assert.equal(mine[0].client, 'web');
  assert.equal(mine[0].deviceName, 'Рабочий ноутбук');
  assert.match(mine[0].createdAt, /^2026-11-01T08:00:00Z$/);
  const phone = list.sessions.find((session) => session.deviceName.startsWith('xxxx'))!;
  assert.equal(phone.deviceName.length, 60);
  assert.equal(phone.client, 'ios');
  for (const session of list.sessions) assert.match(session.id, /^[a-f0-9]{64}$/);

  assert.equal((await call('/api/security/sessions/not-an-id', 'DELETE', web)).status, 404);
  assert.equal((await call(`/api/security/sessions/${phone.id}`, 'DELETE', web)).status, 204);
  assert.equal((await call('/api/security', 'GET', ios)).status, 401);
  assert.equal((await call('/api/security', 'GET', web)).status, 200);

  // Sign out everywhere else keeps the current session valid.
  assert.equal((await call('/api/security/sessions/revoke-others', 'POST', web, {})).status, 204);
  assert.equal((await call('/api/security', 'GET', third)).status, 401);
  const remaining = await (await call('/api/security', 'GET', web)).json();
  assert.equal(remaining.sessions.length, 1);
  assert.equal(remaining.sessions[0].current, true);

  // Revoking the current session is a logout.
  assert.equal(
    (await call(`/api/security/sessions/${remaining.sessions[0].id}`, 'DELETE', web)).status,
    204,
  );
  assert.equal((await call('/api/security', 'GET', web)).status, 401);
});

test('web sessions slide for 12 hours inside a 7 day absolute limit', async (t) => {
  const { call, signedIn } = await fixture(t, true);
  const idle = await signedIn();
  const active = await signedIn();
  t.mock.timers.setTime(start + 11 * HOUR);
  assert.equal((await call('/api/security', 'GET', idle)).status, 200);
  t.mock.timers.setTime(start + 11 * HOUR + 12 * HOUR + 60_000);
  assert.equal((await call('/api/security', 'GET', idle)).status, 401, 'idle for over 12 hours');
  // Keeping the second session busy extends it, but never beyond 7 days.
  for (let visit = 1; visit <= 15; visit++) {
    t.mock.timers.setTime(start + visit * 11 * HOUR);
    assert.equal((await call('/api/security', 'GET', active)).status, 200);
  }
  t.mock.timers.setTime(start + 7 * DAY - 10 * 60_000);
  assert.equal((await call('/api/security', 'GET', active)).status, 200);
  t.mock.timers.setTime(start + 7 * DAY + 60_000);
  assert.equal((await call('/api/security', 'GET', active)).status, 401, 'absolute limit');
});

test('a remembered computer slides for 60 days inside a 365 day limit and shows as web', async (t) => {
  const { call, signedIn } = await fixture(t, true);
  const idle = await signedIn({ remember: true });
  const active = await signedIn({ remember: true });
  const overview = await (await call('/api/security', 'GET', active)).json();
  assert.ok(overview.sessions.every((session: { client: string }) => session.client === 'web'));
  t.mock.timers.setTime(start + 59 * DAY);
  assert.equal((await call('/api/security', 'GET', idle)).status, 200);
  t.mock.timers.setTime(start + 59 * DAY + 60 * DAY + 60_000);
  assert.equal((await call('/api/security', 'GET', idle)).status, 401, 'idle for over 60 days');
  for (let visit = 1; visit <= 8; visit++) {
    t.mock.timers.setTime(start + visit * 45 * DAY);
    assert.equal((await call('/api/security', 'GET', active)).status, 200, 'used every 45 days');
  }
  t.mock.timers.setTime(start + 365 * DAY + 60_000);
  assert.equal((await call('/api/security', 'GET', active)).status, 401, 'absolute limit');
});

test('without remember a plain web login keeps the short policy', async (t) => {
  const { call, signedIn } = await fixture(t, true);
  const plain = await signedIn({ remember: false });
  t.mock.timers.setTime(start + 13 * HOUR);
  assert.equal((await call('/api/security', 'GET', plain)).status, 401);
});

test('iOS sessions slide for a year and end only after a year without use', async (t) => {
  const { call, signedIn } = await fixture(t, true);
  const idle = await signedIn({ client: 'ios' });
  const active = await signedIn({ client: 'ios' });
  t.mock.timers.setTime(start + 364 * DAY);
  assert.equal((await call('/api/security', 'GET', idle)).status, 200);
  assert.equal((await call('/api/security', 'GET', active)).status, 200);
  t.mock.timers.setTime(start + 364 * DAY + 365 * DAY + 60_000);
  assert.equal((await call('/api/security', 'GET', idle)).status, 401, 'idle for over a year');
  for (let step = 2; step <= 9; step++) {
    t.mock.timers.setTime(start + step * 364 * DAY);
    assert.equal((await call('/api/security', 'GET', active)).status, 200, 'used yearly');
  }
});

test('repeated wrong passwords slow the account down but a pause lets the owner back in', async (t) => {
  const { call, login } = await fixture(t, true);
  // Failures spread over 42 minutes stay inside the per-address limit; the 21st exceeds the budget.
  for (let attempt = 0; attempt <= FAILURE_BUDGET; attempt++) {
    t.mock.timers.setTime(start + attempt * 2 * 60_000);
    assert.equal((await login({ password: 'definitely-wrong-password' })).response.status, 401);
  }
  // Even the right password waits once the budget is spent.
  const locked = await login();
  assert.equal(locked.response.status, 429);
  assert.equal(locked.body.code, 'LOGIN_LOCKED');
  assert.ok(Number(locked.body.retryAfterSeconds) <= 900);
  // The delay is finite: after it passes the owner signs in and the budget resets.
  t.mock.timers.setTime(Date.now() + 16_000);
  const recovered = await login();
  assert.equal(recovered.response.status, 200);
  assert.equal((await call('/api/security', 'GET', recovered.cookie)).status, 200);
});

test('a wrong second factor spends the same budget as a wrong password', async (t) => {
  const { call, login, signedIn } = await fixture(t, true);
  const owner = await signedIn();
  const setup = await (await call('/api/security/totp/setup', 'POST', owner, {})).json();
  const confirm = await call('/api/security/totp/confirm', 'POST', owner, {
    code: totpCode(setup.secret, Date.now()),
  });
  assert.equal(confirm.status, 200);
  for (let attempt = 0; attempt < FAILURE_BUDGET + 1; attempt++) {
    t.mock.timers.setTime(start + (attempt + 1) * 2 * 60_000);
    const result = await login({ totp: '000000' });
    assert.equal(result.body.code, 'TOTP_INVALID');
  }
  assert.equal((await login({ totp: '000000' })).response.status, 429);
});

test('blocked requests are logged with a keyed address hash and a route family only', async (t) => {
  const directory = mkdtempSync(join(tmpdir(), 'ritm-two-factor-'));
  const records: Array<Record<string, unknown>> = [];
  const app = createApp({
    dataDir: directory,
    seed: false,
    env: {
      NODE_ENV: 'test',
      APP_ORIGIN: 'https://ritm.example',
      APP_LOGIN: 'test-owner',
      APP_PASSWORD: password,
      APP_SESSION_SECRET: 'two-factor-test-session-secret-'.repeat(2),
    },
    securityLogger: (record) => {
      records.push({ ...record });
    },
  });
  const server = app.app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(async () => {
    server.closeAllConnections();
    await new Promise<void>((done) => server.close(() => done()));
    await app.close();
    rmSync(directory, { recursive: true, force: true });
  });
  const port = (server.address() as AddressInfo).port;
  const response = await fetch(`http://127.0.0.1:${port}/api/security/sessions/abc`, {
    method: 'DELETE',
    headers: { Origin: 'https://ritm.example', 'Content-Type': 'application/json' },
  });
  assert.equal(response.status, 401);
  const blocked = records.find((record) => record.event === 'request_blocked')!;
  assert.match(String(blocked.ipHash), /^[a-f0-9]{16}$/);
  assert.equal(blocked.route, 'security/sessions');
  assert.ok(!JSON.stringify(records).includes('127.0.0.1'));
});
