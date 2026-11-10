/** Server documents <-> models. Tolerant reading like Swift's `workoutValue` / `workoutLossy`. */
import {
  COLOR_COUNT,
  DEFAULT_REPS,
  DEFAULT_REST,
  NAME_LIMIT,
  REPS_RANGE,
  REST_RANGE,
  SET_RANGE,
  clamp,
  isMuscle,
  newId,
  recordDocId,
  type Best,
  type Exercise,
  type Program,
  type ProgramItem,
  type RecordExercise,
  type ResultSet,
  type WorkoutRecord,
  type WorkoutSettings,
} from './model';

type Json = Record<string, unknown>;
const isObject = (value: unknown): value is Json =>
  typeof value === 'object' && value !== null && !Array.isArray(value);
const str = (value: unknown, fallback = ''): string =>
  typeof value === 'string' ? value : fallback;
const num = (value: unknown, fallback: number): number =>
  typeof value === 'number' && Number.isFinite(value) ? value : fallback;
const lossy = <T>(value: unknown, read: (item: unknown) => T | null): T[] =>
  Array.isArray(value) ? value.flatMap((item) => read(item) ?? []) : [];
/** Swift's `.iso8601` rejects fractions, the server stores whatever was written: accept both here. */
const isDate = (value: unknown): value is string =>
  typeof value === 'string' && !Number.isNaN(Date.parse(value));

export function readExercise(value: unknown): Exercise | null {
  if (!isObject(value) || typeof value.id !== 'string') return null;
  return {
    id: value.id,
    name: str(value.name),
    muscle: isMuscle(value.muscle) ? value.muscle : null,
  };
}
export const writeExercise = (exercise: Exercise): Json => ({
  id: exercise.id,
  name: exercise.name,
  muscle: exercise.muscle,
});

export function makeItem(
  fields: Pick<ProgramItem, 'id' | 'exerciseID'> & Partial<ProgramItem>,
): ProgramItem {
  return {
    id: fields.id,
    exerciseID: fields.exerciseID,
    sets: clamp(fields.sets ?? 3, SET_RANGE),
    reps: clamp(fields.reps ?? DEFAULT_REPS, REPS_RANGE),
    restSeconds: clamp(fields.restSeconds ?? DEFAULT_REST, REST_RANGE),
  };
}
function readItem(value: unknown): ProgramItem | null {
  if (!isObject(value) || typeof value.exerciseID !== 'string') return null;
  return makeItem({
    id: str(value.id) || newId(),
    exerciseID: value.exerciseID,
    sets: Math.round(num(value.sets, 3)),
    reps: Math.round(num(value.reps, DEFAULT_REPS)),
    restSeconds: Math.round(num(value.restSeconds, DEFAULT_REST)),
  });
}

export interface ProgramDoc {
  program: Program;
  order: number | null;
  exercises: Exercise[];
}
export function readProgram(id: string, data: unknown): ProgramDoc | null {
  if (!isObject(data)) return null;
  const program: Program = {
    id,
    name: str(data.name),
    items: lossy(data.items, readItem),
    colorIndex: clamp(Math.round(num(data.colorIndex, 0)), [0, COLOR_COUNT - 1]),
  };
  const order = typeof data.order === 'number' && Number.isFinite(data.order) ? data.order : null;
  return { program, order, exercises: lossy(data.exercises, readExercise) };
}
/** Fields the iPhone writes for a program; `raw` keeps any key this client does not know. */
export function writeProgram(
  program: Program,
  order: number,
  used: readonly Exercise[],
  raw: Json = {},
): Json {
  return {
    ...raw,
    id: program.id,
    name: program.name,
    colorIndex: program.colorIndex,
    items: program.items.map((item) => ({
      id: item.id,
      exerciseID: item.exerciseID,
      sets: item.sets,
      reps: item.reps,
      restSeconds: item.restSeconds,
    })),
    order,
    exercises: used.map(writeExercise),
  };
}

function readResultSet(value: unknown): ResultSet | null {
  if (!isObject(value) || typeof value.weight !== 'number' || typeof value.reps !== 'number')
    return null;
  return { weight: value.weight, reps: Math.round(value.reps) };
}
function readRecordExercise(value: unknown): RecordExercise | null {
  if (!isObject(value) || typeof value.exerciseID !== 'string') return null;
  return {
    exerciseID: value.exerciseID,
    name: str(value.name),
    sets: lossy(value.sets, readResultSet),
  };
}
export function readRecord(id: string, data: unknown): WorkoutRecord | null {
  if (!isObject(data) || !isDate(data.endedAt)) return null;
  return {
    id,
    programID: str(data.programID),
    programName: str(data.programName),
    startedAt: isDate(data.startedAt) ? data.startedAt : data.endedAt,
    endedAt: data.endedAt,
    exercises: lossy(data.exercises, readRecordExercise),
  };
}
export const writeRecord = (record: WorkoutRecord, raw: Json = {}): Json => ({
  ...raw,
  id: record.id,
  programID: record.programID,
  programName: record.programName,
  startedAt: record.startedAt,
  endedAt: record.endedAt,
  exercises: record.exercises.map((exercise) => ({
    exerciseID: exercise.exerciseID,
    name: exercise.name,
    sets: exercise.sets.map((set) => ({ weight: set.weight, reps: set.reps })),
  })),
});

export function readBest(data: unknown): Best | null {
  if (!isObject(data) || typeof data.exerciseID !== 'string') return null;
  return {
    exerciseID: data.exerciseID,
    name: str(data.name),
    weight: num(data.weight, 0),
    reps: Math.round(num(data.reps, 1)),
    date: isDate(data.date) ? data.date : '1970-01-01T00:00:00Z',
    deleted: data.deleted === true,
  };
}
export const writeBest = (best: Best, raw: Json = {}): Json => ({
  ...raw,
  exerciseID: best.exerciseID,
  name: best.name,
  weight: best.weight,
  reps: best.reps,
  date: best.date,
  deleted: best.deleted,
});
export const bestDocId = (best: Best) => recordDocId(best.exerciseID);

export function readSettings(data: unknown): WorkoutSettings {
  const fields = isObject(data) ? data : {};
  return {
    linkedHabitID: typeof fields.linkedHabitID === 'string' ? fields.linkedHabitID : null,
    lastTickedDay: typeof fields.lastTickedDay === 'string' ? fields.lastTickedDay : null,
  };
}
/** Optional keys are left out when empty, exactly like Swift's synthesized encoder. */
export const writeSettings = (settings: WorkoutSettings, raw: Json = {}): Json => {
  const { linkedHabitID: _a, lastTickedDay: _b, ...rest } = raw;
  return {
    ...rest,
    ...(settings.linkedHabitID ? { linkedHabitID: settings.linkedHabitID } : {}),
    ...(settings.lastTickedDay ? { lastTickedDay: settings.lastTickedDay } : {}),
  };
};
export const isDefaultSettings = (settings: WorkoutSettings) =>
  settings.linkedHabitID === null && settings.lastTickedDay === null;
export const clampName = (value: string): string =>
  value.split(/\s+/).filter(Boolean).join(' ').slice(0, NAME_LIMIT);
