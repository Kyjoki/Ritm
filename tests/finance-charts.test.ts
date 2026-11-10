import test from 'node:test';
import assert from 'node:assert/strict';
import type { FinanceEntry } from '../shared/types.ts';
import {
  abbreviate,
  donutSegments,
  lineChartModel,
  monotonePath,
  niceTicks,
  spacedLabelIndexes,
} from '../src/features/finance/finance-charts.ts';
import { applyHistoryFilter, groupByDay } from '../src/features/finance/finance-history.ts';

test('nice ticks cover the range with round steps and labels are abbreviated', () => {
  const ticks = niceTicks(1_650_000, 2_250_000, 3);
  assert.ok(ticks[0] <= 1_650_000 && ticks.at(-1)! >= 2_250_000);
  assert.deepEqual(niceTicks(0, 10, 2), [0, 5, 10]);
  assert.equal(abbreviate(2_100_000), '2,1M');
  assert.equal(abbreviate(45_000), '45K');
  assert.equal(abbreviate(-900), '-900');
});

test('monotone path needs two points and starts at the first one', () => {
  assert.equal(monotonePath([[0, 0]]), '');
  const path = monotonePath([
    [0, 10],
    [10, 10],
    [20, 0],
  ]);
  assert.ok(path.startsWith('M0,10C'));
});

test('line chart model returns ticks, up to five x labels and the end point', () => {
  assert.equal(lineChartModel([]).end, null);
  const points = Array.from({ length: 30 }, (_, index) => ({
    date: `2026-10-${String(index + 1).padStart(2, '0')}`,
    valueMinor: 100_000 + index * 5_000,
  }));
  const model = lineChartModel(points);
  assert.ok(model.line.startsWith('M'));
  assert.ok(model.area.endsWith('Z'));
  assert.equal(model.xLabels.length, 5);
  assert.equal(model.xLabels[0].anchor, 'start');
  assert.equal(model.xLabels.at(-1)?.anchor, 'end');
  assert.equal(model.end?.valueMinor, 245_000);
  const single = lineChartModel([{ date: '2026-10-01', valueMinor: 5_000 }]);
  assert.equal(single.xLabels.length, 1);
  assert.equal(single.line, '');
});

test('donut segments cover the circle minus gaps', () => {
  assert.deepEqual(donutSegments([]), []);
  assert.deepEqual(donutSegments([0, 0]), []);
  const one = donutSegments([1]);
  assert.equal(one.length, 1);
  assert.ok(Math.abs(one[0].dash - 2 * Math.PI * 44) < 0.1);
  const three = donutSegments([2, 1, 1]);
  assert.equal(three[0].offset, 0);
  assert.ok(three[1].offset < three[0].offset && three[2].offset < three[1].offset);
  assert.ok(three[0].dash > three[1].dash);
});

function entry(id: string, type: string, date: string): FinanceEntry {
  return {
    id,
    type,
    date,
    currency: 'KZT',
    amountMinor: 1,
    note: '',
    category: 'x',
    createdAt: '',
    updatedAt: '',
  } as unknown as FinanceEntry;
}

test('history groups by day with today and yesterday labels and filters by type', () => {
  const list = [
    entry('a', 'expense', '2026-10-29'),
    entry('b', 'income', '2026-10-28'),
    entry('c', 'expense', '2026-10-28'),
    entry('d', 'expense', '2025-12-31'),
  ];
  const groups = groupByDay(list, '2026-10-29', 'ru');
  assert.deepEqual(
    groups.map((group) => group.key),
    ['2026-10-29', '2026-10-28', '2025-12-31'],
  );
  assert.equal(groups[0].relative, 'today');
  assert.equal(groups[1].relative, 'yesterday');
  assert.equal(groups[1].entries.length, 2);
  assert.equal(groups[0].month, 'окт');
  assert.equal(groups[2].month, 'дек 2025');
  assert.equal(groups[0].weekday, 'чт');
  assert.equal(groupByDay(list, '2026-10-29', 'en')[0].weekday, 'Thu');
  assert.equal(applyHistoryFilter(list, 'income').length, 1);
  assert.equal(applyHistoryFilter(list, 'all').length, 4);
});

test('x labels keep their distance: crowded middle labels are dropped, the ends stay', () => {
  assert.deepEqual(spacedLabelIndexes(1, 266), [0]);
  assert.deepEqual(spacedLabelIndexes(2, 266), [0, 1]);
  const eleven = spacedLabelIndexes(11, 266);
  assert.equal(eleven[0], 0);
  assert.equal(eleven.at(-1), 10);
  for (let i = 1; i < eleven.length; i++) assert.ok(((eleven[i] - eleven[i - 1]) * 266) / 10 >= 64);
  assert.equal(spacedLabelIndexes(30, 266).length, 5);
});
