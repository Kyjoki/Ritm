import { useEffect, useState } from 'react';
import { Send, LoaderCircle } from 'lucide-react';
import type { TelegramStatus } from '../../shared/types';
import { api } from '../lib/api';
import { useI18n } from '../lib/i18n';

const reminderProblems: Record<string, string> = {
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

export function TelegramConnection() {
  const { t, language } = useI18n();
  const [status, setStatus] = useState<TelegramStatus | null>(null);
  const [token, setToken] = useState('');
  const [editing, setEditing] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [testSent, setTestSent] = useState(false);
  useEffect(() => {
    let active = true;
    void api
      .telegramStatus()
      .then((value) => {
        if (active) setStatus(value);
      })
      .catch((failure) => {
        if (active)
          setError(
            failure instanceof Error ? failure.message : t('Не удалось проверить Telegram.'),
          );
      });
    return () => {
      active = false;
    };
  }, [t]);
  useEffect(() => {
    if (!status?.pairingUrl || status.linked) return;
    const timer = window.setInterval(() => {
      void api
        .telegramStatus()
        .then(setStatus)
        .catch(() => {});
    }, 4_000);
    return () => window.clearInterval(timer);
  }, [status?.pairingUrl, status?.linked]);
  useEffect(() => {
    if (!status?.reminders?.enabled) return;
    const timer = window.setInterval(() => {
      void api
        .telegramStatus()
        .then(setStatus)
        .catch(() => {});
    }, 30_000);
    return () => window.clearInterval(timer);
  }, [status?.reminders?.enabled]);
  async function action(operation: () => Promise<TelegramStatus>) {
    setBusy(true);
    setError('');
    try {
      setStatus(await operation());
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : t('Не удалось подключить Telegram.'));
    } finally {
      setBusy(false);
    }
  }
  return (
    <>
      <div className="settings-connection-row">
        <div className="settings-provider-icon settings-telegram-provider">
          <Send size={19} aria-hidden="true" />
        </div>
        <div className="settings-connection-copy">
          <strong>Telegram</strong>
          <span
            className={`settings-connection-status ${status?.linked ? 'settings-configured' : ''}`}
          >
            <i />
            {status?.linked
              ? t('Личный чат привязан')
              : status?.configured
                ? t('Бот настроен · чат не привязан')
                : t('Не настроен')}
          </span>
          <small>
            {status?.botUsername
              ? `@${status.botUsername}`
              : t('Подключи своего бота, затем привяжи личный чат.')}
          </small>
          {status?.linked && status.account ? (
            <small>
              {t('Привязан: {name}', {
                name: status.account.username
                  ? `@${status.account.username}`
                  : status.account.firstName,
              })}
            </small>
          ) : null}
          <small>
            {t(
              'В личном чате отправь /menu, чтобы открыть кнопки быстрых дел, плана и итога. Сообщения не передаются ИИ.',
            )}
          </small>
        </div>
        <div className="settings-connection-actions">
          <button
            type="button"
            className="button button-secondary"
            disabled={busy}
            onClick={() => setEditing((value) => !value)}
          >
            {status?.configured ? t('Сменить бота') : t('Настроить')}
          </button>
          {status?.configured && !status.linked ? (
            <button
              type="button"
              className="button button-secondary"
              disabled={busy}
              onClick={() => void action(api.pairTelegram)}
            >
              {t('Привязать чат')}
            </button>
          ) : null}
          {status?.configured ? (
            <button
              type="button"
              className="settings-text-button"
              disabled={busy}
              onClick={() => void action(api.disconnectTelegram)}
            >
              {t('Отключить')}
            </button>
          ) : null}
        </div>
      </div>
      {editing ? (
        <div className="settings-telegram-setup">
          <label htmlFor="telegram-bot-token">{t('Токен бота от BotFather')}</label>
          <div className="settings-telegram-input-row">
            <input
              id="telegram-bot-token"
              type="password"
              autoComplete="off"
              value={token}
              onChange={(event) => setToken(event.target.value)}
              placeholder="123456789:…"
            />
            <button
              type="button"
              className="button button-primary"
              disabled={busy || !token.trim()}
              onClick={() =>
                void action(async () => {
                  const value = await api.configureTelegram(token.trim());
                  setToken('');
                  setEditing(false);
                  return value;
                })
              }
            >
              {busy ? <LoaderCircle size={16} aria-hidden="true" /> : null}
              {t('Сохранить бота')}
            </button>
          </div>
          <small>{t('Токен хранится зашифрованным на сервере. Не отправляй его в чат.')}</small>
        </div>
      ) : null}
      {status?.pairingUrl && !status.linked ? (
        <div className="settings-telegram-pairing">
          <p>
            {t(
              'Открой ссылку в Telegram и нажми Start, затем вернись сюда. Ссылка действует 10 минут.',
            )}
          </p>
          <a
            className="button button-secondary"
            href={status.pairingUrl}
            target="_blank"
            rel="noopener noreferrer"
          >
            {t('Открыть бота в Telegram')}
          </a>
          <button
            type="button"
            className="settings-text-button"
            disabled={busy}
            onClick={() => void action(api.telegramStatus)}
          >
            {t('Проверить подключение')}
          </button>
        </div>
      ) : null}
      <div className="settings-telegram-reminders">
        <div className="settings-telegram-reminder-heading">
          <div>
            <strong>{t('Напоминания в Telegram')}</strong>
            <small>
              {status?.reminders?.ready
                ? t('Автоматическая отправка работает')
                : t(
                    reminderProblems[status?.reminders?.problem ?? ''] ??
                      'Ожидание планировщика или привязки чата',
                  )}
            </small>
          </div>
          <label className="settings-telegram-switch">
            <input
              type="checkbox"
              checked={status?.reminders?.enabled ?? false}
              disabled={busy || !status?.linked}
              onChange={(event) =>
                void action(() =>
                  api.saveTelegramReminders(
                    event.target.checked,
                    status?.reminders?.leadMinutes ?? 10,
                  ),
                )
              }
            />
            <span>{t('Включить')}</span>
          </label>
        </div>
        <div className="settings-telegram-reminder-controls">
          <label>
            {t('Предупредить')}
            <select
              value={status?.reminders?.leadMinutes ?? 10}
              disabled={busy || !status?.linked}
              onChange={(event) =>
                void action(() =>
                  api.saveTelegramReminders(
                    status?.reminders?.enabled ?? false,
                    Number(event.target.value) as 0 | 5 | 10 | 15 | 30 | 60,
                  ),
                )
              }
            >
              {[0, 5, 10, 15, 30, 60].map((minutes) => (
                <option key={minutes} value={minutes}>
                  {minutes === 0 ? t('В момент начала') : t('За {minutes} минут', { minutes })}
                </option>
              ))}
            </select>
          </label>
          <span>
            {t('Часовой пояс')}: {status?.reminders?.timeZone ?? '—'}
          </span>
          <button
            type="button"
            className="button button-secondary"
            disabled={busy || !status?.linked}
            onClick={() =>
              void (async () => {
                setBusy(true);
                setError('');
                setTestSent(false);
                try {
                  await api.testTelegramReminder();
                  setTestSent(true);
                } catch (failure) {
                  setError(
                    failure instanceof Error
                      ? failure.message
                      : t('Не удалось отправить тестовое уведомление.'),
                  );
                } finally {
                  setBusy(false);
                }
              })()
            }
          >
            {t('Отправить тестовое уведомление')}
          </button>
        </div>
        {testSent ? (
          <small role="status">
            {t('Тестовое сообщение отправлено. Оно не подтверждает работу планировщика.')}
          </small>
        ) : null}
        {status?.reminders?.lastRunAt ? (
          <small>
            {t('Последняя успешная проверка')}:{' '}
            {new Intl.DateTimeFormat(language === 'en' ? 'en-US' : 'ru-RU', {
              dateStyle: 'medium',
              timeStyle: 'short',
              timeZone: status.reminders.timeZone,
            }).format(new Date(status.reminders.lastRunAt))}
          </small>
        ) : null}
      </div>
      {error ? (
        <p className="settings-inline-error" role="alert">
          {t(error)}
        </p>
      ) : null}
    </>
  );
}
