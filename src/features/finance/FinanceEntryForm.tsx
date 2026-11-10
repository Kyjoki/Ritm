import type { FormEvent } from 'react';
import { ExternalLink, LoaderCircle } from 'lucide-react';
import type { FinanceEntry } from '../../../shared/types';
import { Dialog } from '../../components/Dialog';
import { useI18n } from '../../lib/i18n';
import {
  CURRENCIES,
  EXPENSE_CATEGORIES,
  INCOME_CATEGORIES,
  parseMinor,
  quoteUrl,
  type Currency,
  type FormState,
  type Kind,
} from './finance-form';
import { CategoryIcon, formatMoney, useDayLabel } from './finance-format';
import { operationAccounts } from './finance-wallet';

export type FormGroup = 'operation' | 'asset';
const GROUP_KINDS: Record<FormGroup, Kind[]> = {
  operation: ['expense', 'income', 'transfer'],
  asset: ['account', 'deposit', 'stock'],
};
const KIND_LABEL: Record<Kind, string> = {
  transfer: 'Перевод',
  expense: 'Расход',
  income: 'Поступление',
  account: 'Основной счёт',
  deposit: 'Депозит',
  stock: 'Акции',
};

export interface EntryFormProps {
  form: FormState;
  group: FormGroup;
  editing: FinanceEntry | null;
  entries: FinanceEntry[];
  transferAccounts: Extract<FinanceEntry, { type: 'account' | 'deposit' }>[];
  accountName: (id: string) => string;
  today: string;
  saving: boolean;
  error: string;
  onChange: (form: FormState) => void;
  onSubmit: (event: FormEvent<HTMLFormElement>) => void;
  onClose: () => void;
}

function amountLabel(type: Kind) {
  if (type === 'income' || type === 'expense' || type === 'transfer') return 'Сумма';
  return type === 'stock' ? 'Текущая стоимость' : 'Стартовый остаток';
}

function CategoryField({ props }: { props: EntryFormProps }) {
  const { t } = useI18n();
  const { form, saving, onChange } = props;
  const presets = form.type === 'income' ? INCOME_CATEGORIES : EXPENSE_CATEGORIES;
  return (
    <div className="fin-field">
      <label htmlFor="fin-category">{t('Категория')}</label>
      <input
        id="fin-category"
        required
        maxLength={80}
        value={form.category}
        onChange={(event) => onChange({ ...form, category: event.target.value })}
        placeholder={t('Например, зарплата или продукты')}
        disabled={saving}
      />
      <div className="fin-chips" role="group" aria-label={t('Быстрый выбор категории')}>
        {presets.map((label) => (
          <button
            key={label}
            type="button"
            aria-pressed={form.category === label}
            disabled={saving}
            onClick={() => onChange({ ...form, category: label })}
          >
            <CategoryIcon category={label} size={15} />
            {t(label)}
          </button>
        ))}
      </div>
    </div>
  );
}

function AccountField({ props }: { props: EntryFormProps }) {
  const { t } = useI18n();
  const { form, entries, saving, onChange } = props;
  const options = operationAccounts(entries, form.currency);
  const main = options.find((option) => option.isMain);
  const value = options.some((option) => option.id === form.accountId)
    ? form.accountId
    : (main?.id ?? options[0]?.id ?? '');
  return (
    <div className="fin-field">
      <label htmlFor="fin-account">{t('Счёт')}</label>
      <select
        id="fin-account"
        value={value}
        disabled={saving || options.length === 0}
        onChange={(event) => onChange({ ...form, accountId: event.target.value })}
      >
        {options.length === 0 && <option value="">{t('Основной счёт')}</option>}
        {options.map((option) => (
          <option key={option.id} value={option.id}>
            {option.name ?? t('Основной счёт')}
          </option>
        ))}
      </select>
      <p className="fin-help">{t('Операция доступна только по счёту в той же валюте.')}</p>
    </div>
  );
}

