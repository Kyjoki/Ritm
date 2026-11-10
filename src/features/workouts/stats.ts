/** Volume, week, streak and records. Mirrors WorkoutStats / WorkoutRecords of RitmCore. */
import type { Habit } from '../../../shared/types';
import { habitCompleteOn } from '../habit-utils';
import { dateKey, addDays, weekKeys, weekStart } from './dates';
import {
  FALLBACK_WEEKLY_GOAL,
  type Best,
  type RecordCard,
  type RecordExercise,
  type ResultSet,
  type WorkoutRecord,
} from './model';

export const exerciseVolume = (exercise: RecordExercise): number =>
  exercise.sets.reduce((total, set) => total + set.weight * set.reps, 0);
export const recordVolume = (record: WorkoutRecord): number =>
  record.exercises.reduce((total, exercise) => total + exerciseVolume(exercise), 0);
export const recordSetCount = (record: WorkoutRecord): number =>
  record.exercises.reduce((total, exercise) => total + exercise.sets.length, 0);
/** Real duration in seconds, from the stored start to the finish. */
export const recordDuration = (record: WorkoutRecord): number =>
  Math.max(0, (Date.parse(record.endedAt) - Date.parse(record.startedAt)) / 1000);
/** Newest first, ties by id, like the iPhone. */
export const sortRecords = (records: readonly WorkoutRecord[]): WorkoutRecord[] =>
  [...records].sort(
    (a, b) => Date.parse(b.endedAt) - Date.parse(a.endedAt) || (a.id < b.id ? 1 : -1),
  );

export interface WeekDay {
  key: string;
  index: number;
  isDone: boolean;
  isToday: boolean;
}
export interface WeekState {
  days: WeekDay[];
  done: number;
  goal: number;
  habitTitle: string | null;
}
export const workoutDays = (records: readonly WorkoutRecord[], timeZone: string): Set<string> =>
  new Set(records.map((record) => dateKey(record.endedAt, timeZone)));

/** The days a habit is planned in a week: its current weekdays (all seven when none), at least 1. */
export function weeklyGoal(habit: Habit): number {
  const weekdays = habit.periods?.at(-1)?.weekdays ?? habit.weekdays ?? [0, 1, 2, 3, 4, 5, 6];
  return Math.max(1, new Set(weekdays).size);
}

export function weekState(
  habit: Habit | null,
  records: readonly WorkoutRecord[],
  today: string,
  timeZone: string,
): WeekState {
  const logged = habit ? new Set<string>() : workoutDays(records, timeZone);
  const days = weekKeys(today).map((key, index) => ({
    key,
    index,
    isDone: habit ? habitCompleteOn(habit, key) : logged.has(key),
    isToday: key === today,
  }));
  return {
    days,
    done: days.filter((day) => day.isDone).length,
    goal: habit ? weeklyGoal(habit) : FALLBACK_WEEKLY_GOAL,
    habitTitle: habit?.title ?? null,
  };
}
/** A linked habit that is not loaded yet: no numbers, nothing done. */
export const pendingWeek = (today: string): WeekState => ({
  days: weekKeys(today).map((key, index) => ({
    key,
    index,
    isDone: false,
    isToday: key === today,
  })),
  done: 0,
  goal: 0,
  habitTitle: null,
});

export function weekVolume(
  records: readonly WorkoutRecord[],
  weekStarting: string,
  timeZone: string,
): number {
  const keys = new Set(weekKeys(weekStarting));
  return records
    .filter((record) => keys.has(dateKey(record.endedAt, timeZone)))
    .reduce((total, record) => total + recordVolume(record), 0);
}
/** This week's volume and its change against the whole last week (null without a last week). */
export function volumeTrend(
  records: readonly WorkoutRecord[],
  today: string,
  timeZone: string,
): { volume: number; percent: number | null } {
  const start = weekStart(today);
  const volume = weekVolume(records, start, timeZone);
  const last = weekVolume(records, addDays(start, -7), timeZone);
  return { volume, percent: last > 0 ? Math.round(((volume - last) / last) * 100) : null };
}
/** Weeks in a row with at least one workout; this week counts once it has one. */
export function streakWeeks(
  records: readonly WorkoutRecord[],
  today: string,
  timeZone: string,
): number {
  const weeks = new Set([...workoutDays(records, timeZone)].map(weekStart));
  let week = weekStart(today);
  if (!weeks.has(week)) week = addDays(week, -7);
  let count = 0;
  while (weeks.has(week)) {
    count++;
    week = addDays(week, -7);
  }
  return count;
}

