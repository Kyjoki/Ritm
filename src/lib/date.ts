import { dateTimeFormatter } from './intl-formatters';
export function dateInZone(timeZone: string, date = new Date()): string {
  const parts = dateTimeFormatter('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(date);
  const part = (type: string) => parts.find((p) => p.type === type)?.value;
  return `${part('year')}-${part('month')}-${part('day')}`;
}
export function minutesInZone(timeZone: string, date = new Date()): number {
  const parts = dateTimeFormatter('en-GB', {
    timeZone,
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(date);
  return (
    Number(parts.find((p) => p.type === 'hour')?.value) * 60 +
    Number(parts.find((p) => p.type === 'minute')?.value)
  );
}
export function localDate(date: string): Date {
  return new Date(`${date}T12:00:00`);
}
export function formatDate(
  date: string,
  options: Intl.DateTimeFormatOptions = { day: 'numeric', month: 'long' },
  language: 'ru' | 'en' = 'ru',
): string {
  return dateTimeFormatter(language === 'en' ? 'en-US' : 'ru-RU', options).format(localDate(date));
}
export function formatTime(value: number | string, options: { compact?: boolean } = {}): string {
  let minutes: number;
  if (typeof value === 'string') {
    const match = /^(\d{2}):(\d{2})$/.exec(value);
    if (!match || Number(match[1]) > 23 || Number(match[2]) > 59) return '—';
    minutes = Number(match[1]) * 60 + Number(match[2]);
  } else minutes = value;
  if (!Number.isFinite(minutes)) return '—';
  const normalized = Math.floor(((minutes % 1440) + 1440) % 1440);
  const hour = Math.floor(normalized / 60);
  const minute = normalized % 60;
  const suffix = hour < 12 ? 'AM' : 'PM';
  const minuteLabel = options.compact && minute === 0 ? '' : `:${String(minute).padStart(2, '0')}`;
  return `${hour % 12 || 12}${minuteLabel} ${suffix}`;
}
export function durationText(minutes: number, language: 'ru' | 'en' = 'ru'): string {
  const hours = Math.floor(minutes / 60),
    rest = minutes % 60;
  return (
    [
      hours ? `${hours} ${language === 'en' ? 'h' : 'ч'}` : '',
      rest ? `${rest} ${language === 'en' ? 'min' : 'мин'}` : '',
    ]
      .filter(Boolean)
      .join(' ') || (language === 'en' ? '0 min' : '0 мин')
  );
}
export function greeting(hour: number): string {
  return hour < 6
    ? 'Доброй ночи'
    : hour < 12
      ? 'Доброе утро'
      : hour < 18
        ? 'Добрый день'
        : 'Добрый вечер';
}
