import type { Habit } from '../../shared/types';
import { habitPeriod, habitWeekday, isHabitScheduled } from '../../shared/habit-schedule';
import { addDays } from './calendar-utils';

export const HABIT_MILESTONES = [3, 7, 14, 30, 60, 100] as const;
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

/** Accent colours of the habit cards. Each habit keeps one colour for its whole life. */
export const HABIT_PALETTE = [
  '#9c77db',
  '#77a6d4',
  '#79b8a7',
  '#d798bc',
  '#d7ad76',
  '#b79cb6',
  '#d98aa8',
  '#6fb28c',
] as const;

export function habitColorIndex(key: string): number {
  // FNV-1a keeps the colour stable between sessions and devices without storing it.
  let hash = 0x811c9dc5;
  for (let index = 0; index < key.length; index++) {
    hash ^= key.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash % HABIT_PALETTE.length;
}

export function habitColor(habit: Pick<Habit, 'id' | 'title'>): string {
  return HABIT_PALETTE[habitColorIndex(habit.id || habit.title)];
}

const STEP_CHOICES = [1, 2, 5, 10, 25, 50, 100, 250, 500, 1000];

/** Quantity stepper increment: single units for small goals, round steps for large ones. */
export function habitStep(habit: Pick<Habit, 'target'>): number {
  const target = habit.target ?? 1;
  if (target <= 12) return 1;
  return STEP_CHOICES.find((step) => step >= target / 8) ?? STEP_CHOICES[STEP_CHOICES.length - 1];
}

/** Milestones earned by the server record or by the best streak (60 and 100 are derived). */
export function habitMilestonesEarned(habit: Habit, best: number): number[] {
  return HABIT_MILESTONES.filter(
    (milestone) => best >= milestone || (habit.achievements ?? []).includes(milestone),
  );
}

/** The first milestone above the streak, or null once every milestone is behind it. */
export function habitNextMilestone(streak: number): number | null {
  return HABIT_MILESTONES.find((milestone) => milestone > streak) ?? null;
}

export type HabitDayState = 'future' | 'off' | 'done' | 'part' | 'miss';

export function habitDayState(habit: Habit, date: string, today: string): HabitDayState {
  if (date > today) return 'future';
  if (!habitCanMarkOn(habit, date, today) && !habitScheduledOn(habit, date)) return 'off';
  if (habit.completedDates.includes(date)) return 'done';
  return habitProgress(habit, date) > 0 ? 'part' : 'miss';
}

/** Share of the goal reached on a day, 0..1. */
export function habitDayFraction(habit: Habit, date: string): number {
  return Math.min(1, habitProgress(habit, date) / habitTarget(habit));
}

export interface HabitPeriodStats {
  scheduled: number;
  completed: number;
  /** Null when nothing was scheduled in the period. */
  percent: number | null;
  /** Average progress per scheduled day, in the habit's unit. */
  average: number;
}

export function habitPeriodStats(
  habit: Habit,
  dates: readonly string[],
  today: string,
): HabitPeriodStats {
  const summary = habitPeriodSummary([habit], dates, today);
  let sum = 0;
  for (const date of dates)
    if (date <= today && habitScheduledOn(habit, date)) sum += habitProgress(habit, date);
  return {
    scheduled: summary.planned,
    completed: summary.completed,
    percent: summary.progress,
    average: summary.planned ? Math.round(sum / summary.planned) : 0,
  };
}

export interface HabitMilestoneEvent {
  milestone: number;
  /** The most recent day the streak reached this milestone. */
  date: string;
}

/** Newest first. Follows the same schedule and archive rules as habitBestStreak. */
export function habitMilestoneEvents(habit: Habit, today: string): HabitMilestoneEvent[] {
  const latest = new Map<number, string>();
  let run = 0;
  for (let day = habit.startDate; day <= today; day = addDays(day, 1)) {
    if (habitArchivedOn(habit, day)) {
      run = 0;
      continue;
    }
    if (!habitScheduledOn(habit, day)) continue;
    run = habitCompleteOn(habit, day) ? run + 1 : 0;
    if ((HABIT_MILESTONES as readonly number[]).includes(run)) latest.set(run, day);
  }
  return [...latest]
    .map(([milestone, date]) => ({ milestone, date }))
    .sort((a, b) => (a.date < b.date ? 1 : a.date > b.date ? -1 : b.milestone - a.milestone));
}

export type HabitPeriod = 'week' | 'month';

/** Dates of the week (Sunday first) or calendar month `offset` periods away from `today`. */
export function habitPeriodDates(today: string, period: HabitPeriod, offset: number): string[] {
  if (period === 'week') return habitWeek(addDays(today, offset * 7));
  const [year, month] = today.split('-').map(Number);
  const first = new Date(Date.UTC(year, month - 1 + offset, 1));
  const last = new Date(Date.UTC(year, month + offset, 0));
  const result: string[] = [];
  for (
    let day = first.toISOString().slice(0, 10);
    day <= last.toISOString().slice(0, 10);
    day = addDays(day, 1)
  )
    result.push(day);
  return result;
}

/** Today when the period contains it, otherwise the last day that is not in the future. */
export function habitDefaultDay(dates: readonly string[], today: string): string {
  if (dates.includes(today)) return today;
  return dates.filter((date) => date <= today).pop() ?? dates[0];
}
