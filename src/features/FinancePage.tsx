import {
  MotionBar,
  MotionList,
  MotionNumber,
  useMotionValues,
  useMotionNumber,
} from '../components/Motion';
import {
  memo,
  useEffect,
  useMemo,
  useRef,
  useState,
  type CSSProperties,
  type FormEvent,
} from 'react';
import {
  ArrowDownLeft,
  ArrowRightLeft,
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
import { calculateAccountBalance, calculateDepositBalance } from '../../shared/finance';
import { Dialog } from '../components/Dialog';
import { api } from '../lib/api';
import { LatestRead, RefreshGate } from '../lib/latest-read';
import { dateTimeFormatter, numberFormatter } from '../lib/intl-formatters';
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
  purchasePrice: string;
  fromAccountId: string;
  toAccountId: string;
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
    purchasePrice: '',
    fromAccountId: '',
    toAccountId: '',
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
  const animatedValues = useMotionValues(
    items.map((item) => item.value),
    true,
    false,
  );
  const sweep = useMotionNumber(total ? 360 : 0);
  return (
    <div className="finance-donut-wrap">
      <div
        className="finance-donut"
        role="img"
        aria-label={
          total ? items.map((item) => `${item.label}: ${format(item.value)}`).join(', ') : empty
        }
      >
        <span
          className={`finance-donut-surface${total ? ' has-data' : ''}`}
          style={
            {
              background: sectorBackground(animatedValues),
              '--finance-sweep': `${sweep}deg`,
            } as CSSProperties
          }
          aria-hidden="true"
        />
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

export const FinancePage = memo(function FinancePage({
  active = true,
  today = localDate(),
}: {
  active?: boolean;
  today?: string;
}) {
  const { locale, t } = useI18n();
  const [entries, setEntries] = useState<FinanceEntry[]>([]);
  const hasLoaded = useRef(false);
  const read = useRef(new LatestRead());
  const refreshGate = useRef(new RefreshGate());
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
  const [firstEntrance, setFirstEntrance] = useState(true);

  async function reload(initial = false) {
    if (!refreshGate.current.request()) return;
    const signal = read.current.start();
    if (initial) setLoading(true);
    else setRefreshing(true);
    setError('');
    try {
      const result = await api.finance(signal);
      if (!read.current.isCurrent(signal)) return;
      setEntries(result.entries);
      hasLoaded.current = true;
    } catch (failure) {
      if (read.current.isCurrent(signal))
        setError(
          failure instanceof Error ? failure.message : t('Не удалось загрузить финансовые данные.'),
        );
    } finally {
      if (read.current.isCurrent(signal)) {
        setLoading(false);
        setRefreshing(false);
      }
    }
  }

  useEffect(() => {
    if (!active) return;
    refreshGate.current.activate();
    void reload(!hasLoaded.current);
    return () => {
      refreshGate.current.deactivate();
      read.current.cancel();
    };
  }, [active]);
  useEffect(() => {
    if (!active || loading || !firstEntrance) return;
    const timer = window.setTimeout(() => setFirstEntrance(false), 650);
    return () => window.clearTimeout(timer);
  }, [active, loading, firstEntrance]);

  const money = (minor: number) =>
    numberFormatter(locale, {
      style: 'currency',
      currency,
      minimumFractionDigits: minor % 100 ? 2 : 0,
      maximumFractionDigits: 2,
    }).format(minor / 100);
  const formMoney = (minor: number) =>
    numberFormatter(locale, {
      style: 'currency',
      currency: form?.currency ?? currency,
      minimumFractionDigits: minor % 100 ? 2 : 0,
      maximumFractionDigits: 2,
    }).format(minor / 100);
  const dateLabel = (value: string) =>
    dateTimeFormatter(locale, { day: 'numeric', month: 'short', year: 'numeric' }).format(
      new Date(`${value}T12:00:00`),
    );

  const visible = useMemo(
    () => entries.filter((entry) => entry.currency === currency),
    [entries, currency],
  );
  const {
    transactions,
    assets,
    depositEntries,
    depositBalances,
    selectedDeposit,
    account,
    accountBalance,
    currentMonth,
    monthTransactions,
    income,
    expense,
    deposits,
    stocks,
    stockEntries,
    stocksWithBasis,
    stockInvested,
    stockCurrentWithBasis,
    stockGain,
    assetTotal,
    combinedTotal,
    sectionTotal,
    sectionCount,
    expenseGroups,
    expenseSlices,
    sectionAssets,
    sortedAssets,
    sectionAssetSlices,
    sectionSlices,
    monthly,
    chartMax,
    history,
    records,
  } = useMemo(() => {
    const transactions = visible.filter(
      (entry) => entry.type === 'income' || entry.type === 'expense',
    );
    const assets = visible.filter((entry) => entry.type === 'deposit' || entry.type === 'stock');
    const depositEntries = visible.filter((entry) => entry.type === 'deposit');
    const depositBalances = new Map(
      depositEntries.map((entry) => [entry.id, calculateDepositBalance(visible, entry.id, today)]),
    );
    const selectedDeposit = depositEntries.find((entry) => entry.id === selectedDepositId);
    const account = visible.find((entry) => entry.type === 'account');
    const accountBalance = calculateAccountBalance(visible, currency, today);
    const currentMonth = monthKey(today);
    const monthTransactions = transactions.filter((entry) => monthKey(entry.date) === currentMonth);
    const income = monthTransactions
      .filter((entry) => entry.type === 'income')
      .reduce((sum, entry) => sum + entry.amountMinor, 0);
    const expense = monthTransactions
      .filter((entry) => entry.type === 'expense')
      .reduce((sum, entry) => sum + entry.amountMinor, 0);
    const deposits = assets
      .filter((entry) => entry.type === 'deposit')
      .reduce((sum, entry) => sum + (depositBalances.get(entry.id) ?? 0), 0);
    const stocks = assets
      .filter((entry) => entry.type === 'stock')
      .reduce((sum, entry) => sum + entry.valueMinor, 0);
    const stockEntries = visible.filter(
      (entry): entry is Extract<FinanceEntry, { type: 'stock' }> => entry.type === 'stock',
    );
    const stocksWithBasis = stockEntries.filter(
      (entry) => entry.quantity && entry.purchasePriceMinor !== undefined,
    );
    const stockInvested = stocksWithBasis.reduce(
      (sum, entry) => sum + entry.quantity! * entry.purchasePriceMinor!,
      0,
    );
    const stockCurrentWithBasis = stocksWithBasis.reduce((sum, entry) => sum + entry.valueMinor, 0);
    const stockGain = stockCurrentWithBasis - stockInvested;
    const assetTotal = deposits + stocks;
    const combinedTotal = accountBalance === null ? null : accountBalance + assetTotal;
    const sectionTotal =
      view === 'account'
        ? accountBalance
        : view === 'deposits'
          ? selectedDeposit
            ? (depositBalances.get(selectedDeposit.id) ?? null)
            : deposits
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
          const category = t(entry.category);
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
    const sortedAssets = sectionAssets
      .map((entry) => ({
        ...entry,
        valueMinor:
          entry.type === 'deposit'
            ? Math.max(0, depositBalances.get(entry.id) ?? 0)
            : entry.valueMinor,
      }))
      .sort((a, b) => b.valueMinor - a.valueMinor);
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
            {
              label: t('Депозиты'),
              value: depositEntries.reduce(
                (sum, entry) => sum + Math.max(0, depositBalances.get(entry.id) ?? 0),
                0,
              ),
            },
            { label: t('Акции'), value: stocks },
          ].filter((item) => item.value > 0)
        : sectionAssetSlices;
    const monthly = Array.from({ length: 6 }, (_, index) =>
      monthOffset(new Date(`${today}T12:00:00`), index - 5),
    ).map((month) => ({
      ...month,
      income: transactions
        .filter((entry) => entry.type === 'income' && monthKey(entry.date) === month.key)
        .reduce((sum, entry) => sum + entry.amountMinor, 0),
      expense: transactions
        .filter((entry) => entry.type === 'expense' && monthKey(entry.date) === month.key)
        .reduce((sum, entry) => sum + entry.amountMinor, 0),
    }));
    const chartMax = Math.max(1, ...monthly.flatMap((month) => [month.income, month.expense]));
    const history = [...visible].sort(
      (a, b) =>
        (('date' in b ? b.date : b.asOf) || '').localeCompare(
          ('date' in a ? a.date : a.asOf) || '',
        ) || b.createdAt.localeCompare(a.createdAt),
    );
    const records = history.filter(
      (entry) =>
        view === 'all' ||
        (view === 'account' &&
          (entry.type === 'account' ||
            (entry.type === 'transfer' &&
              (entry.fromAccountId === account?.id || entry.toAccountId === account?.id)) ||
            ((entry.type === 'income' || entry.type === 'expense') &&
              (entry.accountId === undefined || entry.accountId === account?.id) &&
              (!account || (entry.date >= account.asOf && entry.date <= today))))) ||
        (view === 'deposits' &&
          ((entry.type === 'deposit' && (!selectedDeposit || entry.id === selectedDeposit.id)) ||
            ((entry.type === 'income' || entry.type === 'expense') &&
              entry.accountId !== undefined &&
              (selectedDeposit
                ? entry.accountId === selectedDeposit.id
                : depositEntries.some((deposit) => deposit.id === entry.accountId))) ||
            (entry.type === 'transfer' &&
              (!selectedDeposit ||
                entry.fromAccountId === selectedDeposit.id ||
                entry.toAccountId === selectedDeposit.id)))) ||
        (view === 'stocks' && entry.type === 'stock'),
    );
    return {
      transactions,
      assets,
      depositEntries,
      depositBalances,
      selectedDeposit,
      account,
      accountBalance,
      currentMonth,
      monthTransactions,
      income,
      expense,
      deposits,
      stocks,
      stockEntries,
      stocksWithBasis,
      stockInvested,
      stockCurrentWithBasis,
      stockGain,
      assetTotal,
      combinedTotal,
      sectionTotal,
      sectionCount,
      expenseGroups,
      expenseSlices,
      sectionAssets,
      sortedAssets,
      sectionAssetSlices,
      sectionSlices,
      monthly,
      chartMax,
      history,
      records,
    };
  }, [visible, currency, view, selectedDepositId, today, t]);

  const transferCurrency = form?.currency ?? currency;
  const transferAccounts = useMemo(
    () =>
      entries.filter(
        (entry): entry is Extract<FinanceEntry, { type: 'account' | 'deposit' }> =>
          (entry.type === 'account' || entry.type === 'deposit') &&
          entry.currency === transferCurrency,
      ),
    [entries, transferCurrency],
  );
  const accountNames = useMemo(
    () =>
      new Map(
        entries.flatMap((entry) =>
          entry.type === 'account' || entry.type === 'deposit'
            ? [[entry.id, entry.type === 'account' ? t('Основной счёт') : entry.name] as const]
            : [],
        ),
      ),
    [entries, t],
  );
  const accountName = (id: string) => accountNames.get(id) ?? t('Счёт недоступен');
  const transferMinDate =
    form?.type === 'transfer'
      ? transferAccounts
          .filter((entry) => entry.id === form.fromAccountId || entry.id === form.toAccountId)
          .map((entry) => entry.asOf)
          .sort()
          .at(-1)
      : undefined;

  function openTransfer(
    fromAccountId = account?.id ?? '',
    toAccountId = selectedDeposit?.id ?? depositEntries[0]?.id ?? '',
  ) {
    setEditing(null);
    setForm({ ...emptyForm(currency, 'transfer'), date: today, fromAccountId, toAccountId });
    setFormError('');
  }

  function openNew(
    type: Kind = view === 'deposits' ? 'deposit' : view === 'stocks' ? 'stock' : 'expense',
  ) {
    if (type === 'transfer') {
      openTransfer();
      return;
    }
    setEditing(null);
    setForm({ ...emptyForm(currency, type), date: today });
    setFormError('');
  }

  function openEdit(entry: FinanceEntry) {
    setEditing(entry);
    setForm({
      type: entry.type,
      fromAccountId: entry.type === 'transfer' ? entry.fromAccountId : '',
      toAccountId: entry.type === 'transfer' ? entry.toAccountId : '',
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
      purchasePrice:
        entry.type === 'stock' && entry.purchasePriceMinor !== undefined
          ? String(entry.purchasePriceMinor / 100)
          : '',
    });
    setFormError('');
  }

  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!form || saving || refreshGate.current.writing) return;
    const isStockWithPrice = form.type === 'stock' && form.quantity.trim() !== '';
    const quantity = isStockWithPrice ? Number(form.quantity) : null;
    const unitPriceMinor = isStockWithPrice ? parseMinor(form.unitPrice) : null;
    const purchasePriceMinor =
      form.type === 'stock' && form.purchasePrice.trim() ? parseMinor(form.purchasePrice) : null;
    const minor =
      isStockWithPrice && quantity && unitPriceMinor !== null
        ? quantity * unitPriceMinor
        : parseMinor(form.amount);
    if (
      minor === null ||
      !Number.isSafeInteger(minor) ||
      minor > 1_000_000_000_000 ||
      ((form.type === 'income' || form.type === 'expense' || form.type === 'transfer') &&
        minor === 0)
    ) {
      setFormError(
        t(
          form.type === 'income' || form.type === 'expense' || form.type === 'transfer'
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
      if (
        (!editing && purchasePriceMinor === null) ||
        (form.purchasePrice.trim() && purchasePriceMinor === null) ||
        (purchasePriceMinor !== null &&
          (!isStockWithPrice || !quantity || quantity * purchasePriceMinor > 1_000_000_000_000))
      ) {
        setFormError(t('Введите цену покупки за одну акцию и количество бумаг.'));
        return;
      }
    }
    if (
      form.type === 'transfer' &&
      (!form.fromAccountId ||
        !form.toAccountId ||
        form.fromAccountId === form.toAccountId ||
        !transferAccounts.some((entry) => entry.id === form.fromAccountId) ||
        !transferAccounts.some((entry) => entry.id === form.toAccountId))
    ) {
      setFormError(t('Выберите два разных счёта в одной валюте.'));
      return;
    }
    const common = { currency: form.currency, note: form.note.trim() };
    const input: FinanceEntryInput =
      form.type === 'transfer'
        ? {
            type: 'transfer',
            amountMinor: minor,
            date: form.date,
            fromAccountId: form.fromAccountId,
            toAccountId: form.toAccountId,
            ...common,
          }
        : form.type === 'income' || form.type === 'expense'
          ? {
              type: form.type,
              amountMinor: minor,
              date: form.date,
              category: form.category.trim(),
              ...(editing && 'accountId' in editing && editing.accountId
                ? { accountId: editing.accountId }
                : {}),
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
                  ...(purchasePriceMinor !== null ? { purchasePriceMinor } : {}),
                  ...common,
                }
              : {
                  type: form.type,
                  valueMinor: minor,
                  asOf: form.date,
                  name: form.name.trim(),
                  ...common,
                };
    read.current.cancel();
    refreshGate.current.beginWrite(!hasLoaded.current);
    setLoading(false);
    setRefreshing(false);
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
      if (refreshGate.current.endWrite()) void reload();
      setSaving(false);
    }
  }

  async function savePrice(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!priceUpdate || saving || refreshGate.current.writing || !priceUpdate.quantity) return;
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
    read.current.cancel();
    refreshGate.current.beginWrite(!hasLoaded.current);
    setLoading(false);
    setRefreshing(false);
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
      if (refreshGate.current.endWrite()) void reload();
      setSaving(false);
    }
  }

  async function remove(entry: FinanceEntry) {
    if (refreshGate.current.writing) return;
    read.current.cancel();
    refreshGate.current.beginWrite(!hasLoaded.current);
    setLoading(false);
    setRefreshing(false);
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
      if (refreshGate.current.endWrite()) void reload();
      setDeleting(null);
    }
  }

  return (
    <div
      className={`finance-page${active ? ' finance-page-visible' : ''}${firstEntrance ? ' finance-first-enter' : ''}`}
    >
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
          <button className="button button-secondary" type="button" onClick={() => openTransfer()}>
            <ArrowRightLeft size={17} /> {t('Перевод')}
          </button>
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
            'Переводы между основным счётом и депозитами меняют оба остатка, но не доходы и расходы.',
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
                <span>
                  {depositBalances.get(entry.id) === null
                    ? '—'
                    : money(depositBalances.get(entry.id) ?? 0)}
                </span>
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
                <span className="finance-figure">
                  {sectionTotal === null ? (
                    '—'
                  ) : (
                    <MotionNumber value={sectionTotal} format={money} step={100} />
                  )}
                </span>
              </strong>
              <p>
                {t(
                  view === 'account'
                    ? 'Стартовый остаток плюс внесённые операции с выбранной даты.'
                    : view === 'all'
                      ? 'Счёт, депозиты и акции в выбранной валюте.'
                      : view === 'deposits'
                        ? 'Стартовый остаток депозита плюс пополнения и снятия.'
                        : 'Стоимость по вашей последней ручной оценке.',
                )}
              </p>
              <div className="finance-hero-split">
                {view === 'account' && account ? (
                  <span>
                    {t('С {date} учтены поступления, расходы и переводы.', {
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
                {view === 'deposits' && selectedDeposit && (
                  <>
                    <button
                      type="button"
                      className="finance-hero-action"
                      onClick={() => openTransfer(account?.id ?? '', selectedDeposit.id)}
                    >
                      <ArrowDownLeft size={16} />
                      {t('Пополнить')}
                    </button>
                    <button
                      type="button"
                      className="finance-hero-action"
                      onClick={() => openTransfer(selectedDeposit.id, account?.id ?? '')}
                    >
                      <ArrowUpRight size={16} />
                      {t('Снять')}
                    </button>
                    {!account && (
                      <button
                        type="button"
                        className="finance-hero-action"
                        onClick={() => openNew('account')}
                      >
                        {t('Задать стартовый остаток')}
                      </button>
                    )}
                  </>
                )}
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
                  <span className="finance-figure">
                    {view === 'all' && accountBalance === null ? (
                      '—'
                    ) : (
                      <MotionNumber
                        value={
                          view === 'account'
                            ? income
                            : view === 'all'
                              ? accountBalance!
                              : sectionCount
                        }
                        format={view === 'account' || view === 'all' ? money : undefined}
                        step={view === 'account' || view === 'all' ? 100 : 1}
                      />
                    )}
                  </span>
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
                        : view === 'stocks'
                          ? 'Вложено в акции'
                          : 'Остаток депозитов',
                  )}
                </span>
                <strong>
                  <span className="finance-figure">
                    {view === 'stocks' && !stocksWithBasis.length ? (
                      '—'
                    ) : (
                      <MotionNumber
                        value={
                          view === 'account'
                            ? expense
                            : view === 'all'
                              ? deposits
                              : view === 'deposits'
                                ? selectedDeposit
                                  ? (depositBalances.get(selectedDeposit.id) ?? 0)
                                  : deposits
                                : stockInvested
                        }
                        format={money}
                        step={100}
                      />
                    )}
                  </span>
                </strong>
                {view === 'stocks' && stocksWithBasis.length < stockEntries.length && (
                  <small>
                    {t('Расчёт для {count} из {total}', {
                      count: stocksWithBasis.length,
                      total: stockEntries.length,
                    })}
                  </small>
                )}
              </div>
              <div
                className={`panel finance-summary-tile finance-net-tile ${view === 'stocks' ? 'finance-stock-net-tile' : ''}`}
              >
                <span className="finance-tile-icon net">
                  {view === 'all' ? <ChartNoAxesCombined size={18} /> : <Banknote size={18} />}
                </span>
                <span className="finance-tile-label">
                  {t(
                    view === 'stocks'
                      ? 'Прибыль / убыток'
                      : view === 'account'
                        ? 'Разница за месяц'
                        : view === 'all'
                          ? 'Акции'
                          : 'Валюта просмотра',
                  )}
                </span>
                <strong>
                  <span className="finance-figure">
                    {view === 'deposits' ? (
                      currency
                    ) : view === 'stocks' && !stocksWithBasis.length ? (
                      '—'
                    ) : (
                      <MotionNumber
                        value={
                          view === 'stocks'
                            ? stockGain
                            : view === 'account'
                              ? income - expense
                              : stocks
                        }
                        step={100}
                        format={(value) =>
                          (view === 'stocks' && value > 0 ? '+' : '') + money(value)
                        }
                      />
                    )}
                  </span>
                </strong>
                {view === 'stocks' && stocksWithBasis.length > 0 && stockInvested > 0 && (
                  <small className="finance-gain-percent">
                    {numberFormatter(locale, {
                      maximumFractionDigits: 1,
                      signDisplay: 'always',
                    }).format((stockGain / stockInvested) * 100)}
                    %
                  </small>
                )}
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
                        `${dateTimeFormatter(locale, { month: 'long', year: 'numeric' }).format(month.date)}: ${t('Поступления')} ${money(month.income)}, ${t('Расходы')} ${money(month.expense)}`,
                    )
                    .join('; ')}
                >
                  {monthly.map((month, index) => (
                    <div className="finance-month" key={month.key}>
                      <div className="finance-month-bars">
                        <MotionBar
                          className="finance-bar income"
                          value={Math.max(month.income ? 3 : 0, (month.income / chartMax) * 100)}
                          index={index}
                          title={`${t('Поступления')}: ${money(month.income)}`}
                        />
                        <MotionBar
                          className="finance-bar expense"
                          value={Math.max(month.expense ? 3 : 0, (month.expense / chartMax) * 100)}
                          index={index}
                          title={`${t('Расходы')}: ${money(month.expense)}`}
                        />
                      </div>
                      <span className="finance-month-label">
                        {dateTimeFormatter(locale, { month: 'short' }).format(month.date)}
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
                  center={money(sectionSlices.reduce((sum, item) => sum + item.value, 0))}
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
                {((view === 'all' && accountBalance !== null && accountBalance < 0) ||
                  ((view === 'all' || view === 'deposits') &&
                    [...depositBalances.values()].some(
                      (balance) => balance !== null && balance < 0,
                    ))) && (
                  <p className="finance-chart-empty">
                    {t('Отрицательные остатки учтены в итогах, но не в круговой диаграмме.')}
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
                <MotionList as="ul" className="finance-record-list">
                  {records.map((entry) => {
                    const isAsset =
                      entry.type === 'account' ||
                      entry.type === 'deposit' ||
                      entry.type === 'stock';
                    const amount =
                      entry.type === 'deposit'
                        ? (depositBalances.get(entry.id) ?? 0)
                        : isAsset
                          ? entry.valueMinor
                          : entry.amountMinor;
                    const label =
                      entry.type === 'account'
                        ? t('Стартовый остаток')
                        : entry.type === 'deposit' || entry.type === 'stock'
                          ? entry.name
                          : entry.type === 'transfer'
                            ? `${accountName(entry.fromAccountId)} → ${accountName(entry.toAccountId)}`
                            : t(entry.category);
                    const date = isAsset ? entry.asOf : entry.date;
                    const Icon =
                      entry.type === 'transfer'
                        ? ArrowRightLeft
                        : entry.type === 'income'
                          ? ArrowDownLeft
                          : entry.type === 'expense'
                            ? ArrowUpRight
                            : entry.type === 'account'
                              ? Wallet
                              : entry.type === 'deposit'
                                ? Landmark
                                : ChartNoAxesCombined;
                    const purchaseValue =
                      entry.type === 'stock' &&
                      entry.quantity &&
                      entry.purchasePriceMinor !== undefined
                        ? entry.quantity * entry.purchasePriceMinor
                        : null;
                    const gain =
                      entry.type === 'stock' && purchaseValue !== null
                        ? entry.valueMinor - purchaseValue
                        : null;
                    return (
                      <li key={entry.id} data-motion-key={entry.id} className="finance-record">
                        <span className={`finance-record-icon ${entry.type}`}>
                          <Icon size={17} />
                        </span>
                        <span className="finance-record-main">
                          <strong>{label}</strong>
                          <span>
                            {t(
                              entry.type === 'transfer'
                                ? 'Перевод'
                                : entry.type === 'income'
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
                          {entry.type === 'deposit' && (
                            <span>
                              {t('Стартовый остаток')}: {money(entry.valueMinor)}
                            </span>
                          )}
                          {entry.type === 'transfer' && entry.date > today && (
                            <span>{t('Запланировано: пока не влияет на остатки')}</span>
                          )}
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
                          {entry.type === 'stock' && (
                            <span
                              className={`finance-stock-result ${gain === null ? '' : gain >= 0 ? 'positive' : 'negative'}`}
                            >
                              {purchaseValue === null
                                ? t('Добавьте цену покупки для расчёта прибыли')
                                : `${t('Куплено за')} ${money(purchaseValue)} · ${t('Плюс / минус')} ${gain! > 0 ? '+' : ''}${money(gain!)}${purchaseValue > 0 ? ` (${numberFormatter(locale, { maximumFractionDigits: 1, signDisplay: 'always' }).format((gain! / purchaseValue) * 100)}%)` : ''}`}
                            </span>
                          )}
                        </span>
                        <strong className={`finance-record-money ${entry.type}`}>
                          {entry.type === 'income' ? '+' : entry.type === 'expense' ? '−' : ''}
                          {entry.type === 'deposit' && depositBalances.get(entry.id) === null
                            ? '—'
                            : money(amount)}
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
                </MotionList>
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
              {(['expense', 'income', 'transfer', 'account', 'deposit', 'stock'] as Kind[]).map(
                (kind) => (
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
                    onClick={() => {
                      setForm({
                        ...form,
                        type: kind,
                        category: '',
                        name: '',
                        fromAccountId: '',
                        toAccountId: '',
                      });
                      setFormError('');
                    }}
                  >
                    {t(
                      kind === 'transfer'
                        ? 'Перевод'
                        : kind === 'expense'
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
                ),
              )}
            </fieldset>
            <div className="form-grid">
              {form.type !== 'stock' && (
                <label className="field">
                  <span>
                    {t(
                      form.type === 'account'
                        ? 'Стартовый остаток'
                        : form.type === 'income' ||
                            form.type === 'expense' ||
                            form.type === 'transfer'
                          ? 'Сумма'
                          : form.type === 'deposit'
                            ? 'Стартовый остаток'
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
                    setForm({
                      ...form,
                      currency: event.target.value as Currency,
                      fromAccountId: '',
                      toAccountId: '',
                    })
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
            ) : form.type === 'transfer' ? (
              <div className="finance-transfer-fields">
                <div className="form-grid">
                  {(['fromAccountId', 'toAccountId'] as const).map((field) => (
                    <label className="field" key={field}>
                      <span>{t(field === 'fromAccountId' ? 'Откуда' : 'Куда')}</span>
                      <select
                        required
                        value={form[field]}
                        disabled={saving}
                        onChange={(event) => setForm({ ...form, [field]: event.target.value })}
                      >
                        <option value="">{t('Выберите счёт')}</option>
                        {transferAccounts.map((entry) => (
                          <option
                            key={entry.id}
                            value={entry.id}
                            disabled={
                              entry.id ===
                              form[field === 'fromAccountId' ? 'toAccountId' : 'fromAccountId']
                            }
                          >
                            {accountName(entry.id)}
                          </option>
                        ))}
                      </select>
                    </label>
                  ))}
                </div>
                <p className="finance-account-help">
                  {t(
                    'Перевод — запись в учёте: деньги в банке не перемещаются. Доходы и расходы не меняются.',
                  )}
                </p>
                {transferMinDate && (
                  <p className="finance-account-help">
                    {t('Дата перевода не раньше {date} — начала учёта обоих счетов.', {
                      date: dateLabel(transferMinDate),
                    })}
                  </p>
                )}
                {transferAccounts.length < 2 && (
                  <p className="finance-form-error">
                    {t('Добавьте основной счёт и депозит или два депозита в одной валюте.')}
                  </p>
                )}
              </div>
            ) : form.type === 'account' ? (
              <p className="finance-account-help">
                {t(
                  'Укажите остаток на начало выбранного дня. Поступления, расходы и переводы с этого дня меняют расчётный баланс.',
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
            {form.type === 'deposit' && (
              <p className="finance-account-help">
                {t(
                  'Укажите остаток на начало выбранного дня, до переводов за этот день. Пополнения и снятия записывайте как переводы.',
                )}
              </p>
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
                    <span>{t('Цена сейчас за акцию')}</span>
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
                <label className="field">
                  <span>{t('Цена покупки за акцию')}</span>
                  <input
                    required={!editing || Boolean(form.purchasePrice)}
                    inputMode="decimal"
                    value={form.purchasePrice}
                    onChange={(event) => setForm({ ...form, purchasePrice: event.target.value })}
                    placeholder="0,00"
                    disabled={saving}
                  />
                </label>
                <p className="finance-account-help">
                  {t('Прибыль и убыток рассчитаны без комиссий и дивидендов.')}
                </p>
                {form.quantity &&
                  form.unitPrice &&
                  parseMinor(form.unitPrice) !== null &&
                  Number.isSafeInteger(Number(form.quantity)) &&
                  Number(form.quantity) > 0 && (
                    <p className="finance-stock-total">
                      {t('Стоимость позиции')}:{' '}
                      {numberFormatter(locale, {
                        style: 'currency',
                        currency: form.currency,
                      }).format((Number(form.quantity) * parseMinor(form.unitPrice)!) / 100)}
                    </p>
                  )}
                {form.quantity &&
                  form.unitPrice &&
                  form.purchasePrice &&
                  Number.isSafeInteger(Number(form.quantity)) &&
                  Number(form.quantity) > 0 &&
                  parseMinor(form.unitPrice) !== null &&
                  parseMinor(form.purchasePrice) !== null && (
                    <p className="finance-stock-total">
                      {t('Куплено за')}{' '}
                      {formMoney(Number(form.quantity) * parseMinor(form.purchasePrice)!)} ·{' '}
                      {t('Плюс / минус')}{' '}
                      {formMoney(
                        Number(form.quantity) *
                          (parseMinor(form.unitPrice)! - parseMinor(form.purchasePrice)!),
                      )}
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
                {form.type === 'income' || form.type === 'expense' || form.type === 'transfer'
                  ? t('Дата операции')
                  : t(
                      form.type === 'account' || form.type === 'deposit'
                        ? 'Дата начала учёта'
                        : 'Дата оценки',
                    )}
              </span>
              <input
                required
                type="date"
                value={form.date}
                max={form.type === 'account' ? today : undefined}
                min={transferMinDate}
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
                data-dialog-dismiss
                disabled={saving}
              >
                {t('Отмена')}
              </button>
              <button
                type="submit"
                className="button button-primary"
                disabled={saving || (form.type === 'transfer' && transferAccounts.length < 2)}
              >
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
      )}
    </div>
  );
});
