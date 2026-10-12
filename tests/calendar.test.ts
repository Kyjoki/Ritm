import assert from 'node:assert/strict';
import test from 'node:test';
import type { Task } from '../shared/types';
import {
  addDays,
  addMonths,
  getDayOccurrences,
  isTimedOccurrence,
  layoutOccurrences,
  startOfWeek,
  taskOccursOn,
} from '../src/features/calendar-utils';
import { dateInZone, minutesInZone } from '../src/lib/date';

function task(overrides: Partial<Task> = {}): Task {
  return {
    id: 'task-1',
    title: 'Созвон с командой',
    description: '',
    date: '2026-10-13',
    time: '11:00',
    duration: 60,
    priority: 'normal',
    repeat: 'none',
    kind: 'task',
    completed: false,
    completedDates: [],
    createdAt: '2026-10-13T05:00:00Z',
    updatedAt: '2026-10-13T05:00:00Z',
    ...overrides,
  };
}

test('weekly and monthly series never appear before their starting date', () => {
  const weekly = task({ repeat: 'weekly' });
  assert.equal(taskOccursOn(weekly, '2026-10-06'), false);
  assert.equal(taskOccursOn(weekly, '2026-10-13'), true);
  assert.equal(taskOccursOn(weekly, '2026-10-20'), true);
  assert.equal(taskOccursOn(weekly, '2026-10-21'), false);
  const monthly = task({ repeat: 'monthly', date: '2026-01-31' });
  assert.equal(taskOccursOn(monthly, '2025-12-31'), false);
  assert.equal(taskOccursOn(monthly, '2026-02-28'), false);
  assert.equal(taskOccursOn(monthly, '2026-03-31'), true);
});

test('the current day and clock follow the user time zone at midnight', () => {
  const moment = new Date('2026-10-13T20:15:00Z');
  assert.equal(dateInZone('Asia/Qyzylorda', moment), '2026-10-14');
  assert.equal(minutesInZone('Asia/Qyzylorda', moment), 75);
  assert.equal(dateInZone('America/New_York', moment), '2026-10-13');
  assert.equal(dateInZone('UTC', moment), '2026-10-13');
});

test('calendar day arithmetic survives month, year and leap-day boundaries', () => {
  assert.equal(addDays('2026-12-31', 1), '2027-01-01');
  assert.equal(addDays('2024-02-28', 1), '2024-02-29');
  assert.equal(addDays('2024-03-01', -1), '2024-02-29');
  assert.equal(startOfWeek('2026-10-18'), '2026-10-12');
});

test('overlapping events use separate lanes and reclaim a lane after an event ends', () => {
  const tasks = [
    task({ id: 'long', time: '10:00', duration: 120 }),
    task({ id: 'first-short', time: '10:30', duration: 30 }),
    task({ id: 'second-short', time: '11:00', duration: 30 }),
    task({ id: 'separate', time: '12:00', duration: 30 }),
  ];
  const laidOut = layoutOccurrences(getDayOccurrences(tasks, '2026-10-13'));
  const long = laidOut.find((entry) => entry.task.id === 'long')!;
  const first = laidOut.find((entry) => entry.task.id === 'first-short')!;
  const second = laidOut.find((entry) => entry.task.id === 'second-short')!;
  const separate = laidOut.find((entry) => entry.task.id === 'separate')!;
  assert.equal(long.lanes, 2);
  assert.notEqual(long.lane, first.lane);
  assert.equal(first.lane, second.lane);
  assert.equal(separate.lanes, 1);
  assert.equal(separate.lane, 0);
});

test('completing a recurring task affects only the selected occurrence', () => {
  const daily = task({ repeat: 'daily', completedDates: ['2026-10-13'] });
  assert.equal(getDayOccurrences([daily], '2026-10-13')[0].completed, true);
  assert.equal(getDayOccurrences([daily], '2026-10-14')[0].completed, false);
  assert.equal(getDayOccurrences([daily], '2026-10-15')[0].completed, false);
  assert.equal(getDayOccurrences([task({ completed: true })], '2026-10-13')[0].completed, true);
});

test('a late event continues after midnight and keeps the original occurrence completion', () => {
  const overnight = task({
    date: '2026-10-13',
    repeat: 'daily',
    time: '23:30',
    duration: 90,
    completedDates: ['2026-10-13'],
  });
  const nextDay = getDayOccurrences([overnight], '2026-10-14');
  assert.equal(nextDay.length, 2);
  assert.equal(nextDay[0].date, '2026-10-13');
  assert.equal(nextDay[0].start, 0);
  assert.equal(nextDay[0].end, 60);
  assert.equal(nextDay[0].completed, true);
  assert.equal(nextDay[1].date, '2026-10-14');
  assert.equal(nextDay[1].completed, false);
});

test('month navigation clamps invalid month dates, including leap years', () => {
  assert.equal(addMonths('2026-01-31', 1), '2026-02-28');
  assert.equal(addMonths('2024-01-31', 1), '2024-02-29');
  assert.equal(addMonths('2026-03-31', -1), '2026-02-28');
  assert.equal(addMonths('2026-12-13', 1), '2027-01-13');
});

test('date-only records remain in the agenda but are excluded from timed layout', () => {
  const entries = getDayOccurrences([task({ time: null }), task({ id: 'timed' })], '2026-10-13');
  assert.equal(entries.length, 2);
  assert.equal(entries.filter(isTimedOccurrence).length, 1);
  assert.equal(layoutOccurrences(entries).length, 1);
  assert.equal(entries.find((entry) => entry.task.id === 'task-1')?.start, null);
});
