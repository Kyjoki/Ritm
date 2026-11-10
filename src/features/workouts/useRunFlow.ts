import { useCallback, useMemo, useState } from 'react';
import { api } from '../../lib/api';
import { useI18n } from '../../lib/i18n';
import { saveFinishedWorkout, tickLinkedHabit } from './finish';
import { decimal } from './format';
import type { WorkoutsState } from './client';
import type { Exercise } from './model';
import {
  addExercise,
  changeFrom,
  doneSets,
  moveExercise,
  removeExercise,
  removeLastOpenSet,
  replaceExercise,
  addSet,
  startSession,
  stepSession,
  toggleSet,
  totalSessionSets,
  typeReps,
  typeWeight,
  type Session,
  type SessionField,
} from './session';
import type { RunActions } from './RunView';
import type { useActiveWorkout } from './useActiveWorkout';
import type { useWorkouts } from './useWorkouts';
import { useAsk } from './dialogs';

export type PickerMode =
  { kind: 'editor' } | { kind: 'add'; after: number | null } | { kind: 'replace'; itemID: string };
type View =
  | { name: 'home' }
  | { name: 'program'; id: string }
  | { name: 'editor' }
  | { name: 'run' }
  | { name: 'summary'; id: string };

export interface RunFlowDeps {
  state: WorkoutsState;
  workouts: ReturnType<typeof useWorkouts>;
  run: ReturnType<typeof useActiveWorkout>;
  today: string;
  nameOf: (exerciseID: string, fallback: string) => string;
  notify: (message: string, error?: boolean) => void;
  setView: (view: View) => void;
  openPicker: (mode: PickerMode) => void;
}

