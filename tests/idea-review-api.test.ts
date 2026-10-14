import test, { type TestContext } from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { randomUUID } from 'node:crypto';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import type { AddressInfo } from 'node:net';
import type { Conversation, IdeaReviewReport } from '../shared/types.ts';
import { createApp, type AppOptions } from '../server/index.ts';
import { Store } from '../server/store.ts';

const fakeKey = 'sk-idea-review-tests-only-abcdefghijklmnopqrstuvwxyz';
const report: IdeaReviewReport = {
  version: 1,
  model: 'gpt-6-luna',
  experts: ['value', 'feasibility', 'resources', 'risks'].map((id) => ({
    id: id as IdeaReviewReport['experts'][number]['id'],
    verdict: 'needs_testing',
    summary: 'Сначала проверить потребность.',
    strengths: ['Малый первый шаг'],
    concerns: ['Нет данных о спросе'],
    assumptions: ['Есть потенциальные пользователи'],
    firstTest: 'Поговорить с пятью пользователями.',
  })),
  synthesis: {
    verdict: 'needs_testing',
    summary: 'Начните с небольшой проверки.',
    agreements: ['Потребность пока не подтверждена'],
    disagreements: ['Неизвестен объём реализации'],
    questions: ['Кому это нужно?'],
    nextSteps: ['Провести пять интервью'],
  },
};
async function harness(t: TestContext, options: AppOptions = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'ritm-idea-api-'));
  const instance = createApp({
    dataDir: dir,
    seed: false,
    env: { NODE_ENV: 'test', OPENAI_API_KEY: fakeKey },
    ...options,
  });
  const server = instance.app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const url = 'http://127.0.0.1:' + (server.address() as AddressInfo).port;
  t.after(async () => {
    server.closeAllConnections();
    await new Promise<void>((done) => server.close(() => done()));
    await instance.close();
    assert.ok(
      resolve(dir).startsWith(resolve(tmpdir()) + '/') ||
        resolve(dir).startsWith(resolve(tmpdir()) + '\\'),
    );
    assert.ok(dir.includes('ritm-idea-api-'));
    rmSync(dir, { recursive: true, force: true });
  });
  const call = async (body: unknown) => {
    const response = await fetch(url + '/api/chat', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    return { status: response.status, body: await response.json(), headers: response.headers };
  };
  return { ...instance, dir, call };
}
test('idea mode skips Calendar, stores four opinions, replays without new generation and fences mode changes', async (t) => {
  let reviews = 0,
    assistantCalls = 0,
    googleCalls = 0;
  const google = new Proxy(
    {},
    {
      get: () => async () => {
        googleCalls++;
        throw new Error('No calendar access for idea review');
      },
    },
  ) as AppOptions['googleService'];
  const h = await harness(t, {
    googleService: google,
    ideaReviewer: async (context) => {
      reviews++;
      assert.equal(context.message, 'Моя идея');
      assert.deepEqual(Object.keys(context).sort(), [
        'apiKey',
        'language',
        'message',
        'model',
        'signal',
      ]);
      return structuredClone(report);
    },
    assistant: async () => {
      assistantCalls++;
      return { text: 'План', steps: [], proposals: [] };
    },
  });
  const input = { requestId: randomUUID(), message: 'Моя идея', mode: 'idea_review' };
  const first = await h.call(input);
  assert.equal(first.status, 200);
  const conversation = first.body as Conversation;
  assert.deepEqual(conversation.messages[1].ideaReview, report);
  assert.deepEqual(conversation.messages[1].proposals, []);
  assert.deepEqual(conversation.messages[1].steps, []);
  assert.equal((await h.call(input)).body.id, conversation.id);
  assert.equal((await h.call({ ...input, mode: 'assistant' })).status, 409);
  assert.equal((await h.call({ ...input, mode: undefined })).status, 409);
  assert.equal(reviews, 1);
  assert.equal(assistantCalls, 0);
  assert.equal(googleCalls, 0);
  const reader = new Store(h.dir, false);
  try {
    assert.deepEqual(reader.conversation(conversation.id).messages[1].ideaReview, report);
  } finally {
    reader.close();
  }
  assert.deepEqual(await h.store.tasks(), []);
});
test('malformed review is rejected without invented opinions or stored partial response; retry remains possible', async (t) => {
  let calls = 0;
  const h = await harness(t, {
    ideaReviewer: async () => {
      calls++;
      return calls === 1
        ? { ...report, experts: report.experts.slice(0, 3) }
        : structuredClone(report);
    },
  });
  const input = { requestId: randomUUID(), message: 'Проверить идею', mode: 'idea_review' };
  const bad = await h.call(input);
  assert.equal(bad.status, 502);
  assert.equal(bad.body.code, 'AI_IDEA_INVALID_RESPONSE');
  assert.equal((await h.store.conversations()).length, 0);
  assert.equal((await h.call(input)).status, 200);
  assert.equal(calls, 2);
});
test('review holds both shared generation slots and releases them after completion', async (t) => {
  let started!: () => void, release!: () => void;
  const ready = new Promise<void>((resolve) => {
    started = resolve;
  });
  const gate = new Promise<void>((resolve) => {
    release = resolve;
  });
  t.after(() => release());
  const h = await harness(t, {
    ideaReviewer: async () => {
      started();
      await gate;
      return structuredClone(report);
    },
    assistant: async () => ({ text: 'План', steps: [], proposals: [] }),
  });
  const pending = h.call({ requestId: randomUUID(), message: 'Оценить идею', mode: 'idea_review' });
  await ready;
  const chat = { requestId: randomUUID(), message: 'Привет' };
  const blocked = await h.call(chat);
  assert.equal(blocked.status, 429);
  assert.equal(blocked.body.code, 'AI_BUSY');
  release();
  assert.equal((await pending).status, 200);
  assert.equal((await h.call(chat)).status, 200);
});
test('unknown modes are rejected before model generation and old assistant fingerprints remain compatible', async (t) => {
  let calls = 0;
  const h = await harness(t, {
    assistant: async () => {
      calls++;
      return { text: 'Привет', steps: [], proposals: [] };
    },
  });
  const input = { requestId: randomUUID(), message: 'Привет' };
  assert.equal((await h.call({ ...input, mode: 'administrator' })).status, 400);
  const first = await h.call(input);
  assert.equal(first.status, 200);
  assert.equal((await h.call({ ...input, mode: 'assistant' })).body.id, first.body.id);
  assert.equal(calls, 1);
});

