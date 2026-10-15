import test from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import type { AddressInfo } from 'node:net';
import { createApp } from '../server/index.ts';

test('Telegram links only a private chat through a short-lived owner-issued start link', async (t) => {
  const dataDir = mkdtempSync(join(tmpdir(), 'ritm-telegram-'));
  const botToken = '123456789:' + 'a'.repeat(35);
  const methods: string[] = [];
  const transport: typeof fetch = async (input, init) => {
    const method = new URL(String(input)).pathname.split('/').at(-1)!;
    methods.push(method);
    const result = method === 'getMe' ? { id: 17, is_bot: true, username: 'RitmTestBot' } : true;
    assert.equal(init?.method, 'POST');
    if (method === 'setWebhook') {
      const body = JSON.parse(String(init?.body));
      assert.equal(body.url, 'https://ritm.example.com/api/integrations/telegram/webhook');
      assert.deepEqual(body.allowed_updates, ['message']);
      assert.ok(body.secret_token);
    }
    return new Response(JSON.stringify({ ok: true, result }), { status: 200 });
  };
  const instance = createApp({
    dataDir,
    seed: false,
    telegramTransport: transport,
    env: {
      NODE_ENV: 'test',
      APP_ORIGIN: 'https://ritm.example.com',
      SECRET_ENCRYPTION_KEY: Buffer.alloc(32, 8).toString('base64'),
    },
  });
  const server = instance.app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}/api/integrations/telegram`;
  t.after(async () => {
    server.closeAllConnections();
    await new Promise<void>((done) => server.close(() => done()));
    await instance.close();
    assert.ok(resolve(dataDir).startsWith(resolve(tmpdir())) && dataDir.includes('ritm-telegram-'));
    rmSync(dataDir, { recursive: true, force: true });
  });
  const call = async (
    path: string,
    method = 'GET',
    body?: unknown,
    headers: Record<string, string> = {},
  ) => {
    const response = await fetch(base + path, {
      method,
      headers: { ...(method === 'GET' ? {} : { 'Content-Type': 'application/json' }), ...headers },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
    return { status: response.status, body: (await response.json()) as Record<string, any> };
  };
  assert.equal((await call('/configuration', 'POST', { botToken })).status, 200);
  assert.deepEqual(methods, ['getMe', 'setWebhook']);
  const pairing = await call('/pairing', 'POST', {});
  assert.equal(pairing.status, 200);
  const code = new URL(pairing.body.pairingUrl).searchParams.get('start')!;
  assert.equal(code.length, 43);
  const header = {
    'x-telegram-bot-api-secret-token': JSON.parse(
      (await instance.secrets.getSecret('telegram-connection'))!,
    )?.webhookSecret,
  };
  const update = (chatId: number, type: string, text: string) => ({
    update_id: 1,
    message: { text, from: { id: 42, first_name: 'Owner' }, chat: { id: chatId, type } },
  });
  assert.equal(
    (await call('/webhook', 'POST', update(42, 'private', `/start ${code}`))).status,
    403,
  );
  assert.equal((await call('/status')).body.linked, false);
  assert.equal(
    (await call('/webhook', 'POST', update(-42, 'group', `/start ${code}`), header)).status,
    200,
  );
  assert.equal(
    (await call('/webhook', 'POST', update(42, 'private', '/start wrong'), header)).status,
    200,
  );
  assert.equal((await call('/status')).body.linked, false);
  assert.equal(
    (await call('/webhook', 'POST', update(42, 'private', `/start ${code}`), header)).status,
    200,
  );
  const linked = (await call('/status')).body;
  assert.equal(linked.linked, true);
  assert.equal(linked.pairingUrl, undefined);
  assert.equal(linked.account.firstName, 'Owner');
  assert.equal((await call('/pairing', 'POST', {})).status, 409);
  assert.equal((await call('/connection', 'DELETE')).status, 200);
  assert.equal((await call('/status')).body.configured, false);
  assert.deepEqual(methods, ['getMe', 'setWebhook', 'deleteWebhook']);
});
