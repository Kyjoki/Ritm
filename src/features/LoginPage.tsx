import { useI18n } from '../lib/i18n';
import { useLayoutEffect, useState, type FormEvent } from 'react';
import {
  ArrowLeft,
  ArrowRight,
  CalendarDays,
  Check,
  Eye,
  EyeOff,
  LoaderCircle,
  LockKeyhole,
  Moon,
  Sparkles,
  Sun,
  UserRound,
} from 'lucide-react';
import '../styles/login.css';

export interface LoginCredentials {
  login: string;
  password: string;
}
interface Props {
  onSubmit: (credentials: LoginCredentials) => Promise<void>;
  preview?: boolean;
  onBack?: () => void;
}

export function LoginPage({ onSubmit, preview = false, onBack }: Props) {
  const { t } = useI18n();
  const [login, setLogin] = useState(''),
    [password, setPassword] = useState('');
  const [visible, setVisible] = useState(false),
    [busy, setBusy] = useState(false),
    [error, setError] = useState(''),
    [capsLock, setCapsLock] = useState(false);
  const [theme, setTheme] = useState<'light' | 'dark'>(() =>
    document.documentElement.dataset.theme === 'dark' ? 'dark' : 'light',
  );
  useLayoutEffect(() => {
    const previous = document.documentElement.dataset.theme;
    document.documentElement.dataset.theme = theme;
    return () => {
      if (previous) document.documentElement.dataset.theme = previous;
      else delete document.documentElement.dataset.theme;
    };
  }, [theme]);
  async function submit(event: FormEvent) {
    event.preventDefault();
    if (busy) return;
    setError('');
    if (preview) {
      setError(t('Неверный логин или пароль. Проверь данные и попробуй ещё раз.'));
      return;
    }
    setBusy(true);
    try {
      await onSubmit({ login: login.trim(), password });
      setPassword('');
    } catch (failure) {
      setError(
        failure instanceof Error ? t(failure.message) : t('Не удалось войти. Попробуй ещё раз.'),
      );
    } finally {
      setBusy(false);
    }
  }
  return (
    <div className="signin-page">
      <header className="signin-topbar">
        <span className="brand">
          <span className="brand-mark" aria-hidden="true">
            <img src="/ritm-mark.svg" width="36" height="36" alt="" />
          </span>
          Ritm
        </span>
        <div className="signin-top-actions">
          {preview ? <span className="signin-preview-label">{t('Дизайн входа')}</span> : null}
          <button
            type="button"
            className="signin-theme"
            aria-label={theme === 'dark' ? t('Светлая тема') : t('Тёмная тема')}
            onClick={() => setTheme(theme === 'dark' ? 'light' : 'dark')}
          >
            {theme === 'dark' ? <Sun size={18} /> : <Moon size={18} />}
          </button>
        </div>
      </header>
      <main className="signin-layout">
        <section className="signin-visual" aria-label={t('Личное пространство Ritm')}>
          <div className="signin-visual-copy">
            <span className="signin-eyebrow">
              <span />
              {t('ЛИЧНОЕ ПРОСТРАНСТВО')}
            </span>
            <h1>
              {t('Войди в свой')}
              <br />
              <span>{t('ритм.')}</span>
            </h1>
            <p>
              {t('Место, где планы обретают ясность,')}
              <br />
              {t('а у важного появляется своё время.')}
            </p>
          </div>
          <div className="signin-art" aria-hidden="true">
            <div className="signin-halo" />
            <div className="signin-orbit signin-orbit-one">
              <i />
            </div>
            <div className="signin-orbit signin-orbit-two">
              <i />
            </div>
            <div className="signin-orbit signin-orbit-three" />
            <div className="signin-sphere">
              <span>✦</span>
            </div>
            <div className="signin-floating-mark signin-mark-one">
              <CalendarDays size={17} />
            </div>
            <div className="signin-floating-mark signin-mark-two">
              <Check size={17} />
            </div>
          </div>
          <div className="signin-focus-card" aria-hidden="true">
            <div className="signin-focus-label">
              <Sparkles size={13} />
              <span>{t('ТВОЙ СЛЕДУЮЩИЙ ШАГ')}</span>
              <span className="signin-focus-dot" />
            </div>
            <div className="signin-focus-body">
              <span className="signin-time">11:00</span>
              <div>
                <strong>{t('Подготовить презентацию')}</strong>
                <small>{t('Работа · 1 час')}</small>
              </div>
              <ArrowRight size={17} />
            </div>
            <div className="signin-focus-track">
              <i />
              <i />
              <i />
              <i />
            </div>
          </div>
          <div className="signin-visual-footer">
            <span>{t('Меньше шума. Больше ясности.')}</span>
            <span className="signin-footer-star">✦</span>
          </div>
        </section>
        <section className="signin-form-side" aria-labelledby="signin-title">
          <div className="signin-form-wrap">
            <div className="signin-welcome-icon">
              <LockKeyhole size={22} />
            </div>
            <span className="signin-form-eyebrow">{t('ТВОЙ ДЕНЬ НАЧИНАЕТСЯ ЗДЕСЬ')}</span>
            <h2 id="signin-title">{t('С возвращением')}</h2>
            <p className="signin-subtitle">{t('Войди, чтобы продолжить в своём темпе.')}</p>
            <form className="signin-form" onSubmit={submit} aria-busy={busy}>
              <fieldset disabled={busy}>
                <label className="signin-field" htmlFor="ritm-login">
                  {t('Логин')}
                </label>
                <div className="signin-input-wrap">
                  <UserRound size={18} aria-hidden="true" />
                  <input
                    id="ritm-login"
                    name="username"
                    autoComplete="username"
                    autoCapitalize="none"
                    spellCheck={false}
                    value={login}
                    onChange={(e) => {
                      setLogin(e.target.value);
                      setError('');
                    }}
                    required
                    maxLength={100}
                    placeholder={t('Твой логин')}
                    aria-invalid={Boolean(error)}
                    aria-describedby={error ? 'signin-error' : undefined}
                  />
                </div>
                <label className="signin-field" htmlFor="ritm-password">
                  {t('Пароль')}
                </label>
                <div className="signin-input-wrap">
                  <LockKeyhole size={18} aria-hidden="true" />
                  <input
                    id="ritm-password"
                    name="password"
                    type={visible ? 'text' : 'password'}
                    autoComplete="current-password"
                    value={password}
                    onChange={(e) => {
                      setPassword(e.target.value);
                      setError('');
                    }}
                    onKeyUp={(e) => setCapsLock(e.getModifierState('CapsLock'))}
                    onKeyDown={(e) => setCapsLock(e.getModifierState('CapsLock'))}
                    onBlur={() => setCapsLock(false)}
                    required
                    maxLength={512}
                    placeholder={t('Введи пароль')}
                    aria-invalid={Boolean(error)}
                    aria-describedby={error ? 'signin-error' : capsLock ? 'signin-caps' : undefined}
                  />
                  <button
                    className="signin-password-toggle"
                    type="button"
                    aria-label={visible ? t('Скрыть пароль') : t('Показать пароль')}
                    aria-pressed={visible}
                    onClick={() => setVisible(!visible)}
                  >
                    {visible ? <EyeOff size={18} /> : <Eye size={18} />}
                  </button>
                </div>
                {capsLock ? (
                  <p className="signin-caps" id="signin-caps" role="status">
                    {t('Включён Caps Lock')}
                  </p>
                ) : null}
                {error ? (
                  <p id="signin-error" className="signin-error" role="alert">
                    {t(error)}
                  </p>
                ) : null}
                <button
                  className="signin-submit"
                  type="submit"
                  disabled={!login.trim() || !password || busy}
                >
                  {busy ? (
                    <>
                      <LoaderCircle size={18} className="spinning" />
                      {t('Входим…')}
                    </>
                  ) : (
                    <>
                      {t('Войти в Ritm')}
                      <ArrowRight size={18} />
                    </>
                  )}
                </button>
              </fieldset>
            </form>
            <div className="signin-account-note">
              <span className="signin-note-line" />
              <span>
                <LockKeyhole size={12} />
                {t('Личный аккаунт')}
              </span>
              <span className="signin-note-line" />
            </div>
            <p className="signin-form-bottom">{t('Твои планы уже ждут тебя.')}</p>
            {preview && onBack ? (
              <button className="signin-back" type="button" onClick={onBack}>
                <ArrowLeft size={15} />
                {t('Вернуться в приложение')}
              </button>
            ) : null}
          </div>
        </section>
      </main>
      <footer className="signin-page-footer">
        <span>{t('Ritm · В своём ритме')}</span>
        <span>{t('Твоё время для важного')}</span>
      </footer>
    </div>
  );
}
