import type { CSSProperties, ReactNode } from 'react';
import { BarChart3, Check, Flame, Trophy } from 'lucide-react';
import { useI18n } from '../../lib/i18n';
import { CountUp, HabitBar, HabitSparkBar } from './habit-motion';
import { fillTemplate } from './habit-format';

export interface HabitKpiData {
  todayDone: number;
  todayPlanned: number;
  currentStreak: number;
  bestStreak: number;
  rate: number;
  /** Percentage points against the previous period, null when there is nothing to compare. */
  delta: number | null;
  daily: { day: string; progress: number | null }[];
  today: string;
}

const SPARK_EMPTY_SHARE = 6;
const SPARK_MIN_SHARE = 8;

function Kpi({
  index,
  icon,
  label,
  value,
  sub,
  extra,
}: {
  index: number;
  icon: ReactNode;
  label: string;
  value: ReactNode;
  sub: ReactNode;
  extra?: ReactNode;
}) {
  return (
    <div className="hb-kpi hb-b" style={{ '--i': index } as CSSProperties}>
      <div className="hb-kpi-head">
        <span className="hb-tic">{icon}</span>
        <p>{label}</p>
      </div>
      <b>{value}</b>
      <small>{sub}</small>
      {extra}
    </div>
  );
}

export function HabitKpis({ data }: { data: HabitKpiData }) {
  const { t } = useI18n();
  const { todayDone, todayPlanned, currentStreak, bestStreak, rate, delta, daily, today } = data;
  const streakNote =
    currentStreak > 0 && currentStreak >= bestStreak
      ? t('новый рекорд')
      : bestStreak > currentStreak
        ? fillTemplate(t('до рекорда {count}'), {
            count: <CountUp value={bestStreak - currentStreak} />,
          })
        : '';
  return (
    <div className="hb-kpis">
      <Kpi
        index={1}
        icon={<Check size={18} aria-hidden="true" />}
        label={t('Сегодня выполнено')}
        value={
          <>
            <CountUp value={todayDone} />
            <small>
              /<CountUp value={todayPlanned} />
            </small>
          </>
        }
        sub={todayPlanned ? t('по расписанию') : t('Нет запланированных привычек')}
        extra={<HabitBar fraction={todayPlanned ? todayDone / todayPlanned : 0} />}
      />
      <Kpi
        index={2}
        icon={<Flame size={18} aria-hidden="true" />}
        label={t('Текущая серия')}
        value={
          <>
            <CountUp value={currentStreak} />
            <small> {t('дн.')}</small>
          </>
        }
        sub={streakNote}
      />
      <Kpi
        index={3}
        icon={<Trophy size={18} aria-hidden="true" />}
        label={t('Лучшая серия')}
        value={
          <>
            <CountUp value={bestStreak} />
            <small> {t('дн.')}</small>
          </>
        }
        sub={t('за всё время')}
      />
      <Kpi
        index={4}
        icon={<BarChart3 size={18} aria-hidden="true" />}
        label={t('Выполнение')}
        value={
          <>
            <CountUp value={rate} />
            <small>%</small>
          </>
        }
        sub={
          delta === null
            ? ''
            : fillTemplate(t('{sign}{count} п.п. к прошлому'), {
                sign: delta >= 0 ? '+' : '−',
                count: <CountUp value={Math.abs(delta)} />,
              })
        }
        extra={
          <div className="hb-spark" aria-hidden="true">
            {daily.map((entry, index) => (
              <HabitSparkBar
                key={entry.day}
                fraction={
                  (entry.progress === null
                    ? SPARK_EMPTY_SHARE
                    : Math.max(SPARK_MIN_SHARE, entry.progress)) / 100
                }
                index={index}
                today={entry.day === today}
              />
            ))}
          </div>
        }
      />
    </div>
  );
}
