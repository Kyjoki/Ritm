import type { Habit } from './types.ts';

const allWeekdays = [0, 1, 2, 3, 4, 5, 6];

/** Calendar dates are already in the owner's time zone; Sunday is day zero. */
export function habitWeekday(date: string): number {
  return new Date(`${date}T12:00:00Z`).getUTCDay();
}

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
  return Boolean(period && !period.archived && period.weekdays.includes(habitWeekday(date)));
}
