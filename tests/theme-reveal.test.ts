import test from 'node:test';
import assert from 'node:assert/strict';
import {
  REVEAL_EASING,
  REVEAL_MS,
  revealClip,
  revealOrigin,
  revealRadius,
  unzoomBox,
} from '../src/lib/theme-reveal.ts';

const SCREEN = { width: 1440, height: 900 };

test('the circle reaches the farthest corner from the toggle button', () => {
  assert.equal(revealRadius({ x: 0, y: 0 }, SCREEN), Math.hypot(1440, 900));
  assert.equal(revealRadius({ x: 1440, y: 900 }, SCREEN), Math.hypot(1440, 900));
  assert.equal(revealRadius({ x: 1400, y: 40 }, SCREEN), Math.hypot(1400, 860));
  assert.equal(revealRadius({ x: 720, y: 450 }, SCREEN), Math.hypot(720, 450));
});

test('the radius always covers every corner of the viewport', () => {
  for (const origin of [
    { x: 10, y: 10 },
    { x: 1430, y: 20 },
    { x: 700, y: 880 },
    { x: -30, y: 2000 },
  ]) {
    const radius = revealRadius(origin, SCREEN);
    for (const corner of [
      { x: 0, y: 0 },
      { x: SCREEN.width, y: 0 },
      { x: 0, y: SCREEN.height },
      { x: SCREEN.width, y: SCREEN.height },
    ]) {
      assert.ok(Math.hypot(corner.x - origin.x, corner.y - origin.y) <= radius + 1e-9);
    }
  }
});

test('the origin is the button centre, kept on screen, or the viewport centre without a button', () => {
  assert.deepEqual(revealOrigin({ left: 1380, top: 16, width: 40, height: 40 }, SCREEN), {
    x: 1400,
    y: 36,
  });
  assert.deepEqual(revealOrigin(null, SCREEN), { x: 720, y: 450 });
  assert.deepEqual(revealOrigin({ left: 0, top: 0, width: 0, height: 0 }, SCREEN), {
    x: 720,
    y: 450,
  });
  assert.deepEqual(revealOrigin({ left: 1500, top: -80, width: 40, height: 40 }, SCREEN), {
    x: 1440,
    y: 0,
  });
});

test('the clip animation grows from a point to a rounded-up circle over 520ms ease-in-out', () => {
  assert.deepEqual(revealClip({ x: 1400.4, y: 36 }, 1700.2), [
    'circle(0px at 1400px 36px)',
    'circle(1701px at 1400px 36px)',
  ]);
  assert.equal(REVEAL_MS, 520);
  assert.match(REVEAL_EASING, /\.65, 0, \.35, 1/);
});

test('a zoomed root shrinks screen rectangles into the zoomed space of the transition layers', () => {
  const box = { left: 1000, top: 16, width: 40, height: 40 };
  assert.equal(unzoomBox(box, 1), box);
  assert.equal(unzoomBox(null, 0.8), null);
  assert.deepEqual(unzoomBox(box, 0.8), { left: 1250, top: 20, width: 50, height: 50 });
  assert.equal(unzoomBox(box, 0), box);
});