/** Start, tick, edit, finish and cancel of the running workout. */
export function useRunFlow(d: RunFlowDeps) {
  const { t, language } = useI18n();
  const { ask, node: askNode } = useAsk();
  const { run, workouts, state } = d;
  const [cur, setCur] = useState(0);
  const [optionsFor, setOptionsFor] = useState<string | null>(null);
  const [listOpen, setListOpen] = useState(false);

  const complete = useCallback(
    async (saveToProgram: boolean): Promise<boolean> => {
      const session = run.current();
      if (!session) return false;
      const result = await saveFinishedWorkout({
        session,
        state,
        client: workouts.client,
        write: workouts.write,
        saveToProgram,
        now: new Date(),
      });
      if (!result) return false;
      run.end();
      if (result.programSaved) d.notify(t('Программа обновлена'));
      const beat = result.beats[0];
      if (beat)
        d.notify(
          t('Новый рекорд: {name} {weight} кг', {
            name: d.nameOf(beat.exerciseID, beat.name).toLowerCase(),
            weight: decimal(beat.weight, language),
          }),
        );
      void tickHabit(!beat);
      d.setView({ name: 'summary', id: result.record.id });
      return true;
    },
    [run, state, workouts, language, t],
  );

  async function tickHabit(announce: boolean) {
    try {
      const outcome = await tickLinkedHabit({
        settings: state.settings,
        today: d.today,
        readHabits: async () => (await api.habits()).habits,
        setProgress: async (habit, date, count) =>
          (await api.setHabitProgress(habit.id, date, count, habit.updatedAt)).habit,
      });
      if (!outcome) return;
      workouts.setHabits(outcome.habits);
      if (!('habit' in outcome)) return;
      window.dispatchEvent(
        new CustomEvent('ritm:habits-changed', { detail: { source: 'workouts' } }),
      );
      await workouts.write(() =>
        workouts.client.saveSettings({ ...state.settings, lastTickedDay: d.today }),
      );
      if (announce) d.notify(t('Привычка «{title}» отмечена', { title: outcome.habit.title }));
    } catch {
      d.notify(t('Тренировка сохранена, но привычку отметить не удалось.'), true);
    }
  }

  const tryFinish = useCallback(async () => {
    const session = run.current();
    if (!session) return;
    const done = doneSets(session);
    const total = totalSessionSets(session);
    if (done === 0) return d.notify(t('Отметьте хотя бы один выполненный подход'), true);
    if (done < total) {
      const answer = await ask({
        title: t('Завершить тренировку?'),
        text: t('Невыполненных подходов: {count}. В историю попадут только отмеченные.', {
          count: total - done,
        }),
        buttons: [
          { label: t('Завершить'), value: 'yes', primary: true },
          { label: t('Продолжить тренировку'), value: null },
        ],
      });
      if (!answer) return;
    }
    const program = state.programs.find((item) => item.id === session.programID);
    const change = program ? changeFrom(session, program) : null;
    if (!change) {
      await complete(false);
      return;
    }
    const parts = [
      change.added ? t('добавлено {count}', { count: change.added }) : '',
      change.removed ? t('убрано {count}', { count: change.removed }) : '',
      change.modified ? t('изменено {count}', { count: change.modified }) : '',
      change.reordered ? t('новый порядок') : '',
    ].filter(Boolean);
    const choice = await ask({
      title: t('Сохранить изменения в программе?'),
      text: t('Программа «{name}»: {changes}.', {
        name: session.programName,
        changes: parts.join(', '),
      }),
      buttons: [
        { label: t('Сохранить в программу'), value: 'save', primary: true },
        { label: t('Только в этой тренировке'), value: 'once' },
        { label: t('Продолжить тренировку'), value: null },
      ],
    });
    if (choice) await complete(choice === 'save');
  }, [run, state, ask, complete, d, t]);

  const cancel = useCallback(async () => {
    const answer = await ask({
      title: t('Отменить тренировку?'),
      text: t('Тренировка не сохранится'),
      buttons: [
        { label: t('Отменить тренировку'), value: 'yes', danger: true },
        { label: t('Продолжить'), value: null },
      ],
    });
    if (!answer) return;
    run.end();
    d.notify(t('Тренировка отменена'));
    d.setView({ name: 'home' });
  }, [ask, run, d, t]);

  const begin = useCallback(
    (programID: string) => {
      const program = state.programs.find((item) => item.id === programID);
      if (!program) return;
      const session = startSession(
        program,
        state.records,
        (id) => d.nameOf(id, t('Упражнение')),
        new Date(),
      );
      if (!session) return d.notify(t('Добавьте в программу хотя бы одно упражнение'), true);
      run.begin(session);
      setCur(0);
      d.setView({ name: 'run' });
    },
    [state, run, d, t],
  );

  const start = useCallback(
    async (programID: string) => {
      const session = run.current();
      if (!session) return begin(programID);
      if (session.programID === programID) return d.setView({ name: 'run' });
      const some = doneSets(session) > 0;
      const answer = await ask({
        title: some
          ? t('Завершить текущую и начать новую?')
          : t('Отменить текущую и начать новую?'),
        text: some
          ? t('Тренировка «{name}» будет сохранена в истории', { name: session.programName })
          : t('Тренировка «{name}» не сохранится', { name: session.programName }),
        buttons: [
          {
            label: some ? t('Завершить и начать') : t('Отменить и начать'),
            value: 'yes',
            primary: true,
          },
          { label: t('Отмена'), value: null },
        ],
      });
      if (!answer) return;
      if (some) {
        if (!(await complete(false))) return;
      } else run.end();
      begin(programID);
    },
    [run, ask, begin, complete, d, t],
  );

  const replace = useCallback(
    async (itemID: string) => {
      const item = run.current()?.items.find((candidate) => candidate.id === itemID);
      if (!item) return;
      const done = item.sets.filter((set) => set.done).length;
      if (done) {
        const answer = await ask({
          title: t('Заменить упражнение?'),
          text: t(
            'Выполненных подходов: {count}. Они останутся в этой тренировке под прежним упражнением, у нового подходы начнутся заново.',
            { count: done },
          ),
          buttons: [
            { label: t('Выбрать замену'), value: 'yes', primary: true },
            { label: t('Отмена'), value: null },
          ],
        });
        if (!answer) return;
      }
      d.openPicker({ kind: 'replace', itemID });
    },
    [run, ask, d, t],
  );
  const remove = useCallback(
    async (itemID: string) => {
      const session = run.current();
      const item = session?.items.find((candidate) => candidate.id === itemID);
      if (!session || !item || session.items.length < 2) return;
      const done = item.sets.filter((set) => set.done).length;
      if (done) {
        const answer = await ask({
          title: t('Убрать упражнение?'),
          text: t('Выполненных подходов: {count}. Они не попадут в историю.', { count: done }),
          buttons: [
            { label: t('Убрать'), value: 'yes', danger: true },
            { label: t('Отмена'), value: null },
          ],
        });
        if (!answer) return;
      }
      const index = session.items.indexOf(item);
      run.update((current) => removeExercise(current, itemID));
      setCur((value) => Math.min(index < value ? value - 1 : value, session.items.length - 2));
      setOptionsFor(null);
    },
    [run, ask, t],
  );

  /** Applies a picked exercise to the running workout (add after / at the end, or replace). */
  const applyPick = useCallback(
    (mode: Exclude<PickerMode, { kind: 'editor' }>, exercise: Exercise): boolean => {
      const session = run.current();
      if (!session) return false;
      const apply = (result: { session: Session; newItemID: string } | null) => {
        if (!result) {
          d.notify(t('Это упражнение уже есть в тренировке.'), true);
          return false;
        }
        run.update(() => result.session);
        setCur(result.session.items.findIndex((item) => item.id === result.newItemID));
        return true;
      };
      return mode.kind === 'add'
        ? apply(
            addExercise(
              session,
              exercise.id,
              exercise.name,
              state.records,
              mode.after ?? undefined,
            ),
          )
        : apply(replaceExercise(session, mode.itemID, exercise.id, exercise.name, state.records));
    },
    [run, state.records, d, t],
  );

  const actions: RunActions = useMemo(
    () => ({
      onTypeWeight: (itemID, setID, text) => run.update((s) => typeWeight(s, itemID, setID, text)),
      onTypeReps: (itemID, setID, text) => run.update((s) => typeReps(s, itemID, setID, text)),
      onTick: (itemID, setID) => {
        const session = run.current();
        if (!session) return;
        const { session: next, result } = toggleSet(session, itemID, setID);
        if (result === 'needsWeight')
          return d.notify(t('Укажите вес, затем отметьте подход'), true);
        if (result === 'needsReps')
          return d.notify(t('Укажите повторы, затем отметьте подход'), true);
        run.update(() => next);
        if (result !== 'done') return;
        const item = next.items.find((candidate) => candidate.id === itemID)!;
        if (doneSets(next) === totalSessionSets(next)) run.stopRest();
        else run.startRest(item.restSeconds);
        const index = next.items.indexOf(item);
        if (item.sets.every((set) => set.done) && index < next.items.length - 1)
          window.setTimeout(() => setCur((value) => (value === index ? index + 1 : value)), 350);
      },
      onAddSet: (itemID) => run.update((s) => addSet(s, itemID)),
      onRemoveSet: (itemID) => run.update((s) => removeLastOpenSet(s, itemID)),
      onStartRest: (seconds) => run.startRest(seconds),
      onExtendRest: () => run.extendRest(15),
      onSkipRest: run.stopRest,
      onFinish: () => void tryFinish(),
      onCancel: () => void cancel(),
      onHome: () => d.setView({ name: 'home' }),
      onAdd: (after) => d.openPicker({ kind: 'add', after }),
      onReplace: (itemID) => void replace(itemID),
      onRemove: (itemID) => void remove(itemID),
      onOptions: setOptionsFor,
      onMove: (from, to) => {
        const session = run.current();
        if (!session) return;
        const id = session.items[cur]?.id;
        const next = moveExercise(session, from, to);
        run.update(() => next);
        setCur(
          Math.max(
            0,
            next.items.findIndex((item) => item.id === id),
          ),
        );
      },
      onList: () => setListOpen(true),
    }),
    [run, d, t, tryFinish, cancel, replace, remove, cur],
  );
  const step = useCallback(
    (itemID: string, field: SessionField, direction: 1 | -1) =>
      run.update((s) => stepSession(s, itemID, field, direction)),
    [run],
  );
  return {
    actions,
    askNode,
    cur,
    setCur,
    optionsFor,
    setOptionsFor,
    listOpen,
    setListOpen,
    start,
    applyPick,
    step,
    remove,
    replace,
  };
}
