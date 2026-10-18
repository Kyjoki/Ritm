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
});
