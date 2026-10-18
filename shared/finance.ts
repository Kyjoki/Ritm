import type { FinanceCurrency, FinanceEntry } from './types.ts';

/** Opening balance is the amount before transactions on its asOf date. */
export function calculateAccountBalance(
  entries: FinanceEntry[],
  currency: FinanceCurrency,
  today: string,
): number | null {
  const account = entries.find(
    (entry): entry is Extract<FinanceEntry, { type: 'account' }> =>
      entry.type === 'account' && entry.currency === currency,
  );
  if (!account || account.asOf > today) return null;
  return entries.reduce((balance, entry) => {
    if (entry.currency !== currency || entry.type === 'account') return balance;
    if (entry.type !== 'income' && entry.type !== 'expense') return balance;
    if (entry.date < account.asOf || entry.date > today) return balance;
    return balance + (entry.type === 'income' ? entry.amountMinor : -entry.amountMinor);
  }, account.valueMinor);
}