/** Heaviest set; bodyweight (0 kg) sets compete by reps. First on a tie. */
export function bestSetIndex(sets: readonly ResultSet[]): number | null {
  let best: number | null = null;
  sets.forEach((set, index) => {
    if (best === null) best = index;
    else if (
      set.weight > sets[best].weight ||
      (set.weight === sets[best].weight && set.reps > sets[best].reps)
    )
      best = index;
  });
  return best;
}
const heaviest = (sets: readonly ResultSet[]): ResultSet | undefined =>
  sets
    .filter((set) => set.weight > 0)
    .reduce<ResultSet | undefined>(
      (top, set) =>
        !top || set.weight > top.weight || (set.weight === top.weight && set.reps > top.reps)
          ? set
          : top,
      undefined,
    );

/** The best set of each exercise over the history (bodyweight is not a record). */
export function derivedRecords(records: readonly WorkoutRecord[]): Map<string, RecordCard> {
  const best = new Map<string, RecordCard>();
  const oldestFirst = [...records].sort((a, b) => Date.parse(a.endedAt) - Date.parse(b.endedAt));
  for (const record of oldestFirst)
    for (const exercise of record.exercises) {
      const top = heaviest(exercise.sets);
      if (!top) continue;
      const current = best.get(exercise.exerciseID);
      if (
        current &&
        (top.weight < current.weight || (top.weight === current.weight && top.reps <= current.reps))
      )
        continue;
      best.set(exercise.exerciseID, {
        exerciseID: exercise.exerciseID,
        name: exercise.name,
        weight: top.weight,
        reps: top.reps,
        date: record.endedAt,
        isStored: false,
      });
    }
  return best;
}
/** Cards to show, newest first: history, then the owner's docs on top (changed replaces, deleted hides). */
export function resolveRecords(
  records: readonly WorkoutRecord[],
  bests: readonly Best[],
): RecordCard[] {
  const cards = derivedRecords(records);
  for (const item of bests) {
    if (item.deleted) cards.delete(item.exerciseID);
    else if (item.weight > 0)
      cards.set(item.exerciseID, {
        exerciseID: item.exerciseID,
        name: item.name,
        weight: item.weight,
        reps: item.reps,
        date: item.date,
        isStored: true,
      });
  }
  return [...cards.values()].sort(
    (a, b) => Date.parse(b.date) - Date.parse(a.date) || a.name.localeCompare(b.name),
  );
}

export interface RecordBeat {
  exerciseID: string;
  name: string;
  weight: number;
  reps: number;
  previousWeight: number;
}
/** Records a finished workout beats, and the docs to store for them. A deleted record returns quietly. */
export function recordUpdates(
  finished: WorkoutRecord,
  before: readonly RecordCard[],
  bests: readonly Best[],
): { changed: Best[]; beats: RecordBeat[] } {
  const changed: Best[] = [];
  const beats: RecordBeat[] = [];
  for (const exercise of finished.exercises) {
    const top = heaviest(exercise.sets);
    if (!top) continue;
    const entry: Best = {
      exerciseID: exercise.exerciseID,
      name: exercise.name,
      weight: top.weight,
      reps: top.reps,
      date: finished.endedAt,
      deleted: false,
    };
    const current = before.find((card) => card.exerciseID === exercise.exerciseID);
    if (current) {
      if (top.weight <= current.weight) continue;
      changed.push(entry);
      beats.push({ ...entry, previousWeight: current.weight });
    } else if (bests.find((best) => best.exerciseID === exercise.exerciseID)?.deleted)
      changed.push(entry);
  }
  return { changed, beats };
}

/** The set that was a personal record when this workout was done, by exercise id. */
export function recordSets(
  record: WorkoutRecord,
  history: readonly WorkoutRecord[],
): Record<string, number> {
  const earlier = history.filter(
    (item) => item.id !== record.id && Date.parse(item.endedAt) < Date.parse(record.endedAt),
  );
  const result: Record<string, number> = {};
  for (const exercise of record.exercises) {
    const index = bestSetIndex(exercise.sets);
    if (index === null || exercise.sets[index].weight <= 0) continue;
    const before = Math.max(
      0,
      ...earlier
        .flatMap((item) => item.exercises)
        .filter((other) => other.exerciseID === exercise.exerciseID)
        .flatMap((other) => other.sets.map((set) => set.weight)),
    );
    if (before > 0 && exercise.sets[index].weight > before) result[exercise.exerciseID] = index;
  }
  return result;
}

/** The last time this exercise was done in a completed workout (by id only). */
export function lastResult(
  records: readonly WorkoutRecord[],
  exerciseID: string,
): { date: string; sets: ResultSet[] } | null {
  let best: { date: string; sets: ResultSet[] } | null = null;
  for (const record of records) {
    const found = record.exercises.find(
      (item) => item.exerciseID === exerciseID && item.sets.length,
    );
    if (found && (!best || Date.parse(record.endedAt) > Date.parse(best.date)))
      best = { date: record.endedAt, sets: found.sets };
  }
  return best;
}
