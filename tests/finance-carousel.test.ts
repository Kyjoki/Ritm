import test from 'node:test';
import assert from 'node:assert/strict';
import {
  cardTiming,
  carouselSlot,
  stackSlot,
  stepIndex,
  tapOutcome,
} from '../src/features/finance/finance-stack.ts';

test('a tap on the stack opens it, on the centred card collapses it, on a neighbour selects it', () => {
  assert.deepEqual(tapOutcome(false, 0, 3), { kind: 'open', index: 3 });
  assert.deepEqual(tapOutcome(false, 2, 2), { kind: 'open', index: 2 });
  assert.deepEqual(tapOutcome(true, 2, 2), { kind: 'collapse', index: 2 });
  assert.deepEqual(tapOutcome(true, 2, 1), { kind: 'select', index: 1 });
  assert.deepEqual(tapOutcome(true, 2, 4), { kind: 'select', index: 4 });
});

test('arrow steps stop at both ends and survive an empty or single-card wallet', () => {
  assert.equal(stepIndex(0, -1, 4), 0);
  assert.equal(stepIndex(3, 1, 4), 3);
  assert.equal(stepIndex(1, 1, 4), 2);
  assert.equal(stepIndex(2, -1, 4), 1);
  assert.equal(stepIndex(0, 1, 1), 0);
  assert.equal(stepIndex(0, 1, 0), 0);
});

test('the centred carousel card is smaller than a stack card, undimmed and on top', () => {
  const centre = carouselSlot(2, 2);
  assert.equal(centre.xPercent, 0);
  assert.equal(centre.xPx, 0);
  assert.ok(Math.abs(centre.scale - 300 / 350) < 1e-9);
  assert.equal(centre.yPercent, 0);
  assert.equal(centre.dim, 1);
  assert.equal(centre.layer, 100);
  assert.ok(centre.scale < stackSlot(2, 2, 5).scale);
});

test('neighbours sit left and right of the centre, shrunk, dimmed and symmetric', () => {
  const left = carouselSlot(1, 2);
  const right = carouselSlot(3, 2);
  assert.ok(left.xPercent < 0 && right.xPercent > 0);
  assert.equal(left.xPercent, -right.xPercent);
  assert.equal(left.xPx, -right.xPx);
  assert.ok(left.scale < carouselSlot(2, 2).scale);
  assert.ok(left.dim < 1 && left.layer < 100);
  const far = carouselSlot(0, 2);
  assert.ok(far.xPercent < left.xPercent);
  assert.equal(far.scale, left.scale);
  assert.ok(far.layer < left.layer);
});

test('the open card leaves a visible edge of its neighbour inside the column', () => {
  const width = 350;
  const centre = carouselSlot(0, 0);
  const next = carouselSlot(1, 0);
  const edge = (slot: ReturnType<typeof carouselSlot>) =>
    (width * slot.xPercent) / 100 + slot.xPx + (width * (1 - slot.scale)) / 2;
  const centreRight = edge(centre) + width * centre.scale;
  assert.ok(edge(next) > centreRight, 'the neighbour starts after the centred card');
  assert.ok(edge(next) < width, 'and its edge peeks inside the column');
});

test('open fans cards out from the selected one, close folds them back towards it', () => {
  const open = [0, 1, 2, 3].map((index) => cardTiming('open', index, 1, 4));
  assert.equal(open[1].delayMs, 0);
  assert.ok(open[3].delayMs > open[2].delayMs && open[2].delayMs > 0);
  const close = [0, 1, 2, 3].map((index) => cardTiming('close', index, 1, 4));
  assert.equal(close[3].delayMs, 0);
  assert.ok(close[1].delayMs > close[2].delayMs);
  assert.ok(
    close[0].durationMs > 0 && close[0].durationMs < 500,
    'collapse takes about 0.42s overall',
  );
  const slide = cardTiming('slide', 3, 1, 4);
  assert.equal(slide.delayMs, 0);
});
