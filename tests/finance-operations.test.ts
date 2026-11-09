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
const operation = {
  amountMinor: 2500,
  currency: 'KZT' as const,
  date: '2026-10-14',
  category: 'Food',
  note: '',
};
const expense = { ...operation, type: 'expense' as const };
const income = { ...operation, type: 'income' as const, amountMinor: 10000 };
const failure = (status: number, code: string) => (error: unknown) =>
  error instanceof AppError && error.status === status && error.code === code;

function withStore(run: (store: Store) => void) {
  const directory = mkdtempSync(join(tmpdir(), 'ritm-operations-'));
  const store = new Store(directory, false);
  try {
    run(store);
  } finally {
    store.close();
    assert.ok(resolve(directory).startsWith(resolve(tmpdir()) + sep));
    rmSync(directory, { recursive: true, force: true });
  }
}

test('operation schema accepts an optional account id and rejects malformed ones', () => {
  assert.equal(financeEntryInputSchema.safeParse(expense).success, true);
  assert.equal(
    financeEntryInputSchema.safeParse({ ...income, accountId: randomUUID() }).success,
    true,
  );
  assert.equal(financeEntryInputSchema.safeParse({ ...expense, accountId: 'main' }).success, false);
  assert.equal(
    financeEntryInputSchema.safeParse({
      type: 'deposit',
      ...opening,
      name: 'Kaspi',
      accountId: randomUUID(),
    }).success,
    false,
  );
});

test('operations move balances of the chosen account only and legacy entries stay on main', () => {
  withStore((store) => {
    const main = store.createFinanceEntry({ ...opening, type: 'account' });
    const kaspi = store.createFinanceEntry({ ...opening, type: 'deposit', name: 'Kaspi Gold' });
    const legacy = store.createFinanceEntry(expense);
    const balances = () => {
      const entries = store.financeEntries();
      return [
        calculateAccountBalance(entries, 'KZT', '2026-10-20'),
        calculateDepositBalance(entries, kaspi.id, '2026-10-20'),
      ];
    };
    assert.equal('accountId' in legacy, false);
    assert.deepEqual(balances(), [97500, 100000]);
    store.createFinanceEntry({ ...income, accountId: kaspi.id });
    const spent = store.createFinanceEntry({ ...expense, accountId: kaspi.id });
    store.createFinanceEntry({ ...expense, amountMinor: 700, accountId: main.id });
    assert.deepEqual(balances(), [96800, 107500]);
    assert.equal(spent.type === 'expense' && spent.accountId, kaspi.id);
    const entries = store.financeEntries();
    const total = (type: string) =>
      entries.reduce(
        (sum, entry) => sum + (entry.type === type && 'date' in entry ? entry.amountMinor : 0),
        0,
      );
    assert.equal(total('income') - total('expense'), 10000 - 2500 - 2500 - 700);
    assert.equal(calculateDepositBalance(entries, kaspi.id, '2026-10-13'), null);
  });
});

test('operations dated before the account opening or after today do not count', () => {
  withStore((store) => {
    const kaspi = store.createFinanceEntry({ ...opening, type: 'deposit', name: 'Halyk' });
    store.createFinanceEntry({ ...expense, accountId: kaspi.id, date: '2026-10-13' });
    store.createFinanceEntry({ ...expense, accountId: kaspi.id, date: '2026-10-25' });
    const entries = store.financeEntries();
    assert.equal(calculateDepositBalance(entries, kaspi.id, '2026-10-20'), 100000);
    assert.equal(calculateDepositBalance(entries, kaspi.id, '2026-10-25'), 97500);
  });
});

