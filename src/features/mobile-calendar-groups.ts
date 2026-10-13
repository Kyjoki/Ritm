import type { CalendarOccurrence } from './google-occurrences';

export interface MobileCalendarGroup {
  key: string;
  start: number;
  end: number;
  entries: CalendarOccurrence[];
}

/** Connected overlaps share one mobile target; touching intervals remain separate. */
export function mobileCalendarGroups(
  entries: readonly CalendarOccurrence[],
): MobileCalendarGroup[] {
  const timed = entries
    .filter(
      (entry): entry is CalendarOccurrence & { start: number; end: number } =>
        !entry.allDay && entry.start !== null && entry.end !== null,
    )
    .sort(
      (a, b) => a.start - b.start || a.end - b.end || (a.key < b.key ? -1 : a.key > b.key ? 1 : 0),
    );
  const groups: MobileCalendarGroup[] = [];
  for (const entry of timed) {
    const group = groups.at(-1);
    if (group && entry.start < group.end) {
      group.end = Math.max(group.end, entry.end);
      group.entries.push(entry);
    } else {
      groups.push({ key: entry.key, start: entry.start, end: entry.end, entries: [entry] });
    }
  }
  return groups;
}
