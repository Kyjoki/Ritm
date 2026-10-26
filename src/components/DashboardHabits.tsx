import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  Activity,
  ArrowUpRight,
  BookOpen,
  Check,
  ChevronLeft,
  ChevronRight,
  Droplet,
  Moon,
  Sparkles,
  Target,
} from 'lucide-react';
import type { Habit } from '../../shared/types';
import {
  habitCanMarkOn,
  habitCompleteOn,
  habitProgress,
  habitScheduledOn,
  habitStreak,
  habitTarget,
  habitWeek,
} from '../features/habit-utils';
import { api } from '../lib/api';
import { formatDate } from '../lib/date';
import { useI18n } from '../lib/i18n';
import { addDays } from '../features/calendar-utils';
import '../styles/dashboard-habits.css';

const icons = {
  sparkles: Sparkles,
  book: BookOpen,
  activity: Activity,
  droplet: Droplet,
  moon: Moon,
  target: Target,
};

export function DashboardHabits({ today, onOpen }: { today: string; onOpen: () => void }) {
  const { t, language } = useI18n();
  const [habits, setHabits] = useState<Habit[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [busyId, setBusyId] = useState<string | null>(null);
  const [weekOffset, setWeekOffset] = useState(0);
  const inFlight = useRef(new Set<string>());
  const days = useMemo(() => habitWeek(addDays(today, weekOffset * 7)), [today, weekOffset]);
  const activeHabits = habits.filter((habit) => !habit.archived);
  const todayDone = activeHabits.filter((habit) => habitCompleteOn(habit, today)).length;
  const todayPlanned = activeHabits.filter((habit) => habitScheduledOn(habit, today)).length;

  const refresh = useCallback(async () => {
    try {
      const response = await api.habits();
      setHabits(response.habits);
      setError('');
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : t('Не удалось загрузить привычки.'));
    } finally {
      setLoading(false);
    }
  }, [t]);

  useEffect(() => {
    void refresh();
    const onChange = () => void refresh();
    window.addEventListener('focus', onChange);
    window.addEventListener('ritm:habits-changed', onChange);
    return () => {
      window.removeEventListener('focus', onChange);
      window.removeEventListener('ritm:habits-changed', onChange);
    };
  }, [refresh]);

  async function toggle(habit: Habit, date: string) {
    if (inFlight.current.has(habit.id)) return;
    const done = habitCompleteOn(habit, date);
    const count = done ? 0 : habitTarget(habit);
    inFlight.current.add(habit.id);
    setBusyId(habit.id);
    setError('');
    if (date >= habit.startDate)
      setHabits((current) =>
        current.map((item) =>
          item.id === habit.id
            ? {
                ...item,
                progressByDate: { ...item.progressByDate, [date]: count },
                completedDates: count
                  ? [...new Set([...item.completedDates, date])].sort()
                  : item.completedDates.filter((value) => value !== date),
              }
            : item,
        ),
      );
    try {
      const response = await api.setHabitProgress(habit.id, date, count, habit.updatedAt);
      setHabits((current) => current.map((item) => (item.id === habit.id ? response.habit : item)));
      window.dispatchEvent(new Event('ritm:habits-changed'));
    } catch (failure) {
      setHabits((current) => current.map((item) => (item.id === habit.id ? habit : item)));
      setError(failure instanceof Error ? failure.message : t('Не удалось изменить отметку.'));
      void refresh();
    } finally {
      inFlight.current.delete(habit.id);
      setBusyId(null);
    }
  }

  return (
    <section className="panel dashboard-habits" aria-labelledby="dashboard-habits-title">
      <div className="dashboard-habits-head">
        <div>
          <p className="card-eyebrow">{t('Привычки на неделю')}</p>
          <h2 id="dashboard-habits-title">
            {t('Привычки')}{' '}
            <span>
              {todayDone}/{todayPlanned} {t('За сегодня').toLocaleLowerCase(language)}
            </span>
          </h2>
        </div>
        <div className="dashboard-habits-actions">
          <span className="dashboard-habits-period">
            {formatDate(days[0], { day: 'numeric', month: 'short' }, language)} –{' '}
            {formatDate(days[6], { day: 'numeric', month: 'short' }, language)}
          </span>
          <button
            className="icon-button"
            type="button"
            onClick={() => setWeekOffset((value) => value - 1)}
            aria-label={t('Предыдущая неделя')}
          >
            <ChevronLeft size={18} />
          </button>
          <button
            className="icon-button"
            type="button"
            onClick={() => setWeekOffset((value) => Math.min(0, value + 1))}
            disabled={weekOffset === 0}
            aria-label={t('Следующая неделя')}
          >
            <ChevronRight size={18} />
          </button>
          <button className="text-button dashboard-habits-all" type="button" onClick={onOpen}>
            {t('Все привычки')} <ArrowUpRight size={14} />
          </button>
        </div>
      </div>
      {error ? (
        <p className="error-note" role="alert">
          {error}{' '}
          <button className="text-button" type="button" onClick={() => void refresh()}>
            {t('Повторить')}
          </button>
        </p>
      ) : null}
      {loading ? (
        <p className="dashboard-habits-empty" role="status">
          {t('Загружаем…')}
        </p>
      ) : activeHabits.length === 0 ? (
        <div className="dashboard-habits-empty">
          <p>{t('Привычек пока нет — добавьте первую.')}</p>
          <button className="button button-secondary" type="button" onClick={onOpen}>
            {t('Добавить привычку')} <ArrowUpRight size={15} />
          </button>
        </div>
      ) : (
        <div className="dashboard-habits-scroll" tabIndex={0} aria-label={t('Привычки на неделю')}>
          <div className="dashboard-habits-matrix">
            <div className="dashboard-habits-name dashboard-habits-label">{t('Привычки')}</div>
            {days.map((date) => (
              <div
                key={date}
                className={`dashboard-habits-date${date === today ? ' is-today' : ''}`}
              >
                <span>{formatDate(date, { weekday: 'short' }, language)}</span>
                <strong>{Number(date.slice(-2))}</strong>
              </div>
            ))}
            {activeHabits.map((habit) => {
              const Icon = icons[habit.icon ?? 'sparkles'];
              const streak = habitStreak(habit, today);
              return (
                <div className="dashboard-habits-row" key={habit.id}>
                  <div className="dashboard-habits-name">
                    <span className="dashboard-habits-icon">
                      <Icon size={17} />
                    </span>
                    <span className="dashboard-habits-copy">
                      <strong title={habit.title}>{habit.title}</strong>
                      <small>
                        {t('Серия')}: {streak}
                        {habit.target
                          ? ` · ${t('Прогресс {count} из {target} {unit}', { count: habitProgress(habit, today), target: habit.target, unit: habit.unit ?? '' })}`
                          : ''}
                      </small>
                    </span>
                  </div>
                  {days.map((date) => {
                    const scheduled = habitScheduledOn(habit, date);
                    const done = habitCompleteOn(habit, date);
                    const future = date > today;
                    const available = habitCanMarkOn(habit, date, today);
                    const labelDate = formatDate(date, { day: 'numeric', month: 'long' }, language);
                    const state = done
                      ? t('Выполнено')
                      : future
                        ? t('Будущий день')
                        : date < habit.startDate && !available
                          ? t('До начала привычки')
                          : available
                            ? t('Запланировано')
                            : t('Не запланировано');
                    const actionLabel = t(
                      done
                        ? 'Снять выполнение {title} за {date}'
                        : 'Отметить выполнение {title} за {date}',
                      { title: habit.title, date: labelDate },
                    );
                    return (
                      <button
                        key={date}
                        type="button"
                        className={`dashboard-habits-cell${date === today ? ' is-today' : ''}${done ? ' is-done' : ''}${!scheduled && !available ? ' is-off' : ''}${future ? ' is-future' : ''}`}
                        aria-label={
                          available
                            ? `${actionLabel}. ${state}`
                            : `${habit.title}: ${labelDate}. ${state}`
                        }
                        title={`${labelDate} · ${state}`}
                        aria-pressed={available ? done : undefined}
                        disabled={!available || busyId === habit.id}
                        onClick={() => void toggle(habit, date)}
                      >
                        <span className="dashboard-habits-mark">
                          {done ? <Check size={15} strokeWidth={3} /> : null}
                        </span>
                      </button>
                    );
                  })}
                </div>
              );
            })}
          </div>
        </div>
      )}
    </section>
  );
}
