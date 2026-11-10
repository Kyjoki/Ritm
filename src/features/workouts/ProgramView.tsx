import { ChevronLeft, Pencil, Play } from 'lucide-react';
import { useI18n } from '../../lib/i18n';
import { dateKey } from './dates';
import { decimal, NBSP, relativeDay } from './format';
import { HistoryRow } from './HomeView';
import { estimatedMinutes, lastDoneAt, totalSets } from './library';
import type { Program, WorkoutRecord } from './model';
import { MuscleChip, SectionHeading, gradientOf, letterOf } from './parts';
import { lastResult } from './stats';
import type { WorkoutsState } from './client';
import { muscleOf } from './model';

export interface ProgramViewProps {
  program: Program;
  state: WorkoutsState;
  today: string;
  timeZone: string;
  running: boolean;
  muscleNames: (program: Program) => string[];
  nameOf: (exerciseID: string, fallback: string) => string;
  onBack: () => void;
  onEdit: () => void;
  onStart: () => void;
  onHistory: (record: WorkoutRecord) => void;
}

export function ProgramView(props: ProgramViewProps) {
  const { t, language } = useI18n();
  const { program, state } = props;
  const last = lastDoneAt(state.records, program.id);
  const lastText = last
    ? relativeDay(dateKey(last, props.timeZone), props.today, language, t, true)
    : t('ещё не было');
  const recent = state.records.filter((record) => record.programID === program.id).slice(0, 3);
  const weightText = (exerciseID: string) => {
    const result = lastResult(state.records, exerciseID);
    if (!result) return '—';
    const top = Math.max(...result.sets.map((set) => set.weight));
    return top > 0
      ? `${decimal(top, language)}${NBSP}${language === 'en' ? 'kg' : 'кг'}`
      : t('свой вес');
  };
  return (
    <>
      <div className="wk-bar">
        <button type="button" className="wk-ib" onClick={props.onBack} aria-label={t('Назад')}>
          <ChevronLeft className="wk-i" aria-hidden="true" />
        </button>
        <h2>{t('Программа')}</h2>
        <button type="button" className="btn sm" onClick={props.onEdit}>
          <Pencil className="wk-i wk-tiny" aria-hidden="true" />
          {t('Изменить')}
        </button>
      </div>
      <div className="wk-cols wk-pcols">
        <div className="wk-l">
          <section className="wk-phero" style={{ background: gradientOf(program.colorIndex) }}>
            <span className="tl">{letterOf(program.name)}</span>
            <h1>{program.name}</h1>
            <div className="chs">
              {props.muscleNames(program).map((name) => (
                <span key={name}>{name}</span>
              ))}
            </div>
            <div className="mt">
              <div>
                <b>≈{estimatedMinutes(program)}</b>
                <small>{t('минут')}</small>
              </div>
              <div>
                <b>{program.items.length}</b>
                <small>{t('упражнений')}</small>
              </div>
              <div>
                <b>{totalSets(program)}</b>
                <small>{t('подходов')}</small>
              </div>
            </div>
            <p>
              {t('Последний раз')} · {lastText}
            </p>
            <button type="button" className="wk-cta" onClick={props.onStart}>
              <Play className="wk-i" aria-hidden="true" />
              {props.running ? t('Продолжить тренировку') : t('Начать тренировку')}
            </button>
          </section>
        </div>
        <div className="wk-r">
          <SectionHeading title={t('Упражнения')} />
          <div className="panel wk-plist2">
            {program.items.length ? (
              program.items.map((item, index) => (
                <div className="wk-px" key={item.id}>
                  <span className="n">{index + 1}</span>
                  <div className="tx">
                    <b>{props.nameOf(item.exerciseID, t('Упражнение'))}</b>
                    <MuscleChip muscle={muscleOf(item.exerciseID, state.custom)} />
                  </div>
                  <div className="rt">
                    <b>
                      {item.sets} × {item.reps}
                    </b>
                    <small>{weightText(item.exerciseID)}</small>
                  </div>
                </div>
              ))
            ) : (
              <p className="wk-empty">{t('В программе пока нет упражнений.')}</p>
            )}
          </div>
          {recent.length ? (
            <>
              <SectionHeading title={t('Последние тренировки')} />
              <div className="wk-hist">
                {recent.map((record) => (
                  <HistoryRow
                    key={record.id}
                    record={record}
                    today={props.today}
                    timeZone={props.timeZone}
                    onOpen={props.onHistory}
                  />
                ))}
              </div>
            </>
          ) : null}
        </div>
      </div>
    </>
  );
}
