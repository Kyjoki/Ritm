import test from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve, sep } from 'node:path';
import type { AddressInfo } from 'node:net';
import { Store } from '../server/store.ts';
import { createApp } from '../server/index.ts';
import { financeEntryInputSchema } from '../server/validation.ts';
import { calculateAccountBalance } from '../shared/finance.ts';

const income = {
  type: 'income' as const,
  amountMinor: 123456,
  currency: 'KZT' as const,
  date: '2026-10-14',
  category: 'Work',
  note: 'October',
};

test('finance validation preserves exact minor units and rejects malformed or unsupported money', () => {
  const parsed = financeEntryInputSchema.parse(income);
  assert.equal(parsed.type === 'income' ? parsed.amountMinor : 0, 123456);
  for (const value of [0, 1.25, -1, Number.MAX_SAFE_INTEGER])
    assert.equal(
      financeEntryInputSchema.safeParse({ ...income, amountMinor: value }).success,
      false,
    );
  assert.equal(financeEntryInputSchema.safeParse({ ...income, currency: 'JPY' }).success, false);
  assert.equal(financeEntryInputSchema.safeParse({ ...income, date: '2026-02-30' }).success, false);
  assert.equal(financeEntryInputSchema.safeParse({ ...income, apiKey: 'leak' }).success, false);
});

test('stock holdings keep legacy valuations and reject inconsistent share totals', () => {
  const legacy = {
    type: 'stock' as const,
    name: 'Halyk',
    valueMinor: 37400,
    currency: 'KZT' as const,
    asOf: '2026-10-16',
    note: '',
  };
  assert.equal(financeEntryInputSchema.safeParse(legacy).success, true);
  const holding = {
    ...legacy,
    exchange: 'KASE',
    ticker: 'HSBK',
    quantity: 2,
    unitPriceMinor: 37400,
    purchasePriceMinor: 35000,
    valueMinor: 74800,
  };
  assert.equal(financeEntryInputSchema.safeParse(holding).success, true);
  assert.equal(financeEntryInputSchema.safeParse({ ...holding, valueMinor: 37400 }).success, false);
  assert.equal(financeEntryInputSchema.safeParse({ ...holding, quantity: 0 }).success, false);
  assert.equal(
    financeEntryInputSchema.safeParse({ ...holding, unitPriceMinor: undefined }).success,
    false,
  );
  assert.equal(
    financeEntryInputSchema.safeParse({ ...holding, quantity: undefined }).success,
    false,
  );
  assert.equal(
    financeEntryInputSchema.safeParse({ ...holding, purchasePriceMinor: 1_000_000_000_000 })
      .success,
    false,
  );
  assert.equal(
    financeEntryInputSchema.safeParse({ ...holding, ticker: 'javascript:alert(1)' }).success,
    false,
  );
});

test('main account uses opening balance and only recorded operations from its start date', () => {
  const account = {
    type: 'account' as const,
    valueMinor: 100000,
    currency: 'KZT' as const,
    asOf: '2026-10-14',
    note: '',
  };
  assert.equal(financeEntryInputSchema.safeParse(account).success, true);
  const entry = (fields: object, id: string) => ({
    id,
    createdAt: '2026-10-14T00:00:00.000Z',
    updatedAt: '2026-10-14T00:00:00.000Z',
    ...fields,
  });
  const entries = [
    entry(account, 'account'),
    entry({ ...income, date: '2026-10-13' }, 'earlier'),
    entry({ ...income, amountMinor: 25000 }, 'current-income'),
    entry(
      {
        type: 'expense',
        amountMinor: 6000,
        currency: 'KZT',
        date: '2026-10-14',
        category: 'Food',
        note: '',
      },
      'current-expense',
    ),
    entry({ ...income, date: '2026-10-19' }, 'future'),
    entry({ ...income, currency: 'USD' }, 'other-currency'),
  ] as Parameters<typeof calculateAccountBalance>[0];
  assert.equal(calculateAccountBalance(entries, 'KZT', '2026-10-18'), 119000);
  assert.equal(calculateAccountBalance(entries, 'KZT', '2026-10-13'), null);
  assert.equal(calculateAccountBalance(entries, 'USD', '2026-10-18'), null);
});

