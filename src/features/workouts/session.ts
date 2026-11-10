/** The workout in progress: a snapshot of a program plus what was ticked (WorkoutSession of RitmCore). */
import { toWireDate } from './dates';
import { makeItem } from './codec';
import { moving } from './library';
import { lastResult } from './stats';
import { isBlank, normalizedWeight, parseReps, parseWeight, formatWeight } from './numbers';
import {
  DEFAULT_REPS,
  DEFAULT_REST,
  MAX_SESSION_SETS,
  REPS_RANGE,
  REST_RANGE,
  REST_STEP,
  clamp,
  newId,
  type Program,
  type ProgramItem,
  type ResultSet,
  type WorkoutRecord,
} from './model';

export interface SessionSet {
  id: string;
  weight: string;
  reps: string;
  done: boolean;
  edited: boolean;
}
export interface SessionItem {
  id: string;
  exerciseID: string;
  name: string;
  previous: { date: string; sets: ResultSet[] } | null;
  sharedWeight: string;
  sets: SessionSet[];
  restSeconds: number;
  plannedReps: number;
  keptForLog: boolean;
}
export interface Session {
  id: string;
  programID: string;
  programName: string;
  startedAt: string;
  items: SessionItem[];
}
export type TickResult = 'done' | 'undone' | 'needsWeight' | 'needsReps' | 'missing';
export type SessionField = 'sets' | 'reps' | 'rest';

const doneCount = (item: SessionItem) => item.sets.filter((set) => set.done).length;
export const minSets = (item: SessionItem) => Math.max(1, doneCount(item));
export const isOnlyInLog = (item: SessionItem) =>
  item.keptForLog && item.sets.every((set) => set.done);
export const doneSets = (session: Session) =>
  session.items.reduce((total, item) => total + doneCount(item), 0);
export const totalSessionSets = (session: Session) =>
  session.items.reduce((total, item) => total + item.sets.length, 0);
export const itemDone = doneCount;

/** An exercise of a workout: sets pre-filled from the last result of THIS exercise id (never counted as done). */
export function makeSessionItem(
  history: readonly WorkoutRecord[],
  fields: {
    exerciseID: string;
    name: string;
    setCount: number;
    plannedReps?: number;
    restSeconds?: number;
  },
): SessionItem {
  const previous = lastResult(history, fields.exerciseID);
  const sets = Array.from({ length: Math.max(1, fields.setCount) }, (_, index) => {
    const result = previous ? (previous.sets[index] ?? previous.sets.at(-1)) : undefined;
    return {
      id: newId(),
      weight: result ? formatWeight(result.weight, false) : '',
      reps: result ? String(result.reps) : fields.plannedReps ? String(fields.plannedReps) : '',
      done: false,
      edited: false,
    };
  });
  return {
    id: newId(),
    exerciseID: fields.exerciseID,
    name: fields.name,
    previous,
    sharedWeight: '',
    sets,
    restSeconds: fields.restSeconds ?? DEFAULT_REST,
    plannedReps: clamp(fields.plannedReps ?? DEFAULT_REPS, REPS_RANGE),
    keptForLog: false,
  };
}

/** «Начать тренировку»: a separate snapshot of the program as it is now. Null for an empty program. */
export function startSession(
  program: Program,
  history: readonly WorkoutRecord[],
  nameOf: (exerciseID: string) => string,
  now: Date,
): Session | null {
  if (!program.items.length) return null;
  return {
    id: newId(),
    programID: program.id,
    programName: program.name,
    startedAt: toWireDate(now),
    items: program.items.map((item) =>
      makeSessionItem(history, {
        exerciseID: item.exerciseID,
        name: nameOf(item.exerciseID),
        setCount: item.sets,
        plannedReps: item.reps,
        restSeconds: item.restSeconds,
      }),
    ),
  };
}

const mapItem = (
  session: Session,
  itemID: string,
  change: (item: SessionItem) => SessionItem,
): Session => ({
  ...session,
  items: session.items.map((item) => (item.id === itemID ? change(item) : item)),
});
const mapSet = (item: SessionItem, setID: string, change: (set: SessionSet) => SessionSet) => ({
  ...item,
  sets: item.sets.map((set) => (set.id === setID ? change(set) : set)),
});

