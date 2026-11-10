import { useState } from 'react';
import { ChevronRight, Flame, Link2, Pencil, Play, Plus, SlidersHorizontal } from 'lucide-react';
import type { Habit } from '../../../shared/types';
import { useI18n } from '../../lib/i18n';
import { dateKey } from './dates';
import {
  decimal,
  durationText,
  kgText,
  relativeDay,
  shortDate,
  tonsText,
  weekdayShort,
} from './format';
import { estimatedMinutes, lastDoneAt, nextProgram } from './library';
import type { Program, RecordCard, WorkoutRecord } from './model';
import { Ring, SectionHeading, gradientOf, letterOf } from './parts';
import {
  pendingWeek,
  recordDuration,
  recordVolume,
  resolveRecords,
  streakWeeks,
  volumeTrend,
  weekState,
} from './stats';
import type { WorkoutsState } from './client';

export interface HomeProps {
  state: WorkoutsState;
  habits: Habit[];
  habitsReady: boolean;
  today: string;
  timeZone: string;
  running: { programName: string; done: number; total: number; elapsed: string } | null;
  muscleNames: (program: Program) => string[];
  nameOf: (exerciseID: string, fallback: string) => string;
  onOpen: (id: string) => void;
  onStart: (id: string) => void;
  onEdit: (id: string) => void;
  onNew: () => void;
  onSettings: () => void;
  onResume: () => void;
  onRecord: (card: RecordCard | null) => void;
  onHistory: (record: WorkoutRecord) => void;
}

function Hero(props: HomeProps) {
  const { t, language } = useI18n();
  const { state, habits, today, timeZone } = props;
  const linked = habits.find(
    (habit) => habit.id === state.settings.linkedHabitID && !habit.archived,
  );
  const week =
    state.settings.linkedHabitID && !linked && !props.habitsReady
      ? pendingWeek(today)
      : weekState(linked ?? null, state.records, today, timeZone);
  const trend = volumeTrend(state.records, today, timeZone);
  const streak = streakWeeks(state.records, today, timeZone);
  return (
    <section className="panel wk-hero">
      <div className="wk-hero-top">
        <button
          type="button"
          className="wk-hchip"
          onClick={props.onSettings}
          aria-label={t('Связь с привычкой')}
        >
          <Link2 className="wk-i" aria-hidden="true" />
          <span>
            {week.habitTitle ? `${week.habitTitle} · ${t('привычка')}` : t('Без привычки')}
          </span>
        </button>
        <button
          type="button"
          className="wk-ib"
          onClick={props.onSettings}
          aria-label={t('Настройки тренировок')}
        >
          <SlidersHorizontal className="wk-i" aria-hidden="true" />
        </button>
      </div>
      <div className="wk-hero-main">
        <Ring fraction={week.goal ? week.done / week.goal : 0}>
          <b>
            {week.done}/{week.goal}
          </b>
          <small>{t('на неделе')}</small>
        </Ring>
        <div className="wk-stats">
          <div>
            <small>{t('Объём за неделю')}</small>
            <b>{tonsText(trend.volume, language)}</b>
            {trend.percent ? (
              <em className={trend.percent > 0 ? 'up' : 'dn'}>
                {trend.percent > 0 ? '▲ ' : '▼ '}
                {Math.abs(trend.percent)}%
              </em>
            ) : null}
          </div>
          <div>
            <small>{t('Серия')}</small>
            <b className="fl">
              <Flame className="wk-i" aria-hidden="true" />
              {streak} {t('нед.')}
            </b>
          </div>
        </div>
      </div>
      <div className="wk-strip">
        {week.days.map((day) => (
          <div
            key={day.key}
            className={`d${day.isDone ? ' on' : ''}${day.isToday ? ' today' : ''}`}
          >
            <i style={{ height: day.isDone ? 34 : day.isToday ? 22 : 6 }} />
            <span>{weekdayShort(day.key, language)}</span>
          </div>
        ))}
      </div>
    </section>
  );
}

function NextCard(props: HomeProps) {
  const { t, language } = useI18n();
  const { state, today, timeZone } = props;
  const program = nextProgram(state.programs, state.records);
  if (!program) return null;
  const last = lastDoneAt(state.records, program.id);
  const lastText = last
    ? relativeDay(dateKey(last, timeZone), today, language, t, true)
    : t('ещё не было');
  return (
    <section className="wk-next" style={{ background: gradientOf(program.colorIndex) }}>
      <small>{t('Следующая тренировка')}</small>
      <h3>{program.name}</h3>
      <div className="chs">
        {props.muscleNames(program).map((name) => (
          <span key={name}>{name}</span>
        ))}
      </div>
      <p>
        {program.items.length} {t('упр.')} · ≈{estimatedMinutes(program)} {t('мин')} ·{' '}
        {t('Последний раз')} {lastText}
      </p>
      <div className="row">
        <button type="button" className="wk-go" onClick={() => props.onStart(program.id)}>
          <Play className="wk-i" aria-hidden="true" />
          {t('Начать')}
        </button>
        <button type="button" className="wk-glassw" onClick={() => props.onOpen(program.id)}>
          {t('Открыть')}
        </button>
        <button type="button" className="wk-glassw" onClick={() => props.onEdit(program.id)}>
          <Pencil className="wk-i" aria-hidden="true" />
          {t('Изменить')}
        </button>
      </div>
    </section>
  );
}

