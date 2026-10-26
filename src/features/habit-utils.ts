import type { Habit } from '../../shared/types';
import { addDays } from './calendar-utils';

export const HABIT_MILESTONES = [3, 7, 14, 30] as const;

export function habitWeek(endDate: string): string[] {
  const sunday = addDays(endDate, -habitWeekday(endDate));
  return Array.from({ length: 7 }, (_, index) => addDays(sunday, index));
}

export function habitWeekday(date: string): number {
  return new Date(`${date}T12:00:00Z`).getUTCDay();
}

export function habitScheduledOn(habit: Habit, date: string): boolean {
  if (date < habit.startDate) return false;
  const period = habit.periods?.findLast((item) => item.from <= date);
  return (
    !(period?.archived ?? habit.archived ?? false) &&
    (period?.weekdays ?? habit.weekdays ?? [0, 1, 2, 3, 4, 5, 6]).includes(habitWeekday(date))
  );
}

function habitArchivedOn(habit: Habit, date: string): boolean {
  const period = habit.periods?.findLast((item) => item.from <= date);
  return period?.archived ?? habit.archived ?? false;
}

export function habitTarget(habit: Habit): number {
  return habit.target ?? 1;
}

export function habitProgress(habit: Habit, date: string): number {
  const stored = habit.progressByDate?.[date];
  return stored === undefined
    ? habit.completedDates.includes(date)
      ? habitTarget(habit)
      : 0
    : stored;
}

export function habitCompleteOn(habit: Habit, date: string): boolean {
  return habitScheduledOn(habit, date) && habit.completedDates.includes(date);
}

export function habitStreak(habit: Habit, today: string): number {
  let day = today;
  while (day >= habit.startDate && !habitScheduledOn(habit, day)) {
    if (habitArchivedOn(habit, day)) return 0;
    day = addDays(day, -1);
  }
  if (day === today && !habitCompleteOn(habit, day)) day = addDays(day, -1);
  while (day >= habit.startDate && !habitScheduledOn(habit, day)) {
    if (habitArchivedOn(habit, day)) return 0;
    day = addDays(day, -1);
  }
  let count = 0;
  while (day >= habit.startDate) {
    if (habitArchivedOn(habit, day)) break;
    if (habitScheduledOn(habit, day)) {
      if (!habitCompleteOn(habit, day)) break;
      count++;
    }
    day = addDays(day, -1);
  }
  return count;
}

export function habitBestStreak(habit: Habit, today: string): number {
  let best = 0;
  let current = 0;
  for (let day = habit.startDate; day <= today; day = addDays(day, 1)) {
    if (habitArchivedOn(habit, day)) {
      current = 0;
      continue;
    }
    if (!habitScheduledOn(habit, day)) continue;
    current = habitCompleteOn(habit, day) ? current + 1 : 0;
    best = Math.max(best, current);
  }
  return best;
}

export function habitCompletionRate(
  habit: Habit,
  dates: string[],
): { completed: number; scheduled: number } {
  const eligible = dates.filter((day) => habitScheduledOn(habit, day));
  return {
    completed: eligible.filter((day) => habitCompleteOn(habit, day)).length,
    scheduled: eligible.length,
  };
}
