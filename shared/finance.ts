import type { FinanceCurrency, FinanceEntry } from './types.ts';

/** One transfer is one durable entry: its two sides always share amount/date. */
function transferDelta(entry: FinanceEntry, accountId: string): number {
  if (entry.type !== 'transfer') return 0;
  return (
    (entry.toAccountId === accountId ? entry.amountMinor : 0) -
    (entry.fromAccountId === accountId ? entry.amountMinor : 0)
  );
}

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
    if (entry.currency !== currency || !('date' in entry)) return balance;
    if (entry.date < account.asOf || entry.date > today) return balance;
    if (entry.type === 'transfer') return balance + transferDelta(entry, account.id);
    return balance + (entry.type === 'income' ? entry.amountMinor : -entry.amountMinor);
  }, account.valueMinor);
}

/** Existing deposit valuations remain the opening snapshot; transfers do not overwrite it. */
export function calculateDepositBalance(
  entries: FinanceEntry[],
  depositId: string,
  today: string,
): number | null {
  const deposit = entries.find(
    (entry): entry is Extract<FinanceEntry, { type: 'deposit' }> =>
      entry.type === 'deposit' && entry.id === depositId,
  );
  if (!deposit || deposit.asOf > today) return null;
  return entries.reduce((balance, entry) => {
    if (
      entry.type !== 'transfer' ||
      entry.currency !== deposit.currency ||
      entry.date < deposit.asOf ||
      entry.date > today
    )
      return balance;
    return balance + transferDelta(entry, deposit.id);
  }, deposit.valueMinor);
}
