import type { FinanceCurrency, FinanceEntry, FinanceEntryInput } from '../../../shared/types';
import { requestAccountId } from './finance-wallet';

export type Currency = FinanceCurrency;
export type Kind = FinanceEntry['type'];
export type Translate = (source: string, values?: Record<string, string | number>) => string;
export type FormState = {
  type: Kind;
  amount: string;
  currency: Currency;
  date: string;
  category: string;
  name: string;
  note: string;
  exchange: 'KASE' | 'AIX';
  ticker: string;
  quantity: string;
  unitPrice: string;
  purchasePrice: string;
  fromAccountId: string;
  toAccountId: string;
  /** Account an income or expense is booked into ('' means the main account). */
  accountId: string;
};

export const CURRENCIES: Currency[] = ['KZT', 'USD', 'EUR', 'RUB'];
export const EXPENSE_CATEGORIES = [
  'Продукты',
  'Кафе',
  'Транспорт',
  'Дом',
  'Здоровье',
  'Покупки',
  'Развлечения',
];
export const INCOME_CATEGORIES = ['Зарплата', 'Подработка', 'Подарок', 'Проценты'];
const MAX_MINOR = 1_000_000_000_000;

export function localDate() {
  const today = new Date();
  return `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;
}

export function emptyForm(currency: Currency, type: Kind = 'expense'): FormState {
  return {
    type,
    amount: '',
    currency,
    date: localDate(),
    category: '',
    name: '',
    note: '',
    exchange: 'KASE',
    ticker: '',
    quantity: '',
    unitPrice: '',
    purchasePrice: '',
    fromAccountId: '',
    toAccountId: '',
    accountId: '',
  };
}

export function quoteUrl(exchange: 'KASE' | 'AIX', ticker: string): string | null {
  if (!/^[A-Z0-9._-]{1,30}$/.test(ticker)) return null;
  return exchange === 'KASE'
    ? `https://kase.kz/en/investors/shares/${ticker}/`
    : `https://data-feed.aix.kz/symbol/${ticker}/trading`;
}

export function parseMinor(value: string): number | null {
  const normalized = value
    .trim()
    .replace(/[\s  ]/g, '')
    .replace(',', '.');
  if (!/^\d+(?:\.\d{1,2})?$/.test(normalized)) return null;
  const [units, fraction = ''] = normalized.split('.');
  const minor = Number(units) * 100 + Number(fraction.padEnd(2, '0'));
  return Number.isSafeInteger(minor) && minor >= 0 ? minor : null;
}

/** The form for an existing entry; every amount is shown in major units. */
export function formFromEntry(entry: FinanceEntry): FormState {
  const isAsset = entry.type === 'account' || entry.type === 'deposit' || entry.type === 'stock';
  const stock = entry.type === 'stock' ? entry : null;
  const majors = (minor: number | undefined) => (minor === undefined ? '' : String(minor / 100));
  return {
    ...emptyForm(entry.currency, entry.type),
    fromAccountId: entry.type === 'transfer' ? entry.fromAccountId : '',
    toAccountId: entry.type === 'transfer' ? entry.toAccountId : '',
    amount: majors(isAsset ? entry.valueMinor : entry.amountMinor),
    date: isAsset ? entry.asOf : entry.date,
    category: entry.type === 'income' || entry.type === 'expense' ? entry.category : '',
    accountId: entry.type === 'income' || entry.type === 'expense' ? (entry.accountId ?? '') : '',
    name: entry.type === 'deposit' || entry.type === 'stock' ? entry.name : '',
    note: entry.note,
    exchange: stock?.exchange ?? 'KASE',
    ticker: stock?.ticker ?? '',
    quantity: stock?.quantity ? String(stock.quantity) : '',
    unitPrice: majors(stock?.unitPriceMinor),
    purchasePrice: majors(stock?.purchasePriceMinor),
  };
}

export type BuildResult = { input: FinanceEntryInput } | { error: string };
const isMoving = (type: Kind) => type === 'income' || type === 'expense' || type === 'transfer';

interface Parsed {
  quantity: number | null;
  unit: number | null;
  purchase: number | null;
  priced: boolean;
  minor: number | null;
}

function parseForm(form: FormState): Parsed {
  const priced = form.type === 'stock' && form.quantity.trim() !== '';
  const quantity = priced ? Number(form.quantity) : null;
  const unit = priced ? parseMinor(form.unitPrice) : null;
  const purchase =
    form.type === 'stock' && form.purchasePrice.trim() ? parseMinor(form.purchasePrice) : null;
  const minor = priced && quantity && unit !== null ? quantity * unit : parseMinor(form.amount);
  return { quantity, unit, purchase, priced, minor };
}

