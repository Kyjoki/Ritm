import { useRef, useState, type CSSProperties, type ReactNode } from 'react';
import { Check, ChevronLeft, ChevronRight, Minus, Plus } from 'lucide-react';
import {
  Activity,
  BookOpen,
  Droplets,
  Moon,
  Sparkles,
  Target,
  type LucideIcon,
} from 'lucide-react';
import type { Habit, HabitIcon as HabitIconName } from '../../../shared/types';
import { formatDate } from '../../lib/date';
import { useI18n } from '../../lib/i18n';
import {
  HABIT_MILESTONES,
  habitCanMarkOn,
  habitColor,
  habitDayFraction,
  habitDayState,
  habitProgress,
  habitScheduledOn,
  habitStep,
  habitTarget,
  habitWeek,
  type HabitDayState,
} from '../habit-utils';
import { addDays } from '../calendar-utils';
import { CountUp, HabitBar, useCellsFade, useCountUp, useLineDraw } from './habit-motion';
import { dayNumber, formatAmount, weekdayOf } from './habit-format';

export const iconChoices: Record<HabitIconName, LucideIcon> = {
  sparkles: Sparkles,
  book: BookOpen,
  activity: Activity,
  droplet: Droplets,
  moon: Moon,
  target: Target,
};
export const iconLabels: Record<HabitIconName, string> = {
  sparkles: 'Искры',
  book: 'Книга',
  activity: 'Движение',
  droplet: 'Вода',
  moon: 'Сон',
  target: 'Цель',
};

export function HabitIconView({ icon, size = 20 }: { icon?: HabitIconName; size?: number }) {
  const Icon = iconChoices[icon ?? 'sparkles'] ?? Sparkles;
  return <Icon size={size} aria-hidden="true" />;
}

/** The accent colour of a habit as a CSS variable, inherited by every part of its card. */
export const habitStyle = (habit: Habit): CSSProperties =>
  ({ '--hc': habitColor(habit) }) as CSSProperties;

export function HabitIconChip({ habit, size }: { habit: Habit; size: number }) {
  return (
    <span className="hb-idc" style={{ '--is': `${size}px` } as CSSProperties}>
      <HabitIconView icon={habit.icon} size={Math.round(size * 0.5)} />
    </span>
  );
}

export function Segmented<T extends string>({
  label,
  value,
  options,
  onChange,
  full = false,
}: {
  label: string;
  value: T;
  options: readonly (readonly [T, string])[];
  onChange: (value: T) => void;
  full?: boolean;
}) {
  return (
    <div className={'hb-seg' + (full ? ' is-full' : '')} role="group" aria-label={label}>
      {options.map(([option, text]) => (
        <button
          key={option}
          type="button"
          aria-pressed={value === option}
          onClick={() => onChange(option)}
        >
          {text}
        </button>
      ))}
    </div>
  );
}

export function StepNav({
  label,
  previousLabel,
  nextLabel,
  canPrevious,
  canNext,
  onStep,
  wide = false,
}: {
  label: ReactNode;
  previousLabel: string;
  nextLabel: string;
  canPrevious: boolean;
  canNext: boolean;
  onStep: (direction: -1 | 1) => void;
  wide?: boolean;
}) {
  return (
    <div className={'hb-nav' + (wide ? ' is-wide' : '')}>
      <button
        type="button"
        aria-label={previousLabel}
        disabled={!canPrevious}
        onClick={() => onStep(-1)}
      >
        <ChevronLeft size={18} strokeWidth={2} aria-hidden="true" />
      </button>
      <span className="hb-nav-label">{label}</span>
      <button type="button" aria-label={nextLabel} disabled={!canNext} onClick={() => onStep(1)}>
        <ChevronRight size={18} strokeWidth={2} aria-hidden="true" />
      </button>
    </div>
  );
}

function useDayHint(habit: Habit, today: string) {
  const { t, language } = useI18n();
  return (day: string) => {
    const state = habitDayState(habit, day, today);
    const text =
      state === 'off'
        ? t('не по расписанию')
        : state === 'future'
          ? t('ещё не наступил')
          : habit.target
            ? formatAmount(habitProgress(habit, day), language) +
              ' / ' +
              formatAmount(habitTarget(habit), language) +
              (habit.unit ? ' ' + habit.unit : '')
            : state === 'done'
              ? t('выполнено')
              : t('не выполнено');
    return formatDate(day, { day: 'numeric', month: 'short' }, language) + ' · ' + text;
  };
}

const stateLabel: Record<HabitDayState, string> = {
  future: 'Будущий день',
  off: 'Не запланировано',
  done: 'Выполнено',
  part: 'Запланировано',
  miss: 'Запланировано',
};

