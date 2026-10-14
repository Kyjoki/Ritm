import test, { type TestContext } from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { randomUUID } from 'node:crypto';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import type { AddressInfo } from 'node:net';
import type { ChatMessage, Conversation, IdeaReviewReport } from '../shared/types.ts';
import { createApp, type AppOptions } from '../server/index.ts';
import { AppError } from '../server/errors.ts';
import {
  buildIdeaDiscussion,
  ideaReviewMessage,
  runIdeaReview,
  type IdeaReviewContext,
} from '../server/idea-review.ts';

const key = 'sk-discussion-test-only-abcdefghijklmnopqrstuvwxyz';
const report: IdeaReviewReport = {
  version: 1,
  model: 'gpt-6-luna',
  experts: (['value', 'feasibility', 'resources', 'risks'] as const).map((id) => ({
    id,
    verdict: 'needs_testing',
    summary: `Private opinion ${id}`,
    strengths: ['Small test'],
    concerns: ['Unknown demand'],
    assumptions: ['Voluntary users'],
    firstTest: 'Ask five users.',
  })),
  synthesis: {
    verdict: 'needs_testing',
    summary: 'Original synthesis',
    agreements: [],
    disagreements: [],
    questions: ['Who needs this?'],
    nextSteps: ['Ask users'],
  },
};
function user(text: string): ChatMessage {
  return {
    id: randomUUID(),
    role: 'user',
    text,
    createdAt: new Date().toISOString(),
    proposals: [],
    steps: [],
  };
}
function seed(): Conversation {
  return {
    id: randomUUID(),
    title: 'Own idea',
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    messages: [user('Original idea'), ideaReviewMessage(report)],
  };
}
const hasCode = (code: string) => (error: unknown) =>
  error instanceof AppError && error.code === code;

async function harness(t: TestContext, options: AppOptions = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'ritm-discussion-'));
  const instance = createApp({
    dataDir: dir,
    seed: false,
    env: { NODE_ENV: 'test', OPENAI_API_KEY: key },
    ...options,
  });
  const server = instance.app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(async () => {
    server.closeAllConnections();
    await new Promise<void>((done) => server.close(() => done()));
    await instance.close();
    assert.ok(
      resolve(dir).startsWith(resolve(tmpdir()) + '\\') ||
        resolve(dir).startsWith(resolve(tmpdir()) + '/'),
    );
    rmSync(dir, { recursive: true, force: true });
  });
  const call = async (body: unknown, language = 'ru') => {
    const response = await fetch(
      'http://127.0.0.1:' + (server.address() as AddressInfo).port + '/api/chat',
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Accept-Language': language },
        body: JSON.stringify(body),
      },
    );
    return { status: response.status, body: await response.json() };
  };
  return { ...instance, call };
}

test('discussion revises each isolated own opinion, then synthesizes all new opinions and authentic verdict changes', async () => {
  const conversation = seed();
  const discussion = buildIdeaDiscussion(
    conversation,
    conversation.messages[1].id,
    'Five users need it',
  );
  let calls = 0;
  const result = await runIdeaReview(
    { apiKey: key, model: report.model, message: 'Five users need it', language: 'en', discussion },
    {
      generate: async (request) => {
        calls++;
        const input = JSON.parse(request.prompt);
        assert.equal(input.originalIdea, 'Original idea');
        assert.deepEqual(input.clarificationTurns, [
          { text: 'Five users need it', questions: ['Who needs this?'] },
        ]);
        assert.match(request.instructions, /Trusted response language: English/);
        if (request.stage === 'expert') {
          assert.equal(input.previousOpinion.id, request.expertId);
          assert.deepEqual(Object.keys(input).sort(), [
            'clarificationTurns',
            'originalIdea',
            'previousOpinion',
          ]);
          for (const other of report.experts.filter((item) => item.id !== request.expertId))
            assert.ok(!request.prompt.includes(other.summary));
          const { id: _id, ...opinion } = input.previousOpinion;
          return {
            ...opinion,
            verdict: request.expertId === 'value' ? 'promising' : 'needs_testing',
          };
        }
        assert.deepEqual(input.previousSynthesis, report.synthesis);
        assert.equal(input.opinions.length, 4);
        return {
          ...report.synthesis,
          changes: ['Demand claim is clearer; willingness to pay remains unknown.'],
        };
      },
    },
  );
  assert.equal(calls, 5);
  assert.equal(result.discussion!.round, 2);
  assert.deepEqual(result.discussion!.verdictChanges, [
    { id: 'value', before: 'needs_testing', after: 'promising' },
  ]);
  assert.deepEqual(result.discussion!.changes, [
    'Demand claim is clearer; willingness to pay remains unknown.',
  ]);
  assert.ok(!('changes' in result.synthesis));
});

