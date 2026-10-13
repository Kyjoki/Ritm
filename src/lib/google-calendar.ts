import { useCallback, useEffect, useRef, useState } from 'react';
import type { GoogleCalendarStatus, GoogleCalendarResult } from '../../shared/types';
import { api } from './api';
import { addDays } from '../features/calendar-utils';
import { googleAuthorizationUrl } from './navigation';

export const unconfiguredGoogle: GoogleCalendarStatus = {
  configured: false,
  status: 'unconfigured',
  mode: 'readwrite',
  calendarId: 'primary',
  lastFetchedAt: null,
};
export function useGoogleCalendar(enabled: boolean, timeZone: string, today: string) {
  const [status, setStatus] = useState<GoogleCalendarStatus>(unconfiguredGoogle);
  const [result, setResult] = useState<GoogleCalendarResult | null>(null),
    [loading, setLoading] = useState(false),
    [error, setError] = useState('');
  const [range, setRangeState] = useState({ from: today, to: addDays(today, 1) });
  const [revision, setRevision] = useState(0);
  const requestVersion = useRef(0);
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
            failure instanceof Error ? failure.message : 'Не удалось проверить подключение Google.',
          );
      });
    return () => {
      active = false;
    };
  }, [enabled]);
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
    setError('');
    api
      .googleEvents(range.from, range.to, timeZone)
      .then((next) => {
        if (version === requestVersion.current) {
          setResult(next);
          setStatus((old) => ({ ...old, lastFetchedAt: next.fetchedAt }));
        }
      })
      .catch((failure) => {
        if (version === requestVersion.current) {
          setError(
            failure instanceof Error ? failure.message : 'Не удалось загрузить календарь Google.',
          );
          void refreshStatus().catch(() => {});
        }
      })
      .finally(() => {
        if (version === requestVersion.current) setLoading(false);
      });
    return () => {
      requestVersion.current++;
    };
  }, [enabled, status.status, range.from, range.to, timeZone, revision, refreshStatus]);
  const refresh = useCallback(() => {
    if (!enabledRef.current) return;
    setLoading(true);
    void refreshStatus()
      .then(() => {
        if (enabledRef.current) setRevision((old) => old + 1);
      })
      .catch((failure) => {
        if (enabledRef.current) {
          setError(
            failure instanceof Error ? failure.message : 'Не удалось проверить Google Calendar.',
          );
          setLoading(false);
        }
      });
  }, [refreshStatus]);
  const connect = useCallback(async () => {
    const { authorizationUrl } = await api.connectGoogle();
    const url = googleAuthorizationUrl(authorizationUrl);
    window.location.assign(url.href);
  }, []);
  const disconnect = useCallback(async () => {
    setStatus(await api.disconnectGoogle());
    setResult(null);
    setError('');
  }, []);
  return { status, result, loading, error, setRange, refresh, connect, disconnect, refreshStatus };
}
