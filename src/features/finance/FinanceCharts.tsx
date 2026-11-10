import { useId, useMemo, type CSSProperties, type ReactNode } from 'react';
import type { FinanceCurrency } from '../../../shared/types';
import { useI18n } from '../../lib/i18n';
import { CHART_LAYOUT, DONUT_RADIUS, donutSegments, lineChartModel } from './finance-charts';
import { useDayLabel, useMoney } from './finance-format';
import type { FinancePeriod, SeriesPoint } from './finance-wallet';

export const PERIOD_OPTIONS: readonly (readonly [FinancePeriod, string])[] = [
  ['week', 'Неделя'],
  ['month', 'Месяц'],
  ['year', 'Год'],
];

export function PeriodSwitch({
  value,
  onChange,
}: {
  value: FinancePeriod;
  onChange: (period: FinancePeriod) => void;
}) {
  const { t } = useI18n();
  return (
    <div className="fin-seg" role="group" aria-label={t('Период')}>
      {PERIOD_OPTIONS.map(([period, label]) => (
        <button
          key={period}
          type="button"
          aria-pressed={value === period}
          onClick={() => onChange(period)}
        >
          {t(label)}
        </button>
      ))}
    </div>
  );
}

/** Balance line of one card or one currency; redraws with a stroke animation when the data changes. */
export function BalanceChart({
  points,
  currency,
  signature,
}: {
  points: SeriesPoint[];
  currency: FinanceCurrency;
  signature: string;
}) {
  const { t } = useI18n();
  const { money } = useMoney();
  const { short } = useDayLabel();
  const gradient = useId();
  const model = useMemo(() => lineChartModel(points), [points]);
  const { width, height, left, right, top } = CHART_LAYOUT;
  if (!model.end) return <p className="fin-empty-note">{t('Данных для графика пока нет.')}</p>;
  const labelY = model.end.y < top + 16 ? model.end.y + 16 : model.end.y - 9;
  return (
    <svg
      key={signature}
      className="fin-chart"
      viewBox={`0 0 ${width} ${height}`}
      role="img"
      aria-label={`${t('График, конец периода')}: ${money(model.end.valueMinor, currency)}`}
    >
      <defs>
        <linearGradient id={gradient} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" className="fin-chart-s0" />
          <stop offset="1" className="fin-chart-s1" />
        </linearGradient>
      </defs>
      {model.yTicks.map((tick) => (
        <g key={tick.y}>
          <line className="fin-chart-grid" x1={left} x2={width - right} y1={tick.y} y2={tick.y} />
          <text x={left - 6} y={tick.y + 3} textAnchor="end">
            {tick.label}
          </text>
        </g>
      ))}
      {model.xLabels.map((label) => (
        <text key={label.x} x={label.x} y={height - 6} textAnchor={label.anchor}>
          {short(label.date)}
        </text>
      ))}
      {model.area && <path className="fin-chart-area" d={model.area} fill={`url(#${gradient})`} />}
      {model.line && <path className="fin-chart-line" pathLength={1} d={model.line} />}
      <circle className="fin-chart-dot" cx={model.end.x} cy={model.end.y} r="3.8" />
      <text className="fin-chart-end" x={model.end.x} y={labelY} textAnchor="end">
        {money(model.end.valueMinor, currency)}
      </text>
    </svg>
  );
}

export interface DonutItem {
  key: string;
  label: string;
  amountMinor: number;
  icon?: ReactNode;
}

/** Ring and legend; slice i uses the shared chart palette index i. */
export function DonutChart({
  items,
  currency,
  caption,
  signature,
  empty,
}: {
  items: DonutItem[];
  currency: FinanceCurrency;
  caption: string;
  signature: string;
  empty: string;
}) {
  const { locale } = useI18n();
  const { money } = useMoney();
  const maskId = useId();
  const total = items.reduce((sum, item) => sum + item.amountMinor, 0);
  const segments = useMemo(() => donutSegments(items.map((item) => item.amountMinor)), [items]);
  if (!total) return <p className="fin-empty-note">{empty}</p>;
  const percent = new Intl.NumberFormat(locale, { style: 'percent', maximumFractionDigits: 0 });
  return (
    <div className="fin-donut-wrap" key={signature}>
      <div
        className="fin-donut"
        role="img"
        aria-label={items
          .map((item) => `${item.label}: ${money(item.amountMinor, currency)}`)
          .join(', ')}
      >
        <svg viewBox="0 0 120 120" aria-hidden="true">
          <defs>
            <mask id={maskId}>
              <circle className="fin-donut-sweep" cx="60" cy="60" r={DONUT_RADIUS} pathLength={1} />
            </mask>
          </defs>
          <g mask={`url(#${maskId})`}>
            {segments.map((segment, index) => (
              <circle
                key={items[index].key}
                className={`fin-donut-seg is-c${index % 6}`}
                cx="60"
                cy="60"
                r={DONUT_RADIUS}
                strokeDasharray={`${segment.dash} ${segment.gap}`}
                strokeDashoffset={segment.offset}
              />
            ))}
          </g>
        </svg>
        <div className="fin-donut-center">
          <b>{money(total, currency)}</b>
          <span>{caption}</span>
        </div>
      </div>
      <ul className="fin-legend">
        {items.map((item, index) => (
          <li key={item.key} style={{ '--i': index } as CSSProperties}>
            {item.icon ? (
              <span className={`fin-legend-ic is-c${index % 6}`}>{item.icon}</span>
            ) : (
              <span className={`fin-legend-dot is-c${index % 6}`} />
            )}
            <span className="fin-legend-name">{item.label}</span>
            <span className="fin-legend-sum">{money(item.amountMinor, currency)}</span>
            <span className="fin-legend-pc">{percent.format(item.amountMinor / total)}</span>
          </li>
        ))}
      </ul>
    </div>
  );
}
