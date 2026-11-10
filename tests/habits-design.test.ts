import test from 'node:test';
import assert from 'node:assert/strict';
import type { Habit } from '../shared/types.ts';
import {
  HABIT_MILESTONES,
  HABIT_PALETTE,
  habitColor,
  habitColorIndex,
  habitDayFraction,
  habitDayState,
  habitMilestoneEvents,
  habitMilestonesEarned,
  habitNextMilestone,
  habitPeriodStats,
  habitStep,
  habitWeek,
} from '../src/features/habit-utils.ts';
import { addDays } from '../src/features/calendar-utils.ts';

function habit(fields: Partial<Habit>): Habit {
  return {
    id: 'habit-1',
    title: 'Gym',
    startDate: '2026-10-01',
    completedDates: [],
    createdAt: '2026-10-01T00:00:00.000Z',
    updatedAt: '2026-10-01T00:00:00.000Z',
    ...fields,
  };
}

function days(from: string, count: number): string[] {
  return Array.from({ length: count }, (_, index) => addDays(from, index));
}

test('each habit keeps one palette colour that depends only on its id', () => {
  const first = habitColorIndex('3f9c1a52-7d77-4a5b-9e6a-0c0f1b2d3e4f');
  assert.equal(first, habitColorIndex('3f9c1a52-7d77-4a5b-9e6a-0c0f1b2d3e4f'));
  assert.equal(habitColor(habit({ id: 'a', title: 'One' })), habitColor(habit({ id: 'a' })));
  const used = new Set(Array.from({ length: 64 }, (_, index) => habitColorIndex('habit-' + index)));
  assert.ok(used.size >= 5, 'ids spread over the palette');
  for (const index of used) assert.ok(index >= 0 && index < HABIT_PALETTE.length);
  assert.equal(
    habitColor(habit({ id: '', title: 'Fallback' })),
    HABIT_PALETTE[habitColorIndex('Fallback')],
  );
});

test('the stepper uses single units for small goals and round steps for large ones', () => {
  assert.equal(habitStep({ target: null }), 1);
  assert.equal(habitStep({ target: 8 }), 1);
  assert.equal(habitStep({ target: 12 }), 1);
  assert.equal(habitStep({ target: 20 }), 5);
  assert.equal(habitStep({ target: 2000 }), 250);
  assert.equal(habitStep({ target: 100000 }), 1000);
});

test('milestones come from the server record or the best streak, and the next one follows the current streak', () => {
  assert.deepEqual([...HABIT_MILESTONES], [3, 7, 14, 30, 60, 100]);
  assert.deepEqual(habitMilestonesEarned(habit({ achievements: [3, 7] }), 2), [3, 7]);
  assert.deepEqual(habitMilestonesEarned(habit({ achievements: [] }), 61), [3, 7, 14, 30, 60]);
  assert.deepEqual(habitMilestonesEarned(habit({}), 0), []);
  assert.equal(habitNextMilestone(0), 3);
  assert.equal(habitNextMilestone(3), 7);
  assert.equal(habitNextMilestone(29), 30);
  assert.equal(habitNextMilestone(100), null);
});

test('day state separates rest days, future days, partial and missed goals', () => {
  const water = habit({
    weekdays: [1, 2, 3, 4, 5],
    target: 8,
    completedDates: ['2026-10-26'],
    progressByDate: { '2026-10-26': 8, '2026-10-27': 3 },
  });
  const today = '2026-10-29';
  assert.equal(habitDayState(water, '2026-10-25', today), 'off');
  assert.equal(habitDayState(water, '2026-10-26', today), 'done');
  assert.equal(habitDayState(water, '2026-10-27', today), 'part');
  assert.equal(habitDayState(water, '2026-10-28', today), 'miss');
  assert.equal(habitDayState(water, '2026-10-30', today), 'future');
  assert.equal(habitDayFraction(water, '2026-10-27'), 3 / 8);
  assert.equal(habitDayFraction(water, '2026-10-26'), 1);
  assert.equal(habitDayFraction(water, '2026-10-28'), 0);
  assert.equal(
    habitDayFraction(habit({ target: 2, progressByDate: { '2026-10-26': 5 } }), '2026-10-26'),
    1,
  );
});

test('period stats count scheduled days up to today and average the progress', () => {
  const read = habit({
    weekdays: [0, 1, 2, 3, 4, 5, 6],
    target: 20,
    startDate: '2026-10-25',
    completedDates: ['2026-10-25', '2026-10-26'],
    progressByDate: { '2026-10-25': 20, '2026-10-26': 20, '2026-10-27': 10 },
  });
  const week = habitWeek('2026-10-27');
  assert.deepEqual(habitPeriodStats(read, week, '2026-10-28'), {
    scheduled: 4,
    completed: 2,
    percent: 50,
    average: 13,
  });
  assert.deepEqual(habitPeriodStats(read, week, '2026-10-24'), {
    scheduled: 0,
    completed: 0,
    percent: null,
    average: 0,
  });
});

test('milestone history keeps the latest day each milestone was reached, newest first', () => {
  const dates = [...days('2026-10-01', 8), ...days('2026-10-12', 4)];
  const run = habit({ completedDates: dates });
  assert.deepEqual(habitMilestoneEvents(run, '2026-10-15'), [
    { milestone: 3, date: '2026-10-14' },
    { milestone: 7, date: '2026-10-07' },
  ]);
  const broken = habit({ completedDates: days('2026-10-01', 3) });
  assert.deepEqual(habitMilestoneEvents(broken, '2026-10-10'), [
    { milestone: 3, date: '2026-10-03' },
  ]);
  assert.deepEqual(habitMilestoneEvents(habit({}), '2026-10-10'), []);
});

test('milestone history ignores rest days and restarts after an archived stretch', () => {
  const weekdaysOnly = habit({
    weekdays: [1, 2, 3, 4, 5],
    startDate: '2026-10-05',
    completedDates: [
      '2026-10-05',
      '2026-10-06',
      '2026-10-07',
      '2026-10-08',
      '2026-10-09',
      '2026-10-12',
    ],
  });
  assert.deepEqual(habitMilestoneEvents(weekdaysOnly, '2026-10-12'), [
    { milestone: 3, date: '2026-10-07' },
  ]);
  const archivedMiddle = habit({
    startDate: '2026-10-01',
    completedDates: days('2026-10-01', 10),
    periods: [
      { from: '2026-10-01', weekdays: [0, 1, 2, 3, 4, 5, 6], archived: false },
      { from: '2026-10-03', weekdays: [0, 1, 2, 3, 4, 5, 6], archived: true },
      { from: '2026-10-06', weekdays: [0, 1, 2, 3, 4, 5, 6], archived: false },
    ],
  });
  assert.deepEqual(habitMilestoneEvents(archivedMiddle, '2026-10-10'), [
    { milestone: 3, date: '2026-10-08' },
  ]);
});
