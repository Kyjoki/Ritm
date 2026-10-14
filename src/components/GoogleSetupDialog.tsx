import { useI18n, translate, type Language } from '../lib/i18n';
import { useEffect, useRef, useState, type FormEvent } from 'react';
import {
  AlertCircle,
  Check,
  CheckCircle2,
  Copy,
  ExternalLink,
  LoaderCircle,
  ShieldCheck,
  Trash2,
} from 'lucide-react';
import type { GoogleOAuthSetup } from '../../shared/types';
import { api, ApiError } from '../lib/api';
import { Dialog } from './Dialog';
import '../styles/google.css';

interface GoogleSetupDialogProps {
  onClose: () => void;
  onChanged: (configuration: GoogleOAuthSetup, notice: string) => Promise<void>;
}

function setupError(failure: unknown, language: Language): string {
  const t = (source: string) => translate(language, source);
  if (failure instanceof ApiError) {
    if (failure.code === 'GOOGLE_CLIENT_SECRET_REQUIRED')
      return t('Для нового Client ID нужен соответствующий Client Secret.');
    if (failure.code === 'GOOGLE_ENVIRONMENT_CONFIGURATION')
      return t(
        'Этими настройками управляет сервер. Обновите форму, чтобы увидеть актуальные данные.',
      );
    if (failure.code === 'GOOGLE_ORIGIN_REQUIRED')
      return t(
        'У Ritm пока не указан адрес возврата. Настройте адрес приложения на сервере и откройте форму снова.',
      );
    if (failure.code === 'GOOGLE_SETUP_INVALID' || failure.code === 'VALIDATION_ERROR')
      return t(
        'Проверьте Client ID и Client Secret: используйте данные OAuth-клиента типа «Веб-приложение».',
      );
    if (failure.status === 429)
      return t('Слишком много попыток. Подождите немного и повторите действие.');
    if (failure.status === 401) return t('Сессия завершилась. Войдите в Ritm снова.');
    if (failure.status === 403)
      return t('Не удалось подтвердить запрос. Обновите страницу и попробуйте снова.');
    if (failure.status === 0)
      return t('Нет связи с сервером. Проверьте соединение и попробуйте снова.');
  }
  return t('Не удалось выполнить действие. Попробуйте ещё раз.');
}

