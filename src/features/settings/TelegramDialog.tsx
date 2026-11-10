import { useId, useState } from 'react';
import { LoaderCircle } from 'lucide-react';
import type { TelegramStatus } from '../../../shared/types';
import { Dialog } from '../../components/Dialog';
import { useI18n } from '../../lib/i18n';
import { ChoiceGroup, type Choice } from './ChoiceGroup';
import { DEFAULT_TELEGRAM_LEAD, TELEGRAM_LEADS, type TelegramLead } from './settings-logic';
import { telegramSummary } from './settings-summaries';
import { DialogError, InfoRow } from './DialogParts';
import { StatusText, Switch } from './Rows';
import type { TelegramConnection } from './useTelegramConnection';

const REMINDER_PROBLEMS: Record<string, string> = {
  disabled: 'Автоматическая отправка выключена',
  chat_unlinked: 'Личный чат Telegram не привязан.',
  scheduler_unconfigured: 'Серверные ключи планировщика не настроены.',
  scheduler_waiting: 'Ожидается первый автоматический запуск планировщика.',
  scheduler_stale: 'Планировщик не запускался более пяти минут.',
  google_disconnected: 'Google Calendar не подключён.',
  google_error: 'Не удалось проверить Google Calendar.',
  telegram_error: 'Ошибка отправки в Telegram.',
  telegram_rejected: 'Telegram отклонил уведомление.',
  telegram_uncertain: 'Результат отправки в Telegram неизвестен.',
  internal_error: 'Ошибка проверки напоминаний на сервере.',
};

interface TelegramDialogProps {
  telegram: TelegramConnection;
  onClose: () => void;
}

export function TelegramDialog({ telegram, onClose }: TelegramDialogProps) {
  const { t } = useI18n();
  const { status } = telegram;
  const summary = telegramSummary(status, telegram.loadFailed);
  const [changingBot, setChangingBot] = useState(false);
  const showTokenForm = !status?.configured || changingBot;
  return (
    <Dialog title="Telegram" onClose={onClose} busy={telegram.busy} className="st-dialog">
      <InfoRow label={t('Состояние')}>
        <StatusText tone={summary.tone}>{t(summary.label)}</StatusText>
      </InfoRow>
      <BotDetails status={status} />
      {showTokenForm ? (
        <TokenForm
          telegram={telegram}
          canCancel={Boolean(status?.configured)}
          onDone={() => setChangingBot(false)}
        />
      ) : null}
      {status?.pairingUrl && !status.linked ? (
        <Pairing telegram={telegram} url={status.pairingUrl} />
      ) : null}
      {status?.linked ? <Reminders telegram={telegram} status={status} /> : null}
      {telegram.error ? <DialogError>{telegram.error}</DialogError> : null}
      {status?.configured ? (
        <div className="dialog-actions st-actions">
          <button
            type="button"
            className="button button-danger"
            disabled={telegram.busy}
            onClick={() => void telegram.disconnect()}
          >
            {t('Отключить')}
          </button>
          {!changingBot ? (
            <button
              type="button"
              className="button button-secondary"
              disabled={telegram.busy}
              onClick={() => setChangingBot(true)}
            >
              {t('Сменить бота')}
            </button>
          ) : null}
          {!status.linked ? (
            <button
              type="button"
              className="button button-primary"
              disabled={telegram.busy}
              onClick={() => void telegram.pair()}
            >
              {t('Привязать чат')}
            </button>
          ) : null}
        </div>
      ) : null}
    </Dialog>
  );
}

function BotDetails({ status }: { status: TelegramStatus | null }) {
  const { t } = useI18n();
  const account = status?.account;
  return (
    <>
      <p className="st-note">
        {status?.botUsername
          ? `@${status.botUsername}`
          : t('Подключи своего бота, затем привяжи личный чат.')}
        {status?.linked && account
          ? ` · ${t('Привязан: {name}', { name: account.username ? `@${account.username}` : account.firstName })}`
          : ''}
      </p>
      <p className="st-note">
        {t(
          'В личном чате отправь /menu, чтобы открыть кнопки быстрых дел, плана и итога. Сообщения не передаются ИИ.',
        )}
      </p>
    </>
  );
}

