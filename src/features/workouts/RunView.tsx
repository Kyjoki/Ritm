import { useEffect, useState } from 'react';
import {
  ChevronLeft,
  ChevronRight,
  Check,
  Clock,
  List,
  Minus,
  Plus,
  SlidersHorizontal,
  GripVertical,
} from 'lucide-react';
import { useI18n } from '../../lib/i18n';
import { decimal, clock } from './format';
import { muscleOf, type Exercise } from './model';
import { MuscleChip, Ring } from './parts';
import { RunMenu } from './RunMenu';
import { formatWeight, parseReps, parseWeight, stepReps, stepWeight } from './numbers';
import { doneSets, itemDone, totalSessionSets, type Session, type SessionItem } from './session';
import { MAX_SESSION_SETS } from './model';
import { useReorder } from './useReorder';
import type { Rest } from './useActiveWorkout';

export interface RunActions {
  onTypeWeight: (itemID: string, setID: string, text: string) => void;
  onTypeReps: (itemID: string, setID: string, text: string) => void;
  onTick: (itemID: string, setID: string) => void;
  onAddSet: (itemID: string) => void;
  onRemoveSet: (itemID: string) => void;
  onStartRest: (seconds: number) => void;
  onExtendRest: () => void;
  onSkipRest: () => void;
  onFinish: () => void;
  onCancel: () => void;
  onHome: () => void;
  onAdd: (after: number | null) => void;
  onReplace: (itemID: string) => void;
  onRemove: (itemID: string) => void;
  onOptions: (itemID: string) => void;
  onMove: (from: number, to: number) => void;
  onList: () => void;
}
interface Selection {
  itemID: string;
  setID: string;
  field: 'weight' | 'reps';
}
const QUICK_CANCEL_SECONDS = 120;

export function ExerciseList({
  session,
  cur,
  custom,
  onGo,
  actions,
}: {
  session: Session;
  cur: number;
  custom: Exercise[];
  onGo: (index: number) => void;
  actions: Pick<RunActions, 'onMove' | 'onOptions'>;
}) {
  const { t } = useI18n();
  const { list, gripProps } = useReorder(actions.onMove);
  return (
    <div className="wk-xlist" ref={list}>
      {session.items.map((item, index) => {
        const full = item.sets.length > 0 && itemDone(item) === item.sets.length;
        const note = item.keptForLog
          ? t('{done} выполнено, остаётся в журнале', { done: itemDone(item) })
          : t('{done} из {total} подходов', { done: itemDone(item), total: item.sets.length });
        return (
          <div
            key={item.id}
            data-row
            className={`wk-xi${index === cur ? ' cur' : ''}${full ? ' full' : ''}`}
          >
            <button
              type="button"
              className="wk-grip"
              aria-label={t('Переместить «{name}»', { name: item.name })}
              {...gripProps(index)}
            >
              <GripVertical className="wk-i" aria-hidden="true" />
            </button>
            <button type="button" className="mn" onClick={() => onGo(index)}>
              <span className="st">
                {full ? <Check className="wk-i" aria-hidden="true" /> : index + 1}
              </span>
              <span className="tx">
                <b>{item.name}</b>
                <span className="mt">
                  <MuscleChip muscle={muscleOf(item.exerciseID, custom)} />
                  <small>{note}</small>
                </span>
              </span>
              {index === cur ? <em>{t('Сейчас')}</em> : null}
            </button>
            <button
              type="button"
              className="wk-ib sm"
              aria-label={t('Изменить «{name}»', { name: item.name })}
              onClick={() => actions.onOptions(item.id)}
            >
              <SlidersHorizontal className="wk-i" aria-hidden="true" />
            </button>
          </div>
        );
      })}
    </div>
  );
}

