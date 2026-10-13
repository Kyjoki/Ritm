import test from 'node:test';
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';
import { APICallError } from 'ai';
import {
  ideaReviewMessage,
  MAX_IDEA_REVIEW_PROMPT_CHARS,
  runIdeaReview,
  type IdeaGenerationRequest,
  type IdeaReviewContext,
  type IdeaReviewGenerator,
} from '../server/idea-review.ts';
import { AppError } from '../server/errors.ts';
import type { IdeaExpertId, IdeaExpertOpinion, IdeaReviewReport } from '../shared/types.ts';

const context: IdeaReviewContext = {
  apiKey: 'sk-test-only-abcdefghijklmnopqrstuvwxyz',
  model: 'gpt-6-luna',
  message: 'Хочу сделать приложение для обмена инструментами между соседями.',
};
const opinion = (id: IdeaExpertId): IdeaExpertOpinion => ({
  verdict: id === 'risks' ? 'weak' : 'needs_testing',
  summary: `Отдельная оценка: ${id}`,
  strengths: ['Польза требует проверки.'],
  concerns: ['Неизвестно, кто будет отвечать за возврат.'],
  assumptions: ['Предполагаем, что соседи готовы делиться.'],
  firstTest: 'Спросить десять соседей о последнем случае нехватки инструмента.',
});
const synthesis = {
  verdict: 'needs_testing' as const,
  summary: 'Сначала проверить потребность и ответственность за возврат.',
  agreements: ['Данных о потребности недостаточно.'],
  disagreements: ['risks считает препятствие серьёзным; value предлагает проверить спрос.'],
  questions: ['Как будет устроен возврат?'],
  nextSteps: ['Опросить соседей без запуска приложения.'],
};
const validGenerator: IdeaReviewGenerator = async (request) =>
  request.stage === 'synthesis' ? synthesis : opinion(request.expertId!);
const hasCode = (code: string) => (error: unknown) => {
  assert.ok(error instanceof AppError);
  assert.equal(error.code, code);
  assert.ok(!error.message.includes(context.apiKey));
  return true;
};

test('four isolated reviewers see original idea only; synthesis sees every distinct confirmed role', async () => {
  const requests: IdeaGenerationRequest[] = [];
  let active = 0;
  let maxActive = 0;
  const report = await runIdeaReview(context, {
    generate: async (request) => {
      requests.push(request);
      active++;
      maxActive = Math.max(maxActive, active);
      await delay(2);
      active--;
      if (request.stage === 'expert') {
        assert.deepEqual(JSON.parse(request.prompt), { idea: context.message });
        assert.equal(request.prompt.includes('calendar'), false);
        assert.equal(request.prompt.includes(context.apiKey), false);
        return opinion(request.expertId!);
      }
      const input = JSON.parse(request.prompt);
      assert.equal(input.idea, context.message);
      assert.deepEqual(
        input.opinions.map((value: { id: string }) => value.id),
        ['value', 'feasibility', 'resources', 'risks'],
      );
      assert.equal(input.opinions[3].verdict, 'weak');
      return synthesis;
    },
  });
  assert.equal(maxActive, 2);
  assert.equal(requests.length, 5);
  assert.equal(report.model, context.model);
  assert.equal(report.experts.length, 4);
  assert.equal(report.synthesis.verdict, 'needs_testing');
  assert.equal(new Set(requests.slice(0, 4).map((request) => request.instructions)).size, 4);
  assert.ok(requests.every((request) => request.instructions.includes('Не выдумывай')));
});

test('failed reviewer cancels sibling, waits for actual settlement, and starts no later batch or synthesis', async () => {
  const ids: string[] = [];
  let siblingSettled = false;
  await assert.rejects(
    runIdeaReview(context, {
      generate: async (request) => {
        ids.push(request.expertId ?? 'synthesis');
        if (request.expertId === 'value') {
          await delay(2);
          throw new Error(`private provider data ${context.apiKey}`);
        }
        try {
          await delay(1000, undefined, { signal: request.signal });
        } finally {
          await delay(5);
          siblingSettled = true;
        }
        return opinion('feasibility');
      },
    }),
    hasCode('AI_IDEA_UNAVAILABLE'),
  );
  assert.equal(siblingSettled, true);
  assert.deepEqual(ids, ['value', 'feasibility']);
});

