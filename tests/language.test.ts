import test, { type TestContext } from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { randomUUID } from 'node:crypto';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import type { AddressInfo } from 'node:net';
import { settingsPatchSchema } from '../server/validation.ts';
import { prepareAssistantInput } from '../server/assistant.ts';
import { runIdeaReview, type IdeaGenerationRequest } from '../server/idea-review.ts';
import { localizeError, localizeGoogleResult, requestLanguage } from '../server/localization.ts';
import { createApp, type AppOptions } from '../server/index.ts';
import { Store, defaultSettings } from '../server/store.ts';
import type { GoogleCalendarResult, IdeaReviewReport } from '../shared/types.ts';

const apiKey = 'sk-language-test-only-abcdefghijklmnopqrstuvwxyz';
function removeDirectory(dir: string) {
  assert.ok(
    resolve(dir).startsWith(resolve(tmpdir()) + '/') ||
      resolve(dir).startsWith(resolve(tmpdir()) + '\\'),
  );
  assert.ok(dir.includes('ritm-language-'));
  rmSync(dir, { recursive: true, force: true });
}
function temporaryDirectory(t: TestContext, cleanup = true) {
  const dir = mkdtempSync(join(tmpdir(), 'ritm-language-'));
  if (cleanup) t.after(() => removeDirectory(dir));
  return dir;
}
const opinion = {
  verdict: 'needs_testing' as const,
  summary: 'Check the demand first.',
  strengths: ['Small initial test'],
  concerns: ['Demand is unknown'],
  assumptions: ['There may be potential users'],
  firstTest: 'Interview five potential users.',
};
const synthesis = {
  verdict: 'needs_testing' as const,
  summary: 'Start with a small demand test.',
  agreements: ['Demand is not confirmed'],
  disagreements: ['The implementation effort is uncertain'],
  questions: ['Who needs this?'],
  nextSteps: ['Interview five users'],
};
test('settings accept only Russian or English; persisted language preserves all other JSON settings', (t) => {
  for (const language of ['ru', 'en'])
    assert.equal(settingsPatchSchema.parse({ language }).language, language);
  for (const language of ['fr', 'EN', '', null, 1])
    assert.equal(settingsPatchSchema.safeParse({ language }).success, false);
  assert.equal(
    settingsPatchSchema.safeParse({ timeZone: 'Unreal/Zone', language: 'en' }).success,
    false,
  );
  const dir = temporaryDirectory(t);
  let store = new Store(dir, false);
  const original = store.settings();
  assert.equal(original.language, 'ru');
  assert.deepEqual(store.updateSettings({ language: 'en' }), { ...original, language: 'en' });
  store.close();
  store = new Store(dir, false);
  try {
    assert.deepEqual(store.settings(), { ...original, language: 'en' });
    assert.deepEqual(store.updateSettings({ language: 'ru' }), original);
  } finally {
    store.close();
  }
});

test('normal assistant uses the saved trusted language independently of Russian personal content/history', () => {
  const title = 'Подготовить отчёт';
  const input = prepareAssistantInput({
    apiKey,
    model: 'gpt-6-luna',
    message: 'Ответь только по-русски',
    settings: { ...defaultSettings, language: 'en' },
    tasks: [
      {
        id: randomUUID(),
        title,
        description: 'Описание на русском',
        date: null,
        time: null,
        duration: 30,
        priority: 'normal',
        repeat: 'none',
        kind: 'task',
        completed: false,
        completedDates: [],
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
      },
    ],
  });
  assert.ok(input.instructions.includes('Trusted response language: English'));
  assert.ok(!input.instructions.includes('Отвечай по-русски,'));
  const data = JSON.parse(input.messages[0].content.slice(input.messages[0].content.indexOf('{')));
  assert.equal(data.language, 'en');
  assert.equal(data.tasks[0].title, title);
  assert.equal(input.messages.at(-1)?.content, 'Ответь только по-русски');
  assert.ok(!JSON.stringify(input).includes(apiKey));
  const ru = prepareAssistantInput({
    apiKey,
    model: 'gpt-6-luna',
    message: 'Hello',
    settings: defaultSettings,
    tasks: [],
  });
  assert.ok(ru.instructions.includes('Отвечай по-русски,'));
});

