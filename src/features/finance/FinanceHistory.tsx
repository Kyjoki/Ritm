import { useMemo, useState, type CSSProperties } from 'react';
import { Inbox } from 'lucide-react';
import type { FinanceEntry } from '../../../shared/types';
import { useI18n } from '../../lib/i18n';
import { RowActions } from './FinanceRowActions';
import { CategoryIcon, TransferIcon, useDayLabel, useMoney } from './finance-format';
import { applyHistoryFilter, groupByDay, type HistoryFilter } from './finance-history';

const COLLAPSED_LIMIT = 6;
const FILTERS: readonly (readonly [HistoryFilter, string])[] = [
  ['all', 'Все'],
  ['expense', 'Расходы'],
  ['income', 'Поступления'],
  ['transfer', 'Переводы'],
];

export interface HistoryProps {
  title: string;
  entries: FinanceEntry[];
  today: string;
  /** Show the account name in each row (overview) instead of the note. */
  showAccount: boolean;
  /** Entries of this id are being deleted right now. */
  deleting: string | null;
  accountName: (entry: FinanceEntry) => string;
  onEdit: (entry: FinanceEntry) => void;
  onDelete: (entry: FinanceEntry) => Promise<void> | void;
  action?: React.ReactNode;
}

type Row = Extract<FinanceEntry, { type: 'income' | 'expense' | 'transfer' }>;
const isRow = (entry: FinanceEntry): entry is Row =>
  entry.type === 'income' || entry.type === 'expense' || entry.type === 'transfer';

function HistoryRow({
  entry,
  index,
  today,
  showAccount,
  confirming,
  deleting,
  accountName,
  onConfirm,
  onEdit,
  onDelete,
}: {
  entry: Row;
  index: number;
  today: string;
  showAccount: boolean;
  confirming: boolean;
  deleting: boolean;
  accountName: (entry: FinanceEntry) => string;
  onConfirm: (id: string | null) => void;
  onEdit: () => void;
  onDelete: () => Promise<void> | void;
}) {
  const { t } = useI18n();
  const { money } = useMoney();
  const isTransfer = entry.type === 'transfer';
  const title = isTransfer ? t('Перевод') : t(entry.category);
  const kind = t(isTransfer ? 'Перевод' : entry.type === 'income' ? 'Поступление' : 'Расход');
  const parts = [
    isTransfer ? accountName(entry) : showAccount ? accountName(entry) : kind,
    entry.note,
    isTransfer && entry.date > today ? t('Запланировано: пока не влияет на остатки') : '',
  ].filter(Boolean);
  const sign = entry.type === 'income' ? '+' : entry.type === 'expense' ? '−' : '';
  return (
    <li className="fin-row" style={{ '--i': Math.min(index, 9) } as CSSProperties}>
      <span className={`fin-row-ic is-${entry.type}`}>
        {isTransfer ? <TransferIcon /> : <CategoryIcon category={entry.category} />}
      </span>
      <span className="fin-row-main">
        <strong>{title}</strong>
        <span>{parts.join(' · ')}</span>
      </span>
      <span className={`fin-row-amount is-${entry.type}`}>
        {sign}
        {money(entry.amountMinor, entry.currency)}
      </span>
      <RowActions
        label={title}
        confirming={confirming}
        deleting={deleting}
        onAskDelete={() => onConfirm(entry.id)}
        onCancel={() => onConfirm(null)}
        onEdit={onEdit}
        onDelete={onDelete}
      />
    </li>
  );
}

export function FinanceHistory(props: HistoryProps) {
  const { title, entries, today, showAccount, deleting, accountName, onEdit, onDelete, action } =
    props;
  const { t, language } = useI18n();
  const [filter, setFilter] = useState<HistoryFilter>('all');
  const [expanded, setExpanded] = useState(false);
  const [confirming, setConfirming] = useState<string | null>(null);
  const operations = useMemo(() => entries.filter(isRow), [entries]);
  const filtered = useMemo(() => applyHistoryFilter(operations, filter), [operations, filter]);
  const shown = expanded ? filtered : filtered.slice(0, COLLAPSED_LIMIT);
  const days = useMemo(() => groupByDay(shown, today, language), [shown, today, language]);
  const { short } = useDayLabel();
  let rowIndex = 0;
  return (
    <section className="fin-panel fin-history" aria-label={title}>
      <div className="fin-panel-head">
        <h2>{title}</h2>
        {action}
      </div>
      {operations.length > 0 && (
        <div className="fin-seg is-wide" role="group" aria-label={t('Тип операций')}>
          {FILTERS.map(([value, label]) => (
            <button
              key={value}
              type="button"
              aria-pressed={filter === value}
              onClick={() => {
                setFilter(value);
                setExpanded(false);
              }}
            >
              {t(label)}
            </button>
          ))}
        </div>
      )}
      {days.length ? (
        <div className="fin-days" key={filter}>
          {days.map((day) => (
            <div className="fin-day" key={day.key || 'none'}>
              <div className="fin-day-gutter" role="heading" aria-level={3}>
                <b>{day.dayNumber || '—'}</b>
                <span>
                  {day.relative
                    ? t(day.relative === 'today' ? 'Сегодня' : 'Вчера')
                    : day.key
                      ? day.month
                      : t('Без даты')}
                </span>
                <span>{day.relative ? `${short(day.key)}, ${day.weekday}` : day.weekday}</span>
              </div>
              <div className="fin-day-rail" aria-hidden="true" />
              <ul className="fin-day-rows">
                {day.entries.filter(isRow).map((entry) => (
                  <HistoryRow
                    key={entry.id}
                    entry={entry}
                    index={rowIndex++}
                    today={today}
                    showAccount={showAccount}
                    confirming={confirming === entry.id}
                    deleting={deleting === entry.id}
                    accountName={accountName}
                    onConfirm={setConfirming}
                    onEdit={() => onEdit(entry)}
                    onDelete={() => onDelete(entry)}
                  />
                ))}
              </ul>
            </div>
          ))}
        </div>
      ) : (
        <div className="fin-empty">
          <span className="fin-empty-ic">
            <Inbox size={26} aria-hidden="true" />
          </span>
          <b>{t(operations.length ? 'Нет таких операций' : 'Операций пока нет')}</b>
          <p>
            {t(
              operations.length
                ? 'Выберите другой тип.'
                : 'Поступления, расходы и переводы появятся здесь.',
            )}
          </p>
        </div>
      )}
      {filtered.length > COLLAPSED_LIMIT && (
        <button type="button" className="fin-link" onClick={() => setExpanded(!expanded)}>
          {expanded ? t('Свернуть') : t('Показать все ({count})', { count: filtered.length })}
        </button>
      )}
    </section>
  );
}
