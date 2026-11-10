import { useCallback, useEffect, useMemo, useRef, useState, useSyncExternalStore } from 'react';
import type { Habit } from '../../../shared/types';
import { api, ApiError } from '../../lib/api';
import { useI18n } from '../../lib/i18n';
import { WorkoutConflictNotice, WorkoutsClient, type WorkoutsTransport } from './client';

const transport: WorkoutsTransport = {
  load: () => api.workouts(),
  put: (kind, id, data, expected) => api.putWorkout(kind, id, data, expected),
  remove: (kind, id, expected) => api.deleteWorkout(kind, id, expected),
};

/** Loads the workout documents when the page becomes active and runs writes through the 409-safe client. */
export function useWorkouts(active: boolean, onProblem: (message: string) => void) {
  const { t } = useI18n();
  const client = useMemo(() => new WorkoutsClient(transport), []);
  const state = useSyncExternalStore(client.subscribe, () => client.state);
  const [loading, setLoading] = useState(!client.loaded);
  const [error, setError] = useState('');
  const [habits, setHabits] = useState<Habit[]>([]);
  const problem = useRef(onProblem);
  problem.current = onProblem;

  const refresh = useCallback(async () => {
    try {
      const [, list] = await Promise.all([client.load(), api.habits()]);
      setHabits(list.habits);
      setError('');
    } catch (failure) {
      setError(
        failure instanceof ApiError ? failure.message : t('Не удалось загрузить тренировки.'),
      );
    } finally {
      setLoading(false);
    }
  }, [client, t]);

  useEffect(() => {
    if (active) void refresh();
  }, [active, refresh]);

  /** Runs a write; on a version conflict the data was reloaded and the owner is told to repeat the action. */
  const write = useCallback(
    async <T>(job: () => Promise<T>): Promise<T | undefined> => {
      try {
        return await job();
      } catch (failure) {
        if (failure instanceof WorkoutConflictNotice)
          problem.current(
            t('Тренировки изменились на другом устройстве. Данные обновлены, повторите действие.'),
          );
        else if (failure instanceof ApiError) problem.current(failure.message);
        else problem.current(t('Не удалось сохранить тренировки.'));
        return undefined;
      }
    },
    [t],
  );
  return { client, state, loading, error, habits, setHabits, refresh, write };
}