function TokenForm({
  telegram,
  canCancel,
  onDone,
}: {
  telegram: TelegramConnection;
  canCancel: boolean;
  onDone: () => void;
}) {
  const { t } = useI18n();
  const tokenId = useId();
  const [token, setToken] = useState('');
  async function submit() {
    if (await telegram.configure(token.trim())) {
      setToken('');
      onDone();
    }
  }
  return (
    <form
      className="st-dialog-form"
      onSubmit={(event) => {
        event.preventDefault();
        if (token.trim() && !telegram.busy) void submit();
      }}
    >
      <div className="st-field">
        <label htmlFor={tokenId}>{t('Токен бота от BotFather')}</label>
        <input
          id={tokenId}
          className="st-input"
          type="password"
          autoComplete="off"
          spellCheck={false}
          value={token}
          placeholder="123456789:…"
          onChange={(event) => setToken(event.target.value)}
        />
        <small>{t('Токен хранится зашифрованным на сервере. Не отправляй его в чат.')}</small>
      </div>
      <div className="st-inline-actions">
        <button
          type="submit"
          className="button button-primary"
          disabled={telegram.busy || !token.trim()}
        >
          {telegram.busy ? <LoaderCircle className="st-spin" size={16} aria-hidden="true" /> : null}
          {t('Сохранить бота')}
        </button>
        {canCancel ? (
          <button type="button" className="button button-secondary" onClick={onDone}>
            {t('Отмена')}
          </button>
        ) : null}
      </div>
    </form>
  );
}

function Pairing({ telegram, url }: { telegram: TelegramConnection; url: string }) {
  const { t } = useI18n();
  return (
    <div className="st-callout">
      <p>
        {t(
          'Открой ссылку в Telegram и нажми Start, затем вернись сюда. Ссылка действует 10 минут.',
        )}
      </p>
      <div className="st-inline-actions">
        <a className="button button-secondary" href={url} target="_blank" rel="noopener noreferrer">
          {t('Открыть бота в Telegram')}
        </a>
        <button
          type="button"
          className="button button-secondary"
          disabled={telegram.busy}
          onClick={() => void telegram.refresh()}
        >
          {t('Проверить подключение')}
        </button>
      </div>
    </div>
  );
}

function Reminders({ telegram, status }: { telegram: TelegramConnection; status: TelegramStatus }) {
  const { t, language } = useI18n();
  const reminders = status.reminders;
  const lead = reminders?.leadMinutes ?? DEFAULT_TELEGRAM_LEAD;
  const enabled = reminders?.enabled ?? false;
  const choices: Choice<TelegramLead>[] = TELEGRAM_LEADS.map((minutes) => ({
    value: minutes,
    label: minutes === 0 ? t('В момент начала') : t('{minutes} мин', { minutes }),
  }));
  const problem = reminders?.ready
    ? t('Автоматическая отправка работает')
    : t(REMINDER_PROBLEMS[reminders?.problem ?? ''] ?? 'Ожидание планировщика или привязки чата');
  return (
    <section className="st-subsection" aria-label={t('Напоминания в Telegram')}>
      <div className="st-info-row">
        <span className="st-info-label">
          <strong>{t('Напоминания в Telegram')}</strong>
          <small>{problem}</small>
        </span>
        <Switch
          checked={enabled}
          label={t('Напоминания в Telegram')}
          disabled={telegram.busy}
          onChange={(next) => void telegram.setReminders(next, lead)}
        />
      </div>
      <div className="st-field">
        <span className="st-field-label">{t('Предупредить')}</span>
        <ChoiceGroup
          label={t('Предупредить')}
          className="st-pills"
          choiceClassName="st-pill"
          value={lead}
          choices={choices}
          onChange={(minutes) => void telegram.setReminders(enabled, minutes)}
        />
        <small>
          {t('Часовой пояс')}: {reminders?.timeZone ?? '—'}
        </small>
      </div>
      <div className="st-inline-actions">
        <button
          type="button"
          className="button button-secondary"
          disabled={telegram.busy}
          onClick={() => void telegram.sendTest()}
        >
          {t('Отправить тестовое уведомление')}
        </button>
      </div>
      {telegram.testSent ? (
        <small role="status">
          {t('Тестовое сообщение отправлено. Оно не подтверждает работу планировщика.')}
        </small>
      ) : null}
      {reminders?.lastRunAt ? (
        <small>
          {t('Последняя успешная проверка')}:{' '}
          {new Intl.DateTimeFormat(language === 'en' ? 'en-US' : 'ru-RU', {
            dateStyle: 'medium',
            timeStyle: 'short',
            timeZone: reminders.timeZone,
          }).format(new Date(reminders.lastRunAt))}
        </small>
      ) : null}
    </section>
  );
}
