/** Finishing a workout: the record, the records it beat, the program edit, and the linked habit tick. */
import type { Habit } from '../../../shared/types';
import { habitCanMarkOn, habitProgress, habitTarget } from '../habit-utils';
import type { WorkoutsClient, WorkoutsState } from './client';
import { applyTo, finishSession, type Session } from './session';
import { recordUpdates, resolveRecords, type RecordBeat } from './stats';
import type { WorkoutRecord, WorkoutSettings } from './model';

export interface Finished {
  record: WorkoutRecord;
  beats: RecordBeat[];
  programSaved: boolean;
}

/**
 * Writes the finished workout (and its record docs, and optionally the edited program).
 * `write` reports failures to the owner and returns undefined; then nothing is lost: the caller keeps
 * the running workout so it can be finished again.
 */
export async function saveFinishedWorkout(args: {
  session: Session;
  state: WorkoutsState;
  client: Pick<WorkoutsClient, 'saveFinished'>;
  write: <T>(job: () => Promise<T>) => Promise<T | undefined>;
  saveToProgram: boolean;
  now: Date;
}): Promise<Finished | null> {
  const record = finishSession(args.session, args.now);
  if (!record) return null;
  const before = resolveRecords(args.state.records, args.state.bests);
  const { changed, beats } = recordUpdates(record, before, args.state.bests);
  const original = args.state.programs.find((program) => program.id === args.session.programID);
  const program = args.saveToProgram && original ? applyTo(args.session, original) : undefined;
  const saved = await args.write(() => args.client.saveFinished(record, changed, program));
  return saved === undefined ? null : { record, beats, programSaved: program !== undefined };
}

/** Finishing ticks the linked habit once a day: it exists, can be marked today and is not complete yet. */
export function shouldTickHabit(
  habit: Habit | undefined,
  settings: WorkoutSettings,
  today: string,
): habit is Habit {
  return (
    habit !== undefined &&
    habit.id === settings.linkedHabitID &&
    !habit.archived &&
    settings.lastTickedDay !== today &&
    habitCanMarkOn(habit, today, today) &&
    habitProgress(habit, today) < habitTarget(habit)
  );
}
/**
 * Reads the habits fresh (a stale `updatedAt` would be a 409) and sets today's progress to the target.
 * Returns the habits as the server has them after, or null when there was nothing to tick.
 */
export async function tickLinkedHabit(args: {
  settings: WorkoutSettings;
  today: string;
  readHabits: () => Promise<Habit[]>;
  setProgress: (habit: Habit, date: string, count: number) => Promise<Habit>;
}): Promise<{ habit: Habit; habits: Habit[] } | { habits: Habit[] } | null> {
  if (!args.settings.linkedHabitID) return null;
  const habits = await args.readHabits();
  const habit = habits.find((item) => item.id === args.settings.linkedHabitID);
  if (!shouldTickHabit(habit, args.settings, args.today)) return { habits };
  const updated = await args.setProgress(habit, args.today, habitTarget(habit));
  return {
    habit: updated,
    habits: habits.map((item) => (item.id === updated.id ? updated : item)),
  };
}
