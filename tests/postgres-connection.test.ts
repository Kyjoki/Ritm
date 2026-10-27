import test from 'node:test';
import assert from 'node:assert/strict';
import pg from 'pg';
import type { ConnectionOptions } from 'node:tls';
import { postgresConnectionString } from '../server/postgres-connection.ts';

test('legacy pg TLS aliases keep certificate and hostname verification without warnings', (t) => {
  const warnings = t.mock.method(process, 'emitWarning', () => {});
  for (const mode of ['require', 'prefer', 'verify-ca', 'verify-full']) {
    const connectionString = postgresConnectionString(
      `postgresql://owner:p%40ss%2Fword@db.example:5432/ritm?sslmode=${mode}&channel_binding=require&application_name=ritm`,
    );
    const url = new URL(connectionString);
    assert.equal(url.searchParams.get('sslmode'), 'verify-full');
    assert.equal(url.searchParams.get('channel_binding'), 'require');
    const client = new pg.Client({ connectionString });
    assert.equal(client.host, 'db.example');
    assert.equal(client.user, 'owner');
    assert.equal(client.password, 'p@ss/word');
    assert.equal(client.database, 'ritm');
    assert.equal(client.port, 5432);
    const ssl = client.ssl as boolean | ConnectionOptions;
    assert.ok(ssl && typeof ssl === 'object');
    // Undefined uses Node's strict defaults; no certificate/hostname bypass.
    assert.notEqual(ssl.rejectUnauthorized, false);
    assert.equal(ssl.checkServerIdentity, undefined);
  }
  assert.equal(warnings.mock.callCount(), 0);
});

test('explicit local and libpq connection modes retain their existing behavior', () => {
  for (const value of [
    '/var/run/postgresql ritm',
    'postgresql://localhost/ritm',
    'postgresql://localhost/ritm?sslmode=disable',
    'postgresql://localhost/ritm?sslmode=require&uselibpqcompat=true',
  ])
    assert.equal(postgresConnectionString(value), value);
  assert.equal(
    new pg.Client({
      connectionString: postgresConnectionString('postgresql://localhost/ritm?sslmode=disable'),
    }).ssl,
    false,
  );
});

test('normalization preserves credentials and TLS options and follows pg duplicate semantics', () => {
  const input =
    'postgres://a%2Bb:p%25%3F%23%40@db.example/ritm?sslmode=disable&sslmode=require&sslrootcert=%2Fcerts%2Froot.pem&sslcert=%2Fcerts%2Fclient.pem&sslkey=%2Fcerts%2Fclient.key&options=-c%20statement_timeout%3D5000';
  const before = new URL(input);
  const after = new URL(postgresConnectionString(input));
  assert.equal(after.username, before.username);
  assert.equal(after.password, before.password);
  for (const key of ['sslrootcert', 'sslcert', 'sslkey', 'options'])
    assert.equal(after.searchParams.get(key), before.searchParams.get(key));
  assert.deepEqual(after.searchParams.getAll('sslmode'), ['verify-full']);
  const disabled = 'postgres://localhost/db?sslmode=require&sslmode=disable';
  assert.equal(postgresConnectionString(disabled), disabled);
});

test('invalid connection errors never expose URL credentials', () => {
  assert.throws(
    () => postgresConnectionString('postgres://owner:secret-password@[broken/db'),
    (error: Error) => {
      assert.equal(error.message, 'Invalid PostgreSQL connection URL.');
      assert.ok(!JSON.stringify(error).includes('secret-password'));
      return true;
    },
  );
});
