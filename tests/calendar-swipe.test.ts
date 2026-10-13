import assert from 'node:assert/strict';
import test from 'node:test';
import { calendarWeekSwipe } from '../src/features/calendar-swipe';

const start = { x: 180, y: 250, time: 100 };
test('horizontal swipes move one week in the expected direction', () => {
  assert.equal(calendarWeekSwipe(start, { x: 70, y: 260, time: 400 }, 390), 1);
  assert.equal(calendarWeekSwipe(start, { x: 290, y: 240, time: 400 }, 390), -1);
});
test('taps, vertical scrolling, and diagonal movements do not change the week', () => {
  assert.equal(calendarWeekSwipe(start, { x: 187, y: 251, time: 300 }, 390), 0);
  assert.equal(calendarWeekSwipe(start, { x: 190, y: 380, time: 300 }, 390), 0);
  assert.equal(calendarWeekSwipe(start, { x: 290, y: 350, time: 300 }, 390), 0);
});
test('short gestures on wider screens and long-held gestures are ignored', () => {
  assert.equal(calendarWeekSwipe(start, { x: 250, y: 250, time: 300 }, 760), 0);
  assert.equal(calendarWeekSwipe(start, { x: 70, y: 250, time: 1_400 }, 390), 0);
  assert.equal(calendarWeekSwipe(start, { x: 70, y: 250, time: 99 }, 390), 0);
});
