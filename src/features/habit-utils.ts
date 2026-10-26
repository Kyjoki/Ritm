import type { Habit } from '../../shared/types';
import { addDays } from './calendar-utils';

export function habitStreak(habit: Habit, today: string): number {
  const done = new Set(habit.completedDates);
  let day = done.has(today) ? today : addDays(today, -1);
  let count = 0;
  while (day >= habit.startDate && done.has(day)) {
    count++;
    day = addDays(day, -1);
  }
  return count;
}

export function habitWeek(endDate: string): string[] {
  return Array.from({ length: 7 }, (_, index) => addDays(endDate, index - 6));
}
