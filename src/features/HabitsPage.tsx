import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import {
  Activity,
  Archive,
  BookOpen,
  Check,
  ChevronLeft,
  ChevronRight,
  Droplets,
  Flame,
  LoaderCircle,
  Minus,
  Moon,
  Pencil,
  Plus,
  RotateCcw,
  Sparkles,
  Target,
  Trash2,
} from 'lucide-react';
import type { Habit, HabitInput } from '../../shared/types';
import { MotionArc, MotionBar, MotionList, MotionNumber } from '../components/Motion';
import { Dialog } from '../components/Dialog';
import { api } from '../lib/api';
import { dateInZone, formatDate } from '../lib/date';
import { useI18n } from '../lib/i18n';
import { addDays } from './calendar-utils';
import {
  HABIT_MILESTONES,
  habitAnalyticsScope,
  habitBestStreak,
  habitCanMarkOn,
  habitCompleteOn,
  habitCompletionRate,
  habitDaySummary,
  habitPeriodSummary,
  habitProgress,
  habitScheduledOn,
  habitStreak,
  habitTarget,
  habitWeek,
  habitWeekday,
} from './habit-utils';
import '../styles/habits.css';

const iconChoices = {
  sparkles: Sparkles,
  book: BookOpen,
  activity: Activity,
  droplet: Droplets,
  moon: Moon,
  target: Target,
} as const;
type HabitIcon = keyof typeof iconChoices;
const iconLabels: Record<HabitIcon, string> = {
  sparkles: 'Искры',
  book: 'Книга',
  activity: 'Движение',
  droplet: 'Вода',
  moon: 'Сон',
  target: 'Цель',
};
const weekdays = [0, 1, 2, 3, 4, 5, 6];
const defaultDraft: HabitInput = {
  title: '',
  icon: 'sparkles',
  weekdays,
  target: null,
  unit: '',
  archived: false,
};

function emitHabitsChanged() {
  window.dispatchEvent(
    new CustomEvent('ritm:habits-changed', { detail: { source: 'habits-page' } }),
  );
}

function periodDates(today: string, period: 'week' | 'month', offset: number) {
  if (period === 'week') return habitWeek(addDays(today, offset * 7));
  const [year, month] = today.split('-').map(Number);
  const first = new Date(Date.UTC(year, month - 1 + offset, 1));
  const last = new Date(Date.UTC(year, month + offset, 0));
  const start = first.toISOString().slice(0, 10);
  const end = last.toISOString().slice(0, 10);
  const result: string[] = [];
  for (let day = start; day <= end; day = addDays(day, 1)) result.push(day);
  return result;
}

function HabitIconView({ icon, size = 20 }: { icon?: HabitIcon; size?: number }) {
  const Icon = iconChoices[icon ?? 'sparkles'] ?? Sparkles;
  return <Icon size={size} aria-hidden="true" />;
}

