import assert from 'node:assert/strict';
import test from 'node:test';
import type { CalendarOccurrence } from '../src/features/google-occurrences';
import { mobileCalendarGroups } from '../src/features/mobile-calendar-groups';

function occurrence(key: string, start: number, end: number): CalendarOccurrence {
  return {
    key,
    date: '2026-10-13',
    title: key,
    start,
    end,
    completed: false,
    allDay: false,
    busy: true,
    continued: false,
    continues: false,
    duration: end - start,
    startLabel: null,
    endLabel: null,
    clockChange: false,
    source: 'google',
    event: {
      id: key,
      source: 'google',
      calendarId: 'primary',
      title: key,
      description: '',
      etag: '"one"',
      start: { dateTime: '2026-10-13T09:00:00+05:00' },
      end: { dateTime: '2026-10-13T10:00:00+05:00' },
      timeZone: 'Asia/Qyzylorda',
      allDay: false,
      busy: true,
      readOnly: false,
    },
  };
}

test('a long event groups sequential nested overlaps once, without changing inputs', () => {
  const long = occurrence('internship', 540, 1080);
  const early = occurrence('meeting', 600, 660);
  const late = occurrence('appointment', 900, 960);
  const entries = [late, long, early];
  const before = structuredClone(entries);
  const groups = mobileCalendarGroups(entries);
  assert.equal(groups.length, 1);
  assert.equal(groups[0].start, 540);
  assert.equal(groups[0].end, 1080);
  assert.deepEqual(groups[0].entries, [long, early, late]);
  assert.equal(groups[0].entries[0], long);
  assert.equal(new Set(groups.flatMap((group) => group.entries)).size, 3);
  assert.deepEqual(entries, before);
});

test('transitive overlaps form one group even when its endpoints do not overlap directly', () => {
  const first = occurrence('first', 540, 600);
  const bridge = occurrence('bridge', 570, 660);
  const last = occurrence('last', 630, 720);
  const groups = mobileCalendarGroups([last, first, bridge]);
  assert.deepEqual(
    groups.map(({ start, end }) => ({ start, end })),
    [{ start: 540, end: 720 }],
  );
  assert.deepEqual(groups[0].entries, [first, bridge, last]);
});

test('adjacent events and a following free interval create separate mobile targets', () => {
  const first = occurrence('first', 540, 600);
  const adjacent = occurrence('adjacent', 600, 660);
  const later = occurrence('later', 720, 780);
  assert.deepEqual(
    mobileCalendarGroups([later, adjacent, first]).map((group) => group.entries),
    [[first], [adjacent], [later]],
  );
});

test('all-day and missing-time records are excluded from timed groups', () => {
  const allDay = { ...occurrence('all-day', 0, 1440), allDay: true };
  const noStart = { ...occurrence('no-start', 540, 600), start: null };
  const noEnd = { ...occurrence('no-end', 540, 600), end: null };
  assert.deepEqual(mobileCalendarGroups([allDay, noStart, noEnd]), []);
  assert.deepEqual(mobileCalendarGroups([]), []);
});

test('ties have deterministic start, end, key ordering, preserving event references', () => {
  const b = occurrence('b', 540, 600);
  const a = occurrence('a', 540, 600);
  const long = occurrence('long', 540, 660);
  const later = occurrence('later', 570, 630);
  const forward = mobileCalendarGroups([b, long, later, a]);
  const backward = mobileCalendarGroups([a, later, long, b]);
  assert.deepEqual(forward, backward);
  assert.equal(forward[0].key, 'a');
  assert.deepEqual(forward[0].entries, [a, b, long, later]);
  forward[0].entries.forEach((entry, index) => {
    assert.equal(entry, [a, b, long, later][index]);
  });
});
