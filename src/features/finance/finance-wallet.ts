import type { FinanceCurrency, FinanceEntry } from '../../../shared/types';
import { calculateAccountBalance, calculateDepositBalance } from '../../../shared/finance';
import { addDays, addMonths } from '../calendar-utils';

/** Pure read model over the raw finance entries (mirrors FinanceWallet.swift on the iPhone). */
export type FinancePeriod = 'week' | 'month' | 'year';
export type CardKind = 'account' | 'deposit' | 'stocks';
export type Operation = Extract<FinanceEntry, { type: 'income' | 'expense' }>;
export type Transfer = Extract<FinanceEntry, { type: 'transfer' }>;
export type StockEntry = Extract<FinanceEntry, { type: 'stock' }>;

export interface FinanceCard {
  /** Account and deposit: the entry id. Stocks: `stocks-<CUR>`. */
  id: string;
  kind: CardKind;
  currency: FinanceCurrency;
  name: string | null;
  /** null when the card has not started yet (asOf after today) or has no snapshot. */
  balanceMinor: number | null;
  asOf: string | null;
}
export interface PeriodStats {
  incomeMinor: number;
  expenseMinor: number;
  transfersInMinor: number;
  transfersOutMinor: number;
}
export interface SeriesPoint {
  date: string;
  valueMinor: number;
}
export interface CategoryShare {
  /** null is the «Другое» bucket. */
  name: string | null;
  amountMinor: number;
  share: number;
}
export interface CardShare {
  cardId: string;
  amountMinor: number;
  share: number;
}

export const CURRENCY_ORDER: FinanceCurrency[] = ['KZT', 'USD', 'EUR', 'RUB'];
export const ZERO_STATS: PeriodStats = {
  incomeMinor: 0,
  expenseMinor: 0,
  transfersInMinor: 0,
  transfersOutMinor: 0,
};

const isOperation = (entry: FinanceEntry): entry is Operation | Transfer =>
  entry.type === 'income' || entry.type === 'expense' || entry.type === 'transfer';
const isIncomeOrExpense = (entry: FinanceEntry): entry is Operation =>
  entry.type === 'income' || entry.type === 'expense';
const sum = (values: number[]) => values.reduce((total, value) => total + value, 0);

/** The date an entry is shown under: operations carry `date`, assets their snapshot date. */
export function entryDay(entry: FinanceEntry): string {
  return 'date' in entry ? entry.date : 'asOf' in entry ? entry.asOf : '';
}

function stocksValue(stocks: StockEntry[], day: string): number | null {
  const started = stocks.filter((entry) => entry.asOf <= day);
  return started.length ? sum(started.map((entry) => entry.valueMinor)) : null;
}

function currencyCards(
  entries: FinanceEntry[],
  currency: FinanceCurrency,
  today: string,
): FinanceCard[] {
  const own = entries.filter((entry) => entry.currency === currency);
  const cards: FinanceCard[] = [];
  const account = own.find((entry) => entry.type === 'account');
  if (account && account.type === 'account')
    cards.push({
      id: account.id,
      kind: 'account',
      currency,
      name: null,
      balanceMinor: calculateAccountBalance(own, currency, today),
      asOf: account.asOf,
    });
  const deposits = own
    .filter((entry) => entry.type === 'deposit')
    .sort((a, b) => a.createdAt.localeCompare(b.createdAt));
  for (const deposit of deposits)
    if (deposit.type === 'deposit')
      cards.push({
        id: deposit.id,
        kind: 'deposit',
        currency,
        name: deposit.name,
        balanceMinor: calculateDepositBalance(own, deposit.id, today),
        asOf: deposit.asOf,
      });
  const stocks = own.filter((entry): entry is StockEntry => entry.type === 'stock');
  if (stocks.length)
    cards.push({
      id: `stocks-${currency}`,
      kind: 'stocks',
      currency,
      name: null,
      balanceMinor: stocksValue(stocks, today),
      asOf: stocks.map((entry) => entry.asOf).sort()[0] ?? null,
    });
  return cards;
}

