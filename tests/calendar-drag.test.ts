import assert from 'node:assert/strict';
import test from 'node:test';
import { calendarDragTarget, calendarDragWeekEdge } from '../src/features/calendar-drag';
import { CALENDAR_GRID_METRICS } from '../src/features/calendar-grid-metrics';

const grid = {
  left: 100,
  top: -300,
  width: 770,
  timeColumn: 70,
  days: 7,
  hourHeight: CALENDAR_GRID_METRICS.mobile.hourHeight,
};

test('calendar dragging preserves the grabbed position and resolves day and quarter-hour', () => {
  assert.deepEqual(calendarDragTarget(330, 156, grid, 12, 60), { dayIndex: 1, minutes: 555 });
});

test('calendar dragging clamps before midnight and outside the first day', () => {
  assert.deepEqual(calendarDragTarget(110, 2000, grid, 0, 90), {
    dayIndex: 0,
    minutes: 1350,
  });
});

test('desktop hours keep quarter-hour snapping aligned with the taller grid', () => {
  const desktopGrid = { ...grid, hourHeight: CALENDAR_GRID_METRICS.desktop.hourHeight };
  const grabbedAt = grid.top + 9.25 * desktopGrid.hourHeight + 12;
  assert.deepEqual(calendarDragTarget(330, grabbedAt, desktopGrid, 12, 60), {
    dayIndex: 1,
    minutes: 555,
  });
  assert.deepEqual(
    calendarDragTarget(330, grabbedAt + desktopGrid.hourHeight / 2, desktopGrid, 12, 60),
    {
      dayIndex: 1,
      minutes: 585,
    },
  );
});

test('calendar week navigation only activates near the calendar edges', () => {
  assert.equal(calendarDragWeekEdge(111, 100, 870), -1);
  assert.equal(calendarDragWeekEdge(500, 100, 870), 0);
  assert.equal(calendarDragWeekEdge(859, 100, 870), 1);
});
