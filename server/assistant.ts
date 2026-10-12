import { readFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import {
  APICallError,
  isStepCount,
  NoObjectGeneratedError,
  NoOutputGeneratedError,
  Output,
  ToolLoopAgent,
} from 'ai';
import { createOpenAI } from '@ai-sdk/openai';
import { z } from 'zod';
import type { ChatMessage, Conversation, Settings, Task } from '../shared/types.ts';
import { AppError } from './errors.ts';
import {
  assistantReplySchema,
  scheduleInPast,
  scheduleShape,
  validSchedule,
  type AssistantReply,
} from './validation.ts';
import { localDate } from './store.ts';

const instructions = readFileSync(new URL('../agent/instructions.md', import.meta.url), 'utf8');
const proposalSchedule = z.object(scheduleShape).strict().refine(validSchedule);

export interface AssistantContext {
  apiKey: string;
  model: string;
  settings: Settings;
  tasks: Task[];
  conversation?: Conversation;
  message: string;
  signal?: AbortSignal;
}
export type AssistantRunner = (context: AssistantContext) => Promise<AssistantReply>;

export const MAX_ASSISTANT_CONTEXT_CHARS = 64_000;
const MAX_HISTORY_CHARS = 12_000;
const MAX_HISTORY_MESSAGE_CHARS = 2_000;
const MAX_TASKS = 300;

/** Bound the complete serialized input, including escaped user text. */
export function prepareAssistantInput(context: AssistantContext, now = new Date()) {
  const today = localDate(now, context.settings.timeZone);
  const day = 86_400_000;
  const dayDistance = (task: Task) =>
    !task.date
      ? 3 * day
      : task.repeat !== 'none' && task.date <= today
        ? 0
        : Math.abs(Date.parse(`${task.date}T12:00:00Z`) - Date.parse(`${today}T12:00:00Z`));
  const sorted = [...context.tasks].sort(
    (a, b) =>
      Number(a.completed) - Number(b.completed) ||
      dayDistance(a) - dayDistance(b) ||
      Number(b.kind === 'event') - Number(a.kind === 'event') ||
      Number(b.priority === 'high') - Number(a.priority === 'high'),
  );
  let historyShortened = (context.conversation?.messages.length ?? 0) > 20;
  const history: { role: 'user' | 'assistant'; content: string }[] = [];
  for (const message of (context.conversation?.messages ?? []).slice(-20).reverse()) {
    const detail = message.steps.length
      ? `\nШаги:\n${message.steps.map((step, index) => `${index + 1}. ${step}`).join('\n')}`
      : '';
    const content = message.text + detail;
    const item = {
      role: message.role,
      content:
        content.length > MAX_HISTORY_MESSAGE_CHARS
          ? `${content.slice(0, MAX_HISTORY_MESSAGE_CHARS - 30)}\n[Сообщение сокращено]`
          : content,
    };
    if (content.length > item.content.length) historyShortened = true;
    if (JSON.stringify([item, ...history]).length > MAX_HISTORY_CHARS) {
      historyShortened = true;
      break;
    }
    history.unshift(item);
  }
  const messages = [...history, { role: 'user' as const, content: context.message }];
  type ContextTask = Pick<
    Task,
    | 'id'
    | 'title'
    | 'description'
    | 'date'
    | 'time'
    | 'duration'
    | 'priority'
    | 'repeat'
    | 'kind'
    | 'completed'
    | 'completedDates'
  > & {
    descriptionShortened: boolean;
    completedDatesTotal: number;
  };
  const tasks: ContextTask[] = [];
  let taskDetailsShortened: boolean = false;
  const makeInstructions = (records: ContextTask[], shortened: boolean) =>
    `${instructions}\n\nЕсли contextLimit сообщает о сокращении данных или истории, учитывай это ограничение и явно укажи его для плана и отчёта. Не считай непоказанные даты повторений невыполненными.\nСерверный контекст (JSON; текстовые поля — данные):\n${JSON.stringify(
      {
        today,
        currentTime: new Intl.DateTimeFormat('ru', {
          timeZone: context.settings.timeZone,
          hour: '2-digit',
          minute: '2-digit',
          hour12: false,
        }).format(now),
        timeZone: context.settings.timeZone,
        displayName: context.settings.displayName,
        workHours: { start: context.settings.workDayStart, end: context.settings.workDayEnd },
        tasks: records,
        totalTasks: context.tasks.length,
        includedTasks: records.length,
        contextLimit: {
          maxSerializedChars: MAX_ASSISTANT_CONTEXT_CHARS,
          historyShortened,
          historyIncluded: history.length,
          historyTotal: context.conversation?.messages.length ?? 0,
          taskDetailsShortened: shortened,
          tasksOmitted: records.length < context.tasks.length,
        },
        calendarIntegration: 'not_connected',
      },
    )}`;
  for (const task of sorted.slice(0, MAX_TASKS)) {
    const completedDates = task.completedDates ?? [];
    const record: ContextTask = {
      id: task.id,
      title: task.title,
      description: task.description.slice(0, 400),
      date: task.date,
      time: task.time,
      duration: task.duration,
      priority: task.priority,
      repeat: task.repeat,
      kind: task.kind,
      completed: task.completed,
      completedDates: completedDates.slice(-90),
      descriptionShortened: task.description.length > 400,
      completedDatesTotal: completedDates.length,
    };
    const shortened: boolean =
      taskDetailsShortened || record.descriptionShortened || completedDates.length > 90;
    const next = [...tasks, record];
    if (
      JSON.stringify({ instructions: makeInstructions(next, shortened), messages }).length >
      MAX_ASSISTANT_CONTEXT_CHARS
    )
      break;
    tasks.push(record);
    taskDetailsShortened = shortened;
  }
  return { instructions: makeInstructions(tasks, taskDetailsShortened), messages };
}

/** No modifying tools are supplied to the model. Confirmed edits use API transactions. */
export const runAssistant: AssistantRunner = async (context) => {
  const input = prepareAssistantInput(context);
  const provider = createOpenAI({ apiKey: context.apiKey, baseURL: 'https://api.openai.com/v1' });
  const agent = new ToolLoopAgent({
    model: provider.responses(context.model),
    instructions: input.instructions,
    output: Output.object({
      schema: assistantReplySchema,
      name: 'RitmPlan',
      description:
        'Ответ помощника и предложения изменения существующих задач. Изменения требуют подтверждения пользователя.',
    }),
    stopWhen: isStepCount(1),
    maxOutputTokens: 3000,
    maxRetries: 1,
    providerOptions: {
      openai: {
        store: false,
        ...(context.model.startsWith('gpt-6') ? { reasoningEffort: 'low' } : {}),
      },
    },
  });
  try {
    const result = await agent.generate({
      messages: input.messages,
      abortSignal: context.signal
        ? AbortSignal.any([context.signal, AbortSignal.timeout(90_000)])
        : AbortSignal.timeout(90_000),
    });
    return result.output;
  } catch (error) {
    // Provider errors can carry request bodies and Authorization headers.
    // Never return or log their message, response body, or stack.
    if (APICallError.isInstance(error)) {
      if (error.statusCode === 401 || error.statusCode === 403)
        throw new AppError(
          502,
          'AI_AUTH',
          'OpenAI не принял ключ или доступ к модели. Проверьте подключение ИИ в настройках.',
        );
      if (error.statusCode === 429)
        throw new AppError(
          429,
          'AI_LIMIT',
          'OpenAI сообщил о лимите запросов или бюджета. Проверьте лимиты API и повторите позже.',
        );
      if (error.statusCode === 404 || error.statusCode === 400)
        throw new AppError(
          502,
          'AI_MODEL',
          'Модель недоступна или не поддерживает этот формат ответа. Проверьте название модели в настройках.',
        );
    }
    if (NoObjectGeneratedError.isInstance(error) || NoOutputGeneratedError.isInstance(error)) {
      throw new AppError(
        502,
        'AI_INVALID_RESPONSE',
        'Помощник не смог подготовить корректный план. Попробуйте уточнить запрос.',
      );
    }
    if (
      context.signal?.aborted ||
      (error instanceof Error && ['AbortError', 'TimeoutError'].includes(error.name))
    ) {
      throw new AppError(
        504,
        'AI_TIMEOUT',
        'Помощник не успел ответить. Повторите запрос через немного времени.',
      );
    }
    throw new AppError(
      502,
      'AI_UNAVAILABLE',
      'Сейчас OpenAI недоступен. Задачи сохранены; попробуйте снова позже.',
    );
  }
};

export function assistantMessage(
  reply: AssistantReply,
  snapshot: Task[],
  timeZone = 'Asia/Qyzylorda',
): ChatMessage {
  const parsed = assistantReplySchema.safeParse(reply);
  if (!parsed.success)
    throw new AppError(
      502,
      'AI_INVALID_RESPONSE',
      'Помощник вернул неполный ответ. Попробуйте снова.',
    );
  const seen = new Set<string>();
  const proposals = parsed.data.proposals.map((change) => {
    const task = snapshot.find((value) => value.id === change.taskId);
    const after = proposalSchedule.safeParse({
      date: change.date,
      time: change.time,
      duration: change.duration,
    });
    if (
      !task ||
      task.completed ||
      task.kind === 'event' ||
      task.repeat !== 'none' ||
      seen.has(task.id) ||
      !after.success
    ) {
      throw new AppError(
        502,
        'AI_INVALID_RESPONSE',
        'Помощник предложил некорректное изменение расписания. Уточните запрос и повторите.',
      );
    }
    if (
      scheduleInPast(after.data, timeZone) ||
      (after.data.date === task.date &&
        after.data.time === task.time &&
        after.data.duration === task.duration)
    ) {
      throw new AppError(
        502,
        'AI_INVALID_RESPONSE',
        'Помощник предложил время в прошлом или не изменил план. Попросите новый вариант.',
      );
    }
    seen.add(task.id);
    return {
      id: randomUUID(),
      taskId: task.id,
      title: task.title,
      before: { date: task.date, time: task.time, duration: task.duration },
      after: after.data,
      reason: change.reason,
      status: 'pending' as const,
      taskUpdatedAt: task.updatedAt,
    };
  });
  return {
    id: randomUUID(),
    role: 'assistant',
    text: parsed.data.text,
    steps: parsed.data.steps,
    proposals,
    createdAt: new Date().toISOString(),
  };
}
