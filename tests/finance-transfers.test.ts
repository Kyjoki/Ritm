import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve, sep } from 'node:path';
import { Store } from '../server/store.ts';
import { AppError } from '../server/errors.ts';
import { financeEntryInputSchema } from '../server/validation.ts';
import { calculateAccountBalance, calculateDepositBalance } from '../shared/finance.ts';

const opening = { valueMinor: 100000, currency: 'KZT' as const, asOf: '2026-10-14', note: '' };
const errorCode = (code: string) => (error: unknown) =>
  error instanceof AppError && error.code === code;

test('transfer schema validates exact positive money, identifiers and dates', () => {
  const transfer = {
    type: 'transfer',
    amountMinor: 12345,
    currency: 'KZT',
    date: '2026-10-14',
    fromAccountId: randomUUID(),
    toAccountId: randomUUID(),
    note: '',
  };
  assert.equal(financeEntryInputSchema.safeParse(transfer).success, true);
  for (const amountMinor of [0, -1, 1.1, Number.MAX_SAFE_INTEGER])
    assert.equal(financeEntryInputSchema.safeParse({ ...transfer, amountMinor }).success, false);
  for (const patch of [
    { date: '2026-02-30' },
    { fromAccountId: 'invalid' },
    { currency: 'JPY' },
    { amountReceived: 100 },
  ])
    assert.equal(financeEntryInputSchema.safeParse({ ...transfer, ...patch }).success, false);
});

test('deposit transfers persist, conserve totals and reverse on edit/delete without becoming income or expense', () => {
  const directory = mkdtempSync(join(tmpdir(), 'ritm-transfers-'));
  let store: Store | undefined;
  try {
    store = new Store(directory, false);
    const account = store.createFinanceEntry({ ...opening, type: 'account' });
    const first = store.createFinanceEntry({
      ...opening,
      type: 'deposit',
      name: 'First',
      valueMinor: 50000,
    });
    const second = store.createFinanceEntry({
      ...opening,
      type: 'deposit',
      name: 'Second',
      valueMinor: 10000,
    });
    const input = {
      type: 'transfer' as const,
      amountMinor: 12345,
      currency: 'KZT' as const,
      date: opening.asOf,
      fromAccountId: account.id,
      toAccountId: first.id,
      note: 'Top up',
    };
    const transfer = store.createFinanceEntry(input);
    const check = (main: number, a: number, b: number, day = opening.asOf) => {
      const entries = store!.financeEntries();
      assert.equal(calculateAccountBalance(entries, 'KZT', day), main);
      assert.equal(calculateDepositBalance(entries, first.id, day), a);
      assert.equal(calculateDepositBalance(entries, second.id, day), b);
      assert.equal(main + a + b, 160000);
      assert.equal(
        entries.filter((entry) => entry.type === 'income' || entry.type === 'expense').length,
        0,
      );
    };
    check(87655, 62345, 10000);
    assert.equal(calculateAccountBalance(store.financeEntries(), 'KZT', '2026-10-13'), null);
    assert.equal(calculateDepositBalance(store.financeEntries(), first.id, '2026-10-13'), null);
    assert.equal(calculateDepositBalance(store.financeEntries(), randomUUID(), opening.asOf), null);
    const between = store.createFinanceEntry({
      ...input,
      amountMinor: 345,
      fromAccountId: first.id,
      toAccountId: second.id,
    });
    check(87655, 62000, 10345);
    const withdrawn = store.createFinanceEntry({
      ...input,
      amountMinor: 2000,
      fromAccountId: first.id,
      toAccountId: account.id,
    });
    check(89655, 60000, 10345);
    const future = store.createFinanceEntry({ ...input, date: '2026-10-20', amountMinor: 1000 });
    check(89655, 60000, 10345);
    check(88655, 61000, 10345, '2026-10-20');
    store.close();
    store = new Store(directory, false);
    check(89655, 60000, 10345);
    const edited = store.updateFinanceEntry(
      transfer.id,
      { ...input, amountMinor: 10000 },
      transfer.updatedAt,
    );
    check(92000, 57655, 10345);
    assert.throws(
      () => store!.updateFinanceEntry(transfer.id, input, transfer.updatedAt),
      (error: unknown) => error instanceof AppError && error.status === 409,
    );
    assert.throws(
      () => store!.deleteFinanceEntry(transfer.id, transfer.updatedAt),
      (error: unknown) => error instanceof AppError && error.status === 409,
    );
    for (const entry of [edited, between, withdrawn, future])
      store.deleteFinanceEntry(entry.id, entry.updatedAt);
    check(100000, 50000, 10000);
    store.deleteFinanceEntry(first.id, first.updatedAt);
    assert.equal(calculateDepositBalance(store.financeEntries(), first.id, opening.asOf), null);
  } finally {
    store?.close();
    assert.ok(resolve(directory).startsWith(resolve(tmpdir()) + sep));
    rmSync(directory, { recursive: true, force: true });
  }
});

