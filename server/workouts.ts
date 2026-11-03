import { z } from 'zod';
import type { WorkoutDoc, WorkoutKind } from '../shared/types.ts';
import { AppError } from './errors.ts';

export const MAX_WORKOUT_DATA_BYTES = 64 * 1024;
export const MAX_WORKOUT_DOCS: Record<WorkoutKind, number> = { programs: 300, sessions: 10_000 };

export const workoutKindSchema = z.enum(['programs', 'sessions']);
export const workoutIdSchema = z.string().regex(/^[A-Za-z0-9_-]{1,64}$/);

const workoutDataSchema = z
  .record(z.string(), z.unknown())
  .refine((data) => Buffer.byteLength(JSON.stringify(data), 'utf8') <= MAX_WORKOUT_DATA_BYTES);

export const workoutPutSchema = z
  .object({ data: workoutDataSchema, expectedUpdatedAt: z.iso.datetime().nullable() })
  .strict();
export const workoutDeleteQuerySchema = z.object({ expectedUpdatedAt: z.iso.datetime() }).strict();

/** 409 carrying the stored document so the client can merge without another GET. */
export class WorkoutConflictError extends AppError {
  constructor(public current: WorkoutDoc) {
    super(409, 'CONFLICT', 'Тренировка изменилась. Обновите данные и повторите действие.');
    this.name = 'WorkoutConflictError';
  }
}

export const workoutNotFound = () =>
  new AppError(404, 'NOT_FOUND', 'Тренировка не найдена. Обновите страницу.');
export const workoutLimit = () =>
  new AppError(400, 'WORKOUT_LIMIT', 'Достигнут предел сохранённых тренировок.');

export function sameInstant(a: string, b: string) {
  return Date.parse(a) === Date.parse(b);
}

/** Shared decision for create/update so both stores behave identically. */
export function assertWorkoutPut(
  current: WorkoutDoc | undefined,
  expectedUpdatedAt: string | null,
  count: number,
  kind: WorkoutKind,
) {
  if (!current) {
    if (expectedUpdatedAt !== null) throw workoutNotFound();
    if (count >= MAX_WORKOUT_DOCS[kind]) throw workoutLimit();
    return;
  }
  if (expectedUpdatedAt === null || !sameInstant(current.updatedAt, expectedUpdatedAt))
    throw new WorkoutConflictError(current);
}

export function assertWorkoutDelete(current: WorkoutDoc | undefined, expectedUpdatedAt: string) {
  if (!current) throw workoutNotFound();
  if (!sameInstant(current.updatedAt, expectedUpdatedAt)) throw new WorkoutConflictError(current);
}