/** Per currency: the main account, its deposits by creation time, then the stocks card. */
export function buildCards(entries: FinanceEntry[], today: string): FinanceCard[] {
  return CURRENCY_ORDER.flatMap((currency) => currencyCards(entries, currency, today));
}

/** Per currency, the sum of the known card balances; only currencies that have cards. */
export function cardTotals(
  cards: FinanceCard[],
): { currency: FinanceCurrency; amountMinor: number }[] {
  return CURRENCY_ORDER.flatMap((currency) => {
    const own = cards.filter((card) => card.currency === currency);
    return own.length
      ? [{ currency, amountMinor: sum(own.map((card) => card.balanceMinor ?? 0)) }]
      : [];
  });
}

/** Calendar period to date: Monday…today, the 1st…today or January 1…today. */
export function periodInterval(period: FinancePeriod, today: string) {
  if (period === 'year') return { start: `${today.slice(0, 4)}-01-01`, end: today };
  if (period === 'month') return { start: `${today.slice(0, 7)}-01`, end: today };
  const weekday = new Date(`${today}T12:00:00Z`).getUTCDay();
  return { start: addDays(today, -((weekday + 6) % 7)), end: today };
}

/** An income or expense counts on the main account when it names no account (or its own id). */
export function operationBelongsTo(entry: FinanceEntry, card: FinanceCard): boolean {
  if (!isIncomeOrExpense(entry) || entry.currency !== card.currency) return false;
  if (card.kind === 'account') return entry.accountId === undefined || entry.accountId === card.id;
  return card.kind === 'deposit' && entry.accountId === card.id;
}

const inRange = (entry: FinanceEntry, start: string, end: string) => {
  const day = 'date' in entry ? entry.date : '';
  return day !== '' && day >= start && day <= end;
};

/** Income, expense and transfers of one card from its snapshot date on. Stocks: zero. */
export function cardStats(
  entries: FinanceEntry[],
  card: FinanceCard,
  period: FinancePeriod,
  today: string,
): PeriodStats {
  if (card.kind === 'stocks' || !card.asOf) return ZERO_STATS;
  const range = periodInterval(period, today);
  const start = range.start > card.asOf ? range.start : card.asOf;
  let incomeMinor = 0;
  let expenseMinor = 0;
  let transfersInMinor = 0;
  let transfersOutMinor = 0;
  for (const entry of entries) {
    if (entry.currency !== card.currency || !inRange(entry, start, range.end)) continue;
    if (entry.type === 'income' && operationBelongsTo(entry, card))
      incomeMinor += entry.amountMinor;
    else if (entry.type === 'expense' && operationBelongsTo(entry, card))
      expenseMinor += entry.amountMinor;
    else if (entry.type === 'transfer') {
      if (entry.toAccountId === card.id) transfersInMinor += entry.amountMinor;
      if (entry.fromAccountId === card.id) transfersOutMinor += entry.amountMinor;
    }
  }
  return { incomeMinor, expenseMinor, transfersInMinor, transfersOutMinor };
}

/** Income and expense of one currency from the main account's start date; transfers left out. */
export function overviewStats(
  entries: FinanceEntry[],
  currency: FinanceCurrency,
  period: FinancePeriod,
  today: string,
): PeriodStats {
  const account = entries.find((entry) => entry.type === 'account' && entry.currency === currency);
  if (!account || account.type !== 'account' || account.asOf > today) return ZERO_STATS;
  const range = periodInterval(period, today);
  const start = range.start > account.asOf ? range.start : account.asOf;
  let incomeMinor = 0;
  let expenseMinor = 0;
  for (const entry of entries) {
    if (entry.currency !== currency || !inRange(entry, start, range.end)) continue;
    if (entry.type === 'income') incomeMinor += entry.amountMinor;
    if (entry.type === 'expense') expenseMinor += entry.amountMinor;
  }
  return { ...ZERO_STATS, incomeMinor, expenseMinor };
}

function monthEnds(start: string, today: string): string[] {
  const ends: string[] = [];
  for (let first = start; first <= today; first = addMonths(first, 1)) {
    const end = addDays(addMonths(first, 1), -1);
    ends.push(end < today ? end : today);
  }
  return ends;
}