function TransferFields({ props }: { props: EntryFormProps }) {
  const { t } = useI18n();
  const { form, transferAccounts, accountName, saving, onChange } = props;
  const { full } = useDayLabel();
  const minDate = transferAccounts
    .filter((entry) => entry.id === form.fromAccountId || entry.id === form.toAccountId)
    .map((entry) => entry.asOf)
    .sort()
    .at(-1);
  return (
    <div className="fin-transfer">
      <div className="fin-grid">
        {(['fromAccountId', 'toAccountId'] as const).map((field) => (
          <div className="fin-field" key={field}>
            <label htmlFor={`fin-${field}`}>
              {t(field === 'fromAccountId' ? 'Откуда' : 'Куда')}
            </label>
            <select
              id={`fin-${field}`}
              required
              value={form[field]}
              disabled={saving}
              onChange={(event) => onChange({ ...form, [field]: event.target.value })}
            >
              <option value="">{t('Выберите счёт')}</option>
              {transferAccounts.map((entry) => (
                <option
                  key={entry.id}
                  value={entry.id}
                  disabled={
                    entry.id === form[field === 'fromAccountId' ? 'toAccountId' : 'fromAccountId']
                  }
                >
                  {accountName(entry.id)}
                </option>
              ))}
            </select>
          </div>
        ))}
      </div>
      <p className="fin-help">
        {t(
          'Перевод — запись в учёте: деньги в банке не перемещаются. Доходы и расходы не меняются.',
        )}
      </p>
      {minDate && (
        <p className="fin-help">
          {t('Дата перевода не раньше {date} — начала учёта обоих счетов.', {
            date: full(minDate),
          })}
        </p>
      )}
      {transferAccounts.length < 2 && (
        <p className="fin-error">
          {t('Добавьте основной счёт и депозит или два депозита в одной валюте.')}
        </p>
      )}
    </div>
  );
}

function TextField({
  id,
  label,
  value,
  onChange,
  disabled,
  ...rest
}: {
  id: string;
  label: string;
  value: string;
  onChange: (value: string) => void;
  disabled: boolean;
  required?: boolean;
  maxLength?: number;
  placeholder?: string;
  inputMode?: 'decimal' | 'numeric';
}) {
  return (
    <div className="fin-field">
      <label htmlFor={id}>{label}</label>
      <input
        id={id}
        autoComplete="off"
        value={value}
        onChange={(event) => onChange(event.target.value)}
        disabled={disabled}
        {...rest}
      />
    </div>
  );
}

function StockInputs({ props }: { props: EntryFormProps }) {
  const { t } = useI18n();
  const { form, editing, saving, onChange } = props;
  const set = (patch: Partial<FormState>) => onChange({ ...form, ...patch });
  return (
    <>
      <div className="fin-grid">
        <div className="fin-field">
          <label htmlFor="fin-exchange">{t('Биржа')}</label>
          <select
            id="fin-exchange"
            value={form.exchange}
            disabled={saving}
            onChange={(event) => set({ exchange: event.target.value as 'KASE' | 'AIX' })}
          >
            <option value="KASE">KASE</option>
            <option value="AIX">AIX</option>
          </select>
        </div>
        <TextField
          id="fin-ticker"
          label={t('Тикер')}
          value={form.ticker}
          placeholder="HSBK"
          maxLength={30}
          required={!editing}
          disabled={saving}
          onChange={(value) => set({ ticker: value.toUpperCase() })}
        />
      </div>
      <div className="fin-grid">
        <TextField
          id="fin-qty"
          label={t('Количество акций')}
          value={form.quantity}
          inputMode="numeric"
          placeholder="10"
          required={!editing || Boolean(form.unitPrice)}
          disabled={saving}
          onChange={(value) => set({ quantity: value })}
        />
        <TextField
          id="fin-unit"
          label={t('Цена сейчас за акцию')}
          value={form.unitPrice}
          inputMode="decimal"
          placeholder="0,00"
          required={!editing || Boolean(form.quantity)}
          disabled={saving}
          onChange={(value) => set({ unitPrice: value })}
        />
      </div>
      <TextField
        id="fin-buy"
        label={t('Цена покупки за акцию')}
        value={form.purchasePrice}
        inputMode="decimal"
        placeholder="0,00"
        required={!editing || Boolean(form.purchasePrice)}
        disabled={saving}
        onChange={(value) => set({ purchasePrice: value })}
      />
    </>
  );
}

