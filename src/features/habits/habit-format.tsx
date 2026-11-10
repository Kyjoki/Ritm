import { Fragment, type ReactNode } from 'react';
import type { Habit } from '../../../shared/types';
import { formatDate } from '../../lib/date';
import type { Language } from '../../lib/i18n';
import { addDays } from '../calendar-utils';

type Translate = (source: string, values?: Record<string, string | number>) => string;

const SUNDAY = '2026-10-25';
const upper = (text: string) => text.charAt(0).toLocaleUpperCase() + text.slice(1);

/** Two-letter weekday heads: «Вс», «Sun». Weeks start on Sunday (0). */
export function weekdayShort(weekday: number, language: Language): string {
  return upper(formatDate(addDays(SUNDAY, weekday), { weekday: 'short' }, language));
}
export function weekdayOf(date: string, language: Language): string {
  return upper(formatDate(date, { weekday: 'short' }, language));
}
export function weekdayLong(date: string, language: Language): string {
  return upper(formatDate(date, { weekday: 'long' }, language));
}
export function shortDate(date: string, language: Language): string {
  return formatDate(date, { day: 'numeric', month: 'short' }, language);
}
export const dayNumber = (date: string) => Number(date.slice(8));

export function formatAmount(amount: number, language: Language): string {
  return new Intl.NumberFormat(language === 'en' ? 'en-US' : 'ru-RU').format(amount);
}

export function periodLabel(dates: readonly string[], week: boolean, language: Language): string {
  const first = dates[0];
  const last = dates[dates.length - 1];
  if (!week) return upper(formatDate(first, { month: 'long', year: 'numeric' }, language));
  if (first.slice(0, 7) !== last.slice(0, 7))
    return shortDate(first, language) + ' – ' + shortDate(last, language);
  return language === 'en'
    ? shortDate(first, language) + ' – ' + dayNumber(last)
    : dayNumber(first) + '–' + shortDate(last, language);
}

export function scheduleText(habit: Habit, t: Translate, language: Language): string {
  const days = [...(habit.weekdays ?? [0, 1, 2, 3, 4, 5, 6])].sort((a, b) => a - b);
  const base =
    days.length === 7
      ? t('Каждый день')
      : days.map((weekday) => weekdayShort(weekday, language)).join(' ');
  if (habit.target)
    return (
      base + ' · ' + formatAmount(habit.target, language) + (habit.unit ? ' ' + habit.unit : '')
    );
  return days.length === 7 ? base : base + ' · ' + t('{count}/нед', { count: days.length });
}

/** Fills `{name}` slots of an already translated sentence with elements (animated numbers). */
export function fillTemplate(template: string, slots: Record<string, ReactNode>): ReactNode {
  return template.split(/(\{[a-zA-Z]+\})/).map((part, index) => {
    const key = /^\{([a-zA-Z]+)\}$/.exec(part)?.[1];
    return <Fragment key={index}>{key && key in slots ? slots[key] : part}</Fragment>;
  });
}

/** Russian wording for streak milestones: «3 дня подряд», «7 дней подряд». */
export function daysInRow(count: number, t: Translate): string {
  return t(count === 3 ? '{count} дня подряд' : '{count} дней подряд', { count });
}
