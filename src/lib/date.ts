export function dateInZone(timeZone: string, date = new Date()): string {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(date);
  const part = (type: string) => parts.find((p) => p.type === type)?.value;
  return `${part('year')}-${part('month')}-${part('day')}`;
}
export function minutesInZone(timeZone: string, date = new Date()): number {
  const parts = new Intl.DateTimeFormat('en-GB', {
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
): string {
  return new Intl.DateTimeFormat('ru-RU', options).format(localDate(date));
}
export function formatTime(minutes: number): string {
  return `${String(Math.floor(minutes / 60) % 24).padStart(2, '0')}:${String(minutes % 60).padStart(2, '0')}`;
}
export function durationText(minutes: number): string {
  const hours = Math.floor(minutes / 60),
    rest = minutes % 60;
  return (
    [hours ? `${hours} ч` : '', rest ? `${rest} мин` : ''].filter(Boolean).join(' ') || '0 мин'
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
