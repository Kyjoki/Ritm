import assert from 'node:assert/strict';
import test from 'node:test';
import { taskInputSchema } from '../server/validation';
import { assertTransferTask } from '../server/repository';
import { calendarOccurrences } from '../src/features/google-occurrences';
import { getDayOccurrences } from '../src/features/calendar-utils';
import type { Task } from '../shared/types';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve, sep } from 'node:path';
import { Store } from '../server/store';

const task: Task = {
  id: 'e54526c7-f1c0-4f4b-8dfd-ece614b5b90d',
  title: 'Купить продукты',
  description: '',
  date: '2026-10-14',
  time: null,
  duration: 30,
  priority: 'normal',
  repeat: 'none',
  kind: 'task',
  completed: false,
  completedDates: [],
  calendarEntry: false,
  createdAt: '2026-10-14T04:00:00Z',
  updatedAt: '2026-10-14T04:00:00Z',
};
test('a dated quick task stays in today checklist but never appears in calendar or migration', () => {
  assert.equal(
    taskInputSchema.parse(
      Object.fromEntries(
        Object.entries(task).filter(
          ([key]) => !['id', 'completedDates', 'createdAt', 'updatedAt'].includes(key),
        ),
      ),
    ).calendarEntry,
    false,
  );
  assert.equal(getDayOccurrences([task], '2026-10-14').length, 1);
  assert.equal(calendarOccurrences([task], [], '2026-10-14', 'Asia/Qyzylorda').length, 0);
  assert.throws(
    () => assertTransferTask(task),
    (error: unknown) => (error as { code: string }).code === 'GOOGLE_TRANSFER_NOT_SCHEDULED',
  );
  assert.equal(
    calendarOccurrences([{ ...task, calendarEntry: undefined }], [], '2026-10-14', 'Asia/Qyzylorda')
      .length,
    1,
  );
});
test('quick task flag survives saving, completion, reload and restore', () => {
  const directory = mkdtempSync(join(tmpdir(), 'ritm-day-tasks-'));
  let store: Store | undefined;
  try {
    store = new Store(directory, false);
    const { id, createdAt, updatedAt, completedDates, ...input } = task;
    const created = store.createTask(input);
    assert.equal(created.calendarEntry, false);
    const completed = store.updateTask(created.id, { completed: true });
    assert.equal(completed.calendarEntry, false);
    store.close();
    store = new Store(directory, false);
    assert.equal(store.task(created.id).calendarEntry, false);
    const removed = store.deleteTask(created.id);
    assert.equal(store.restoreTask(removed).calendarEntry, false);
    assert.throws(
      () => store!.beginGoogleTransfer(created.id, 'identity'),
      (error: unknown) => (error as { code: string }).code === 'GOOGLE_TRANSFER_NOT_SCHEDULED',
    );
  } finally {
    store?.close();
    assert.ok(resolve(directory).startsWith(resolve(tmpdir()) + sep + 'ritm-day-tasks-'));
    rmSync(directory, { recursive: true, force: true });
  }
});