function HabitForm({
  initial,
  busy,
  onSubmit,
  onCancel,
}: {
  initial: HabitInput;
  busy: boolean;
  onSubmit: (input: HabitInput) => void;
  onCancel: () => void;
}) {
  const { t, language } = useI18n();
  const [draft, setDraft] = useState<HabitInput>({
    title: initial.title,
    icon: initial.icon ?? 'sparkles',
    weekdays: initial.weekdays ?? weekdays,
    target: initial.target ?? null,
    unit: initial.unit ?? '',
    archived: initial.archived ?? false,
  });
  function submit(event: FormEvent) {
    event.preventDefault();
    if (!draft.title.trim() || !draft.weekdays?.length) return;
    onSubmit({
      ...draft,
      title: draft.title.trim(),
      unit: draft.target ? (draft.unit?.trim() ?? '') : '',
      target: draft.target || null,
    });
  }
  return (
    <form className="habit-form" onSubmit={submit}>
      <label className="field" htmlFor="habit-form-title">
        {t('Название привычки')}
        <input
          id="habit-form-title"
          value={draft.title}
          onChange={(event) => setDraft({ ...draft, title: event.target.value })}
          maxLength={80}
          placeholder={t('Например, читать 20 минут')}
          required
          autoFocus
        />
      </label>
      <fieldset className="habit-form-fieldset">
        <legend>{t('Иконка')}</legend>
        <div className="habit-form-icons">
          {(Object.keys(iconChoices) as HabitIcon[]).map((icon) => (
            <button
              className={
                draft.icon === icon ? 'habit-icon-choice is-selected' : 'habit-icon-choice'
              }
              type="button"
              key={icon}
              aria-label={t('Иконка: {icon}', { icon: t(iconLabels[icon]) })}
              aria-pressed={draft.icon === icon}
              onClick={() => setDraft({ ...draft, icon })}
            >
              <HabitIconView icon={icon} />
            </button>
          ))}
        </div>
      </fieldset>
      <fieldset className="habit-form-fieldset">
        <legend>{t('Дни недели')}</legend>
        <div className="habit-form-weekdays">
          {weekdays.map((day) => {
            const label = new Intl.DateTimeFormat(language === 'en' ? 'en-US' : 'ru-RU', {
              weekday: 'short',
              timeZone: 'UTC',
            }).format(new Date(Date.UTC(2026, 9, 25 + day)));
            const selected = draft.weekdays?.includes(day) ?? true;
            return (
              <button
                key={day}
                type="button"
                className={selected ? 'habit-weekday-choice is-selected' : 'habit-weekday-choice'}
                aria-pressed={selected}
                aria-label={t('{day}: {state}', {
                  day: label,
                  state: selected ? t('Запланировано') : t('Не запланировано'),
                })}
                onClick={() => {
                  const next = selected
                    ? (draft.weekdays ?? weekdays).filter((value) => value !== day)
                    : [...(draft.weekdays ?? weekdays), day].sort();
                  setDraft({ ...draft, weekdays: next });
                }}
              >
                {label}
              </button>
            );
          })}
        </div>
        {!draft.weekdays?.length && (
          <p className="habit-form-hint">{t('Выберите хотя бы один день.')}</p>
        )}
      </fieldset>
      <div className="habit-form-goal">
        <label className="field" htmlFor="habit-form-target">
          {t('Цель за день')}
          <input
            id="habit-form-target"
            type="number"
            min={1}
            max={10000}
            step={1}
            value={draft.target ?? ''}
            onChange={(event) =>
              setDraft({ ...draft, target: event.target.value ? Number(event.target.value) : null })
            }
            placeholder={t('Просто выполнить')}
          />
        </label>
        <label className="field" htmlFor="habit-form-unit">
          {t('Единица')}
          <input
            id="habit-form-unit"
            value={draft.unit ?? ''}
            onChange={(event) => setDraft({ ...draft, unit: event.target.value })}
            maxLength={24}
            disabled={!draft.target}
            placeholder={t('Например, страниц')}
          />
        </label>
      </div>
      <div className="button-row habits-dialog-actions">
        <button type="button" className="button button-secondary" onClick={onCancel}>
          {t('Отмена')}
        </button>
        <button
          type="submit"
          className="button button-primary"
          disabled={busy || !draft.title.trim() || !draft.weekdays?.length}
        >
          {busy ? <LoaderCircle className="spin" size={16} /> : <Check size={16} />}
          {t('Сохранить')}
        </button>
      </div>
    </form>
  );
}

function HabitProgressEditor({
  habit,
  today,
  busy,
  onSave,
}: {
  habit: Habit;
  today: string;
  busy: boolean;
  onSave: (count: number) => void;
}) {
  const { t } = useI18n();
  const progress = habitProgress(habit, today);
  const target = habitTarget(habit);
  const [draft, setDraft] = useState(String(progress));
  useEffect(() => setDraft(String(progress)), [progress]);
  const value = draft.trim() === '' ? Number.NaN : Number(draft);
  const valid = Number.isInteger(value) && value >= 0 && value <= target;
  return (
    <form
      className="habit-progress-controls"
      onSubmit={(event) => {
        event.preventDefault();
        if (valid && value !== progress) onSave(value);
      }}
    >
      <div
        className="habit-stepper"
        role="group"
        aria-label={t('Прогресс {title}', { title: habit.title })}
      >
        <button
          type="button"
          aria-label={t('Уменьшить прогресс {title}', { title: habit.title })}
          disabled={busy || !valid || value <= 0}
          onClick={() => onSave(value - 1)}
        >
          <Minus size={17} />
        </button>
        <input
          type="number"
          min={0}
          max={target}
          step={1}
          value={draft}
          onChange={(event) => setDraft(event.target.value)}
          aria-label={t('Введите прогресс {title}', { title: habit.title })}
        />
        <button
          type="button"
          aria-label={t('Увеличить прогресс {title}', { title: habit.title })}
          disabled={busy || !valid || value >= target}
          onClick={() => onSave(value + 1)}
        >
          <Plus size={17} />
        </button>
      </div>
      {valid && value !== progress && (
        <button className="button button-primary" type="submit" disabled={busy}>
          {t('Сохранить')}
        </button>
      )}
      <button
        className={
          'button ' + (habitCompleteOn(habit, today) ? 'button-secondary' : 'button-primary')
        }
        type="button"
        disabled={busy}
        onClick={() => onSave(habitCompleteOn(habit, today) ? 0 : target)}
      >
        <Check size={15} />
        {t(habitCompleteOn(habit, today) ? 'Отменить' : 'Выполнить цель')}
      </button>
      {progress > 0 && (
        <button
          className="icon-button"
          type="button"
          disabled={busy}
          aria-label={t('Сбросить прогресс {title}', { title: habit.title })}
          onClick={() => onSave(0)}
        >
          <RotateCcw size={16} />
        </button>
      )}
    </form>
  );
}

