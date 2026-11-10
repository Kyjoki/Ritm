/** Pure, immutable operations on programs and the editor draft (WorkoutPlan / WorkoutDraft of RitmCore). */
import { makeItem, clampName } from './codec';
import {
  COLOR_COUNT,
  NAME_LIMIT,
  REPS_RANGE,
  REST_RANGE,
  REST_STEP,
  SET_RANGE,
  allExercises,
  customID,
  newId,
  type Exercise,
  type MuscleKey,
  type Program,
  type ProgramItem,
  type WorkoutRecord,
} from './model';

export type PlanField = 'sets' | 'reps' | 'rest';
const RANGES = { sets: SET_RANGE, reps: REPS_RANGE, rest: REST_RANGE } as const;
const STEPS = { sets: 1, reps: 1, rest: REST_STEP } as const;
const FIELD_KEY = { sets: 'sets', reps: 'reps', rest: 'restSeconds' } as const;

export function moving<T>(items: readonly T[], from: number, to: number): T[] {
  if (from === to || !(from in items) || !(to in items)) return [...items];
  const next = [...items];
  const [moved] = next.splice(from, 1);
  next.splice(to, 0, moved);
  return next;
}

export const totalSets = (program: Program): number =>
  program.items.reduce((total, item) => total + item.sets, 0);
/** «≈ 35 мин»: about four minutes a set and three to get started. */
export const estimatedMinutes = (program: Program): number => totalSets(program) * 4 + 3;

export interface Draft {
  name: string;
  colorIndex: number;
  items: ProgramItem[];
}
export const draftOf = (program?: Program): Draft =>
  program
    ? { name: program.name, colorIndex: program.colorIndex, items: program.items }
    : { name: '', colorIndex: 0, items: [] };
export const canSaveDraft = (draft: Draft) =>
  clampName(draft.name) !== '' && draft.items.length > 0;
export const withName = (draft: Draft, name: string): Draft => ({
  ...draft,
  name: name.slice(0, NAME_LIMIT),
});
export const withColor = (draft: Draft, colorIndex: number): Draft => ({
  ...draft,
  colorIndex: Math.min(Math.max(colorIndex, 0), COLOR_COUNT - 1),
});
/** A new exercise gets 3 sets of 10 and the default rest; a duplicate is refused (null). */
export function withExercise(draft: Draft, exerciseID: string): Draft | null {
  if (draft.items.some((item) => item.exerciseID === exerciseID)) return null;
  return { ...draft, items: [...draft.items, makeItem({ id: newId(), exerciseID, sets: 3 })] };
}
export const withoutItem = (draft: Draft, itemID: string): Draft => ({
  ...draft,
  items: draft.items.filter((item) => item.id !== itemID),
});
export const withMovedItem = (draft: Draft, from: number, to: number): Draft => ({
  ...draft,
  items: moving(draft.items, from, to),
});

export const fieldValue = (item: ProgramItem, field: PlanField): number =>
  field === 'rest' ? item.restSeconds : item[field];
export function canStepItem(item: ProgramItem, field: PlanField, direction: 1 | -1): boolean {
  const [low, high] = RANGES[field];
  const next = fieldValue(item, field) + direction * STEPS[field];
  return next >= low && next <= high;
}
export function stepItem(draft: Draft, itemID: string, field: PlanField, direction: 1 | -1): Draft {
  return {
    ...draft,
    items: draft.items.map((item) =>
      item.id === itemID && canStepItem(item, field, direction)
        ? { ...item, [FIELD_KEY[field]]: fieldValue(item, field) + direction * STEPS[field] }
        : item,
    ),
  };
}

/** Writes the draft as program `id`: replaces it or appends a new one. Null when it cannot be saved. */
export function saveDraft(
  programs: readonly Program[],
  draft: Draft,
  id: string,
): Program[] | null {
  if (!canSaveDraft(draft)) return null;
  const program: Program = {
    id,
    name: clampName(draft.name),
    items: draft.items,
    colorIndex: draft.colorIndex,
  };
  return programs.some((item) => item.id === id)
    ? programs.map((item) => (item.id === id ? program : item))
    : [...programs, program];
}

/** The owner's own exercise. An existing name (any language, any case) returns that exercise. */
export function createExercise(
  custom: readonly Exercise[],
  raw: string,
  muscle: MuscleKey | null,
): { exercise: Exercise; created: boolean } | null {
  const name = clampName(raw);
  if (name.length < 2) return null;
  const key = name.toLowerCase();
  for (const language of ['ru', 'en'] as const) {
    const found = allExercises(custom, language).find((item) => item.name.toLowerCase() === key);
    if (found) return { exercise: found, created: false };
  }
  return { exercise: { id: customID(newId()), name, muscle }, created: true };
}

export const filterExercises = (
  exercises: readonly Exercise[],
  query: string,
  filter: 'any' | 'none' | MuscleKey,
): Exercise[] => {
  const key = query.trim().toLowerCase();
  return exercises.filter(
    (item) =>
      (filter === 'any' || (filter === 'none' ? item.muscle === null : item.muscle === filter)) &&
      (!key || item.name.toLowerCase().includes(key)),
  );
};

export const lastDoneAt = (records: readonly WorkoutRecord[], programID: string): string | null =>
  records.reduce<string | null>(
    (last, record) =>
      record.programID === programID && (!last || Date.parse(record.endedAt) > Date.parse(last))
        ? record.endedAt
        : last,
    null,
  );
/** The program done longest ago (never done first): the «next workout» card. */
export function nextProgram(
  programs: readonly Program[],
  records: readonly WorkoutRecord[],
): Program | null {
  const rank = (program: Program) => {
    const last = lastDoneAt(records, program.id);
    return last ? Date.parse(last) : -Infinity;
  };
  return [...programs].sort((a, b) => rank(a) - rank(b))[0] ?? null;
}
