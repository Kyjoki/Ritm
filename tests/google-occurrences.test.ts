import assert from 'node:assert/strict';
import test from 'node:test';
import type { GoogleCalendarEvent, Task } from '../shared/types';
import {
  calendarOccurrences,
  calendarRange,
  canEditGoogleEvent,
  googleEventDraft,
  googleOccurrences,
  layoutCalendarOccurrences,
} from '../src/features/google-occurrences';

function event(overrides: Partial<GoogleCalendarEvent> = {}): GoogleCalendarEvent {
  return {
    id: 'google-event',
    source: 'google',
    calendarId: 'primary',
    title: 'Созвон с клиентом',
    description: '',
    etag: '"one"',
    start: { dateTime: '2026-10-13T10:00:00+05:00' },
    end: { dateTime: '2026-10-13T11:00:00+05:00' },
    timeZone: 'Asia/Qyzylorda',
    allDay: false,
    busy: true,
    readOnly: false,
    ...overrides,
  };
}
function task(overrides: Partial<Task> = {}): Task {
  return {
    id: 'local-task',
    title: 'Подготовить слайды',
    description: '',
    date: '2026-10-13',
    time: '10:30',
    duration: 30,
    priority: 'normal',
    repeat: 'none',
    kind: 'task',
    completed: false,
    completedDates: [],
    createdAt: '2026-10-13T01:00:00Z',
    updatedAt: '2026-10-13T01:00:00Z',
    ...overrides,
  };
}

test('Google projections keep external identity separate from real Ritm tasks', () => {
  const local = task({ id: 'same-id' }),
    external = event({ id: 'same-id' });
  const entries = calendarOccurrences([local], [external], '2026-10-13', 'Asia/Qyzylorda');
  assert.equal(entries.length, 2);
  assert.notEqual(entries[0].key, entries[1].key);
  const projectedGoogle = entries.find((entry) => entry.source === 'google')!;
  const projectedLocal = entries.find((entry) => entry.source === 'ritm')!;
  assert.equal('task' in projectedGoogle, false);
  assert.equal('event' in projectedLocal, false);
  if (projectedGoogle.source === 'google') assert.equal(projectedGoogle.event, external);
  if (projectedLocal.source === 'ritm') assert.equal(projectedLocal.task, local);
  assert.equal(external.id, 'same-id');
});

test('timed Google events follow the selected time zone across midnight', () => {
  const external = event({
    start: { dateTime: '2026-10-13T23:30:00Z' },
    end: { dateTime: '2026-10-14T00:00:00Z' },
    timeZone: 'UTC',
  });
  assert.equal(googleOccurrences([external], '2026-10-13', 'Asia/Qyzylorda').length, 0);
  const displayed = googleOccurrences([external], '2026-10-14', 'Asia/Qyzylorda')[0];
  assert.equal(displayed.start, 270);
  assert.equal(displayed.end, 300);
  assert.equal(displayed.startLabel, '04:30');
  assert.equal(displayed.endLabel, '05:00');
  assert.deepEqual(googleEventDraft(external, 'Asia/Qyzylorda'), {
    title: external.title,
    description: '',
    date: '2026-10-14',
    time: '04:30',
    duration: 30,
    allDay: false,
  });
});

test('overnight events split into day segments and exclude an exact midnight end', () => {
  const external = event({
    start: { dateTime: '2026-10-13T23:30:00+05:00' },
    end: { dateTime: '2026-10-14T00:30:00+05:00' },
  });
  const first = googleOccurrences([external], '2026-10-13', 'Asia/Qyzylorda')[0];
  const second = googleOccurrences([external], '2026-10-14', 'Asia/Qyzylorda')[0];
  assert.equal(first.start, 1410);
  assert.equal(first.end, 1440);
  assert.equal(first.continues, true);
  assert.equal(second.start, 0);
  assert.equal(second.end, 30);
  assert.equal(second.continued, true);
  assert.equal(second.duration, 60);
  assert.equal(canEditGoogleEvent(external, 'Asia/Qyzylorda'), false);
  const endingAtMidnight = event({
    start: external.start,
    end: { dateTime: '2026-10-14T00:00:00+05:00' },
  });
  assert.equal(googleOccurrences([endingAtMidnight], '2026-10-14', 'Asia/Qyzylorda').length, 0);
  assert.equal(
    googleOccurrences([endingAtMidnight], '2026-10-13', 'Asia/Qyzylorda')[0].continues,
    false,
  );
  assert.equal(canEditGoogleEvent(endingAtMidnight, 'Asia/Qyzylorda'), true);
});

test('all-day dates remain floating and the Google end date is exclusive', () => {
  const external = event({
    allDay: true,
    start: { date: '2026-10-13' },
    end: { date: '2026-10-15' },
    readOnly: true,
  });
  for (const timeZone of ['Asia/Qyzylorda', 'America/New_York', 'Pacific/Kiritimati']) {
    assert.equal(googleOccurrences([external], '2026-10-12', timeZone).length, 0);
    assert.equal(googleOccurrences([external], '2026-10-13', timeZone)[0].allDay, true);
    assert.equal(googleOccurrences([external], '2026-10-13', timeZone)[0].continues, true);
    assert.equal(googleOccurrences([external], '2026-10-14', timeZone)[0].continued, true);
    assert.equal(googleOccurrences([external], '2026-10-14', timeZone)[0].start, null);
    assert.equal(googleOccurrences([external], '2026-10-15', timeZone).length, 0);
  }
  assert.equal(canEditGoogleEvent({ ...external, readOnly: false }, 'UTC'), false);
  assert.equal(
    canEditGoogleEvent({ ...external, readOnly: false, end: { date: '2026-10-14' } }, 'UTC'),
    true,
  );
});