/** A weight typed into the leading set is copied into the other unfinished sets the owner did not set by hand. */
export function typeWeight(session: Session, itemID: string, setID: string, text: string) {
  return mapItem(session, itemID, (item) => {
    const index = item.sets.findIndex((set) => set.id === setID);
    if (index < 0 || item.sets[index].done) return item;
    const leader = item.sets.findIndex((set) => !set.done);
    const typed = mapSet(item, setID, (set) => ({
      ...set,
      weight: text,
      edited: index === leader ? false : !isBlank(text),
    }));
    if (index !== leader) return typed;
    const shared = normalizedWeight(text);
    if (shared === null) return typed;
    return {
      ...typed,
      sharedWeight: shared,
      sets: typed.sets.map((set, other) =>
        other !== index && !set.done && !set.edited ? { ...set, weight: shared } : set,
      ),
    };
  });
}
export const typeReps = (session: Session, itemID: string, setID: string, text: string) =>
  mapItem(session, itemID, (item) =>
    mapSet(item, setID, (set) => (set.done ? set : { ...set, reps: text })),
  );

/** Ticks or unticks a set; a tick needs a valid weight and reps (values are cleaned up then). */
export function toggleSet(
  session: Session,
  itemID: string,
  setID: string,
): { session: Session; result: TickResult } {
  const item = session.items.find((candidate) => candidate.id === itemID);
  const set = item?.sets.find((candidate) => candidate.id === setID);
  if (!item || !set) return { session, result: 'missing' };
  if (set.done)
    return {
      session: mapItem(session, itemID, (it) => mapSet(it, setID, (s) => ({ ...s, done: false }))),
      result: 'undone',
    };
  const weight = normalizedWeight(set.weight);
  if (weight === null || parseWeight(set.weight) === null)
    return { session, result: 'needsWeight' };
  const reps = parseReps(set.reps);
  if (reps === null) return { session, result: 'needsReps' };
  return {
    session: mapItem(session, itemID, (it) =>
      mapSet(it, setID, (s) => ({ ...s, weight, reps: String(reps), done: true })),
    ),
    result: 'done',
  };
}

const newSet = (item: SessionItem): SessionSet => ({
  id: newId(),
  weight: isBlank(item.sharedWeight) ? (item.sets.at(-1)?.weight ?? '') : item.sharedWeight,
  reps: '',
  done: false,
  edited: false,
});
export const addSet = (session: Session, itemID: string): Session =>
  mapItem(session, itemID, (item) =>
    item.sets.length < MAX_SESSION_SETS ? { ...item, sets: [...item.sets, newSet(item)] } : item,
  );
/** Removes the last set that is not done. The last remaining set stays. */
export const removeLastOpenSet = (session: Session, itemID: string): Session =>
  mapItem(session, itemID, (item) => {
    const last = item.sets.findLastIndex((set) => !set.done);
    return last < 0 || item.sets.length < 2
      ? item
      : { ...item, sets: item.sets.filter((_, index) => index !== last) };
  });

function allowedRange(item: SessionItem, field: SessionField): readonly [number, number] {
  return field === 'sets'
    ? [minSets(item), MAX_SESSION_SETS]
    : field === 'reps'
      ? REPS_RANGE
      : REST_RANGE;
}
const fieldOf = (item: SessionItem, field: SessionField) =>
  field === 'sets' ? item.sets.length : field === 'reps' ? item.plannedReps : item.restSeconds;
export function canStepSession(item: SessionItem, field: SessionField, direction: 1 | -1) {
  const [low, high] = allowedRange(item, field);
  const next = fieldOf(item, field) + direction * (field === 'rest' ? REST_STEP : 1);
  return next >= low && next <= high;
}
export function stepSession(
  session: Session,
  itemID: string,
  field: SessionField,
  direction: 1 | -1,
): Session {
  return mapItem(session, itemID, (item) => {
    if (!canStepSession(item, field, direction)) return item;
    if (field === 'sets') {
      let next = item;
      if (direction > 0) next = { ...item, sets: [...item.sets, newSet(item)] };
      else {
        const last = item.sets.findLastIndex((set) => !set.done);
        next = { ...item, sets: item.sets.filter((_, index) => index !== last) };
      }
      return next;
    }
    if (field === 'reps') {
      const reps = clamp(item.plannedReps + direction, REPS_RANGE);
      return {
        ...item,
        plannedReps: reps,
        sets: item.sets.map((set) => (set.done ? set : { ...set, reps: String(reps) })),
      };
    }
    return { ...item, restSeconds: clamp(item.restSeconds + direction * REST_STEP, REST_RANGE) };
  });
}

