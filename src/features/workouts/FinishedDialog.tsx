import { Check, Star } from 'lucide-react';
import type { Habit } from '../../../shared/types';
import { Dialog } from '../../components/Dialog';
import { useI18n } from '../../lib/i18n';
import { habitCompleteOn } from '../habit-utils';
import { dateKey } from './dates';
import { decimal, durationText, kgText, longDate, NBSP } from './format';
import { muscleOf, type Exercise, type Program, type WorkoutRecord } from './model';
import { MuscleChip, gradientOf, letterOf } from './parts';
import {
  bestSetIndex,
  exerciseVolume,
  recordDuration,
  recordSetCount,
  recordSets,
  recordVolume,
} from './stats';

/** A finished workout in detail: the three numbers, every exercise with its sets, records marked. */
export function FinishedDialog({
  record,
  history,
  program,
  custom,
  habit,
  timeZone,
  nameOf,
  onRepeat,
  onClose,
}: {
  record: WorkoutRecord;
  history: WorkoutRecord[];
  program: Program | null;
  custom: Exercise[];
  habit: Habit | null;
  timeZone: string;
  nameOf: (exerciseID: string, fallback: string) => string;
  onRepeat: (programID: string) => void;
  onClose: () => void;
}) {
  const { t, language } = useI18n();
  const name = record.programName || t('Тренировка');
  const records = recordSets(record, history);
  const day = dateKey(record.endedAt, timeZone);
  const ticked = habit && !habit.archived && habitCompleteOn(habit, day);
  const gradient = program
    ? program.colorIndex
    : [...record.programID].reduce((sum, char) => (sum + char.charCodeAt(0)) % 6, 0);
  return (
    <Dialog title={name} className="wkm wk-bare" onClose={onClose}>
      <div className="wkf-hd" style={{ background: gradientOf(gradient) }}>
        <div className="top">
          <span className="tl">{letterOf(name)}</span>
          <div>
            <h2>{name}</h2>
            <span>{longDate(day, language)}</span>
          </div>
        </div>
        <div className="tiles">
          <div>
            <b>{durationText(recordDuration(record), language)}</b>
            <small>{t('Длительность')}</small>
          </div>
          <div>
            <b>{kgText(recordVolume(record), language)}</b>
            <small>{t('Объём')}</small>
          </div>
          <div>
            <b>{recordSetCount(record)}</b>
            <small>{t('Подходов')}</small>
          </div>
        </div>
      </div>
      <div className="wkf-body">
        {record.exercises.map((exercise) => {
          const best = bestSetIndex(exercise.sets);
          const recordIndex = records[exercise.exerciseID];
          return (
            <section className="panel wkx" key={exercise.exerciseID}>
              <div className="hd">
                <div>
                  <b>{nameOf(exercise.exerciseID, exercise.name)}</b>
                  <MuscleChip muscle={muscleOf(exercise.exerciseID, custom)} />
                </div>
                <div className="vl">
                  <b>{kgText(exerciseVolume(exercise), language)}</b>
                  <small>{t('объём')}</small>
                </div>
              </div>
              {exercise.sets.map((set, index) => {
                const isRecord = recordIndex === index;
                const isBest = index === best && (exercise.sets.length > 1 || isRecord);
                return (
                  <div className={`wkr${isBest ? ' best' : ''}`} key={index}>
                    <span className="n">{index + 1}</span>
                    <span className="v">
                      {decimal(set.weight, language)}
                      {NBSP}
                      {language === 'en' ? 'kg' : 'кг'} × {set.reps}
                    </span>
                    {isRecord ? (
                      <span className="rec">
                        <Star className="wk-i" aria-hidden="true" />
                        {t('Рекорд')}
                      </span>
                    ) : null}
                  </div>
                );
              })}
            </section>
          );
        })}
        {ticked ? (
          <div className="panel wkf-hab">
            <span className="st">
              <Check className="wk-i" aria-hidden="true" />
            </span>
            <b>{t('Привычка «{title}» отмечена', { title: habit.title })}</b>
          </div>
        ) : null}
        <div className="wkm-btns">
          {program ? (
            <button
              type="button"
              className="btn primary wide"
              onClick={() => {
                onClose();
                onRepeat(program.id);
              }}
            >
              {t('Повторить тренировку')}
            </button>
          ) : null}
          <button type="button" className="btn wide" onClick={onClose}>
            {t('Закрыть')}
          </button>
        </div>
      </div>
    </Dialog>
  );
}
