import test from 'node:test';
import assert from 'node:assert/strict';
import type { FinanceEntry } from '../shared/types.ts';
import {
  balanceSeries,
  buildCards,
  cardHistory,
  cardStats,
  cardTotals,
  categoryShares,
  distribution,
  operationAccounts,
  overviewSeries,
  overviewStats,
  periodInterval,
  requestAccountId,
  seriesDates,
  stockPositions,
} from '../src/features/finance/finance-wallet.ts';
import { cardTones, stackSlot } from '../src/features/finance/finance-stack.ts';

const TODAY = '2026-10-29';
let counter = 0;
function make(fields: Record<string, unknown>): FinanceEntry {
  counter += 1;
  const stamp = `2026-01-01T00:00:${String(counter).padStart(2, '0')}.000Z`;
  return {
    id: `e${counter}`,
    createdAt: stamp,
    updatedAt: stamp,
    note: '',
    ...fields,
  } as FinanceEntry;
}
const account = make({
  id: 'main',
  type: 'account',
  currency: 'KZT',
  valueMinor: 100000,
  asOf: '2026-08-01',
});
const deposit = make({
  id: 'dep',
  type: 'deposit',
  currency: 'KZT',
  name: 'Накопления',
  valueMinor: 50000,
  asOf: '2026-08-01',
});
const usd = make({
  id: 'usd',
  type: 'account',
  currency: 'USD',
  valueMinor: 7000,
  asOf: '2026-08-01',
});
const stock = make({
  id: 'st',
  type: 'stock',
  currency: 'KZT',
  name: 'HSBK',
  valueMinor: 30000,
  asOf: '2026-09-01',
  quantity: 100,
  unitPriceMinor: 300,
  purchasePriceMinor: 250,
});
const salary = make({
  type: 'income',
  currency: 'KZT',
  amountMinor: 20000,
  date: '2026-10-05',
  category: 'Зарплата',
});
const food = make({
  type: 'expense',
  currency: 'KZT',
  amountMinor: 4000,
  date: '2026-10-27',
  category: 'Продукты',
});
const foodOld = make({
  type: 'expense',
  currency: 'KZT',
  amountMinor: 1000,
  date: '2026-09-12',
  category: 'Кафе',
});
const depositSpend = make({
  type: 'expense',
  currency: 'KZT',
  amountMinor: 500,
  date: '2026-10-28',
  category: 'Комиссия',
  accountId: 'dep',
});
const move = make({
  type: 'transfer',
  currency: 'KZT',
  amountMinor: 10000,
  date: '2026-10-06',
  fromAccountId: 'main',
  toAccountId: 'dep',
});
const entries = [account, deposit, usd, stock, salary, food, foodOld, depositSpend, move];

test('cards are ordered per currency: account, deposits, stocks, and totals stay per currency', () => {
  const cards = buildCards(entries, TODAY);
  assert.deepEqual(
    cards.map((card) => card.id),
    ['main', 'dep', 'stocks-KZT', 'usd'],
  );
  const main = cards[0];
  assert.equal(main.balanceMinor, 100000 + 20000 - 4000 - 1000 - 10000);
  assert.equal(cards[1].balanceMinor, 50000 + 10000 - 500);
  assert.equal(cards[2].balanceMinor, 30000);
  const totals = cardTotals(cards);
  assert.deepEqual(
    totals.map((total) => total.currency),
    ['KZT', 'USD'],
  );
  assert.equal(totals[1].amountMinor, 7000);
});

test('period intervals run Monday to today, the 1st to today and January 1 to today', () => {
  assert.deepEqual(periodInterval('week', TODAY), { start: '2026-10-26', end: TODAY });
  assert.deepEqual(periodInterval('week', '2026-11-01'), {
    start: '2026-10-26',
    end: '2026-11-01',
  });
  assert.deepEqual(periodInterval('month', TODAY), { start: '2026-10-01', end: TODAY });
  assert.deepEqual(periodInterval('year', TODAY), { start: '2026-01-01', end: TODAY });
});

test('card stats count only the operations that belong to the card, plus its transfers', () => {
  const cards = buildCards(entries, TODAY);
  const main = cardStats(entries, cards[0], 'month', TODAY);
  assert.equal(main.incomeMinor, 20000);
  assert.equal(main.expenseMinor, 4000);
  assert.equal(main.transfersOutMinor, 10000);
  const dep = cardStats(entries, cards[1], 'month', TODAY);
  assert.equal(dep.expenseMinor, 500);
  assert.equal(dep.transfersInMinor, 10000);
  assert.deepEqual(cardStats(entries, cards[2], 'month', TODAY).incomeMinor, 0);
  const overview = overviewStats(entries, 'KZT', 'year', TODAY);
  assert.equal(overview.expenseMinor, 5500);
  assert.equal(overview.transfersInMinor, 0);
  assert.equal(overviewStats(entries, 'EUR', 'month', TODAY).incomeMinor, 0);
});

