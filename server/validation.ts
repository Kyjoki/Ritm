import { z } from 'zod';
import { CALENDAR_COLOR_IDS } from '../shared/calendar-colors.ts';

export const dateValue = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/)
  .refine((value) => {
    const date = new Date(`${value}T00:00:00.000Z`);
    return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === value;
  }, 'Укажите существующую дату.');
export const timeValue = z.string().regex(/^(?:[01]\d|2[0-3]):[0-5]\d$/);
export const calendarColorSchema = z.union([
  z.enum(CALENDAR_COLOR_IDS),
  z
    .string()
    .regex(/^#[0-9a-f]{6}$/i)
    .transform((value) => value.toLowerCase()),
]);
export const minutes = (time: string) => Number(time.slice(0, 2)) * 60 + Number(time.slice(3));

export const scheduleShape = {
  date: dateValue.nullable(),
  time: timeValue.nullable(),
  duration: z.number().int().min(5).max(720),
};
const taskFields = z
  .object({
    title: z.string().trim().min(1).max(160),
    description: z.string().trim().max(4000),
    ...scheduleShape,
    priority: z.enum(['low', 'normal', 'high']),
    repeat: z.enum(['none', 'daily', 'weekly', 'monthly']),
    kind: z.enum(['task', 'event']),
    completed: z.boolean(),
    colorId: calendarColorSchema.nullable().optional(),
    calendarEntry: z.boolean().optional(),
  })
  .strict();

export function validSchedule(value: {
  date: string | null;
  time: string | null;
  duration: number;
}) {
  return (
    !(value.time && !value.date) && (!value.time || minutes(value.time) + value.duration <= 1440)
  );
}

export function scheduleInPast(
  value: { date: string | null; time: string | null },
  timeZone: string,
  now = new Date(),
) {
  const parts = new Intl.DateTimeFormat('en', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(now);
  const get = (type: string) => parts.find((part) => part.type === type)!.value;
  const today = `${get('year')}-${get('month')}-${get('day')}`;
  const time = `${get('hour')}:${get('minute')}`;
  return Boolean(
    value.date && (value.date < today || (value.date === today && value.time && value.time < time)),
  );
}

export const taskInputSchema = taskFields
  .refine(validSchedule, 'Задайте дату для времени и завершите запись до полуночи.')
  .refine(
    (value) => value.repeat === 'none' || !value.completed,
    'Выполнение повторяющейся задачи отмечается для конкретной даты.',
  );
export const taskPatchSchema = taskFields
  .partial()
  .extend({ occurrenceDate: dateValue.optional() })
  .refine(
    (v) => Object.keys(v).length > 0 && (!v.occurrenceDate || v.completed !== undefined),
    'Нет изменений или не указано выполнение.',
  );
export const idSchema = z.string().uuid();
export const taskSchema = taskFields
  .extend({
    id: idSchema,
    createdAt: z.iso.datetime(),
    updatedAt: z.iso.datetime(),
    completedDates: z
      .array(dateValue)
      .max(5000)
      .refine((dates) => new Set(dates).size === dates.length),
  })
  .refine(validSchedule);
export const settingsPatchSchema = z
  .object({
    displayName: z.string().trim().min(1).max(60),
    email: z.union([z.literal(''), z.email().max(254)]),
    theme: z.enum(['light', 'dark', 'system']),
    sidebar: z.enum(['dark', 'light']),
    language: z.literal('ru'),
    timeZone: z
      .string()
      .max(80)
      .refine((value) => {
        try {
          new Intl.DateTimeFormat('ru', { timeZone: value });
          return true;
        } catch {
          return false;
        }
      }, 'Неизвестный часовой пояс.'),
    notifications: z.boolean(),
    dailyBriefing: z.boolean(),
    workDayStart: timeValue,
    workDayEnd: timeValue,
  })
  .strict()
  .partial()
  .refine((v) => Object.keys(v).length > 0, 'Нет изменений.');

export const modelSchema = z
  .string()
  .trim()
  .min(1)
  .max(100)
  .regex(/^[a-zA-Z0-9._:-]+$/);
export const secretSchema = z
  .object({
    apiKey: z
      .string()
      .trim()
      .min(20)
      .max(512)
      .regex(/^sk-[a-zA-Z0-9_-]+$/),
    model: modelSchema,
  })
  .strict();
export const chatSchema = z
  .object({
    conversationId: idSchema.optional(),
    message: z.string().trim().min(1).max(6000),
    requestId: idSchema,
  })
  .strict();
export const proposalActionSchema = z
  .object({
    conversationId: idSchema,
    messageId: idSchema,
    proposalIds: z
      .array(idSchema)
      .min(1)
      .max(20)
      .refine((ids) => new Set(ids).size === ids.length),
  })
  .strict();

// Keep the provider schema compatible with OpenAI Structured Outputs. Semantic
// date/time constraints are rechecked on the server before saving the reply.
export const assistantReplySchema = z
  .object({
    text: z.string().min(1).max(10000),
    steps: z.array(z.string().min(1).max(800)).max(20),
    proposals: z
      .array(
        z
          .object({
            taskId: z.string(),
            date: z.string().nullable(),
            time: z.string().nullable(),
            duration: z.number().int(),
            reason: z.string().min(1).max(600),
          })
          .strict(),
      )
      .max(20),
  })
  .strict();
export type AssistantReply = z.infer<typeof assistantReplySchema>;
