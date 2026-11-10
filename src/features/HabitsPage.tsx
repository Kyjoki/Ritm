import { memo, useCallback, useEffect, useMemo, useRef, useState, type CSSProperties } from 'react';
import { Archive, ChevronLeft, LoaderCircle, Plus, Sparkles } from 'lucide-react';
import type { Habit, HabitInput } from '../../shared/types';
import { MotionList } from '../components/Motion';
import { Dialog } from '../components/Dialog';
import { api } from '../lib/api';
import { LatestRead, RefreshGate } from '../lib/latest-read';
import { dateInZone } from '../lib/date';
import { useI18n } from '../lib/i18n';
import { addDays } from './calendar-utils';
import {
  habitAnalyticsScope,
  habitBestStreak,
  habitCanMarkOn,
  habitCompleteOn,
  habitDaySummary,
  habitDefaultDay,
  habitMilestoneEvents,
  habitMilestonesEarned,
  habitNextMilestone,
  habitPeriodDates,
  habitPeriodSummary,
  habitStreak,
  habitTarget,
  type HabitPeriod,
} from './habit-utils';
import { HabitAwards } from './habits/HabitAwards';
import { HabitCard, type HabitCardData } from './habits/HabitCard';
import { HabitDrawer } from './habits/HabitDrawer';
import { HabitForm, defaultHabitDraft } from './habits/HabitForm';
import { HabitKpis } from './habits/HabitKpis';
import { CountUp } from './habits/habit-motion';
import { fillTemplate, periodLabel, shortDate, weekdayOf } from './habits/habit-format';
import { Segmented, StepNav } from './habits/habit-parts';
import '../styles/habits.css';
import '../styles/habits-drawer.css';

const ALL_DAYS = [0, 1, 2, 3, 4, 5, 6];
/** Longest entrance: 380 ms plus eight 45 ms steps. */
const ENTER_TOTAL_MS = 760;
const SWAP_MS = 320;
const POP_MS = 420;
const RECORD_MS = 1050;
const CELEBRATION_MS = 2600;

function emitHabitsChanged() {
  window.dispatchEvent(
    new CustomEvent('ritm:habits-changed', { detail: { source: 'habits-page' } }),
  );
}

function habitCards(habits: Habit[], today: string): HabitCardData[] {
  return habits.map((habit) => {
    const current = habitStreak(habit, today);
    return {
      habit,
      current,
      best: habitBestStreak(habit, today),
      next: habitNextMilestone(current),
    };
  });
}

const enterStyle = (index: number) => ({ '--i': Math.min(index, 7) }) as CSSProperties;