test('incomplete, oversized, unknown-field and blank expert responses never form fake consensus', async () => {
  for (const bad of [
    { summary: 'Нет остальных полей' },
    { ...opinion('value'), summary: 'a'.repeat(1001) },
    { ...opinion('value'), summary: '   ' },
    { ...opinion('value'), action: { taskId: 'private-task' } },
    { ...opinion('value'), concerns: Array(5).fill('Слишком много пунктов') },
  ]) {
    let calls = 0;
    await assert.rejects(
      runIdeaReview(context, {
        generate: async (request) => {
          calls++;
          return request.expertId === 'value' ? bad : validGenerator(request);
        },
      }),
      hasCode('AI_IDEA_INVALID_RESPONSE'),
    );
    assert.equal(calls, 2);
  }
});

test('malformed synthesis fails instead of publishing a partial report', async () => {
  let calls = 0;
  await assert.rejects(
    runIdeaReview(context, {
      generate: async (request) => {
        calls++;
        return request.stage === 'synthesis'
          ? { ...synthesis, nextSteps: [] }
          : opinion(request.expertId!);
      },
    }),
    hasCode('AI_IDEA_INVALID_RESPONSE'),
  );
  assert.equal(calls, 5);
});

test('single overall deadline cancels all active calls and waits for their settlement', async () => {
  let settled = 0;
  let calls = 0;
  await assert.rejects(
    runIdeaReview(context, {
      timeoutMs: 10,
      generate: async (request) => {
        calls++;
        try {
          await delay(1000, undefined, { signal: request.signal });
        } finally {
          settled++;
        }
        return opinion('value');
      },
    }),
    hasCode('AI_IDEA_TIMEOUT'),
  );
  assert.equal(calls, 2);
  assert.equal(settled, 2);
});

test('per-call deadline aborts stalled reviewer and sibling before launching more work', async () => {
  let settled = 0;
  await assert.rejects(
    runIdeaReview(context, {
      callTimeoutMs: 10,
      generate: async (request) => {
        try {
          await delay(1000, undefined, { signal: request.signal });
        } finally {
          settled++;
        }
        return opinion('value');
      },
    }),
    hasCode('AI_IDEA_TIMEOUT'),
  );
  assert.equal(settled, 2);
});

test('caller cancellation including already-aborted input stops provider work', async () => {
  const controller = new AbortController();
  controller.abort();
  let calls = 0;
  await assert.rejects(
    runIdeaReview(
      { ...context, signal: controller.signal },
      {
        generate: async (request) => {
          calls++;
          return validGenerator(request);
        },
      },
    ),
    hasCode('AI_IDEA_TIMEOUT'),
  );
  assert.equal(calls, 0);
});

test('keys cannot enter prompts, reviewer output, synthesis or saved reports', async () => {
  for (const message of [context.apiKey, 'sk-another-credential-abcdefghijklmnopqrstuvwxyz']) {
    let calls = 0;
    await assert.rejects(
      runIdeaReview(
        { ...context, message },
        {
          generate: async (request) => {
            calls++;
            return validGenerator(request);
          },
        },
      ),
      hasCode('AI_SECRET_INPUT'),
    );
    assert.equal(calls, 0);
  }
  for (const stage of ['expert', 'synthesis']) {
    await assert.rejects(
      runIdeaReview(context, {
        generate: async (request) =>
          request.stage === stage
            ? { ...(stage === 'expert' ? opinion('value') : synthesis), summary: context.apiKey }
            : validGenerator(request),
      }),
      hasCode('AI_IDEA_INVALID_RESPONSE'),
    );
  }
  const report = await runIdeaReview(context, { generate: validGenerator });
  assert.throws(
    () =>
      ideaReviewMessage({ ...report, synthesis: { ...report.synthesis, summary: context.apiKey } }),
    hasCode('AI_IDEA_INVALID_RESPONSE'),
  );
});

test('input and full serialized prompts are bounded without silently shortening idea', async () => {
  await assert.rejects(
    runIdeaReview({ ...context, message: 'x'.repeat(6001) }, { generate: validGenerator }),
    hasCode('AI_IDEA_INPUT'),
  );
  await assert.rejects(
    runIdeaReview({ ...context, message: '   ' }, { generate: validGenerator }),
    hasCode('AI_IDEA_INPUT'),
  );
  const idea = '\u0001'.repeat(6000);
  await runIdeaReview(
    { ...context, message: idea },
    {
      generate: async (request) => {
        assert.ok(request.prompt.length <= MAX_IDEA_REVIEW_PROMPT_CHARS);
        assert.equal(JSON.parse(request.prompt).idea, idea);
        return validGenerator(request);
      },
    },
  );
});