test('operation account must exist, be an account or deposit, and share the currency', () => {
  withStore((store) => {
    store.createFinanceEntry({ ...opening, type: 'account' });
    const usd = store.createFinanceEntry({
      ...opening,
      type: 'deposit',
      name: 'USD',
      currency: 'USD',
    });
    const stock = store.createFinanceEntry({ ...opening, type: 'stock', name: 'Stock' });
    for (const accountId of [randomUUID(), stock.id])
      assert.throws(
        () => store.createFinanceEntry({ ...expense, accountId }),
        failure(400, 'FINANCE_OPERATION_ACCOUNT'),
      );
    assert.throws(
      () => store.createFinanceEntry({ ...expense, accountId: usd.id }),
      (error: unknown) =>
        failure(400, 'FINANCE_OPERATION_CURRENCY')(error) &&
        /валюте/.test((error as AppError).message),
    );
    const saved = store.createFinanceEntry(expense);
    assert.throws(
      () => store.updateFinanceEntry(saved.id, { ...expense, accountId: usd.id }, saved.updatedAt),
      failure(400, 'FINANCE_OPERATION_CURRENCY'),
    );
    assert.throws(
      () =>
        store.updateFinanceEntry(
          saved.id,
          { ...expense, accountId: randomUUID() },
          saved.updatedAt,
        ),
      failure(400, 'FINANCE_OPERATION_ACCOUNT'),
    );
    assert.equal(store.financeEntries().length, 4);
  });
});

test('update moves an operation between accounts and back to main', () => {
  withStore((store) => {
    const main = store.createFinanceEntry({ ...opening, type: 'account' });
    const kaspi = store.createFinanceEntry({ ...opening, type: 'deposit', name: 'Kaspi' });
    const saved = store.createFinanceEntry(expense);
    const balances = () => {
      const entries = store.financeEntries();
      return [
        calculateAccountBalance(entries, 'KZT', '2026-10-20'),
        calculateDepositBalance(entries, kaspi.id, '2026-10-20'),
      ];
    };
    assert.deepEqual(balances(), [97500, 100000]);
    const moved = store.updateFinanceEntry(
      saved.id,
      { ...expense, accountId: kaspi.id },
      saved.updatedAt,
    );
    assert.deepEqual(balances(), [100000, 97500]);
    const same = store.updateFinanceEntry(
      saved.id,
      { ...expense, accountId: main.id },
      moved.updatedAt,
    );
    assert.deepEqual(balances(), [97500, 100000]);
    const back = store.updateFinanceEntry(saved.id, expense, same.updatedAt);
    assert.equal('accountId' in back, false);
    assert.deepEqual(balances(), [97500, 100000]);
  });
});

test('accounts referenced by operations cannot be deleted until the operations are gone', () => {
  withStore((store) => {
    const main = store.createFinanceEntry({ ...opening, type: 'account' });
    const kaspi = store.createFinanceEntry({ ...opening, type: 'deposit', name: 'Kaspi' });
    const free = store.createFinanceEntry({ ...opening, type: 'deposit', name: 'Free' });
    const onKaspi = store.createFinanceEntry({ ...income, accountId: kaspi.id });
    const onMain = store.createFinanceEntry({ ...expense, accountId: main.id });
    for (const target of [kaspi, main])
      assert.throws(
        () => store.deleteFinanceEntry(target.id, target.updatedAt),
        (error: unknown) =>
          failure(409, 'FINANCE_ACCOUNT_HAS_OPERATIONS')(error) &&
          /операци/.test((error as AppError).message),
      );
    assert.throws(
      () =>
        store.updateFinanceEntry(
          kaspi.id,
          { ...opening, type: 'deposit', name: 'Kaspi', currency: 'USD' },
          kaspi.updatedAt,
        ),
      failure(400, 'FINANCE_OPERATION_CURRENCY'),
    );
    store.deleteFinanceEntry(free.id, free.updatedAt);
    store.deleteFinanceEntry(onKaspi.id, onKaspi.updatedAt);
    store.deleteFinanceEntry(kaspi.id, kaspi.updatedAt);
    store.deleteFinanceEntry(onMain.id, onMain.updatedAt);
    store.deleteFinanceEntry(main.id, main.updatedAt);
    assert.equal(store.financeEntries().length, 0);
  });
});