test('series start on the snapshot date and the year uses month ends', () => {
  assert.deepEqual(seriesDates('week', TODAY, '2026-08-01').slice(0, 2), [
    '2026-10-25',
    '2026-10-26',
  ]);
  assert.equal(seriesDates('week', TODAY, '2026-08-01').at(-1), TODAY);
  const late = seriesDates('month', TODAY, '2026-10-10');
  assert.equal(late[0], '2026-10-10');
  const year = seriesDates('year', TODAY, '2026-08-01');
  assert.deepEqual(year, ['2026-08-01', '2026-08-31', '2026-09-30', TODAY]);
  const cards = buildCards(entries, TODAY);
  const series = balanceSeries(entries, cards[0], 'month', TODAY);
  assert.equal(series.at(-1)?.valueMinor, cards[0].balanceMinor);
  const all = overviewSeries(entries, cards, 'KZT', 'month', TODAY);
  assert.equal(all.at(-1)?.valueMinor, 105000 + 59500 + 30000);
  assert.deepEqual(balanceSeries(entries, { ...cards[0], balanceMinor: null }, 'month', TODAY), []);
});

test('categories fold the tail into one «Другое» row and shares add up to one', () => {
  const cards = buildCards(entries, TODAY);
  const many = ['A', 'B', 'C', 'D', 'E', 'F', 'G'].map((category, index) =>
    make({
      type: 'expense',
      currency: 'KZT',
      amountMinor: 1000 * (index + 1),
      date: '2026-10-10',
      category,
    }),
  );
  const shares = categoryShares([...entries, ...many], cards[0], 'month', TODAY);
  assert.equal(shares.length, 5);
  assert.equal(shares.at(-1)?.name, null);
  assert.ok(Math.abs(shares.reduce((total, row) => total + row.share, 0) - 1) < 1e-9);
  assert.deepEqual(categoryShares(entries, cards[2], 'month', TODAY), []);
  assert.equal(categoryShares(entries, cards[0], 'month', TODAY)[0].name, 'Продукты');
});

test('distribution ignores negative balances and history lists newest first', () => {
  const cards = buildCards(entries, TODAY);
  const shares = distribution(cards, 'KZT');
  assert.equal(shares.length, 3);
  assert.ok(Math.abs(shares.reduce((total, row) => total + row.share, 0) - 1) < 1e-9);
  assert.deepEqual(distribution([{ ...cards[0], balanceMinor: -5 }], 'KZT'), []);
  const history = cardHistory(entries, cards[0]);
  assert.deepEqual(
    history.map((entry) => entry.id),
    [food.id, move.id, salary.id, foodOld.id],
  );
  assert.deepEqual(
    cardHistory(entries, cards[2]).map((entry) => entry.id),
    [stock.id],
  );
});

test('operation accounts put the main account first and send no id for it', () => {
  const options = operationAccounts(entries, 'KZT');
  assert.deepEqual(
    options.map((option) => option.id),
    ['main', 'dep'],
  );
  assert.equal(options[1].name, 'Накопления');
  assert.equal(requestAccountId('main', entries, 'KZT'), undefined);
  assert.equal(requestAccountId('dep', entries, 'KZT'), 'dep');
  assert.equal(requestAccountId('usd', entries, 'KZT'), undefined);
  assert.equal(requestAccountId('missing', entries, 'KZT'), undefined);
});

test('stock positions sort by value and compute gain only when all prices are known', () => {
  const noBasis = make({
    type: 'stock',
    currency: 'KZT',
    name: 'Fund',
    valueMinor: 90000,
    asOf: '2026-09-01',
  });
  const positions = stockPositions([...entries, noBasis], 'KZT');
  assert.equal(positions[0].entry.name, 'Fund');
  assert.equal(positions[0].gainMinor, null);
  assert.equal(positions[1].gainMinor, 100 * (300 - 250));
});

test('the active card sits lowest and in front, the rest peek out above it in order', () => {
  const front = stackSlot(2, 2, 5);
  assert.deepEqual(front, { offset: 4 * 44, scale: 1, dim: 1, layer: 5 });
  const first = stackSlot(0, 2, 5);
  assert.equal(first.offset, 3 * 44);
  assert.ok(first.scale < 1 && first.layer < front.layer);
  const last = stackSlot(4, 2, 5);
  assert.equal(last.offset, 0);
  assert.ok(last.layer < first.layer);
  const offsets = [0, 1, 2, 3, 4].map((index) => stackSlot(index, 0, 5).offset);
  assert.deepEqual(offsets, [176, 132, 88, 44, 0]);
});

test('card colours follow the kind: accounts by currency, deposits alternate, stocks teal', () => {
  const cards = buildCards(entries, TODAY);
  const tones = cardTones(cards);
  assert.equal(tones.get('main'), 'violet');
  assert.equal(tones.get('dep'), 'indigo');
  assert.equal(tones.get('stocks-KZT'), 'teal');
  assert.equal(tones.get('usd'), 'graphite');
});
