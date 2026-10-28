import { createRoot } from 'react-dom/client';
import { Component, type ReactNode } from 'react';
import '@fontsource/inter/400.css';
import '@fontsource/inter/500.css';
import '@fontsource/inter/600.css';
import '@fontsource/inter/700.css';
import './styles/tokens.css';
import './styles/app.css';
import './styles/calendar-settings.css';
import './styles/assistant.css';
import './styles/finance.css';
import App from './App';
import './styles/dashboard-layout.css';
import { I18nProvider, getLanguage, translate } from './lib/i18n';

class ErrorBoundary extends Component<{ children: ReactNode }, { failed: boolean }> {
  state = { failed: false };
  static getDerivedStateFromError() {
    return { failed: true };
  }
  render() {
    return this.state.failed ? (
      <div className="startup">
        <div className="startup-card">
          <h1>{translate(getLanguage(), 'Не удалось открыть экран')}</h1>
          <p>
            {translate(
              getLanguage(),
              'Ваши данные сохранены на сервере. Обновите страницу, чтобы продолжить.',
            )}
          </p>
          <button className="button button-primary" onClick={() => window.location.reload()}>
            {translate(getLanguage(), 'Обновить страницу')}
          </button>
        </div>
      </div>
    ) : (
      this.props.children
    );
  }
}
// Keep the dev root across module invalidation (motion hooks also export shared helpers).
const root = import.meta.hot?.data.root ?? createRoot(document.getElementById('root')!);
if (import.meta.hot) import.meta.hot.data.root = root;
root.render(
  <ErrorBoundary>
    <I18nProvider>
      <App />
    </I18nProvider>
  </ErrorBoundary>,
);
