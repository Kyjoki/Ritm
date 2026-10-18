import { useEffect, useMemo, useState, type CSSProperties, type FormEvent } from 'react';
import {
  ArrowDownLeft,
  ArrowUpRight,
  Banknote,
  ChartNoAxesCombined,
  CirclePlus,
  Coins,
  ExternalLink,
  Landmark,
  LoaderCircle,
  Pencil,
  RefreshCw,
  Trash2,
  Wallet,
} from 'lucide-react';
import type { FinanceEntry, FinanceEntryInput } from '../../shared/types';
import { calculateAccountBalance } from '../../shared/finance';
import { Dialog } from '../components/Dialog';
import { api } from '../lib/api';
import { useI18n } from '../lib/i18n';
import '../styles/finance.css';

type Currency = FinanceEntry['currency'];
type Kind = FinanceEntry['type'];
type FinanceView = 'account' | 'deposits' | 'stocks' | 'all';
type FormState = {
  type: Kind;
  amount: string;
  currency: Currency;
  date: string;
  category: string;
  name: string;
  note: string;
  exchange: 'KASE' | 'AIX';
  ticker: string;
  quantity: string;
  unitPrice: string;
};

const currencies: Currency[] = ['KZT', 'USD', 'EUR', 'RUB'];
const swatches = Array.from({ length: 6 }, (_, index) => `var(--finance-chart-${index + 1})`);

function localDate() {
  const today = new Date();
  return `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;
}

function emptyForm(currency: Currency, type: Kind = 'expense'): FormState {
  return {
    type,
    amount: '',
    currency,
    date: localDate(),
    category: '',
    name: '',
    note: '',
    exchange: 'KASE',
    ticker: '',
    quantity: '',
    unitPrice: '',
  };
}

function quoteUrl(exchange: 'KASE' | 'AIX', ticker: string): string | null {
  if (!/^[A-Z0-9._-]{1,30}$/.test(ticker)) return null;
  return exchange === 'KASE'
    ? `https://kase.kz/en/investors/shares/${ticker}/`
    : `https://data-feed.aix.kz/symbol/${ticker}/trading`;
}

function parseMinor(value: string): number | null {
  const normalized = value
    .trim()
    .replace(/[\s\u00a0\u202f]/g, '')
    .replace(',', '.');
  if (!/^\d+(?:\.\d{1,2})?$/.test(normalized)) return null;
  const [units, fraction = ''] = normalized.split('.');
  const minor = Number(units) * 100 + Number(fraction.padEnd(2, '0'));
  return Number.isSafeInteger(minor) && minor >= 0 ? minor : null;
}

function monthKey(date: string) {
  return date.slice(0, 7);
}

function monthOffset(base: Date, offset: number) {
  const month = new Date(base.getFullYear(), base.getMonth() + offset, 1);
  return {
    key: `${month.getFullYear()}-${String(month.getMonth() + 1).padStart(2, '0')}`,
    date: month,
  };
}

function sectorBackground(values: number[]): string {
  const total = values.reduce((sum, value) => sum + value, 0);
  if (!total) return 'var(--ring-track)';
  let cursor = 0;
  const segments = values.map((value, index) => {
    const start = cursor;
    cursor += (value / total) * 100;
    return `${swatches[index % swatches.length]} ${start}% ${cursor}%`;
  });
  return `conic-gradient(${segments.join(', ')})`;
}

function Donut({
  items,
  center,
  caption,
  empty,
  format,
}: {
  items: { label: string; value: number }[];
  center: string;
  caption: string;
  empty: string;
  format: (minor: number) => string;
}) {
  const total = items.reduce((sum, item) => sum + item.value, 0);
  return (
    <div className="finance-donut-wrap">
      <div
        className="finance-donut"
        style={{ background: sectorBackground(items.map((item) => item.value)) }}
        role="img"
        aria-label={
          total ? items.map((item) => `${item.label}: ${format(item.value)}`).join(', ') : empty
        }
      >
        <div className="finance-donut-hole">
          <strong>{center}</strong>
          <span>{caption}</span>
        </div>
      </div>
      {total ? (
        <ul className="finance-legend">
          {items.map((item, index) => (
            <li key={`${item.label}-${index}`}>
              <span
                className="finance-legend-dot"
                style={{ '--finance-swatch': swatches[index % swatches.length] } as CSSProperties}
              />
              <span className="finance-legend-name">{item.label}</span>
              <strong>{format(item.value)}</strong>
            </li>
          ))}
        </ul>
      ) : (
        <p className="finance-chart-empty">{empty}</p>
      )}
    </div>
  );
}

