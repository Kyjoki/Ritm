import test, { type TestContext } from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve, sep } from 'node:path';
import type { AddressInfo } from 'node:net';
import { DataType, newDb } from 'pg-mem';
import type { Pool } from 'pg';
import { createApp } from '../server/index.ts';
import { PostgresStore } from '../server/postgres-store.ts';
import { Store } from '../server/store.ts';
import { WorkoutConflictError } from '../server/workouts.ts';
import { migrate } from '../migrations/migrate.ts';
import type { WorkoutDoc, WorkoutsSnapshot } from '../shared/types.ts';

const ORIGIN = 'https://ritm.example';
const PAST = '2000-01-01T00:00:00.000Z';

async function harness(t: TestContext) {
  const directory = mkdtempSync(join(tmpdir(), 'ritm-workouts-'));
  const app = createApp({
    dataDir: directory,
    seed: false,
    env: {
      NODE_ENV: 'test',
      APP_ORIGIN: ORIGIN,
      APP_LOGIN: 'test-owner',
      APP_PASSWORD: 'workouts-test-password',
      APP_SESSION_SECRET: 'workouts-test-secret-'.repeat(3),
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
    assert.ok(target.startsWith(resolve(tmpdir()) + sep));
    assert.ok(target.includes('ritm-workouts-'));
    rmSync(target, { recursive: true, force: true });
  });
  const call = (path: string, method = 'GET', cookie?: string, body?: unknown, raw?: string) =>
    fetch(base + path, {
      method,
      redirect: 'error',
      headers: {
        Origin: ORIGIN,
        'Accept-Language': 'en',
        ...(cookie ? { Cookie: cookie } : {}),
        ...(method === 'GET' ? {} : { 'Content-Type': 'application/json' }),
      },
      body: raw ?? (body === undefined ? undefined : JSON.stringify(body)),
    });
  const login = await call('/api/login', 'POST', undefined, {
    login: 'test-owner',
    password: 'workouts-test-password',
  });
  assert.equal(login.status, 200);
  const cookie = login.headers.get('set-cookie')!.split(';')[0];
  const put = async (path: string, data: unknown, expectedUpdatedAt: string | null = null) =>
    call(path, 'PUT', cookie, { data, expectedUpdatedAt });
  return { call, cookie, put };
}

const del = (path: string, version: string) =>
  `${path}?expectedUpdatedAt=${encodeURIComponent(version)}`;

test('workouts require a session', async (t) => {
  const { call } = await harness(t);
  assert.equal((await call('/api/workouts')).status, 401);
  assert.equal(
    (
      await call('/api/workouts/programs/p1', 'PUT', undefined, {
        data: {},
        expectedUpdatedAt: null,
      })
    ).status,
    401,
  );
  assert.equal((await call(del('/api/workouts/programs/p1', PAST), 'DELETE')).status, 401);
});

test('workout documents are created, updated, listed and deleted with optimistic versions', async (t) => {
  const { call, cookie, put } = await harness(t);
  const empty = (await (await call('/api/workouts', 'GET', cookie)).json()) as WorkoutsSnapshot;
  assert.deepEqual(empty, { programs: [], sessions: [] });

  const created = await put('/api/workouts/programs/prog_1', {
    name: 'Push',
    order: 1,
    nested: { sets: [1, 2] },
  });
  assert.equal(created.status, 200);
  const doc = (await created.json()) as WorkoutDoc;
  assert.equal(doc.id, 'prog_1');
  assert.deepEqual(doc.data, { name: 'Push', order: 1, nested: { sets: [1, 2] } });
  assert.equal(new Date(doc.updatedAt).toISOString(), doc.updatedAt);

  const duplicate = await put('/api/workouts/programs/prog_1', { name: 'Other' });
  assert.equal(duplicate.status, 409);
  const duplicateBody = (await duplicate.json()) as { code: string; current: WorkoutDoc };
  assert.equal(duplicateBody.code, 'CONFLICT');
  assert.deepEqual(duplicateBody.current, doc);
  const stale = await put('/api/workouts/programs/prog_1', { name: 'Other' }, PAST);
  assert.equal(stale.status, 409);
  assert.deepEqual(((await stale.json()) as { current: WorkoutDoc }).current, doc);

  const updated = await put('/api/workouts/programs/prog_1', { name: 'Pull' }, doc.updatedAt);
  assert.equal(updated.status, 200);
  const next = (await updated.json()) as WorkoutDoc;
  assert.deepEqual(next.data, { name: 'Pull' });
  assert.ok(Date.parse(next.updatedAt) > Date.parse(doc.updatedAt));

  // Nothing to return as `current` for a document that no longer exists.
  assert.equal((await put('/api/workouts/programs/ghost', {}, doc.updatedAt)).status, 404);

  const first = (await (await put('/api/workouts/sessions/s_1', { n: 1 })).json()) as WorkoutDoc;
  const second = (await (await put('/api/workouts/sessions/s_2', { n: 2 })).json()) as WorkoutDoc;
  const snapshot = (await (await call('/api/workouts', 'GET', cookie)).json()) as WorkoutsSnapshot;
  assert.deepEqual(snapshot.programs, [next]);
  assert.deepEqual(snapshot.sessions, [second, first]);

  const wrong = await call(del('/api/workouts/sessions/s_1', PAST), 'DELETE', cookie);
  assert.equal(wrong.status, 409);
  assert.deepEqual(((await wrong.json()) as { current: WorkoutDoc }).current, first);
  const removed = await call(del('/api/workouts/sessions/s_1', first.updatedAt), 'DELETE', cookie);
  assert.equal(removed.status, 204);
  assert.equal(await removed.text(), '');
  const again = await call(del('/api/workouts/sessions/s_1', first.updatedAt), 'DELETE', cookie);
  assert.equal(again.status, 404);
  assert.equal((await call('/api/workouts/sessions/s_2', 'DELETE', cookie)).status, 400);
});

test('workout payloads and identifiers are validated', async (t) => {
  const { call, cookie, put } = await harness(t);
  for (const data of [[], 'text', 5, null, true])
    assert.equal((await put('/api/workouts/programs/a', data)).status, 400);
  const send = (body: unknown, raw?: string, path = '/api/workouts/programs/a') =>
    call(path, 'PUT', cookie, body, raw);
  assert.equal((await send({ expectedUpdatedAt: null })).status, 400);
  assert.equal((await send({ data: {} })).status, 400);
  assert.equal((await send({ data: {}, expectedUpdatedAt: 'yesterday' })).status, 400);
  assert.equal((await send({ data: {}, expectedUpdatedAt: null, extra: 1 })).status, 400);
  assert.equal((await send(undefined, '{not json')).status, 400);
  const body = { data: {}, expectedUpdatedAt: null };
  assert.equal(
    (await send(body, undefined, `/api/workouts/programs/${'a'.repeat(65)}`)).status,
    400,
  );
  assert.equal((await send(body, undefined, '/api/workouts/programs/bad.id')).status, 400);
  assert.equal((await send(body, undefined, '/api/workouts/other/a')).status, 400);
  const oversized = await put('/api/workouts/programs/big', { blob: 'x'.repeat(65 * 1024) });
  assert.equal(oversized.status, 400);
  const error = (await oversized.json()) as { code: string; error: string };
  assert.equal(error.code, 'VALIDATION_ERROR');
  assert.match(error.error, /Check the workout data/);
  // {"blob":"..."} adds 11 bytes of JSON syntax around the string.
  const exact = await put('/api/workouts/programs/exact', { blob: 'x'.repeat(64 * 1024 - 11) });
  assert.equal(exact.status, 200);
  assert.equal((await put('/api/workouts/programs/id-ok_1', {})).status, 200);
});

test('workout counts are capped per collection', (t) => {
  const directory = mkdtempSync(join(tmpdir(), 'ritm-workouts-cap-'));
  const store = new Store(directory, false);
  t.after(() => {
    store.close();
    rmSync(directory, { recursive: true, force: true });
  });
  for (let index = 0; index < 300; index += 1)
    store.putWorkout('programs', `p${index}`, { index }, null);
  assert.throws(
    () => store.putWorkout('programs', 'extra', {}, null),
    (error: { status?: number; code?: string }) =>
      error.status === 400 && error.code === 'WORKOUT_LIMIT',
  );
  const existing = store.workouts().programs[0];
  store.putWorkout('programs', existing.id, { again: true }, existing.updatedAt);
  store.putWorkout('sessions', 'first', {}, null);
});

test('pg-mem: PostgreSQL store follows the same workout contract', async (t) => {
  const db = newDb({ autoCreateForeignKeyIndices: true, noAstCoverageCheck: true });
  db.public.registerFunction({
    name: 'pg_advisory_xact_lock',
    args: [DataType.integer],
    returns: DataType.integer,
    implementation: () => 0,
    impure: true,
  });
  const adapter = db.adapters.createPg();
  const pool = new adapter.Pool() as unknown as Pool;
  t.after(async () => {
    await pool.end();
  });
  assert.ok((await migrate(pool)).includes('003-workouts.sql'));
  let now = Date.parse('2026-10-13T06:00:00Z');
  const store = new PostgresStore(pool, { now: () => now });
  const created = await store.putWorkout('sessions', 's1', { reps: [5, 5] }, null);
  assert.deepEqual(created.data, { reps: [5, 5] });
  await assert.rejects(store.putWorkout('sessions', 's1', {}, null), WorkoutConflictError);
  now += 1000;
  const updated = await store.putWorkout('sessions', 's1', { reps: [6] }, created.updatedAt);
  assert.ok(Date.parse(updated.updatedAt) > Date.parse(created.updatedAt));
  await assert.rejects(
    store.deleteWorkout('sessions', 's1', created.updatedAt),
    (error) =>
      error instanceof WorkoutConflictError && error.current.updatedAt === updated.updatedAt,
  );
  now += 1000;
  await store.putWorkout('sessions', 's2', {}, null);
  const ids = async () => (await store.workouts()).sessions.map((item) => item.id);
  assert.deepEqual(await ids(), ['s2', 's1']);
  await store.deleteWorkout('sessions', 's1', updated.updatedAt);
  assert.deepEqual(await ids(), ['s2']);
  await assert.rejects(store.deleteWorkout('sessions', 's1', updated.updatedAt), /не найдена/);
});
