import type { CSSProperties } from 'react';
import { RefreshCw } from 'lucide-react';
import type { FinanceCurrency } from '../../../shared/types';
import { useI18n } from '../../lib/i18n';
import { FinanceTotals } from './FinanceWallet';
import { WalletStack } from './WalletStack';
import type { FinanceCard } from './finance-wallet';

/** Left column: totals per currency, the wallet stack and the refresh control. */
export function FinanceLeft({
  style,
  cards,
  totals,
  selectedId,
  refreshing,
  onSelect,
  onRefresh,
}: {
  style: CSSProperties;
  cards: FinanceCard[];
  totals: { currency: FinanceCurrency; amountMinor: number }[];
  selectedId: string | null;
  refreshing: boolean;
  onSelect: (id: string | null) => void;
  onRefresh: () => void;
}) {
  const { t } = useI18n();
  return (
    <div className="fin-left fin-b" style={style}>
      <FinanceTotals totals={totals} />
      <WalletStack cards={cards} selectedId={selectedId} onSelect={onSelect} />
      <button type="button" className="fin-refresh" onClick={onRefresh} disabled={refreshing}>
        <RefreshCw size={15} className={refreshing ? 'spinning' : ''} aria-hidden="true" />{' '}
        {t('Обновить финансы')}
      </button>
      <p className="fin-manual">
        {t('Все суммы вводятся вручную. Курсы валют и цены акций не обновляются автоматически.')}
      </p>
    </div>
  );
}
