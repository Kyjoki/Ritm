/** Legacy provider-neutral contract. Current Google DTOs are in shared/types.ts;
 * server/google-calendar.ts is the implementation and requires owner OAuth setup. */
export interface ExternalCalendarEvent {
  externalId: string;
  calendarId: string;
  title: string;
  description?: string;
  start: string;
  end: string;
  timeZone: string;
  allDay: boolean;
  updatedAt: string;
}

export interface CalendarConnectionStatus {
  provider: 'google';
  connected: boolean;
  accountLabel?: string;
  lastSyncedAt?: string;
}

export interface CalendarAdapter {
  getStatus(): Promise<CalendarConnectionStatus>;
  listEvents(period: {
    from: string;
    to: string;
    timeZone: string;
  }): Promise<ExternalCalendarEvent[]>;
  disconnect(): Promise<void>;
}