function dayList(start: string, end: string): string[] {
  const days: string[] = [];
  for (let day = start; day <= end; day = addDays(day, 1)) days.push(day);
  return days;
}

/** The day before the interval, then its points, without anything before `asOf`. */
export function seriesDates(period: FinancePeriod, today: string, asOf: string): string[] {
  const { start } = periodInterval(period, today);
  const before = addDays(start, -1);
  const points = period === 'year' ? monthEnds(start, today) : dayList(start, today);
  const kept = [before, ...points].filter((day) => day >= asOf);
  return asOf > before && kept[0] !== asOf ? [asOf, ...kept] : kept;
}

function balanceOn(card: FinanceCard, entries: FinanceEntry[], day: string): number {
  if (card.kind === 'account') return calculateAccountBalance(entries, card.currency, day) ?? 0;
  if (card.kind === 'deposit') return calculateDepositBalance(entries, card.id, day) ?? 0;
  const stocks = entries.filter(
    (entry): entry is StockEntry => entry.type === 'stock' && entry.currency === card.currency,
  );
  return stocksValue(stocks, day) ?? 0;
}

/** End-of-day balances of one card; empty for a card that has not started. */
export function balanceSeries(
  entries: FinanceEntry[],
  card: FinanceCard,
  period: FinancePeriod,
  today: string,
): SeriesPoint[] {
  if (card.balanceMinor === null || !card.asOf || card.asOf > today) return [];
  return seriesDates(period, today, card.asOf).map((date) => ({
    date,
    valueMinor: balanceOn(card, entries, date),
  }));
}

/** The same series summed over every started card of one currency. */
export function overviewSeries(
  entries: FinanceEntry[],
  cards: FinanceCard[],
  currency: FinanceCurrency,
  period: FinancePeriod,
  today: string,
): SeriesPoint[] {
  const own = cards.filter((card) => card.currency === currency && card.balanceMinor !== null);
  const firstDay = own.map((card) => card.asOf ?? today).sort()[0];
  if (!firstDay) return [];
  return seriesDates(period, today, firstDay).map((date) => ({
    date,
    valueMinor: sum(own.map((card) => balanceOn(card, entries, date))),
  }));
}

function foldShares(
  expenses: Operation[],
  start: string,
  end: string,
  limit: number,
): CategoryShare[] {
  const totals = new Map<string, number>();
  let uncategorized = 0;
  for (const entry of expenses) {
    if (!inRange(entry, start, end) || entry.amountMinor <= 0) continue;
    const name = entry.category.trim();
    if (name) totals.set(name, (totals.get(name) ?? 0) + entry.amountMinor);
    else uncategorized += entry.amountMinor;
  }
  const named = [...totals].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]));
  const total = uncategorized + sum(named.map(([, value]) => value));
  if (total <= 0) return [];
  const row = (name: string | null, amountMinor: number): CategoryShare => ({
    name,
    amountMinor,
    share: amountMinor / total,
  });
  const keep = Math.max(limit, 1);
  const folds = named.length + (uncategorized > 0 ? 1 : 0) > keep;
  const shown = folds ? named.slice(0, keep - 1) : named;
  const rest = (folds ? sum(named.slice(keep - 1).map(([, value]) => value)) : 0) + uncategorized;
  return [
    ...shown.map(([name, value]) => row(name, value)),
    ...(rest > 0 ? [row(null, rest)] : []),
  ];
}

/** Expenses of an account or deposit by trimmed category, largest first; the tail folds into «Другое». */
export function categoryShares(
  entries: FinanceEntry[],
  card: FinanceCard,
  period: FinancePeriod,
  today: string,
  limit = 5,
): CategoryShare[] {
  if (card.kind === 'stocks' || !card.asOf) return [];
  const range = periodInterval(period, today);
  const start = range.start > card.asOf ? range.start : card.asOf;
  const expenses = entries.filter(
    (entry): entry is Operation => entry.type === 'expense' && operationBelongsTo(entry, card),
  );
  return foldShares(expenses, start, range.end, limit);
}

