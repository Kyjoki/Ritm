import type { Habit, HabitInput } from '../shared/types.ts';
import { AppError, conflict } from './errors.ts';

export const habitMilestones = [3, 7, 14, 30] as const;
const allWeekdays = [0, 1, 2, 3, 4, 5, 6];

export function habitPeriod(habit: Habit, date: string) {
  if (!habit.periods?.length)
    return { weekdays: habit.weekdays ?? allWeekdays, archived: habit.archived ?? false };
  for (let index = habit.periods.length - 1; index >= 0; index--) {
    if (habit.periods[index].from <= date) return habit.periods[index];
  }
  return null;
}

export function isHabitScheduled(habit: Habit, date: string): boolean {
  if (date < habit.startDate) return false;
  const period = habitPeriod(habit, date);
  const weekday = new Date(`${date}T12:00:00Z`).getUTCDay();
  return Boolean(period && !period.archived && period.weekdays.includes(weekday));
}

export function habitProgress(habit: Habit, date: string): number {
  return (
    habit.progressByDate?.[date] ?? (habit.completedDates.includes(date) ? (habit.target ?? 1) : 0)
  );
}

function addDate(date: string, days: number): string {
  const value = new Date(`${date}T12:00:00Z`);
  value.setUTCDate(value.getUTCDate() + days);
  return value.toISOString().slice(0, 10);
}

export function habitBestStreak(habit: Habit): number {
  let best = 0;
  let streak = 0;
  let previous = '';
  for (const date of [...new Set(habit.completedDates)].sort()) {
    if (date < habit.startDate || !isHabitScheduled(habit, date)) continue;
    if (previous) {
      let next = addDate(previous, 1);
      let gap = false;
      while (next < date) {
        if (isHabitScheduled(habit, next)) {
          gap = true;
          break;
        }
        next = addDate(next, 1);
      }
      streak = gap ? 1 : streak + 1;
    } else streak = 1;
    best = Math.max(best, streak);
    previous = date;
  }
  return best;
}

export function updateHabitProgress(habit: Habit, date: string, count: number): Habit {
  const target = habit.target ?? 1;
  const progressByDate = { ...habit.progressByDate };
  if (count) progressByDate[date] = count;
  else delete progressByDate[date];
  const completedDates = new Set(habit.completedDates);
  if (count >= target) completedDates.add(date);
  else completedDates.delete(date);
  const updated = { ...habit, progressByDate, completedDates: [...completedDates].sort() };
  const best = habitBestStreak(updated);
  return {
    ...updated,
    achievements: [
      ...new Set([
        ...(habit.achievements ??
          habitMilestones.filter((milestone) => milestone <= habitBestStreak(habit))),
        ...habitMilestones.filter((milestone) => milestone <= best),
      ]),
    ].sort((a, b) => a - b),
  };
}

export function updateHabitDefinition(habit: Habit, fields: HabitInput, today: string): Habit {
  // A completed day records success against the goal that applied on that day.
  // Editing today's definition must not rewrite historical completion or streaks.
  const updated = { ...habit, ...fields };
  const oldDays = habit.weekdays ?? allWeekdays;
  const newDays = updated.weekdays ?? allWeekdays;
  const scheduleChanged =
    oldDays.length !== newDays.length ||
    oldDays.some((day) => !newDays.includes(day)) ||
    Boolean(habit.archived) !== Boolean(updated.archived);
  if (!scheduleChanged) return updated;
  const baseline = habit.periods?.length
    ? habit.periods
    : [{ from: habit.startDate, weekdays: oldDays, archived: Boolean(habit.archived) }];
  return {
    ...updated,
    periods: [
      ...baseline.filter((period) => period.from < today),
      {
        from: today,
        weekdays: [...newDays].sort((a, b) => a - b),
        archived: Boolean(updated.archived),
      },
    ],
  };
}

export function assertHabitVersion(habit: Habit, expectedUpdatedAt: string) {
  if (habit.updatedAt !== expectedUpdatedAt)
    throw conflict('Привычка изменилась. Обновите данные и повторите действие.');
}

export function assertHabitDay(habit: Habit, date: string, today: string) {
  if (date < habit.startDate || date > today)
    throw new AppError(
      400,
      'HABIT_DATE_INVALID',
      'Можно отметить только прошедший день с даты создания привычки.',
    );
  if (habit.archived)
    throw new AppError(400, 'HABIT_ARCHIVED', 'Архивную привычку нельзя отмечать.');
  if (!isHabitScheduled(habit, date))
    throw new AppError(400, 'HABIT_DAY_UNSCHEDULED', 'В этот день привычка не запланирована.');
}

export function assertHabitProgress(habit: Habit, count: number) {
  if (!Number.isInteger(count) || count < 0 || count > (habit.target ?? 1))
    throw new AppError(400, 'HABIT_PROGRESS_INVALID', 'Прогресс превышает цель привычки.');
}
