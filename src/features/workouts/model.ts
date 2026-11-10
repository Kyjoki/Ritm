/** Models of «Тренировки». They mirror the Swift RitmCore models field for field (ids, names, units). */
export type MuscleKey = 'chest' | 'back' | 'legs' | 'shoulders' | 'biceps' | 'triceps' | 'abs';
export const MUSCLES: readonly MuscleKey[] = [
  'chest',
  'back',
  'legs',
  'shoulders',
  'biceps',
  'triceps',
  'abs',
];
export const MUSCLE_TITLES: Record<MuscleKey, string> = {
  chest: 'Грудь',
  back: 'Спина',
  legs: 'Ноги',
  shoulders: 'Плечи',
  biceps: 'Бицепс',
  triceps: 'Трицепс',
  abs: 'Пресс',
};
export const isMuscle = (value: unknown): value is MuscleKey =>
  typeof value === 'string' && (MUSCLES as readonly string[]).includes(value);

export interface Exercise {
  id: string;
  name: string;
  muscle: MuscleKey | null;
}
export interface ProgramItem {
  id: string;
  exerciseID: string;
  sets: number;
  reps: number;
  restSeconds: number;
}
export interface Program {
  id: string;
  name: string;
  items: ProgramItem[];
  colorIndex: number;
}
export interface ResultSet {
  weight: number;
  reps: number;
}
export interface RecordExercise {
  exerciseID: string;
  name: string;
  sets: ResultSet[];
}
/** One completed workout (the «sessions» doc). */
export interface WorkoutRecord {
  id: string;
  programID: string;
  programName: string;
  startedAt: string;
  endedAt: string;
  exercises: RecordExercise[];
}
/** A manual record or the tombstone of a deleted one (the «records» doc). */
export interface Best {
  exerciseID: string;
  name: string;
  weight: number;
  reps: number;
  date: string;
  deleted: boolean;
}
export interface WorkoutSettings {
  linkedHabitID: string | null;
  lastTickedDay: string | null;
}
export interface RecordCard {
  exerciseID: string;
  name: string;
  weight: number;
  reps: number;
  date: string;
  isStored: boolean;
}

export const SET_RANGE = [1, 10] as const;
export const REPS_RANGE = [1, 99] as const;
export const REST_RANGE = [15, 900] as const;
export const REST_STEP = 15;
export const DEFAULT_REPS = 10;
export const DEFAULT_REST = 180;
export const MAX_SESSION_SETS = 12;
export const NAME_LIMIT = 40;
export const COLOR_COUNT = 6;
export const SETTINGS_DOC_ID = 'workouts';
export const FALLBACK_WEEKLY_GOAL = 4;

export const clamp = (value: number, [low, high]: readonly [number, number]) =>
  Math.min(Math.max(value, low), high);

const BUILTIN: ReadonlyArray<readonly [string, string, string, MuscleKey]> = [
  ['bench', 'Жим лёжа', 'Bench press', 'chest'],
  ['incline', 'Жим гантелей на наклонной', 'Incline dumbbell press', 'chest'],
  ['fly', 'Разводка гантелей', 'Dumbbell fly', 'chest'],
  ['dips', 'Отжимания на брусьях', 'Dips', 'chest'],
  ['crossover', 'Сведение в кроссовере', 'Cable crossover', 'chest'],
  ['deadlift', 'Становая тяга', 'Deadlift', 'back'],
  ['pullup', 'Подтягивания', 'Pull-up', 'back'],
  ['row', 'Тяга штанги в наклоне', 'Barbell row', 'back'],
  ['pulldown', 'Тяга верхнего блока', 'Lat pulldown', 'back'],
  ['dbrow', 'Тяга гантели одной рукой', 'One-arm dumbbell row', 'back'],
  ['cablerow', 'Тяга нижнего блока', 'Seated cable row', 'back'],
  ['squat', 'Присед со штангой', 'Barbell squat', 'legs'],
  ['legpress', 'Жим ногами', 'Leg press', 'legs'],
  ['rdl', 'Румынская тяга', 'Romanian deadlift', 'legs'],
  ['lunge', 'Выпады с гантелями', 'Dumbbell lunge', 'legs'],
  ['legcurl', 'Сгибание ног лёжа', 'Lying leg curl', 'legs'],
  ['ohp', 'Жим стоя', 'Overhead press', 'shoulders'],
  ['lateral', 'Махи гантелями в стороны', 'Lateral raise', 'shoulders'],
  ['arnold', 'Жим Арнольда', 'Arnold press', 'shoulders'],
  ['upright', 'Тяга к подбородку', 'Upright row', 'shoulders'],
  ['reardelt', 'Задние дельты в тренажёре', 'Rear delt machine', 'shoulders'],
  ['curl', 'Подъём штанги на бицепс', 'Barbell curl', 'biceps'],
  ['hammer', 'Молотки', 'Hammer curl', 'biceps'],
  ['preacher', 'Сгибания на скамье Скотта', 'Preacher curl', 'biceps'],
  ['french', 'Французский жим', 'Skull crusher', 'triceps'],
  ['pushdown', 'Разгибания на блоке', 'Triceps pushdown', 'triceps'],
  ['closegrip', 'Жим узким хватом', 'Close-grip bench press', 'triceps'],
  ['crunch', 'Скручивания', 'Crunch', 'abs'],
  ['legraise', 'Подъём ног в висе', 'Hanging leg raise', 'abs'],
  ['twist', 'Русские скручивания', 'Russian twist', 'abs'],
];

export const builtinID = (key: string) => `builtin.${key}`;
export const customID = (uuid: string) => `custom.${uuid}`;
export const BENCH_ID = builtinID('bench');

export function builtinExercises(language: 'ru' | 'en'): Exercise[] {
  return BUILTIN.map(([key, ru, en, muscle]) => ({
    id: builtinID(key),
    name: language === 'ru' ? ru : en,
    muscle,
  }));
}
export const allExercises = (custom: readonly Exercise[], language: 'ru' | 'en'): Exercise[] => [
  ...builtinExercises(language),
  ...custom,
];
export const findExercise = (id: string, custom: readonly Exercise[], language: 'ru' | 'en') =>
  allExercises(custom, language).find((exercise) => exercise.id === id);
export const exerciseName = (
  id: string,
  custom: readonly Exercise[],
  language: 'ru' | 'en',
  fallback = 'Упражнение',
) => findExercise(id, custom, language)?.name ?? fallback;
export const muscleOf = (id: string, custom: readonly Exercise[]): MuscleKey | null =>
  findExercise(id, custom, 'ru')?.muscle ?? null;

/** RFC 4122 v4 id, upper-case like Swift's UUID().uuidString (accepted by the server id rule). */
export function newId(): string {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = [...bytes].map((byte) => byte.toString(16).padStart(2, '0')).join('');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`.toUpperCase();
}
/** The server accepts 1–64 characters of letters, digits, `_` and `-`. */
export const isValidDocId = (id: string) => /^[A-Za-z0-9_-]{1,64}$/.test(id);
/** Doc id of an exercise's record: `rec-` and the exercise id with `.` turned into `-`. */
export const recordDocId = (exerciseID: string) => `rec-${exerciseID.replaceAll('.', '-')}`;
