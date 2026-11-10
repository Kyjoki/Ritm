import { useMemo, useState, type ReactNode } from 'react';
import { ArrowDownLeft, ArrowUpRight, Pencil, Plus, Trash2 } from 'lucide-react';
import type { FinanceEntry } from '../../../shared/types';
import { MotionNumber } from '../../components/Motion';
import { useI18n } from '../../lib/i18n';
import { FinanceHistory } from './FinanceHistory';
import {
  CategoryPanel,
  ChartPanel,
  KpiTiles,
  PositionsPanel,
  statTiles,
  windowLabelKey,
} from './FinancePanels';
import { formatPercent, useDayLabel, useMoney } from './finance-format';
import {
  balanceSeries,
  cardHistory,
  cardStats,
  categoryShares,
  stockPositions,
  type FinanceCard,
  type FinancePeriod,
} from './finance-wallet';

export interface DetailProps {
  card: FinanceCard;
  entries: FinanceEntry[];
  cards: FinanceCard[];
  today: string;
  period: FinancePeriod;
  onPeriod: (period: FinancePeriod) => void;
  deleting: string | null;
  accountName: (entry: FinanceEntry) => string;
  cardEntry: FinanceEntry | null;
  onEditEntry: (entry: FinanceEntry) => void;
  onDeleteEntry: (entry: FinanceEntry) => Promise<void> | void;
  onOperation: () => void;
  onTransfer: (from: string, to: string) => void;
  onPrice: (entry: Extract<FinanceEntry, { type: 'stock' }>) => void;
  onAddStock: () => void;
}

function DetailHead({ props, children }: { props: DetailProps; children?: ReactNode }) {
  const { t } = useI18n();
  const { money } = useMoney();
  const { full } = useDayLabel();
  const { card, cardEntry, deleting, onEditEntry, onDeleteEntry } = props;
  const [confirming, setConfirming] = useState(false);
  const name =
    card.kind === 'account'
      ? t('Основной счёт')
      : card.kind === 'stocks'
        ? t('Акции')
        : (card.name ?? '');
  const kind =
    card.kind === 'account'
      ? t('Расчётный счёт')
      : card.kind === 'stocks'
        ? t('Брокерский счёт')
        : t('Депозит');
  return (
    <div className="fin-detail-head">
      <div className="fin-detail-title">
        <h2>{name}</h2>
        <p>
          {kind} · {card.currency}
          {card.asOf ? ` · ${t('с {date}', { date: full(card.asOf) })}` : ''}
        </p>
        <div className="fin-detail-balance">
          {card.balanceMinor === null ? (
            '—'
          ) : (
            <MotionNumber
              value={card.balanceMinor}
              step={100}
              format={(value) => money(value, card.currency)}
            />
          )}
        </div>
      </div>
      <div className="fin-detail-actions">
        {children}
        {cardEntry &&
          (confirming ? (
            <>
              <button
                type="button"
                className="fin-btn is-danger"
                disabled={deleting === cardEntry.id}
                onClick={() =>
                  void Promise.resolve(onDeleteEntry(cardEntry)).then(() => setConfirming(false))
                }
              >
                {deleting === cardEntry.id ? t('Удаляем…') : t('Удалить?')}
              </button>
              <button type="button" className="fin-btn" onClick={() => setConfirming(false)}>
                {t('Отмена')}
              </button>
            </>
          ) : (
            <>
              <button
                type="button"
                className="fin-icon-btn"
                aria-label={t('Изменить счёт')}
                title={t('Изменить счёт')}
                onClick={() => onEditEntry(cardEntry)}
              >
                <Pencil size={16} />
              </button>
              <button
                type="button"
                className="fin-icon-btn"
                aria-label={t('Удалить счёт')}
                title={t('Удалить счёт')}
                onClick={() => setConfirming(true)}
              >
                <Trash2 size={16} />
              </button>
            </>
          ))}
      </div>
    </div>
  );
}

