import { useCallback, useEffect, useRef, useState } from 'react';
import type {
  GoogleCalendarStatus,
  GoogleCalendarResult,
  GoogleCalendarEvent,
} from '../../shared/types';
import { api } from './api';
import { addDays } from '../features/calendar-utils';
import { googleAuthorizationUrl } from './navigation';
import { useI18n } from './i18n';

export const unconfiguredGoogle: GoogleCalendarStatus = {
  configured: false,
  status: 'unconfigured',
  mode: 'readwrite',
  calendarId: 'primary',
  lastFetchedAt: null,
};
export function useGoogleCalendar(enabled: boolean, timeZone: string, today: string) {
  const { t: tr } = useI18n();
  const [status, setStatus] = useState<GoogleCalendarStatus>(unconfiguredGoogle);
  const [statusChecked, setStatusChecked] = useState(false);
  const [result, setResult] = useState<GoogleCalendarResult | null>(null),
    [loading, setLoading] = useState(false),
    [error, setError] = useState('');
  const [range, setRangeState] = useState({ from: today, to: addDays(today, 1) });
  const [revision, setRevision] = useState(0);
  const requestVersion = useRef(0);
  const activeRead = useRef<AbortController | null>(null);
  const readBusy = useRef(false);
  const refreshBusy = useRef(false);
  const enabledRef = useRef(enabled);
  enabledRef.current = enabled;
  const refreshStatus = useCallback(async () => {
    const next = await api.googleStatus();
    if (enabledRef.current) {
      setStatus(next);
      if (next.status !== 'connected') setResult(null);
    }
    return next;
  }, []);
  useEffect(() => {
    if (!enabled) {
      setStatusChecked(false);
      setStatus(unconfiguredGoogle);
      setResult(null);
      setError('');
      return;
    }
    let active = true;
    api
      .googleStatus()
      .then((next) => {
        if (active) setStatus(next);
      })
      .catch((failure) => {
        if (active)
          setError(
            failure instanceof Error
              ? failure.message
              : tr('Не удалось проверить подключение Google.'),
          );
      })
      .finally(() => {
        if (active) setStatusChecked(true);
      });
    return () => {
      active = false;
    };
  }, [enabled, tr]);
  const setRange = useCallback(
    (from: string, to: string) =>
      setRangeState((old) => (old.from === from && old.to === to ? old : { from, to })),
    [],
  );
  useEffect(() => {
    const version = ++requestVersion.current;
    if (!enabled || status.status !== 'connected') {
      setResult(null);
      setLoading(false);
      return;
    }
    setResult((old) =>
      old?.from === range.from && old.to === range.to && old.timeZone === timeZone ? old : null,
    );
    setLoading(true);
    readBusy.current = true;
    const controller = new AbortController();
    activeRead.current = controller;
    setError('');
    api
      .googleEvents(range.from, range.to, timeZone, controller.signal)
      .then((next) => {
        if (version === requestVersion.current) {
          setResult(next);
          setStatus((old) => ({ ...old, lastFetchedAt: next.fetchedAt }));
        }
      })
      .catch((failure) => {
        if (version === requestVersion.current) {
          setError(
            failure instanceof Error
              ? failure.message
              : tr('Не удалось загрузить календарь Google.'),
          );
          void refreshStatus().catch(() => {});
        }
      })
      .finally(() => {
        if (version === requestVersion.current) {
          setLoading(false);
          readBusy.current = false;
          if (activeRead.current === controller) activeRead.current = null;
        }
      });
    return () => {
      requestVersion.current++;
      controller.abort();
      if (activeRead.current === controller) {
        activeRead.current = null;
        readBusy.current = false;
      }
    };
  }, [enabled, status.status, range.from, range.to, timeZone, revision, refreshStatus, tr]);
  const refresh = useCallback(() => {
    if (!enabledRef.current || refreshBusy.current || readBusy.current) return;
    refreshBusy.current = true;
    setLoading(true);
    void refreshStatus()
      .then(() => {
        if (enabledRef.current) setRevision((old) => old + 1);
      })
      .catch((failure) => {
        if (enabledRef.current) {
          setError(
            failure instanceof Error
              ? failure.message
              : tr('Не удалось проверить Google Calendar.'),
          );
          setLoading(false);
        }
      })
      .finally(() => {
        refreshBusy.current = false;
      });
  }, [refreshStatus, tr]);
  useEffect(() => {
    if (!enabled) return;
    const refreshVisible = () => {
      if (document.visibilityState === 'visible') refresh();
    };
    const interval = window.setInterval(refreshVisible, 30_000);
    window.addEventListener('focus', refreshVisible);
    document.addEventListener('visibilitychange', refreshVisible);
    return () => {
      window.clearInterval(interval);
      window.removeEventListener('focus', refreshVisible);
      document.removeEventListener('visibilitychange', refreshVisible);
    };
  }, [enabled, refresh]);
  const invalidateRead = useCallback(() => {
    requestVersion.current++;
    activeRead.current?.abort();
    activeRead.current = null;
    readBusy.current = false;
    setLoading(false);
  }, []);
  const upsertEvent = useCallback(
    (event: GoogleCalendarEvent) => {
      invalidateRead();
      setResult((old) =>
        old && (!(event.recurring && event.readOnly) || Boolean(event.googleTask))
          ? { ...old, events: [...old.events.filter((item) => item.id !== event.id), event] }
          : old,
      );
    },
    [invalidateRead],
  );
  const removeEvent = useCallback(
    (id: string) => {
      invalidateRead();
      setResult((old) =>
        old ? { ...old, events: old.events.filter((item) => item.id !== id) } : old,
      );
    },
    [invalidateRead],
  );
  const connect = useCallback(async (extendedColors?: boolean) => {
    const { authorizationUrl } = await api.connectGoogle(extendedColors);
    const url = googleAuthorizationUrl(authorizationUrl);
    window.location.assign(url.href);
  }, []);
  const disconnect = useCallback(async () => {
    setStatus(await api.disconnectGoogle());
    setResult(null);
    setError('');
  }, []);
  const connectTasks = useCallback(async () => {
    const { authorizationUrl } = await api.connectGoogle(undefined, true);
    window.location.assign(googleAuthorizationUrl(authorizationUrl).href);
  }, []);
  return {
    status,
    result,
    loading,
    checkingStatus: enabled && !statusChecked,
    error,
    setRange,
    refresh,
    connect,
    connectTasks,
    disconnect,
    refreshStatus,
    upsertEvent,
    removeEvent,
  };
}
