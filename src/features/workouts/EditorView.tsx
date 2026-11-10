import { GripVertical, Plus, Trash2, X } from 'lucide-react';
import { useI18n } from '../../lib/i18n';
import { clampName } from './codec';
import {
  canSaveDraft,
  canStepItem,
  fieldValue,
  stepItem,
  withColor,
  withMovedItem,
  withName,
  withoutItem,
  type Draft,
} from './library';
import { COLOR_COUNT, NAME_LIMIT, muscleOf, type Exercise, type MuscleKey } from './model';
import { MuscleChip, PlanStepper, gradientOf, letterOf } from './parts';
import { MUSCLE_TITLES } from './model';
import { NBSP } from './format';
import { useReorder } from './useReorder';

export interface EditorProps {
  isNew: boolean;
  draft: Draft;
  custom: Exercise[];
  nameOf: (exerciseID: string, fallback: string) => string;
  onChange: (draft: Draft) => void;
  onAdd: () => void;
  onSave: () => void;
  onCancel: () => void;
  onDelete: () => void;
}

function Preview({ draft, custom }: { draft: Draft; custom: Exercise[] }) {
  const { t } = useI18n();
  const muscles = [
    ...new Set(
      draft.items
        .map((item) => muscleOf(item.exerciseID, custom))
        .filter((m): m is MuscleKey => m !== null),
    ),
  ];
  const sets = draft.items.reduce((total, item) => total + item.sets, 0);
  const name = clampName(draft.name);
  return (
    <div className="wk-eprev" style={{ background: gradientOf(draft.colorIndex) }}>
      <span className="l">{letterOf(name)}</span>
      <b>{name || t('Название программы')}</b>
      <small>
        {draft.items.length} {t('упр.')} · ≈{sets * 4 + 3} {t('мин')}
        {muscles.length
          ? ` · ${muscles
              .slice(0, 3)
              .map((m) => t(MUSCLE_TITLES[m]))
              .join(', ')}`
          : ''}
      </small>
    </div>
  );
}

export function EditorView(props: EditorProps) {
  const { t } = useI18n();
  const { draft, onChange } = props;
  const { list, gripProps } = useReorder((from, to) => onChange(withMovedItem(draft, from, to)));
  return (
    <>
      <div className="wk-bar">
        <button type="button" className="wk-lnk big" onClick={props.onCancel}>
          {t('Отмена')}
        </button>
        <h2>{props.isNew ? t('Новая программа') : t('Изменить')}</h2>
        <button
          type="button"
          className="btn primary"
          disabled={!canSaveDraft(draft)}
          onClick={props.onSave}
        >
          {t('Сохранить')}
        </button>
      </div>
      <div className="wk-cols wk-ecols">
        <div className="wk-l">
          <section className="panel wk-ef">
            <label className="wk-lb" htmlFor="wkName">
              {t('Название')}
            </label>
            <input
              className="wk-inp"
              id="wkName"
              value={draft.name}
              placeholder={t('Название программы')}
              maxLength={NAME_LIMIT}
              autoComplete="off"
              onChange={(event) => onChange(withName(draft, event.target.value))}
            />
            <div className="wk-lb">{t('Цвет')}</div>
            <div className="wk-sws">
              {Array.from({ length: COLOR_COUNT }, (_, index) => (
                <button
                  key={index}
                  type="button"
                  className={`wk-sw${draft.colorIndex === index ? ' on' : ''}`}
                  style={{ background: gradientOf(index) }}
                  aria-label={t('Цвет {number}', { number: index + 1 })}
                  aria-pressed={draft.colorIndex === index}
                  onClick={() => onChange(withColor(draft, index))}
                />
              ))}
            </div>
          </section>
          <Preview draft={draft} custom={props.custom} />
          {!props.isNew ? (
            <button type="button" className="btn wide danger" onClick={props.onDelete}>
              <Trash2 className="wk-i wk-tiny" aria-hidden="true" />
              {t('Удалить программу')}
            </button>
          ) : null}
        </div>
        <div className="wk-r">
          <div className="wk-sh">
            <h2>
              {t('Упражнения')} · {draft.items.length}
            </h2>
            <button type="button" className="btn sm" onClick={props.onAdd}>
              <Plus className="wk-i wk-tiny" aria-hidden="true" />
              {t('Добавить упражнение')}
            </button>
          </div>
          <div className="wk-edlist" ref={list}>
            {draft.items.map((item, index) => {
              const name = props.nameOf(item.exerciseID, t('Упражнение'));
              return (
                <div className="wk-er" data-row key={item.id}>
                  <div className="top">
                    <button
                      type="button"
                      className="wk-grip"
                      aria-label={t('Переместить «{name}»', { name })}
                      {...gripProps(index)}
                    >
                      <GripVertical className="wk-i" aria-hidden="true" />
                    </button>
                    <div className="tx">
                      <b>{name}</b>
                      <MuscleChip muscle={muscleOf(item.exerciseID, props.custom)} />
                    </div>
                    <button
                      type="button"
                      className="wk-ib sm"
                      aria-label={t('Удалить «{name}»', { name })}
                      onClick={() => onChange(withoutItem(draft, item.id))}
                    >
                      <X className="wk-i" aria-hidden="true" />
                    </button>
                  </div>
                  <div className="st3">
                    {(['sets', 'reps', 'rest'] as const).map((field) => (
                      <PlanStepper
                        key={field}
                        label={
                          field === 'sets'
                            ? t('Подходы')
                            : field === 'reps'
                              ? t('Повторы')
                              : t('Отдых')
                        }
                        value={
                          field === 'rest'
                            ? `${fieldValue(item, field)}${NBSP}${t('с')}`
                            : fieldValue(item, field)
                        }
                        canDecrease={canStepItem(item, field, -1)}
                        canIncrease={canStepItem(item, field, 1)}
                        onStep={(direction) => onChange(stepItem(draft, item.id, field, direction))}
                      />
                    ))}
                  </div>
                </div>
              );
            })}
          </div>
          {draft.items.length ? null : (
            <p className="wk-empty">{t('Добавьте первое упражнение.')}</p>
          )}
        </div>
      </div>
    </>
  );
}