/** The seven days of the selected day's week; a tap completes or clears a day. */
export function HabitDayTiles({
  habit,
  day,
  today,
  busy,
  popKey,
  onToggle,
}: {
  habit: Habit;
  day: string;
  today: string;
  busy: boolean;
  popKey: string | null;
  onToggle: (day: string, complete: boolean) => void;
}) {
  const { t, language } = useI18n();
  const hint = useDayHint(habit, today);
  return (
    <div
      className="hb-tiles"
      role="group"
      aria-label={t('Неделя: {title}', { title: habit.title })}
    >
      {habitWeek(day).map((date) => {
        const state = habitDayState(habit, date, today);
        const complete = state === 'done';
        const label = formatDate(
          date,
          { weekday: 'short', day: 'numeric', month: 'long' },
          language,
        );
        return (
          <div key={date} className={'hb-tile-col' + (date === today ? ' is-today' : '')}>
            <i>{weekdayOf(date, language)}</i>
            <button
              type="button"
              className={
                'hb-dc is-' +
                state +
                (date === today ? ' is-today' : '') +
                (date === day && date !== today ? ' is-sel' : '') +
                (popKey === habit.id + '|' + date ? ' is-pop' : '')
              }
              style={
                { '--p': `${Math.round(habitDayFraction(habit, date) * 100)}%` } as CSSProperties
              }
              disabled={!habitCanMarkOn(habit, date, today) || busy}
              aria-pressed={complete}
              title={hint(date)}
              aria-label={
                t(complete ? 'Снять отметку {title} за {date}' : 'Отметить {title} за {date}', {
                  title: habit.title,
                  date: label,
                }) +
                '. ' +
                t(stateLabel[state])
              }
              onClick={() => onToggle(date, complete)}
            >
              <em>{dayNumber(date)}</em>
            </button>
          </div>
        );
      })}
    </div>
  );
}

function ProgressInput({
  habit,
  progress,
  disabled,
  onCommit,
}: {
  habit: Habit;
  progress: number;
  disabled: boolean;
  onCommit: (count: number) => void;
}) {
  const { t, language } = useI18n();
  const shown = useCountUp(progress);
  const [draft, setDraft] = useState<string | null>(null);
  const target = habitTarget(habit);
  const commit = () => {
    const value = draft === null || draft.trim() === '' ? Number.NaN : Number(draft);
    setDraft(null);
    if (Number.isInteger(value) && value >= 0 && value <= target && value !== progress)
      onCommit(value);
  };
  return (
    <span className="hb-qv">
      <input
        type="number"
        min={0}
        max={target}
        step={1}
        inputMode="numeric"
        disabled={disabled}
        value={draft ?? String(Math.round(shown))}
        onFocus={(event) => {
          setDraft(String(progress));
          event.currentTarget.select();
        }}
        onChange={(event) => setDraft(event.target.value)}
        onBlur={commit}
        onKeyDown={(event) => event.key === 'Enter' && event.currentTarget.blur()}
        aria-label={t('Введите прогресс {title}', { title: habit.title })}
      />
      <small>
        / {formatAmount(target, language)}
        {habit.unit ? ' ' + habit.unit : ''}
      </small>
    </span>
  );
}

/** «Выполнить» for check habits, − value + for quantity habits. */
export function HabitDayFooter({
  habit,
  day,
  today,
  busy,
  pop,
  big = false,
  onProgress,
}: {
  habit: Habit;
  day: string;
  today: string;
  busy: boolean;
  pop: boolean;
  big?: boolean;
  onProgress: (count: number) => void;
}) {
  const { t, language } = useI18n();
  const markable = habitCanMarkOn(habit, day, today);
  const progress = habitProgress(habit, day);
  const target = habitTarget(habit);
  const complete = progress >= target;
  const className =
    (big ? 'hb-do is-big' : 'hb-do') + (complete ? ' is-on' : '') + (pop ? ' is-pop' : '');
  if (!markable)
    return (
      <button type="button" className={className} disabled>
        {t(day > today ? 'Ещё не наступил' : 'Не по расписанию')}
      </button>
    );
  if (!habit.target)
    return (
      <button
        type="button"
        className={className}
        aria-pressed={complete}
        disabled={busy}
        onClick={() => onProgress(complete ? 0 : target)}
      >
        {complete && <Check size={15} strokeWidth={2.6} aria-hidden="true" />}
        {t(complete ? 'Выполнено' : 'Выполнить')}
      </button>
    );
  const step = habitStep(habit);
  const unit = habit.unit ? ' ' + habit.unit : '';
  return (
    <>
      <div className="hb-bar-row">
        <HabitBar fraction={habitDayFraction(habit, day)} />
      </div>
      <div
        className={'hb-qs' + (pop ? ' is-pop' : '')}
        role="group"
        aria-label={t('Прогресс {title}', { title: habit.title })}
      >
        <button
          type="button"
          disabled={busy || progress <= 0}
          aria-label={
            t('Уменьшить прогресс {title}', { title: habit.title }) +
            ` (${formatAmount(step, language)}${unit})`
          }
          onClick={() => onProgress(Math.max(0, progress - step))}
        >
          <Minus size={18} strokeWidth={2.4} aria-hidden="true" />
        </button>
        <ProgressInput habit={habit} progress={progress} disabled={busy} onCommit={onProgress} />
        <button
          type="button"
          className="is-plus"
          disabled={busy || progress >= target}
          aria-label={
            t('Увеличить прогресс {title}', { title: habit.title }) +
            ` (${formatAmount(step, language)}${unit})`
          }
          onClick={() => onProgress(Math.min(target, progress + step))}
        >
          <Plus size={18} strokeWidth={2.4} aria-hidden="true" />
        </button>
      </div>
    </>
  );
}

