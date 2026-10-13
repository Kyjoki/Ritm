import { performance } from 'node:perf_hooks';
import { z } from 'zod';
import type { GoogleTransferResult } from '../shared/types.ts';
import type { WorkspaceRepository } from './repository.ts';
import { AppError } from './errors.ts';
import { idSchema } from './validation.ts';
import {
  googleEventInputSchema,
  type GoogleCalendarService,
  type GoogleSecretStorage,
} from './google-calendar.ts';

interface TransferOptions {
  store: WorkspaceRepository;
  leases: Pick<GoogleSecretStorage, 'acquireLease' | 'releaseLease'>;
  google: Pick<
    GoogleCalendarService,
    'createEvent' | 'connectionIdentity' | 'withConnectionIdentity'
  >;
  clock?: () => number;
}
const knownNoCreation = new Set([
  'GOOGLE_NOT_CONFIGURED',
  'GOOGLE_NOT_CONNECTED',
  'GOOGLE_REAUTH_REQUIRED',
  'GOOGLE_FORBIDDEN',
  'GOOGLE_TIMEZONE',
  'GOOGLE_TIME_GAP',
  'GOOGLE_TIME_AMBIGUOUS',
  'GOOGLE_TIME_RANGE',
  'GOOGLE_EXTENDED_COLORS_REQUIRED',
  'GOOGLE_LABEL_LIMIT',
]);

/** One-way migration into Google's canonical calendar; no persistent mirror. */
export function createTaskGoogleTransfer(options: TransferOptions) {
  return async (taskId: string): Promise<GoogleTransferResult> => {
    const id = idSchema.parse(taskId),
      key = 'google.transfer.' + id;
    const clock = options.clock ?? (() => performance.now()),
      deadline = clock() + 45_000;
    const assertActive = () => {
      if (clock() >= deadline)
        throw new AppError(
          503,
          'GOOGLE_TRANSFER_PENDING',
          'Перенос ещё не завершён. Запись Ritm сохранена; повторите действие, чтобы подтвердить результат Google.',
        );
    };
    const lease = await options.leases.acquireLease(key, 180_000);
    if (!lease)
      throw new AppError(
        409,
        'GOOGLE_TRANSFER_BUSY',
        'Эта запись уже переносится в Google. Подождите немного и повторите.',
      );
    try {
      assertActive();
      const identity = await options.google.connectionIdentity();
      assertActive();
      const receipt = await options.store.beginGoogleTransfer(id, identity, assertActive);
      if (receipt.status === 'complete')
        return await options.google.withConnectionIdentity(
          receipt.connectionIdentity,
          async (guard) => {
            assertActive();
            guard();
            return receipt.result;
          },
        );
      let started = false,
        confirmed = false;
      try {
        const task = receipt.task;
        const input = googleEventInputSchema.parse({
          title: task.title,
          description: task.description,
          date: task.date,
          time: task.time,
          duration: task.duration,
          allDay: task.time === null,
          ...(task.colorId === undefined ? {} : { colorId: task.colorId }),
          repeat: task.repeat,
        });
        assertActive();
        const marked = await options.store.markGoogleTransferAttempt(id, assertActive);
        if (marked.status === 'complete')
          return await options.google.withConnectionIdentity(
            marked.connectionIdentity,
            async (guard) => {
              assertActive();
              guard();
              return marked.result;
            },
          );
        assertActive();
        started = true;
        const event = await options.google.createEvent(input, id, {
          timeZone: receipt.timeZone,
          expectedConnectionIdentity: receipt.connectionIdentity,
          transparency: receipt.task.time === null ? 'transparent' : 'opaque',
        });
        confirmed = true;
        assertActive();
        try {
          return await options.google.withConnectionIdentity(
            receipt.connectionIdentity,
            async (assertConnectionActive) =>
              options.store.finishGoogleTransfer(id, event, receipt.connectionIdentity, () => {
                assertActive();
                assertConnectionActive();
              }),
          );
        } catch (error) {
          if (error instanceof AppError) throw error;
          throw new AppError(
            503,
            'GOOGLE_TRANSFER_PENDING',
            'Google подтвердил событие, но перенос Ritm ещё не завершён. Повторите действие; новый дубль не создастся.',
          );
        }
      } catch (error) {
        // Never drop a snapshot after a previously uncertain provider outcome.
        // The stable Google ID must keep using that exact payload on retries.
        const certainlyNotCreated =
          !confirmed &&
          (error instanceof z.ZodError ||
            (error instanceof AppError &&
              (knownNoCreation.has(error.code) ||
                error.code === 'GOOGLE_TRANSFER_CONNECTION_CHANGED')));
        if (!receipt.attempted && (!started || certainlyNotCreated)) {
          assertActive();
          await options.store.cancelGoogleTransfer(id, receipt.task, assertActive);
        }
        throw error;
      }
    } finally {
      // No early race/timeout releases a lease while a provider call is active.
      await options.leases.releaseLease(key, lease);
    }
  };
}
