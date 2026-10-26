import { useCallback, useEffect, useMemo, useState, type FormEvent } from 'react';
import {
  Check,
  ChevronLeft,
  ChevronRight,
  Flame,
  LoaderCircle,
  Pencil,
  Plus,
  Trash2,
} from 'lucide-react';
import type { Habit } from '../../shared/types';
import { Dialog } from '../components/Dialog';
import { api } from '../lib/api';
import { dateInZone, formatDate } from '../lib/date';
import { useI18n } from '../lib/i18n';
import { addDays } from './calendar-utils';
import { habitStreak, habitWeek } from './habit-utils';
import '../styles/habits.css';

export function HabitsPage({ active, timeZone }: { active: boolean; timeZone: string }) {
  const { t, language } = useI18n();
  const today = dateInZone(timeZone);
  const [habits, setHabits] = useState<Habit[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [name, setName] = useState('');
  const [editing, setEditing] = useState<Habit | null>(null);
  const [deleting, setDeleting] = useState<Habit | null>(null);
  const [draft, setDraft] = useState('');
  const [busyId, setBusyId] = useState<string | null>(null);
  const [weekOffset, setWeekOffset] = useState(0);
  const endDate = addDays(today, weekOffset * 7);
  const days = useMemo(() => habitWeek(endDate), [endDate]);
  const todayDone = habits.filter((habit) => habit.completedDates.includes(today)).length;

  const refresh = useCallback(async () => {
    try {
      const result = await api.habits();
      setHabits(result.habits);
      setError('');
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : t('Не удалось загрузить привычки.'));
    } finally {
      setLoading(false);
    }
  }, [t]);
  useEffect(() => {
    if (!active) return;
    void refresh();
    const onFocus = () => void refresh();
    window.addEventListener('focus', onFocus);
    return () => window.removeEventListener('focus', onFocus);
  }, [active, refresh]);

  function replaceHabit(habit: Habit) {
    setHabits((current) => current.map((item) => (item.id === habit.id ? habit : item)));
  }
  async function create(event: FormEvent) {
    event.preventDefault();
    if (!name.trim() || busyId) return;
    setBusyId('create');
    setError('');
    try {
      const result = await api.createHabit({ title: name.trim() });
      setHabits((current) => [...current, result.habit]);
      setName('');
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : t('Не удалось сохранить привычку.'));
    } finally {
      setBusyId(null);
    }
  }
  async function toggle(habit: Habit, date: string) {
    if (busyId) return;
    const completed = !habit.completedDates.includes(date);
    setBusyId(habit.id);
    setError('');
    replaceHabit({
      ...habit,
      completedDates: completed
        ? [...habit.completedDates, date].sort()
        : habit.completedDates.filter((day) => day !== date),
    });
    try {
      replaceHabit((await api.setHabitDay(habit.id, date, completed, habit.updatedAt)).habit);
    } catch (failure) {
      replaceHabit(habit);
      setError(failure instanceof Error ? failure.message : t('Не удалось изменить отметку.'));
      void refresh();
    } finally {
      setBusyId(null);
    }
  }
  async function saveEdit(event: FormEvent) {
    event.preventDefault();
    if (!editing || !draft.trim() || busyId) return;
    setBusyId(editing.id);
    try {
      replaceHabit(
        (await api.updateHabit(editing.id, { title: draft.trim() }, editing.updatedAt)).habit,
      );
      setEditing(null);
      setError('');
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : t('Не удалось сохранить привычку.'));
      void refresh();
    } finally {
      setBusyId(null);
    }
  }
  async function remove() {
    if (!deleting || busyId) return;
    setBusyId(deleting.id);
    try {
      await api.deleteHabit(deleting.id, deleting.updatedAt);
      setHabits((current) => current.filter((habit) => habit.id !== deleting.id));
      setDeleting(null);
      setError('');
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : t('Не удалось удалить привычку.'));
      void refresh();
    } finally {
      setBusyId(null);
    }
  }

  return (
    <section className="habits-page" aria-labelledby="habits-title">
      <header className="page-heading">
        <div>
          <p className="page-eyebrow">RITM · {t('Ежедневные привычки')}</p>
          <h1 id="habits-title" className="gradient-title">
            {t('Привычки')}
          </h1>
          <p className="page-description">
            {t('Отмечайте день одним нажатием. История сохраняется на всех ваших устройствах.')}
          </p>
        </div>
      </header>
      <div className="habits-summary panel">
        <div>
          <span className="card-eyebrow">{t('Сегодня выполнено')}</span>
          <strong>
            {todayDone} <span>/ {habits.length}</span>
          </strong>
        </div>
        <span className="habits-summary-date">
          {formatDate(today, { weekday: 'long', day: 'numeric', month: 'long' }, language)}
        </span>
      </div>
      <form className="habits-add panel" onSubmit={(event) => void create(event)}>
        <label className="field" htmlFor="habit-title">
          {t('Новая привычка')}
        </label>
        <div className="habits-add-row">
          <input
            id="habit-title"
            value={name}
            onChange={(event) => setName(event.target.value)}
            maxLength={80}
            placeholder={t('Например, читать 20 минут')}
            required
          />
          <button
            className="button button-primary"
            type="submit"
            disabled={Boolean(busyId) || !name.trim()}
          >
            {busyId === 'create' ? <LoaderCircle className="spin" size={17} /> : <Plus size={17} />}
            <span>{t('Добавить привычку')}</span>
          </button>
        </div>
      </form>
      {error && (
        <div className="habits-error" role="alert">
          {error}{' '}
          <button className="text-button" type="button" onClick={() => void refresh()}>
            {t('Повторить')}
          </button>
        </div>
      )}
      <div className="habits-week-heading">
        <div>
          <h2>
            {formatDate(days[0], { day: 'numeric', month: 'short' }, language)} –{' '}
            {formatDate(days[6], { day: 'numeric', month: 'short' }, language)}
          </h2>
          <span>
            {t('Серия')} · {t('Сегодня')}
          </span>
        </div>
        <div className="button-row">
          <button
            className="icon-button"
            type="button"
            onClick={() => setWeekOffset((value) => value - 1)}
            aria-label={t('Предыдущие 7 дней')}
          >
            <ChevronLeft size={18} />
          </button>
          <button
            className="icon-button"
            type="button"
            onClick={() => setWeekOffset((value) => Math.min(0, value + 1))}
            disabled={weekOffset === 0}
            aria-label={t('Следующие 7 дней')}
          >
            <ChevronRight size={18} />
          </button>
        </div>
      </div>
      {loading ? (
        <div className="habits-empty panel" role="status">
          <LoaderCircle className="spin" size={22} /> {t('Загружаем…')}
        </div>
      ) : habits.length === 0 ? (
        <div className="habits-empty panel">
          <h2>{t('Пока нет привычек')}</h2>
          <p>{t('Добавьте первую привычку, которую хотите повторять каждый день.')}</p>
        </div>
      ) : (
        <div className="habits-list">
          {habits.map((habit) => {
            const dates = new Set(habit.completedDates);
            const streak = habitStreak(habit, today);
            return (
              <article className="habit-card panel" key={habit.id}>
                <div className="habit-card-head">
                  <div>
                    <h2>{habit.title}</h2>
                    <span className="habit-streak">
                      <Flame size={15} /> {t('Серия')}: {t('{count} дн.', { count: streak })}
                    </span>
                  </div>
                  <div className="button-row">
                    <button
                      className="icon-button"
                      type="button"
                      aria-label={t('Редактировать привычку {title}', { title: habit.title })}
                      onClick={() => {
                        setEditing(habit);
                        setDraft(habit.title);
                      }}
                    >
                      <Pencil size={16} />
                    </button>
                    <button
                      className="icon-button"
                      type="button"
                      aria-label={t('Удалить привычку {title}', { title: habit.title })}
                      onClick={() => setDeleting(habit)}
                    >
                      <Trash2 size={16} />
                    </button>
                  </div>
                </div>
                <div className="habit-days" role="group" aria-label={habit.title}>
                  {days.map((day) => {
                    const done = dates.has(day);
                    const available = day >= habit.startDate && day <= today;
                    const label = formatDate(day, { weekday: 'short' }, language);
                    return (
                      <button
                        key={day}
                        type="button"
                        className={`habit-day ${done ? 'is-done' : ''} ${day === today ? 'is-today' : ''}`}
                        disabled={!available || Boolean(busyId)}
                        aria-pressed={done}
                        aria-label={t(
                          done ? 'Снять отметку {title} за {date}' : 'Отметить {title} за {date}',
                          {
                            title: habit.title,
                            date: formatDate(day, { day: 'numeric', month: 'long' }, language),
                          },
                        )}
                        onClick={() => void toggle(habit, day)}
                      >
                        <span>{label}</span>
                        <strong>{Number(day.slice(-2))}</strong>
                        <span className="habit-day-mark">
                          {done ? <Check size={15} strokeWidth={3} /> : null}
                        </span>
                      </button>
                    );
                  })}
                </div>
              </article>
            );
          })}
        </div>
      )}
      {editing && (
        <Dialog
          title={t('Изменить привычку')}
          onClose={() => setEditing(null)}
          busy={Boolean(busyId)}
        >
          <form onSubmit={(event) => void saveEdit(event)}>
            <label className="field" htmlFor="habit-edit-title">
              {t('Название привычки')}
              <input
                id="habit-edit-title"
                value={draft}
                maxLength={80}
                required
                onChange={(event) => setDraft(event.target.value)}
              />
            </label>
            <div className="button-row habits-dialog-actions">
              <button
                type="button"
                className="button button-secondary"
                onClick={() => setEditing(null)}
              >
                {t('Отмена')}
              </button>
              <button
                type="submit"
                className="button button-primary"
                disabled={!draft.trim() || Boolean(busyId)}
              >
                {t('Сохранить')}
              </button>
            </div>
          </form>
        </Dialog>
      )}
      {deleting && (
        <Dialog
          title={t('Удалить привычку?')}
          onClose={() => setDeleting(null)}
          busy={Boolean(busyId)}
        >
          <p className="page-description">{t('История отметок этой привычки будет удалена.')}</p>
          <div className="button-row habits-dialog-actions">
            <button
              type="button"
              className="button button-secondary"
              onClick={() => setDeleting(null)}
            >
              {t('Отмена')}
            </button>
            <button
              type="button"
              className="button button-danger"
              onClick={() => void remove()}
              disabled={Boolean(busyId)}
            >
              {t('Удалить привычку')}
            </button>
          </div>
        </Dialog>
      )}
    </section>
  );
}
