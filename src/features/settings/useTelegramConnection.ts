import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { TelegramStatus } from '../../../shared/types';
import { api } from '../../lib/api';
import { useI18n } from '../../lib/i18n';
import { createSerialQueue, type TelegramLead } from './settings-logic';
import type { SaveFeedback } from './useSaveFeedback';

const PAIRING_POLL_MS = 4_000;
const REMINDERS_POLL_MS = 30_000;

/** Server messages are already Russian source text; callers translate them with t(). */
function message(failure: unknown, fallback: string): string {
  return failure instanceof Error ? failure.message : fallback;
}

export interface TelegramConnection {
  status: TelegramStatus | null;
  loadFailed: boolean;
  busy: boolean;
  error: string;
  testSent: boolean;
  configure: (token: string) => Promise<boolean>;
  pair: () => Promise<void>;
  refresh: () => Promise<void>;
  disconnect: () => Promise<void>;
  setReminders: (enabled: boolean, lead: TelegramLead) => Promise<void>;
  sendTest: () => Promise<void>;
}

/** Telegram state shared by the notification row, the connection row and the dialog. */
export function useTelegramConnection(feedback: SaveFeedback): TelegramConnection {
  const { t } = useI18n();
  const [status, setStatus] = useState<TelegramStatus | null>(null);
  const [loadFailed, setLoadFailed] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [testSent, setTestSent] = useState(false);
  const statusRef = useRef(status);
  statusRef.current = status;
  const queue = useMemo(() => createSerialQueue(), []);
  const { showSaved, showError } = feedback;

  useEffect(() => {
    let active = true;
    api
      .telegramStatus()
      .then((value) => active && setStatus(value))
      .catch(() => active && setLoadFailed(true));
    return () => {
      active = false;
    };
  }, []);

  const poll =
    status?.pairingUrl && !status.linked
      ? PAIRING_POLL_MS
      : status?.reminders?.enabled
        ? REMINDERS_POLL_MS
        : 0;
  useEffect(() => {
    if (!poll) return;
    const timer = window.setInterval(() => {
      api
        .telegramStatus()
        .then(setStatus)
        .catch(() => undefined);
    }, poll);
    return () => window.clearInterval(timer);
  }, [poll]);

  const run = useCallback(
    async (operation: () => Promise<TelegramStatus>, fallback: string): Promise<boolean> => {
      setBusy(true);
      setError('');
      try {
        setStatus(await operation());
        return true;
      } catch (failure) {
        setError(message(failure, fallback));
        return false;
      } finally {
        setBusy(false);
      }
    },
    [],
  );

  const configure = useCallback(
    (token: string) => run(() => api.configureTelegram(token), 'Не удалось подключить Telegram.'),
    [run],
  );
  const pair = useCallback(async () => {
    await run(() => api.pairTelegram(), 'Не удалось подключить Telegram.');
  }, [run]);
  const refresh = useCallback(async () => {
    await run(() => api.telegramStatus(), 'Не удалось проверить Telegram.');
  }, [run]);
  const disconnect = useCallback(async () => {
    await run(() => api.disconnectTelegram(), 'Не удалось подключить Telegram.');
  }, [run]);

  const setReminders = useCallback(
    (enabled: boolean, lead: TelegramLead) =>
      queue(async () => {
        const before = statusRef.current;
        if (before?.reminders)
          setStatus({ ...before, reminders: { ...before.reminders, enabled, leadMinutes: lead } });
        try {
          setStatus(await api.saveTelegramReminders(enabled, lead));
          showSaved();
        } catch (failure) {
          setStatus(before);
          showError(t(message(failure, 'Не удалось сохранить изменения. Попробуй ещё раз.')));
        }
      }),
    [queue, showSaved, showError, t],
  );

  const sendTest = useCallback(async () => {
    setBusy(true);
    setError('');
    setTestSent(false);
    try {
      await api.testTelegramReminder();
      setTestSent(true);
    } catch (failure) {
      setError(message(failure, 'Не удалось отправить тестовое уведомление.'));
    } finally {
      setBusy(false);
    }
  }, []);

  return {
    status,
    loadFailed,
    busy,
    error,
    testSent,
    configure,
    pair,
    refresh,
    disconnect,
    setReminders,
    sendTest,
  };
}
