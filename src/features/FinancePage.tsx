import { useEffect, useMemo, useState, type CSSProperties, type FormEvent } from 'react';
import {
  ArrowDownLeft,
  ArrowUpRight,
  Banknote,
  ChartNoAxesCombined,
  CirclePlus,
  Coins,
  Landmark,
  LoaderCircle,
  Pencil,
  RefreshCw,
  Trash2,
  Wallet,
} from 'lucide-react';
import type { FinanceEntry, FinanceEntryInput } from '../../shared/types';
import { Dialog } from '../components/Dialog';
import { api } from '../lib/api';
import { useI18n } from '../lib/i18n';
import '../styles/finance.css';

type Currency = FinanceEntry['currency'];
type Kind = FinanceEntry['type'];
type FormState = {
  type: Kind;
  amount: string;
  currency: Currency;
  date: string;
  category: string;
  name: string;
  note: string;
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
  };
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
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState('');
  const [form, setForm] = useState<FormState | null>(null);
  const [editing, setEditing] = useState<FinanceEntry | null>(null);
  const [saving, setSaving] = useState(false);
  const [formError, setFormError] = useState('');
  const [confirmDelete, setConfirmDelete] = useState<string | null>(null);
  const [deleting, setDeleting] = useState<string | null>(null);

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
  const assetSlices = [
    ...assets
      .sort((a, b) => b.valueMinor - a.valueMinor)
      .slice(0, 5)
      .map((entry) => ({ label: entry.name, value: entry.valueMinor })),
    ...(assets.length > 5
      ? [
          {
            label: t('Другое'),
            value: assets.slice(5).reduce((sum, entry) => sum + entry.valueMinor, 0),
          },
        ]
      : []),
  ];
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

  function openNew(type: Kind = 'expense') {
    setEditing(null);
    setForm(emptyForm(currency, type));
    setFormError('');
  }

  function openEdit(entry: FinanceEntry) {
    setEditing(entry);
    setForm({
      type: entry.type,
      amount: String(
        (entry.type === 'deposit' || entry.type === 'stock'
          ? entry.valueMinor
          : entry.amountMinor) / 100,
      ),
      currency: entry.currency,
      date: entry.type === 'deposit' || entry.type === 'stock' ? entry.asOf : entry.date,
      category: entry.type === 'deposit' || entry.type === 'stock' ? '' : entry.category,
      name: entry.type === 'deposit' || entry.type === 'stock' ? entry.name : '',
      note: entry.note,
    });
    setFormError('');
  }

  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!form || saving) return;
    const minor = parseMinor(form.amount);
    if (minor === null || ((form.type === 'income' || form.type === 'expense') && minor === 0)) {
      setFormError(
        t(
          form.type === 'income' || form.type === 'expense'
            ? 'Введите сумму больше нуля, максимум с двумя знаками после запятой.'
            : 'Введите стоимость от нуля, максимум с двумя знаками после запятой.',
        ),
      );
      return;
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
      setForm(null);
      setEditing(null);
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
              onChange={(event) => setCurrency(event.target.value as Currency)}
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
      ) : !visible.length ? (
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
                <span>{t('Учтённые активы')}</span>
                <Wallet size={21} />
              </div>
              <strong className="finance-hero-value">{money(assetTotal)}</strong>
              <p>{t('Вклады и акции по вашей последней оценке')}</p>
              <div className="finance-hero-split">
                <span>
                  <Landmark size={17} />
                  <span>
                    {t('Депозиты')} <strong>{money(deposits)}</strong>
                  </span>
                </span>
                <span>
                  <ChartNoAxesCombined size={17} />
                  <span>
                    {t('Акции')} <strong>{money(stocks)}</strong>
                  </span>
                </span>
              </div>
            </div>
            <div className="finance-overview-tiles">
              <div className="panel finance-summary-tile">
                <span className="finance-tile-icon income">
                  <ArrowDownLeft size={18} />
                </span>
                <span className="finance-tile-label">{t('Поступило за месяц')}</span>
                <strong>{money(income)}</strong>
              </div>
              <div className="panel finance-summary-tile">
                <span className="finance-tile-icon expense">
                  <ArrowUpRight size={18} />
                </span>
                <span className="finance-tile-label">{t('Потрачено за месяц')}</span>
                <strong>{money(expense)}</strong>
              </div>
              <div className="panel finance-summary-tile finance-net-tile">
                <span className="finance-tile-icon net">
                  <Banknote size={18} />
                </span>
                <span className="finance-tile-label">{t('Разница за месяц')}</span>
                <strong>{money(income - expense)}</strong>
              </div>
            </div>
          </section>

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

          <section className="finance-bottom-grid">
            <div className="panel finance-chart-card">
              <div className="finance-card-heading">
                <div>
                  <span>{t('Состав активов')}</span>
                  <h2>{t('Где находятся деньги')}</h2>
                </div>
              </div>
              <Donut
                items={assetSlices}
                center={money(assetTotal)}
                caption={t('в активах')}
                empty={t('Добавьте депозит или акции, чтобы увидеть распределение.')}
                format={money}
              />
            </div>
            <div className="panel finance-records">
              <div className="finance-card-heading">
                <div>
                  <span>{t('Ваши записи')}</span>
                  <h2>{t('Операции и активы')}</h2>
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
              {history.length ? (
                <ul className="finance-record-list">
                  {history.map((entry) => {
                    const isAsset = entry.type === 'deposit' || entry.type === 'stock';
                    const amount = isAsset ? entry.valueMinor : entry.amountMinor;
                    const label = isAsset ? entry.name : categoryLabel(entry.category);
                    const date = isAsset ? entry.asOf : entry.date;
                    const Icon =
                      entry.type === 'income'
                        ? ArrowDownLeft
                        : entry.type === 'expense'
                          ? ArrowUpRight
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
                                  : entry.type === 'deposit'
                                    ? 'Депозит'
                                    : 'Акции',
                            )}{' '}
                            · {dateLabel(date)}
                            {entry.note ? ` · ${entry.note}` : ''}
                          </span>
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
                  <p>{t('Добавьте первое поступление, расход или актив.')}</p>
                  <button
                    type="button"
                    className="button button-secondary"
                    onClick={() => openNew()}
                  >
                    {t('Добавить запись')}
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
              {(['expense', 'income', 'deposit', 'stock'] as Kind[]).map((kind) => (
                <button
                  key={kind}
                  type="button"
                  aria-pressed={form.type === kind}
                  onClick={() => setForm({ ...form, type: kind, category: '', name: '' })}
                >
                  {t(
                    kind === 'expense'
                      ? 'Расход'
                      : kind === 'income'
                        ? 'Поступление'
                        : kind === 'deposit'
                          ? 'Депозит'
                          : 'Акции',
                  )}
                </button>
              ))}
            </fieldset>
            <div className="form-grid">
              <label className="field">
                <span>
                  {form.type === 'income' || form.type === 'expense'
                    ? t('Сумма')
                    : t('Текущая стоимость')}
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
              <label className="field">
                <span>{t('Валюта')}</span>
                <select
                  value={form.currency}
                  onChange={(event) =>
                    setForm({ ...form, currency: event.target.value as Currency })
                  }
                  disabled={saving}
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
            <label className="field">
              <span>
                {form.type === 'income' || form.type === 'expense'
                  ? t('Дата операции')
                  : t('Дата оценки')}
              </span>
              <input
                required
                type="date"
                value={form.date}
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
    </div>
  );
}
