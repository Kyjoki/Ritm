import { useI18n } from '../lib/i18n';
import { useEffect, useId, useRef, useState } from 'react';
import {
  AlertCircle,
  Bell,
  Check,
  CheckCircle2,
  ChevronRight,
  Globe2,
  KeyRound,
  LoaderCircle,
  LogOut,
  Moon,
  Palette,
  ShieldCheck,
  Sparkles,
  Sun,
  UserRound,
  X,
} from 'lucide-react';
import type {
  AiStatus,
  GoogleCalendarStatus,
  GoogleOAuthSetup,
  Settings,
} from '../../shared/types';
import { Dialog } from '../components/Dialog';
import { GoogleSetupDialog } from '../components/GoogleSetupDialog';
import { TelegramConnection } from '../components/TelegramConnection';
import '../styles/calendar-settings.css';

interface SettingsPageProps {
  settings: Settings;
  aiStatus: AiStatus;
  googleStatus: GoogleCalendarStatus;
  onConnectGoogle: (extendedColors?: boolean) => Promise<void>;
  onConnectGoogleTasks?: () => Promise<void>;
  googleTasksMessage?: string;
  onDisconnectGoogle: () => Promise<void>;
  onGoogleConfigured?: () => Promise<void>;
  onSave: (settings: Settings) => Promise<void>;
  onConfigureAI: (apiKey: string, model: string) => Promise<void>;
  onDisconnectAI: () => Promise<void>;
  onLogout?: () => Promise<void>;
}

const TIME_ZONES = [
  ['Asia/Qyzylorda', 'Кызылорда · UTC+5'],
  ['Asia/Almaty', 'Алматы, Астана · UTC+5'],
  ['Europe/Moscow', 'Москва · UTC+3'],
  ['Europe/Kyiv', 'Киев'],
  ['Europe/Minsk', 'Минск · UTC+3'],
  ['Asia/Tashkent', 'Ташкент · UTC+5'],
  ['Asia/Bishkek', 'Бишкек · UTC+6'],
  ['Europe/Berlin', 'Берлин'],
  ['Europe/London', 'Лондон'],
  ['America/New_York', 'Нью-Йорк'],
  ['UTC', 'Всемирное время · UTC'],
];

function errorText(error: unknown, t: ReturnType<typeof useI18n>['t']): string {
  return error instanceof Error
    ? t(error.message)
    : t('Не удалось сохранить изменения. Попробуй ещё раз.');
}

