import test from 'node:test';
import assert from 'node:assert/strict';
import type { Habit } from '../shared/types.ts';
import {
  habitAnalyticsScope,
  habitBestStreak,
  habitCompleteOn,
  habitCompletionRate,
  habitDaySummary,
  habitPeriodSummary,
  habitScheduledOn,
  habitStreak,
  habitWeek,
  habitWeekday,
} from '../src/features/habit-utils.ts';
import { addDays } from '../src/features/calendar-utils.ts';
import { dateInZone } from '../src/lib/date.ts';

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

test('daily and period analytics count only scheduled, completed opportunities', () => {
  const gym = {
    id: 'gym',
    title: 'Gym',
    startDate: '2026-10-26',
    weekdays: [1, 2, 6],
    archived: false,
    completedDates: ['2026-10-26'],
    createdAt: '2026-10-26T00:00:00.000Z',
    updatedAt: '2026-10-26T00:00:00.000Z',
  } as Habit;
  const ielts = {
    id: 'ielts',
    title: 'IELTS',
    startDate: '2026-10-26',
    weekdays: [0, 2, 5, 6],
    archived: false,
    completedDates: [],
    createdAt: '2026-10-26T00:00:00.000Z',
    updatedAt: '2026-10-26T00:00:00.000Z',
  } as Habit;
  const habits = [gym, ielts];
  assert.equal(habitWeekday('2026-10-25'), 0);
  assert.equal(habitWeekday('2026-10-26'), 1);
  assert.deepEqual(habitWeek('2026-10-27'), [
    '2026-10-25',
    '2026-10-26',
    '2026-10-27',
    '2026-10-28',
    '2026-10-29',
    '2026-10-30',
    '2026-10-31',
  ]);
  assert.deepEqual(habitDaySummary(habits, '2026-10-26'), {
    planned: 1,
    completed: 1,
    progress: 100,
  });
  assert.deepEqual(habitDaySummary(habits, '2026-10-27'), {
    planned: 2,
    completed: 0,
    progress: 0,
  });
  const gymTuesday = { ...gym, completedDates: [...gym.completedDates, '2026-10-27'] };
  assert.deepEqual(habitDaySummary([gymTuesday, ielts], '2026-10-27'), {
    planned: 2,
    completed: 1,
    progress: 50,
  });
  const ieltsTuesday = { ...ielts, completedDates: ['2026-10-27'] };
  assert.deepEqual(habitDaySummary([gymTuesday, ieltsTuesday], '2026-10-27'), {
    planned: 2,
    completed: 2,
    progress: 100,
  });
  assert.deepEqual(habitDaySummary([gym, ieltsTuesday], '2026-10-27'), {
    planned: 2,
    completed: 1,
    progress: 50,
  });
  assert.deepEqual(habitDaySummary(habits, '2026-10-28'), {
    planned: 0,
    completed: 0,
    progress: null,
  });
  assert.deepEqual(habitPeriodSummary([gymTuesday, ielts], ['2026-10-26', '2026-10-27']), {
    planned: 3,
    completed: 2,
    progress: 67,
  });
  assert.deepEqual(habitPeriodSummary(habits, habitWeek('2026-10-26'), '2026-10-26'), {
    planned: 1,
    completed: 1,
    progress: 100,
  });
  assert.deepEqual(habitDaySummary(habits, '2026-11-01'), {
    planned: 1,
    completed: 0,
    progress: 0,
  });
  assert.deepEqual(habitPeriodSummary(habits, ['2026-10-28']), {
    planned: 0,
    completed: 0,
    progress: null,
  });
});

test('client and server honor historical periods, archive state, and owner dates', () => {
  const habit = {
    startDate: '2026-10-26',
    weekdays: [1, 2],
    archived: false,
    completedDates: ['2026-10-26', '2026-10-27'],
    periods: [
      { from: '2026-10-27', weekdays: [2], archived: false },
      { from: '2026-10-28', weekdays: [2], archived: true },
    ],
  } as Habit;
  assert.deepEqual(habitDaySummary([habit], '2026-10-26'), {
    planned: 0,
    completed: 0,
    progress: null,
  });
  assert.deepEqual(habitDaySummary([habit], '2026-10-27'), {
    planned: 1,
    completed: 1,
    progress: 100,
  });
  assert.deepEqual(habitDaySummary([habit], '2026-11-03'), {
    planned: 0,
    completed: 0,
    progress: null,
  });
  assert.equal(dateInZone('Asia/Qyzylorda', new Date('2026-10-26T20:30:00Z')), '2026-10-27');
  assert.equal(dateInZone('America/New_York', new Date('2026-10-26T02:30:00Z')), '2026-10-25');
});

test('active analytics excludes archived history while archive view preserves it', () => {
  const base = {
    createdAt: '2026-10-25T00:00:00.000Z',
    updatedAt: '2026-10-27T00:00:00.000Z',
    startDate: '2026-10-25',
  };
  const gym = {
    ...base,
    id: 'gym',
    title: 'Gym',
    weekdays: [1, 2, 6],
    archived: false,
    completedDates: ['2026-10-26'],
  } as Habit;
  const ielts = {
    ...base,
    id: 'ielts',
    title: 'IELTS',
    weekdays: [0, 2, 5, 6],
    archived: false,
    completedDates: ['2026-10-25'],
  } as Habit;
  const oldHabit = {
    ...base,
    id: 'old',
    title: 'Old habit',
    weekdays: [1],
    archived: true,
    completedDates: [],
    periods: [
      { from: '2026-10-25', weekdays: [1], archived: false },
      { from: '2026-10-27', weekdays: [1], archived: true },
    ],
  } as Habit;
  const all = [gym, ielts, oldHabit];
  const active = habitAnalyticsScope(all, false);
  const archived = habitAnalyticsScope(all, true);
  assert.deepEqual(habitDaySummary(active, '2026-10-25'), {
    planned: 1,
    completed: 1,
    progress: 100,
  });
  assert.deepEqual(habitDaySummary(active, '2026-10-26'), {
    planned: 1,
    completed: 1,
    progress: 100,
  });
  assert.deepEqual(habitPeriodSummary(active, ['2026-10-25', '2026-10-26']), {
    planned: 2,
    completed: 2,
    progress: 100,
  });
  assert.deepEqual(habitDaySummary(archived, '2026-10-26'), {
    planned: 1,
    completed: 0,
    progress: 0,
  });
  assert.deepEqual(habitDaySummary(all, '2026-10-26'), {
    planned: 2,
    completed: 1,
    progress: 50,
  });
});
