import { ArrowLeftRight, CircleMinus, Plus } from 'lucide-react';
import { Dialog } from '../../components/Dialog';
import { useI18n } from '../../lib/i18n';
import { NBSP } from './format';
import { muscleOf, type Exercise } from './model';
import { MuscleChip, PlanStepper } from './parts';
import {
  canStepSession,
  itemDone,
  type Session,
  type SessionField,
  type SessionItem,
} from './session';
import { ExerciseList, type RunActions } from './RunView';

/** Plan of one exercise for this workout only: sets, reps, rest, replace, remove. */
export function OptionsDialog({
  item,
  canRemove,
  custom,
  onStep,
  onReplace,
  onRemove,
  onClose,
}: {
  item: SessionItem;
  canRemove: boolean;
  custom: Exercise[];
  onStep: (field: SessionField, direction: 1 | -1) => void;
  onReplace: () => void;
  onRemove: () => void;
  onClose: () => void;
}) {
  const { t } = useI18n();
  const can = (field: SessionField, direction: 1 | -1) => canStepSession(item, field, direction);
  return (
    <Dialog title={item.name} className="wkm" onClose={onClose}>
      <div className="wkm-sub">
        <MuscleChip muscle={muscleOf(item.exerciseID, custom)} />
        <span>
          {t('выполнено {done} из {total}', { done: itemDone(item), total: item.sets.length })}
        </span>
      </div>
      <div className="wk-lb">{t('План на эту тренировку')}</div>
      <div className="st3">
        <PlanStepper
          label={t('Подходы')}
          value={item.sets.length}
          canDecrease={can('sets', -1)}
          canIncrease={can('sets', 1)}
          onStep={(d) => onStep('sets', d)}
        />
        <PlanStepper
          label={t('Повторы')}
          value={item.plannedReps}
          canDecrease={can('reps', -1)}
          canIncrease={can('reps', 1)}
          onStep={(d) => onStep('reps', d)}
        />
        <PlanStepper
          label={t('Отдых')}
          value={`${item.restSeconds}${NBSP}${t('с')}`}
          canDecrease={can('rest', -1)}
          canIncrease={can('rest', 1)}
          onStep={(d) => onStep('rest', d)}
        />
      </div>
      <button type="button" className="btn wide" style={{ marginTop: 16 }} onClick={onReplace}>
        <ArrowLeftRight className="wk-i wk-tiny" aria-hidden="true" />
        {t('Заменить упражнение')}
      </button>
      <button
        type="button"
        className="btn wide danger"
        style={{ marginTop: 8 }}
        disabled={!canRemove}
        onClick={onRemove}
      >
        <CircleMinus className="wk-i wk-tiny" aria-hidden="true" />
        {t('Убрать из тренировки')}
      </button>
      <button
        type="button"
        className="btn primary wide"
        style={{ marginTop: 14 }}
        onClick={onClose}
      >
        {t('Готово')}
      </button>
    </Dialog>
  );
}

/** The exercise list as a dialog: on a narrow screen the left column is hidden. */
export function ExercisesDialog({
  session,
  cur,
  custom,
  actions,
  onGo,
  onClose,
}: {
  session: Session;
  cur: number;
  custom: Exercise[];
  actions: RunActions;
  onGo: (index: number) => void;
  onClose: () => void;
}) {
  const { t } = useI18n();
  return (
    <Dialog title={t('Упражнения')} className="wkm" onClose={onClose}>
      <ExerciseList
        session={session}
        cur={cur}
        custom={custom}
        onGo={(index) => {
          onGo(index);
          onClose();
        }}
        actions={actions}
      />
      <button
        type="button"
        className="wk-dash row"
        style={{ marginTop: 10 }}
        onClick={() => actions.onAdd(null)}
      >
        <Plus className="wk-i" aria-hidden="true" />
        {t('Добавить упражнение')}
      </button>
    </Dialog>
  );
}