export function HabitsPage({ active, timeZone }: { active: boolean; timeZone: string }) {
  const { t, language } = useI18n();
  const today = dateInZone(timeZone);
  const [habits, setHabits] = useState<Habit[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [busyId, setBusyId] = useState<string | null>(null);
  const [editing, setEditing] = useState<Habit | 'create' | null>(null);
  const [deleting, setDeleting] = useState<Habit | null>(null);
  const [showArchived, setShowArchived] = useState(false);
  const [period, setPeriod] = useState<'week' | 'month'>('week');
  const [offset, setOffset] = useState(0);
  const [selectedDay, setSelectedDay] = useState<string | null>(null);
  const [intro, setIntro] = useState(false);
  const [introduced, setIntroduced] = useState(false);
  const [celebration, setCelebration] = useState<{ title: string; milestone: number } | null>(null);
  const [recordId, setRecordId] = useState<string | null>(null);
  const activeHabits = habitAnalyticsScope(habits, false);
  const archivedHabits = habitAnalyticsScope(habits, true);
  const visibleHabits = showArchived ? archivedHabits : activeHabits;
  const dates = useMemo(() => periodDates(today, period, offset), [today, period, offset]);
  const availableDates = dates.filter((date) => date <= today);
  const previousDates = periodDates(addDays(dates[0], -1), period, 0);
  const weekDays = habitWeek(addDays(today, offset * 7));
  const selected = selectedDay && dates.includes(selectedDay) ? selectedDay : null;

  const refresh = useCallback(
    async (preserveError = false) => {
      try {
        const result = await api.habits();
        setHabits(result.habits);
        if (!preserveError) setError('');
      } catch (failure) {
        setError(failure instanceof Error ? failure.message : t('Не удалось загрузить привычки.'));
      } finally {
        setLoading(false);
      }
    },
    [t],
  );
  useEffect(() => {
    if (!active) return;
    void refresh();
    const onFocus = () => void refresh();
    const onChange = (event: Event) => {
      if ((event as CustomEvent<{ source?: string }>).detail?.source !== 'habits-page')
        void refresh();
    };
    window.addEventListener('focus', onFocus);
    window.addEventListener('ritm:habits-changed', onChange);
    return () => {
      window.removeEventListener('focus', onFocus);
      window.removeEventListener('ritm:habits-changed', onChange);
    };
  }, [active, refresh]);
  useEffect(() => {
    if (!active || loading || introduced) return;
    setIntro(true);
    setIntroduced(true);
    const timer = window.setTimeout(() => setIntro(false), 1000);
    return () => window.clearTimeout(timer);
  }, [active, loading, introduced]);
  useEffect(() => {
    if (!celebration) return;
    const timer = window.setTimeout(() => setCelebration(null), 2600);
    return () => window.clearTimeout(timer);
  }, [celebration]);
  useEffect(() => {
    if (!recordId) return;
    const timer = window.setTimeout(() => setRecordId(null), 1050);
    return () => window.clearTimeout(timer);
  }, [recordId]);
  function replaceHabit(habit: Habit) {
    setHabits((current) => current.map((item) => (item.id === habit.id ? habit : item)));
  }
  async function save(input: HabitInput) {
    const old = editing === 'create' ? null : editing;
    if (!editing || busyId) return;
    setBusyId(old?.id ?? 'create');
    setError('');
    try {
      if (old) replaceHabit((await api.updateHabit(old.id, input, old.updatedAt)).habit);
      else {
        const created = (await api.createHabit(input)).habit;
        setHabits((current) => [...current, created]);
      }
      setEditing(null);
      emitHabitsChanged();
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : t('Не удалось сохранить привычку.'));
      void refresh(true);
    } finally {
      setBusyId(null);
    }
  }
  async function updateArchive(habit: Habit, archived: boolean) {
    if (busyId) return;
    setBusyId(habit.id);
    try {
      replaceHabit(
        (
          await api.updateHabit(
            habit.id,
            {
              title: habit.title,
              icon: habit.icon ?? 'sparkles',
              weekdays: habit.weekdays ?? weekdays,
              target: habit.target ?? null,
              unit: habit.unit ?? '',
              archived,
            },
            habit.updatedAt,
          )
        ).habit,
      );
      emitHabitsChanged();
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : t('Не удалось сохранить привычку.'));
      void refresh(true);
    } finally {
      setBusyId(null);
    }
  }
  async function remove() {
    if (!deleting || busyId) return;
    setBusyId(deleting.id);
    try {
      await api.deleteHabit(deleting.id, deleting.updatedAt);
      setHabits((current) => current.filter((item) => item.id !== deleting.id));
      setDeleting(null);
      emitHabitsChanged();
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : t('Не удалось удалить привычку.'));
      void refresh(true);
    } finally {
      setBusyId(null);
    }
  }
  async function setProgress(habit: Habit, day: string, count: number) {
    if (busyId || !habitCanMarkOn(habit, day, today)) return;
    const target = habitTarget(habit);
    const nextCount = Math.max(0, Math.min(target, count));
    const wasComplete = habitCompleteOn(habit, day);
    const nextDates = habit.completedDates.filter((value) => value !== day);
    if (nextCount >= target) nextDates.push(day);
    const optimistic = {
      ...habit,
      completedDates: nextDates.sort(),
      progressByDate: { ...habit.progressByDate, [day]: nextCount },
    };
    setBusyId(habit.id);
    setError('');
    if (day >= habit.startDate) replaceHabit(optimistic);
    try {
      const result = habit.target
        ? await api.setHabitProgress(habit.id, day, nextCount, habit.updatedAt)
        : await api.setHabitDay(habit.id, day, nextCount > 0, habit.updatedAt);
      replaceHabit(result.habit);
      if (
        !wasComplete &&
        nextCount >= target &&
        habitBestStreak(result.habit, today) > habitBestStreak(habit, today)
      )
        setRecordId(habit.id);
      if (!wasComplete && nextCount >= target) {
        const newMilestone = HABIT_MILESTONES.find(
          (milestone) =>
            (result.habit.achievements ?? []).includes(milestone) &&
            !(habit.achievements ?? []).includes(milestone),
        );
        if (newMilestone) setCelebration({ title: habit.title, milestone: newMilestone });
      }
      emitHabitsChanged();
    } catch (failure) {
      replaceHabit(habit);
      setError(failure instanceof Error ? failure.message : t('Не удалось изменить отметку.'));
      void refresh(true);
    } finally {
      setBusyId(null);
    }
  }

  const totals = habitPeriodSummary(visibleHabits, dates, today);
  const rate = totals.progress ?? 0;
  const comparisonLength = Math.min(availableDates.length, previousDates.length);
  const comparisonCurrent = habitPeriodSummary(
    visibleHabits,
    availableDates.slice(0, comparisonLength),
    today,
  );
  const previous = habitPeriodSummary(
    visibleHabits,
    previousDates.slice(0, comparisonLength),
    today,
  );
  const previousRate =
    previous.progress !== null && comparisonCurrent.progress !== null ? previous.progress : null;
  const comparisonCurrentRate = comparisonCurrent.progress ?? 0;
  const todaySummary = habitDaySummary(visibleHabits, today, today);
  const currentStreak = Math.max(0, ...visibleHabits.map((habit) => habitStreak(habit, today)));
  const bestStreak = Math.max(0, ...visibleHabits.map((habit) => habitBestStreak(habit, today)));
  const daily = dates.map((day) => ({ day, ...habitDaySummary(visibleHabits, day, today) }));
  const describeDay = (entry: (typeof daily)[number], label: string) =>
    entry.day > today
      ? label + '. ' + t('Будущий день')
      : entry.planned
        ? t('{date}: {done} из {total}', {
            date: label,
            done: entry.completed,
            total: entry.planned,
          })
        : label + '. ' + t('Нет запланированных привычек');
  const stable = visibleHabits
    .map((habit) => ({
      habit,
      ...habitCompletionRate(
        habit,
        availableDates.filter((date) => date < today),
      ),
    }))
    .filter((value) => value.scheduled >= 3)
    .sort(
      (a, b) => b.completed / b.scheduled - a.completed / a.scheduled || b.completed - a.completed,
    )[0];
  const missed = weekdays
    .map((weekday) => {
      const entries = daily.filter(
        (entry) => entry.day < today && habitWeekday(entry.day) === weekday,
      );
      const scheduled = entries.reduce((sum, entry) => sum + entry.planned, 0);
      const completed = entries.reduce((sum, entry) => sum + entry.completed, 0);
      return { weekday, scheduled, completed };
    })
    .filter((entry) => entry.scheduled >= 2)
    .sort((a, b) => a.completed / a.scheduled - b.completed / b.scheduled)[0];
  const selectedEntry = daily.find((entry) => entry.day === selected);
  const periodLabel =
    period === 'week'
      ? formatDate(dates[0], { day: 'numeric', month: 'short' }, language) +
        ' – ' +
        formatDate(dates[6], { day: 'numeric', month: 'short' }, language)
      : formatDate(dates[0], { month: 'long', year: 'numeric' }, language);

  return (
    <section
      className={'habits-page' + (intro ? ' is-entering' : '')}
      aria-labelledby="habits-title"
    >
      <header className="page-heading habits-page-heading">
        <div>
          <p className="page-eyebrow">RITM · {t('Ежедневные привычки')}</p>
          <h1 id="habits-title" className="gradient-title">
            {t('Привычки')}
          </h1>
          <p className="page-description">
            {t('Маленькие действия складываются в устойчивый ритм.')}
          </p>
        </div>
        <button
          className="button button-primary"
          type="button"
          onClick={() => {
            setError('');
            setEditing('create');
          }}
        >
          <Plus size={17} /> {t('Новая привычка')}
        </button>
      </header>
      {error && (
        <div className="habits-error" role="alert">
          {error}{' '}
          <button className="text-button" type="button" onClick={() => void refresh()}>
            {t('Повторить')}
          </button>
        </div>
      )}
      {celebration && (
        <div className="habits-celebration" role="status">
          <Sparkles size={18} />
          {t('{title}: достижение {count} дней', {
            title: celebration.title,
            count: celebration.milestone,
          })}
        </div>
      )}
      {loading ? (
        <div className="habits-empty panel" role="status">
          <LoaderCircle className="spin" size={22} /> {t('Загружаем…')}
        </div>
      ) : (
        <>
          <section className="habits-analytics panel" aria-labelledby="habits-analytics-title">
            <div className="habits-section-heading">
              <div>
                <p className="card-eyebrow">
                  {t(showArchived ? 'История архивных привычек' : 'История активных привычек')}
                </p>
                <h2 id="habits-analytics-title">{t('Прогресс привычек')}</h2>
              </div>
              <div className="habits-period-controls">
                <div className="habits-segmented" role="group" aria-label={t('Период аналитики')}>
                  {(['week', 'month'] as const).map((value) => (
                    <button
                      key={value}
                      type="button"
                      className={period === value ? 'is-active' : ''}
                      aria-pressed={period === value}
                      onClick={() => {
                        setPeriod(value);
                        setOffset(0);
                        setSelectedDay(null);
                      }}
                    >
                      {t(value === 'week' ? 'Неделя' : 'Месяц')}
                    </button>
                  ))}
                </div>
                <button
                  className="icon-button"
                  type="button"
                  aria-label={t('Предыдущий период')}
                  onClick={() => {
                    setOffset(offset - 1);
                    setSelectedDay(null);
                  }}
                >
                  <ChevronLeft size={17} />
                </button>
                <button
                  className="icon-button"
                  type="button"
                  aria-label={t('Следующий период')}
                  disabled={offset === 0}
                  onClick={() => {
                    setOffset(offset + 1);
                    setSelectedDay(null);
                  }}
                >
                  <ChevronRight size={17} />
                </button>
              </div>
            </div>
            <p className="habits-period-label">{periodLabel}</p>
            <div className="habits-analytics-top">
              <div
                className="habits-gauge"
                aria-label={
                  totals.progress === null
                    ? t('Нет запланированных привычек')
                    : t('Выполнено {count} процентов', { count: rate })
                }
              >
                <svg viewBox="0 0 180 104" aria-hidden="true">
                  <path
                    d="M 12 92 A 78 78 0 0 1 168 92"
                    pathLength="100"
                    className="habits-gauge-track"
                  />
                  <MotionArc value={rate} />
                </svg>
                <div className="habits-gauge-value" aria-hidden="true">
                  <strong>
                    {totals.progress === null ? (
                      '—'
                    ) : (
                      <MotionNumber value={rate} format={(value) => `${Math.round(value)}%`} />
                    )}
                  </strong>
                  <span>
                    {t(
                      totals.progress === null
                        ? 'Нет запланированных привычек'
                        : 'выполнено за период',
                    )}
                  </span>
                </div>
              </div>
              <div className="habits-kpis">
                <div>
                  <span>{t('Сегодня выполнено')}</span>
                  {todaySummary.planned ? (
                    <strong aria-label={todaySummary.completed + ' / ' + todaySummary.planned}>
                      <MotionNumber value={todaySummary.completed} />
                      <small> / {todaySummary.planned}</small>
                    </strong>
                  ) : (
                    <strong className="habits-kpi-empty">
                      {t('Нет запланированных привычек')}
                    </strong>
                  )}
                </div>
                <div>
                  <span>{t('Текущая серия')}</span>
                  <strong aria-label={currentStreak + ' ' + t('дней')}>
                    <MotionNumber value={currentStreak} />
                    <small> {t('дн.')}</small>
                  </strong>
                </div>
                <div>
                  <span>{t('Лучшая серия')}</span>
                  <strong aria-label={bestStreak + ' ' + t('дней')}>
                    <MotionNumber value={bestStreak} />
                    <small> {t('дн.')}</small>
                  </strong>
                </div>
              </div>
            </div>
            {totals.planned ? (
              <>
                <div className="habits-analytics-graphs">
                  <div className="habits-chart-block">
                    <h3>{t('Выполнение по дням')}</h3>
                    <div className={'habits-bars' + (period === 'month' ? ' is-month' : '')}>
                      {daily.map((entry, index) => {
                        const percentage = entry.progress ?? 0;
                        const label = formatDate(
                          entry.day,
                          { weekday: 'short', day: 'numeric', month: 'short' },
                          language,
                        );
                        const description = describeDay(entry, label);
                        return (
                          <button
                            type="button"
                            className={
                              'habits-bar-button' + (entry.day === selected ? ' is-selected' : '')
                            }
                            key={index}
                            onClick={() => setSelectedDay(entry.day)}
                            aria-label={description}
                            title={description}
                          >
                            <span className="motion-chart-tooltip" aria-hidden="true">
                              {description}
                            </span>
                            <span className="habits-bar-track">
                              <MotionBar
                                className="habits-bar-fill"
                                value={percentage}
                                index={index}
                              />
                            </span>
                            <span className="habits-bar-label">
                              {formatDate(entry.day, { day: 'numeric' }, language)}
                            </span>
                          </button>
                        );
                      })}
                    </div>
                  </div>
                  <div className="habits-heatmap-block">
                    <h3>{t('Регулярность')}</h3>
                    <div
                      className="habits-heatmap"
                      role="group"
                      aria-label={t('Календарь выполнения')}
                    >
                      {Array.from({ length: habitWeekday(dates[0]) }, (_, index) => (
                        <span key={'pad-' + index} />
                      ))}
                      {daily.map((entry) => {
                        const ratio = entry.progress === null ? 0 : entry.progress / 100;
                        const level =
                          entry.day > today
                            ? 'future'
                            : !entry.planned
                              ? 'none'
                              : ratio === 1
                                ? 'full'
                                : ratio > 0
                                  ? 'some'
                                  : 'empty';
                        const label = formatDate(
                          entry.day,
                          { weekday: 'short', day: 'numeric', month: 'short' },
                          language,
                        );
                        const description = describeDay(entry, label);
                        return (
                          <button
                            type="button"
                            key={entry.day}
                            className={
                              'habits-heat-day is-' +
                              level +
                              (selected === entry.day ? ' is-selected' : '')
                            }
                            onClick={() => setSelectedDay(entry.day)}
                            aria-label={description}
                            title={description}
                          >
                            <span>{Number(entry.day.slice(-2))}</span>
                          </button>
                        );
                      })}
                    </div>
                    <div className="habits-heat-legend">
                      <span>{t('Меньше')}</span>
                      <i />
                      <i />
                      <i />
                      <span>{t('Больше')}</span>
                    </div>
                  </div>
                </div>
                {selectedEntry && (
                  <p className="habits-date-detail" role="status">
                    {describeDay(
                      selectedEntry,
                      formatDate(
                        selectedEntry.day,
                        { weekday: 'long', day: 'numeric', month: 'long' },
                        language,
                      ),
                    )}
                  </p>
                )}
                <div className="habits-insights">
                  {stable && (
                    <p>
                      <Sparkles size={15} />{' '}
                      {t('Самая стабильная: {title} ({percent}%)', {
                        title: stable.habit.title,
                        percent: Math.round((stable.completed / stable.scheduled) * 100),
                      })}
                    </p>
                  )}
                  {missed && missed.completed < missed.scheduled && (
                    <p>
                      <Target size={15} />{' '}
                      {t('Чаще пропускается: {day}', {
                        day: formatDate(
                          daily.find((entry) => habitWeekday(entry.day) === missed.weekday)?.day ??
                            today,
                          { weekday: 'long' },
                          language,
                        ),
                      })}
                    </p>
                  )}
                  {previousRate !== null && (
                    <p>
                      <Activity size={15} />{' '}
                      {t('К прошлому периоду: {sign}{count} п. п.', {
                        sign: comparisonCurrentRate - previousRate > 0 ? '+' : '',
                        count: comparisonCurrentRate - previousRate,
                      })}
                    </p>
                  )}
                  {!stable && !missed && previousRate === null && (
                    <p>{t('Истории пока мало для выводов. Продолжайте отмечать привычки.')}</p>
                  )}
                </div>
              </>
            ) : (
              <div className="habits-analytics-empty">
                <Sparkles size={24} />
                <p>{t('Нет запланированных привычек')}</p>
              </div>
            )}
          </section>
          <div className="habits-list-heading">
            <div>
              <p className="card-eyebrow">{t('Ваши действия')}</p>
              <h2>{t(showArchived ? 'Архив' : 'Мои привычки')}</h2>
            </div>
            <button
              className="button button-secondary"
              type="button"
              onClick={() => {
                setShowArchived(!showArchived);
                setSelectedDay(null);
              }}
            >
              {showArchived ? <RotateCcw size={16} /> : <Archive size={16} />}
              {t(showArchived ? 'К активным' : 'Архив')}
              {showArchived && archivedHabits.length ? ' (' + archivedHabits.length + ')' : ''}
            </button>
          </div>
          {visibleHabits.length === 0 ? (
            <div className="habits-empty panel">
              <h3>{t(showArchived ? 'Архив пуст' : 'Пока нет привычек')}</h3>
              <p>
                {t(
                  showArchived
                    ? 'Здесь появятся сохранённые привычки.'
                    : 'Добавьте первую привычку, которую хотите повторять каждый день.',
                )}
              </p>
            </div>
          ) : (
            <MotionList className="habits-list">
              {visibleHabits.map((habit) => {
                const streak = habitStreak(habit, today);
                const best = habitBestStreak(habit, today);
                const awards =
                  habit.achievements ?? HABIT_MILESTONES.filter((milestone) => best >= milestone);
                const nextMilestone = HABIT_MILESTONES.find(
                  (milestone) => !awards.includes(milestone),
                );
                const isScheduled = habitScheduledOn(habit, today);
                const progress = habitProgress(habit, today);
                return (
                  <article
                    className={'habit-card panel' + (recordId === habit.id ? ' is-record' : '')}
                    key={habit.id}
                    data-motion-key={habit.id}
                  >
                    <div className="habit-card-head">
                      <div className="habit-card-identity">
                        <span className="habit-card-icon">
                          <HabitIconView icon={habit.icon} />
                        </span>
                        <div>
                          <h3>{habit.title}</h3>
                          <span className="habit-card-schedule">
                            {habit.weekdays?.length === 7 || !habit.weekdays
                              ? t('Каждый день')
                              : habit.weekdays
                                  .map((day) =>
                                    formatDate(
                                      addDays('2026-10-25', day),
                                      { weekday: 'short' },
                                      language,
                                    ),
                                  )
                                  .join(' · ')}
                          </span>
                        </div>
                      </div>
                      <div className="habit-card-actions">
                        <button
                          className="icon-button"
                          type="button"
                          aria-label={t('Редактировать привычку {title}', { title: habit.title })}
                          onClick={() => {
                            setError('');
                            setEditing(habit);
                          }}
                        >
                          <Pencil size={16} />
                        </button>
                        <button
                          className="icon-button"
                          type="button"
                          aria-label={t(
                            habit.archived
                              ? 'Восстановить привычку {title}'
                              : 'Архивировать привычку {title}',
                            { title: habit.title },
                          )}
                          disabled={Boolean(busyId)}
                          onClick={() => void updateArchive(habit, !habit.archived)}
                        >
                          {habit.archived ? <RotateCcw size={16} /> : <Archive size={16} />}
                        </button>
                        {habit.archived && (
                          <button
                            className="icon-button"
                            type="button"
                            aria-label={t('Удалить привычку {title}', { title: habit.title })}
                            onClick={() => setDeleting(habit)}
                          >
                            <Trash2 size={16} />
                          </button>
                        )}
                      </div>
                    </div>
                    <div className="habit-card-meta">
                      <span>
                        <Flame size={15} /> {t('Серия')}:{' '}
                        <strong>
                          <MotionNumber value={streak} />
                        </strong>
                      </span>
                      <span>
                        {t('Рекорд')}:{' '}
                        <strong>
                          <MotionNumber value={best} />
                        </strong>
                      </span>
                      {nextMilestone && (
                        <span>
                          {t('Следующая цель')}: <strong>{nextMilestone}</strong>
                        </span>
                      )}
                    </div>
                    {!habit.archived && (
                      <>
                        <div className="habit-days-scroll">
                          <div className="habit-days" role="group" aria-label={habit.title}>
                            {weekDays.map((day) => {
                              const complete = habitCompleteOn(habit, day);
                              const scheduled = habitScheduledOn(habit, day);
                              const canMark = habitCanMarkOn(habit, day, today);
                              const status =
                                day < habit.startDate && !canMark
                                  ? 'before'
                                  : day > today
                                    ? 'future'
                                    : scheduled || canMark
                                      ? complete
                                        ? 'done'
                                        : 'pending'
                                      : 'rest';
                              const label = formatDate(
                                day,
                                { weekday: 'short', day: 'numeric', month: 'long' },
                                language,
                              );
                              return (
                                <button
                                  key={day}
                                  type="button"
                                  className={
                                    'habit-day is-' + status + (day === today ? ' is-today' : '')
                                  }
                                  disabled={!canMark || Boolean(busyId)}
                                  aria-pressed={complete}
                                  aria-label={
                                    t(
                                      complete
                                        ? 'Снять отметку {title} за {date}'
                                        : 'Отметить {title} за {date}',
                                      { title: habit.title, date: label },
                                    ) +
                                    '. ' +
                                    t(
                                      status === 'future'
                                        ? 'Будущий день'
                                        : status === 'rest'
                                          ? 'Не запланировано'
                                          : status === 'before'
                                            ? 'До начала'
                                            : complete
                                              ? 'Выполнено'
                                              : 'Запланировано',
                                    )
                                  }
                                  onClick={() =>
                                    void setProgress(habit, day, complete ? 0 : habitTarget(habit))
                                  }
                                >
                                  <span>{formatDate(day, { weekday: 'short' }, language)}</span>
                                  <strong>{Number(day.slice(-2))}</strong>
                                  <i>
                                    {complete ? (
                                      <Check size={15} strokeWidth={3} />
                                    ) : status === 'rest' ? (
                                      '–'
                                    ) : null}
                                  </i>
                                </button>
                              );
                            })}
                          </div>
                        </div>
                        <div className="habit-card-bottom">
                          <div className="habit-today-copy">
                            <span>{t(isScheduled ? 'Прогресс сегодня' : 'Сегодня выходной')}</span>
                            {isScheduled && (
                              <strong>
                                {habit.target
                                  ? progress +
                                    ' / ' +
                                    habit.target +
                                    (habit.unit ? ' ' + habit.unit : '')
                                  : t(
                                      habitCompleteOn(habit, today)
                                        ? 'Выполнено'
                                        : 'Ещё не выполнено',
                                    )}
                              </strong>
                            )}
                          </div>
                          {isScheduled && habit.target ? (
                            <HabitProgressEditor
                              habit={habit}
                              today={today}
                              busy={Boolean(busyId)}
                              onSave={(count) => void setProgress(habit, today, count)}
                            />
                          ) : isScheduled ? (
                            <button
                              type="button"
                              className={
                                'button ' +
                                (habitCompleteOn(habit, today)
                                  ? 'button-secondary'
                                  : 'button-primary')
                              }
                              disabled={Boolean(busyId)}
                              onClick={() =>
                                void setProgress(
                                  habit,
                                  today,
                                  habitCompleteOn(habit, today) ? 0 : 1,
                                )
                              }
                            >
                              <Check size={16} />{' '}
                              {t(habitCompleteOn(habit, today) ? 'Отменить' : 'Выполнить')}
                            </button>
                          ) : null}
                        </div>
                      </>
                    )}
                    <div className="habit-awards" aria-label={t('Достижения')}>
                      {HABIT_MILESTONES.map((milestone) => (
                        <span
                          key={milestone}
                          className={awards.includes(milestone) ? 'is-earned' : ''}
                          title={t('{count} дней подряд', { count: milestone })}
                        >
                          <Flame size={13} /> {milestone}
                        </span>
                      ))}
                    </div>
                  </article>
                );
              })}
            </MotionList>
          )}
        </>
      )}
      {editing && (
        <Dialog
          title={t(editing === 'create' ? 'Новая привычка' : 'Изменить привычку')}
          onClose={() => setEditing(null)}
          busy={Boolean(busyId)}
        >
          {error && (
            <p className="habits-error" role="alert">
              {error}
            </p>
          )}
          <HabitForm
            key={editing === 'create' ? 'create' : editing.id}
            initial={editing === 'create' ? defaultDraft : editing}
            busy={Boolean(busyId)}
            onSubmit={(input) => void save(input)}
            onCancel={() => setEditing(null)}
          />
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
              className="button button-secondary"
              type="button"
              onClick={() => setDeleting(null)}
            >
              {t('Отмена')}
            </button>
            <button
              className="button button-danger"
              type="button"
              disabled={Boolean(busyId)}
              onClick={() => void remove()}
            >
              {t('Удалить привычку')}
            </button>
          </div>
        </Dialog>
      )}
    </section>
  );
}
