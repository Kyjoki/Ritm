/** Text and number formatting of «Тренировки» (the prototype's W.fmt / kg / tons / dur / rel). */
import { addDays } from './dates';
import { dateTimeFormatter, numberFormatter } from '../../lib/intl-formatters';
import { dateKey } from './dates';
import type { Language } from '../../lib/i18n';

export const NBSP = ' ';
const locale = (language: Language) => (language === 'en' ? 'en-US' : 'ru-RU');

export const decimal = (value: number, language: Language): string =>
  numberFormatter(locale(language), { maximumFractionDigits: 1 }).format(value);
export const kgNumber = (value: number, language: Language): string =>
  numberFormatter(locale(language), { maximumFractionDigits: 0, useGrouping: true })
    .format(Math.round(value))
    .replace(/\s/g, NBSP);
export const kgText = (value: number, language: Language): string =>
  `${kgNumber(value, language)}${NBSP}${language === 'en' ? 'kg' : 'кг'}`;
export const tonsText = (value: number, language: Language): string =>
  value >= 1000
    ? `${decimal(Math.round(value / 100) / 10, language)}${NBSP}${language === 'en' ? 't' : 'т'}`
    : kgText(value, language);

export function clock(seconds: number): string {
  const total = Math.max(0, Math.floor(seconds));
  const hours = Math.floor(total / 3600);
  const minutes = String(Math.floor(total / 60) % 60).padStart(hours ? 2 : 1, '0');
  const rest = String(total % 60).padStart(2, '0');
  return hours ? `${hours}:${minutes}:${rest}` : `${minutes}:${rest}`;
}
export function durationText(seconds: number, language: Language): string {
  const minutes = Math.max(1, Math.round(seconds / 60));
  const [h, m] = language === 'en' ? ['h', 'min'] : ['ч', 'мин'];
  return minutes >= 60
    ? `${Math.floor(minutes / 60)} ${h} ${String(minutes % 60).padStart(2, '0')} ${m}`
    : `${minutes} ${m}`;
}
/** Russian plural forms: 1 подход, 2 подхода, 5 подходов. */
export function plural(count: number, one: string, few: string, many: string): string {
  const hundred = count % 100;
  const ten = count % 10;
  return hundred > 10 && hundred < 15 ? many : ten === 1 ? one : ten > 1 && ten < 5 ? few : many;
}

const day = (key: string, language: Language, options: Intl.DateTimeFormatOptions) =>
  dateTimeFormatter(locale(language), { timeZone: 'UTC', ...options }).format(
    new Date(`${key}T12:00:00Z`),
  );
export const dayMonth = (key: string, language: Language) =>
  day(key, language, { day: 'numeric', month: 'long' });
export const shortDate = (key: string, language: Language) =>
  day(key, language, { day: 'numeric', month: 'short' }).replace('.', '');
export const longDate = (key: string, language: Language) =>
  day(key, language, { day: 'numeric', month: 'long', year: 'numeric' }).replace(' г.', '');
export const weekdayShort = (key: string, language: Language) =>
  day(key, language, { weekday: 'short' }).replace('.', '');

/** «Сегодня» / «Вчера» / «12 октября» for the history rows. */
export function relativeDay(
  key: string,
  today: string,
  language: Language,
  t: (source: string) => string,
  lowercase = false,
): string {
  const word =
    key === today
      ? t('Сегодня')
      : key === addDays(today, -1)
        ? t('Вчера')
        : dayMonth(key, language);
  return lowercase && (key === today || key === addDays(today, -1)) ? word.toLowerCase() : word;
}
/** «4 подхода» / «1 set». */
export const setsText = (count: number, language: Language): string =>
  language === 'en'
    ? `${count} ${count === 1 ? 'set' : 'sets'}`
    : `${count} ${plural(count, 'подход', 'подхода', 'подходов')}`;
