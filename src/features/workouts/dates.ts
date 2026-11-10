/** Date math in the account time zone. Weeks start on Sunday (0 = Sunday … 6 = Saturday). */
import { dateInZone } from '../../lib/date';

const DAY_MS = 86_400_000;

export const addDays = (key: string, days: number): string =>
  new Date(Date.parse(`${key}T12:00:00Z`) + days * DAY_MS).toISOString().slice(0, 10);
export const weekday = (key: string): number => new Date(`${key}T12:00:00Z`).getUTCDay();
export const weekStart = (key: string): string => addDays(key, -weekday(key));
export const weekKeys = (key: string): string[] =>
  Array.from({ length: 7 }, (_, index) => addDays(weekStart(key), index));

/** yyyy-MM-dd of an ISO instant in the owner's zone. */
export function dateKey(iso: string, timeZone: string): string {
  const time = Date.parse(iso);
  return Number.isNaN(time) ? '' : dateInZone(timeZone, new Date(time));
}

/** Swift's `.iso8601` strategy: UTC, whole seconds, trailing `Z`. Milliseconds would not decode on the iPhone. */
export const toWireDate = (date: Date): string => date.toISOString().replace(/\.\d{3}Z$/, 'Z');

/** The offset (ms) of a zone at an instant: local wall time minus UTC. */
function zoneOffset(time: number, timeZone: string): number {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    hourCycle: 'h23',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  }).formatToParts(new Date(time));
  const pick = (type: string) => Number(parts.find((part) => part.type === type)?.value);
  const local = Date.UTC(
    pick('year'),
    pick('month') - 1,
    pick('day'),
    pick('hour'),
    pick('minute'),
    pick('second'),
  );
  return local - Math.floor(time / 1000) * 1000;
}

/** Noon of a calendar day in the zone, as a wire date: it stays on that day everywhere. */
export function zonedNoon(key: string, timeZone: string): string {
  const guess = Date.parse(`${key}T12:00:00Z`);
  const first = guess - zoneOffset(guess, timeZone);
  return toWireDate(new Date(guess - zoneOffset(first, timeZone)));
}
