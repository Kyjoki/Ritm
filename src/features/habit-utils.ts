import type { Habit } from '../../shared/types';
import { habitPeriod, habitWeekday, isHabitScheduled } from '../../shared/habit-schedule';
import { addDays } from './calendar-utils';

export const HABIT_MILESTONES = [3, 7, 14, 30] as const;
export { habitWeekday } from '../../shared/habit-schedule';

export function habitWeek(endDate: string): string[] {
  const sunday = addDays(endDate, -habitWeekday(endDate));
  return Array.from({ length: 7 }, (_, index) => addDays(sunday, index));
}

export function habitScheduledOn(habit: Habit, date: string): boolean {
  return isHabitScheduled(habit, date);
}

export function habitCanMarkOn(habit: Habit, date: string, today: string): boolean {
  if (habit.archived || date > today) return false;
  if (date >= habit.startDate) return habitScheduledOn(habit, date);
  const firstPeriod = habit.periods?.[0];
  return (
    !(firstPeriod?.archived ?? false) &&
    (firstPeriod?.weekdays ?? habit.weekdays ?? [0, 1, 2, 3, 4, 5, 6]).includes(habitWeekday(date))
  );
}

function habitArchivedOn(habit: Habit, date: string): boolean {
  return habitPeriod(habit, date)?.archived ?? true;
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
  const summary = habitPeriodSummary([habit], dates);
  return {
    completed: summary.completed,
    scheduled: summary.planned,
  };
}

export interface HabitSummary {
  planned: number;
  completed: number;
  /** Null means there were no scheduled opportunities, not a failed day. */
  progress: number | null;
}

export function habitAnalyticsScope(habits: readonly Habit[], archived: boolean): Habit[] {
  return habits.filter((habit) => Boolean(habit.archived) === archived);
}

export function habitDaySummary(
  habits: readonly Habit[],
  date: string,
  today?: string,
): HabitSummary {
  if (today && date > today) return { planned: 0, completed: 0, progress: null };
  let planned = 0;
  let completed = 0;
  for (const habit of habits) {
    if (!habitScheduledOn(habit, date)) continue;
    planned++;
    if (habitCompleteOn(habit, date)) completed++;
  }
  return { planned, completed, progress: planned ? Math.round((completed / planned) * 100) : null };
}

export function habitPeriodSummary(
  habits: readonly Habit[],
  dates: readonly string[],
  today?: string,
): HabitSummary {
  let planned = 0;
  let completed = 0;
  for (const date of dates) {
    const day = habitDaySummary(habits, date, today);
    planned += day.planned;
    completed += day.completed;
  }
  return { planned, completed, progress: planned ? Math.round((completed / planned) * 100) : null };
}