test('only one main account per currency can be stored and its currency cannot change', () => {
  const directory = mkdtempSync(join(tmpdir(), 'ritm-finance-account-'));
  try {
    const store = new Store(directory, false);
    const input = {
      type: 'account' as const,
      valueMinor: 50000,
      currency: 'KZT' as const,
      asOf: '2026-10-14',
      note: '',
    };
    const created = store.createFinanceEntry(input);
    assert.throws(
      () => store.createFinanceEntry(input),
      (error: unknown) =>
        error instanceof Error && 'code' in error && error.code === 'FINANCE_ACCOUNT_EXISTS',
    );
    assert.throws(
      () => store.updateFinanceEntry(created.id, { ...input, currency: 'USD' }, created.updatedAt),
      (error: unknown) =>
        error instanceof Error && 'code' in error && error.code === 'FINANCE_ACCOUNT_CURRENCY',
    );
    assert.equal(store.financeEntries().length, 1);
    store.close();
  } finally {
    assert.ok(resolve(directory).startsWith(resolve(tmpdir()) + sep));
    rmSync(directory, { recursive: true, force: true });
  }
});

test('SQLite finance records survive reopening and remain independent of calendar tasks', () => {
  const directory = mkdtempSync(join(tmpdir(), 'ritm-finance-'));
  try {
    const first = new Store(directory, false);
    const created = first.createFinanceEntry(income);
    assert.equal(first.tasks().length, 0);
    first.close();
    const second = new Store(directory, false);
    assert.equal(second.financeEntries()[0].id, created.id);
    assert.equal(second.financeEntries()[0].type, 'income');
    second.deleteFinanceEntry(created.id, created.updatedAt);
    assert.deepEqual(second.financeEntries(), []);
    second.close();
  } finally {
    assert.ok(resolve(directory).startsWith(resolve(tmpdir()) + sep));
    rmSync(directory, { recursive: true, force: true });
  }
});

