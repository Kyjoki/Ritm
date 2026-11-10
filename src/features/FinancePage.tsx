import { memo, useEffect, useMemo, useState, type CSSProperties } from 'react';
import { ArrowRightLeft, Coins, LoaderCircle, Plus } from 'lucide-react';
import type { FinanceEntry } from '../../shared/types';
import { useI18n } from '../lib/i18n';
import { FinanceDetail } from './finance/FinanceDetail';
import { FinanceDialogs } from './finance/FinanceDialogs';
import { FinanceOverview } from './finance/FinanceOverview';
import { FinanceLeft } from './finance/FinanceLeft';
import { localDate } from './finance/finance-form';
import {
  buildCards,
  cardTotals,
  type FinanceCard,
  type FinancePeriod,
} from './finance/finance-wallet';
import { useFinanceData } from './finance/useFinanceData';
import { useFinanceDialogs } from './finance/useFinanceDialogs';
import '../styles/finance.css';

const ENTER_TOTAL_MS = 900;
const enterStyle = (index: number) => ({ '--i': index }) as CSSProperties;

function HeaderActions({
  canTransfer,
  onAccount,
  onTransfer,
  onOperation,
}: {
  canTransfer: boolean;
  onAccount: () => void;
  onTransfer: () => void;
  onOperation: () => void;
}) {
  const { t } = useI18n();
  return (
    <div className="fin-actions">
      <button type="button" className="fin-btn" onClick={onAccount}>
        <Plus size={16} aria-hidden="true" /> {t('Счёт')}
      </button>
      <button type="button" className="fin-btn" onClick={onTransfer} disabled={!canTransfer}>
        <ArrowRightLeft size={16} aria-hidden="true" /> {t('Перевод')}
      </button>
      <button type="button" className="fin-btn is-primary" onClick={onOperation}>
        <Plus size={16} aria-hidden="true" /> {t('Операция')}
      </button>
    </div>
  );
}

/** Account label lookups used by the history rows and the transfer form. */
function useAccountNames(
  entries: FinanceEntry[],
  cards: FinanceCard[],
  t: (source: string) => string,
) {
  return useMemo(() => {
    const byId = new Map(entries.map((entry) => [entry.id, entry]));
    const manyCurrencies = new Set(cards.map((card) => card.currency)).size > 1;
    const label = (id: string) => {
      const entry = byId.get(id);
      if (entry?.type === 'deposit') return entry.name;
      return entry?.type === 'account' ? t('Основной счёт') : t('Счёт недоступен');
    };
    const rowName = (entry: FinanceEntry) => {
      if (entry.type === 'transfer')
        return `${label(entry.fromAccountId)} → ${label(entry.toAccountId)}`;
      if (entry.type !== 'income' && entry.type !== 'expense') return '';
      if (entry.accountId) return label(entry.accountId);
      return t('Основной счёт') + (manyCurrencies ? ` · ${entry.currency}` : '');
    };
    return { byId, label, rowName };
  }, [entries, cards, t]);
}

export const FinancePage = memo(function FinancePage({
  active = true,
  today = localDate(),
}: {
  active?: boolean;
  today?: string;
}) {
  const { t } = useI18n();
  const data = useFinanceData(active, t);
  const { entries, loading } = data;
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [period, setPeriod] = useState<FinancePeriod>('month');
  const [entering, setEntering] = useState(true);
  useEffect(() => {
    if (!active || loading || !entering) return;
    const timer = window.setTimeout(() => setEntering(false), ENTER_TOTAL_MS);
    return () => window.clearTimeout(timer);
  }, [active, loading, entering]);

  const cards = useMemo(() => buildCards(entries, today), [entries, today]);
  const totals = useMemo(() => cardTotals(cards), [cards]);
  const currencies = useMemo(() => totals.map((total) => total.currency), [totals]);
  const selected = cards.find((card) => card.id === selectedId) ?? null;
  const names = useAccountNames(entries, cards, t);
  const dialogs = useFinanceDialogs({
    entries,
    cards,
    selected,
    currencies,
    today,
    data,
    t,
    onCreated: setSelectedId,
  });

  async function removeEntry(entry: FinanceEntry) {
    const removed = await data.removeEntry(entry);
    if (removed && selected?.id === entry.id) setSelectedId(null);
  }
  const cardName = (card: FinanceCard) =>
    card.kind === 'account'
      ? t('Основной счёт')
      : card.kind === 'stocks'
        ? t('Акции')
        : (card.name ?? '');
  const shared = {
    entries,
    today,
    period,
    onPeriod: setPeriod,
    deleting: data.deleting,
    accountName: names.rowName,
    onEditEntry: dialogs.openEdit,
    onDeleteEntry: removeEntry,
  };
  return (
    <section
      className={`finance-page fin${entering ? ' is-entering' : ''}`}
      aria-labelledby="finance-title"
    >
      <header className="page-heading fin-heading">
        <div>
          <p className="page-eyebrow">{t('RITM · ЛИЧНЫЕ ФИНАНСЫ')}</p>
          <h1 id="finance-title" className="gradient-title">
            {t('Финансы')}
          </h1>
          <p className="page-description">
            {t('Поступления, расходы и активы — в одной ясной картине.')}
          </p>
        </div>
        <HeaderActions
          canTransfer={cards.filter((card) => card.kind !== 'stocks').length > 1}
          onAccount={() => dialogs.openAsset()}
          onTransfer={() => dialogs.openTransfer()}
          onOperation={() => dialogs.openOperation()}
        />
      </header>
      {data.error && (
        <div className="fin-alert" role="alert">
          <span>{data.error}</span>
          {data.retryable && (
            <button type="button" onClick={data.reload}>
              {t('Повторить')}
            </button>
          )}
        </div>
      )}
      {loading ? (
        <div className="fin-loading" role="status">
          <LoaderCircle className="spinning" size={20} /> {t('Загружаем финансы…')}
        </div>
      ) : cards.length === 0 ? (
        <div className="fin-panel fin-welcome">
          <Coins size={28} aria-hidden="true" />
          <strong>{t('Начните с первой записи')}</strong>
          <p>
            {t('Добавьте основной счёт, депозит или акции. Графики появятся по мере заполнения.')}
          </p>
          <button
            type="button"
            className="fin-btn is-primary"
            onClick={() => dialogs.openAsset('account')}
          >
            {t('Задать стартовый остаток')}
          </button>
        </div>
      ) : (
        <div className="fin-layout">
          <FinanceLeft
            style={enterStyle(0)}
            cards={cards}
            totals={totals}
            selectedId={selected?.id ?? null}
            refreshing={data.refreshing}
            onSelect={setSelectedId}
            onRefresh={data.reload}
          />
          <div className="fin-right fin-b" style={enterStyle(1)}>
            {selected ? (
              <FinanceDetail
                {...shared}
                card={selected}
                cards={cards}
                cardEntry={
                  selected.kind === 'stocks' ? null : (names.byId.get(selected.id) ?? null)
                }
                onOperation={() => dialogs.openOperation(selected)}
                onTransfer={dialogs.openTransfer}
                onPrice={dialogs.openPrice}
                onAddStock={() => dialogs.openStock(selected.currency)}
              />
            ) : (
              <FinanceOverview
                {...shared}
                cards={cards}
                currencies={currencies}
                nameOf={cardName}
              />
            )}
          </div>
        </div>
      )}
      <FinanceDialogs
        dialogs={dialogs}
        entries={entries}
        saving={data.saving}
        today={today}
        accountName={names.label}
      />
    </section>
  );
});
