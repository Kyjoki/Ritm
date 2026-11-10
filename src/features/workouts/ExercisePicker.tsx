import { useState, type CSSProperties } from 'react';
import { Search } from 'lucide-react';
import { Dialog } from '../../components/Dialog';
import { useI18n } from '../../lib/i18n';
import { createExercise, filterExercises } from './library';
import { MUSCLES, MUSCLE_TITLES, allExercises, type Exercise, type MuscleKey } from './model';
import { MuscleChip, muscleColor } from './parts';

type Filter = 'any' | 'none' | MuscleKey;

/** Search, muscle chips, own exercises (with a muscle group tag), and a creator for a new one. */
export function ExercisePicker({
  title,
  usedNote,
  used,
  custom,
  onPick,
  onCreated,
  onSetMuscle,
  onClose,
}: {
  title: string;
  usedNote: string;
  used: ReadonlySet<string>;
  custom: Exercise[];
  onPick: (exercise: Exercise) => void;
  onCreated: (exercise: Exercise) => void;
  onSetMuscle: (exerciseID: string, muscle: MuscleKey | null) => void;
  onClose: () => void;
}) {
  const { t, language } = useI18n();
  const [query, setQuery] = useState('');
  const [filter, setFilter] = useState<Filter>('any');
  const [newGroup, setNewGroup] = useState<MuscleKey | null>(null);
  const [tagging, setTagging] = useState<string | null>(null);
  const [notice, setNotice] = useState('');
  const everything = allExercises(custom, language);
  const rows = filterExercises(everything, query, filter);
  const ungrouped = custom.some((exercise) => !exercise.muscle);
  const key = query.trim();
  const canCreate =
    key.length >= 2 &&
    !everything.some((exercise) => exercise.name.toLowerCase() === key.toLowerCase());
  const isCustom = (id: string) => custom.some((exercise) => exercise.id === id);

  const create = () => {
    const made = createExercise(custom, query, newGroup);
    if (!made) return;
    if (!made.created) {
      setNotice(t('Это упражнение уже есть.'));
      return;
    }
    onCreated(made.exercise);
    onPick(made.exercise);
  };
  const chip = (value: Filter, label: string) => (
    <button
      key={value}
      type="button"
      className={`wk-gch${filter === value ? ' on' : ''}`}
      aria-pressed={filter === value}
      onClick={() => {
        setFilter(value);
        if (value !== 'any' && value !== 'none') setNewGroup(value);
      }}
    >
      {label}
    </button>
  );
  const groupChips = (
    selected: MuscleKey | null,
    onSelect: (muscle: MuscleKey | null) => void,
    none = false,
  ) => (
    <div className="wk-mchs">
      {MUSCLES.map((muscle) => (
        <button
          key={muscle}
          type="button"
          className={`wk-mch${selected === muscle ? ' on' : ''}`}
          style={{ '--mc': muscleColor(muscle) } as CSSProperties}
          aria-pressed={selected === muscle}
          onClick={() => onSelect(selected === muscle && !none ? null : muscle)}
        >
          {t(MUSCLE_TITLES[muscle])}
        </button>
      ))}
      {none ? (
        <button
          type="button"
          className={`wk-mch${selected === null ? ' on' : ''}`}
          onClick={() => onSelect(null)}
        >
          {t('Без группы')}
        </button>
      ) : null}
    </div>
  );

  return (
    <Dialog title={title} className="wkm" onClose={onClose}>
      <div className="wkp">
        <label className="wk-srch">
          <Search className="wk-i" aria-hidden="true" />
          <input
            value={query}
            placeholder={t('Поиск')}
            aria-label={t('Поиск')}
            autoComplete="off"
            spellCheck={false}
            onChange={(event) => {
              setQuery(event.target.value);
              setNotice('');
            }}
          />
        </label>
        <div className="wk-gchips">
          {chip('any', t('Все'))}
          {MUSCLES.map((muscle) => chip(muscle, t(MUSCLE_TITLES[muscle])))}
          {ungrouped || filter === 'none' ? chip('none', t('Без группы')) : null}
        </div>
        <div className="wkp-list">
          {rows.map((exercise) => {
            const taken = used.has(exercise.id);
            const own = isCustom(exercise.id);
            return (
              <div key={exercise.id}>
                <div className={`wkp-r${taken ? ' taken' : ''}`}>
                  <button
                    type="button"
                    className="nm"
                    disabled={taken}
                    onClick={() => onPick(exercise)}
                  >
                    {exercise.name}
                  </button>
                  {taken ? <span className="note">{usedNote}</span> : null}
                  {own ? (
                    exercise.muscle ? (
                      <button
                        type="button"
                        className="wk-mcb"
                        aria-label={t('Группа мышц: {name}', {
                          name: t(MUSCLE_TITLES[exercise.muscle]),
                        })}
                        onClick={() => setTagging(tagging === exercise.id ? null : exercise.id)}
                      >
                        <MuscleChip muscle={exercise.muscle} />
                      </button>
                    ) : (
                      <button
                        type="button"
                        className="wk-addg"
                        aria-label={t('Выбрать группу мышц для «{name}»', { name: exercise.name })}
                        onClick={() => setTagging(tagging === exercise.id ? null : exercise.id)}
                      >
                        {t('＋ группа')}
                      </button>
                    )
                  ) : taken ? null : (
                    <MuscleChip muscle={exercise.muscle} />
                  )}
                </div>
                {tagging === exercise.id ? (
                  <div className="wkp-tag">
                    {groupChips(
                      exercise.muscle,
                      (muscle) => {
                        onSetMuscle(exercise.id, muscle);
                        setTagging(null);
                      },
                      true,
                    )}
                  </div>
                ) : null}
              </div>
            );
          })}
          {rows.length ? null : <p className="wk-empty">{t('Ничего не найдено')}</p>}
          {canCreate ? (
            <div className="wkp-new">
              <div className="wk-lb tight">{t('Своё упражнение · группа мышц')}</div>
              {groupChips(newGroup, setNewGroup)}
              <button type="button" className="btn wide" onClick={create}>
                {t('Создать «{name}»', { name: key })}
              </button>
              {newGroup ? null : (
                <p className="wk-fine">
                  {t('Без группы упражнение не найдётся по фильтрам, группу можно выбрать позже.')}
                </p>
              )}
            </div>
          ) : null}
          {notice ? (
            <p className="wk-fine" role="status">
              {notice}
            </p>
          ) : null}
        </div>
      </div>
    </Dialog>
  );
}