export const HabitsPage = memo(function HabitsPage({
  active,
  timeZone,
  today = dateInZone(timeZone),
}: {
  active: boolean;
  timeZone: string;
  today?: string;
}) {
  const { t, language } = useI18n();
  const [habits, setHabits] = useState<Habit[]>([]);
  const read = useRef(new LatestRead());
  const hasLoaded = useRef(false);
  const refreshGate = useRef(new RefreshGate());
  const preserveRefreshError = useRef(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [busyId, setBusyId] = useState<string | null>(null);
  const [editing, setEditing] = useState<Habit | 'create' | null>(null);
  const [deleting, setDeleting] = useState<Habit | null>(null);
  const [drawerId, setDrawerId] = useState<string | null>(null);
  const [showArchived, setShowArchived] = useState(false);
  const [period, setPeriod] = useState<HabitPeriod>('week');
  const [offset, setOffset] = useState(0);
  const [selectedDay, setSelectedDay] = useState<string | null>(null);
  const [entering, setEntering] = useState(false);
  const [swap, setSwap] = useState<'fade' | 'next' | 'prev' | null>(null);
  const [dayChange, setDayChange] = useState(false);
  const [popKey, setPopKey] = useState<string | null>(null);
  const [celebration, setCelebration] = useState<{ title: string; milestone: number } | null>(null);
  const [recordId, setRecordId] = useState<string | null>(null);

  const activeHabits = useMemo(() => habitAnalyticsScope(habits, false), [habits]);
  const archivedHabits = useMemo(() => habitAnalyticsScope(habits, true), [habits]);
  const visibleHabits = showArchived ? archivedHabits : activeHabits;
  const dates = useMemo(() => habitPeriodDates(today, period, offset), [today, period, offset]);
  const availableDates = useMemo(() => dates.filter((date) => date <= today), [dates, today]);
  const previousDates = useMemo(
    () => habitPeriodDates(today, period, offset - 1),
    [today, period, offset],
  );
  const day =
    selectedDay && dates.includes(selectedDay) ? selectedDay : habitDefaultDay(dates, today);
  const earliest = useMemo(
    () =>
      habits.reduce((first, habit) => (habit.startDate < first ? habit.startDate : first), today),
    [habits, today],
  );
  const drawerHabit = drawerId ? habits.find((habit) => habit.id === drawerId) : undefined;

  const activeCards = useMemo(() => habitCards(activeHabits, today), [activeHabits, today]);
  const archivedCards = useMemo(() => habitCards(archivedHabits, today), [archivedHabits, today]);
  const cards = showArchived ? archivedCards : activeCards;
  const awardRows = useMemo(
    () => activeCards.map((card) => ({ ...card, events: habitMilestoneEvents(card.habit, today) })),
    [activeCards, today],
  );

  const refresh = useCallback(
    async (preserveError = false) => {
      preserveRefreshError.current ||= preserveError;
      if (!refreshGate.current.request()) return;
      const keepError = preserveRefreshError.current;
      preserveRefreshError.current = false;
      const signal = read.current.start();
      try {
        const result = await api.habits(signal);
        if (!read.current.isCurrent(signal)) return;
        setHabits(result.habits);
        hasLoaded.current = true;
        if (!keepError) setError('');
      } catch (failure) {
        if (read.current.isCurrent(signal))
          setError(
            failure instanceof Error ? failure.message : t('Не удалось загрузить привычки.'),
          );
      } finally {
        if (read.current.isCurrent(signal)) setLoading(false);
      }
    },
    [t],
  );
  useEffect(() => {
    if (!active) return;
    refreshGate.current.activate();
    void refresh();
    const onFocus = () => {
      if (!document.hidden && !refreshGate.current.writing) void refresh();
    };
    const onChange = (event: Event) => {
      if (
        !document.hidden &&
        !refreshGate.current.writing &&
        (event as CustomEvent<{ source?: string }>).detail?.source !== 'habits-page'
      )
        void refresh();
    };
    window.addEventListener('focus', onFocus);
    window.addEventListener('ritm:habits-changed', onChange);
    return () => {
      refreshGate.current.deactivate();
      read.current.cancel();
      window.removeEventListener('focus', onFocus);
      window.removeEventListener('ritm:habits-changed', onChange);
    };
  }, [active, refresh]);
  // Every visit plays the page entrance once the habits are on screen.
  useEffect(() => {
    if (!active || loading) return;
    setEntering(true);
    const timer = window.setTimeout(() => setEntering(false), ENTER_TOTAL_MS);
    return () => {
      window.clearTimeout(timer);
      setEntering(false);
    };
  }, [active, loading]);
  useEffect(() => {
    if (!swap) return;
    const timer = window.setTimeout(() => setSwap(null), SWAP_MS);
    return () => window.clearTimeout(timer);
  }, [swap]);
  useEffect(() => {
    if (!dayChange) return;
    const timer = window.setTimeout(() => setDayChange(false), SWAP_MS + 8 * 30);
    return () => window.clearTimeout(timer);
  }, [dayChange]);
  useEffect(() => {
    if (!popKey) return;
    const timer = window.setTimeout(() => setPopKey(null), POP_MS);
    return () => window.clearTimeout(timer);
  }, [popKey]);
  useEffect(() => {
    if (!celebration) return;
    const timer = window.setTimeout(() => setCelebration(null), CELEBRATION_MS);
    return () => window.clearTimeout(timer);
  }, [celebration]);
  useEffect(() => {
    if (!recordId) return;
    const timer = window.setTimeout(() => setRecordId(null), RECORD_MS);
    return () => window.clearTimeout(timer);
  }, [recordId]);
  useEffect(() => {
    if (drawerId && !drawerHabit && !loading) setDrawerId(null);
  }, [drawerId, drawerHabit, loading]);

  function replaceHabit(habit: Habit) {
    setHabits((current) => current.map((item) => (item.id === habit.id ? habit : item)));
  }
  async function save(input: HabitInput) {
    const old = editing === 'create' ? null : editing;
    if (!editing || busyId || refreshGate.current.writing) return;
    read.current.cancel();
    refreshGate.current.beginWrite(!hasLoaded.current);
    setLoading(false);
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
      if (refreshGate.current.endWrite()) void refresh();
      setBusyId(null);
    }
  }
  async function updateArchive(habit: Habit, archived: boolean): Promise<boolean> {
    if (busyId || refreshGate.current.writing) return false;
    read.current.cancel();
    refreshGate.current.beginWrite(!hasLoaded.current);
    setLoading(false);
    setBusyId(habit.id);
    try {
      replaceHabit(
        (
          await api.updateHabit(
            habit.id,
            {
              title: habit.title,
              icon: habit.icon ?? 'sparkles',
              weekdays: habit.weekdays ?? ALL_DAYS,
              target: habit.target ?? null,
              unit: habit.unit ?? '',
              archived,
            },
            habit.updatedAt,
          )
        ).habit,
      );
      emitHabitsChanged();
      return true;
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : t('Не удалось сохранить привычку.'));
      void refresh(true);
      return false;
    } finally {
      if (refreshGate.current.endWrite()) void refresh();
      setBusyId(null);
    }
  }
  async function archiveHabit(habit: Habit, archived: boolean) {
    if (await updateArchive(habit, archived)) {
      setDrawerId((current) => (current === habit.id ? null : current));
      setEditing((current) =>
        current && current !== 'create' && current.id === habit.id ? null : current,
      );
    }
  }
  async function remove() {
    if (!deleting || busyId || refreshGate.current.writing) return;
    read.current.cancel();
    refreshGate.current.beginWrite(!hasLoaded.current);
    setLoading(false);
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
      if (refreshGate.current.endWrite()) void refresh();
      setBusyId(null);
    }
  }
  async function setProgress(habit: Habit, date: string, count: number) {
    if (busyId || refreshGate.current.writing || !habitCanMarkOn(habit, date, today)) return;
    read.current.cancel();
    refreshGate.current.beginWrite(!hasLoaded.current);
    setLoading(false);
    const target = habitTarget(habit);
    const nextCount = Math.max(0, Math.min(target, count));
    const wasComplete = habitCompleteOn(habit, date);
    const nextDates = habit.completedDates.filter((value) => value !== date);
    if (nextCount >= target) nextDates.push(date);
    const optimistic = {
      ...habit,
      completedDates: nextDates.sort(),
      progressByDate: { ...habit.progressByDate, [date]: nextCount },
    };
    setBusyId(habit.id);
    setError('');
    setPopKey(habit.id + '|' + date);
    if (date >= habit.startDate) replaceHabit(optimistic);
    try {
      const result = habit.target
        ? await api.setHabitProgress(habit.id, date, nextCount, habit.updatedAt)
        : await api.setHabitDay(habit.id, date, nextCount > 0, habit.updatedAt);
      replaceHabit(result.habit);
      if (!wasComplete && nextCount >= target) {
        const before = habitBestStreak(habit, today);
        const after = habitBestStreak(result.habit, today);
        if (after > before) setRecordId(habit.id);
        const earnedBefore = habitMilestonesEarned(habit, before);
        const reached = habitMilestonesEarned(result.habit, after).find(
          (milestone) => !earnedBefore.includes(milestone),
        );
        if (reached) setCelebration({ title: habit.title, milestone: reached });
      }
      emitHabitsChanged();
    } catch (failure) {
      replaceHabit(habit);
      setError(failure instanceof Error ? failure.message : t('Не удалось изменить отметку.'));
      void refresh(true);
    } finally {
      if (refreshGate.current.endWrite()) void refresh();
      setBusyId(null);
    }
  }

  const stats = useMemo(() => {
    const totals = habitPeriodSummary(visibleHabits, dates, today);
    const length = Math.min(availableDates.length, previousDates.length);
    const comparable = habitPeriodSummary(visibleHabits, availableDates.slice(0, length), today);
    const previous = habitPeriodSummary(visibleHabits, previousDates.slice(0, length), today);
    const delta =
      previous.progress !== null && comparable.progress !== null
        ? comparable.progress - previous.progress
        : null;
    const todaySummary = habitDaySummary(visibleHabits, today, today);
    return {
      totals,
      delta,
      todaySummary,
      currentStreak: Math.max(0, ...cards.map((card) => card.current)),
      bestStreak: Math.max(0, ...cards.map((card) => card.best)),
      daily: dates.map((date) => ({
        day: date,
        progress: habitDaySummary(visibleHabits, date, today).progress,
      })),
    };
  }, [visibleHabits, dates, availableDates, previousDates, today, cards]);

  const changePeriod = (value: HabitPeriod) => {
    setPeriod(value);
    setOffset(0);
    setSelectedDay(null);
    setSwap('fade');
  };
  const stepPeriod = (direction: -1 | 1) => {
    setOffset((current) => Math.min(0, current + direction));
    setSelectedDay(null);
    setSwap(direction > 0 ? 'next' : 'prev');
  };
  const stepDay = (direction: -1 | 1) => {
    const next = addDays(day, direction);
    if (!dates.includes(next) || next > today) return;
    setSelectedDay(next);
    setDayChange(true);
  };
  const week = period === 'week';
  const swapClass = swap ? ' is-swap-' + swap : '';

  return (
    <section
      className={'habits-page hb' + (entering ? ' is-entering' : '')}
      aria-labelledby="habits-title"
    >
      <header className="page-heading habits-page-heading hb-b" style={enterStyle(0)}>
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
          className="hb-btn is-primary hb-add"
          type="button"
          onClick={() => {
            setError('');
            setEditing('create');
          }}
        >
          <Plus size={18} strokeWidth={2.2} aria-hidden="true" /> {t('Новая привычка')}
        </button>
      </header>
      {error && (
        <div className="hb-error" role="alert">
          {error}{' '}
          <button className="text-button" type="button" onClick={() => void refresh()}>
            {t('Повторить')}
          </button>
        </div>
      )}
      {celebration && (
        <div className="hb-toast" role="status">
          <Sparkles size={18} aria-hidden="true" />
          {t('{title}: достижение {count} дней', {
            title: celebration.title,
            count: celebration.milestone,
          })}
        </div>
      )}
      {loading ? (
        <div className="hb-empty" role="status">
          <LoaderCircle className="spin" size={22} /> {t('Загружаем…')}
        </div>
      ) : (
        <>
          <div className="hb-top">
            <div className="hb-period-head hb-b" style={enterStyle(0)}>
              <div className={'hb-swap' + swapClass}>
                <h2>{periodLabel(dates, week, language)}</h2>
                <p>
                  {t(week ? 'Неделя' : 'Месяц')} ·{' '}
                  {fillTemplate(t('{done} из {total} отметок'), {
                    done: <CountUp value={stats.totals.completed} />,
                    total: <CountUp value={stats.totals.planned} />,
                  })}
                </p>
              </div>
              <div className="hb-ctl">
                <StepNav
                  label={periodLabel(dates, week, language)}
                  previousLabel={t(week ? 'Предыдущая неделя' : 'Предыдущий месяц')}
                  nextLabel={t(week ? 'Следующая неделя' : 'Следующий месяц')}
                  canPrevious={dates[0] > earliest}
                  canNext={offset < 0}
                  onStep={stepPeriod}
                />
                <Segmented
                  label={t('Период аналитики')}
                  value={period}
                  onChange={changePeriod}
                  options={[
                    ['week', t('Неделя')],
                    ['month', t('Месяц')],
                  ]}
                />
              </div>
            </div>
            <div className={'hb-kpis-wrap' + swapClass}>
              <HabitKpis
                data={{
                  todayDone: stats.todaySummary.completed,
                  todayPlanned: stats.todaySummary.planned,
                  currentStreak: stats.currentStreak,
                  bestStreak: stats.bestStreak,
                  rate: stats.totals.progress ?? 0,
                  delta: stats.delta,
                  daily: stats.daily,
                  today,
                }}
              />
            </div>
          </div>
          <div className="hb-body">
            <main>
              <div className="hb-list-head hb-b" style={enterStyle(4)}>
                <h2 id="habit-list-title">
                  {t(showArchived ? 'Архив' : 'Мои привычки')}
                  <small>{visibleHabits.length}</small>
                </h2>
                <div className="hb-list-tools">
                  {!showArchived && (
                    <StepNav
                      label={
                        day === today
                          ? t('Сегодня')
                          : weekdayOf(day, language) + ', ' + shortDate(day, language)
                      }
                      previousLabel={t('Предыдущий день')}
                      nextLabel={t('Следующий день')}
                      canPrevious={dates.includes(addDays(day, -1))}
                      canNext={dates.includes(addDays(day, 1)) && addDays(day, 1) <= today}
                      onStep={stepDay}
                    />
                  )}
                  <button
                    className="hb-btn is-ghost"
                    type="button"
                    onClick={() => {
                      setShowArchived(!showArchived);
                      setSelectedDay(null);
                    }}
                  >
                    {showArchived ? (
                      <ChevronLeft size={16} strokeWidth={2} aria-hidden="true" />
                    ) : (
                      <Archive size={16} strokeWidth={2} aria-hidden="true" />
                    )}
                    {t(showArchived ? 'К привычкам' : 'Архив')}
                  </button>
                </div>
              </div>
              {visibleHabits.length === 0 ? (
                <div className="hb-empty">
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
                <MotionList className={'hb-grid' + (dayChange ? ' is-day-change' : '')}>
                  {cards.map((card, index) => (
                    <HabitCard
                      key={card.habit.id}
                      data={card}
                      index={index}
                      day={day}
                      today={today}
                      busy={Boolean(busyId)}
                      popKey={popKey}
                      record={recordId === card.habit.id}
                      onOpen={(habit) => setDrawerId(habit.id)}
                      onEdit={(habit) => {
                        setError('');
                        setEditing(habit);
                      }}
                      onArchive={(habit, archived) => void archiveHabit(habit, archived)}
                      onDelete={setDeleting}
                      onProgress={(habit, date, count) => void setProgress(habit, date, count)}
                    />
                  ))}
                </MotionList>
              )}
            </main>
            <div className="hb-b" style={enterStyle(5)}>
              <HabitAwards rows={awardRows} onOpen={(habit) => setDrawerId(habit.id)} />
            </div>
          </div>
        </>
      )}
      {drawerHabit && (
        <HabitDrawer
          key={drawerHabit.id}
          habit={drawerHabit}
          today={today}
          period={period}
          offset={offset}
          day={day}
          busy={Boolean(busyId)}
          popKey={popKey}
          earliest={earliest}
          onClose={() => setDrawerId(null)}
          onEdit={(habit) => {
            setError('');
            setEditing(habit);
          }}
          onArchive={(habit, archived) => void archiveHabit(habit, archived)}
          onProgress={(habit, date, count) => void setProgress(habit, date, count)}
        />
      )}
      {editing && (
        <Dialog
          title={t(editing === 'create' ? 'Новая привычка' : 'Изменить привычку')}
          onClose={() => setEditing(null)}
          busy={Boolean(busyId)}
          className="hb-dialog"
        >
          {error && (
            <p className="hb-form-error" role="alert">
              {error}
            </p>
          )}
          <HabitForm
            key={editing === 'create' ? 'create' : editing.id}
            initial={editing === 'create' ? defaultHabitDraft : editing}
            busy={Boolean(busyId)}
            onSubmit={(input) => void save(input)}
            onCancel={() => setEditing(null)}
            onArchive={
              editing !== 'create' && !editing.archived
                ? () => void archiveHabit(editing, true)
                : undefined
            }
          />
        </Dialog>
      )}
      {deleting && (
        <Dialog
          title={t('Удалить привычку?')}
          onClose={() => setDeleting(null)}
          busy={Boolean(busyId)}
          className="hb-dialog"
        >
          <p className="hb-note">{t('История отметок этой привычки будет удалена.')}</p>
          <div className="hb-form-actions">
            <span className="hb-spacer" />
            <button className="hb-btn" type="button" onClick={() => setDeleting(null)}>
              {t('Отмена')}
            </button>
            <button
              className="hb-btn is-danger"
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
});
