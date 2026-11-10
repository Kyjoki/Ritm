import type { SeriesPoint } from './finance-wallet';

/** Pure geometry for the balance line and the donut; the components only draw what this returns. */
export interface ChartLayout {
  width: number;
  height: number;
  left: number;
  right: number;
  top: number;
  bottom: number;
}
export const CHART_LAYOUT: ChartLayout = {
  width: 318,
  height: 164,
  left: 40,
  right: 12,
  top: 14,
  bottom: 24,
};

const round1 = (value: number) => Math.round(value * 10) / 10;

export function niceTicks(min: number, max: number, count: number): number[] {
  const span = max - min || 1;
  const raw = span / count;
  const power = 10 ** Math.floor(Math.log10(raw));
  const fraction = raw / power;
  const factor =
    fraction <= 1 ? 1 : fraction <= 2 ? 2 : fraction <= 2.5 ? 2.5 : fraction <= 5 ? 5 : 10;
  const step = factor * power;
  const low = Math.floor(min / step) * step;
  const high = Math.ceil(max / step) * step;
  const ticks: number[] = [];
  for (let value = low; value <= high + step * 1e-6; value += step) ticks.push(value);
  return ticks;
}

/** Short axis label: 1 200 000 becomes 1,2M, 45 000 becomes 45K. */
export function abbreviate(value: number): string {
  const abs = Math.abs(value);
  if (abs >= 1e6) return `${String(round1(value / 1e6)).replace('.', ',')}M`;
  if (abs >= 1e3) return `${Math.round(value / 1e3)}K`;
  return String(Math.round(value));
}

function limitTangents(tangent: number[], slope: number[]) {
  for (let i = 0; i < slope.length; i++) {
    if (slope[i] === 0) {
      tangent[i] = 0;
      tangent[i + 1] = 0;
      continue;
    }
    const a = tangent[i] / slope[i];
    const b = tangent[i + 1] / slope[i];
    const squares = a * a + b * b;
    if (squares > 9) {
      const k = 3 / Math.sqrt(squares);
      tangent[i] = k * a * slope[i];
      tangent[i + 1] = k * b * slope[i];
    }
  }
}

/** Monotone cubic path through the points (no overshoot between samples). */
export function monotonePath(points: [number, number][]): string {
  const count = points.length;
  if (count < 2) return '';
  const dx: number[] = [];
  const slope: number[] = [];
  for (let i = 0; i < count - 1; i++) {
    dx[i] = points[i + 1][0] - points[i][0];
    slope[i] = (points[i + 1][1] - points[i][1]) / dx[i];
  }
  const tangent: number[] = [slope[0]];
  for (let i = 1; i < count - 1; i++)
    tangent[i] = slope[i - 1] * slope[i] <= 0 ? 0 : (slope[i - 1] + slope[i]) / 2;
  tangent[count - 1] = slope[count - 2];
  limitTangents(tangent, slope);
  let path = `M${round1(points[0][0])},${round1(points[0][1])}`;
  for (let i = 0; i < count - 1; i++) {
    const h = dx[i] / 3;
    const c1 = `${round1(points[i][0] + h)},${round1(points[i][1] + tangent[i] * h)}`;
    const c2 = `${round1(points[i + 1][0] - h)},${round1(points[i + 1][1] - tangent[i + 1] * h)}`;
    path += `C${c1} ${c2} ${round1(points[i + 1][0])},${round1(points[i + 1][1])}`;
  }
  return path;
}

const MIN_LABEL_GAP_PX = 64;

/** Up to five evenly spread x labels; middle ones that would touch a neighbour are dropped. */
export function spacedLabelIndexes(count: number, plotWidth: number): number[] {
  if (count <= 1) return [0];
  const x = (index: number) => (index * plotWidth) / (count - 1);
  const all = [0, 1, 2, 3, 4]
    .map((step) => Math.round((step * (count - 1)) / 4))
    .filter((value, index, list) => list.indexOf(value) === index);
  const last = all[all.length - 1];
  const kept = [all[0]];
  for (const index of all.slice(1, -1))
    if (
      x(index) - x(kept[kept.length - 1]) >= MIN_LABEL_GAP_PX &&
      x(last) - x(index) >= MIN_LABEL_GAP_PX
    )
      kept.push(index);
  return all.length > 1 && last !== kept[0] ? [...kept, last] : kept;
}

export interface LineChartModel {
  line: string;
  area: string;
  yTicks: { y: number; label: string }[];
  xLabels: { x: number; date: string; anchor: 'start' | 'middle' | 'end' }[];
  end: { x: number; y: number; valueMinor: number } | null;
}

/** Layout of the balance line: nice y ticks, up to five x labels and the end point. */
export function lineChartModel(
  points: SeriesPoint[],
  layout: ChartLayout = CHART_LAYOUT,
): LineChartModel {
  if (!points.length) return { line: '', area: '', yTicks: [], xLabels: [], end: null };
  const { width, height, left, right, top, bottom } = layout;
  const plotWidth = width - left - right;
  const plotHeight = height - top - bottom;
  const values = points.map((point) => point.valueMinor / 100);
  const min = Math.min(...values);
  const max = Math.max(...values);
  const pad = (max - min) * 0.1 || Math.abs(max) * 0.05 || 1;
  const ticks = niceTicks(min - pad, max + pad, 3);
  const low = ticks[0];
  const high = ticks[ticks.length - 1];
  const count = points.length;
  const x = (index: number) => left + (count === 1 ? plotWidth : (index * plotWidth) / (count - 1));
  const y = (value: number) => top + plotHeight - ((value - low) / (high - low)) * plotHeight;
  const line = monotonePath(values.map((value, index) => [x(index), y(value)]));
  const base = top + plotHeight;
  const area = line ? `${line}L${round1(x(count - 1))},${base}L${left},${base}Z` : '';
  const labelIndexes = spacedLabelIndexes(count, plotWidth);
  return {
    line,
    area,
    yTicks: ticks.map((tick) => ({ y: round1(y(tick)), label: abbreviate(tick) })),
    xLabels: labelIndexes.map((index) => ({
      x: round1(x(index)),
      date: points[index].date,
      anchor: index === 0 ? 'start' : index === count - 1 ? 'end' : 'middle',
    })),
    end: {
      x: round1(x(count - 1)),
      y: round1(y(values[count - 1])),
      valueMinor: points[count - 1].valueMinor,
    },
  };
}

export interface DonutSegment {
  dash: number;
  gap: number;
  offset: number;
}
export const DONUT_RADIUS = 44;

/** Stroke-dash segments of a donut ring with a small gap between slices. */
export function donutSegments(shares: number[], radius = DONUT_RADIUS): DonutSegment[] {
  const circumference = 2 * Math.PI * radius;
  const total = shares.reduce((sum, value) => sum + value, 0);
  if (total <= 0) return [];
  const gap = shares.length > 1 ? 2.5 : 0;
  let offset = 0;
  return shares.map((share) => {
    const length = (share / total) * circumference;
    const segment = {
      dash: round1(Math.max(length - gap, 0.5)),
      gap: round1(circumference),
      offset: offset > 0 ? round1(-offset) : 0,
    };
    offset += length;
    return segment;
  });
}
