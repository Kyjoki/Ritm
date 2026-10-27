import test from 'node:test';
import assert from 'node:assert/strict';
import { easeOut, interpolateValues, sampleValues } from '../src/lib/motion-math';

test('motion preserves exact endpoint for currency, negative values, zero and completion percentages', () => {
  const target = [123456789.12, -349.37, 0, 100];
  assert.deepEqual(interpolateValues([0, 100, 5, 2], target, 1), target);
  assert.deepEqual(interpolateValues([], target, 2), target);
});
test('interrupted transition starts at its current presentation and can reverse without a zero reset', () => {
  const current = interpolateValues([20, 90], [80, 20], 0.4);
  assert.deepEqual(interpolateValues(current, [10, 100], 0), current);
  const next = interpolateValues(current, [10, 100], 0.5);
  assert.ok(next[0] < current[0] && next[0] > 10);
  assert.ok(next[1] > current[1] && next[1] < 100);
});
test('week to month resampling keeps endpoints and finite intermediate values', () => {
  const result = sampleValues([0, 25, 50, 100, 50, 25, 10], 31);
  assert.equal(result.length, 31);
  assert.equal(result[0], 0);
  assert.equal(result[30], 10);
  assert.ok(result.every((value) => Number.isFinite(value) && value >= 0 && value <= 100));
  assert.deepEqual(sampleValues([], 3), [0, 0, 0]);
  assert.deepEqual(sampleValues([5], 0), []);
});
test('easing is monotonic and bounded so counters never overshoot', () => {
  const samples = Array.from({ length: 101 }, (_, i) => easeOut(i / 100));
  assert.equal(easeOut(-1), 0);
  assert.equal(easeOut(2), 1);
  assert.ok(
    samples.every((value, i) => value >= 0 && value <= 1 && (!i || value >= samples[i - 1])),
  );
});