export function SettingsPage({
  settings,
  aiStatus,
  googleStatus,
  onConnectGoogle,
  onConnectGoogleTasks,
  googleTasksMessage,
  onDisconnectGoogle,
  onGoogleConfigured,
  onSave,
  onConfigureAI,
  onDisconnectAI,
  onLogout,
}: SettingsPageProps) {
  const { t } = useI18n();
  const [draft, setDraft] = useState<Settings>(settings);
  const [saving, setSaving] = useState(false);
  const [saveState, setSaveState] = useState<'idle' | 'saved' | 'error'>('idle');
  const [error, setError] = useState('');
  const [notificationError, setNotificationError] = useState('');
  const [permissionBusy, setPermissionBusy] = useState(false);
  const [key, setKey] = useState('');
  const [model, setModel] = useState(aiStatus.model);
  const [connectionBusy, setConnectionBusy] = useState(false);
  const [connectionError, setConnectionError] = useState('');
  const [connectionNotice, setConnectionNotice] = useState('');
  const [disconnecting, setDisconnecting] = useState(false);
  const [loggingOut, setLoggingOut] = useState(false);
  const [googleBusy, setGoogleBusy] = useState(false);
  const [googleError, setGoogleError] = useState('');
  const [googleNotice, setGoogleNotice] = useState('');
  const [googleSetupOpen, setGoogleSetupOpen] = useState(false);
  const [googleSetup, setGoogleSetup] = useState<GoogleOAuthSetup | null>(null);
  const [googleStatusUnknown, setGoogleStatusUnknown] = useState(false);
  const [confirmGoogleDisconnect, setConfirmGoogleDisconnect] = useState(false);
  const dialogRef = useRef<HTMLDialogElement>(null);
  const secretInputRef = useRef<HTMLInputElement>(null);
  const titleId = useId();
  const previousSettings = useRef(settings);
  async function googleAction(disconnect = false, extendedColors?: boolean) {
    setGoogleBusy(true);
    setGoogleError('');
    try {
      if (disconnect) {
        await onDisconnectGoogle();
        setGoogleStatusUnknown(false);
        setConfirmGoogleDisconnect(false);
        setConnectionNotice(t('Google Calendar отключён от Ritm.'));
      } else await onConnectGoogle(extendedColors);
    } catch (error) {
      setGoogleError(errorText(error, t));
    } finally {
      setGoogleBusy(false);
    }
  }
  async function googleConfigured(configuration: GoogleOAuthSetup, message: string) {
    setGoogleSetup(configuration);
    setGoogleError('');
    setGoogleNotice(message);
    try {
      await onGoogleConfigured?.();
      setGoogleStatusUnknown(false);
    } catch (failure) {
      setGoogleStatusUnknown(true);
      setGoogleNotice(
        t('{message} Статус подключения не обновился. Обновите страницу.', { message: t(message) }),
      );
      throw failure;
    }
  }
  const googleConfiguredLocally = googleSetup?.configured ?? googleStatus.configured;
  useEffect(() => {
    setGoogleSetup(null);
    setGoogleStatusUnknown(false);
  }, [googleStatus]);
  useEffect(() => {
    const previous = previousSettings.current;
    previousSettings.current = settings;
    setDraft((current) => {
      const next = { ...settings };
      function preserve<K extends keyof Settings>(key: K) {
        if (current[key] !== previous[key]) next[key] = current[key];
      }
      for (const key of Object.keys(settings) as (keyof Settings)[]) preserve(key);
      return next;
    });
  }, [settings]);
  const dirty = JSON.stringify(draft) !== JSON.stringify(settings);
  const initials =
    draft.displayName
      .trim()
      .split(/\s+/)
      .map((part) => part[0])
      .slice(0, 2)
      .join('')
      .toUpperCase() || t('Р');

  function update<K extends keyof Settings>(field: K, value: Settings[K]) {
    setDraft((current) => ({ ...current, [field]: value }));
    setSaveState('idle');
    setError('');
  }

  async function save(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!dirty || saving) return;
    if (!draft.displayName.trim()) {
      setError(t('Введи имя, которым к тебе будет обращаться помощник.'));
      setSaveState('error');
      return;
    }
    if (draft.workDayEnd <= draft.workDayStart) {
      setError(t('Конец рабочего дня должен быть позже начала.'));
      setSaveState('error');
      return;
    }
    setSaving(true);
    setError('');
    try {
      const normalized = {
        ...draft,
        displayName: draft.displayName.trim(),
        email: draft.email.trim(),
      };
      await onSave(normalized);
      setDraft(normalized);
      setSaveState('saved');
    } catch (failure) {
      setError(errorText(failure, t));
      setSaveState('error');
    } finally {
      setSaving(false);
    }
  }

  async function toggleNotifications(enabled: boolean) {
    setNotificationError('');
    if (!enabled) {
      update('notifications', false);
      return;
    }
    if (!('Notification' in window)) {
      setNotificationError(t('Этот браузер не поддерживает уведомления.'));
      return;
    }
    setPermissionBusy(true);
    try {
      const permission =
        Notification.permission === 'granted' ? 'granted' : await Notification.requestPermission();
      if (permission === 'granted') update('notifications', true);
      else setNotificationError(t('Разреши уведомления для Ritm в настройках браузера.'));
    } catch {
      setNotificationError(t('Не удалось запросить разрешение. Проверь настройки браузера.'));
    } finally {
      setPermissionBusy(false);
    }
  }

  function openConnection() {
    if (aiStatus.source === 'environment') return;
    setKey('');
    setModel(aiStatus.model);
    setConnectionError('');
    setConnectionNotice('');
    dialogRef.current?.showModal();
    secretInputRef.current?.focus();
  }

  function closeConnection() {
    if (connectionBusy) return;
    dialogRef.current?.close();
    setKey('');
    setConnectionError('');
  }

  async function configure(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (connectionBusy) return;
    setConnectionBusy(true);
    setConnectionError('');
    try {
      await onConfigureAI(key.trim(), model.trim());
      setKey('');
      dialogRef.current?.close();
      setConnectionNotice(t('Настройки OpenAI сохранены.'));
    } catch (failure) {
      setConnectionError(errorText(failure, t));
    } finally {
      setConnectionBusy(false);
    }
  }

  async function disconnect() {
    setDisconnecting(true);
    setConnectionNotice('');
    setConnectionError('');
    try {
      await onDisconnectAI();
      setConnectionNotice(t('Сохранённый ключ удалён.'));
    } catch (failure) {
      setConnectionError(errorText(failure, t));
    } finally {
      setDisconnecting(false);
    }
  }

  async function logout() {
    if (!onLogout || loggingOut) return;
    setLoggingOut(true);
    try {
      await onLogout();
    } catch (failure) {
      setError(errorText(failure, t));
    } finally {
      setLoggingOut(false);
    }
  }

  return (
    <div className="settings-page">
      <header className="page-heading">
        <div>
          <p className="page-eyebrow">{t('Ritm под твой образ жизни')}</p>
          <h1>{t('Настройки')}</h1>
          <p className="page-description">{t('Твоё пространство. Твои правила.')}</p>
        </div>
        <span className="settings-top-status">
          <ShieldCheck size={17} aria-hidden="true" />
          {t('Личное пространство')}
        </span>
      </header>
      <form onSubmit={save} className="settings-form">
        <fieldset className="settings-form-fields" disabled={saving}>
          <div className="settings-grid">
            <section className="panel settings-card">
              <div className="settings-card-title">
                <Globe2 size={19} aria-hidden="true" />
                <h2>{t('Язык и время')}</h2>
              </div>
              <label className="settings-field">
                {t('Язык интерфейса')}
                <select
                  className="field"
                  value={draft.language}
                  onChange={(event) =>
                    update('language', event.target.value as Settings['language'])
                  }
                >
                  <option value="ru">{t('Русский')}</option>
                  <option value="en">English</option>
                </select>
              </label>
              <label className="settings-field">
                {t('Часовой пояс')}
                <select
                  className="field"
                  value={draft.timeZone}
                  onChange={(event) => update('timeZone', event.target.value)}
                >
                  {!TIME_ZONES.some(([value]) => value === draft.timeZone) ? (
                    <option value={draft.timeZone}>{draft.timeZone}</option>
                  ) : null}
                  {TIME_ZONES.map(([value, label]) => (
                    <option key={value} value={value}>
                      {t(label)}
                    </option>
                  ))}
                </select>
              </label>
              <div className="settings-work-hours">
                <label className="settings-field">
                  {t('Начало дня')}
                  <input
                    className="field"
                    type="time"
                    value={draft.workDayStart}
                    required
                    onChange={(event) => update('workDayStart', event.target.value)}
                  />
                </label>
                <label className="settings-field">
                  {t('Конец дня')}
                  <input
                    className="field"
                    type="time"
                    value={draft.workDayEnd}
                    required
                    onChange={(event) => update('workDayEnd', event.target.value)}
                  />
                </label>
              </div>
              <span className="settings-hint">
                {t('Помощник учитывает эти часы при планировании.')}
              </span>
            </section>
            <section className="panel settings-card">
              <div className="settings-card-title">
                <UserRound size={19} aria-hidden="true" />
                <h2>{t('Аккаунт')}</h2>
              </div>
              <div className="settings-profile">
                <div className="settings-avatar" aria-hidden="true">
                  {initials}
                </div>
                <div>
                  <strong>{draft.displayName || t('Твоё имя')}</strong>
                  <span>{t('Твой личный Ritm')}</span>
                </div>
              </div>
              <label className="settings-field">
                {t('Имя')}
                <input
                  className="field"
                  name="displayName"
                  autoComplete="name"
                  maxLength={60}
                  required
                  value={draft.displayName}
                  onChange={(event) => update('displayName', event.target.value)}
                />
              </label>
              <label className="settings-field">
                {t('Электронная почта')}
                <input
                  className="field"
                  name="email"
                  type="email"
                  autoComplete="email"
                  maxLength={254}
                  value={draft.email}
                  placeholder={t('Твоя почта')}
                  onChange={(event) => update('email', event.target.value)}
                />
                <span className="settings-hint">
                  {t('Для профиля. Почтовые уведомления пока не подключены.')}
                </span>
              </label>
            </section>

            <section className="panel settings-card">
              <div className="settings-card-title">
                <Palette size={19} aria-hidden="true" />
                <h2>{t('Оформление')}</h2>
              </div>
              <p className="settings-card-copy">
                {t('Фиолетовые оттенки в твоём любимом освещении.')}
              </p>
              <div
                className="settings-theme-options"
                role="group"
                aria-label={t('Тема приложения')}
              >
                {(
                  [
                    { value: 'light', label: t('Светлая'), icon: Sun },
                    { value: 'dark', label: t('Тёмная'), icon: Moon },
                    { value: 'system', label: t('Системная'), icon: Sparkles },
                  ] as const
                ).map(({ value, label, icon: Icon }) => (
                  <button
                    type="button"
                    key={value}
                    className={`settings-theme-option ${draft.theme === value ? 'settings-active' : ''}`}
                    aria-pressed={draft.theme === value}
                    onClick={() => update('theme', value)}
                  >
                    <span className={`settings-theme-preview settings-preview-${value}`}>
                      <i />
                      <i />
                      <i />
                    </span>
                    <span>
                      <Icon size={16} aria-hidden="true" />
                      {t(label)}
                      {draft.theme === value ? <Check size={14} aria-hidden="true" /> : null}
                    </span>
                  </button>
                ))}
              </div>
              <label className="settings-field">
                {t('Боковая панель')}
                <select
                  className="field"
                  value={draft.sidebar}
                  onChange={(event) => update('sidebar', event.target.value as Settings['sidebar'])}
                >
                  <option value="dark">{t('Графитовая')}</option>
                  <option value="light">{t('Светлая')}</option>
                </select>
              </label>
              <span className="settings-hint">
                {t('Новое оформление появится после сохранения.')}
              </span>
            </section>

            <section className="panel settings-card">
              <div className="settings-card-title">
                <Bell size={19} aria-hidden="true" />
                <h2>{t('Уведомления')}</h2>
              </div>
              <label className="settings-switch-row">
                <span>
                  {t('Напоминания о задачах')}
                  <small>{t('За 15 минут до начала, пока Ritm открыт')}</small>
                </span>
                <input
                  className="settings-switch"
                  type="checkbox"
                  role="switch"
                  checked={draft.notifications}
                  disabled={permissionBusy}
                  onChange={(event) => void toggleNotifications(event.target.checked)}
                />
              </label>
              <label className="settings-switch-row">
                <span>
                  {t('Утренний план')}
                  <small>{t('Сводка в начале рабочего дня, пока Ritm открыт')}</small>
                </span>
                <input
                  className="settings-switch"
                  type="checkbox"
                  role="switch"
                  checked={draft.dailyBriefing}
                  disabled={!draft.notifications}
                  onChange={(event) => update('dailyBriefing', event.target.checked)}
                />
              </label>
              {notificationError ? (
                <p className="settings-inline-error" role="alert">
                  <AlertCircle size={16} aria-hidden="true" />
                  {t(notificationError)}
                </p>
              ) : (
                <p className="settings-hint settings-notification-note">
                  {t('Для напоминаний понадобится разрешение браузера.')}
                </p>
              )}
              <div className="settings-quiet-note">
                <Moon size={17} aria-hidden="true" />
                <span>
                  {t('Только полезные напоминания.')}
                  <br />
                  {t('В твоём ритме.')}
                </span>
              </div>
            </section>

            <section className="panel settings-card settings-connections">
              <div className="settings-card-title">
                <Sparkles size={19} aria-hidden="true" />
                <h2>{t('Подключения')}</h2>
              </div>
              <div className="settings-connection-row">
                <div className="settings-provider-icon">
                  <Sparkles size={20} aria-hidden="true" />
                </div>
                <div className="settings-connection-copy">
                  <strong>OpenAI</strong>
                  <span
                    className={`settings-connection-status ${aiStatus.configured ? 'settings-configured' : ''}`}
                  >
                    <i />
                    {aiStatus.configured
                      ? t('Ключ настроен · {model}', { model: aiStatus.model })
                      : t('Не настроен')}
                  </span>
                  {aiStatus.source === 'environment' ? (
                    <small>{t('Настройкой управляет сервер')}</small>
                  ) : null}
                </div>
                <div className="settings-connection-actions">
                  {aiStatus.source === 'environment' ? (
                    <span className="settings-coming">{t('На сервере')}</span>
                  ) : (
                    <button
                      type="button"
                      className="button button-secondary"
                      onClick={openConnection}
                    >
                      {aiStatus.configured ? t('Изменить') : t('Настроить')}
                      <ChevronRight size={16} aria-hidden="true" />
                    </button>
                  )}
                  {aiStatus.source === 'saved' ? (
                    <button
                      type="button"
                      className="settings-text-button"
                      disabled={disconnecting}
                      onClick={() => void disconnect()}
                    >
                      {disconnecting ? t('Удаляем…') : t('Удалить ключ')}
                    </button>
                  ) : null}
                </div>
              </div>
              <div className="settings-connection-row">
                <div className="settings-provider-icon settings-calendar-provider">
                  <CalendarMark />
                </div>
                <div className="settings-connection-copy">
                  <strong>Google Calendar</strong>
                  <span
                    className={`settings-connection-status ${!googleStatusUnknown && googleStatus.status === 'connected' ? 'settings-configured' : ''}`}
                  >
                    <i />
                    {googleStatusUnknown
                      ? t('Статус подключения не обновился')
                      : googleStatus.status === 'connected'
                        ? t('Подключён')
                        : googleStatus.status === 'reauth_required'
                          ? t('Нужно подключить заново')
                          : googleConfiguredLocally
                            ? t('Не подключён')
                            : t('Нужна настройка OAuth-клиента')}
                  </span>
                  <small>
                    {googleConfiguredLocally
                      ? t('Основной календарь · просмотр, создание и редактирование событий')
                      : t('Добавьте Client ID и Client Secret из Google Cloud')}
                  </small>
                  {googleStatus.status === 'connected' ? (
                    <small>
                      {googleStatus.extendedColors
                        ? t('Полная палитра включена')
                        : t(
                            'Для новых оттенков Google попросит разрешение на управление календарями.',
                          )}
                    </small>
                  ) : null}
                  {googleStatus.tasksEnabled ? (
                    <small>{t('Google Tasks: отметки выполнения подключены')}</small>
                  ) : null}
                </div>
                <div className="settings-connection-actions">
                  <button
                    type="button"
                    className="button button-secondary"
                    disabled={googleBusy}
                    onClick={() => {
                      setGoogleError('');
                      setGoogleNotice('');
                      setGoogleSetupOpen(true);
                    }}
                  >
                    {googleConfiguredLocally ? t('Настройки') : t('Настроить')}
                  </button>
                  {googleConfiguredLocally ? (
                    <button
                      type="button"
                      className="button button-secondary"
                      disabled={googleBusy}
                      onClick={() => void googleAction()}
                    >
                      {googleBusy
                        ? t('Подождите…')
                        : !googleStatusUnknown &&
                            ['connected', 'reauth_required'].includes(googleStatus.status)
                          ? t('Переподключить')
                          : t('Подключить')}
                    </button>
                  ) : null}
                  {googleTasksMessage ? (
                    <p className="settings-connection-detail">{t(googleTasksMessage)}</p>
                  ) : null}
                  {googleConfiguredLocally &&
                  googleStatus.status === 'connected' &&
                  !googleStatus.tasksEnabled &&
                  onConnectGoogleTasks ? (
                    <button
                      type="button"
                      className="button button-secondary"
                      disabled={googleBusy}
                      onClick={() => {
                        setGoogleBusy(true);
                        setGoogleError('');
                        void onConnectGoogleTasks()
                          .catch((error) => setGoogleError(errorText(error, t)))
                          .finally(() => setGoogleBusy(false));
                      }}
                    >
                      {t('Подключить Google Tasks')}
                    </button>
                  ) : null}
                  {googleConfiguredLocally &&
                  googleStatus.status === 'connected' &&
                  !googleStatus.extendedColors ? (
                    <button
                      type="button"
                      className="button button-secondary"
                      disabled={googleBusy}
                      onClick={() => void googleAction(false, true)}
                    >
                      {t('Разрешить новые цвета')}
                    </button>
                  ) : null}
                  {googleConfiguredLocally &&
                  ['connected', 'reauth_required'].includes(googleStatus.status) ? (
                    <button
                      type="button"
                      className="settings-text-button"
                      disabled={googleBusy}
                      onClick={() => {
                        setGoogleError('');
                        setConfirmGoogleDisconnect(true);
                      }}
                    >
                      {t('Отключить')}
                    </button>
                  ) : null}
                </div>
              </div>
              {googleNotice ? (
                <p className="settings-connection-notice" role="status">
                  <CheckCircle2 size={16} aria-hidden="true" />
                  {t(googleNotice)}
                </p>
              ) : null}
              {googleError && !confirmGoogleDisconnect ? (
                <p className="settings-inline-error" role="alert">
                  <AlertCircle size={16} aria-hidden="true" />
                  {t(googleError)}
                </p>
              ) : null}
              <TelegramConnection />
              {connectionNotice ? (
                <p className="settings-connection-notice" role="status">
                  <CheckCircle2 size={16} aria-hidden="true" />
                  {t(connectionNotice)}
                </p>
              ) : null}
              {connectionError && !dialogRef.current?.open ? (
                <p className="settings-inline-error" role="alert">
                  <AlertCircle size={16} aria-hidden="true" />
                  {t(connectionError)}
                </p>
              ) : null}
            </section>
          </div>
        </fieldset>
        <div className="settings-save-bar">
          <div
            className={`settings-save-status ${saveState === 'error' ? 'settings-error-status' : ''}`}
            aria-live="polite"
          >
            {saving ? (
              <>
                <LoaderCircle size={16} className="settings-spinner" aria-hidden="true" />
                {t('Сохраняем…')}
              </>
            ) : error ? (
              <>
                <AlertCircle size={16} aria-hidden="true" />
                {t(error)}
              </>
            ) : dirty ? (
              t('Есть несохранённые изменения')
            ) : saveState === 'saved' ? (
              <>
                <CheckCircle2 size={16} aria-hidden="true" />
                {t('Настройки сохранены')}
              </>
            ) : (
              <>
                <Check size={16} aria-hidden="true" />
                {t('Всё сохранено')}
              </>
            )}
          </div>
          <div className="settings-save-actions">
            {dirty ? (
              <button
                type="button"
                className="settings-text-button"
                disabled={saving}
                onClick={() => {
                  setDraft(settings);
                  setError('');
                  setSaveState('idle');
                }}
              >
                {t('Отменить изменения')}
              </button>
            ) : null}
            <button className="button button-primary" type="submit" disabled={!dirty || saving}>
              {saving ? t('Сохраняем…') : t('Сохранить настройки')}
            </button>
          </div>
        </div>
      </form>
      {googleSetupOpen ? (
        <GoogleSetupDialog onClose={() => setGoogleSetupOpen(false)} onChanged={googleConfigured} />
      ) : null}
      {confirmGoogleDisconnect ? (
        <Dialog
          title={t('Отключить Google Calendar?')}
          onClose={() => setConfirmGoogleDisconnect(false)}
          busy={googleBusy}
        >
          <p className="dialog-copy">
            {t(
              'Ritm перестанет получать и изменять события. События в Google и подключение другого приложения сохранятся.',
            )}
          </p>
          {googleError ? (
            <p className="error-note" role="alert">
              {t(googleError)}
            </p>
          ) : null}
          <div className="dialog-actions">
            <button
              type="button"
              className="button button-secondary"
              disabled={googleBusy}
              onClick={() => setConfirmGoogleDisconnect(false)}
            >
              {t('Отмена')}
            </button>
            <button
              type="button"
              className="button button-primary"
              disabled={googleBusy}
              onClick={() => void googleAction(true)}
            >
              {googleBusy ? t('Отключаем…') : t('Отключить')}
            </button>
          </div>
        </Dialog>
      ) : null}
      {onLogout ? (
        <button
          type="button"
          className="settings-logout"
          onClick={() => void logout()}
          disabled={loggingOut}
        >
          <LogOut size={17} aria-hidden="true" />
          {loggingOut ? t('Выходим…') : t('Выйти из аккаунта')}
        </button>
      ) : null}

      <dialog
        ref={dialogRef}
        className="settings-key-dialog"
        aria-labelledby={titleId}
        onCancel={(event) => {
          if (connectionBusy) event.preventDefault();
          else {
            setKey('');
            setConnectionError('');
          }
        }}
        onClose={() => setKey('')}
        onClick={(event) => {
          if (event.target === event.currentTarget) {
            const b = event.currentTarget.getBoundingClientRect();
            if (
              event.clientX < b.left ||
              event.clientX > b.right ||
              event.clientY < b.top ||
              event.clientY > b.bottom
            )
              closeConnection();
          }
        }}
      >
        <form onSubmit={configure} className="settings-key-form">
          <header className="settings-dialog-head">
            <div className="settings-key-icon">
              <KeyRound size={23} aria-hidden="true" />
            </div>
            <button
              type="button"
              className="settings-close"
              aria-label={t('Закрыть настройку OpenAI')}
              disabled={connectionBusy}
              onClick={closeConnection}
            >
              <X size={21} aria-hidden="true" />
            </button>
          </header>
          <h2 id={titleId}>{t('Твой помощник на связи')}</h2>
          <p className="settings-dialog-copy">
            {t('Добавь ключ OpenAI, чтобы планировать день и разбирать задачи вместе с Ritm.')}
          </p>
          <label className="settings-field">
            {t('API-ключ OpenAI')}
            <input
              ref={secretInputRef}
              className="field"
              type="password"
              autoComplete="off"
              autoCapitalize="none"
              spellCheck={false}
              required
              minLength={20}
              maxLength={512}
              value={key}
              placeholder="sk-…"
              onChange={(event) => setKey(event.target.value)}
              disabled={connectionBusy}
            />
          </label>
          <label className="settings-field">
            {t('Модель')}
            <input
              className="field"
              value={model}
              required
              maxLength={100}
              placeholder={t('Название модели')}
              onChange={(event) => setModel(event.target.value)}
              disabled={connectionBusy}
            />
          </label>
          <p className="settings-key-security">
            <ShieldCheck size={17} aria-hidden="true" />
            {t('Ключ передаётся серверу и не сохраняется в браузере.')}
          </p>
          {connectionError ? (
            <p className="settings-inline-error" role="alert">
              <AlertCircle size={17} aria-hidden="true" />
              {t(connectionError)}
            </p>
          ) : null}
          <div className="settings-dialog-actions">
            <button
              type="button"
              className="button button-secondary"
              disabled={connectionBusy}
              onClick={closeConnection}
            >
              {t('Отмена')}
            </button>
            <button
              type="submit"
              className="button button-primary"
              disabled={connectionBusy || !key.trim() || !model.trim()}
            >
              {connectionBusy ? (
                <>
                  <LoaderCircle className="settings-spinner" size={17} aria-hidden="true" />
                  {t('Сохраняем…')}
                </>
              ) : (
                t('Сохранить ключ')
              )}
            </button>
          </div>
        </form>
      </dialog>
    </div>
  );
}

function CalendarMark() {
  return (
    <svg
      width="21"
      height="21"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <rect x="3" y="5" width="18" height="16" rx="3" />
      <path d="M16 3v4M8 3v4M3 11h18M8 15h2M14 15h2" />
    </svg>
  );
}