export function MilestoneChips({ earned }: { earned: readonly number[] }) {
  const { t } = useI18n();
  const next = HABIT_MILESTONES.find((milestone) => !earned.includes(milestone));
  return (
    <div className="hb-chips">
      {HABIT_MILESTONES.map((milestone) => {
        const done = earned.includes(milestone);
        return (
          <span
            key={milestone}
            className={'hb-chip' + (done ? ' is-on' : '') + (milestone === next ? ' is-next' : '')}
            title={t(milestone === 3 ? '{count} дня подряд' : '{count} дней подряд', {
              count: milestone,
            })}
          >
            {done && <Check size={12} strokeWidth={2.6} aria-hidden="true" />}
            <b>{milestone}</b>
          </span>
        );
      })}
    </div>
  );
}

const HEAT_WEEKS = 20;

/** Last 20 weeks, one column per week from Sunday. Interactive in the drawer. */
export function HabitHeat({
  habit,
  today,
  selected,
  onPick,
}: {
  habit: Habit;
  today: string;
  selected?: string;
  onPick?: (day: string) => void;
}) {
  const { t, language } = useI18n();
  const hint = useDayHint(habit, today);
  const grid = useRef<HTMLDivElement>(null);
  useCellsFade(grid);
  const start = addDays(habitWeek(today)[0], -(HEAT_WEEKS - 1) * 7);
  const days = Array.from({ length: HEAT_WEEKS * 7 }, (_, index) => addDays(start, index));
  return (
    <>
      <div
        ref={grid}
        className="hb-heat"
        role={onPick ? 'group' : 'img'}
        aria-label={t('Последние 20 недель')}
      >
        {days.map((day) => {
          const state = habitDayState(habit, day, today);
          const cellClass = 'hb-hm is-' + state + (day === selected ? ' is-sel' : '');
          const style = {
            '--p': `${Math.round(habitDayFraction(habit, day) * 100)}%`,
          } as CSSProperties;
          return onPick ? (
            <button
              key={day}
              type="button"
              className={cellClass}
              style={style}
              tabIndex={-1}
              disabled={state === 'future'}
              title={hint(day)}
              aria-label={hint(day)}
              onClick={() => onPick(day)}
            />
          ) : (
            <i key={day} className={cellClass} style={style} />
          );
        })}
      </div>
      <div className="hb-heat-cap">
        <span>{formatDate(start, { day: 'numeric', month: 'short' }, language)}</span>
        <span>{t('сегодня')}</span>
      </div>
    </>
  );
}

const LINE_W = 296;
const LINE_H = 84;
const LINE_DAYS = 14;

/** Daily progress of the last 14 days for quantity habits. */
export function HabitLine({ habit, today }: { habit: Habit; today: string }) {
  const { t, language } = useI18n();
  const svg = useRef<SVGSVGElement>(null);
  useLineDraw(svg);
  const target = habitTarget(habit);
  const x = (index: number) => 6 + (index * (LINE_W - 12)) / (LINE_DAYS - 1);
  const y = (value: number) => LINE_H - 8 - Math.min(1, value / target) * (LINE_H - 24);
  const points = Array.from({ length: LINE_DAYS }, (_, index) => {
    const day = addDays(today, index - (LINE_DAYS - 1));
    const value = habitScheduledOn(habit, day) || day === today ? habitProgress(habit, day) : 0;
    return [x(index), y(value)] as const;
  });
  const path = points
    .map(([px, py], index) => (index ? 'L' : 'M') + px.toFixed(1) + ' ' + py.toFixed(1))
    .join(' ');
  const last = points[points.length - 1];
  return (
    <>
      <svg
        ref={svg}
        className="hb-line"
        viewBox={`0 0 ${LINE_W} ${LINE_H}`}
        role="img"
        aria-label={t('Последние 14 дней')}
      >
        <line x1="0" x2={LINE_W} y1={y(target)} y2={y(target)} className="hb-line-goal" />
        <path
          d={`${path} L${last[0]} ${LINE_H - 8} L${points[0][0]} ${LINE_H - 8} Z`}
          className="hb-line-area"
        />
        <path d={path} className="hb-line-stroke" pathLength={1} />
        <circle cx={last[0]} cy={last[1]} r={4} className="hb-line-point" />
      </svg>
      <div className="hb-heat-cap">
        <span>{t('14 дней назад')}</span>
        <span>
          {t('цель')} {formatAmount(target, language)}
          {habit.unit ? ' ' + habit.unit : ''}
        </span>
      </div>
    </>
  );
}

/** A small stat: big number above a caption. */
export function Stat({ value, caption }: { value: ReactNode; caption: string }) {
  return (
    <div className="hb-stat">
      <b>{value}</b>
      <span>{caption}</span>
    </div>
  );
}

export { CountUp };