test('six sequential reviews are allowed; the next is bounded with accurate retry delay and no paid generation', async (t) => {
  let calls = 0;
  const h = await harness(t, {
    ideaReviewer: async () => {
      calls++;
      return structuredClone(report);
    },
  });
  let firstInput: { requestId: string; message: string; mode: string } | undefined;
  for (let i = 0; i < 6; i++) {
    const input = { requestId: randomUUID(), message: `Идея ${i}`, mode: 'idea_review' };
    firstInput ??= input;
    assert.equal((await h.call(input)).status, 200);
  }
  const blockedInput = { requestId: randomUUID(), message: 'Следующая идея', mode: 'idea_review' };
  const blocked = await h.call(blockedInput);
  assert.equal(blocked.status, 429);
  assert.equal(blocked.body.code, 'IDEA_REVIEW_RATE_LIMIT');
  assert.ok(Number.isInteger(blocked.body.retryAfterSeconds));
  assert.ok(blocked.body.retryAfterSeconds > 0 && blocked.body.retryAfterSeconds <= 60);
  assert.equal(blocked.headers.get('Retry-After'), String(blocked.body.retryAfterSeconds));
  assert.equal(calls, 6);
  assert.equal(await h.store.request(blockedInput.requestId), undefined);
  // A saved response stays available even while new reviews are limited.
  assert.equal((await h.call(firstInput)).status, 200);
  assert.equal(calls, 6);
});
