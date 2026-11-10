import type { Settings } from '../../../shared/types';

/** A set of changed settings fields: the only thing that is ever sent to PATCH /api/settings. */
export type SettingsPatch = Partial<Settings>;

export interface TimeZoneOption {
  id: string;
  /** Russian source string, translated with t() at render time. */
  name: string;
}

export const TIME_ZONES: readonly TimeZoneOption[] = [
  { id: 'Asia/Qyzylorda', name: 'Кызылорда' },
  { id: 'Asia/Almaty', name: 'Алматы, Астана' },
  { id: 'Europe/Moscow', name: 'Москва' },
  { id: 'Europe/Kyiv', name: 'Киев' },
  { id: 'Europe/Minsk', name: 'Минск' },
  { id: 'Asia/Tashkent', name: 'Ташкент' },
  { id: 'Asia/Bishkek', name: 'Бишкек' },
  { id: 'Europe/Berlin', name: 'Берлин' },
  { id: 'Europe/London', name: 'Лондон' },
  { id: 'America/New_York', name: 'Нью-Йорк' },
  { id: 'UTC', name: 'Всемирное время' },
];

export const NAME_MAX_LENGTH = 60;
export const EMAIL_MAX_LENGTH = 254;
export const TELEGRAM_LEADS = [0, 5, 10, 15, 30, 60] as const;
export type TelegramLead = (typeof TELEGRAM_LEADS)[number];
export const DEFAULT_TELEGRAM_LEAD: TelegramLead = 10;

const TIME_PATTERN = /^(?:[01]\d|2[0-3]):[0-5]\d$/;
// Same rule as the server (zod email), so the client never sends what the server will reject.
const EMAIL_PATTERN =
  /^(?!\.)(?!.*\.\.)([A-Za-z0-9_'+\-.]*)[A-Za-z0-9_+-]@([A-Za-z0-9][A-Za-z0-9-]*\.)+[A-Za-z]{2,}$/;

export type SettingsIssue =
  | 'name-required'
  | 'name-too-long'
  | 'email-invalid'
  | 'time-invalid'
  | 'day-order'
  | 'zone-invalid';

/** Russian source strings; callers translate them with t(). */
export const ISSUE_MESSAGES: Record<SettingsIssue, string> = {
  'name-required': 'Введи имя, которым к тебе будет обращаться помощник.',
  'name-too-long': 'Имя не длиннее 60 символов.',
  'email-invalid': 'Проверь адрес электронной почты.',
  'time-invalid': 'Укажи время в формате ЧЧ:ММ.',
  'day-order': 'Конец рабочего дня должен быть позже начала.',
  'zone-invalid': 'Неизвестный часовой пояс.',
};

export function isValidTimeZone(timeZone: string): boolean {
  try {
    new Intl.DateTimeFormat('ru', { timeZone });
    return true;
  } catch {
    return false;
  }
}

export function isValidEmail(email: string): boolean {
  return email === '' || (email.length <= EMAIL_MAX_LENGTH && EMAIL_PATTERN.test(email));
}

/** The workday must start before it ends; both are HH:MM so a string compare is exact. */
export function dayRangeIssue(start: string, end: string): SettingsIssue | null {
  if (!TIME_PATTERN.test(start) || !TIME_PATTERN.test(end)) return 'time-invalid';
  return end > start ? null : 'day-order';
}

function profileIssue(patch: SettingsPatch): SettingsIssue | null {
  if (patch.displayName !== undefined) {
    if (!patch.displayName) return 'name-required';
    if (patch.displayName.length > NAME_MAX_LENGTH) return 'name-too-long';
  }
  if (patch.email !== undefined && !isValidEmail(patch.email)) return 'email-invalid';
  return null;
}

/** Trim text fields and drop every key that does not differ from the current settings. */
export function diffPatch(current: Settings, changes: SettingsPatch): SettingsPatch {
  const next: SettingsPatch = {};
  for (const key of Object.keys(changes) as (keyof Settings)[]) {
    const raw = changes[key];
    if (raw === undefined) continue;
    const value =
      typeof raw === 'string' && (key === 'displayName' || key === 'email') ? raw.trim() : raw;
    if (value !== current[key]) Object.assign(next, { [key]: value });
  }
  return next;
}

export interface PreparedPatch {
  patch: SettingsPatch;
  issue: SettingsIssue | null;
}

/** Build the patch to send: only changed fields, trimmed, or the first issue that forbids sending. */
export function prepareSettingsPatch(current: Settings, changes: SettingsPatch): PreparedPatch {
  const patch = diffPatch(current, changes);
  const issue =
    profileIssue(patch) ??
    (patch.timeZone !== undefined && !isValidTimeZone(patch.timeZone) ? 'zone-invalid' : null) ??
    dayIssue(current, patch);
  return { patch: issue ? {} : patch, issue };
}

function dayIssue(current: Settings, patch: SettingsPatch): SettingsIssue | null {
  if (patch.workDayStart === undefined && patch.workDayEnd === undefined) return null;
  return dayRangeIssue(
    patch.workDayStart ?? current.workDayStart,
    patch.workDayEnd ?? current.workDayEnd,
  );
}

/** Optimistic update: a new object, the original is never mutated. */
export function applySettingsPatch(current: Settings, patch: SettingsPatch): Settings {
  return { ...current, ...patch };
}

/**
 * Undo a failed save. A field goes back to its previous value only if it still holds the
 * optimistic value, so a newer change to the same field made in the meantime is kept.
 */
export function rollbackSettingsPatch(
  current: Settings,
  patch: SettingsPatch,
  previous: Settings,
): Settings {
  const restored: SettingsPatch = {};
  for (const key of Object.keys(patch) as (keyof Settings)[]) {
    if (current[key] === patch[key]) Object.assign(restored, { [key]: previous[key] });
  }
  return { ...current, ...restored };
}

/** Runs async tasks strictly one after another so PATCH requests are never reordered. */
export function createSerialQueue(): <T>(task: () => Promise<T>) => Promise<T> {
  let tail: Promise<unknown> = Promise.resolve();
  return (task) => {
    const run = tail.then(task, task);
    tail = run.catch(() => undefined);
    return run;
  };
}

/** "UTC+5", "UTC−5", "UTC+0": the offset that is in force in the zone at the given moment. */
export function utcOffsetLabel(timeZone: string, at: Date): string {
  try {
    const offset = new Intl.DateTimeFormat('en-US', { timeZone, timeZoneName: 'shortOffset' })
      .formatToParts(at)
      .find((part) => part.type === 'timeZoneName')?.value;
    if (!offset) return '';
    return (offset === 'GMT' ? 'GMT+0' : offset).replace('GMT', 'UTC').replace('-', '−');
  } catch {
    return '';
  }
}

/** Local time in the zone, 24-hour HH:MM. */
export function zoneClock(timeZone: string, at: Date): string {
  try {
    return new Intl.DateTimeFormat('en-GB', {
      timeZone,
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    }).format(at);
  } catch {
    return '--:--';
  }
}

export function timeZoneName(timeZone: string): string {
  return TIME_ZONES.find((zone) => zone.id === timeZone)?.name ?? timeZone;
}

export function profileInitials(displayName: string, fallback: string): string {
  const letters = displayName
    .trim()
    .split(/\s+/)
    .map((part) => part[0] ?? '')
    .slice(0, 2)
    .join('')
    .toUpperCase();
  return letters || fallback;
}
