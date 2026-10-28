import test from 'node:test';
import assert from 'node:assert/strict';
import {
  ARM_WINDOW_MS,
  OUTCOME_MS,
  idle,
  nextFeedback,
  type Feedback,
} from '../src/lib/action-feedback';

const run = (events: Parameters<typeof nextFeedback>[1][], from: Feedback = idle) =>
  events.reduce(nextFeedback, from);

test('press followed by disable shows loading, then success when re-enabled', () => {
  const loading = run([
    { type: 'press', at: 0 },
    { type: 'disabled', at: 20 },
  ]);
  assert.equal(loading.state, 'loading');
  const done = nextFeedback(loading, { type: 'enabled', at: 400, errorSince: false });
  assert.deepEqual(done, { state: 'success', since: 400 });
});

test('an error that surfaced while loading ends in the error state', () => {
  const result = run([
    { type: 'press', at: 0 },
    { type: 'disabled', at: 10 },
    { type: 'enabled', at: 300, errorSince: true },
  ]);
  assert.equal(result.state, 'error');
});

test('a disable long after the press is not attributed to the press', () => {
  const result = run([
    { type: 'press', at: 0 },
    { type: 'disabled', at: ARM_WINDOW_MS + 1 },
  ]);
  assert.equal(result.state, 'armed');
});

test('disabling without a press never shows loading', () => {
  assert.equal(run([{ type: 'disabled', at: 5 }]).state, 'idle');
});

test('repeated presses during loading keep the running request', () => {
  const result = run([
    { type: 'press', at: 0 },
    { type: 'disabled', at: 10 },
    { type: 'press', at: 50 },
    { type: 'press', at: 60 },
  ]);
  assert.deepEqual(result, { state: 'loading', since: 10 });
});

test('outcome and unused arm settle back to idle', () => {
  const success = { state: 'success', since: 100 } as const;
  assert.equal(
    nextFeedback(success, { type: 'settle', at: 100 + OUTCOME_MS - 1 }).state,
    'success',
  );
  assert.equal(nextFeedback(success, { type: 'settle', at: 100 + OUTCOME_MS }).state, 'idle');
  const armed = { state: 'armed', since: 0 } as const;
  assert.equal(nextFeedback(armed, { type: 'settle', at: ARM_WINDOW_MS + 1 }).state, 'idle');
});

test('a new press during a shown outcome re-arms immediately', () => {
  const result = nextFeedback({ state: 'success', since: 0 }, { type: 'press', at: 200 });
  assert.deepEqual(result, { state: 'armed', since: 200 });
});