/** Expenses of every account of one currency, from the main account's start date. */
export function overviewCategoryShares(
  entries: FinanceEntry[],
  currency: FinanceCurrency,
  period: FinancePeriod,
  today: string,
  limit = 5,
): CategoryShare[] {
  const account = entries.find((entry) => entry.type === 'account' && entry.currency === currency);
  if (!account || account.type !== 'account' || account.asOf > today) return [];
  const range = periodInterval(period, today);
  const start = range.start > account.asOf ? range.start : account.asOf;
  const expenses = entries.filter(
    (entry): entry is Operation => entry.type === 'expense' && entry.currency === currency,
  );
  return foldShares(expenses, start, range.end, limit);
}

/** Cards of one currency with a positive balance and their share of those balances. */
export function distribution(cards: FinanceCard[], currency: FinanceCurrency): CardShare[] {
  const positive = cards.filter(
    (card) => card.currency === currency && (card.balanceMinor ?? 0) > 0,
  );
  const total = sum(positive.map((card) => card.balanceMinor ?? 0));
  if (total <= 0) return [];
  return positive.map((card) => ({
    cardId: card.id,
    amountMinor: card.balanceMinor ?? 0,
    share: (card.balanceMinor ?? 0) / total,
  }));
}

/** Newest date first, then newest creation time. */
export function newestFirst<T extends FinanceEntry>(entries: T[]): T[] {
  return [...entries].sort(
    (a, b) => entryDay(b).localeCompare(entryDay(a)) || b.createdAt.localeCompare(a.createdAt),
  );
}

/** Every operation that touches the card, whatever its date. */
export function cardHistory(entries: FinanceEntry[], card: FinanceCard): FinanceEntry[] {
  return newestFirst(
    entries.filter((entry) => {
      if (entry.currency !== card.currency) return false;
      if (entry.type === 'transfer')
        return (
          card.kind !== 'stocks' &&
          (entry.fromAccountId === card.id || entry.toAccountId === card.id)
        );
      if (isIncomeOrExpense(entry)) return operationBelongsTo(entry, card);
      return entry.type === 'stock' && card.kind === 'stocks';
    }),
  );
}

/** The newest income, expense and transfer entries across all cards. */
export function recentOperations(entries: FinanceEntry[], limit: number): FinanceEntry[] {
  return limit > 0 ? newestFirst(entries.filter(isOperation)).slice(0, limit) : [];
}

export interface StockPosition {
  entry: StockEntry;
  valueMinor: number;
  /** quantity × (unit price − purchase price) when all three are known. */
  gainMinor: number | null;
}

/** Stock entries of one currency, largest value first. */
export function stockPositions(
  entries: FinanceEntry[],
  currency: FinanceCurrency,
): StockPosition[] {
  return entries
    .filter((entry): entry is StockEntry => entry.type === 'stock' && entry.currency === currency)
    .sort((a, b) => b.valueMinor - a.valueMinor)
    .map((entry) => ({
      entry,
      valueMinor: entry.valueMinor,
      gainMinor:
        entry.quantity !== undefined &&
        entry.unitPriceMinor !== undefined &&
        entry.purchasePriceMinor !== undefined
          ? entry.quantity * (entry.unitPriceMinor - entry.purchasePriceMinor)
          : null,
    }));
}

/** Accounts the operation form can book into: the main account first, then deposits by creation. */
export function operationAccounts(entries: FinanceEntry[], currency: FinanceCurrency) {
  const own = entries.filter((entry) => entry.currency === currency);
  const main = own.find((entry) => entry.type === 'account');
  const named = own
    .filter((entry) => entry.type === 'deposit')
    .sort((a, b) => a.createdAt.localeCompare(b.createdAt));
  return [
    ...(main ? [{ id: main.id, name: null as string | null, isMain: true }] : []),
    ...named.map((entry) => ({
      id: entry.id,
      name: entry.type === 'deposit' ? entry.name.trim() || entry.id : entry.id,
      isMain: false,
    })),
  ];
}

/** The account id to send: undefined for the main account so older data keeps its shape. */
export function requestAccountId(
  selected: string,
  entries: FinanceEntry[],
  currency: FinanceCurrency,
): string | undefined {
  const options = operationAccounts(entries, currency);
  const target = options.find((option) => option.id === selected);
  return target && !target.isMain ? target.id : undefined;
}