/** Replaces an exercise DURING the workout; done sets stay logged under the old one. Null when nothing changed. */
export function replaceExercise(
  session: Session,
  itemID: string,
  exerciseID: string,
  name: string,
  history: readonly WorkoutRecord[],
): { session: Session; newItemID: string } | null {
  const index = session.items.findIndex((item) => item.id === itemID);
  if (index < 0 || session.items.some((item) => item.exerciseID === exerciseID)) return null;
  const old = session.items[index];
  const replacement = makeSessionItem(history, {
    exerciseID,
    name,
    setCount: Math.max(1, old.sets.length),
    plannedReps: old.plannedReps,
    restSeconds: old.restSeconds,
  });
  const items = [...session.items];
  if (old.sets.some((set) => set.done)) {
    items[index] = { ...old, sets: old.sets.filter((set) => set.done), keptForLog: true };
    items.splice(index + 1, 0, replacement);
  } else items[index] = replacement;
  return { session: { ...session, items }, newItemID: replacement.id };
}
/** A new exercise: 3 sets of 10 and the default rest. Null when it is already in the workout. */
export function addExercise(
  session: Session,
  exerciseID: string,
  name: string,
  history: readonly WorkoutRecord[],
  after?: number,
): { session: Session; newItemID: string } | null {
  if (session.items.some((item) => item.exerciseID === exerciseID)) return null;
  const item = makeSessionItem(history, {
    exerciseID,
    name,
    setCount: 3,
    plannedReps: DEFAULT_REPS,
  });
  const at =
    after === undefined ? session.items.length : clamp(after + 1, [0, session.items.length]);
  const items = [...session.items];
  items.splice(at, 0, item);
  return { session: { ...session, items }, newItemID: item.id };
}
/** A workout keeps at least one exercise. */
export const removeExercise = (session: Session, itemID: string): Session =>
  session.items.length > 1
    ? { ...session, items: session.items.filter((item) => item.id !== itemID) }
    : session;
export const moveExercise = (session: Session, from: number, to: number): Session => ({
  ...session,
  items: moving(session.items, from, to),
});

/** The history entry for what was ticked; null when nothing was. Only done sets count. */
export function finishSession(session: Session, end: Date): WorkoutRecord | null {
  const exercises = session.items.flatMap((item) => {
    const sets = item.sets.flatMap((set) => {
      const weight = parseWeight(set.weight);
      const reps = parseReps(set.reps);
      return set.done && weight !== null && reps !== null ? [{ weight, reps }] : [];
    });
    return sets.length ? [{ exerciseID: item.exerciseID, name: item.name, sets }] : [];
  });
  if (!exercises.length) return null;
  return {
    id: session.id,
    programID: session.programID,
    programName: session.programName,
    startedAt: session.startedAt,
    endedAt: toWireDate(end),
    exercises,
  };
}

// --- difference from the saved program ---------------------------------------------------------
export const sessionPlan = (item: SessionItem): ProgramItem =>
  makeItem({
    id: item.id,
    exerciseID: item.exerciseID,
    sets: item.sets.length,
    reps: item.plannedReps,
    restSeconds: item.restSeconds,
  });
export const programItems = (session: Session): ProgramItem[] =>
  session.items.filter((item) => !isOnlyInLog(item)).map(sessionPlan);

export interface ProgramChange {
  added: number;
  removed: number;
  modified: number;
  reordered: boolean;
}
/** Null when the workout still matches the program (exercises, order, sets, reps, rest). */
export function changeFrom(session: Session, program: Program): ProgramChange | null {
  const mine = programItems(session);
  if (!mine.length) return null;
  const theirs = program.items;
  const mineIds = new Set(mine.map((item) => item.exerciseID));
  const theirIds = new Set(theirs.map((item) => item.exerciseID));
  const modified = mine.filter((item) => {
    const other = theirs.find((candidate) => candidate.exerciseID === item.exerciseID);
    return (
      other !== undefined &&
      (other.sets !== item.sets ||
        other.reps !== item.reps ||
        other.restSeconds !== item.restSeconds)
    );
  }).length;
  const common = (ids: Set<string>) => (id: string) => ids.has(id);
  const both = common(new Set([...mineIds].filter((id) => theirIds.has(id))));
  const change = {
    added: [...mineIds].filter((id) => !theirIds.has(id)).length,
    removed: [...theirIds].filter((id) => !mineIds.has(id)).length,
    modified,
    reordered:
      mine
        .map((item) => item.exerciseID)
        .filter(both)
        .join('|') !==
      theirs
        .map((item) => item.exerciseID)
        .filter(both)
        .join('|'),
  };
  return change.added || change.removed || change.modified || change.reordered ? change : null;
}
/** The program as the workout now has it; its id, name and colour stay. */
export function applyTo(session: Session, program: Program): Program {
  const mine = programItems(session);
  if (!mine.length) return program;
  return {
    ...program,
    items: mine.map((item) => {
      const existing = program.items.find((other) => other.exerciseID === item.exerciseID);
      return { ...item, id: existing?.id ?? item.id };
    }),
  };
}
