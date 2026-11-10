import type { FinanceEntry } from '../../../shared/types';
import { entryDay } from './finance-wallet';

const MONTHS_RU = [
  'янв',
  'фев',
  'мар',
  'апр',
  'мая',
  'июн',
  'июл',
  'авг',
  'сен',
  'окт',
  'ноя',
  'дек',
];
const MONTHS_EN = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
const WEEKDAYS_RU = ['вс', 'пн', 'вт', 'ср', 'чт', 'пт', 'сб'];
const WEEKDAYS_EN = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

export type HistoryFilter = 'all' | 'expense' | 'income' | 'transfer';
export interface HistoryDay {
  /** yyyy-mm-dd, empty for entries without a valid date. */
  key: string;
  dayNumber: string;
  month: string;
  weekday: string;
  relative: 'today' | 'yesterday' | null;
  entries: FinanceEntry[];
}

export function applyHistoryFilter(entries: FinanceEntry[], filter: HistoryFilter): FinanceEntry[] {
  return filter === 'all' ? entries : entries.filter((entry) => entry.type === filter);
}

const validDay = (value: string) => /^\d{4}-\d{2}-\d{2}$/.test(value);
const previousDay = (day: string) =>
  new Date(new Date(`${day}T12:00:00Z`).getTime() - 864e5).toISOString().slice(0, 10);

/** Days newest first; inside a day the order of `entries` is kept. */
export function groupByDay(
  entries: FinanceEntry[],
  today: string,
  language: 'ru' | 'en',
): HistoryDay[] {
  const buckets = new Map<string, FinanceEntry[]>();
  for (const entry of entries) {
    const raw = entryDay(entry);
    const key = validDay(raw) ? raw : '';
    buckets.set(key, [...(buckets.get(key) ?? []), entry]);
  }
  const months = language === 'en' ? MONTHS_EN : MONTHS_RU;
  const weekdays = language === 'en' ? WEEKDAYS_EN : WEEKDAYS_RU;
  const yesterday = previousDay(today);
  const keys = [...buckets.keys()].filter(Boolean).sort().reverse();
  if (buckets.has('')) keys.push('');
  return keys.map((key) => {
    const list = buckets.get(key) ?? [];
    if (!key) return { key, dayNumber: '', month: '', weekday: '', relative: null, entries: list };
    const [year, month, day] = key.split('-').map(Number);
    return {
      key,
      dayNumber: String(day),
      month: months[month - 1] + (String(year) !== today.slice(0, 4) ? ` ${year}` : ''),
      weekday: weekdays[new Date(`${key}T12:00:00Z`).getUTCDay()],
      relative: key === today ? 'today' : key === yesterday ? 'yesterday' : null,
      entries: list,
    };
  });
}
