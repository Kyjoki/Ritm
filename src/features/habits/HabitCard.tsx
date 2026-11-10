import type { CSSProperties } from 'react';
import { Archive, Pencil, RotateCcw, Trash2 } from 'lucide-react';
import type { Habit } from '../../../shared/types';
import { useI18n } from '../../lib/i18n';
import { habitPeriodSummary, habitWeek } from '../habit-utils';
import { CountUp, HabitRing } from './habit-motion';
import { fillTemplate, scheduleText } from './habit-format';
import {
  HabitDayFooter,
  HabitDayTiles,
  HabitHeat,
  HabitIconChip,
  HabitLine,
  habitStyle,
  Stat,
} from './habit-parts';

export interface HabitCardData {
  habit: Habit;
  current: number;
  best: number;
  next: number | null;
}

export function HabitCard({
  data,
  index,
  day,
  today,
  busy,
  popKey,
  record,
  onOpen,
  onEdit,
  onArchive,
  onDelete,
  onProgress,
}: {
  data: HabitCardData;
  index: number;
  day: string;
  today: string;
  busy: boolean;
  popKey: string | null;
  record: boolean;
  onOpen: (habit: Habit) => void;
  onEdit: (habit: Habit) => void;
  onArchive: (habit: Habit, archived: boolean) => void;
  onDelete: (habit: Habit) => void;
  onProgress: (habit: Habit, day: string, count: number) => void;
}) {
  const { t, language } = useI18n();
  const { habit, current, best, next } = data;
  const archived = Boolean(habit.archived);
  const week = habitPeriodSummary([habit], habitWeek(day), today);
  const complete = habit.completedDates.includes(day);
  const sub = archived
    ? t('В архиве')
    : week.planned
      ? fillTemplate(t('{done} из {total} на неделе'), {
          done: <CountUp value={week.completed} />,
          total: <CountUp value={week.planned} />,
        })
      : scheduleText(habit, t, language);
  return (
    <article
      className={
        'hb-card' + (complete && !archived ? ' is-done' : '') + (record ? ' is-record' : '')
      }
      style={
        {
          ...habitStyle(habit),
          '--i': Math.min(5 + index, 7),
          '--j': Math.min(index, 7),
        } as CSSProperties
      }
      data-motion-key={habit.id}
    >
      <header>
        <button
          type="button"
          className="hb-idb"
          aria-label={t('Открыть «{title}»', { title: habit.title })}
          onClick={() => onOpen(habit)}
        >
          <HabitIconChip habit={habit} size={46} />
        </button>
        <div className="hb-tx">
          <h3>
            <button type="button" onClick={() => onOpen(habit)}>
              {habit.title}
            </button>
          </h3>
          <p>{sub}</p>
          <div className="hb-meta">{scheduleText(habit, t, language)}</div>
        </div>
        {!archived && (
          <HabitRing
            count={current}
            fraction={next ? current / next : 1}
            size={60}
            label={t('дн.')}
          />
        )}
      </header>
      <div className="hb-acts">
        <button
          type="button"
          aria-label={t('Редактировать привычку {title}', { title: habit.title })}
          onClick={() => onEdit(habit)}
        >
          <Pencil size={16} aria-hidden="true" />
        </button>
        <button
          type="button"
          disabled={busy}
          aria-label={t(
            archived ? 'Восстановить привычку {title}' : 'Архивировать привычку {title}',
            { title: habit.title },
          )}
          onClick={() => onArchive(habit, !archived)}
        >
          {archived ? (
            <RotateCcw size={16} aria-hidden="true" />
          ) : (
            <Archive size={16} aria-hidden="true" />
          )}
        </button>
        {archived && (
          <button
            type="button"
            aria-label={t('Удалить привычку {title}', { title: habit.title })}
            onClick={() => onDelete(habit)}
          >
            <Trash2 size={16} aria-hidden="true" />
          </button>
        )}
      </div>
      {archived ? (
        <div className="hb-card-foot">
          <Stat value={<CountUp value={best} />} caption={t('рекорд, дн.')} />
          <button
            type="button"
            className="hb-btn"
            disabled={busy}
            onClick={() => onArchive(habit, false)}
          >
            <RotateCcw size={16} aria-hidden="true" />
            {t('Вернуть')}
          </button>
        </div>
      ) : (
        <>
          <div className="hb-chart">
            {habit.target ? (
              <HabitLine habit={habit} today={today} />
            ) : (
              <HabitHeat habit={habit} today={today} />
            )}
          </div>
          <HabitDayTiles
            habit={habit}
            day={day}
            today={today}
            busy={busy}
            popKey={popKey}
            onToggle={(date, done) => onProgress(habit, date, done ? 0 : (habit.target ?? 1))}
          />
          <div className="hb-foot">
            <HabitDayFooter
              habit={habit}
              day={day}
              today={today}
              busy={busy}
              pop={popKey === habit.id + '|' + day}
              onProgress={(count) => onProgress(habit, day, count)}
            />
          </div>
          <div className="hb-stats">
            <Stat value={<CountUp value={best} />} caption={t('рекорд, дн.')} />
            <Stat value={next ? <CountUp value={next} /> : '—'} caption={t('цель, дн.')} />
          </div>
        </>
      )}
    </article>
  );
}
