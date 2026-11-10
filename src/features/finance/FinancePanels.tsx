import { useMemo, type ReactNode } from 'react';
import { ExternalLink } from 'lucide-react';
import type { FinanceCurrency, FinanceEntry } from '../../../shared/types';
import { MotionNumber } from '../../components/Motion';
import { useI18n } from '../../lib/i18n';
import { RowActions } from './FinanceRowActions';
import { BalanceChart, DonutChart, PeriodSwitch, type DonutItem } from './FinanceCharts';
import { quoteUrl } from './finance-form';
import { CategoryIcon, formatPercent, useDayLabel, useMoney } from './finance-format';
import {
  distribution,
  type CategoryShare,
  type FinanceCard,
  type FinancePeriod,
  type PeriodStats,
  type SeriesPoint,
  type StockPosition,
} from './finance-wallet';

export function windowLabelKey(period: FinancePeriod) {
  return period === 'week' ? 'за неделю' : period === 'month' ? 'за месяц' : 'за год';
}

export interface Tile {
  label: string;
  value: number;
  tone?: 'income' | 'expense' | 'net';
  signed?: boolean;
  /** Replaces the number, e.g. «—» when nothing can be calculated. */
  text?: string;
}

export function KpiTiles({ tiles, currency }: { tiles: Tile[]; currency: FinanceCurrency }) {
  const { money, signed } = useMoney();
  return (
    <div className="fin-tiles">
      {tiles.map((tile) => (
        <div className="fin-tile" key={tile.label}>
          <span className="fin-tile-label">{tile.label}</span>
          <b
            className={`fin-tile-value${
              tile.tone === 'net'
                ? tile.value > 0
                  ? ' is-income'
                  : tile.value < 0
                    ? ' is-expense'
                    : ''
                : tile.tone
                  ? ` is-${tile.tone}`
                  : ''
            }`}
          >
            {tile.text ?? (
              <MotionNumber
                value={tile.value}
                step={100}
                format={(value) => (tile.signed ? signed(value, currency) : money(value, currency))}
              />
            )}
          </b>
        </div>
      ))}
    </div>
  );
}

export function statTiles(
  stats: PeriodStats,
  labels: { income: string; expense: string; net: string },
): Tile[] {
  return [
    { label: labels.income, value: stats.incomeMinor, tone: 'income', signed: true },
    { label: labels.expense, value: -stats.expenseMinor, tone: 'expense', signed: true },
    { label: labels.net, value: stats.incomeMinor - stats.expenseMinor, tone: 'net', signed: true },
  ];
}

export function ChartPanel({
  title,
  subtitle,
  period,
  onPeriod,
  points,
  currency,
  signature,
  note,
  headExtra,
}: {
  title: string;
  subtitle: string;
  period: FinancePeriod;
  onPeriod: (period: FinancePeriod) => void;
  points: SeriesPoint[];
  currency: FinanceCurrency;
  signature: string;
  note?: ReactNode;
  headExtra?: ReactNode;
}) {
  const { t } = useI18n();
  const { short } = useDayLabel();
  const first = points[0]?.date;
  const last = points.at(-1)?.date;
  return (
    <section className="fin-panel fin-chart-panel" aria-label={title}>
      <div className="fin-panel-head">
        <div>
          <h2>{title}</h2>
          <p>{subtitle}</p>
        </div>
        {headExtra}
      </div>
      <PeriodSwitch value={period} onChange={onPeriod} />
      {first && last && (
        <p className="fin-window" aria-live="polite">
          {short(first)} – {short(last)} · {t(windowLabelKey(period))}
        </p>
      )}
      <div className="fin-chart-box">
        <BalanceChart points={points} currency={currency} signature={signature} />
      </div>
      {note && <p className="fin-note">{note}</p>}
    </section>
  );
}

export function DistributionPanel({
  cards,
  currencies,
  nameOf,
}: {
  cards: FinanceCard[];
  currencies: FinanceCurrency[];
  nameOf: (card: FinanceCard) => string;
}) {
  const { t } = useI18n();
  const { money } = useMoney();
  return (
    <section className="fin-panel fin-dist-panel" aria-label={t('Распределение')}>
      <div className="fin-panel-head">
        <div>
          <h2>{t('Распределение')}</h2>
          <p>{t('По счетам, отдельно для каждой валюты')}</p>
        </div>
      </div>
      {currencies.map((currency) => (
        <DistributionBlock
          key={currency}
          cards={cards}
          currency={currency}
          nameOf={nameOf}
          money={money}
        />
      ))}
    </section>
  );
}

function DistributionBlock({
  cards,
  currency,
  nameOf,
  money,
}: {
  cards: FinanceCard[];
  currency: FinanceCurrency;
  nameOf: (card: FinanceCard) => string;
  money: (minor: number, currency: FinanceCurrency) => string;
}) {
  const { t, locale } = useI18n();
  const shares = useMemo(() => distribution(cards, currency), [cards, currency]);
  const total = cards
    .filter((card) => card.currency === currency)
    .reduce((sum, card) => sum + (card.balanceMinor ?? 0), 0);
  return (
    <div className="fin-dist">
      <div className="fin-dist-head">
        <span>{currency}</span>
        <b>{money(total, currency)}</b>
      </div>
      {shares.length > 0 ? (
        <>
          <div className="fin-dist-bar" role="img" aria-label={t('Распределение по счетам')}>
            {shares.map((share, index) => (
              <i key={share.cardId} className={`is-c${index % 6}`} style={{ flex: share.share }} />
            ))}
          </div>
          <ul className="fin-legend">
            {shares.map((share, index) => {
              const card = cards.find((item) => item.id === share.cardId)!;
              return (
                <li key={share.cardId}>
                  <span className={`fin-legend-dot is-c${index % 6}`} />
                  <span className="fin-legend-name">{nameOf(card)}</span>
                  <span className="fin-legend-sum">{money(share.amountMinor, currency)}</span>
                  <span className="fin-legend-pc">
                    {formatPercent(locale, share.share, false, 0)}
                  </span>
                </li>
              );
            })}
          </ul>
        </>
      ) : (
        <p className="fin-empty-note">{t('Положительных остатков пока нет.')}</p>
      )}
    </div>
  );
}

