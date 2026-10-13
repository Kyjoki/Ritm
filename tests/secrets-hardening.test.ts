import test from 'node:test';
import assert from 'node:assert/strict';
import { createCipheriv, randomBytes } from 'node:crypto';
import { SecretStore } from '../server/secrets.ts';
import { AppError } from '../server/errors.ts';
import type { RuntimeState } from '../server/runtime-state.ts';

const fixtureKey = '11'.repeat(32),
  fakeKey = 'sk-secrets-test-only-abcdefghijklmnopqrstuvwxyz';
function fixture() {
  const records = new Map<string, string>();
  const state: RuntimeState = {
    createSession: () => {},
    hasSession: () => false,
    deleteSession: () => {},
    consumeRateLimit: () => ({ allowed: true, retryAfterMs: 0 }),
    getServerSecret: (name) => records.get(name) ?? null,
    setServerSecret: (name, value) => {
      records.set(name, value);
    },
    deleteServerSecret: (name) => {
      records.delete(name);
    },
    consumeServerSecret: (name) => {
      const value = records.get(name) ?? null;
      records.delete(name);
      return value;
    },
    acquireLease: () => 'fixture',
    releaseLease: () => {},
  };
  return {
    records,
    store: new SecretStore('unused-no-files', { SECRET_ENCRYPTION_KEY: fixtureKey }, state, true),
    state,
  };
}
const rejectsStoreError = (error: unknown) =>
  error instanceof AppError &&
  error.code === 'SECRET_STORE_ERROR' &&
  !error.message.includes(fakeKey);

test('encrypted envelopes reject authentication-tag truncation, malformed encoding and row substitution', async () => {
  const f = fixture();
  await f.store.save({ apiKey: fakeKey, model: 'gpt-6-luna' });
  const original = f.records.get('openai')!,
    envelope = JSON.parse(original);
  for (const size of [4, 8, 12, 15]) {
    f.records.set(
      'openai',
      JSON.stringify({
        ...envelope,
        tag: Buffer.from(envelope.tag, 'base64').subarray(0, size).toString('base64'),
      }),
    );
    await assert.rejects(() => f.store.credentials(), rejectsStoreError);
  }
  f.records.set('openai', JSON.stringify({ ...envelope, ciphertext: `${envelope.ciphertext}\n` }));
  await assert.rejects(() => f.store.credentials(), rejectsStoreError);
  f.records.set('openai', JSON.stringify({ ...envelope, extra: 'unsupported' }));
  await assert.rejects(() => f.store.credentials(), rejectsStoreError);
  f.records.set('google.tokens', original);
  await assert.rejects(() => f.store.getSecret('google.tokens'), rejectsStoreError);
  f.records.set('openai', original);
  assert.equal((await f.store.credentials())!.apiKey, fakeKey);
});

test('legacy 128-bit tags remain readable only in the original OpenAI slot', async () => {
  const f = fixture(),
    iv = randomBytes(12),
    cipher = createCipheriv('aes-256-gcm', Buffer.from(fixtureKey, 'hex'), iv);
  const ciphertext = Buffer.concat([
    cipher.update(JSON.stringify({ apiKey: fakeKey, model: 'gpt-6-luna' }), 'utf8'),
    cipher.final(),
  ]);
  const envelope = JSON.stringify({
    version: 1,
    iv: iv.toString('base64'),
    tag: cipher.getAuthTag().toString('base64'),
    ciphertext: ciphertext.toString('base64'),
  });
  f.records.set('openai', envelope);
  assert.equal((await f.store.credentials())!.apiKey, fakeKey);
  f.records.set('google.tokens', envelope);
  await assert.rejects(() => f.store.getSecret('google.tokens'), rejectsStoreError);
});

test('credential shapes and cryptographic configuration fail safely instead of leaking or silently accepting malformed data', async () => {
  const f = fixture();
  await f.store.saveSecret(
    'openai',
    JSON.stringify({ apiKey: fakeKey, model: 'model', unrelated: 'http://169.254.169.254' }),
  );
  await assert.rejects(() => f.store.credentials(), rejectsStoreError);
  await assert.rejects(
    () => f.store.save({ apiKey: fakeKey, model: 'https://example.invalid/model' }),
    (error: unknown) => error instanceof AppError && error.code === 'SECRET_INVALID',
  );
  const malformed = new SecretStore(
    'unused-no-files',
    { SECRET_ENCRYPTION_KEY: `${Buffer.from(fixtureKey, 'hex').toString('base64')}#` },
    f.state,
    true,
  );
  await assert.rejects(() => malformed.saveSecret('google.tokens', '{}'), rejectsStoreError);
  await assert.rejects(
    () => f.store.saveSecret('google.tokens', 'a'.repeat(65537)),
    (error: unknown) => error instanceof AppError && error.code === 'SECRET_TOO_LARGE',
  );
  await assert.rejects(() => f.store.saveSecret('../openai', 'x'));
});