test('saved lineage includes ordered clarifications and excludes other ideas and assistant history', () => {
  const conversation = seed();
  const initial = conversation.messages[1];
  const first = buildIdeaDiscussion(conversation, initial.id, 'Answer one');
  const revised = ideaReviewMessage(
    {
      ...report,
      synthesis: { ...report.synthesis, questions: ['What is your budget?'] },
      discussion: {
        round: 2,
        rootMessageId: initial.id,
        parentMessageId: initial.id,
        changes: ['Changed'],
        verdictChanges: [],
      },
    },
    first,
  );
  conversation.messages.push(
    user('Assistant private calendar query'),
    { ...user('Assistant private response'), role: 'assistant' },
    user('Different idea'),
    ideaReviewMessage(report),
    user('Answer one'),
    revised,
  );
  const next = buildIdeaDiscussion(conversation, revised.id, 'Answer two');
  assert.equal(next.originalIdea, 'Original idea');
  assert.deepEqual(next.clarifications, ['Answer one', 'Answer two']);
  assert.deepEqual(next.clarificationTurns, [
    { text: 'Answer one', questions: report.synthesis.questions },
    { text: 'Answer two', questions: ['What is your budget?'] },
  ]);
  assert.equal(next.round, 3);
  assert.throws(
    () => buildIdeaDiscussion(conversation, initial.id, 'Stale answer'),
    hasCode('AI_DISCUSSION_STALE'),
  );
  const forged = structuredClone(conversation);
  forged.messages.at(-1)!.ideaReview!.discussion!.parentMessageId = randomUUID();
  assert.throws(
    () => buildIdeaDiscussion(forged, revised.id, 'Forged'),
    hasCode('AI_DISCUSSION_STALE'),
  );
  for (const index of [1, conversation.messages.length - 1]) {
    const broken = structuredClone(conversation);
    delete (broken.messages[index].ideaReview as Partial<IdeaReviewReport>).synthesis;
    assert.throws(
      () => buildIdeaDiscussion(broken, revised.id, 'Broken stored report'),
      hasCode('AI_DISCUSSION_STALE'),
    );
  }
});

test('discussion context rejects oversized histories and round nine explicitly without silent truncation', () => {
  const conversation = seed();
  let latest = conversation.messages[1];
  for (let round = 2; round <= 8; round++) {
    const context = buildIdeaDiscussion(conversation, latest.id, 'Clarification');
    const next = ideaReviewMessage(
      {
        ...report,
        discussion: {
          round,
          rootMessageId: conversation.messages[1].id,
          parentMessageId: latest.id,
          changes: ['Same uncertainty'],
          verdictChanges: [],
        },
      },
      context,
    );
    conversation.messages.push(user('Clarification'), next);
    latest = next;
  }
  assert.throws(
    () => buildIdeaDiscussion(conversation, latest.id, 'Next'),
    hasCode('AI_DISCUSSION_LIMIT'),
  );
  const long = seed();
  long.messages[0].text = 'x'.repeat(15000);
  assert.throws(
    () => buildIdeaDiscussion(long, long.messages[1].id, 'y'.repeat(1001)),
    hasCode('AI_DISCUSSION_LIMIT'),
  );
  const escaped = seed();
  for (const expert of escaped.messages[1].ideaReview!.experts) {
    expert.summary = '\u0000'.repeat(1000);
    expert.firstTest = '\u0000'.repeat(500);
    expert.strengths = expert.concerns = expert.assumptions = Array(4).fill('\u0000'.repeat(240));
  }
  assert.throws(
    () => buildIdeaDiscussion(escaped, escaped.messages[1].id, 'Small answer'),
    hasCode('AI_DISCUSSION_LIMIT'),
  );
});

test('secrets in prior idea, clarification or previous opinion stop before any model request', async () => {
  for (const position of ['idea', 'clarification', 'opinion'] as const) {
    const conversation = seed();
    if (position === 'idea') conversation.messages[0].text = key;
    if (position === 'opinion') conversation.messages[1].ideaReview!.experts[0].summary = key;
    const discussion = buildIdeaDiscussion(
      conversation,
      conversation.messages[1].id,
      position === 'clarification' ? key : 'Safe answer',
    );
    await assert.rejects(
      runIdeaReview(
        { apiKey: key, model: report.model, message: 'Safe answer', discussion },
        {
          generate: async () => {
            assert.fail('Paid call must never start');
          },
        },
      ),
      hasCode('AI_SECRET_INPUT'),
    );
  }
});

