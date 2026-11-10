import { Medal, Trophy } from 'lucide-react';
import type { Habit } from '../../../shared/types';
import { formatDate } from '../../lib/date';
import { useI18n } from '../../lib/i18n';
import type { HabitMilestoneEvent } from '../habit-utils';
import { CountUp, HabitBar } from './habit-motion';
import { daysInRow, fillTemplate } from './habit-format';
import { HabitIconView, habitStyle } from './habit-parts';

/** Records and milestones show from this streak length, so a three-day run is not a headline. */
export const AWARD_MIN_MILESTONE = 7;
const AWARD_LIMIT = 6;
const GOAL_LIMIT = 3;

export interface HabitAwardRow {
  habit: Habit;
  current: number;
  best: number;
  next: number | null;
  events: HabitMilestoneEvent[];
}

export function HabitAwards({
  rows,
  onOpen,
}: {
  rows: readonly HabitAwardRow[];
  onOpen: (habit: Habit) => void;
}) {
  const { t, language } = useI18n();
  const records = [...rows].sort((a, b) => b.best - a.best);
  const longest = Math.max(1, ...records.map((row) => row.best));
  const achievements = rows
    .flatMap((row) =>
      row.events
        .filter((event) => event.milestone >= AWARD_MIN_MILESTONE)
        .map((event) => ({ row, event })),
    )
    .sort((a, b) => (a.event.date < b.event.date ? 1 : a.event.date > b.event.date ? -1 : 0))
    .slice(0, AWARD_LIMIT);
  const goals = rows
    .filter((row) => row.next)
    .sort((a, b) => a.next! - a.current - (b.next! - b.current))
    .slice(0, GOAL_LIMIT);
  return (
    <aside className="hb-rewards" aria-labelledby="habit-awards-title">
      <div className="hb-rewards-head">
        <span className="hb-tic">
          <Trophy size={18} aria-hidden="true" />
        </span>
        <h2 id="habit-awards-title">{t('Награды')}</h2>
      </div>
      <h3>{t('Рекорды серий')}</h3>
      <ul className="hb-records">
        {records.map((row, index) => (
          <li key={row.habit.id} style={habitStyle(row.habit)}>
            <button type="button" onClick={() => onOpen(row.habit)}>
              <HabitIconView icon={row.habit.icon} size={15} />
              <span className="hb-name">{row.habit.title}</span>
              <HabitBar fraction={row.best / longest} index={index} />
              <b>
                <CountUp value={row.best} />
              </b>
            </button>
          </li>
        ))}
      </ul>
      <h3>{t('Достижения')}</h3>
      {achievements.length ? (
        <ol className="hb-timeline">
          {achievements.map(({ row, event }) => (
            <li key={row.habit.id + event.milestone} style={habitStyle(row.habit)}>
              <button type="button" onClick={() => onOpen(row.habit)}>
                <span className="hb-node">
                  <Medal size={14} strokeWidth={2} aria-hidden="true" />
                </span>
                <div>
                  <b>{daysInRow(event.milestone, t)}</b>
                  <small>
                    {row.habit.title} ·{' '}
                    {formatDate(event.date, { day: 'numeric', month: 'short' }, language)}
                  </small>
                </div>
              </button>
            </li>
          ))}
        </ol>
      ) : (
        <p className="hb-rewards-empty">
          {t('Достижения появятся, когда серия дойдёт до {count} дней.', {
            count: AWARD_MIN_MILESTONE,
          })}
        </p>
      )}
      {goals.length > 0 && (
        <>
          <h3>{t('Ближайшие цели')}</h3>
          <ul className="hb-goals">
            {goals.map((row, index) => (
              <li key={row.habit.id} style={habitStyle(row.habit)}>
                <button type="button" onClick={() => onOpen(row.habit)}>
                  <div>
                    <b>{row.habit.title}</b>
                    <small>
                      {fillTemplate(t('{current} из {next} дн.'), {
                        current: <CountUp value={row.current} />,
                        next: row.next,
                      })}
                    </small>
                  </div>
                  <HabitBar fraction={row.current / row.next!} index={index} />
                </button>
              </li>
            ))}
          </ul>
        </>
      )}
    </aside>
  );
}
