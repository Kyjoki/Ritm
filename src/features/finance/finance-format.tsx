import { useCallback } from 'react';
import {
  ArrowLeftRight,
  Banknote,
  Briefcase,
  Bus,
  Coffee,
  Gift,
  HeartPulse,
  House,
  Percent,
  ShoppingBag,
  ShoppingCart,
  Tag,
  Ticket,
  type LucideIcon,
} from 'lucide-react';
import type { FinanceCurrency } from '../../../shared/types';
import { dateTimeFormatter, numberFormatter } from '../../lib/intl-formatters';
import { useI18n } from '../../lib/i18n';

export type MoneyFormat = (minor: number, currency: FinanceCurrency) => string;

export function formatMoney(locale: string, currency: FinanceCurrency, minor: number): string {
  return numberFormatter(locale, {
    style: 'currency',
    currency,
    currencyDisplay: 'narrowSymbol',
    minimumFractionDigits: minor % 100 ? 2 : 0,
    maximumFractionDigits: 2,
  }).format(minor / 100);
}

/** «+12 000 ₸» or «−3 000 ₸»; zero has no sign. */
export function formatSigned(locale: string, currency: FinanceCurrency, minor: number): string {
  const body = formatMoney(locale, currency, Math.abs(minor));
  return minor > 0 ? `+${body}` : minor < 0 ? `−${body}` : body;
}

export function formatPercent(locale: string, ratio: number, signed = false, digits = 1): string {
  return numberFormatter(locale, {
    style: 'percent',
    maximumFractionDigits: digits,
    ...(signed ? { signDisplay: 'always' as const } : {}),
  }).format(ratio);
}

export function useMoney() {
  const { locale } = useI18n();
  const money = useCallback<MoneyFormat>(
    (minor, currency) => formatMoney(locale, currency, minor),
    [locale],
  );
  const signed = useCallback<MoneyFormat>(
    (minor, currency) => formatSigned(locale, currency, minor),
    [locale],
  );
  return { money, signed };
}

export function useDayLabel() {
  const { locale } = useI18n();
  const full = useCallback(
    (value: string) =>
      dateTimeFormatter(locale, { day: 'numeric', month: 'short', year: 'numeric' }).format(
        new Date(`${value}T12:00:00`),
      ),
    [locale],
  );
  const short = useCallback(
    (value: string) =>
      dateTimeFormatter(locale, { day: 'numeric', month: 'short' }).format(
        new Date(`${value}T12:00:00`),
      ),
    [locale],
  );
  return { full, short };
}

const CATEGORY_ICONS: Record<string, LucideIcon> = {
  Продукты: ShoppingCart,
  Кафе: Coffee,
  Транспорт: Bus,
  Дом: House,
  Здоровье: HeartPulse,
  Покупки: ShoppingBag,
  Развлечения: Ticket,
  Зарплата: Banknote,
  Подработка: Briefcase,
  Подарок: Gift,
  Проценты: Percent,
};

export function CategoryIcon({ category, size = 18 }: { category: string; size?: number }) {
  const Icon = CATEGORY_ICONS[category.trim()] ?? Tag;
  return <Icon size={size} aria-hidden="true" />;
}

export function TransferIcon({ size = 18 }: { size?: number }) {
  return <ArrowLeftRight size={size} aria-hidden="true" />;
}