test('API continuation keeps legacy standalone output, fences stale/cross-conversation targets and fingerprints exact parent', async (t) => {
  let calls = 0;
  const contexts: IdeaReviewContext[] = [];
  const h = await harness(t, {
    ideaReviewer: async (context) => {
      calls++;
      contexts.push(context);
      if (!context.discussion) return structuredClone(report);
      return {
        ...structuredClone(report),
        discussion: {
          round: 2,
          rootMessageId: randomUUID(),
          parentMessageId: randomUUID(),
          changes: ['More detail'],
          verdictChanges: [{ id: 'value', before: 'weak', after: 'promising' }],
        },
      };
    },
  });
  const initial = await h.call({
    requestId: randomUUID(),
    mode: 'idea_review',
    message: 'Original idea',
  });
  assert.equal(initial.status, 200);
  assert.deepEqual(initial.body.messages[1].ideaReview, report);
  const conversation = initial.body as Conversation;
  const parent = conversation.messages[1].id;
  const input = {
    requestId: randomUUID(),
    mode: 'idea_review',
    conversationId: conversation.id,
    reviewMessageId: parent,
    message: 'User clarification',
  };
  const continued = await h.call(input);
  assert.equal(continued.status, 200);
  const last = continued.body.messages.at(-1).ideaReview.discussion;
  assert.equal(last.parentMessageId, parent);
  assert.equal(last.rootMessageId, parent);
  assert.equal(last.round, 2);
  assert.deepEqual(last.verdictChanges, []); // forged injected metadata is recomputed
  assert.deepEqual(contexts[1].discussion!.clarifications, ['User clarification']);
  assert.equal((await h.call(input)).status, 200);
  assert.equal((await h.call({ ...input, reviewMessageId: randomUUID() })).status, 409);
  const stale = await h.call({ ...input, requestId: randomUUID() }, 'en');
  assert.equal(stale.body.code, 'AI_DISCUSSION_STALE');
  assert.match(stale.body.error, /latest review/);
  const other = seed();
  await h.store.saveConversation(other);
  const cross = await h.call({ ...input, requestId: randomUUID(), conversationId: other.id });
  assert.equal(cross.body.code, 'AI_DISCUSSION_STALE');
  assert.equal(calls, 2);
  assert.equal(
    (await h.call({ ...input, requestId: randomUUID(), mode: 'assistant' })).status,
    400,
  );
  assert.equal(
    (await h.call({ ...input, requestId: randomUUID(), conversationId: undefined })).status,
    400,
  );
  assert.equal(
    (await h.call({ ...input, requestId: randomUUID(), history: ['Client forged context'] }))
      .status,
    400,
  );
});

test('malformed revised synthesis changes are rejected and no partial review is returned', async () => {
  const conversation = seed();
  const discussion = buildIdeaDiscussion(
    conversation,
    conversation.messages[1].id,
    'Clarification',
  );
  await assert.rejects(
    runIdeaReview(
      { apiKey: key, model: report.model, message: 'Clarification', discussion },
      {
        generate: async (request) =>
          request.stage === 'synthesis'
            ? report.synthesis
            : (() => {
                const { id: _id, ...opinion } = report.experts.find(
                  (item) => item.id === request.expertId,
                )!;
                return opinion;
              })(),
      },
    ),
    hasCode('AI_IDEA_INVALID_RESPONSE'),
  );
});