function stockError(
  form: FormState,
  editing: FinanceEntry | null,
  t: Translate,
  parsed: Parsed,
): string | null {
  const ticker = form.ticker.trim().toUpperCase();
  const { quantity, unit, purchase, priced } = parsed;
  if (
    (!editing && !ticker) ||
    (ticker && !quoteUrl(form.exchange, ticker)) ||
    (!editing && !priced)
  )
    return t('Укажите биржу, тикер, количество и цену одной акции.');
  if (
    priced &&
    (!Number.isSafeInteger(quantity) || !quantity || quantity > 1_000_000_000 || unit === null)
  )
    return t('Введите целое количество акций и цену с точностью до двух знаков.');
  if (!priced && form.unitPrice.trim()) return t('Для цены одной акции укажите количество.');
  const badPurchase =
    (!editing && purchase === null) ||
    (form.purchasePrice.trim() !== '' && purchase === null) ||
    (purchase !== null && (!priced || !quantity || quantity * purchase > MAX_MINOR));
  return badPurchase ? t('Введите цену покупки за одну акцию и количество бумаг.') : null;
}

function amountError(form: FormState, minor: number | null, t: Translate): string | null {
  const bad =
    minor === null ||
    !Number.isSafeInteger(minor) ||
    minor > MAX_MINOR ||
    (isMoving(form.type) && minor === 0);
  if (!bad) return null;
  return t(
    isMoving(form.type)
      ? 'Введите сумму больше нуля, максимум с двумя знаками после запятой.'
      : 'Введите стоимость от нуля, максимум с двумя знаками после запятой.',
  );
}

function stockInput(form: FormState, parsed: Parsed, minor: number): FinanceEntryInput {
  const { quantity, unit, purchase, priced } = parsed;
  const ticker = form.ticker.trim().toUpperCase();
  return {
    type: 'stock',
    valueMinor: minor,
    asOf: form.date,
    name: form.name.trim(),
    ...(ticker ? { exchange: form.exchange, ticker } : {}),
    ...(priced ? { quantity: quantity!, unitPriceMinor: unit! } : {}),
    ...(purchase !== null ? { purchasePriceMinor: purchase } : {}),
    currency: form.currency,
    note: form.note.trim(),
  };
}

function operationInput(
  form: FormState,
  minor: number,
  entries: FinanceEntry[],
): FinanceEntryInput | null {
  const common = { currency: form.currency, note: form.note.trim() };
  if (form.type === 'transfer')
    return {
      type: 'transfer',
      amountMinor: minor,
      date: form.date,
      fromAccountId: form.fromAccountId,
      toAccountId: form.toAccountId,
      ...common,
    };
  if (form.type !== 'income' && form.type !== 'expense') return null;
  const accountId = requestAccountId(form.accountId, entries, form.currency);
  return {
    type: form.type,
    amountMinor: minor,
    date: form.date,
    category: form.category.trim(),
    ...(accountId ? { accountId } : {}),
    ...common,
  };
}

/** Validates the form and builds the API input; messages are translated with `t`. */
export function buildEntryInput(
  form: FormState,
  editing: FinanceEntry | null,
  entries: FinanceEntry[],
  transferAccountIds: string[],
  t: Translate,
): BuildResult {
  const parsed = parseForm(form);
  const problem =
    amountError(form, parsed.minor, t) ??
    (form.type === 'stock' ? stockError(form, editing, t, parsed) : null);
  if (problem || parsed.minor === null) return { error: problem ?? '' };
  const minor = parsed.minor;
  const ids = [form.fromAccountId, form.toAccountId];
  if (
    form.type === 'transfer' &&
    (ids.some((id) => !id || !transferAccountIds.includes(id)) || ids[0] === ids[1])
  )
    return { error: t('Выберите два разных счёта в одной валюте.') };
  const moving = operationInput(form, minor, entries);
  if (moving) return { input: moving };
  if (form.type === 'stock') return { input: stockInput(form, parsed, minor) };
  const base = {
    valueMinor: minor,
    asOf: form.date,
    currency: form.currency,
    note: form.note.trim(),
  };
  if (form.type === 'account') return { input: { type: 'account', ...base } };
  return { input: { type: 'deposit', name: form.name.trim(), ...base } };
}
