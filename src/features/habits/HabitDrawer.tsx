import { useEffect, useMemo, useRef, useState, type CSSProperties } from 'react';
import { createPortal } from 'react-dom';
import { Archive, Check, Medal, Pencil, RotateCcw, Target, X } from 'lucide-react';
import type { Habit } from '../../../shared/types';
import { formatDate } from '../../lib/date';
import { activateDialogViewport } from '../../lib/dialog-viewport';
import { useI18n } from '../../lib/i18n';
import {
  HABIT_MILESTONES,
  habitBestStreak,
  habitCanMarkOn,
  habitDayFraction,
  habitDayState,
  habitDefaultDay,
  habitMilestoneEvents,
  habitMilestonesEarned,
  habitNextMilestone,
  habitPeriodDates,
  habitPeriodStats,
  habitProgress,
  habitStreak,
  habitTarget,
  type HabitPeriod,
} from '../habit-utils';
import { CountUp, HabitRing } from './habit-motion';
import {
  dayNumber,
  daysInRow,
  fillTemplate,
  formatAmount,
  periodLabel,
  scheduleText,
  shortDate,
  weekdayLong,
  weekdayOf,
  weekdayShort,
} from './habit-format';
import {
  HabitDayFooter,
  HabitHeat,
  HabitIconChip,
  MilestoneChips,
  Segmented,
  StepNav,
  habitStyle,
  Stat,
} from './habit-parts';

const CLOSE_MS = 240;
const CLOSE_REDUCED_MS = 120;

interface DrawerProps {
  habit: Habit;
  today: string;
  period: HabitPeriod;
  offset: number;
  day: string;
  busy: boolean;
  popKey: string | null;
  earliest: string;
  onClose: () => void;
  onEdit: (habit: Habit) => void;
  onArchive: (habit: Habit, archived: boolean) => void;
  onProgress: (habit: Habit, day: string, count: number) => void;
}

function DayCell({
  habit,
  date,
  today,
  selected,
  onPick,
  hint,
  week,
}: {
  habit: Habit;
  date: string;
  today: string;
  selected: string;
  onPick: (date: string) => void;
  hint: string;
  week: boolean;
}) {
  const { language } = useI18n();
  const state = habitDayState(habit, date, today);
  const style = { '--p': `${Math.round(habitDayFraction(habit, date) * 100)}%` } as CSSProperties;
  const amount =
    week && habit.target && state !== 'off' && state !== 'future'
      ? formatAmount(habitProgress(habit, date), language)
      : '';
  const common = {
    type: 'button' as const,
    style,
    title: hint,
    'aria-label': hint,
    disabled: state === 'future',
    onClick: () => onPick(date),
  };
  if (!week)
    return (
      <button
        {...common}
        className={
          'hb-dc is-' +
          state +
          (date === today ? ' is-today' : '') +
          (date === selected ? ' is-sel' : '')
        }
      >
        <em>{dayNumber(date)}</em>
      </button>
    );
  return (
    <button
      {...common}
      className={
        'hb-wk is-' +
        state +
        (date === today ? ' is-today' : '') +
        (date === selected ? ' is-sel' : '')
      }
    >
      <i>{weekdayOf(date, language)}</i>
      <em>{dayNumber(date)}</em>
      <span className="hb-bx">
        {state === 'done' && <Check size={15} strokeWidth={2.6} aria-hidden="true" />}
      </span>
      <small>{amount}</small>
    </button>
  );
}

function Legend({ habit }: { habit: Habit }) {
  const { t } = useI18n();
  return (
    <div className="hb-legend">
      <span>
        <i className="hb-hm" />
        {t('нет')}
      </span>
      {habit.target ? (
        <>
          <span>
            <i className="hb-hm is-part" style={{ '--p': '50%' } as CSSProperties} />
            {t('часть цели')}
          </span>
          <span>
            <i className="hb-hm is-done" />
            {t('цель выполнена')}
          </span>
        </>
      ) : (
        <span>
          <i className="hb-hm is-done" />
          {t('выполнено')}
        </span>
      )}
    </div>
  );
}

function Readout({ habit, date, today }: { habit: Habit; date: string; today: string }) {
  const { t, language } = useI18n();
  const state = habitDayState(habit, date, today);
  const value =
    state === 'future'
      ? t('Ещё не наступил')
      : state === 'off'
        ? t('Не по расписанию')
        : habit.target
          ? formatAmount(habitProgress(habit, date), language) +
            ' / ' +
            formatAmount(habitTarget(habit), language) +
            (habit.unit ? ' ' + habit.unit : '')
          : t(state === 'done' ? 'Выполнено' : 'Не выполнено');
  return (
    <div className="hb-readout">
      <b>{weekdayLong(date, language) + ', ' + shortDate(date, language)}</b>
      <span>{value}</span>
    </div>
  );
}