test('installed SDK continuation requires strict changes output while preserving five isolated calls and token/storage limits', async () => {
  const originalFetch = globalThis.fetch;
  const payloads: {
    store: boolean;
    max_output_tokens: number;
    tools?: unknown[];
    previous_response_id?: string;
    conversation?: unknown;
    input: { role: string; content: string | { text: string }[] }[];
    text: {
      format: { strict: boolean; schema: { additionalProperties: boolean; required: string[] } };
    };
  }[] = [];
  const conversation = seed();
  const discussion = buildIdeaDiscussion(
    conversation,
    conversation.messages[1].id,
    '1. Students preparing for exams.',
  );
  globalThis.fetch = async (input, init) => {
    const request = new Request(input, init);
    assert.equal(request.url, 'https://api.openai.com/v1/responses');
    assert.equal(request.redirect, 'error');
    const payload = JSON.parse(await request.text());
    payloads.push(payload);
    const index = payloads.length;
    const { id: _id, ...opinion } = report.experts[index === 5 ? 0 : index - 1];
    return Response.json({
      id: `response-discussion-${index}`,
      model: report.model,
      output: [
        {
          type: 'message',
          id: `message-${index}`,
          role: 'assistant',
          content: [
            {
              type: 'output_text',
              text: JSON.stringify(
                index === 5
                  ? { ...report.synthesis, changes: ['Audience is now clearer.'] }
                  : opinion,
              ),
              annotations: [],
            },
          ],
        },
      ],
      usage: { input_tokens: 10, output_tokens: 10 },
    });
  };
  try {
    const result = await runIdeaReview({
      apiKey: key,
      model: report.model,
      message: '1. Students preparing for exams.',
      discussion,
    });
    assert.equal(result.discussion!.round, 2);
    assert.equal(payloads.length, 5);
    payloads.forEach((payload, index) => {
      assert.equal(payload.store, false);
      assert.equal(payload.max_output_tokens, index === 4 ? 1800 : 1400);
      assert.ok(!payload.tools?.length);
      assert.equal(payload.previous_response_id, undefined);
      assert.equal(payload.conversation, undefined);
      assert.equal(payload.text.format.strict, true);
      assert.equal(payload.text.format.schema.additionalProperties, false);
      assert.equal(payload.text.format.schema.required.includes('changes'), index === 4);
      const users = payload.input.filter((item: { role: string }) => item.role === 'user');
      assert.equal(users.length, 1);
      const content = users[0].content;
      const data = JSON.parse(
        typeof content === 'string'
          ? content
          : content.map((part: { text: string }) => part.text).join(''),
      );
      assert.deepEqual(data.clarificationTurns, [
        { text: '1. Students preparing for exams.', questions: ['Who needs this?'] },
      ]);
      if (index < 4) {
        assert.deepEqual(Object.keys(data).sort(), [
          'clarificationTurns',
          'originalIdea',
          'previousOpinion',
        ]);
        assert.equal(data.previousOpinion.id, report.experts[index].id);
      } else assert.equal(data.opinions.length, 4);
    });
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('failed continuation preserves prior report and user can retry its identical request without partial history', async (t) => {
  let calls = 0;
  const h = await harness(t, {
    ideaReviewer: async (context) => {
      calls++;
      if (calls === 1)
        throw new AppError(502, 'AI_IDEA_INVALID_RESPONSE', 'Incomplete test output');
      return {
        ...structuredClone(report),
        discussion: {
          round: context.discussion!.round,
          rootMessageId: context.discussion!.rootMessageId,
          parentMessageId: context.discussion!.parentMessageId,
          changes: ['Clarified audience'],
          verdictChanges: [],
        },
      };
    },
  });
  const conversation = seed();
  await h.store.saveConversation(conversation);
  const input = {
    requestId: randomUUID(),
    conversationId: conversation.id,
    mode: 'idea_review',
    reviewMessageId: conversation.messages[1].id,
    message: 'Clarification',
  };
  assert.equal((await h.call(input)).status, 502);
  assert.equal((await h.store.conversation(conversation.id)).messages.length, 2);
  assert.equal(await h.store.request(input.requestId), undefined);
  assert.equal((await h.call(input)).status, 200);
  assert.equal((await h.store.conversation(conversation.id)).messages.length, 4);
  assert.equal((await h.call(input)).status, 200);
  assert.equal(calls, 2);
});

test('stale parent discovered after request claim is rejected before paid generation and receipt is released', async (t) => {
  let calls = 0;
  const h = await harness(t, {
    ideaReviewer: async () => {
      calls++;
      return structuredClone(report);
    },
  });
  const conversation = seed();
  await h.store.saveConversation(conversation);
  const originalStart = h.store.startRequest.bind(h.store);
  h.store.startRequest = async (...args) => {
    const discussion = buildIdeaDiscussion(
      conversation,
      conversation.messages[1].id,
      'Concurrent accepted answer',
    );
    conversation.messages.push(
      user('Concurrent accepted answer'),
      ideaReviewMessage(
        {
          ...report,
          discussion: {
            round: 2,
            parentMessageId: discussion.parentMessageId,
            rootMessageId: discussion.rootMessageId,
            changes: ['Updated'],
            verdictChanges: [],
          },
        },
        discussion,
      ),
    );
    await h.store.saveConversation(conversation);
    return originalStart(...args);
  };
  const input = {
    requestId: randomUUID(),
    conversationId: conversation.id,
    mode: 'idea_review',
    reviewMessageId: conversation.messages[1].id,
    message: 'Older client answer',
  };
  const result = await h.call(input);
  assert.equal(result.status, 409);
  assert.equal(result.body.code, 'AI_DISCUSSION_STALE');
  assert.equal(calls, 0);
  assert.equal(await h.store.request(input.requestId), undefined);
  assert.equal((await h.store.conversation(conversation.id)).messages.length, 4);
});