export function FinancePage({ active = true }: { active?: boolean }) {
  const { locale, t } = useI18n();
  const [entries, setEntries] = useState<FinanceEntry[]>([]);
  const [currency, setCurrency] = useState<Currency>('KZT');
  const [view, setView] = useState<FinanceView>('account');
  const [selectedDepositId, setSelectedDepositId] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState('');
  const [form, setForm] = useState<FormState | null>(null);
  const [editing, setEditing] = useState<FinanceEntry | null>(null);
  const [saving, setSaving] = useState(false);
  const [formError, setFormError] = useState('');
  const [confirmDelete, setConfirmDelete] = useState<string | null>(null);
  const [deleting, setDeleting] = useState<string | null>(null);
  const [priceUpdate, setPriceUpdate] = useState<Extract<FinanceEntry, { type: 'stock' }> | null>(
    null,
  );
  const [priceInput, setPriceInput] = useState('');
  const [priceDate, setPriceDate] = useState(localDate());

  async function reload(initial = false) {
    if (initial) setLoading(true);
    else setRefreshing(true);
    setError('');
    try {
      const result = await api.finance();
      setEntries(result.entries);
    } catch (failure) {
      setError(
        failure instanceof Error ? failure.message : t('Не удалось загрузить финансовые данные.'),
      );
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }

  useEffect(() => {
    if (active) void reload(true);
  }, [active]);

  const money = (minor: number) =>
    new Intl.NumberFormat(locale, {
      style: 'currency',
      currency,
      minimumFractionDigits: minor % 100 ? 2 : 0,
      maximumFractionDigits: 2,
    }).format(minor / 100);
  const dateLabel = (value: string) =>
    new Intl.DateTimeFormat(locale, { day: 'numeric', month: 'short', year: 'numeric' }).format(
      new Date(`${value}T12:00:00`),
    );
  const categoryLabel = (value: string) => t(value);

  const visible = useMemo(
    () => entries.filter((entry) => entry.currency === currency),
    [entries, currency],
  );
  const transactions = visible.filter(
    (entry) => entry.type === 'income' || entry.type === 'expense',
  );
  const assets = visible.filter((entry) => entry.type === 'deposit' || entry.type === 'stock');
  const depositEntries = visible.filter((entry) => entry.type === 'deposit');
  const selectedDeposit = depositEntries.find((entry) => entry.id === selectedDepositId);
  const account = visible.find((entry) => entry.type === 'account');
  const accountBalance = calculateAccountBalance(visible, currency, localDate());
  const currentMonth = monthKey(localDate());
  const monthTransactions = transactions.filter((entry) => monthKey(entry.date) === currentMonth);
  const income = monthTransactions
    .filter((entry) => entry.type === 'income')
    .reduce((sum, entry) => sum + entry.amountMinor, 0);
  const expense = monthTransactions
    .filter((entry) => entry.type === 'expense')
    .reduce((sum, entry) => sum + entry.amountMinor, 0);
  const deposits = assets
    .filter((entry) => entry.type === 'deposit')
    .reduce((sum, entry) => sum + entry.valueMinor, 0);
  const stocks = assets
    .filter((entry) => entry.type === 'stock')
    .reduce((sum, entry) => sum + entry.valueMinor, 0);
  const assetTotal = deposits + stocks;
  const combinedTotal = accountBalance === null ? null : accountBalance + assetTotal;
  const sectionTotal =
    view === 'account'
      ? accountBalance
      : view === 'deposits'
        ? (selectedDeposit?.valueMinor ?? deposits)
        : view === 'stocks'
          ? stocks
          : combinedTotal;
  const sectionCount =
    view === 'account'
      ? transactions.length
      : view === 'deposits'
        ? selectedDeposit
          ? 1
          : depositEntries.length
        : view === 'stocks'
          ? assets.filter((entry) => entry.type === 'stock').length
          : visible.length;
  const expenseGroups = Object.entries(
    monthTransactions
      .filter((entry) => entry.type === 'expense')
      .reduce<Record<string, number>>((acc, entry) => {
        const category = categoryLabel(entry.category);
        acc[category] = (acc[category] ?? 0) + entry.amountMinor;
        return acc;
      }, {}),
  ).sort((a, b) => b[1] - a[1]);
  const expenseSlices = [
    ...expenseGroups.slice(0, 5).map(([label, value]) => ({ label, value })),
    ...(expenseGroups.length > 5
      ? [
          {
            label: t('Другое'),
            value: expenseGroups.slice(5).reduce((sum, [, value]) => sum + value, 0),
          },
        ]
      : []),
  ];
  const sectionAssets = assets.filter((entry) =>
    view === 'deposits' ? entry.type === 'deposit' : entry.type === 'stock',
  );
  const sortedAssets = [...sectionAssets].sort((a, b) => b.valueMinor - a.valueMinor);
  const sectionAssetSlices = [
    ...sortedAssets.slice(0, 5).map((entry) => ({ label: entry.name, value: entry.valueMinor })),
    ...(sortedAssets.length > 5
      ? [
          {
            label: t('Другое'),
            value: sortedAssets.slice(5).reduce((sum, entry) => sum + entry.valueMinor, 0),
          },
        ]
      : []),
  ];
  const sectionSlices =
    view === 'all'
      ? [
          { label: t('Основной счёт'), value: Math.max(0, accountBalance ?? 0) },
          { label: t('Депозиты'), value: deposits },
          { label: t('Акции'), value: stocks },
        ].filter((item) => item.value > 0)
      : sectionAssetSlices;
  const monthly = Array.from({ length: 6 }, (_, index) => monthOffset(new Date(), index - 5)).map(
    (month) => ({
      ...month,
      income: transactions
        .filter((entry) => entry.type === 'income' && monthKey(entry.date) === month.key)
        .reduce((sum, entry) => sum + entry.amountMinor, 0),
      expense: transactions
        .filter((entry) => entry.type === 'expense' && monthKey(entry.date) === month.key)
        .reduce((sum, entry) => sum + entry.amountMinor, 0),
    }),
  );
  const chartMax = Math.max(1, ...monthly.flatMap((month) => [month.income, month.expense]));
  const history = [...visible].sort(
    (a, b) =>
      ((b.type === 'income' || b.type === 'expense' ? b.date : b.asOf) || '').localeCompare(
        (a.type === 'income' || a.type === 'expense' ? a.date : a.asOf) || '',
      ) || b.createdAt.localeCompare(a.createdAt),
  );
  const records = history.filter(
    (entry) =>
      view === 'all' ||
      (view === 'account' &&
        (entry.type === 'account' ||
          ((entry.type === 'income' || entry.type === 'expense') &&
            (!account || (entry.date >= account.asOf && entry.date <= localDate()))))) ||
      (view === 'deposits' &&
        entry.type === 'deposit' &&
        (!selectedDeposit || entry.id === selectedDeposit.id)) ||
      (view === 'stocks' && entry.type === 'stock'),
  );

  function openNew(
    type: Kind = view === 'deposits' ? 'deposit' : view === 'stocks' ? 'stock' : 'expense',
  ) {
    setEditing(null);
    setForm(emptyForm(currency, type));
    setFormError('');
  }

  function openEdit(entry: FinanceEntry) {
    setEditing(entry);
    setForm({
      type: entry.type,
      amount: String(
        (entry.type === 'account' || entry.type === 'deposit' || entry.type === 'stock'
          ? entry.valueMinor
          : entry.amountMinor) / 100,
      ),
      currency: entry.currency,
      date:
        entry.type === 'account' || entry.type === 'deposit' || entry.type === 'stock'
          ? entry.asOf
          : entry.date,
      category: entry.type === 'income' || entry.type === 'expense' ? entry.category : '',
      name: entry.type === 'deposit' || entry.type === 'stock' ? entry.name : '',
      note: entry.note,
      exchange: entry.type === 'stock' ? (entry.exchange ?? 'KASE') : 'KASE',
      ticker: entry.type === 'stock' ? (entry.ticker ?? '') : '',
      quantity: entry.type === 'stock' && entry.quantity ? String(entry.quantity) : '',
      unitPrice:
        entry.type === 'stock' && entry.unitPriceMinor !== undefined
          ? String(entry.unitPriceMinor / 100)
          : '',
    });
    setFormError('');
  }

  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!form || saving) return;
    const isStockWithPrice = form.type === 'stock' && form.quantity.trim() !== '';
    const quantity = isStockWithPrice ? Number(form.quantity) : null;
    const unitPriceMinor = isStockWithPrice ? parseMinor(form.unitPrice) : null;
    const minor =
      isStockWithPrice && quantity && unitPriceMinor !== null
        ? quantity * unitPriceMinor
        : parseMinor(form.amount);
    if (
      minor === null ||
      !Number.isSafeInteger(minor) ||
      minor > 1_000_000_000_000 ||
      ((form.type === 'income' || form.type === 'expense') && minor === 0)
    ) {
      setFormError(
        t(
          form.type === 'income' || form.type === 'expense'
            ? 'Введите сумму больше нуля, максимум с двумя знаками после запятой.'
            : 'Введите стоимость от нуля, максимум с двумя знаками после запятой.',
        ),
      );
      return;
    }
    if (form.type === 'stock') {
      if (
        (!editing && !form.ticker.trim()) ||
        (form.ticker.trim() && !quoteUrl(form.exchange, form.ticker.trim().toUpperCase())) ||
        (!editing && !isStockWithPrice)
      ) {
        setFormError(t('Укажите биржу, тикер, количество и цену одной акции.'));
        return;
      }
      if (
        isStockWithPrice &&
        (!Number.isSafeInteger(quantity) ||
          !quantity ||
          quantity > 1_000_000_000 ||
          unitPriceMinor === null)
      ) {
        setFormError(t('Введите целое количество акций и цену с точностью до двух знаков.'));
        return;
      }
      if (!isStockWithPrice && form.unitPrice.trim()) {
        setFormError(t('Для цены одной акции укажите количество.'));
        return;
      }
    }
    const common = { currency: form.currency, note: form.note.trim() };
    const input: FinanceEntryInput =
      form.type === 'income' || form.type === 'expense'
        ? {
            type: form.type,
            amountMinor: minor,
            date: form.date,
            category: form.category.trim(),
            ...common,
          }
        : form.type === 'account'
          ? { type: 'account', valueMinor: minor, asOf: form.date, ...common }
          : form.type === 'stock'
            ? {
                type: 'stock',
                valueMinor: minor,
                asOf: form.date,
                name: form.name.trim(),
                ...(form.ticker.trim()
                  ? { exchange: form.exchange, ticker: form.ticker.trim().toUpperCase() }
                  : {}),
                ...(isStockWithPrice
                  ? { quantity: quantity!, unitPriceMinor: unitPriceMinor! }
                  : {}),
                ...common,
              }
            : {
                type: form.type,
                valueMinor: minor,
                asOf: form.date,
                name: form.name.trim(),
                ...common,
              };
    setSaving(true);
    setFormError('');
    try {
      const result = editing
        ? await api.updateFinanceEntry(editing.id, input, editing.updatedAt)
        : await api.createFinanceEntry(input);
      setEntries((current) =>
        editing
          ? current.map((entry) => (entry.id === editing.id ? result.entry : entry))
          : [result.entry, ...current],
      );
      setCurrency(result.entry.currency);
      if (!editing && result.entry.type === 'deposit') {
        setView('deposits');
        setSelectedDepositId(result.entry.id);
      }
      setForm(null);
      setEditing(null);
    } catch (failure) {
      setFormError(failure instanceof Error ? failure.message : t('Не удалось сохранить запись.'));
    } finally {
      setSaving(false);
    }
  }

  async function savePrice(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!priceUpdate || saving || !priceUpdate.quantity) return;
    const unitPriceMinor = parseMinor(priceInput);
    const valueMinor = unitPriceMinor === null ? null : unitPriceMinor * priceUpdate.quantity;
    if (
      valueMinor === null ||
      !Number.isSafeInteger(valueMinor) ||
      valueMinor > 1_000_000_000_000
    ) {
      setFormError(t('Введите цену с точностью до двух знаков.'));
      return;
    }
    setSaving(true);
    setFormError('');
    try {
      const { id, createdAt, updatedAt, ...input } = priceUpdate;
      const result = await api.updateFinanceEntry(
        id,
        { ...input, asOf: priceDate, unitPriceMinor: unitPriceMinor!, valueMinor },
        updatedAt,
      );
      setEntries((current) => current.map((entry) => (entry.id === id ? result.entry : entry)));
      setPriceUpdate(null);
    } catch (failure) {
      setFormError(failure instanceof Error ? failure.message : t('Не удалось сохранить запись.'));
    } finally {
      setSaving(false);
    }
  }

  async function remove(entry: FinanceEntry) {
    setDeleting(entry.id);
    setError('');
    try {
      await api.deleteFinanceEntry(entry.id, entry.updatedAt);
      setEntries((current) => current.filter((record) => record.id !== entry.id));
      if (entry.id === selectedDepositId) setSelectedDepositId(null);
      setConfirmDelete(null);
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : t('Не удалось удалить запись.'));
    } finally {
      setDeleting(null);
    }
  }

  return (
    <div className="finance-page">
      <header className="page-heading finance-heading">
        <div>
          <div className="page-eyebrow">{t('RITM · ЛИЧНЫЕ ФИНАНСЫ')}</div>
          <h1 className="gradient-title">{t('Финансы')}</h1>
          <p className="page-description">
            {t('Поступления, расходы и активы — в одной ясной картине.')}
          </p>
        </div>
        <div className="finance-toolbar">
          <label className="finance-currency-label">
            <span>{t('Валюта')}</span>
            <select
              aria-label={t('Валюта для просмотра')}
              value={currency}
              onChange={(event) => {
                setCurrency(event.target.value as Currency);
                setSelectedDepositId(null);
              }}
            >
              {currencies.map((item) => (
                <option key={item} value={item}>
                  {item}
                </option>
              ))}
            </select>
          </label>
          <button className="button button-primary" type="button" onClick={() => openNew()}>
            <CirclePlus size={17} /> {t('Добавить запись')}
          </button>
        </div>
      </header>

      <div className="finance-info-note">
        <Coins size={15} />
        {t('Все суммы вводятся вручную. Курсы валют и цены акций не обновляются автоматически.')}
      </div>
      {view === 'all' && (
        <div className="finance-info-note">
          <Wallet size={15} />
          {t(
            'Баланс счёта и оценки активов ведутся отдельно. Учитывайте переводы между ними вручную.',
          )}
        </div>
      )}
      <nav className="finance-views" aria-label={t('Разделы финансов')}>
        {(['account', 'deposits', 'stocks', 'all'] as FinanceView[]).map((item) => (
          <button
            key={item}
            type="button"
            className={view === item ? 'active' : ''}
            aria-pressed={view === item}
            onClick={() => setView(item)}
          >
            {t(
              item === 'account'
                ? 'Основной счёт'
                : item === 'deposits'
                  ? 'Депозиты'
                  : item === 'stocks'
                    ? 'Акции'
                    : 'Всё вместе',
            )}
          </button>
        ))}
      </nav>
      {view === 'deposits' && !loading && (
        <section className="finance-deposit-picker" aria-label={t('Выбрать депозит')}>
          <div className="finance-deposit-picker-heading">
            <strong>{t('Выбрать депозит')}</strong>
            <span>{t('Всего депозитов: {count}', { count: depositEntries.length })}</span>
          </div>
          <div className="finance-deposit-options">
            <button
              type="button"
              className={`finance-deposit-option ${!selectedDeposit ? 'active' : ''}`}
              aria-pressed={!selectedDeposit}
              onClick={() => setSelectedDepositId(null)}
            >
              <strong>{t('Все депозиты')}</strong>
              <span>{money(deposits)}</span>
            </button>
            {depositEntries.map((entry) => (
              <button
                type="button"
                key={entry.id}
                className={`finance-deposit-option ${selectedDeposit?.id === entry.id ? 'active' : ''}`}
                aria-pressed={selectedDeposit?.id === entry.id}
                onClick={() => setSelectedDepositId(entry.id)}
              >
                <strong>{entry.name}</strong>
                <span>{money(entry.valueMinor)}</span>
              </button>
            ))}
            <button
              type="button"
              className="finance-deposit-option finance-deposit-add"
              onClick={() => openNew('deposit')}
            >
              <CirclePlus size={16} /> {t('Добавить депозит')}
            </button>
          </div>
        </section>
      )}
      {error && (
        <div className="finance-alert" role="alert">
          {error}{' '}
          <button type="button" onClick={() => void reload()}>
            {t('Повторить')}
          </button>
        </div>
      )}
      {loading ? (
        <div className="panel finance-loading" role="status">
          <LoaderCircle className="spinning" size={20} /> {t('Загружаем финансы…')}
        </div>
      ) : !visible.length && view === 'all' ? (
        <div className="panel finance-empty finance-empty-page">
          <Coins size={28} />
          <strong>
            {entries.length
              ? t('Пока нет записей в {currency}', { currency })
              : t('Начните с первой записи')}
          </strong>
          <p>
            {t(
              'Добавьте поступление, расход, депозит или акции. Графики появятся по мере заполнения.',
            )}
          </p>
          <button type="button" className="button button-primary" onClick={() => openNew()}>
            {t('Добавить запись')}
          </button>
        </div>
      ) : (
        <>
          <section className="finance-top-grid" aria-label={t('Обзор финансов')}>
            <div className="finance-hero panel">
              <div className="finance-hero-top">
                <span>
                  {view === 'deposits' && selectedDeposit
                    ? selectedDeposit.name
                    : t(
                        view === 'account'
                          ? 'Основной счёт'
                          : view === 'deposits'
                            ? 'Депозиты'
                            : view === 'stocks'
                              ? 'Акции'
                              : 'Всего учтено',
                      )}
                </span>
                <Wallet size={21} />
              </div>
              <strong className="finance-hero-value">
                {sectionTotal === null ? '—' : money(sectionTotal)}
              </strong>
              <p>
                {t(
                  view === 'account'
                    ? 'Стартовый остаток плюс внесённые операции с выбранной даты.'
                    : view === 'all'
                      ? 'Счёт, депозиты и акции в выбранной валюте.'
                      : 'Стоимость по вашей последней ручной оценке.',
                )}
              </p>
              <div className="finance-hero-split">
                {view === 'account' && account ? (
                  <span>
                    {t('С {date} учтены все поступления и расходы.', {
                      date: dateLabel(account.asOf),
                    })}
                  </span>
                ) : null}
                {(view === 'account' || view === 'all') && !account ? (
                  <button
                    type="button"
                    className="finance-hero-action"
                    onClick={() => openNew('account')}
                  >
                    <CirclePlus size={16} /> {t('Задать стартовый остаток')}
                  </button>
                ) : null}
                {(view === 'account' || view === 'all') && account ? (
                  <button
                    type="button"
                    className="finance-hero-action"
                    onClick={() => openEdit(account)}
                  >
                    <Pencil size={15} /> {t('Изменить стартовый остаток')}
                  </button>
                ) : null}
                {view === 'deposits' && selectedDeposit ? (
                  <button
                    type="button"
                    className="finance-hero-action"
                    onClick={() => openEdit(selectedDeposit)}
                  >
                    <Pencil size={15} /> {t('Изменить депозит')}
                  </button>
                ) : null}
                {view === 'deposits' || view === 'stocks' ? (
                  <span>{t('Записей: {count}', { count: sectionCount })}</span>
                ) : null}
              </div>
            </div>
            <div className="finance-overview-tiles">
              <div className="panel finance-summary-tile">
                <span className="finance-tile-icon income">
                  {view === 'account' ? <ArrowDownLeft size={18} /> : <Wallet size={18} />}
                </span>
                <span className="finance-tile-label">
                  {t(
                    view === 'account'
                      ? 'Поступило за месяц'
                      : view === 'all'
                        ? 'Основной счёт'
                        : 'Позиций',
                  )}
                </span>
                <strong>
                  {view === 'account'
                    ? money(income)
                    : view === 'all'
                      ? accountBalance === null
                        ? '—'
                        : money(accountBalance)
                      : sectionCount}
                </strong>
              </div>
              <div className="panel finance-summary-tile">
                <span className="finance-tile-icon expense">
                  {view === 'account' ? <ArrowUpRight size={18} /> : <Landmark size={18} />}
                </span>
                <span className="finance-tile-label">
                  {t(
                    view === 'account'
                      ? 'Потрачено за месяц'
                      : view === 'all'
                        ? 'Депозиты'
                        : 'Сумма оценок',
                  )}
                </span>
                <strong>
                  {money(
                    view === 'account'
                      ? expense
                      : view === 'all'
                        ? deposits
                        : view === 'deposits'
                          ? (selectedDeposit?.valueMinor ?? deposits)
                          : stocks,
                  )}
                </strong>
              </div>
              <div className="panel finance-summary-tile finance-net-tile">
                <span className="finance-tile-icon net">
                  {view === 'all' ? <ChartNoAxesCombined size={18} /> : <Banknote size={18} />}
                </span>
                <span className="finance-tile-label">
                  {t(
                    view === 'account'
                      ? 'Разница за месяц'
                      : view === 'all'
                        ? 'Акции'
                        : 'Валюта просмотра',
                  )}
                </span>
                <strong>
                  {view === 'account'
                    ? money(income - expense)
                    : view === 'all'
                      ? money(stocks)
                      : currency}
                </strong>
              </div>
            </div>
          </section>

          {view === 'account' && (
            <section className="finance-chart-grid" aria-label={t('Финансовые графики')}>
              <div className="panel finance-chart-card finance-cash-chart">
                <div className="finance-card-heading">
                  <div>
                    <span>{t('Динамика')}</span>
                    <h2>{t('Деньги по месяцам')}</h2>
                  </div>
                  <div className="finance-chart-key">
                    <span className="income" />
                    {t('Поступления')}
                    <span className="expense" />
                    {t('Расходы')}
                  </div>
                </div>
                <div
                  className="finance-bars"
                  role="img"
                  aria-label={monthly
                    .map(
                      (month) =>
                        `${new Intl.DateTimeFormat(locale, { month: 'long', year: 'numeric' }).format(month.date)}: ${t('Поступления')} ${money(month.income)}, ${t('Расходы')} ${money(month.expense)}`,
                    )
                    .join('; ')}
                >
                  {monthly.map((month) => (
                    <div className="finance-month" key={month.key}>
                      <div className="finance-month-bars">
                        <span
                          className="finance-bar income"
                          style={{
                            height: `${Math.max(month.income ? 3 : 0, (month.income / chartMax) * 100)}%`,
                          }}
                          title={`${t('Поступления')}: ${money(month.income)}`}
                        />
                        <span
                          className="finance-bar expense"
                          style={{
                            height: `${Math.max(month.expense ? 3 : 0, (month.expense / chartMax) * 100)}%`,
                          }}
                          title={`${t('Расходы')}: ${money(month.expense)}`}
                        />
                      </div>
                      <span className="finance-month-label">
                        {new Intl.DateTimeFormat(locale, { month: 'short' }).format(month.date)}
                      </span>
                    </div>
                  ))}
                </div>
                {!transactions.length && (
                  <p className="finance-chart-empty">
                    {t('Добавьте поступление или расход — здесь появится динамика.')}
                  </p>
                )}
              </div>
              <div className="panel finance-chart-card">
                <div className="finance-card-heading">
                  <div>
                    <span>{t('Этот месяц')}</span>
                    <h2>{t('На что уходят деньги')}</h2>
                  </div>
                </div>
                <Donut
                  items={expenseSlices}
                  center={money(expense)}
                  caption={t('расходов')}
                  empty={t('Пока нет расходов за этот месяц.')}
                  format={money}
                />
              </div>
            </section>
          )}

          <section
            className={`finance-bottom-grid ${view === 'account' ? 'finance-records-only' : ''}`}
          >
            {view !== 'account' && (
              <div className="panel finance-chart-card">
                <div className="finance-card-heading">
                  <div>
                    <span>{t('Состав активов')}</span>
                    <h2>
                      {t(
                        view === 'all'
                          ? 'Где находятся деньги'
                          : view === 'deposits'
                            ? 'Все депозиты'
                            : 'Мои акции',
                      )}
                    </h2>
                  </div>
                </div>
                <Donut
                  items={sectionSlices}
                  center={money(
                    view === 'all'
                      ? Math.max(0, accountBalance ?? 0) + assetTotal
                      : view === 'deposits'
                        ? deposits
                        : (sectionTotal ?? 0),
                  )}
                  caption={t(view === 'deposits' ? 'всего в депозитах' : 'в активах')}
                  empty={t(
                    view === 'all'
                      ? 'Добавьте счёт, депозит или акции, чтобы увидеть распределение.'
                      : view === 'deposits'
                        ? 'Добавьте депозит, чтобы увидеть распределение.'
                        : 'Добавьте акции, чтобы увидеть распределение.',
                  )}
                  format={money}
                />
                {view === 'all' && accountBalance !== null && accountBalance < 0 && (
                  <p className="finance-chart-empty">
                    {t(
                      'Отрицательный остаток счёта показан в общем итоге, но не в круговой диаграмме.',
                    )}
                  </p>
                )}
              </div>
            )}
            <div className="panel finance-records">
              <div className="finance-card-heading">
                <div>
                  <span>{t('Ваши записи')}</span>
                  <h2>
                    {view === 'deposits' && selectedDeposit
                      ? selectedDeposit.name
                      : t(
                          view === 'account'
                            ? 'Операции основного счёта'
                            : view === 'deposits'
                              ? 'Мои депозиты'
                              : view === 'stocks'
                                ? 'Мои акции'
                                : 'Операции и активы',
                        )}
                  </h2>
                </div>
                <button
                  type="button"
                  className="finance-refresh"
                  onClick={() => void reload()}
                  disabled={refreshing}
                  aria-label={t('Обновить финансы')}
                  title={t('Обновить финансы')}
                >
                  <RefreshCw className={refreshing ? 'spinning' : ''} size={17} />
                </button>
              </div>
              {records.length ? (
                <ul className="finance-record-list">
                  {records.map((entry) => {
                    const isAsset =
                      entry.type === 'account' ||
                      entry.type === 'deposit' ||
                      entry.type === 'stock';
                    const amount = isAsset ? entry.valueMinor : entry.amountMinor;
                    const label =
                      entry.type === 'account'
                        ? t('Стартовый остаток')
                        : entry.type === 'deposit' || entry.type === 'stock'
                          ? entry.name
                          : categoryLabel(entry.category);
                    const date = isAsset ? entry.asOf : entry.date;
                    const Icon =
                      entry.type === 'income'
                        ? ArrowDownLeft
                        : entry.type === 'expense'
                          ? ArrowUpRight
                          : entry.type === 'account'
                            ? Wallet
                            : entry.type === 'deposit'
                              ? Landmark
                              : ChartNoAxesCombined;
                    return (
                      <li key={entry.id} className="finance-record">
                        <span className={`finance-record-icon ${entry.type}`}>
                          <Icon size={17} />
                        </span>
                        <span className="finance-record-main">
                          <strong>{label}</strong>
                          <span>
                            {t(
                              entry.type === 'income'
                                ? 'Поступление'
                                : entry.type === 'expense'
                                  ? 'Расход'
                                  : entry.type === 'account'
                                    ? 'Основной счёт'
                                    : entry.type === 'deposit'
                                      ? 'Депозит'
                                      : 'Акции',
                            )}{' '}
                            · {dateLabel(date)}
                            {entry.note ? ` · ${entry.note}` : ''}
                          </span>
                          {entry.type === 'stock' && (
                            <span className="finance-stock-details">
                              {entry.quantity && entry.unitPriceMinor !== undefined
                                ? `${entry.quantity} × ${money(entry.unitPriceMinor)}`
                                : t('Ручная оценка')}
                              {entry.exchange &&
                                entry.ticker &&
                                quoteUrl(entry.exchange, entry.ticker) && (
                                  <a
                                    href={quoteUrl(entry.exchange, entry.ticker)!}
                                    target="_blank"
                                    rel="noopener noreferrer"
                                  >
                                    {entry.exchange} · {entry.ticker}{' '}
                                    <ExternalLink size={12} aria-hidden="true" />
                                  </a>
                                )}
                            </span>
                          )}
                        </span>
                        <strong className={`finance-record-money ${entry.type}`}>
                          {entry.type === 'income' ? '+' : entry.type === 'expense' ? '−' : ''}
                          {money(amount)}
                        </strong>
                        <span className="finance-record-actions">
                          {confirmDelete === entry.id ? (
                            <>
                              <button
                                type="button"
                                className="finance-delete-confirm"
                                onClick={() => void remove(entry)}
                                disabled={deleting === entry.id}
                              >
                                {deleting === entry.id ? t('Удаляем…') : t('Удалить?')}
                              </button>
                              <button type="button" onClick={() => setConfirmDelete(null)}>
                                {t('Отмена')}
                              </button>
                            </>
                          ) : (
                            <>
                              {entry.type === 'stock' && entry.quantity && (
                                <button
                                  type="button"
                                  className="finance-price-action"
                                  onClick={() => {
                                    setPriceUpdate(entry);
                                    setPriceInput(
                                      entry.unitPriceMinor !== undefined
                                        ? String(entry.unitPriceMinor / 100)
                                        : '',
                                    );
                                    setPriceDate(localDate());
                                    setFormError('');
                                  }}
                                >
                                  {t('Обновить цену')}
                                </button>
                              )}
                              <button
                                type="button"
                                aria-label={`${t('Изменить')} ${label}`}
                                title={t('Изменить')}
                                onClick={() => openEdit(entry)}
                              >
                                <Pencil size={15} />
                              </button>
                              <button
                                type="button"
                                aria-label={`${t('Удалить')} ${label}`}
                                title={t('Удалить')}
                                onClick={() => setConfirmDelete(entry.id)}
                              >
                                <Trash2 size={15} />
                              </button>
                            </>
                          )}
                        </span>
                      </li>
                    );
                  })}
                </ul>
              ) : (
                <div className="finance-empty">
                  <Coins size={24} />
                  <strong>{t('Пока нет записей в {currency}', { currency })}</strong>
                  <p>
                    {t(
                      view === 'account'
                        ? 'Задайте стартовый остаток или добавьте операцию.'
                        : view === 'deposits'
                          ? 'Добавьте первый депозит.'
                          : view === 'stocks'
                            ? 'Добавьте первые акции.'
                            : 'Добавьте первое поступление, расход или актив.',
                    )}
                  </p>
                  <button
                    type="button"
                    className="button button-secondary"
                    onClick={() =>
                      openNew(
                        view === 'account' && !account
                          ? 'account'
                          : view === 'deposits'
                            ? 'deposit'
                            : view === 'stocks'
                              ? 'stock'
                              : 'expense',
                      )
                    }
                  >
                    {t(
                      view === 'account' && !account
                        ? 'Задать стартовый остаток'
                        : 'Добавить запись',
                    )}
                  </button>
                </div>
              )}
            </div>
          </section>
        </>
      )}

      {form && (
        <Dialog
          title={editing ? t('Изменить запись') : t('Новая запись')}
          onClose={() => {
            setForm(null);
            setEditing(null);
          }}
          busy={saving}
          className="finance-dialog"
        >
          <form onSubmit={(event) => void save(event)} className="finance-form">
            <fieldset className="finance-type-switch" disabled={Boolean(editing) || saving}>
              <legend>{t('Тип записи')}</legend>
              {(['expense', 'income', 'account', 'deposit', 'stock'] as Kind[]).map((kind) => (
                <button
                  key={kind}
                  type="button"
                  aria-pressed={form.type === kind}
                  disabled={
                    !editing &&
                    kind === 'account' &&
                    entries.some(
                      (entry) => entry.type === 'account' && entry.currency === form.currency,
                    )
                  }
                  onClick={() => setForm({ ...form, type: kind, category: '', name: '' })}
                >
                  {t(
                    kind === 'expense'
                      ? 'Расход'
                      : kind === 'income'
                        ? 'Поступление'
                        : kind === 'account'
                          ? 'Основной счёт'
                          : kind === 'deposit'
                            ? 'Депозит'
                            : 'Акции',
                  )}
                </button>
              ))}
            </fieldset>
            <div className="form-grid">
              {form.type !== 'stock' && (
                <label className="field">
                  <span>
                    {t(
                      form.type === 'account'
                        ? 'Стартовый остаток'
                        : form.type === 'income' || form.type === 'expense'
                          ? 'Сумма'
                          : 'Текущая стоимость',
                    )}
                  </span>
                  <input
                    required
                    inputMode="decimal"
                    autoComplete="off"
                    placeholder="0,00"
                    value={form.amount}
                    onChange={(event) => setForm({ ...form, amount: event.target.value })}
                    disabled={saving}
                  />
                </label>
              )}
              <label className="field">
                <span>{t('Валюта')}</span>
                <select
                  value={form.currency}
                  onChange={(event) =>
                    setForm({ ...form, currency: event.target.value as Currency })
                  }
                  disabled={saving || (Boolean(editing) && form.type === 'account')}
                >
                  {currencies.map((item) => (
                    <option key={item} value={item}>
                      {item}
                    </option>
                  ))}
                </select>
              </label>
            </div>
            {form.type === 'income' || form.type === 'expense' ? (
              <label className="field">
                <span>{t('Категория')}</span>
                <input
                  required
                  maxLength={80}
                  list="finance-categories"
                  value={form.category}
                  onChange={(event) => setForm({ ...form, category: event.target.value })}
                  placeholder={t('Например, зарплата или продукты')}
                  disabled={saving}
                />
                <datalist id="finance-categories">
                  {(form.type === 'income'
                    ? ['Зарплата', 'Подработка', 'Подарок', 'Проценты']
                    : ['Продукты', 'Кафе', 'Транспорт', 'Дом', 'Здоровье', 'Покупки', 'Развлечения']
                  ).map((label) => (
                    <option key={label} value={label} label={t(label)} />
                  ))}
                </datalist>
              </label>
            ) : form.type === 'account' ? (
              <p className="finance-account-help">
                {t(
                  'Укажите остаток на начало выбранного дня. Все внесённые поступления и расходы с этого дня меняют расчётный баланс.',
                )}
              </p>
            ) : (
              <label className="field">
                <span>{t('Название')}</span>
                <input
                  required
                  maxLength={100}
                  value={form.name}
                  onChange={(event) => setForm({ ...form, name: event.target.value })}
                  placeholder={
                    form.type === 'deposit' ? t('Название вклада') : t('Название акции или фонда')
                  }
                  disabled={saving}
                />
              </label>
            )}
            {form.type === 'stock' && (
              <div className="finance-stock-form">
                <div className="form-grid">
                  <label className="field">
                    <span>{t('Биржа')}</span>
                    <select
                      value={form.exchange}
                      onChange={(event) =>
                        setForm({ ...form, exchange: event.target.value as 'KASE' | 'AIX' })
                      }
                      disabled={saving}
                    >
                      <option value="KASE">KASE</option>
                      <option value="AIX">AIX</option>
                    </select>
                  </label>
                  <label className="field">
                    <span>{t('Тикер')}</span>
                    <input
                      required={!editing}
                      maxLength={30}
                      value={form.ticker}
                      onChange={(event) =>
                        setForm({ ...form, ticker: event.target.value.toUpperCase() })
                      }
                      placeholder="HSBK"
                      disabled={saving}
                    />
                  </label>
                </div>
                <div className="form-grid">
                  <label className="field">
                    <span>{t('Количество акций')}</span>
                    <input
                      required={!editing || Boolean(form.unitPrice)}
                      inputMode="numeric"
                      value={form.quantity}
                      onChange={(event) => setForm({ ...form, quantity: event.target.value })}
                      placeholder="10"
                      disabled={saving}
                    />
                  </label>
                  <label className="field">
                    <span>{t('Цена одной акции')}</span>
                    <input
                      required={!editing || Boolean(form.quantity)}
                      inputMode="decimal"
                      value={form.unitPrice}
                      onChange={(event) => setForm({ ...form, unitPrice: event.target.value })}
                      placeholder="0,00"
                      disabled={saving}
                    />
                  </label>
                </div>
                {form.quantity &&
                  form.unitPrice &&
                  parseMinor(form.unitPrice) !== null &&
                  Number.isSafeInteger(Number(form.quantity)) &&
                  Number(form.quantity) > 0 && (
                    <p className="finance-stock-total">
                      {t('Стоимость позиции')}:{' '}
                      {new Intl.NumberFormat(locale, {
                        style: 'currency',
                        currency: form.currency,
                      }).format((Number(form.quantity) * parseMinor(form.unitPrice)!) / 100)}
                    </p>
                  )}
                {editing && editing.type === 'stock' && !editing.quantity && !form.quantity && (
                  <label className="field">
                    <span>{t('Прежняя ручная оценка')}</span>
                    <input
                      required
                      inputMode="decimal"
                      value={form.amount}
                      onChange={(event) => setForm({ ...form, amount: event.target.value })}
                      disabled={saving}
                    />
                  </label>
                )}
                {form.ticker && quoteUrl(form.exchange, form.ticker.trim()) && (
                  <a
                    className="finance-quote-link"
                    href={quoteUrl(form.exchange, form.ticker.trim())!}
                    target="_blank"
                    rel="noopener noreferrer"
                  >
                    {t('Посмотреть котировку на сайте биржи')}{' '}
                    <ExternalLink size={14} aria-hidden="true" />
                  </a>
                )}
                <p className="finance-account-help">
                  {t(
                    'Цену вы вводите вручную после проверки на сайте биржи. Показываем дату вашей оценки.',
                  )}
                </p>
                <p className="finance-account-help">
                  {t('Выбирайте валюту, в которой биржа показывает цену этой акции.')}
                </p>
              </div>
            )}
            <label className="field">
              <span>
                {form.type === 'income' || form.type === 'expense'
                  ? t('Дата операции')
                  : t(form.type === 'account' ? 'Дата начала учёта' : 'Дата оценки')}
              </span>
              <input
                required
                type="date"
                value={form.date}
                max={form.type === 'account' ? localDate() : undefined}
                onChange={(event) => setForm({ ...form, date: event.target.value })}
                disabled={saving}
              />
            </label>
            <label className="field">
              <span>
                {t('Заметка')} <span className="finance-optional">{t('необязательно')}</span>
              </span>
              <textarea
                rows={2}
                maxLength={400}
                value={form.note}
                onChange={(event) => setForm({ ...form, note: event.target.value })}
                placeholder={t('Добавьте контекст для себя')}
                disabled={saving}
              />
            </label>
            {formError && (
              <p className="finance-form-error" role="alert">
                {formError}
              </p>
            )}
            <div className="dialog-actions">
              <button
                type="button"
                className="button button-secondary"
                onClick={() => {
                  setForm(null);
                  setEditing(null);
                }}
                disabled={saving}
              >
                {t('Отмена')}
              </button>
              <button type="submit" className="button button-primary" disabled={saving}>
                {saving && <LoaderCircle size={16} className="spinning" />}
                {editing ? t('Сохранить изменения') : t('Добавить запись')}
              </button>
            </div>
          </form>
        </Dialog>
      )}
      {priceUpdate && (
        <Dialog
          title={t('Обновить цену акции')}
          onClose={() => setPriceUpdate(null)}
          busy={saving}
          className="finance-dialog"
        >
          <form onSubmit={(event) => void savePrice(event)} className="finance-form">
            <strong>
              {priceUpdate.name} · {priceUpdate.quantity} {t('шт.')}
            </strong>
            {priceUpdate.exchange &&
              priceUpdate.ticker &&
              quoteUrl(priceUpdate.exchange, priceUpdate.ticker) && (
                <a
                  className="finance-quote-link"
                  href={quoteUrl(priceUpdate.exchange, priceUpdate.ticker)!}
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  {t('Посмотреть котировку на сайте биржи')}{' '}
                  <ExternalLink size={14} aria-hidden="true" />
                </a>
              )}
            <div className="form-grid">
              <label className="field">
                <span>
                  {t('Цена одной акции')} · {priceUpdate.currency}
                </span>
                <input
                  required
                  autoFocus
                  inputMode="decimal"
                  value={priceInput}
                  onChange={(event) => setPriceInput(event.target.value)}
                  disabled={saving}
                />
              </label>
              <label className="field">
                <span>{t('Дата оценки')}</span>
                <input
                  required
                  type="date"
                  max={localDate()}
                  value={priceDate}
                  onChange={(event) => setPriceDate(event.target.value)}
                  disabled={saving}
                />
              </label>
            </div>
            {formError && (
              <p className="finance-form-error" role="alert">
                {formError}
              </p>
            )}
            <div className="dialog-actions">
              <button
                type="button"
                className="button button-secondary"
                onClick={() => setPriceUpdate(null)}
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
      )}
    </div>
  );
}
