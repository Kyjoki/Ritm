import test from 'node:test';
import assert from 'node:assert/strict';
import type { FinanceEntry } from '../shared/types.ts';
import {
  buildEntryInput,
  emptyForm,
  formFromEntry,
  parseMinor,
  quoteUrl,
} from '../src/features/finance/finance-form.ts';

const t = (source: string) => source;
const stamp = '2026-01-01T00:00:00.000Z';
const base = { createdAt: stamp, updatedAt: stamp, note: '' };
const main = {
  ...base,
  id: 'main',
  type: 'account',
  currency: 'KZT',
  valueMinor: 0,
  asOf: '2026-08-01',
} as FinanceEntry;
const dep = {
  ...base,
  id: 'dep',
  type: 'deposit',
  currency: 'KZT',
  name: 'Накопления',
  valueMinor: 0,
  asOf: '2026-08-01',
} as FinanceEntry;
const entries = [main, dep];

test('amounts parse to exact minor units and reject malformed input', () => {
  assert.equal(parseMinor('12,5'), 1250);
  assert.equal(parseMinor(' 1 000.05 '), 100005);
  assert.equal(parseMinor('1.234'), null);
  assert.equal(parseMinor('-1'), null);
  assert.equal(parseMinor(''), null);
  assert.equal(quoteUrl('KASE', 'HSBK'), 'https://kase.kz/en/investors/shares/HSBK/');
  assert.equal(quoteUrl('AIX', 'javascript:alert(1)'), null);
});

test('an expense carries accountId only for a named account', () => {
  const form = {
    ...emptyForm('KZT', 'expense'),
    amount: '15,50',
    category: ' Кафе ',
    date: '2026-10-29',
  };
  const onMain = buildEntryInput({ ...form, accountId: 'main' }, null, entries, [], t);
  assert.ok('input' in onMain);
  assert.equal('accountId' in onMain.input, false);
  const onDeposit = buildEntryInput({ ...form, accountId: 'dep' }, null, entries, [], t);
  assert.ok('input' in onDeposit && onDeposit.input.type === 'expense');
  assert.equal(onDeposit.input.type === 'expense' && onDeposit.input.accountId, 'dep');
  assert.equal(onDeposit.input.type === 'expense' && onDeposit.input.category, 'Кафе');
  assert.equal(onDeposit.input.type === 'expense' && onDeposit.input.amountMinor, 1550);
  const wrongCurrency = buildEntryInput(
    { ...form, currency: 'USD', accountId: 'dep' },
    null,
    entries,
    [],
    t,
  );
  assert.ok('input' in wrongCurrency);
  assert.equal('accountId' in wrongCurrency.input, false);
});

test('operations and transfers must have a positive amount and two different accounts', () => {
  const zero = buildEntryInput(
    { ...emptyForm('KZT', 'income'), amount: '0' },
    null,
    entries,
    [],
    t,
  );
  assert.ok('error' in zero);
  const bad = buildEntryInput(
    { ...emptyForm('KZT', 'transfer'), amount: '5', fromAccountId: 'main', toAccountId: 'main' },
    null,
    entries,
    ['main', 'dep'],
    t,
  );
  assert.ok('error' in bad && bad.error.includes('разных'));
  const good = buildEntryInput(
    { ...emptyForm('KZT', 'transfer'), amount: '5', fromAccountId: 'main', toAccountId: 'dep' },
    null,
    entries,
    ['main', 'dep'],
    t,
  );
  assert.ok('input' in good && good.input.type === 'transfer');
  const opening = buildEntryInput(
    { ...emptyForm('KZT', 'account'), amount: '0' },
    null,
    entries,
    [],
    t,
  );
  assert.ok('input' in opening);
});

test('a stock needs ticker, quantity and both prices when created', () => {
  const form = { ...emptyForm('KZT', 'stock'), name: 'Halyk', ticker: 'hsbk' };
  assert.ok('error' in buildEntryInput({ ...form, amount: '1' }, null, entries, [], t));
  const ok = buildEntryInput(
    { ...form, quantity: '10', unitPrice: '250', purchasePrice: '200' },
    null,
    entries,
    [],
    t,
  );
  assert.ok('input' in ok && ok.input.type === 'stock');
  if ('input' in ok && ok.input.type === 'stock') {
    assert.equal(ok.input.valueMinor, 250000);
    assert.equal(ok.input.ticker, 'HSBK');
    assert.equal(ok.input.purchasePriceMinor, 20000);
  }
});

test('editing keeps the stored account of an operation', () => {
  const op = {
    ...base,
    id: 'o',
    type: 'expense',
    currency: 'KZT',
    amountMinor: 1000,
    date: '2026-10-01',
    category: 'Кафе',
    accountId: 'dep',
  } as FinanceEntry;
  const form = formFromEntry(op);
  assert.equal(form.accountId, 'dep');
  assert.equal(form.amount, '10');
  const rebuilt = buildEntryInput(form, op, entries, [], t);
  assert.ok(
    'input' in rebuilt && rebuilt.input.type === 'expense' && rebuilt.input.accountId === 'dep',
  );
});
