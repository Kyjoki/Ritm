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
import App from './App';

class ErrorBoundary extends Component<{ children: ReactNode }, { failed: boolean }> {
  state = { failed: false };
  static getDerivedStateFromError() {
    return { failed: true };
  }
  render() {
    return this.state.failed ? (
      <div className="startup">
        <div className="startup-card">
          <h1>Не удалось открыть экран</h1>
          <p>Ваши данные сохранены на сервере. Обновите страницу, чтобы продолжить.</p>
          <button className="button button-primary" onClick={() => window.location.reload()}>
            Обновить страницу
          </button>
        </div>
      </div>
    ) : (
      this.props.children
    );
  }
}
createRoot(document.getElementById('root')!).render(
  <ErrorBoundary>
    <App />
  </ErrorBoundary>,
);
