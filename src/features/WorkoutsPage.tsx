import { memo, useCallback, useEffect, useMemo, useState } from 'react';
import { Check, LoaderCircle } from 'lucide-react';
import { useI18n } from '../lib/i18n';
import { dateInZone } from '../lib/date';
import { dateKey } from './workouts/dates';
import { EditorView } from './workouts/EditorView';
import { ExercisePicker } from './workouts/ExercisePicker';
import { FinishedDialog } from './workouts/FinishedDialog';
import { HomeView } from './workouts/HomeView';
import { ProgramView } from './workouts/ProgramView';
import { RunView } from './workouts/RunView';
import { ExercisesDialog, OptionsDialog } from './workouts/RunDialogs';
import { RecordDialog, SettingsDialog, useAsk } from './workouts/dialogs';
import { clock, kgText, setsText } from './workouts/format';
import { canSaveDraft, draftOf, saveDraft, withExercise, type Draft } from './workouts/library';
import {
  exerciseName,
  MUSCLE_TITLES,
  muscleOf,
  newId,
  type Best,
  type Program,
  type RecordCard,
  type WorkoutRecord,
} from './workouts/model';
import { doneSets, totalSessionSets } from './workouts/session';
import { recordDuration, recordSetCount, recordVolume } from './workouts/stats';
import { useActiveWorkout } from './workouts/useActiveWorkout';
import { useRunFlow, type PickerMode } from './workouts/useRunFlow';
import { useWorkouts } from './workouts/useWorkouts';
import '../styles/workouts.css';
import '../styles/workouts-program.css';
import '../styles/workouts-run.css';
import '../styles/workouts-modals.css';
import '../styles/workouts-phone.css';

type View =
  | { name: 'home' }
  | { name: 'program'; id: string }
  | { name: 'editor' }
  | { name: 'run' }
  | { name: 'summary'; id: string };
type Dialog =
  | { kind: 'settings' }
  | { kind: 'record'; card: RecordCard | null }
  | { kind: 'history'; id: string };
interface EditorState {
  id: string;
  isNew: boolean;
  from: 'home' | 'program';
  draft: Draft;
}