test('all four isolated experts and synthesis receive English instructions without calendar or history', async () => {
  const calls: IdeaGenerationRequest[] = [];
  const idea = 'Хочу сделать приложение для соседей';
  const report = await runIdeaReview(
    { apiKey, model: 'gpt-6-luna', message: idea, language: 'en' },
    {
      generate: async (request) => {
        calls.push(request);
        assert.ok(request.instructions.includes('Trusted response language: English'));
        assert.ok(!request.instructions.includes('на русском языке'));
        const data = JSON.parse(request.prompt);
        assert.equal(data.idea, idea);
        assert.equal(data.calendar, undefined);
        assert.equal(data.history, undefined);
        if (request.stage === 'expert') assert.deepEqual(Object.keys(data), ['idea']);
        return request.stage === 'expert' ? opinion : synthesis;
      },
    },
  );
  assert.equal(calls.length, 5);
  assert.deepEqual(
    report.experts.map((expert) => expert.id),
    ['value', 'feasibility', 'resources', 'risks'],
  );
  assert.equal(report.synthesis.summary, synthesis.summary);
  await runIdeaReview(
    { apiKey, model: 'gpt-6-luna', message: idea },
    {
      generate: async (request) => {
        assert.ok(request.instructions.includes('на русском языке'));
        return request.stage === 'expert' ? opinion : synthesis;
      },
    },
  );
});

test('language negotiation, rate countdown, conflicts and Google reasons preserve user text', () => {
  assert.equal(requestLanguage(), 'ru');
  assert.equal(requestLanguage('en-US,en;q=0.8,ru;q=0.5'), 'en');
  assert.equal(requestLanguage('en;q=0,ru;q=1'), 'ru');
  assert.equal(requestLanguage('en;q=wat,ru'), 'ru');
  assert.equal(requestLanguage('ru;q=0.2,en;q=0.9'), 'en');
  const message = 'Ritm временно ограничил частоту разбора идей. Повторите через 42 с.';
  assert.equal(
    localizeError(message, 'IDEA_REVIEW_RATE_LIMIT', 'en'),
    'Ritm temporarily limited idea reviews. Try again in 42 seconds.',
  );
  assert.equal(localizeError(message, 'IDEA_REVIEW_RATE_LIMIT', 'ru'), message);
  assert.equal(
    localizeError(
      '«Мой отчёт» пересекается с другой записью. Выберите другое время или попросите новый план.',
      'CONFLICT',
      'en',
    ),
    '“Мой отчёт” overlaps another entry. Choose another time or ask for a new plan.',
  );
  const result: GoogleCalendarResult = {
    from: '2026-10-11',
    to: '2026-10-18',
    timeZone: 'Asia/Qyzylorda',
    fetchedAt: new Date().toISOString(),
    partial: false,
    tasks: {
      status: 'unavailable',
      message:
        'Не удалось загрузить статусы Google Tasks. Календарь доступен; повторите обновление.',
    },
    events: [
      {
        id: 'abc',
        source: 'google',
        calendarId: 'primary',
        title: 'Моя встреча',
        description: 'Личное описание',
        etag: '"v1"',
        start: { date: '2026-10-14' },
        end: { date: '2026-10-15' },
        timeZone: 'Asia/Qyzylorda',
        allDay: true,
        busy: true,
        readOnly: true,
        readOnlyReason: 'Это специальное событие Google. Измените его в Google Calendar.',
      },
    ],
  };
  const localized = localizeGoogleResult(result, 'en');
  assert.equal(localized.events[0].title, result.events[0].title);
  assert.equal(localized.events[0].description, result.events[0].description);
  assert.equal(
    localized.events[0].readOnlyReason,
    'This is a special Google event. Edit it in Google Calendar.',
  );
  assert.ok(localized.tasks?.message?.startsWith('Google Tasks statuses'));
  assert.equal(localizeGoogleResult(result, 'ru'), result);
  assert.equal(
    result.events[0].readOnlyReason,
    'Это специальное событие Google. Измените его в Google Calendar.',
  );
});

