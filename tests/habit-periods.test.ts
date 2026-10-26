import test from 'node:test';
import assert from 'node:assert/strict';
import type { Habit } from '../shared/types.ts';
import {
  habitBestStreak,
  habitCompleteOn,
  habitCompletionRate,
  habitScheduledOn,
  habitStreak,
} from '../src/features/habit-utils.ts';
import { addDays } from '../src/features/calendar-utils.ts';

test('habit analytics uses the schedule and archive state effective on each date', () => {
  const habit = {
    startDate: '2026-10-19',
    weekdays: [1, 2, 3, 4, 5],
    archived: false,
    completedDates: [
      '2026-10-19',
      '2026-10-21',
      '2026-10-23',
      '2026-10-26',
      '2026-10-27',
      '2026-10-28',
      '2026-11-02',
    ],
    periods: [
      { from: '2026-10-19', weekdays: [1, 3, 5], archived: false },
      { from: '2026-10-26', weekdays: [1, 2, 3, 4, 5], archived: false },
      { from: '2026-10-29', weekdays: [1, 2, 3, 4, 5], archived: true },
      { from: '2026-11-02', weekdays: [1, 2, 3, 4, 5], archived: false },
    ],
  } as Habit;

  assert.equal(habitScheduledOn(habit, '2026-10-20'), false);
  assert.equal(habitScheduledOn(habit, '2026-10-27'), true);
  assert.equal(habitScheduledOn(habit, '2026-10-29'), false);
  assert.equal(habitScheduledOn(habit, '2026-11-02'), true);
  assert.equal(habitCompleteOn(habit, '2026-10-23'), true);
  assert.equal(habitStreak(habit, '2026-10-29'), 0);
  assert.equal(habitStreak(habit, '2026-11-02'), 1);
  assert.equal(habitBestStreak(habit, '2026-11-02'), 6);
  const dates: string[] = [];
  for (let day = habit.startDate; day <= '2026-11-02'; day = addDays(day, 1)) dates.push(day);
  assert.deepEqual(habitCompletionRate(habit, dates), { completed: 7, scheduled: 7 });
});