test('transfers reject missing/cross-currency/same/stock accounts and protect linked history', () => {
  const directory = mkdtempSync(join(tmpdir(), 'ritm-transfer-guards-'));
  const store = new Store(directory, false);
  try {
    const account = store.createFinanceEntry({ ...opening, type: 'account' });
    const deposit = store.createFinanceEntry({ ...opening, type: 'deposit', name: 'Savings' });
    const foreign = store.createFinanceEntry({
      ...opening,
      type: 'deposit',
      name: 'USD',
      currency: 'USD',
    });
    const stock = store.createFinanceEntry({ ...opening, type: 'stock', name: 'Stock' });
    const input = {
      type: 'transfer' as const,
      amountMinor: 100,
      currency: 'KZT' as const,
      date: opening.asOf,
      fromAccountId: account.id,
      toAccountId: deposit.id,
      note: '',
    };
    for (const [patch, code] of [
      [{ fromAccountId: randomUUID() }, 'FINANCE_TRANSFER_ACCOUNT'],
      [{ toAccountId: stock.id }, 'FINANCE_TRANSFER_ACCOUNT'],
      [{ toAccountId: account.id }, 'FINANCE_TRANSFER_SAME_ACCOUNT'],
      [{ toAccountId: foreign.id }, 'FINANCE_TRANSFER_CURRENCY'],
      [{ currency: 'USD' }, 'FINANCE_TRANSFER_CURRENCY'],
      [{ date: '2026-10-13' }, 'FINANCE_TRANSFER_DATE'],
    ] as const)
      assert.throws(() => store.createFinanceEntry({ ...input, ...patch }), errorCode(code));
    assert.equal(store.financeEntries().length, 4);
    const transfer = store.createFinanceEntry(input);
    assert.throws(
      () => store.deleteFinanceEntry(account.id, account.updatedAt),
      errorCode('FINANCE_ACCOUNT_HAS_TRANSFERS'),
    );
    assert.throws(
      () => store.deleteFinanceEntry(deposit.id, deposit.updatedAt),
      errorCode('FINANCE_ACCOUNT_HAS_TRANSFERS'),
    );
    assert.throws(
      () =>
        store.updateFinanceEntry(
          deposit.id,
          { ...opening, type: 'deposit', name: 'Savings', currency: 'USD' },
          deposit.updatedAt,
        ),
      errorCode('FINANCE_TRANSFER_CURRENCY'),
    );
    assert.throws(
      () =>
        store.updateFinanceEntry(
          deposit.id,
          { ...opening, type: 'deposit', name: 'Savings', asOf: '2026-10-15' },
          deposit.updatedAt,
        ),
      errorCode('FINANCE_TRANSFER_DATE'),
    );
    assert.throws(
      () =>
        store.updateFinanceEntry(
          account.id,
          { ...opening, type: 'account', asOf: '2026-10-15' },
          account.updatedAt,
        ),
      errorCode('FINANCE_TRANSFER_DATE'),
    );
    assert.throws(
      () =>
        store.updateFinanceEntry(
          transfer.id,
          { ...input, toAccountId: foreign.id },
          transfer.updatedAt,
        ),
      errorCode('FINANCE_TRANSFER_CURRENCY'),
    );
    assert.equal(store.financeEntries().length, 5);
    assert.equal(calculateDepositBalance(store.financeEntries(), deposit.id, opening.asOf), 100100);
    const renamed = store.updateFinanceEntry(
      deposit.id,
      { ...opening, type: 'deposit', name: 'Renamed' },
      deposit.updatedAt,
    );
    assert.equal(renamed.type === 'deposit' && renamed.name, 'Renamed');
    assert.equal(calculateDepositBalance(store.financeEntries(), deposit.id, opening.asOf), 100100);
  } finally {
    store.close();
    assert.ok(resolve(directory).startsWith(resolve(tmpdir()) + sep));
    rmSync(directory, { recursive: true, force: true });
  }
});
