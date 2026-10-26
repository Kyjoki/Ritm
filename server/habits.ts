import type { Habit } from '../shared/types.ts';
import { AppError, conflict } from './errors.ts';

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
}
