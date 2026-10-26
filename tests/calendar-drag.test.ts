import assert from 'node:assert/strict';
import test from 'node:test';
import { calendarDragTarget, calendarDragWeekEdge } from '../src/features/calendar-drag';

const grid = { left: 100, top: -300, width: 770, timeColumn: 70, days: 7, hourHeight: 48 };

test('calendar dragging preserves the grabbed position and resolves day and quarter-hour', () => {
  assert.deepEqual(calendarDragTarget(330, 156, grid, 12, 60), { dayIndex: 1, minutes: 555 });
});

test('calendar dragging clamps before midnight and outside the first day', () => {
  assert.deepEqual(calendarDragTarget(110, 2000, grid, 0, 90), {
    dayIndex: 0,
    minutes: 1350,
  });
});

test('calendar week navigation only activates near the calendar edges', () => {
  assert.equal(calendarDragWeekEdge(111, 100, 870), -1);
  assert.equal(calendarDragWeekEdge(500, 100, 870), 0);
  assert.equal(calendarDragWeekEdge(859, 100, 870), 1);
});