async function harness(t: TestContext, options: AppOptions = {}) {
  const dir = temporaryDirectory(t, false);
  const instance = createApp({
    dataDir: dir,
    seed: false,
    env: { NODE_ENV: 'test', OPENAI_API_KEY: apiKey },
    ...options,
  });
  const server = instance.app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const url = 'http://127.0.0.1:' + (server.address() as AddressInfo).port;
  t.after(async () => {
    server.closeAllConnections();
    await new Promise<void>((done) => server.close(() => done()));
    await instance.close();
    removeDirectory(dir);
  });
  const call = async (
    path: string,
    body?: unknown,
    language?: string,
    method = body === undefined ? 'GET' : 'POST',
  ) => {
    const response = await fetch(url + '/api' + path, {
      method,
      headers: {
        ...(language ? { 'Accept-Language': language } : {}),
        ...(method === 'GET' ? {} : { 'Content-Type': 'application/json' }),
      },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
    return { status: response.status, body: await response.json() };
  };
  return { ...instance, call };
}

test('HTTP errors use requested language before/after settings save without changing Russian default', async (t) => {
  const h = await harness(t);
  const ru = await h.call('/settings', { language: 'fr' }, undefined, 'PATCH');
  assert.equal(ru.status, 400);
  assert.ok(ru.body.error.startsWith('Проверьте'));
  const en = await h.call('/settings', { language: 'fr' }, 'en', 'PATCH');
  assert.equal(en.status, 400);
  assert.equal(en.body.code, 'VALIDATION_ERROR');
  assert.ok(en.body.error.startsWith('Check the name'));
  assert.equal((await h.call('/settings', { language: 'en' }, 'en', 'PATCH')).body.language, 'en');
  assert.equal((await h.call('/bootstrap', undefined, 'en')).body.settings.language, 'en');
  const missing = await h.call('/tasks/' + randomUUID(), {}, 'en', 'PATCH');
  assert.equal(missing.status, 400);
  assert.equal(missing.body.error, 'Check the title, date, time and duration fields.');
  const notFound = await h.call('/tasks/' + randomUUID(), undefined, 'en', 'DELETE');
  assert.equal(notFound.status, 404);
  assert.equal(notFound.body.error, 'Task not found. Refresh the page.');
  const invalidHours = await h.call(
    '/settings',
    { workDayStart: '23:00', workDayEnd: '08:00' },
    'en',
    'PATCH',
  );
  assert.equal(invalidHours.body.error, 'The work day must start before it ends.');
});

test('chat routes pass persisted English to both runners while idea mode receives no personal workspace', async (t) => {
  let assistantCalls = 0,
    ideaCalls = 0;
  const report: IdeaReviewReport = {
    version: 1,
    model: 'gpt-6-luna',
    experts: ['value', 'feasibility', 'resources', 'risks'].map((id) => ({
      id: id as IdeaReviewReport['experts'][number]['id'],
      ...opinion,
    })),
    synthesis,
  };
  const h = await harness(t, {
    assistant: async (context) => {
      assistantCalls++;
      assert.equal(context.settings.language, 'en');
      return { text: 'Your plan', steps: [], proposals: [] };
    },
    ideaReviewer: async (context) => {
      ideaCalls++;
      assert.equal(context.language, 'en');
      assert.deepEqual(Object.keys(context).sort(), [
        'apiKey',
        'language',
        'message',
        'model',
        'signal',
      ]);
      return report;
    },
  });
  await h.call('/settings', { language: 'en' }, 'en', 'PATCH');
  assert.equal(
    (await h.call('/chat', { requestId: randomUUID(), message: 'Помоги', mode: 'assistant' }, 'en'))
      .status,
    200,
  );
  assert.equal(
    (
      await h.call(
        '/chat',
        { requestId: randomUUID(), message: 'Моя идея', mode: 'idea_review' },
        'en',
      )
    ).status,
    200,
  );
  assert.equal(assistantCalls, 1);
  assert.equal(ideaCalls, 1);
});
