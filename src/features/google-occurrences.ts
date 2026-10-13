import type { GoogleCalendarEvent, GoogleEventInput, Task } from '../../shared/types';
import { addDays, dateKey, getDayOccurrences, parseDate, startOfWeek } from './calendar-utils';
import { formatTime } from '../lib/date';

interface CalendarOccurrenceBase {
  key: string;
  /** Date of this displayed segment, independent from the original event. */
  date: string;
  title: string;
  start: number | null;
  end: number | null;
  completed: boolean;
  allDay: boolean;
  busy: boolean;
  continued: boolean;
  continues: boolean;
  duration: number;
  startLabel: string | null;
  endLabel: string | null;
  clockChange: boolean;
}
export type CalendarOccurrence = CalendarOccurrenceBase &
  ({ source: 'ritm'; task: Task } | { source: 'google'; event: GoogleCalendarEvent });

const formatters = new Map<string, Intl.DateTimeFormat>();
function localParts(instant: number, timeZone: string) {
  let formatter = formatters.get(timeZone);
  if (!formatter) {
    formatter = new Intl.DateTimeFormat('en', {
      timeZone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hourCycle: 'h23',
    });
    if (formatters.size >= 24) formatters.delete(formatters.keys().next().value!);
    formatters.set(timeZone, formatter);
  }
  const parts = formatter.formatToParts(instant);
  const get = (name: string) => parts.find((part) => part.type === name)!.value;
  return {
    date: `${get('year')}-${get('month')}-${get('day')}`,
    time: `${get('hour')}:${get('minute')}`,
    seconds: Number(get('hour')) * 3600 + Number(get('minute')) * 60 + Number(get('second')),
  };
}

function ambiguousWallTime(instant: number, timeZone: string) {
  const current = localParts(instant, timeZone);
  return [-120, -90, -60, -30, -15, 15, 30, 60, 90, 120].some((difference) => {
    const other = localParts(instant + difference * 60000, timeZone);
    return current.date === other.date && current.seconds === other.seconds;
  });
}

const timedCache = new WeakMap<
  GoogleCalendarEvent,
  {
    key: string;
    value: {
      startInstant: number;
      endInstant: number;
      start: ReturnType<typeof localParts>;
      end: ReturnType<typeof localParts>;
      duration: number;
      wallDuration: number;
      ambiguous: boolean;
    };
  }
>();
function timedParts(event: GoogleCalendarEvent, timeZone: string) {
  const key = `${timeZone}|${event.start.dateTime}|${event.end.dateTime}`;
  const cached = timedCache.get(event);
  if (cached?.key === key) return cached.value;
  const startInstant = Date.parse(event.start.dateTime ?? ''),
    endInstant = Date.parse(event.end.dateTime ?? '');
  if (!Number.isFinite(startInstant) || !Number.isFinite(endInstant) || endInstant <= startInstant)
    return null;
  const start = localParts(startInstant, timeZone),
    end = localParts(endInstant, timeZone);
  const duration = (endInstant - startInstant) / 60000;
  const wallDuration =
    (Date.parse(`${end.date}T${end.time}:00Z`) - Date.parse(`${start.date}T${start.time}:00Z`)) /
    60000;
  const value = {
    startInstant,
    endInstant,
    start,
    end,
    duration,
    wallDuration,
    ambiguous: ambiguousWallTime(startInstant, timeZone) || ambiguousWallTime(endInstant, timeZone),
  };
  timedCache.set(event, { key, value });
  return value;
}

/** Only open editable controls for events the simple form can round-trip. */
export function canEditGoogleEvent(event: GoogleCalendarEvent, timeZone: string): boolean {
  if (event.readOnly) return false;
  if (event.allDay)
    return Boolean(event.start.date && event.end.date === addDays(event.start.date, 1));
  const parts = timedParts(event, timeZone);
  if (!parts) return false;
  const { duration, start, end, wallDuration, ambiguous } = parts;
  if (duration < 5 || duration > 720 || !Number.isInteger(duration)) return false;
  if (start.seconds % 60 || end.seconds % 60) return false;
  if (start.date !== end.date && !(end.date === addDays(start.date, 1) && end.seconds === 0))
    return false;
  return wallDuration === duration && !ambiguous;
}

export function googleEventDraft(event: GoogleCalendarEvent, timeZone: string): GoogleEventInput {
  if (event.allDay)
    return {
      title: event.title,
      description: event.description,
      date: event.start.date!,
      time: null,
      duration: 60,
      allDay: true,
    };
  const start = Date.parse(event.start.dateTime!),
    end = Date.parse(event.end.dateTime!);
  const local = localParts(start, timeZone);
  return {
    title: event.title,
    description: event.description,
    date: local.date,
    time: local.time,
    duration: (end - start) / 60000,
    allDay: false,
  };
}

