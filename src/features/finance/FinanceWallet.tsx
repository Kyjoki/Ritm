import type { FinanceCurrency } from '../../../shared/types';
import { MotionNumber } from '../../components/Motion';
import { useI18n } from '../../lib/i18n';
import { useMoney } from './finance-format';

export function FinanceTotals({
  totals,
}: {
  totals: { currency: FinanceCurrency; amountMinor: number }[];
}) {
  const { t } = useI18n();
  const { money } = useMoney();
  return (
    <div className="fin-totals">
      <span className="fin-totals-label">{t('Всего средств')}</span>
      <div className="fin-totals-values">
        {totals.length ? (
          totals.map((total, index) => (
            <span key={total.currency} className="fin-totals-item">
              {index > 0 && (
                <span className="fin-totals-sep" aria-hidden="true">
                  ·
                </span>
              )}
              <span className={index ? 'fin-total-sub' : 'fin-total-main'}>
                <MotionNumber
                  value={total.amountMinor}
                  format={(value) => money(value, total.currency)}
                  step={100}
                />
              </span>
            </span>
          ))
        ) : (
          <span className="fin-total-main">—</span>
        )}
      </div>
      {totals.length > 1 && (
        <p className="fin-totals-note">{t('Суммы в разных валютах не складываются.')}</p>
      )}
    </div>
  );
}