function SetsCard({
  item,
  custom,
  selection,
  actions,
  onSelect,
}: {
  item: SessionItem;
  custom: Exercise[];
  selection: Selection;
  actions: RunActions;
  onSelect: (selection: Selection) => void;
}) {
  const { t, language } = useI18n();
  const active = item.sets.findIndex((set) => !set.done);
  const set = item.sets.find((candidate) => candidate.id === selection.setID);
  const locked = !set || set.done || item.keptForLog;
  const step = selection.field === 'weight' ? '2,5' : '1';
  const value = !set
    ? '0'
    : selection.field === 'weight'
      ? parseWeight(set.weight) === null
        ? '0'
        : formatWeight(parseWeight(set.weight) ?? 0)
      : (parseReps(set.reps) ?? 0);
  const change = (direction: 1 | -1) => {
    if (!set) return;
    if (selection.field === 'weight')
      actions.onTypeWeight(
        item.id,
        set.id,
        stepWeight(set.weight, direction * 2.5, language === 'ru'),
      );
    else actions.onTypeReps(item.id, set.id, stepReps(set.reps, direction));
  };
  const canRemove = item.sets.length > 1 && item.sets.some((candidate) => !candidate.done);
  return (
    <section className="panel wk-xc">
      <div className="hd">
        <h2>{item.name}</h2>
        <span className="cn">
          {itemDone(item)}/{item.sets.length}
        </span>
      </div>
      <div className="chs">
        <MuscleChip muscle={muscleOf(item.exerciseID, custom)} />
      </div>
      <div className="wk-tb th">
        <span>№</span>
        <span>{t('Прошлый раз')}</span>
        <span>{t('кг')}</span>
        <span>{t('повт.')}</span>
        <span />
      </div>
      {item.sets.map((row, index) => {
        const previous = item.previous?.sets[index];
        const readOnly = row.done || item.keptForLog;
        const selected = (field: 'weight' | 'reps') =>
          selection.setID === row.id && selection.field === field;
        return (
          <div
            key={row.id}
            className={`wk-tb wk-sr${row.done ? ' d' : ''}${index === active ? ' a' : ''}`}
          >
            <span className="n">{index + 1}</span>
            <span className="p">
              {previous ? `${decimal(previous.weight, language)} × ${previous.reps}` : '—'}
            </span>
            <input
              className={`wk-v${selected('weight') ? ' sel' : ''}`}
              inputMode="decimal"
              autoComplete="off"
              placeholder={t('кг')}
              value={row.weight}
              readOnly={readOnly}
              tabIndex={readOnly ? -1 : 0}
              aria-label={t('Вес в килограммах, подход {number}', { number: index + 1 })}
              onFocus={() =>
                !readOnly && onSelect({ itemID: item.id, setID: row.id, field: 'weight' })
              }
              onChange={(event) => actions.onTypeWeight(item.id, row.id, event.target.value)}
              onKeyDown={(event) => event.key === 'Enter' && actions.onTick(item.id, row.id)}
            />
            <input
              className={`wk-v${selected('reps') ? ' sel' : ''}`}
              inputMode="numeric"
              autoComplete="off"
              placeholder={t('повт.')}
              value={row.reps}
              readOnly={readOnly}
              tabIndex={readOnly ? -1 : 0}
              aria-label={t('Повторы, подход {number}', { number: index + 1 })}
              onFocus={() =>
                !readOnly && onSelect({ itemID: item.id, setID: row.id, field: 'reps' })
              }
              onChange={(event) => actions.onTypeReps(item.id, row.id, event.target.value)}
              onKeyDown={(event) => event.key === 'Enter' && actions.onTick(item.id, row.id)}
            />
            <button
              type="button"
              className="tkb"
              disabled={item.keptForLog}
              aria-pressed={row.done}
              aria-label={t('Подход {number} выполнен', { number: index + 1 })}
              onClick={() => actions.onTick(item.id, row.id)}
            >
              <Check className="wk-i" aria-hidden="true" />
            </button>
          </div>
        );
      })}
      <div className="wk-st">
        <button type="button" disabled={locked} onClick={() => change(-1)}>
          −{step}
        </button>
        <b>
          {value}
          <i>{selection.field === 'weight' ? t('кг') : t('повт.')}</i>
        </b>
        <button type="button" disabled={locked} onClick={() => change(1)}>
          +{step}
        </button>
      </div>
      <div className="wk-sbtn">
        <button
          type="button"
          disabled={!canRemove}
          aria-label={t('Убрать последний невыполненный подход')}
          onClick={() => actions.onRemoveSet(item.id)}
        >
          <Minus className="wk-i" aria-hidden="true" />
          {t('Подход')}
        </button>
        <button
          type="button"
          disabled={item.sets.length >= MAX_SESSION_SETS || item.keptForLog}
          aria-label={t('Добавить подход')}
          onClick={() => actions.onAddSet(item.id)}
        >
          <Plus className="wk-i" aria-hidden="true" />
          {t('Подход')}
        </button>
      </div>
    </section>
  );
}

function RestCard({
  item,
  rest,
  left,
  actions,
}: {
  item: SessionItem;
  rest: Rest | null;
  left: number;
  actions: RunActions;
}) {
  const { t } = useI18n();
  const running = rest !== null && left > 0;
  return (
    <aside className={`panel wk-rest${running ? ' run' : ''}`}>
      <Ring fraction={running && rest ? left / rest.length : 0} className="big">
        <b>{clock(running ? left : item.restSeconds)}</b>
        <small>{t('Отдых')}</small>
      </Ring>
      <div className="rb">
        {running ? (
          <>
            <button type="button" className="btn sm" onClick={actions.onExtendRest}>
              {t('+15 с')}
            </button>
            <button type="button" className="btn sm primary" onClick={actions.onSkipRest}>
              {t('Пропустить')}
            </button>
          </>
        ) : (
          <button
            type="button"
            className="btn sm primary"
            onClick={() => actions.onStartRest(item.restSeconds)}
          >
            {t('Запустить отдых')}
          </button>
        )}
      </div>
    </aside>
  );
}

