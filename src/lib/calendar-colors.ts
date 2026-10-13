import type { CSSProperties } from 'react';
import { CALENDAR_COLORS } from '../../shared/calendar-colors';
import type { CalendarOccurrence } from '../features/google-occurrences';

export function calendarEntryStyle(entry: CalendarOccurrence): CSSProperties {
  const id = entry.source === 'google' ? entry.event.colorId : entry.task.colorId;
  const color = CALENDAR_COLORS.find((color) => color.id === id)?.hex ?? 'var(--accent)';
  return {
    '--calendar-event-bg': `color-mix(in srgb, ${color} 24%, var(--panel))`,
    '--calendar-event-text': 'var(--text)',
    '--calendar-event-border': `color-mix(in srgb, ${color} 76%, var(--panel))`,
  } as CSSProperties;
}
