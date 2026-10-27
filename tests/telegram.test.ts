import test from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import type { AddressInfo } from 'node:net';
import { createApp } from '../server/index.ts';
import type { GoogleEventInput } from '../shared/types.ts';

test('Telegram links only a private chat through a short-lived owner-issued start link', async (t) => {
  const dataDir = mkdtempSync(join(tmpdir(), 'ritm-telegram-'));
  const botToken = '123456789:' + 'a'.repeat(35);
  const methods: string[] = [];
  const webhookRegistrations: Record<string, unknown>[] = [];
  const sent: { text: string; reply_markup?: unknown }[] = [];
  const transport: typeof fetch = async (input, init) => {
    const method = new URL(String(input)).pathname.split('/').at(-1)!;
    methods.push(method);
    const result = method === 'getMe' ? { id: 17, is_bot: true, username: 'RitmTestBot' } : true;
    if (method === 'sendMessage') sent.push(JSON.parse(String(init?.body)));
    assert.equal(init?.method, 'POST');
    if (method === 'setWebhook') {
      const body = JSON.parse(String(init?.body));
      webhookRegistrations.push(body);
      assert.equal(body.url, 'https://ritm.example.com/api/integrations/telegram/webhook');
      assert.deepEqual(body.allowed_updates, ['message', 'callback_query']);
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
  assert.match(sent.at(-1)!.text, /Чат подключён/);
  assert.ok(sent.at(-1)!.reply_markup);
  const reminderSettings = await call('/reminders', 'PATCH', { enabled: true, leadMinutes: 10 });
  assert.equal(reminderSettings.status, 200);
  assert.equal(reminderSettings.body.reminders.enabled, true);
  assert.equal(reminderSettings.body.reminders.ready, false);
  assert.equal((await call('/reminders/test', 'POST', {})).status, 200);
  assert.match(sent.at(-1)!.text, /Тестовое уведомление/);
  assert.equal(
    (await call('/webhook', 'POST', update(42, 'private', '🔔 Напоминания'), header)).status,
    200,
  );
  assert.match(sent.at(-1)!.text, /Предупреждение: за 10 мин/);
  assert.equal(
    (await call('/webhook', 'POST', update(42, 'private', '➕ Добавить дело'), header)).status,
    200,
  );
  assert.equal(
    (await call('/webhook', 'POST', update(42, 'private', 'Купить лекарства завтра'), header))
      .status,
    200,
  );
  const confirmation = sent.at(-1)!;
  assert.match(confirmation.text, /Купить лекарства/);
  const expectedTomorrow = new Date(Date.now() + 86_400_000).toLocaleDateString('sv-SE', {
    timeZone: 'Asia/Qyzylorda',
  });
  assert.match(confirmation.text, new RegExp(expectedTomorrow));
  const save = (confirmation.reply_markup as { inline_keyboard: { callback_data: string }[][] })
    .inline_keyboard[0][0].callback_data;
  const legacy = JSON.parse((await instance.secrets.getSecret('telegram-connection'))!);
  delete legacy.webhookVersion;
  await instance.secrets.saveSecret('telegram-connection', JSON.stringify(legacy));
  assert.equal((await call('/status')).body.linked, true);
  assert.equal(webhookRegistrations.length, 2);
  assert.equal(webhookRegistrations[1].drop_pending_updates, false);
  assert.equal(
    (
      await call(
        '/webhook',
        'POST',
        {
          update_id: 2,
          callback_query: {
            id: 'callback-1',
            from: { id: 42 },
            data: save,
            message: { chat: { id: 42, type: 'private' } },
          },
        },
        header,
      )
    ).status,
    200,
  );
  assert.match(sent.at(-1)!.text, /Сохранено/);
  const sentAfterSave = sent.length;
  assert.equal(
    (
      await call(
        '/webhook',
        'POST',
        {
          update_id: 3,
          callback_query: {
            id: 'callback-2',
            from: { id: 42 },
            data: save,
            message: { chat: { id: 42, type: 'private' } },
          },
        },
        header,
      )
    ).status,
    200,
  );
  assert.equal(sent.length, sentAfterSave);
  assert.equal(
    (await call('/webhook', 'POST', update(42, 'private', '➕ Добавить дело'), header)).status,
    200,
  );
  assert.equal(
    (await call('/webhook', 'POST', update(42, 'private', 'Позвонить врачу'), header)).status,
    200,
  );
  const retrySave = (
    sent.at(-1)!.reply_markup as { inline_keyboard: { callback_data: string }[][] }
  ).inline_keyboard[0][0].callback_data;
  const createTask = instance.store.createTask.bind(instance.store);
  instance.store.createTask = () => {
    throw new Error('temporary database failure');
  };
  const answersBeforeFailure = methods.filter((method) => method === 'answerCallbackQuery').length;
  assert.equal(
    (
      await call(
        '/webhook',
        'POST',
        {
          update_id: 4,
          callback_query: {
            id: 'callback-3',
            from: { id: 42 },
            data: retrySave,
            message: { chat: { id: 42, type: 'private' } },
          },
        },
        header,
      )
    ).status,
    200,
  );
  assert.equal(
    methods.filter((method) => method === 'answerCallbackQuery').length,
    answersBeforeFailure + 1,
  );
  assert.match(sent.at(-1)!.text, /Не удалось сохранить/);
  instance.store.createTask = createTask;
  assert.equal(
    (
      await call(
        '/webhook',
        'POST',
        {
          update_id: 5,
          callback_query: {
            id: 'callback-4',
            from: { id: 42 },
            data: retrySave,
            message: { chat: { id: 42, type: 'private' } },
          },
        },
        header,
      )
    ).status,
    200,
  );
  assert.match(sent.at(-1)!.text, /Сохранено/);
  assert.equal(
    (await call('/webhook', 'POST', update(42, 'private', '🌙 Итог дня'), header)).status,
    200,
  );
  assert.match(sent.at(-1)!.text, /Итог дня/);
  assert.equal((await call('/pairing', 'POST', {})).status, 409);
  assert.equal((await call('/connection', 'DELETE')).status, 200);
  assert.equal((await call('/status')).body.configured, false);
  assert.ok(methods.includes('answerCallbackQuery'));
  assert.equal(methods.at(-1), 'deleteWebhook');
});

test('owner voice messages create a draft and require a single confirmed save', async (t) => {
  const dataDir = mkdtempSync(join(tmpdir(), 'ritm-telegram-voice-'));
  const botToken = '123456789:' + 'b'.repeat(35);
  const sent: Array<{
    text: string;
    reply_markup?: { inline_keyboard: Array<Array<{ callback_data: string }>> };
  }> = [];
  const createdEvents: Array<{ title: string; requestId: string }> = [];
  let kind: 'task' | 'event' = 'task';
  const transport: typeof fetch = async (input, init) => {
    const url = new URL(String(input));
    if (url.pathname.includes('/file/bot'))
      return new Response(new Uint8Array([1, 2, 3]), { status: 200 });
    const method = url.pathname.split('/').at(-1)!;
    const body = JSON.parse(String(init?.body ?? '{}'));
    if (method === 'sendMessage') sent.push(body);
    const result =
      method === 'getMe'
        ? { id: 17, is_bot: true, username: 'RitmVoiceBot' }
        : method === 'getFile'
          ? { file_path: 'voice/file_12.oga', file_size: 3 }
          : true;
    return new Response(JSON.stringify({ ok: true, result }), { status: 200 });
  };
  const instance = createApp({
    dataDir,
    seed: false,
    telegramTransport: transport,
    telegramVoiceInterpreter: async () => ({
      transcript: kind === 'task' ? 'завтра купить продукты' : 'встреча завтра в 3',
      kind,
      title: kind === 'task' ? 'Купить продукты' : 'Встреча',
      description: '',
      date: '2026-10-24',
      time: kind === 'task' ? null : '15:00',
      duration: 60,
      allDay: false,
    }),
    googleService: {
      status: async () => ({ status: 'connected' }) as never,
      connectionIdentity: async () => 'google-account-1',
      createEvent: async (input: GoogleEventInput, requestId: string) => {
        createdEvents.push({ title: input.title, requestId });
        return { id: requestId } as never;
      },
    } as unknown as NonNullable<NonNullable<Parameters<typeof createApp>[0]>['googleService']>,
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
    assert.ok(
      resolve(dataDir).startsWith(resolve(tmpdir())) && dataDir.includes('ritm-telegram-voice-'),
    );
    rmSync(dataDir, { recursive: true, force: true });
  });
  const call = async (path: string, body?: unknown, headers: Record<string, string> = {}) =>
    fetch(base + path, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', ...headers },
      body: JSON.stringify(body ?? {}),
    });
  assert.equal((await call('/configuration', { botToken })).status, 200);
  const pairing = await (await call('/pairing')).json();
  const code = new URL(pairing.pairingUrl).searchParams.get('start')!;
  const secret = JSON.parse(
    (await instance.secrets.getSecret('telegram-connection'))!,
  ).webhookSecret;
  const headers = { 'x-telegram-bot-api-secret-token': secret };
  const message = (id: number, from = 42) => ({
    update_id: id,
    message: {
      from: { id: from, first_name: 'Owner' },
      chat: { id: from, type: 'private' },
      voice: { file_id: 'voice-id', file_size: 3, duration: 3 },
    },
  });
  assert.equal(
    (
      await call(
        '/webhook',
        {
          update_id: 1,
          message: {
            text: `/start ${code}`,
            from: { id: 42, first_name: 'Owner' },
            chat: { id: 42, type: 'private' },
          },
        },
        headers,
      )
    ).status,
    200,
  );
  sent.length = 0;
  assert.equal((await call('/webhook', message(10, 99), headers)).status, 200);
  assert.equal(sent.length, 0);
  assert.equal((await call('/webhook', message(10), headers)).status, 200);
  assert.equal(sent.length, 1);
  assert.match(sent[0].text, /Купить продукты/);
  assert.equal((await call('/webhook', message(10), headers)).status, 200);
  assert.equal(sent.length, 1);
  const button = sent[0].reply_markup!.inline_keyboard[0][0].callback_data;
  const callback = (id: string, actor = 42, data = button) => ({
    update_id: 11,
    callback_query: {
      id,
      data,
      from: { id: actor },
      message: { chat: { id: 42, type: 'private' } },
    },
  });
  assert.equal((await call('/webhook', callback('foreign', 99), headers)).status, 200);
  assert.equal((await instance.store.tasks()).length, 0);
  assert.equal((await call('/webhook', callback('confirm'), headers)).status, 200);
  const tasks = await instance.store.tasks();
  assert.equal(tasks.length, 1);
  assert.equal(tasks[0].title, 'Купить продукты');
  assert.equal(tasks[0].calendarEntry, false);
  assert.equal(tasks[0].date, '2026-10-24');
  assert.equal((await call('/webhook', callback('duplicate'), headers)).status, 200);
  assert.equal((await instance.store.tasks()).length, 1);

  kind = 'event';
  assert.equal((await call('/webhook', message(12), headers)).status, 200);
  const eventButton = sent.at(-1)!.reply_markup!.inline_keyboard[0][0].callback_data;
  assert.equal(
    (await call('/webhook', callback('event-confirm', 42, eventButton), headers)).status,
    200,
  );
  assert.deepEqual(
    createdEvents.map((event) => event.title),
    ['Встреча'],
  );
  assert.equal(
    (await call('/webhook', callback('event-duplicate', 42, eventButton), headers)).status,
    200,
  );
  assert.equal(createdEvents.length, 1);
});