export function RunView({
  session,
  cur,
  onCur,
  elapsed,
  rest,
  restLeft,
  custom,
  actions,
}: {
  session: Session;
  cur: number;
  onCur: (index: number) => void;
  elapsed: number;
  rest: Rest | null;
  restLeft: number;
  custom: Exercise[];
  actions: RunActions;
}) {
  const { t } = useI18n();
  const item = session.items[Math.min(cur, session.items.length - 1)];
  const firstOpen = item.sets.find((set) => !set.done) ?? item.sets.at(-1)!;
  const [picked, setPicked] = useState<Selection | null>(null);
  const selection =
    picked &&
    picked.itemID === item.id &&
    item.sets.some((set) => set.id === picked.setID && !set.done)
      ? picked
      : { itemID: item.id, setID: firstOpen.id, field: 'weight' as const };
  const done = doneSets(session);
  const total = totalSessionSets(session);
  useEffect(() => setPicked(null), [cur]);
  const index = session.items.indexOf(item);
  return (
    <>
      <div className="wk-rh">
        <button
          type="button"
          className="wk-ib"
          onClick={actions.onHome}
          aria-label={t('К программам, тренировка продолжается')}
        >
          <ChevronLeft className="wk-i" aria-hidden="true" />
        </button>
        <div className="wk-rt">
          <h2>{session.programName}</h2>
          <span className="wk-clock">
            <Clock className="wk-i" aria-hidden="true" />
            <span>{clock(elapsed)}</span>
            {elapsed < QUICK_CANCEL_SECONDS ? (
              <>
                <span>·</span>
                <button type="button" className="wk-quick" onClick={actions.onCancel}>
                  {t('Отменить')}
                </button>
              </>
            ) : null}
          </span>
        </div>
        <div
          className="wk-rpg"
          role="progressbar"
          aria-valuemin={0}
          aria-valuemax={total}
          aria-valuenow={done}
        >
          <i>
            <b style={{ width: `${total ? (done / total) * 100 : 0}%` }} />
          </i>
          <span>{t('{done} из {total} подходов', { done, total })}</span>
        </div>
        <button
          type="button"
          className={`btn${done === total ? ' primary' : ''}`}
          onClick={actions.onFinish}
        >
          {t('Завершить тренировку')}
        </button>
        <RunMenu
          canRemove={session.items.length > 1}
          actions={actions}
          current={item.id}
          index={index}
        />
      </div>
      <div className="wk-rgrid">
        <aside className="panel wk-rl">
          <div className="wk-xh">
            <h2>{t('Упражнения')}</h2>
            <span>
              {t('{current} из {count}', { current: index + 1, count: session.items.length })}
            </span>
          </div>
          <ExerciseList
            session={session}
            cur={index}
            custom={custom}
            onGo={onCur}
            actions={actions}
          />
          <button type="button" className="wk-dash row" onClick={() => actions.onAdd(null)}>
            <Plus className="wk-i" aria-hidden="true" />
            {t('Добавить упражнение')}
          </button>
        </aside>
        <div className="wk-rm">
          <div className="wk-xw">
            <SetsCard
              item={item}
              custom={custom}
              selection={selection}
              actions={actions}
              onSelect={setPicked}
            />
            <div className="wk-nv">
              <button
                type="button"
                className="btn"
                disabled={index === 0}
                onClick={() => onCur(index - 1)}
              >
                <ChevronLeft className="wk-i" aria-hidden="true" />
                {t('Предыдущее')}
              </button>
              <button type="button" className="btn wk-listbtn" onClick={actions.onList}>
                <List className="wk-i" aria-hidden="true" />
                {t('Упражнения · {current} из {count}', {
                  current: index + 1,
                  count: session.items.length,
                })}
              </button>
              <button
                type="button"
                className="btn"
                disabled={index >= session.items.length - 1}
                onClick={() => onCur(index + 1)}
              >
                {t('Следующее')}
                <ChevronRight className="wk-i" aria-hidden="true" />
              </button>
            </div>
          </div>
          <RestCard item={item} rest={rest} left={restLeft} actions={actions} />
        </div>
      </div>
    </>
  );
}
