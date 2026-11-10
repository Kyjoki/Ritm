import { useCallback, useEffect, useState } from 'react';
import type { GoogleCalendarStatus, GoogleOAuthSetup } from '../../../shared/types';
import { useI18n } from '../../lib/i18n';
import type { SaveFeedback } from './useSaveFeedback';

export interface GoogleHandlers {
  onConnect: (extendedColors?: boolean) => Promise<void>;
  onConnectTasks?: () => Promise<void>;
  onDisconnect: () => Promise<void>;
  onConfigured?: () => Promise<void>;
}

export interface GoogleConnection {
  /** OAuth client is configured, counting a change made in the setup dialog before the refresh. */
  configured: boolean;
  statusUnknown: boolean;
  busy: boolean;
  error: string;
  /** Resolves with the error text (Russian source) when the action failed, otherwise null. */
  connect: (extendedColors?: boolean) => Promise<string | null>;
  connectTasks: () => Promise<string | null>;
  disconnect: () => Promise<boolean>;
  handleConfigured: (configuration: GoogleOAuthSetup, message: string) => Promise<void>;
  clearMessages: () => void;
}

export function useGoogleConnection(
  status: GoogleCalendarStatus,
  handlers: GoogleHandlers,
  feedback: SaveFeedback,
): GoogleConnection {
  const { t } = useI18n();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [setup, setSetup] = useState<GoogleOAuthSetup | null>(null);
  const [statusUnknown, setStatusUnknown] = useState(false);
  const { onConnect, onConnectTasks, onDisconnect, onConfigured } = handlers;

  useEffect(() => {
    setSetup(null);
    setStatusUnknown(false);
  }, [status]);

  const attempt = useCallback(async (operation: () => Promise<void>): Promise<string | null> => {
    setBusy(true);
    setError('');
    try {
      await operation();
      return null;
    } catch (failure) {
      const text =
        failure instanceof Error
          ? failure.message
          : 'Не удалось сохранить изменения. Попробуй ещё раз.';
      setError(text);
      return text;
    } finally {
      setBusy(false);
    }
  }, []);

  const connect = useCallback(
    (extendedColors?: boolean) => attempt(() => onConnect(extendedColors)),
    [attempt, onConnect],
  );

  const connectTasks = useCallback(
    async () => (onConnectTasks ? attempt(onConnectTasks) : null),
    [attempt, onConnectTasks],
  );

  const disconnect = useCallback(async () => {
    const done = (await attempt(onDisconnect)) === null;
    if (done) {
      setStatusUnknown(false);
      feedback.showSaved(t('Google Calendar отключён от Ritm.'));
    }
    return done;
  }, [attempt, onDisconnect, feedback, t]);

  const handleConfigured = useCallback(
    async (configuration: GoogleOAuthSetup, message: string) => {
      setSetup(configuration);
      setError('');
      try {
        await onConfigured?.();
        setStatusUnknown(false);
        feedback.showSaved(t(message));
      } catch (failure) {
        setStatusUnknown(true);
        feedback.showError(
          t('{message} Статус подключения не обновился. Обновите страницу.', {
            message: t(message),
          }),
        );
        throw failure;
      }
    },
    [onConfigured, feedback, t],
  );

  const clearMessages = useCallback(() => setError(''), []);

  return {
    configured: setup?.configured ?? status.configured,
    statusUnknown,
    busy,
    error,
    connect,
    connectTasks,
    disconnect,
    handleConfigured,
    clearMessages,
  };
}