export function HabitDrawer(props: DrawerProps) {
  const { habit, today, busy, popKey, earliest, onClose, onEdit, onArchive, onProgress } = props;
  const { t, language } = useI18n();
  const dialog = useRef<HTMLDialogElement>(null);
  const closing = useRef<number | null>(null);
  const closeRef = useRef(onClose);
  closeRef.current = onClose;
  const [period, setPeriod] = useState(props.period);
  const [offset, setOffset] = useState(props.offset);
  const [day, setDay] = useState(props.day);
  const archived = Boolean(habit.archived);

  const requestClose = () => {
    const element = dialog.current;
    if (!element || closing.current !== null) return;
    element.classList.add('is-closing');
    closing.current = window.setTimeout(
      () => {
        closing.current = null;
        closeRef.current();
      },
      window.matchMedia('(prefers-reduced-motion: reduce)').matches ? CLOSE_REDUCED_MS : CLOSE_MS,
    );
  };
  useEffect(() => {
    const element = dialog.current!;
    const previous = document.activeElement as HTMLElement | null;
    element.showModal();
    const release = activateDialogViewport(element);
    return () => {
      if (closing.current !== null) window.clearTimeout(closing.current);
      element.close();
      release();
      if (previous?.isConnected) previous.focus({ preventScroll: true });
    };
  }, []);

  const dates = useMemo(() => habitPeriodDates(today, period, offset), [today, period, offset]);
  const stats = useMemo(() => habitPeriodStats(habit, dates, today), [habit, dates, today]);
  const current = habitStreak(habit, today);
  const best = habitBestStreak(habit, today);
  const next = habitNextMilestone(current);
  const earned = habitMilestonesEarned(habit, best);
  const events = useMemo(() => habitMilestoneEvents(habit, today), [habit, today]);
  const week = period === 'week';
  const selected = dates.includes(day) ? day : habitDefaultDay(dates, today);
  const unitSuffix = habit.unit ? ' ' + habit.unit : '';
  const hint = (date: string) => {
    const state = habitDayState(habit, date, today);
    const text =
      state === 'off'
        ? t('не по расписанию')
        : state === 'future'
          ? t('ещё не наступил')
          : habit.target
            ? formatAmount(habitProgress(habit, date), language) +
              ' / ' +
              formatAmount(habitTarget(habit), language) +
              unitSuffix
            : t(state === 'done' ? 'выполнено' : 'не выполнено');
    return weekdayLong(date, language) + ', ' + shortDate(date, language) + ' · ' + text;
  };
  const changePeriod = (value: HabitPeriod) => {
    setPeriod(value);
    setOffset(0);
    setDay(habitDefaultDay(habitPeriodDates(today, value, 0), today));
  };
  const step = (direction: -1 | 1) => {
    const nextOffset = Math.min(0, offset + direction);
    setOffset(nextOffset);
    setDay(habitDefaultDay(habitPeriodDates(today, period, nextOffset), today));
  };
  const summary = !stats.scheduled
    ? t('В этом периоде нет дней по расписанию.')
    : habit.target
      ? fillTemplate(t('Цель достигнута {done} из {total} дней · в среднем {average} в день'), {
          done: <b>{stats.completed}</b>,
          total: <b>{stats.scheduled}</b>,
          average: (
            <b>
              {formatAmount(stats.average, language)}
              {unitSuffix}
            </b>
          ),
        })
      : fillTemplate(t('Выполнено {done} из {total} дней по расписанию'), {
          done: <b>{stats.completed}</b>,
          total: <b>{stats.scheduled}</b>,
        });
  const first = dates[0];
  const blanks = Array.from({ length: new Date(first + 'T12:00:00Z').getUTCDay() });
  const unitCaption = habit.target ? habit.unit || '' : '';

  return createPortal(
    <dialog
      ref={dialog}
      className="hb-drawer-dialog"
      aria-label={habit.title}
      onCancel={(event) => {
        event.preventDefault();
        requestClose();
      }}
      onClick={(event) => event.target === event.currentTarget && requestClose()}
    >
      <aside className="hb-drawer" style={habitStyle(habit)}>
        <div className="hb-drawer-body">
          <header className="hb-drawer-id">
            <HabitIconChip habit={habit} size={50} />
            <div className="hb-tx">
              <h2>{habit.title}</h2>
              <p>{scheduleText(habit, t, language)}</p>
            </div>
            <button
              type="button"
              className="hb-icon-btn"
              aria-label={t('Закрыть')}
              onClick={requestClose}
            >
              <X size={18} strokeWidth={2} aria-hidden="true" />
            </button>
          </header>
          <div className="hb-drawer-period">
            <Segmented
              full
              label={t('Период аналитики')}
              value={period}
              onChange={changePeriod}
              options={[
                ['week', t('Неделя')],
                ['month', t('Месяц')],
              ]}
            />
            <StepNav
              wide
              label={periodLabel(dates, week, language)}
              previousLabel={t(week ? 'Предыдущая неделя' : 'Предыдущий месяц')}
              nextLabel={t(week ? 'Следующая неделя' : 'Следующий месяц')}
              canPrevious={dates[0] > earliest}
              canNext={offset < 0}
              onStep={step}
            />
          </div>
          <div className="hb-drawer-stats">
            <HabitRing
              count={current}
              fraction={next ? current / next : 1}
              size={76}
              label={t('дн.')}
            />
            <div className="hb-stat-grid">
              <Stat value={<CountUp value={best} />} caption={t('рекорд, дн.')} />
              <Stat
                value={
                  <>
                    <CountUp value={stats.percent ?? 0} />%
                  </>
                }
                caption={t(week ? 'за неделю' : 'за месяц')}
              />
              <Stat
                value={next ? <CountUp value={next - current} /> : '—'}
                caption={next ? t('до цели · {count}', { count: next }) : t('до цели')}
              />
            </div>
          </div>
          <p className="hb-summary">{summary}</p>
          {week ? (
            <section className="hb-card-block">
              <div className="hb-block-head">
                <h3>{t('Неделя')}</h3>
                <small>
                  {unitCaption ? t('{unit} за день', { unit: unitCaption }) : t('по дням')}
                </small>
              </div>
              <div className="hb-wk7">
                {dates.map((date) => (
                  <DayCell
                    key={date}
                    habit={habit}
                    date={date}
                    today={today}
                    selected={selected}
                    hint={hint(date)}
                    week
                    onPick={setDay}
                  />
                ))}
              </div>
              <Legend habit={habit} />
              <Readout habit={habit} date={selected} today={today} />
            </section>
          ) : (
            <>
              <section className="hb-card-block">
                <div className="hb-block-head">
                  <h3>{t('Календарь месяца')}</h3>
                  <small>
                    {unitCaption ? t('{unit} за день', { unit: unitCaption }) : t('по дням')}
                  </small>
                </div>
                <div className="hb-cal-head">
                  {Array.from({ length: 7 }, (_, weekday) => (
                    <i key={weekday}>{weekdayShort(weekday, language)}</i>
                  ))}
                </div>
                <div className="hb-cal">
                  {blanks.map((_, index) => (
                    <span key={'blank-' + index} />
                  ))}
                  {dates.map((date) => (
                    <DayCell
                      key={date}
                      habit={habit}
                      date={date}
                      today={today}
                      selected={selected}
                      hint={hint(date)}
                      week={false}
                      onPick={setDay}
                    />
                  ))}
                </div>
                <Legend habit={habit} />
                <Readout habit={habit} date={selected} today={today} />
              </section>
              <section className="hb-card-block">
                <div className="hb-block-head">
                  <h3>{t('Тепловая карта')}</h3>
                  <small>{t('20 недель')}</small>
                </div>
                <HabitHeat habit={habit} today={today} selected={selected} onPick={setDay} />
                <Legend habit={habit} />
                <Readout habit={habit} date={selected} today={today} />
              </section>
            </>
          )}
          {!archived && habitCanMarkOn(habit, selected, today) && (
            <div className="hb-drawer-ctl">
              <HabitDayFooter
                habit={habit}
                day={selected}
                today={today}
                busy={busy}
                big
                pop={popKey === habit.id + '|' + selected}
                onProgress={(count) => onProgress(habit, selected, count)}
              />
            </div>
          )}
          <section className="hb-card-block">
            <div className="hb-block-head">
              <h3>{t('Достижения')}</h3>
              <small>{t('дней подряд')}</small>
            </div>
            <MilestoneChips earned={earned} />
            <p className="hb-note">
              {next
                ? t('Следующая — {next} дн. подряд, осталось {left}.', {
                    next,
                    left: next - current,
                  })
                : t('Все достижения получены.')}
            </p>
          </section>
          <section className="hb-card-block">
            <div className="hb-block-head">
              <h3>{t('История достижений')}</h3>
              <small>
                {t('{count} из {total}', { count: events.length, total: HABIT_MILESTONES.length })}
              </small>
            </div>
            <ol className="hb-timeline">
              {next && (
                <li className="is-next">
                  <span className="hb-node">
                    <Target size={14} strokeWidth={2} aria-hidden="true" />
                  </span>
                  <div>
                    <b>{daysInRow(next, t)}</b>
                    <small>{t('осталось {count}', { count: next - current })}</small>
                  </div>
                </li>
              )}
              {events.map((event) => (
                <li key={event.milestone}>
                  <span className="hb-node">
                    <Medal size={14} strokeWidth={2} aria-hidden="true" />
                  </span>
                  <div>
                    <b>{daysInRow(event.milestone, t)}</b>
                    <small>
                      {formatDate(event.date, { day: 'numeric', month: 'short' }, language)}
                    </small>
                  </div>
                </li>
              ))}
            </ol>
          </section>
          <div className="hb-drawer-actions">
            <button type="button" className="hb-btn" onClick={() => onEdit(habit)}>
              <Pencil size={16} aria-hidden="true" />
              {t('Изменить')}
            </button>
            <button
              type="button"
              className="hb-btn"
              disabled={busy}
              onClick={() => onArchive(habit, !archived)}
            >
              {archived ? (
                <RotateCcw size={16} aria-hidden="true" />
              ) : (
                <Archive size={16} aria-hidden="true" />
              )}
              {t(archived ? 'Вернуть' : 'В архив')}
            </button>
          </div>
        </div>
      </aside>
    </dialog>,
    document.body,
  );
}