export const WorkoutsPage = memo(function WorkoutsPage({
  active,
  timeZone,
  today = dateInZone(timeZone),
  onNotify,
}: {
  active: boolean;
  timeZone: string;
  today?: string;
  onNotify: (message: string, error?: boolean) => void;
}) {
  const { t, language } = useI18n();
  const workouts = useWorkouts(active, (message) => onNotify(message, true));
  const { state } = workouts;
  const run = useActiveWorkout(active);
  const [view, setView] = useState<View>({ name: 'home' });
  const [dialog, setDialog] = useState<Dialog | null>(null);
  const [picker, setPicker] = useState<PickerMode | null>(null);
  const [editor, setEditor] = useState<EditorState | null>(null);
  const { ask, node: askNode } = useAsk();

  const nameOf = useCallback(
    (exerciseID: string, fallback: string) =>
      exerciseName(exerciseID, state.custom, language, fallback),
    [state.custom, language],
  );
  const muscleNames = useCallback(
    (program: Program) => [
      ...new Set(
        program.items
          .map((item) => muscleOf(item.exerciseID, state.custom))
          .flatMap((m) => (m ? [t(MUSCLE_TITLES[m])] : [])),
      ),
    ],
    [state.custom, t],
  );
  const flow = useRunFlow({
    state,
    workouts,
    run,
    today,
    nameOf,
    notify: onNotify,
    setView,
    openPicker: setPicker,
  });
  const { cur, setCur } = flow;

  useEffect(() => {
    if (!active) return;
    window.scrollTo(0, 0);
    document.getElementById('main-content')?.scrollTo?.(0, 0);
  }, [view.name, active]);
  useEffect(() => {
    if (view.name === 'run' && !run.session) setView({ name: 'home' });
    if (
      view.name === 'program' &&
      workouts.client.loaded &&
      !state.programs.some((p) => p.id === view.id)
    )
      setView({ name: 'home' });
  }, [view, run.session, state.programs, workouts.client.loaded]);

  const openEditor = (id: string | null, from: 'home' | 'program') => {
    const program = id ? state.programs.find((item) => item.id === id) : undefined;
    setEditor({ id: id ?? newId(), isNew: !program, from, draft: draftOf(program) });
    setView({ name: 'editor' });
  };
  const saveEditor = async () => {
    if (!editor || !canSaveDraft(editor.draft)) return;
    const next = saveDraft(state.programs, editor.draft, editor.id);
    if (!next) return;
    const saved = await workouts.write(() => workouts.client.saveProgramList(next, state.custom));
    if (!saved) return;
    onNotify(t('Программа сохранена'));
    setView(
      editor.isNew || editor.from === 'home'
        ? { name: 'home' }
        : { name: 'program', id: editor.id },
    );
  };
  const deleteProgram = async () => {
    if (!editor) return;
    const yes = await ask({
      title: t('Удалить программу?'),
      text: t('Программа будет удалена. Это действие нельзя отменить'),
      buttons: [
        { label: t('Удалить'), value: 'yes', danger: true },
        { label: t('Отмена'), value: null },
      ],
    });
    if (!yes) return;
    const next = state.programs.filter((program) => program.id !== editor.id);
    if (!(await workouts.write(() => workouts.client.saveProgramList(next, state.custom)))) return;
    onNotify(t('Программа удалена'));
    setView({ name: 'home' });
  };
  const saveBests = async (bests: Best[]) => {
    const saved = await workouts.write(async () => {
      for (const best of bests) await workouts.client.saveBest(best);
      return true as const;
    });
    if (saved) setDialog(null);
  };
  const deleteRecord = async (card: RecordCard) => {
    const yes = await ask({
      title: t('Удалить рекорд?'),
      buttons: [
        { label: t('Удалить'), value: 'yes', danger: true },
        { label: t('Отмена'), value: null },
      ],
    });
    if (!yes) return;
    await saveBests([
      {
        exerciseID: card.exerciseID,
        name: card.name,
        weight: 0,
        reps: 1,
        date: new Date().toISOString().replace(/\.\d{3}Z$/, 'Z'),
        deleted: true,
      },
    ]);
  };

  const habit = state.settings.linkedHabitID
    ? (workouts.habits.find((item) => item.id === state.settings.linkedHabitID) ?? null)
    : null;
  const program =
    view.name === 'program' ? state.programs.find((item) => item.id === view.id) : undefined;
  const running = run.session
    ? {
        programName: run.session.programName,
        done: doneSets(run.session),
        total: totalSessionSets(run.session),
        elapsed: clock(Math.floor((run.now - Date.parse(run.session.startedAt)) / 1000)),
      }
    : null;
  const openRecord = (record: WorkoutRecord) => setDialog({ kind: 'history', id: record.id });
  const historyRecord =
    dialog?.kind === 'history' ? state.records.find((item) => item.id === dialog.id) : undefined;
  const common = useMemo(
    () => ({ state, today, timeZone, nameOf, muscleNames }),
    [state, today, timeZone, nameOf, muscleNames],
  );

  const pickFor = (mode: PickerMode) => {
    const used =
      mode.kind === 'editor'
        ? new Set(editor?.draft.items.map((item) => item.exerciseID))
        : new Set(run.session?.items.map((item) => item.exerciseID));
    return (
      <ExercisePicker
        title={mode.kind === 'replace' ? t('Заменить упражнение') : t('Добавить упражнение')}
        usedNote={mode.kind === 'editor' ? t('уже в программе') : t('уже в тренировке')}
        used={used}
        custom={state.custom}
        onCreated={workouts.client.rememberExercise.bind(workouts.client)}
        onSetMuscle={(id, muscle) =>
          void workouts.write(() => workouts.client.setMuscle(id, muscle))
        }
        onClose={() => setPicker(null)}
        onPick={(exercise) => {
          if (mode.kind === 'editor') {
            const next = editor ? withExercise(editor.draft, exercise.id) : null;
            if (!next || !editor) return onNotify(t('Это упражнение уже есть в программе.'), true);
            setEditor({ ...editor, draft: next });
            setPicker(null);
          } else if (flow.applyPick(mode, exercise)) setPicker(null);
        }}
      />
    );
  };

  let body;
  if (!workouts.client.loaded) {
    body = workouts.error ? (
      <div className="panel wk-state" role="alert">
        <p>{workouts.error}</p>
        <button type="button" className="btn primary" onClick={() => void workouts.refresh()}>
          {t('Повторить')}
        </button>
      </div>
    ) : (
      <p className="wk-empty wk-state" role="status">
        <LoaderCircle className="wk-i spinning" aria-hidden="true" /> {t('Загрузка тренировок…')}
      </p>
    );
  } else if (view.name === 'program' && program) {
    body = (
      <ProgramView
        {...common}
        program={program}
        running={run.session?.programID === program.id}
        onBack={() => setView({ name: 'home' })}
        onEdit={() => openEditor(program.id, 'program')}
        onStart={() => void flow.start(program.id)}
        onHistory={openRecord}
      />
    );
  } else if (view.name === 'editor' && editor) {
    body = (
      <EditorView
        isNew={editor.isNew}
        draft={editor.draft}
        custom={state.custom}
        nameOf={nameOf}
        onChange={(draft) => setEditor({ ...editor, draft })}
        onAdd={() => setPicker({ kind: 'editor' })}
        onSave={() => void saveEditor()}
        onCancel={() =>
          setView(
            editor.isNew || editor.from === 'home'
              ? { name: 'home' }
              : { name: 'program', id: editor.id },
          )
        }
        onDelete={() => void deleteProgram()}
      />
    );
  } else if (view.name === 'run' && run.session) {
    body = (
      <RunView
        session={run.session}
        cur={cur}
        onCur={setCur}
        elapsed={Math.floor((run.now - Date.parse(run.session.startedAt)) / 1000)}
        rest={run.rest}
        restLeft={run.restLeft}
        custom={state.custom}
        actions={flow.actions}
      />
    );
  } else if (view.name === 'summary') {
    const record = state.records.find((item) => item.id === view.id);
    body = record ? (
      <div className="wk-fin">
        <span className="ico">
          <Check className="wk-i" aria-hidden="true" />
        </span>
        <h2>{t('Тренировка завершена')}</h2>
        <p>
          {clock(recordDuration(record))} · {kgText(recordVolume(record), language)} ·{' '}
          {setsText(recordSetCount(record), language)}
        </p>
        <div className="btns">
          <button type="button" className="btn primary" onClick={() => setView({ name: 'home' })}>
            {t('Готово')}
          </button>
          <button type="button" className="btn" onClick={() => openRecord(record)}>
            {t('Итоги тренировки')}
          </button>
        </div>
      </div>
    ) : null;
  } else {
    body = (
      <HomeView
        {...common}
        habits={workouts.habits}
        habitsReady={!workouts.loading}
        running={running}
        onOpen={(id) => setView({ name: 'program', id })}
        onStart={(id) => void flow.start(id)}
        onEdit={(id) => openEditor(id, 'home')}
        onNew={() => openEditor(null, 'home')}
        onSettings={() => setDialog({ kind: 'settings' })}
        onResume={() => setView({ name: 'run' })}
        onRecord={(card) => setDialog({ kind: 'record', card })}
        onHistory={openRecord}
      />
    );
  }
  const session = run.session;
  const optionsItem = session?.items.find((item) => item.id === flow.optionsFor);
  return (
    <div className="wk wk-enter" key={view.name} data-view={view.name}>
      {body}
      {dialog?.kind === 'settings' ? (
        <SettingsDialog
          habits={workouts.habits}
          settings={state.settings}
          onLink={(id) =>
            void workouts.write(() =>
              workouts.client.saveSettings({ ...state.settings, linkedHabitID: id }),
            )
          }
          onClose={() => setDialog(null)}
        />
      ) : null}
      {dialog?.kind === 'record' ? (
        <RecordDialog
          card={dialog.card}
          custom={state.custom}
          today={today}
          timeZone={timeZone}
          onSave={(bests) => void saveBests(bests)}
          onDelete={(card) => void deleteRecord(card)}
          onClose={() => setDialog(null)}
        />
      ) : null}
      {historyRecord ? (
        <FinishedDialog
          record={historyRecord}
          history={state.records}
          program={state.programs.find((item) => item.id === historyRecord.programID) ?? null}
          custom={state.custom}
          habit={habit}
          timeZone={timeZone}
          nameOf={nameOf}
          onRepeat={(id) => void flow.start(id)}
          onClose={() => setDialog(null)}
        />
      ) : null}
      {optionsItem && session ? (
        <OptionsDialog
          item={optionsItem}
          custom={state.custom}
          canRemove={session.items.length > 1}
          onStep={(field, direction) => flow.step(optionsItem.id, field, direction)}
          onReplace={() => {
            flow.setOptionsFor(null);
            void flow.replace(optionsItem.id);
          }}
          onRemove={() => void flow.remove(optionsItem.id)}
          onClose={() => flow.setOptionsFor(null)}
        />
      ) : null}
      {flow.listOpen && session ? (
        <ExercisesDialog
          session={session}
          cur={cur}
          custom={state.custom}
          actions={flow.actions}
          onGo={setCur}
          onClose={() => flow.setListOpen(false)}
        />
      ) : null}
      {picker ? pickFor(picker) : null}
      {flow.askNode}
      {askNode}
    </div>
  );
});
