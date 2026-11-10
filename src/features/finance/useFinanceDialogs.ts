import { useMemo, useState, type FormEvent } from 'react';
import type { FinanceEntry } from '../../../shared/types';
import type { FormGroup } from './FinanceEntryForm';
import type { PricedStock } from './FinancePriceDialog';
import {
  buildEntryInput,
  emptyForm,
  formFromEntry,
  localDate,
  parseMinor,
  type Currency,
  type FormState,
  type Kind,
  type Translate,
} from './finance-form';
import type { FinanceCard } from './finance-wallet';
import type { useFinanceData } from './useFinanceData';

const MAX_MINOR = 1_000_000_000_000;
const ASSET_KINDS: Kind[] = ['account', 'deposit', 'stock'];

export type DialogState = {
  form: FormState;
  group: FormGroup;
  editing: FinanceEntry | null;
} | null;
export type PriceState = { stock: PricedStock; price: string; date: string } | null;

interface Context {
  entries: FinanceEntry[];
  cards: FinanceCard[];
  selected: FinanceCard | null;
  currencies: Currency[];
  today: string;
  data: ReturnType<typeof useFinanceData>;
  t: Translate;
  onCreated: (cardId: string) => void;
}

/** The entry dialog and the stock price dialog: opening, validation and saving. */
export function useFinanceDialogs(ctx: Context) {
  const { entries, cards, selected, currencies, today, data, t, onCreated } = ctx;
  const [dialog, setDialog] = useState<DialogState>(null);
  const [price, setPrice] = useState<PriceState>(null);
  const [formError, setFormError] = useState('');
  const defaultCurrency: Currency = selected?.currency ?? currencies[0] ?? 'KZT';

  const transferAccounts = useMemo(
    () =>
      entries.filter(
        (entry): entry is Extract<FinanceEntry, { type: 'account' | 'deposit' }> =>
          (entry.type === 'account' || entry.type === 'deposit') &&
          entry.currency === dialog?.form.currency,
      ),
    [entries, dialog?.form.currency],
  );

  const open = (form: FormState, group: FormGroup, editing: FinanceEntry | null = null) => {
    setFormError('');
    setDialog({ form, group, editing });
  };
  const openOperation = (card: FinanceCard | null = selected) => {
    const accountId = card?.kind === 'deposit' ? card.id : '';
    const form = { ...emptyForm(card?.currency ?? defaultCurrency, 'expense'), accountId };
    open({ ...form, date: today }, 'operation');
  };
  const openTransfer = (from = '', to = '') => {
    const currency =
      cards.find((card) => card.id === from || card.id === to)?.currency ?? defaultCurrency;
    const main = cards.find((card) => card.kind === 'account' && card.currency === currency);
    const other = cards.find((card) => card.kind === 'deposit' && card.currency === currency);
    const picked =
      selected?.kind === 'deposit' && selected.currency === currency ? selected : other;
    const form = { ...emptyForm(currency, 'transfer'), date: today };
    open(
      { ...form, fromAccountId: from || main?.id || '', toAccountId: to || picked?.id || '' },
      'operation',
    );
  };
  const openAsset = (type?: Kind, currency: Currency = defaultCurrency) => {
    const hasMain = cards.some((card) => card.kind === 'account' && card.currency === currency);
    const kind = type ?? (hasMain ? 'deposit' : 'account');
    open({ ...emptyForm(currency, kind), date: today }, 'asset');
  };
  const openEdit = (entry: FinanceEntry) =>
    open(formFromEntry(entry), ASSET_KINDS.includes(entry.type) ? 'asset' : 'operation', entry);
  const openPrice = (stock: PricedStock) => {
    setFormError('');
    const current = stock.unitPriceMinor === undefined ? '' : String(stock.unitPriceMinor / 100);
    setPrice({ stock, price: current, date: localDate() });
  };

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!dialog || data.saving) return;
    const ids = transferAccounts.map((entry) => entry.id);
    const built = buildEntryInput(dialog.form, dialog.editing, entries, ids, t);
    if ('error' in built) return setFormError(built.error);
    setFormError('');
    const outcome = await data.saveEntry(built.input, dialog.editing);
    if (!outcome.ok) return setFormError(outcome.message);
    const saved = outcome.result.entry;
    if (!dialog.editing && (saved.type === 'deposit' || saved.type === 'account'))
      onCreated(saved.id);
    if (!dialog.editing && saved.type === 'stock') onCreated(`stocks-${saved.currency}`);
    setDialog(null);
  }

  async function submitPrice(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!price || data.saving || !price.stock.quantity) return;
    const unitPriceMinor = parseMinor(price.price);
    const valueMinor = unitPriceMinor === null ? null : unitPriceMinor * price.stock.quantity;
    if (
      unitPriceMinor === null ||
      valueMinor === null ||
      !Number.isSafeInteger(valueMinor) ||
      valueMinor > MAX_MINOR
    )
      return setFormError(t('Введите цену с точностью до двух знаков.'));
    const { id: _id, createdAt: _created, updatedAt: _updated, ...input } = price.stock;
    const next = { ...input, asOf: price.date, unitPriceMinor, valueMinor };
    const outcome = await data.saveEntry(next, price.stock);
    if (!outcome.ok) return setFormError(outcome.message);
    setPrice(null);
  }

  return {
    dialog,
    price,
    formError,
    transferAccounts,
    setDialog,
    setPrice,
    openOperation,
    openTransfer,
    openAsset,
    openEdit,
    openPrice,
    openStock: (currency: Currency) => openAsset('stock', currency),
    submit,
    submitPrice,
  };
}
