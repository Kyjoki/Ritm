import { useMemo, useState } from 'react';
import type { FinanceCurrency, FinanceEntry } from '../../../shared/types';
import { useI18n } from '../../lib/i18n';
import { FinanceHistory } from './FinanceHistory';
import {
  CategoryPanel,
  ChartPanel,
  DistributionPanel,
  KpiTiles,
  statTiles,
  windowLabelKey,
} from './FinancePanels';
import { useMoney } from './finance-format';
import {
  overviewCategoryShares,
  overviewSeries,
  overviewStats,
  recentOperations,
  type FinanceCard,
  type FinancePeriod,
} from './finance-wallet';

const RECENT_LIMIT = 40;

export interface OverviewProps {
  entries: FinanceEntry[];
  cards: FinanceCard[];
  currencies: FinanceCurrency[];
  today: string;
  period: FinancePeriod;
  onPeriod: (period: FinancePeriod) => void;
  deleting: string | null;
  accountName: (entry: FinanceEntry) => string;
  nameOf: (card: FinanceCard) => string;
  onEditEntry: (entry: FinanceEntry) => void;
  onDeleteEntry: (entry: FinanceEntry) => void;
}

function CurrencySwitch({
  currencies,
  value,
  onChange,
}: {
  currencies: FinanceCurrency[];
  value: FinanceCurrency;
  onChange: (currency: FinanceCurrency) => void;
}) {
  const { t } = useI18n();
  if (currencies.length < 2) return null;
  return (
    <div className="fin-seg is-small" role="group" aria-label={t('Валюта для просмотра')}>
      {currencies.map((currency) => (
        <button
          key={currency}
          type="button"
          aria-pressed={value === currency}
          onClick={() => onChange(currency)}
        >
          {currency}
        </button>
      ))}
    </div>
  );
}

export function FinanceOverview(props: OverviewProps) {
  const { t } = useI18n();
  const { signed } = useMoney();
  const { entries, cards, currencies, today, period, onPeriod } = props;
  const [picked, setPicked] = useState<FinanceCurrency | null>(null);
  const currency = picked && currencies.includes(picked) ? picked : currencies[0];
  const stats = useMemo(
    () => overviewStats(entries, currency, period, today),
    [entries, currency, period, today],
  );
  const points = useMemo(
    () => overviewSeries(entries, cards, currency, period, today),
    [entries, cards, currency, period, today],
  );
  const shares = useMemo(
    () => overviewCategoryShares(entries, currency, period, today),
    [entries, currency, period, today],
  );
  const recent = useMemo(() => recentOperations(entries, RECENT_LIMIT), [entries]);
  const others = currencies.filter((item) => item !== currency);
  return (
    <div className="fin-right-stack">
      <ChartPanel
        title={t('Динамика средств')}
        subtitle={t('Только {currency}, без пересчёта валют', { currency })}
        period={period}
        onPeriod={onPeriod}
        points={points}
        currency={currency}
        signature={`ov|${currency}|${period}`}
        headExtra={<CurrencySwitch currencies={currencies} value={currency} onChange={setPicked} />}
        note={t('Средства в других валютах показаны отдельно и не складываются.')}
      />
      <KpiTiles
        currency={currency}
        tiles={statTiles(stats, { income: t('Доходы'), expense: t('Расходы'), net: t('Разница') })}
      />
      <p className="fin-note">
        {t('Показатели')} {t(windowLabelKey(period))}, {currency}.
        {others.map((other) => {
          const extra = overviewStats(entries, other, period, today);
          return (
            <span key={other} className="fin-note-line">
              {t('В {currency}: доходы {income} · расходы {expense} · разница {net}', {
                currency: other,
                income: signed(extra.incomeMinor, other),
                expense: signed(-extra.expenseMinor, other),
                net: signed(extra.incomeMinor - extra.expenseMinor, other),
              })}
            </span>
          );
        })}
        <span className="fin-note-line">
          {t('Переводы между своими счетами не считаются доходом или расходом.')}
        </span>
      </p>
      <div className="fin-two">
        <DistributionPanel cards={cards} currencies={currencies} nameOf={props.nameOf} />
        <CategoryPanel
          shares={shares}
          currency={currency}
          periodLabel={t(period === 'week' ? 'Неделя' : period === 'month' ? 'Месяц' : 'Год')}
        />
      </div>
      <FinanceHistory
        title={t('Последние операции')}
        entries={recent}
        today={today}
        showAccount
        deleting={props.deleting}
        accountName={props.accountName}
        onEdit={props.onEditEntry}
        onDelete={props.onDeleteEntry}
      />
    </div>
  );
}
