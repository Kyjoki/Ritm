import type { FormEvent } from 'react';
import { ExternalLink } from 'lucide-react';
import type { FinanceEntry } from '../../../shared/types';
import { Dialog } from '../../components/Dialog';
import { useI18n } from '../../lib/i18n';
import { quoteUrl } from './finance-form';

export type PricedStock = Extract<FinanceEntry, { type: 'stock' }>;

/** Updates the price of one stock position (value = quantity × price). */
export function PriceDialog({
  stock,
  price,
  date,
  today,
  saving,
  error,
  onPrice,
  onDate,
  onSubmit,
  onClose,
}: {
  stock: PricedStock;
  price: string;
  date: string;
  today: string;
  saving: boolean;
  error: string;
  onPrice: (value: string) => void;
  onDate: (value: string) => void;
  onSubmit: (event: FormEvent<HTMLFormElement>) => void;
  onClose: () => void;
}) {
  const { t } = useI18n();
  const link = stock.exchange && stock.ticker ? quoteUrl(stock.exchange, stock.ticker) : null;
  return (
    <Dialog
      title={t('Обновить цену акции')}
      onClose={onClose}
      busy={saving}
      className="finance-dialog fin-dialog"
    >
      <form onSubmit={onSubmit} className="fin-form">
        <strong>
          {stock.name} · {stock.quantity} {t('шт.')}
        </strong>
        {link && (
          <a className="fin-link-out" href={link} target="_blank" rel="noopener noreferrer">
            {t('Посмотреть котировку на сайте биржи')} <ExternalLink size={14} aria-hidden="true" />
          </a>
        )}
        <div className="fin-grid">
          <div className="fin-field">
            <label htmlFor="fin-price">
              {t('Цена одной акции')} · {stock.currency}
            </label>
            <input
              id="fin-price"
              required
              autoFocus
              inputMode="decimal"
              value={price}
              onChange={(event) => onPrice(event.target.value)}
              disabled={saving}
            />
          </div>
          <div className="fin-field">
            <label htmlFor="fin-price-date">{t('Дата оценки')}</label>
            <input
              id="fin-price-date"
              required
              type="date"
              max={today}
              value={date}
              onChange={(event) => onDate(event.target.value)}
              disabled={saving}
            />
          </div>
        </div>
        {error && (
          <p className="fin-error" role="alert">
            {error}
          </p>
        )}
        <div className="dialog-actions">
          <button
            type="button"
            className="button button-secondary"
            data-dialog-dismiss
            disabled={saving}
          >
            {t('Отмена')}
          </button>
          <button type="submit" className="button button-primary" disabled={saving}>
            {t('Сохранить изменения')}
          </button>
        </div>
      </form>
    </Dialog>
  );
}