test('mixed Google and Ritm overlaps use different lanes and reclaim them at boundaries', () => {
  const entries = calendarOccurrences(
    [task(), task({ id: 'later', time: '11:00' }), task({ id: 'no-time', time: null })],
    [
      event(),
      event({
        id: 'all-day',
        allDay: true,
        start: { date: '2026-10-13' },
        end: { date: '2026-10-14' },
      }),
    ],
    '2026-10-13',
    'Asia/Qyzylorda',
  );
  const positioned = layoutCalendarOccurrences(entries);
  assert.equal(positioned.length, 3);
  const google = positioned.find((entry) => entry.source === 'google')!;
  const local = positioned.find(
    (entry) => entry.source === 'ritm' && entry.task.id === 'local-task',
  )!;
  const later = positioned.find((entry) => entry.source === 'ritm' && entry.task.id === 'later')!;
  assert.notEqual(google.lane, local.lane);
  assert.equal(google.lanes, 2);
  assert.equal(later.lanes, 1);
  assert.equal(later.lane, 0);
  assert.equal('lane' in entries[0], false);
});

test('completed, unscheduled and transparent records do not claim busy time', () => {
  const entries = calendarOccurrences(
    [task({ completed: true }), task({ id: 'no-time', time: null })],
    [
      event({ busy: false }),
      event({
        id: 'busy-all-day',
        allDay: true,
        start: { date: '2026-10-13' },
        end: { date: '2026-10-14' },
      }),
    ],
    '2026-10-13',
    'Asia/Qyzylorda',
  );
  assert.equal(entries.filter((entry) => entry.busy).length, 1);
  assert.equal(entries.find((entry) => entry.busy)?.allDay, true);
});

test('day/week/month fetch ranges use exclusive ends and all 42 displayed month cells', () => {
  assert.deepEqual(calendarRange('day', '2026-12-31'), { from: '2026-12-31', to: '2027-01-01' });
  assert.deepEqual(calendarRange('week', '2026-10-18'), { from: '2026-10-12', to: '2026-10-19' });
  assert.deepEqual(calendarRange('month', '2026-10-13'), { from: '2026-09-28', to: '2026-11-09' });
  const february = calendarRange('month', '2024-02-29');
  assert.equal((Date.parse(february.to) - Date.parse(february.from)) / 86400000, 42);
});

test('DST changes retain actual duration and readonly edits avoid silently moving the event', () => {
  const spring = event({
    start: { dateTime: '2026-03-29T01:30:00+01:00' },
    end: { dateTime: '2026-03-29T03:30:00+02:00' },
    timeZone: 'Europe/Berlin',
  });
  const projected = googleOccurrences([spring], '2026-03-29', 'Europe/Berlin')[0];
  assert.equal(projected.start, 90);
  assert.equal(projected.end, 210);
  assert.equal(projected.duration, 60);
  assert.equal(projected.clockChange, true);
  assert.equal(canEditGoogleEvent(spring, 'Europe/Berlin'), false);
  const autumn = event({
    start: { dateTime: '2026-10-25T02:45:00+02:00' },
    end: { dateTime: '2026-10-25T02:15:00+01:00' },
    timeZone: 'Europe/Berlin',
  });
  const reversedWall = googleOccurrences([autumn], '2026-10-25', 'Europe/Berlin')[0];
  assert.ok(reversedWall.end! > reversedWall.start!);
  assert.equal(reversedWall.startLabel, '02:45');
  assert.equal(reversedWall.endLabel, '02:15');
  assert.equal(reversedWall.duration, 30);
  assert.equal(reversedWall.clockChange, true);
  assert.equal(canEditGoogleEvent(autumn, 'Europe/Berlin'), false);
  const sameOffsetAmbiguous = event({
    start: { dateTime: '2026-10-25T02:05:00+02:00' },
    end: { dateTime: '2026-10-25T02:15:00+02:00' },
    timeZone: 'Europe/Berlin',
  });
  assert.equal(canEditGoogleEvent(sameOffsetAmbiguous, 'Europe/Berlin'), false);
});

test('seconds and provider readonly flags preserve view-only behavior; cache notices changed timestamps', () => {
  const seconds = event({
    start: { dateTime: '2026-10-13T10:00:30+05:00' },
    end: { dateTime: '2026-10-13T10:10:30+05:00' },
  });
  assert.equal(canEditGoogleEvent(seconds, 'Asia/Qyzylorda'), false);
  assert.equal(canEditGoogleEvent(event({ readOnly: true }), 'Asia/Qyzylorda'), false);
  assert.equal(canEditGoogleEvent(event(), 'Asia/Qyzylorda'), true);
  const external = event();
  assert.equal(googleOccurrences([external], '2026-10-13', 'Asia/Qyzylorda')[0].end, 660);
  external.end = { dateTime: '2026-10-13T12:00:00+05:00' };
  assert.equal(googleOccurrences([external], '2026-10-13', 'Asia/Qyzylorda')[0].end, 720);
});