export function ProgramRow({
  program,
  ...props
}: Pick<HomeProps, 'onOpen' | 'onStart' | 'onEdit'> & { program: Program }) {
  const { t } = useI18n();
  return (
    <div
      className="wk-pc"
      role="button"
      tabIndex={0}
      style={{ background: gradientOf(program.colorIndex) }}
      onClick={() => props.onOpen(program.id)}
      onKeyDown={(event) => {
        if (event.target === event.currentTarget && (event.key === 'Enter' || event.key === ' ')) {
          event.preventDefault();
          props.onOpen(program.id);
        }
      }}
    >
      <span className="l">{letterOf(program.name)}</span>
      <span className="tx">
        <b>{program.name}</b>
        <small>
          {program.items.length} {t('упр.')} · ≈{estimatedMinutes(program)} {t('мин')}
        </small>
      </span>
      <button
        type="button"
        className="ed"
        onClick={(event) => {
          event.stopPropagation();
          props.onEdit(program.id);
        }}
      >
        <Pencil className="wk-i" aria-hidden="true" />
        <span>{t('Изменить')}</span>
      </button>
      <button
        type="button"
        className="pl"
        aria-label={t('Начать тренировку «{name}»', { name: program.name })}
        onClick={(event) => {
          event.stopPropagation();
          props.onStart(program.id);
        }}
      >
        <Play className="wk-i" aria-hidden="true" />
      </button>
    </div>
  );
}

export function HistoryRow({
  record,
  today,
  timeZone,
  onOpen,
}: {
  record: WorkoutRecord;
  today: string;
  timeZone: string;
  onOpen: (record: WorkoutRecord) => void;
}) {
  const { t, language } = useI18n();
  const name = record.programName || t('Тренировка');
  return (
    <button type="button" className="wk-hi" onClick={() => onOpen(record)}>
      <span className="tl">{letterOf(name)}</span>
      <span className="tx">
        <b>{name}</b>
        <small>
          {relativeDay(dateKey(record.endedAt, timeZone), today, language, t)} ·{' '}
          {durationText(recordDuration(record), language)} · {record.exercises.length} {t('упр.')}
        </small>
      </span>
      <span className="v">{kgText(recordVolume(record), language)}</span>
      <ChevronRight className="wk-i ch" aria-hidden="true" />
    </button>
  );
}

function Records(props: HomeProps) {
  const { t, language } = useI18n();
  const cards = resolveRecords(props.state.records, props.state.bests);
  return (
    <>
      <SectionHeading title={t('Рекорды')} />
      <div className="wk-recs">
        {cards.map((card) => (
          <button
            key={card.exerciseID}
            type="button"
            className="panel wk-rc"
            onClick={() => props.onRecord(card)}
          >
            <small>{props.nameOf(card.exerciseID, card.name)}</small>
            <b>
              {decimal(card.weight, language)}
              <i>{language === 'en' ? 'kg' : 'кг'}</i>
            </b>
            <em>
              × {card.reps} · ★ {shortDate(dateKey(card.date, props.timeZone), language)}
            </em>
          </button>
        ))}
        <button type="button" className="wk-dash" onClick={() => props.onRecord(null)}>
          <Plus className="wk-i" aria-hidden="true" />
          {t('Рекорд')}
        </button>
      </div>
    </>
  );
}

function History(props: HomeProps) {
  const { t } = useI18n();
  const [all, setAll] = useState(false);
  const records = props.state.records;
  const list = all ? records : records.slice(0, 5);
  return (
    <>
      <SectionHeading
        title={t('История')}
        action={
          records.length > 5 ? (
            <button type="button" className="wk-lnk" onClick={() => setAll(!all)}>
              {all ? t('Свернуть') : t('Вся история')}
            </button>
          ) : undefined
        }
      />
      {list.length ? (
        <div className="wk-hist">
          {list.map((record) => (
            <HistoryRow
              key={record.id}
              record={record}
              today={props.today}
              timeZone={props.timeZone}
              onOpen={props.onHistory}
            />
          ))}
        </div>
      ) : (
        <p className="wk-empty">{t('Пока нет завершённых тренировок.')}</p>
      )}
    </>
  );
}

export function HomeView(props: HomeProps) {
  const { t } = useI18n();
  const next = nextProgram(props.state.programs, props.state.records);
  const rest = props.state.programs.filter((program) => program.id !== next?.id);
  return (
    <>
      <h1 className="gradient-title wk-ptitle">{t('Тренировки')}</h1>
      {props.running ? (
        <button type="button" className="wk-cont" onClick={props.onResume}>
          <span className="tx">
            <small>{t('Продолжить тренировку')}</small>
            <b>{props.running.programName}</b>
            <span>
              {t('{done} из {total} подходов', {
                done: props.running.done,
                total: props.running.total,
              })}{' '}
              · {props.running.elapsed}
            </span>
          </span>
          <span className="rb">
            <Play className="wk-i" aria-hidden="true" />
          </span>
        </button>
      ) : null}
      <div className="wk-cols">
        <div className="wk-l">
          <Hero {...props} />
          <NextCard {...props} />
          <SectionHeading title={t('Программы')} />
          <div className="wk-plist">
            {rest.map((program) => (
              <ProgramRow
                key={program.id}
                program={program}
                onOpen={props.onOpen}
                onStart={props.onStart}
                onEdit={props.onEdit}
              />
            ))}
            <button type="button" className="wk-dash row" onClick={props.onNew}>
              <Plus className="wk-i" aria-hidden="true" />
              {t('Новая программа')}
            </button>
          </div>
        </div>
        <div className="wk-r">
          <Records {...props} />
          <History {...props} />
        </div>
      </div>
    </>
  );
}