function StockTotals({ form }: { form: FormState }) {
  const { t, locale } = useI18n();
  const quantity = Number(form.quantity);
  const unit = parseMinor(form.unitPrice);
  const purchase = parseMinor(form.purchasePrice);
  const valid = form.quantity && Number.isSafeInteger(quantity) && quantity > 0;
  if (!valid || unit === null) return null;
  const money = (minor: number) => formatMoney(locale, form.currency, minor);
  return (
    <p className="fin-stock-total">
      {t('Стоимость позиции')}: {money(quantity * unit)}
      {purchase !== null &&
        ` · ${t('Куплено за')} ${money(quantity * purchase)} · ${t('Плюс / минус')} ${money(quantity * (unit - purchase))}`}
    </p>
  );
}

function StockFields({ props }: { props: EntryFormProps }) {
  const { t } = useI18n();
  const { form, editing, saving, onChange } = props;
  const set = (patch: Partial<FormState>) => onChange({ ...form, ...patch });
  const link = form.ticker ? quoteUrl(form.exchange, form.ticker.trim()) : null;
  return (
    <div className="fin-stock-form">
      <StockInputs props={props} />
      <StockTotals form={form} />
      {editing && editing.type === 'stock' && !editing.quantity && !form.quantity && (
        <TextField
          id="fin-legacy"
          label={t('Прежняя ручная оценка')}
          value={form.amount}
          inputMode="decimal"
          required
          disabled={saving}
          onChange={(value) => set({ amount: value })}
        />
      )}
      {link && (
        <a className="fin-link-out" href={link} target="_blank" rel="noopener noreferrer">
          {t('Посмотреть котировку на сайте биржи')} <ExternalLink size={14} aria-hidden="true" />
        </a>
      )}
      <p className="fin-help">
        {t('Цену вы вводите вручную после проверки на сайте биржи. Показываем дату вашей оценки.')}{' '}
        {t('Выбирайте валюту, в которой биржа показывает цену этой акции.')}
      </p>
    </div>
  );
}

function KindSwitch({ props }: { props: EntryFormProps }) {
  const { t } = useI18n();
  const { form, group, editing, entries, saving, onChange } = props;
  return (
    <fieldset className="fin-kinds" disabled={Boolean(editing) || saving}>
      <legend>{t('Тип записи')}</legend>
      {GROUP_KINDS[group].map((kind) => (
        <button
          key={kind}
          type="button"
          aria-pressed={form.type === kind}
          disabled={
            !editing &&
            kind === 'account' &&
            entries.some((entry) => entry.type === 'account' && entry.currency === form.currency)
          }
          onClick={() =>
            onChange({
              ...form,
              type: kind,
              category: '',
              name: '',
              fromAccountId: '',
              toAccountId: '',
            })
          }
        >
          {t(KIND_LABEL[kind])}
        </button>
      ))}
    </fieldset>
  );
}

function AmountCurrencyFields({ props }: { props: EntryFormProps }) {
  const { t } = useI18n();
  const { form, editing, saving, onChange } = props;
  const set = (patch: Partial<FormState>) => onChange({ ...form, ...patch });
  return (
    <div className="fin-grid">
      {form.type !== 'stock' && (
        <div className="fin-field">
          <label htmlFor="fin-amount">{t(amountLabel(form.type))}</label>
          <input
            id="fin-amount"
            required
            inputMode="decimal"
            autoComplete="off"
            placeholder="0,00"
            value={form.amount}
            onChange={(event) => set({ amount: event.target.value })}
            disabled={saving}
          />
        </div>
      )}
      <div className="fin-field">
        <label htmlFor="fin-currency">{t('Валюта')}</label>
        <select
          id="fin-currency"
          value={form.currency}
          onChange={(event) =>
            set({
              currency: event.target.value as Currency,
              fromAccountId: '',
              toAccountId: '',
              accountId: '',
            })
          }
          disabled={saving || (Boolean(editing) && form.type === 'account')}
        >
          {CURRENCIES.map((item) => (
            <option key={item} value={item}>
              {item}
            </option>
          ))}
        </select>
      </div>
    </div>
  );
}