export function googleOccurrences(
  events: GoogleCalendarEvent[],
  date: string,
  timeZone: string,
): CalendarOccurrence[] {
  const entries: CalendarOccurrence[] = [];
  for (const event of events) {
    if (event.allDay) {
      const start = event.start.date,
        end = event.end.date;
      // Google all-day end dates are exclusive and never shift with time zone.
      if (!start || !end || date < start || date >= end) continue;
      entries.push({
        source: 'google',
        event,
        date,
        key: `google:${event.calendarId}:${event.id}:${date}`,
        title: event.title,
        start: null,
        end: null,
        completed: event.googleTask?.status === 'completed',
        allDay: true,
        busy: event.busy,
        continued: start < date,
        continues: end > addDays(date, 1),
        duration: 1440,
        startLabel: null,
        endLabel: null,
        clockChange: false,
      });
      continue;
    }
    const parts = timedParts(event, timeZone);
    if (!parts) continue;
    const { start, end, duration, wallDuration, ambiguous } = parts;
    if (start.date > date || end.date < date || (end.date === date && end.seconds === 0)) continue;
    const continued = start.date < date;
    const startMinute = continued ? 0 : Math.floor(start.seconds / 60);
    const endMinute = end.date > date ? 1440 : Math.ceil(end.seconds / 60);
    const clockChange = Math.abs(wallDuration - duration) >= 1 || ambiguous;
    // A backward clock change may make wall-clock end < start. Draw a positive
    // segment while keeping the actual endpoint labels and clock-change notice.
    const drawnEnd = Math.min(
      1440,
      Math.max(startMinute + 1, endMinute > startMinute ? endMinute : startMinute + duration),
    );
    entries.push({
      source: 'google',
      event,
      date,
      key: `google:${event.calendarId}:${event.id}:${date}`,
      title: event.title,
      start: startMinute,
      end: drawnEnd,
      completed: event.googleTask?.status === 'completed',
      allDay: false,
      busy: event.busy,
      continued,
      continues: end.date > date && !(end.date === addDays(date, 1) && end.seconds === 0),
      duration,
      startLabel: continued ? formatTime(0) : formatTime(start.time),
      endLabel: end.date > date ? formatTime(1440) : formatTime(end.time),
      clockChange,
    });
  }
  return entries;
}

export function calendarOccurrences(
  tasks: Task[],
  googleEvents: GoogleCalendarEvent[],
  date: string,
  timeZone: string,
): CalendarOccurrence[] {
  const local: CalendarOccurrence[] = getDayOccurrences(
    tasks.filter((task) => task.calendarEntry !== false),
    date,
  ).map((entry) => ({
    source: 'ritm',
    task: entry.task,
    date,
    key: `ritm:${entry.key}`,
    title: entry.task.title,
    start: entry.start,
    end: entry.end,
    completed: entry.completed,
    allDay: false,
    busy: !entry.completed && entry.start !== null,
    continued: entry.key.endsWith(':continued'),
    continues:
      entry.end === 1440 &&
      (entry.task.time
        ? Number(entry.task.time.slice(0, 2)) * 60 +
            Number(entry.task.time.slice(3)) +
            entry.task.duration >
          1440
        : false),
    duration: entry.task.duration,
    startLabel: null,
    endLabel: null,
    clockChange: false,
  }));
  return local
    .concat(googleOccurrences(googleEvents, date, timeZone))
    .sort(
      (a, b) =>
        Number(b.allDay) - Number(a.allDay) ||
        (a.start ?? 1441) - (b.start ?? 1441) ||
        a.title.localeCompare(b.title, 'ru') ||
        a.key.localeCompare(b.key),
    );
}

export function calendarRange(view: 'day' | 'week' | 'month', selectedDate: string) {
  if (view === 'day') return { from: selectedDate, to: addDays(selectedDate, 1) };
  if (view === 'week') {
    const from = startOfWeek(selectedDate);
    return { from, to: addDays(from, 7) };
  }
  const month = parseDate(selectedDate);
  month.setUTCDate(1);
  const from = startOfWeek(dateKey(month));
  return { from, to: addDays(from, 42) };
}

type Timed<T> = T & { start: number; end: number; lane: number; lanes: number };
/** Shared positioning for mixed sources; no conversion to synthetic Task IDs. */
export function layoutCalendarOccurrences<T extends { start: number | null; end: number | null }>(
  entries: T[],
): Timed<T>[] {
  const timed = entries
    .filter(
      (entry): entry is T & { start: number; end: number } =>
        entry.start !== null && entry.end !== null,
    )
    .sort((a, b) => a.start - b.start || b.end - a.end);
  const result: Timed<T>[] = [];
  let group: Timed<T>[] = [],
    laneEnds: number[] = [],
    groupEnd = -1;
  const finish = () => {
    group.forEach((entry) => {
      entry.lanes = laneEnds.length;
    });
    result.push(...group);
    group = [];
    laneEnds = [];
    groupEnd = -1;
  };
  for (const entry of timed) {
    if (group.length && entry.start >= groupEnd) finish();
    let lane = laneEnds.findIndex((end) => end <= entry.start);
    if (lane === -1) lane = laneEnds.length;
    laneEnds[lane] = entry.end;
    group.push({ ...entry, lane, lanes: 1 });
    groupEnd = Math.max(groupEnd, entry.end);
  }
  finish();
  return result;
}
