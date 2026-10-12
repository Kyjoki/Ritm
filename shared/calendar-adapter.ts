/** Future Google Calendar boundary. No provider connection exists in this release. */
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