export function GoogleSetupDialog({ onClose, onChanged }: GoogleSetupDialogProps) {
  const { t, language } = useI18n();
  const [configuration, setConfiguration] = useState<GoogleOAuthSetup | null>(null);
  const [clientId, setClientId] = useState('');
  const [clientSecret, setClientSecret] = useState('');
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [copyNotice, setCopyNotice] = useState('');
  const [confirmRemove, setConfirmRemove] = useState(false);
  const [revision, setRevision] = useState(0);
  const clientIdRef = useRef<HTMLInputElement>(null);
  const clientSecretRef = useRef<HTMLInputElement>(null);
  const redirectRef = useRef<HTMLInputElement>(null);
  const keepButtonRef = useRef<HTMLButtonElement>(null);
  const removeButtonRef = useRef<HTMLButtonElement>(null);
  const noticeRef = useRef<HTMLParagraphElement>(null);
  const wasConfirming = useRef(false);
  const actionLock = useRef(false);

  useEffect(() => {
    let active = true;
    setLoading(true);
    setError('');
    api
      .googleConfiguration()
      .then((next) => {
        if (!active) return;
        setConfiguration(next);
        setClientId(next.clientId);
        setClientSecret('');
      })
      .catch((failure) => {
        if (active) setError(setupError(failure, language));
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
      if (clientSecretRef.current) clientSecretRef.current.value = '';
    };
  }, [revision, language]);

  useEffect(() => {
    if (!loading && configuration?.source !== 'environment') clientIdRef.current?.focus();
  }, [loading, configuration?.source]);

  useEffect(() => {
    if (confirmRemove) {
      wasConfirming.current = true;
      if (!busy) keepButtonRef.current?.focus();
    } else if (wasConfirming.current && !busy) {
      (removeButtonRef.current ?? clientIdRef.current)?.focus();
      wasConfirming.current = false;
    }
  }, [confirmRemove, busy]);

  useEffect(() => {
    if (notice && !busy) noticeRef.current?.focus();
  }, [notice, busy]);

  const serverManaged = configuration?.source === 'environment';
  const trimmedId = clientId.trim();
  const keepingSecret = Boolean(
    configuration?.hasClientSecret && trimmedId === configuration.clientId,
  );
  const dirty =
    configuration && (trimmedId !== configuration.clientId || Boolean(clientSecret.trim()));

  function close() {
    if (actionLock.current) return;
    setClientSecret('');
    if (clientSecretRef.current) clientSecretRef.current.value = '';
    onClose();
  }

  async function reportChange(next: GoogleOAuthSetup, message: string) {
    setConfiguration(next);
    setClientId(next.clientId);
    setClientSecret('');
    setNotice(message);
    try {
      await onChanged(next, message);
    } catch {
      setNotice(t('{p0} Статус подключения не обновился. Обновите страницу.', { p0: message }));
    }
  }

  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (actionLock.current || serverManaged || !configuration?.redirectUri) return;
    setError('');
    setNotice('');
    if (!/^[A-Za-z0-9_-]+\.apps\.googleusercontent\.com$/.test(trimmedId)) {
      setError(
        t(
          'Client ID должен оканчиваться на .apps.googleusercontent.com. Скопируйте его из Google Cloud.',
        ),
      );
      clientIdRef.current?.focus();
      return;
    }
    const secret = clientSecret.trim();
    if (!secret && !keepingSecret) {
      setError(t('Введите Client Secret для этого OAuth-клиента.'));
      clientSecretRef.current?.focus();
      return;
    }
    if (secret && /\s/.test(secret)) {
      setError(
        t('В Client Secret не должно быть пробелов. Скопируйте значение целиком из Google Cloud.'),
      );
      clientSecretRef.current?.focus();
      return;
    }
    actionLock.current = true;
    setBusy(true);
    try {
      const next = await api.configureGoogle({
        clientId: trimmedId,
        ...(secret ? { clientSecret: secret } : {}),
      });
      await reportChange(
        next,
        t('OAuth-клиент сохранён. Доступ к календарю можно разрешить кнопкой «Подключить».'),
      );
    } catch (failure) {
      setError(setupError(failure, language));
    } finally {
      actionLock.current = false;
      setBusy(false);
    }
  }

  async function remove() {
    if (actionLock.current || serverManaged) return;
    actionLock.current = true;
    setBusy(true);
    setError('');
    setNotice('');
    try {
      const next = await api.removeGoogleConfiguration();
      setConfirmRemove(false);
      await reportChange(
        next,
        t('Данные OAuth и подключение удалены. Задачи Ritm и события в Google сохранены.'),
      );
    } catch (failure) {
      setError(setupError(failure, language));
    } finally {
      actionLock.current = false;
      setBusy(false);
    }
  }

  async function copyRedirect() {
    if (!configuration?.redirectUri) return;
    try {
      if (!navigator.clipboard?.writeText) throw new Error('Clipboard unavailable');
      await navigator.clipboard.writeText(configuration.redirectUri);
      setCopyNotice(t('Адрес скопирован'));
    } catch {
      redirectRef.current?.focus();
      redirectRef.current?.select();
      setCopyNotice(t('Адрес выделен. Скопируйте его вручную.'));
    }
  }

  return (
    <Dialog
      title={t('Настройка Google Calendar')}
      onClose={close}
      busy={busy}
      className="google-setup-dialog"
    >
      {loading ? (
        <div className="google-setup-loading" role="status">
          <LoaderCircle className="spinning" size={22} aria-hidden="true" />
          {t('Загружаем настройки…')}
        </div>
      ) : !configuration ? (
        <div className="google-setup-load-error">
          <p className="error-note" role="alert">
            {error}
          </p>
          <button
            type="button"
            className="button button-secondary"
            onClick={() => setRevision((value) => value + 1)}
          >
            {t('Попробовать снова')}
          </button>
        </div>
      ) : (
        <>
          <p className="google-setup-intro">
            {t(
              'Добавьте данные OAuth-клиента из Google Cloud. Доступ к событиям вы разрешите отдельным шагом.',
            )}
          </p>
          <div className="google-setup-status">
            <ShieldCheck size={17} aria-hidden="true" />
            <span>
              {serverManaged
                ? configuration.configured
                  ? t('OAuth-клиент настроен на сервере')
                  : t('Настройка OAuth на сервере не завершена')
                : configuration.configured
                  ? t('OAuth-клиент настроен')
                  : t('OAuth-клиент ещё не настроен')}
            </span>
          </div>
          <section className="google-setup-help" aria-labelledby="google-setup-help-title">
            <h3 id="google-setup-help-title">{t('Что нужно в Google Cloud')}</h3>
            <ol>
              <li>
                {t('Включите')}{' '}
                <a
                  href="https://console.cloud.google.com/apis/library/calendar-json.googleapis.com"
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  Google Calendar API <ExternalLink size={12} aria-hidden="true" />
                </a>
                .
              </li>
              <li>
                {t('Создайте')}{' '}
                <a
                  href="https://console.cloud.google.com/auth/clients"
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  {t('OAuth-клиент')}
                  <ExternalLink size={12} aria-hidden="true" />
                </a>{' '}
                {t('типа «Веб-приложение» (Web application).')}
              </li>
              <li>
                {t(
                  'Добавьте адрес ниже в «Разрешённые URI перенаправления» (Authorized redirect URIs).',
                )}
              </li>
            </ol>
          </section>
          <div className="google-setup-callback">
            <label className="field" htmlFor="google-callback-url">
              {t('Адрес возврата в Ritm (callback URL)')}
            </label>
            <div className="google-setup-copy-row">
              <input
                id="google-callback-url"
                ref={redirectRef}
                readOnly
                value={configuration.redirectUri ?? ''}
                placeholder={t('Адрес возврата пока недоступен')}
                aria-describedby="google-callback-hint"
                spellCheck={false}
                autoCapitalize="none"
              />
              <button
                type="button"
                className="button button-secondary"
                disabled={!configuration.redirectUri}
                onClick={() => void copyRedirect()}
                aria-label={t('Скопировать адрес возврата')}
              >
                <Copy size={16} aria-hidden="true" />
                {t('Копировать')}
              </button>
            </div>
            <p id="google-callback-hint" className="field-hint">
              {configuration.redirectUri
                ? t('Скопируйте адрес без изменений в настройки OAuth-клиента Google.')
                : t(
                    'У Ritm пока не указан адрес возврата. Настройте APP_ORIGIN на сервере, затем откройте форму снова.',
                  )}
            </p>
            {copyNotice ? (
              <p className="google-setup-copy-notice" role="status">
                {copyNotice}
              </p>
            ) : null}
          </div>
          {serverManaged ? (
            <div className="google-setup-managed">
              <label className="field">
                Client ID
                <input
                  readOnly
                  value={configuration.clientId}
                  placeholder={t('Не задан на сервере')}
                  spellCheck={false}
                />
              </label>
              <p className="field-hint">
                {configuration.hasClientSecret
                  ? t(
                      'Client Secret задан на сервере и не отображается. Изменение этих данных доступно в настройках сервера.',
                    )
                  : t('Client Secret ещё не задан на сервере. Завершите настройку на сервере.')}
              </p>
            </div>
          ) : (
            <form onSubmit={save} className="google-setup-form">
              <fieldset disabled={busy || confirmRemove}>
                <label className="field">
                  Client ID
                  <input
                    ref={clientIdRef}
                    required
                    maxLength={512}
                    value={clientId}
                    autoComplete="off"
                    autoCapitalize="none"
                    spellCheck={false}
                    placeholder="…apps.googleusercontent.com"
                    onChange={(event) => {
                      setClientId(event.target.value);
                      setError('');
                      setNotice('');
                    }}
                  />
                </label>
                <label className="field">
                  Client Secret
                  <input
                    ref={clientSecretRef}
                    type="password"
                    required={!keepingSecret}
                    maxLength={2048}
                    value={clientSecret}
                    autoComplete="off"
                    autoCapitalize="none"
                    spellCheck={false}
                    placeholder={
                      keepingSecret
                        ? t('Оставьте пустым, чтобы сохранить текущий секрет')
                        : t('Секрет OAuth-клиента из Google Cloud')
                    }
                    aria-describedby="google-client-secret-hint"
                    onChange={(event) => {
                      setClientSecret(event.target.value);
                      setError('');
                      setNotice('');
                    }}
                  />
                  <span id="google-client-secret-hint" className="field-hint">
                    {keepingSecret
                      ? t(
                          'Секрет уже сохранён и не отображается. При смене Client ID введите новый Client Secret.',
                        )
                      : t('Ritm передаст секрет серверу и не сохранит его в браузере.')}
                  </span>
                </label>
                <div className="google-setup-save-actions">
                  <button
                    type="submit"
                    className="button button-primary"
                    disabled={
                      busy ||
                      !configuration.redirectUri ||
                      !trimmedId ||
                      (!clientSecret.trim() && !keepingSecret) ||
                      !dirty
                    }
                  >
                    {busy ? (
                      <>
                        <LoaderCircle size={16} className="spinning" aria-hidden="true" />
                        {t('Сохраняем…')}
                      </>
                    ) : (
                      t('Сохранить настройки')
                    )}
                  </button>
                  {configuration.source === 'saved' ? (
                    <button
                      ref={removeButtonRef}
                      type="button"
                      className="settings-text-button google-setup-remove"
                      onClick={() => {
                        setError('');
                        setConfirmRemove(true);
                      }}
                    >
                      <Trash2 size={15} aria-hidden="true" />
                      {t('Удалить данные OAuth')}
                    </button>
                  ) : null}
                </div>
              </fieldset>
            </form>
          )}
          {confirmRemove ? (
            <div
              className="google-setup-remove-confirm"
              role="group"
              aria-label={t('Подтверждение удаления OAuth')}
            >
              <strong>{t('Удалить данные OAuth?')}</strong>
              <p>
                {t(
                  'Client ID, Client Secret и доступ Ritm к Google Calendar будут удалены. Ваши задачи и события останутся.',
                )}
              </p>
              <div className="button-row">
                <button
                  ref={keepButtonRef}
                  type="button"
                  className="button button-secondary"
                  disabled={busy}
                  onClick={() => setConfirmRemove(false)}
                >
                  {t('Оставить')}
                </button>
                <button
                  type="button"
                  className="button button-danger"
                  disabled={busy}
                  onClick={() => void remove()}
                >
                  {busy ? t('Удаляем…') : t('Удалить данные')}
                </button>
              </div>
            </div>
          ) : null}
          {error ? (
            <p className="error-note" role="alert">
              <AlertCircle size={16} aria-hidden="true" />
              {error}
            </p>
          ) : null}
          {notice ? (
            <p ref={noticeRef} tabIndex={-1} className="google-setup-notice" role="status">
              <CheckCircle2 size={17} aria-hidden="true" />
              {notice}
            </p>
          ) : null}
          <section className="google-setup-permissions" aria-labelledby="google-permissions-title">
            <h3 id="google-permissions-title">{t('После подключения Ritm сможет')}</h3>
            <ul>
              <li>
                <Check size={14} aria-hidden="true" />
                {t('Показывать события основного календаря')}
              </li>
              <li>
                <Check size={14} aria-hidden="true" />
                {t('Создавать выбранные вами события')}
              </li>
              <li>
                <Check size={14} aria-hidden="true" />
                {t('Сохранять ваши изменения событий')}
              </li>
            </ul>
            <p>
              {t(
                'Google предоставляет права на просмотр, создание, изменение и удаление событий. Ritm использует просмотр, создание и редактирование только основного календаря.',
              )}
            </p>
            <a
              href="https://developers.google.com/identity/protocols/oauth2/web-server"
              target="_blank"
              rel="noopener noreferrer"
            >
              {t('Инструкция Google')}
              <ExternalLink size={12} aria-hidden="true" />
            </a>
          </section>
          <div className="google-setup-footer">
            <button
              type="button"
              className="button button-secondary"
              disabled={busy}
              onClick={close}
            >
              {t('Готово')}
            </button>
          </div>
        </>
      )}
    </Dialog>
  );
}