function StockDetail({ props }: { props: DetailProps }) {
  const { t, locale } = useI18n();
  const [confirming, setConfirming] = useState<string | null>(null);
  const { card, entries, deleting, onEditEntry, onDeleteEntry, onPrice, onAddStock } = props;
  const positions = useMemo(() => stockPositions(entries, card.currency), [entries, card.currency]);
  const priced = positions.filter((position) => position.gainMinor !== null);
  const invested = priced.reduce(
    (sum, { entry }) => sum + (entry.quantity ?? 0) * (entry.purchasePriceMinor ?? 0),
    0,
  );
  const gain = priced.reduce((sum, position) => sum + (position.gainMinor ?? 0), 0);
  const none = priced.length === 0;
  return (
    <>
      <DetailHead props={props}>
        <button type="button" className="fin-btn is-small" onClick={onAddStock}>
          <Plus size={15} /> {t('Акции')}
        </button>
      </DetailHead>
      <KpiTiles
        currency={card.currency}
        tiles={[
          { label: t('Стоимость'), value: card.balanceMinor ?? 0 },
          { label: t('Вложено'), value: invested, text: none ? '—' : undefined },
          {
            label: t('Результат'),
            value: gain,
            tone: 'net',
            signed: true,
            text: none ? '—' : undefined,
          },
        ]}
      />
      {!none && invested > 0 && (
        <p className="fin-note">
          {t('Результат')}: {formatPercent(locale, gain / invested, true)}
          {priced.length < positions.length &&
            ` · ${t('Расчёт для {count} из {total}', { count: priced.length, total: positions.length })}`}
        </p>
      )}
      <PositionsPanel
        positions={positions}
        currency={card.currency}
        deleting={deleting}
        confirming={confirming}
        onConfirm={setConfirming}
        onEdit={onEditEntry}
        onPrice={onPrice}
        onDelete={onDeleteEntry}
        onAdd={onAddStock}
      />
    </>
  );
}

function MoneyDetail({ props }: { props: DetailProps }) {
  const { t } = useI18n();
  const { card, entries, today, period, onPeriod } = props;
  const stats = useMemo(
    () => cardStats(entries, card, period, today),
    [entries, card, period, today],
  );
  const points = useMemo(
    () => balanceSeries(entries, card, period, today),
    [entries, card, period, today],
  );
  const shares = useMemo(
    () => categoryShares(entries, card, period, today),
    [entries, card, period, today],
  );
  const history = useMemo(() => cardHistory(entries, card), [entries, card]);
  const isDeposit = card.kind === 'deposit';
  const tiles = isDeposit
    ? statTiles(
        {
          ...stats,
          incomeMinor: stats.transfersInMinor + stats.incomeMinor,
          expenseMinor: stats.transfersOutMinor + stats.expenseMinor,
        },
        { income: t('Пополнения'), expense: t('Снятия'), net: t('Итого') },
      )
    : statTiles(stats, { income: t('Поступления'), expense: t('Расходы'), net: t('Разница') });
  const main = props.cards.find(
    (item) => item.kind === 'account' && item.currency === card.currency,
  );
  return (
    <>
      <DetailHead props={props}>
        <button type="button" className="fin-btn is-primary is-small" onClick={props.onOperation}>
          <Plus size={15} /> {t('Операция')}
        </button>
        {isDeposit && main && (
          <>
            <button
              type="button"
              className="fin-btn is-small"
              onClick={() => props.onTransfer(main.id, card.id)}
            >
              <ArrowDownLeft size={15} /> {t('Пополнить')}
            </button>
            <button
              type="button"
              className="fin-btn is-small"
              onClick={() => props.onTransfer(card.id, main.id)}
            >
              <ArrowUpRight size={15} /> {t('Снять')}
            </button>
          </>
        )}
      </DetailHead>
      <KpiTiles tiles={tiles} currency={card.currency} />
      <p className="fin-note">
        {t(
          isDeposit
            ? 'Пополнения и снятия — переводы со своих счетов.'
            : 'Переводы между своими счетами не считаются доходом или расходом.',
        )}{' '}
        {t(windowLabelKey(period))}.
      </p>
      <ChartPanel
        title={t('Динамика баланса')}
        subtitle={card.name ?? t('Основной счёт')}
        period={period}
        onPeriod={onPeriod}
        points={points}
        currency={card.currency}
        signature={`${card.id}|${period}`}
      />
      {(shares.length > 0 || !isDeposit) && (
        <CategoryPanel
          shares={shares}
          currency={card.currency}
          periodLabel={t(period === 'week' ? 'Неделя' : period === 'month' ? 'Месяц' : 'Год')}
        />
      )}
      <FinanceHistory
        title={t('История операций')}
        entries={history}
        today={today}
        showAccount={false}
        deleting={props.deleting}
        accountName={props.accountName}
        onEdit={props.onEditEntry}
        onDelete={props.onDeleteEntry}
      />
    </>
  );
}

export function FinanceDetail(props: DetailProps) {
  return (
    <div className="fin-right-stack" key={props.card.id}>
      {props.card.kind === 'stocks' ? <StockDetail props={props} /> : <MoneyDetail props={props} />}
    </div>
  );
}