function KindFields({ props }: { props: EntryFormProps }) {
  const { t } = useI18n();
  const { form, saving, onChange } = props;
  const type = form.type;
  if (type === 'income' || type === 'expense')
    return (
      <>
        <AccountField props={props} />
        <CategoryField props={props} />
      </>
    );
  if (type === 'transfer') return <TransferFields props={props} />;
  if (type === 'stock') return <StockFields props={props} />;
  if (type === 'account')
    return (
      <p className="fin-help">
        {t(
          'Укажите остаток на начало выбранного дня. Поступления, расходы и переводы с этого дня меняют расчётный баланс.',
        )}
      </p>
    );
  return (
    <>
      <TextField
        id="fin-name"
        label={t('Название')}
        value={form.name}
        maxLength={100}
        required
        disabled={saving}
        placeholder={t('Название вклада')}
        onChange={(value) => onChange({ ...form, name: value })}
      />
      <p className="fin-help">
        {t(
          'Укажите остаток на начало выбранного дня, до переводов за этот день. Пополнения и снятия записывайте как переводы.',
        )}
      </p>
    </>
  );
}

function DateNoteFields({ props }: { props: EntryFormProps }) {
  const { t } = useI18n();
  const { form, saving, onChange, today } = props;
  const type = form.type;
  const moving = type === 'income' || type === 'expense' || type === 'transfer';
  const set = (patch: Partial<FormState>) => onChange({ ...form, ...patch });
  return (
    <>
      <div className="fin-field">
        <label htmlFor="fin-date">
          {moving ? t('Дата операции') : t(type === 'stock' ? 'Дата оценки' : 'Дата начала учёта')}
        </label>
        <input
          id="fin-date"
          required
          type="date"
          value={form.date}
          max={type === 'account' ? today : undefined}
          onChange={(event) => set({ date: event.target.value })}
          disabled={saving}
        />
      </div>
      <div className="fin-field">
        <label htmlFor="fin-note">
          {t('Заметка')} <span className="fin-optional">{t('необязательно')}</span>
        </label>
        <textarea
          id="fin-note"
          rows={2}
          maxLength={400}
          value={form.note}
          onChange={(event) => set({ note: event.target.value })}
          placeholder={t('Добавьте контекст для себя')}
          disabled={saving}
        />
      </div>
    </>
  );
}

function Body({ props }: { props: EntryFormProps }) {
  return (
    <>
      <AmountCurrencyFields props={props} />
      <KindFields props={props} />
      <DateNoteFields props={props} />
    </>
  );
}

export function EntryDialog(props: EntryFormProps) {
  const { t } = useI18n();
  const { editing, saving, error, onSubmit, onClose, transferAccounts, form } = props;
  return (
    <Dialog
      title={
        editing
          ? t('Изменить запись')
          : t(props.group === 'operation' ? 'Новая операция' : 'Новый счёт')
      }
      onClose={onClose}
      busy={saving}
      className="finance-dialog fin-dialog"
    >
      <form onSubmit={onSubmit} className="fin-form">
        <KindSwitch props={props} />
        <Body props={props} />
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
          <button
            type="submit"
            className="button button-primary"
            disabled={saving || (form.type === 'transfer' && transferAccounts.length < 2)}
          >
            {saving && <LoaderCircle size={16} className="spinning" />}
            {editing ? t('Сохранить изменения') : t('Сохранить')}
          </button>
        </div>
      </form>
    </Dialog>
  );
}
