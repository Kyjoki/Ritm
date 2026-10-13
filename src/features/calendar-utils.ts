import type { Task } from '../../shared/types';

export interface TaskOccurrence {
  task: Task;
  date: string;
  start: number | null;
  end: number | null;
  key: string;
  completed: boolean;
}

export function isTimedOccurrence(
  entry: TaskOccurrence,
): entry is TaskOccurrence & { start: number; end: number } {
  return entry.start !== null && entry.end !== null;
}

const DAY = 86_400_000;

export function parseDate(date: string): Date {
  return new Date(`${date}T12:00:00Z`);
}

export function dateKey(date: Date): string {
  return date.toISOString().slice(0, 10);
}

export function addDays(date: string, amount: number): string {
  return dateKey(new Date(parseDate(date).getTime() + amount * DAY));
}

export function addMonths(date: string, amount: number): string {
  const value = parseDate(date);
  const day = value.getUTCDate();
  value.setUTCDate(1);
  value.setUTCMonth(value.getUTCMonth() + amount);
  const monthEnd = new Date(
    Date.UTC(value.getUTCFullYear(), value.getUTCMonth() + 1, 0),
  ).getUTCDate();
  value.setUTCDate(Math.min(day, monthEnd));
  return dateKey(value);
}

export function startOfWeek(date: string): string {
  return addDays(date, -parseDate(date).getUTCDay());
}

export function timeMinutes(time: string): number {
  const [hour, minute] = time.split(':').map(Number);
  return hour * 60 + minute;
}

export function minuteTime(minute: number): string {
  const normalized = ((minute % 1440) + 1440) % 1440;
  return `${String(Math.floor(normalized / 60)).padStart(2, '0')}:${String(normalized % 60).padStart(2, '0')}`;
}

export function formatDate(date: string, options: Intl.DateTimeFormatOptions): string {
  return new Intl.DateTimeFormat('ru-RU', { ...options, timeZone: 'UTC' }).format(parseDate(date));
}

export function taskOccursOn(task: Task, date: string): boolean {
  if (!task.date || task.date > date) return false;
  if (task.repeat === 'none') return task.date === date;
  if (task.repeat === 'daily') return true;
  const origin = parseDate(task.date);
  const target = parseDate(date);
  if (task.repeat === 'weekly') return origin.getUTCDay() === target.getUTCDay();
  return origin.getUTCDate() === target.getUTCDate();
}

export function getDayOccurrences(tasks: Task[], date: string): TaskOccurrence[] {
  const result: TaskOccurrence[] = [];
  for (const task of tasks) {
    if (taskOccursOn(task, date)) {
      const start = task.time ? timeMinutes(task.time) : null;
      const completed =
        task.repeat === 'none' ? task.completed : task.completedDates.includes(date);
      result.push({
        task,
        date,
        start,
        end: start === null ? null : Math.min(1440, start + task.duration),
        key: `${task.id}:${date}`,
        completed,
      });
    }
    // Late events remain visible after midnight on the following day.
    if (task.time) {
      const previous = addDays(date, -1);
      const overflow = timeMinutes(task.time) + task.duration - 1440;
      if (overflow > 0 && taskOccursOn(task, previous)) {
        const completed =
          task.repeat === 'none' ? task.completed : task.completedDates.includes(previous);
        result.push({
          task,
          date: previous,
          start: 0,
          end: Math.min(1440, overflow),
          key: `${task.id}:${previous}:continued`,
          completed,
        });
      }
    }
  }
  return result.sort(
    (a, b) =>
      (a.start ?? 1441) - (b.start ?? 1441) || a.task.title.localeCompare(b.task.title, 'ru'),
  );
}

export interface PositionedOccurrence extends TaskOccurrence {
  lane: number;
  lanes: number;
}

export function layoutOccurrences(occurrences: TaskOccurrence[]): PositionedOccurrence[] {
  const timed = occurrences
    .filter(isTimedOccurrence)
    .sort((a, b) => a.start - b.start || b.end - a.end);
  const result: PositionedOccurrence[] = [];
  let group: PositionedOccurrence[] = [];
  let groupEnd = -1;
  let laneEnds: number[] = [];
  const finishGroup = () => {
    for (const entry of group) entry.lanes = laneEnds.length;
    result.push(...group);
    group = [];
    laneEnds = [];
  };
  for (const entry of timed) {
    if (entry.start >= groupEnd && group.length) finishGroup();
    let lane = laneEnds.findIndex((end) => end <= entry.start);
    if (lane === -1) lane = laneEnds.length;
    laneEnds[lane] = entry.end;
    group.push({ ...entry, lane, lanes: 1 });
    groupEnd = Math.max(groupEnd, entry.end);
  }
  finishGroup();
  return result;
}

export function durationLabel(duration: number): string {
  const hours = Math.floor(duration / 60);
  const minutes = duration % 60;
  return [hours ? `${hours} ч` : '', minutes ? `${minutes} мин` : ''].filter(Boolean).join(' ');
}