test('finance API requires owner session and supports create, edit and delete', async (t) => {
  const directory = mkdtempSync(join(tmpdir(), 'ritm-finance-api-'));
  const instance = createApp({
    dataDir: directory,
    seed: false,
    env: { NODE_ENV: 'test', APP_PASSWORD: 'finance-test-password' },
  });
  const server = instance.app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(async () => {
    server.closeAllConnections();
    await new Promise<void>((done) => server.close(() => done()));
    await instance.close();
    assert.ok(resolve(directory).startsWith(resolve(tmpdir()) + sep));
    rmSync(directory, { recursive: true, force: true });
  });
  const root = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  const anonymous = await fetch(root + '/api/finance');
  assert.equal(anonymous.status, 401);
  const login = await fetch(root + '/api/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ login: 'maksim', password: 'finance-test-password' }),
  });
  assert.equal(login.status, 200);
  const cookie = login.headers.get('set-cookie')!.split(';')[0];
  const call = (path: string, method = 'GET', body?: unknown) =>
    fetch(root + '/api' + path, {
      method,
      headers: {
        Cookie: cookie,
        ...(method === 'GET' ? {} : { 'Content-Type': 'application/json' }),
      },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
  const created = await call('/finance', 'POST', income);
  assert.equal(created.status, 201);
  const initial = (await created.json()).entry as { id: string; updatedAt: string };
  const id = initial.id;
  assert.equal((await (await call('/finance')).json()).entries.length, 1);
  assert.equal((await call('/finance', 'POST', { ...income, amountMinor: 1.2 })).status, 400);
  const updated = await call('/finance/' + id, 'PATCH', {
    entry: { ...income, amountMinor: 250000 },
    expectedUpdatedAt: initial.updatedAt,
  });
  assert.equal(updated.status, 200);
  const revised = (await updated.json()).entry as { amountMinor: number; updatedAt: string };
  assert.equal(revised.amountMinor, 250000);
  assert.equal(
    (
      await call('/finance/' + id, 'PATCH', {
        entry: { ...income, amountMinor: 1 },
        expectedUpdatedAt: initial.updatedAt,
      })
    ).status,
    409,
  );
  assert.equal(
    (await call('/finance/' + id, 'DELETE', { expectedUpdatedAt: initial.updatedAt })).status,
    409,
  );
  assert.equal((await (await call('/finance')).json()).entries[0].amountMinor, 250000);
  assert.equal(
    (await call('/finance/' + id, 'DELETE', { expectedUpdatedAt: revised.updatedAt })).status,
    200,
  );
  assert.deepEqual((await (await call('/finance')).json()).entries, []);
  const holding = {
    type: 'stock' as const,
    name: 'Halyk',
    exchange: 'KASE' as const,
    ticker: 'HSBK',
    quantity: 2,
    unitPriceMinor: 37400,
    purchasePriceMinor: 35000,
    valueMinor: 74800,
    currency: 'KZT' as const,
    asOf: '2026-10-16',
    note: '',
  };
  const stockCreated = await call('/finance', 'POST', holding);
  assert.equal(stockCreated.status, 201);
  const stock = (await stockCreated.json()).entry as { id: string; updatedAt: string };
  assert.equal(
    (
      await call('/finance/' + stock.id, 'PATCH', {
        entry: { ...holding, unitPriceMinor: 40000, valueMinor: 74800 },
        expectedUpdatedAt: stock.updatedAt,
      })
    ).status,
    400,
  );
  const repriced = await call('/finance/' + stock.id, 'PATCH', {
    entry: { ...holding, unitPriceMinor: 40000, valueMinor: 80000, asOf: '2026-10-18' },
    expectedUpdatedAt: stock.updatedAt,
  });
  assert.equal(repriced.status, 200);
  const persisted = (await (await call('/finance')).json()).entries[0];
  assert.equal(persisted.purchasePriceMinor, 35000);
  assert.equal(persisted.valueMinor, 80000);
  const opening = { valueMinor: 100000, currency: 'KZT', asOf: '2026-10-14', note: '' };
  const accountResponse = await call('/finance', 'POST', { ...opening, type: 'account' });
  const account = (await accountResponse.json()).entry;
  const depositResponse = await call('/finance', 'POST', {
    ...opening,
    type: 'deposit',
    name: 'Savings',
  });
  const deposit = (await depositResponse.json()).entry;
  const transferInput = {
    type: 'transfer',
    amountMinor: 10000,
    currency: 'KZT',
    date: '2026-10-14',
    fromAccountId: account.id,
    toAccountId: deposit.id,
    note: '',
  };
  const transferResponse = await call('/finance', 'POST', transferInput);
  assert.equal(transferResponse.status, 201);
  const transfer = (await transferResponse.json()).entry;
  assert.equal(
    (await call('/finance/' + deposit.id, 'DELETE', { expectedUpdatedAt: deposit.updatedAt }))
      .status,
    409,
  );
  const reversed = await call('/finance/' + transfer.id, 'PATCH', {
    entry: { ...transferInput, fromAccountId: deposit.id, toAccountId: account.id },
    expectedUpdatedAt: transfer.updatedAt,
  });
  assert.equal(reversed.status, 200);
  const reversal = (await reversed.json()).entry;
  const ledger = (await (await call('/finance')).json()).entries;
  assert.equal(calculateAccountBalance(ledger, 'KZT', '2026-10-14'), 110000);
  assert.equal(
    (await call('/finance/' + transfer.id, 'DELETE', { expectedUpdatedAt: reversal.updatedAt }))
      .status,
    200,
  );
  assert.equal(
    calculateAccountBalance((await (await call('/finance')).json()).entries, 'KZT', '2026-10-14'),
    100000,
  );
});
