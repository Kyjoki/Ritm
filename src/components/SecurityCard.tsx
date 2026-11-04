import { useCallback, useEffect, useState, type KeyboardEvent } from 'react';
import { AlertCircle, Copy, LoaderCircle, ShieldCheck } from 'lucide-react';
import qrcode from 'qrcode-generator';
import { api, type SecurityOverview } from '../lib/api';
import { useI18n } from '../lib/i18n';

type Panel = 'none' | 'setup' | 'disable' | 'regenerate';

function qrDataUrl(text: string) {
  const code = qrcode(0, 'M');
  code.addData(text);
  code.make();
  return code.createDataURL(5, 8);
}
const digitsOnly = (value: string) => value.replace(/\s/g, '');

/** Security card: two-factor setup, recovery codes and the signed-in device list. */
export function SecurityCard() {
  const { t, language } = useI18n();
  const [overview, setOverview] = useState<SecurityOverview | null>(null);
  const [panel, setPanel] = useState<Panel>('none');
  const [setup, setSetup] = useState<{ secret: string; qr: string } | null>(null);
  const [codes, setCodes] = useState<string[] | null>(null);
  const [code, setCode] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [copied, setCopied] = useState(false);

  const refresh = useCallback(async () => {
    try {
      setOverview(await api.security());
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : t('Не удалось загрузить защиту.'));
    }
  }, [t]);
  useEffect(() => {
    void refresh();
  }, [refresh]);

  async function run(operation: () => Promise<void>) {
    if (busy) return;
    setBusy(true);
    setError('');
    try {
      await operation();
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : t('Не удалось выполнить действие.'));
    } finally {
      setBusy(false);
    }
  }
  const close = () => {
    setPanel('none');
    setSetup(null);
    setCode('');
    setPassword('');
    setError('');
  };
  const startSetup = () =>
    run(async () => {
      const value = await api.setupTotp();
      setSetup({ secret: value.secret, qr: qrDataUrl(value.otpauthUrl) });
      setPanel('setup');
    });
  const confirm = () =>
    run(async () => {
      const result = await api.confirmTotp(digitsOnly(code));
      setCodes(result.recoveryCodes);
      setCopied(false);
      close();
      await refresh();
    });
  const disable = () =>
    run(async () => {
      const value = code.trim();
      await api.disableTotp(
        password,
        /^\d{6}$/.test(digitsOnly(value)) ? { totp: digitsOnly(value) } : { recoveryCode: value },
      );
      close();
      setCodes(null);
      await refresh();
    });
  const regenerate = () =>
    run(async () => {
      const result = await api.regenerateRecoveryCodes(digitsOnly(code));
      setCodes(result.recoveryCodes);
      setCopied(false);
      close();
      await refresh();
    });
  const revoke = (id: string) =>
    run(async () => {
      await api.revokeSession(id);
      await refresh();
    });
  const revokeOthers = () =>
    run(async () => {
      await api.revokeOtherSessions();
      await refresh();
    });
  const copyCodes = async () => {
    try {
      await navigator.clipboard.writeText(codes?.join('\n') ?? '');
      setCopied(true);
    } catch {
      setError(t('Не удалось скопировать. Выделите коды вручную.'));
    }
  };
  // The settings form must not submit while a code is typed.
  const onEnter = (action: () => Promise<void>) => (event: KeyboardEvent) => {
    if (event.key !== 'Enter') return;
    event.preventDefault();
    void action();
  };
  const formatTime = (value: string) =>
    new Date(value).toLocaleString(language === 'en' ? 'en-US' : 'ru-RU', {
      dateStyle: 'medium',
      timeStyle: 'short',
    });
  const others = overview?.sessions.filter((session) => !session.current).length ?? 0;
  const codeReady = digitsOnly(code).length === 6;

  return (
    <section className="panel settings-card settings-security">
      <div className="settings-card-title">
        <ShieldCheck size={18} aria-hidden="true" />
        <h2>{t('Безопасность')}</h2>
      </div>
      <div className="settings-security-row">
        <div>
          <strong>{t('Двухфакторная защита')}</strong>
          <small>
            {overview?.totpEnabled
              ? t('Включена · кодов восстановления: {count}', {
                  count: overview.recoveryCodesLeft,
                })
              : t('Выключена. Код из приложения-аутентификатора защитит вход.')}
          </small>
        </div>
        {overview ? (
          overview.totpEnabled ? (
            <div className="settings-security-actions">
              <button
                type="button"
                className="button button-secondary"
                disabled={busy}
                onClick={() => setPanel(panel === 'regenerate' ? 'none' : 'regenerate')}
              >
                {t('Новые коды')}
              </button>
              <button
                type="button"
                className="settings-text-button"
                disabled={busy}
                onClick={() => setPanel(panel === 'disable' ? 'none' : 'disable')}
              >
                {t('Отключить')}
              </button>
            </div>
          ) : (
            <button
              type="button"
              className="button button-secondary"
              disabled={busy}
              onClick={() => void startSetup()}
            >
              {t('Включить')}
            </button>
          )
        ) : null}
      </div>
      {panel === 'setup' && setup ? (
        <div className="settings-security-panel">
          <p>{t('Отсканируй QR-код в приложении-аутентификаторе или введи ключ вручную.')}</p>
          <img src={setup.qr} width={170} height={170} alt={t('QR-код для аутентификатора')} />
          <code className="settings-security-secret">{setup.secret}</code>
          <label htmlFor="security-code">{t('Код из приложения')}</label>
          <div className="settings-telegram-input-row">
            <input
              id="security-code"
              inputMode="numeric"
              autoComplete="one-time-code"
              maxLength={8}
              value={code}
              onChange={(event) => setCode(event.target.value)}
              onKeyDown={onEnter(confirm)}
              placeholder="123456"
            />
            <button
              type="button"
              className="button button-primary"
              disabled={busy || !codeReady}
              onClick={() => void confirm()}
            >
              {t('Подтвердить')}
            </button>
            <button type="button" className="settings-text-button" onClick={close}>
              {t('Отмена')}
            </button>
          </div>
        </div>
      ) : null}
      {panel === 'regenerate' ? (
        <div className="settings-security-panel">
          <p>{t('Старые коды перестанут работать. Введи код из приложения.')}</p>
          <div className="settings-telegram-input-row">
            <input
              aria-label={t('Код из приложения')}
              inputMode="numeric"
              autoComplete="one-time-code"
              maxLength={8}
              value={code}
              onChange={(event) => setCode(event.target.value)}
              onKeyDown={onEnter(regenerate)}
              placeholder="123456"
            />
            <button
              type="button"
              className="button button-primary"
              disabled={busy || !codeReady}
              onClick={() => void regenerate()}
            >
              {t('Создать коды')}
            </button>
            <button type="button" className="settings-text-button" onClick={close}>
              {t('Отмена')}
            </button>
          </div>
        </div>
      ) : null}
      {panel === 'disable' ? (
        <div className="settings-security-panel">
          <p>{t('Для отключения нужны пароль и код из приложения или код восстановления.')}</p>
          <div className="settings-telegram-input-row">
            <input
              type="password"
              aria-label={t('Пароль')}
              autoComplete="current-password"
              maxLength={512}
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              onKeyDown={onEnter(disable)}
              placeholder={t('Пароль')}
            />
            <input
              aria-label={t('Код')}
              autoComplete="one-time-code"
              maxLength={40}
              value={code}
              onChange={(event) => setCode(event.target.value)}
              onKeyDown={onEnter(disable)}
              placeholder={t('Код')}
            />
            <button
              type="button"
              className="button button-primary"
              disabled={busy || !password || !code.trim()}
              onClick={() => void disable()}
            >
              {t('Отключить защиту')}
            </button>
            <button type="button" className="settings-text-button" onClick={close}>
              {t('Отмена')}
            </button>
          </div>
        </div>
      ) : null}
      {codes ? (
        <div className="settings-security-panel" role="status">
          <p>
            <strong>{t('Коды восстановления')}</strong> —{' '}
            {t('сохрани их сейчас, больше они не покажутся. Каждый код работает один раз.')}
          </p>
          <ul className="settings-security-codes">
            {codes.map((item) => (
              <li key={item}>
                <code>{item}</code>
              </li>
            ))}
          </ul>
          <div className="settings-security-actions">
            <button
              type="button"
              className="button button-secondary"
              onClick={() => void copyCodes()}
            >
              <Copy size={15} aria-hidden="true" /> {copied ? t('Скопировано') : t('Скопировать')}
            </button>
            <button
              type="button"
              className="settings-text-button"
              onClick={() => {
                setCodes(null);
                setCopied(false);
              }}
            >
              {t('Я сохранил коды')}
            </button>
          </div>
        </div>
      ) : null}
      {error ? (
        <p className="settings-inline-error" role="alert">
          <AlertCircle size={16} aria-hidden="true" />
          {error}
        </p>
      ) : null}
      <div className="settings-security-devices">
        <div className="settings-security-row">
          <strong>{t('Устройства')}</strong>
          {others > 0 ? (
            <button
              type="button"
              className="settings-text-button"
              disabled={busy}
              onClick={() => void revokeOthers()}
            >
              {t('Выйти на всех других устройствах')}
            </button>
          ) : null}
        </div>
        {!overview ? (
          <LoaderCircle size={16} className="settings-spinner" aria-hidden="true" />
        ) : null}
        <ul className="settings-security-sessions">
          {overview?.sessions.map((session) => (
            <li key={session.id}>
              <div>
                <strong>
                  {session.deviceName}
                  {session.current ? ` · ${t('это устройство')}` : ''}
                </strong>
                <small>
                  {session.client === 'ios' ? 'iPhone' : 'Web'} ·{' '}
                  {t('вход {time}', { time: formatTime(session.createdAt) })} ·{' '}
                  {t('активность {time}', { time: formatTime(session.lastSeenAt) })}
                </small>
              </div>
              {session.current ? null : (
                <button
                  type="button"
                  className="settings-text-button"
                  disabled={busy}
                  onClick={() => void revoke(session.id)}
                >
                  {t('Выйти')}
                </button>
              )}
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}