export function CategoryPanel({
  shares,
  currency,
  periodLabel,
}: {
  shares: CategoryShare[];
  currency: FinanceCurrency;
  periodLabel: string;
}) {
  const { t } = useI18n();
  const items = useMemo<DonutItem[]>(
    () =>
      shares.map((share) => ({
        key: share.name ?? '__other',
        label: share.name ? t(share.name) : t('Другое'),
        amountMinor: share.amountMinor,
        icon: <CategoryIcon category={share.name ?? ''} />,
      })),
    [shares, t],
  );
  return (
    <section className="fin-panel fin-cat-panel" aria-label={t('Расходы по категориям')}>
      <div className="fin-panel-head">
        <div>
          <h2>{t('Расходы по категориям')}</h2>
          <p>{periodLabel}</p>
        </div>
      </div>
      <DonutChart
        items={items}
        currency={currency}
        caption={t('Всего')}
        signature={items.map((item) => `${item.key}:${item.amountMinor}`).join('|')}
        empty={t('За этот период расходов нет.')}
      />
    </section>
  );
}

function PositionRow({
  position,
  currency,
  deleting,
  confirming,
  onConfirm,
  onEdit,
  onPrice,
  onDelete,
}: {
  position: StockPosition;
  currency: FinanceCurrency;
  deleting: boolean;
  confirming: boolean;
  onConfirm: (id: string | null) => void;
  onEdit: (entry: FinanceEntry) => void;
  onPrice: (entry: Extract<FinanceEntry, { type: 'stock' }>) => void;
  onDelete: (entry: FinanceEntry) => Promise<void> | void;
}) {
  const { t, locale } = useI18n();
  const { money, signed } = useMoney();
  const { full } = useDayLabel();
  const { entry, valueMinor, gainMinor } = position;
  const link = entry.exchange && entry.ticker ? quoteUrl(entry.exchange, entry.ticker) : null;
  const basis =
    gainMinor === null || entry.quantity === undefined || entry.purchasePriceMinor === undefined
      ? null
      : entry.quantity * entry.purchasePriceMinor;
  const result =
    gainMinor === null
      ? t('Добавьте цену покупки для расчёта прибыли')
      : `${signed(gainMinor, currency)}${basis ? ` (${formatPercent(locale, gainMinor / basis, true)})` : ''}`;
  return (
    <li>
      <span className="fin-pos-main">
        <strong>{entry.name}</strong>
        <span>
          {entry.quantity && entry.unitPriceMinor !== undefined
            ? `${entry.quantity} × ${money(entry.unitPriceMinor, currency)}`
            : t('Ручная оценка')}
          {' · '}
          {full(entry.asOf)}
        </span>
        {link && (
          <a href={link} target="_blank" rel="noopener noreferrer">
            {entry.exchange} · {entry.ticker} <ExternalLink size={12} aria-hidden="true" />
          </a>
        )}
      </span>
      <span className="fin-pos-values">
        <b>{money(valueMinor, currency)}</b>
        <span className={gainMinor === null ? '' : gainMinor >= 0 ? 'is-income' : 'is-expense'}>
          {result}
        </span>
      </span>
      <RowActions
        label={entry.name}
        confirming={confirming}
        deleting={deleting}
        onAskDelete={() => onConfirm(entry.id)}
        onCancel={() => onConfirm(null)}
        onEdit={() => onEdit(entry)}
        onDelete={() => onDelete(entry)}
        extra={
          entry.quantity ? (
            <button type="button" className="is-text" onClick={() => onPrice(entry)}>
              {t('Обновить цену')}
            </button>
          ) : null
        }
      />
    </li>
  );
}

export function PositionsPanel({
  positions,
  onAdd,
  ...rest
}: {
  positions: StockPosition[];
  currency: FinanceCurrency;
  deleting: string | null;
  confirming: string | null;
  onConfirm: (id: string | null) => void;
  onEdit: (entry: FinanceEntry) => void;
  onPrice: (entry: Extract<FinanceEntry, { type: 'stock' }>) => void;
  onDelete: (entry: FinanceEntry) => Promise<void> | void;
  onAdd: () => void;
}) {
  const { t } = useI18n();
  const { deleting, confirming, ...row } = rest;
  return (
    <section className="fin-panel fin-positions" aria-label={t('Позиции')}>
      <div className="fin-panel-head">
        <div>
          <h2>{t('Позиции')}</h2>
          <p>{t('Цены вводятся вручную и не обновляются автоматически.')}</p>
        </div>
        <button type="button" className="fin-btn is-small" onClick={onAdd}>
          {t('Добавить акции')}
        </button>
      </div>
      <ul className="fin-pos-list">
        {positions.map((position) => (
          <PositionRow
            key={position.entry.id}
            position={position}
            deleting={deleting === position.entry.id}
            confirming={confirming === position.entry.id}
            {...row}
          />
        ))}
      </ul>
      <p className="fin-note">{t('Прибыль и убыток рассчитаны без комиссий и дивидендов.')}</p>
    </section>
  );
}