test('API errors are sanitized and never retried', async () => {
  for (const [statusCode, code] of [
    [401, 'AI_AUTH'],
    [429, 'AI_LIMIT'],
    [400, 'AI_MODEL'],
    [500, 'AI_IDEA_UNAVAILABLE'],
  ] as const) {
    let calls = 0;
    await assert.rejects(
      runIdeaReview(context, {
        generate: async () => {
          calls++;
          throw new APICallError({
            message: `private: ${context.apiKey}`,
            url: 'https://api.openai.com/v1/responses',
            requestBodyValues: { apiKey: context.apiKey },
            statusCode,
            responseBody: context.apiKey,
            isRetryable: true,
          });
        },
      }),
      hasCode(code),
    );
    assert.equal(calls, 2);
  }
});

test('saved report validates every role and cannot introduce executable actions', async () => {
  const report = await runIdeaReview(context, { generate: validGenerator });
  const message = ideaReviewMessage(report);
  assert.equal(message.text, synthesis.summary);
  assert.deepEqual(message.proposals, []);
  assert.deepEqual(message.steps, []);
  assert.equal(message.ideaReview?.experts.length, 4);
  for (const invalid of [
    { ...report, experts: report.experts.slice(1) },
    { ...report, experts: [report.experts[0], report.experts[0], ...report.experts.slice(2)] },
    { ...report, experts: report.experts.map((expert) => ({ ...expert, extra: true })) },
    { ...report, synthesis: { ...synthesis, proposals: [{ action: 'write' }] } },
  ]) {
    assert.throws(
      () => ideaReviewMessage(invalid as IdeaReviewReport),
      hasCode('AI_IDEA_INVALID_RESPONSE'),
    );
  }
});

test('installed SDK sends five isolated strict Responses requests with no storage or tools', async () => {
  const originalFetch = globalThis.fetch;
  const payloads: {
    input: { role: string; content: string | { type: string; text: string }[] }[];
    model: string;
    store: boolean;
    tools?: unknown[];
    previous_response_id?: string;
    conversation?: unknown;
    max_output_tokens: number;
    text: {
      format: {
        type: string;
        strict: boolean;
        schema: {
          properties: Record<string, unknown>;
          required: string[];
          additionalProperties: boolean;
        };
      };
    };
  }[] = [];
  globalThis.fetch = async (input, init) => {
    const request = new Request(input, init);
    assert.equal(request.url, 'https://api.openai.com/v1/responses');
    assert.equal(request.method, 'POST');
    assert.equal(request.redirect, 'error');
    const payload = JSON.parse(await request.text());
    payloads.push(payload);
    const index = payloads.length;
    return Response.json({
      id: `response-test-${index}`,
      model: context.model,
      output: [
        {
          type: 'message',
          id: `message-test-${index}`,
          role: 'assistant',
          content: [
            {
              type: 'output_text',
              text: JSON.stringify(
                index === 5
                  ? synthesis
                  : opinion((['value', 'feasibility', 'resources', 'risks'] as const)[index - 1]),
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
    const report = await runIdeaReview(context);
    assert.equal(report.experts.length, 4);
    assert.equal(payloads.length, 5);
    for (const [index, payload] of payloads.entries()) {
      assert.equal(payload.model, context.model);
      assert.equal(payload.store, false);
      assert.equal(payload.max_output_tokens, index === 4 ? 1800 : 1400);
      assert.ok(!payload.tools?.length);
      assert.equal(payload.previous_response_id, undefined);
      assert.equal(payload.conversation, undefined);
      const format = payload.text.format;
      assert.equal(format.type, 'json_schema');
      assert.equal(format.strict, true);
      assert.equal(format.schema.additionalProperties, false);
      assert.deepEqual(
        [...format.schema.required].sort(),
        Object.keys(format.schema.properties).sort(),
      );
      const users = payload.input.filter((message) => message.role === 'user');
      assert.equal(users.length, 1);
      const content = users[0].content;
      const data = JSON.parse(
        typeof content === 'string' ? content : content.map((part) => part.text).join(''),
      );
      assert.equal(data.idea, context.message);
      if (index < 4) assert.deepEqual(Object.keys(data), ['idea']);
      else
        assert.deepEqual(
          data.opinions.map((expert: { id: string }) => expert.id),
          ['value', 'feasibility', 'resources', 'risks'],
        );
    }
  } finally {
    globalThis.fetch = originalFetch;
  }
});
