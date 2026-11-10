import { useCallback, useEffect, useRef, useState } from 'react';
import type { FinanceEntry, FinanceEntryInput } from '../../../shared/types';
import { ApiError, api } from '../../lib/api';
import { LatestRead, RefreshGate } from '../../lib/latest-read';
import type { Translate } from './finance-form';

export type WriteOutcome<T> = { ok: true; result: T } | { ok: false; message: string };

/** How long a load or delete error stays on screen before it dismisses itself. */
export const ERROR_DISMISS_MS = 7000;

/** Loads the ledger while the page is visible and serialises writes (409 triggers a fresh read). */
export function useFinanceData(active: boolean, t: Translate) {
  const [entries, setEntries] = useState<FinanceEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState('');
  const [retryable, setRetryable] = useState(false);
  const [saving, setSaving] = useState(false);
  const [deleting, setDeleting] = useState<string | null>(null);
  const hasLoaded = useRef(false);
  const read = useRef(new LatestRead());
  const gate = useRef(new RefreshGate());

  const reload = useCallback(
    async (initial = false) => {
      if (!gate.current.request()) return;
      const signal = read.current.start();
      if (initial) setLoading(true);
      else setRefreshing(true);
      setError('');
      setRetryable(false);
      try {
        const result = await api.finance(signal);
        if (!read.current.isCurrent(signal)) return;
        setEntries(result.entries);
        hasLoaded.current = true;
      } catch (failure) {
        if (read.current.isCurrent(signal)) {
          setRetryable(true);
          setError(
            failure instanceof Error
              ? failure.message
              : t('Не удалось загрузить финансовые данные.'),
          );
        }
      } finally {
        if (read.current.isCurrent(signal)) {
          setLoading(false);
          setRefreshing(false);
        }
      }
    },
    [t],
  );

  useEffect(() => {
    if (!active) return;
    gate.current.activate();
    void reload(!hasLoaded.current);
    return () => {
      gate.current.deactivate();
      read.current.cancel();
    };
  }, [active, reload]);

  useEffect(() => {
    if (!error) return;
    const timer = window.setTimeout(() => setError(''), ERROR_DISMISS_MS);
    return () => window.clearTimeout(timer);
  }, [error]);

  const write = useCallback(
    async <T>(
      run: () => Promise<T>,
      apply: (result: T) => void,
      busy: (on: boolean) => void,
      fallback: string,
    ): Promise<WriteOutcome<T>> => {
      if (gate.current.writing) return { ok: false, message: '' };
      read.current.cancel();
      gate.current.beginWrite(!hasLoaded.current);
      setLoading(false);
      setRefreshing(false);
      busy(true);
      let stale = false;
      try {
        const result = await run();
        apply(result);
        return { ok: true, result };
      } catch (failure) {
        stale = failure instanceof ApiError && failure.status === 409;
        return { ok: false, message: failure instanceof Error ? failure.message : fallback };
      } finally {
        if (gate.current.endWrite() || stale) {
          gate.current.request();
          void reload();
        }
        busy(false);
      }
    },
    [reload],
  );

  const saveEntry = useCallback(
    (input: FinanceEntryInput, editing: FinanceEntry | null) =>
      write(
        () =>
          editing
            ? api.updateFinanceEntry(editing.id, input, editing.updatedAt)
            : api.createFinanceEntry(input),
        (result) =>
          setEntries((current) =>
            editing
              ? current.map((entry) => (entry.id === editing.id ? result.entry : entry))
              : [result.entry, ...current],
          ),
        setSaving,
        t('Не удалось сохранить запись.'),
      ),
    [t, write],
  );

  const removeEntry = useCallback(
    async (entry: FinanceEntry) => {
      const outcome = await write(
        () => api.deleteFinanceEntry(entry.id, entry.updatedAt),
        () => setEntries((current) => current.filter((record) => record.id !== entry.id)),
        (on) => setDeleting(on ? entry.id : null),
        t('Не удалось удалить запись.'),
      );
      if (!outcome.ok && outcome.message) {
        setRetryable(false);
        setError(outcome.message);
      }
      return outcome.ok;
    },
    [t, write],
  );

  return {
    entries,
    loading,
    refreshing,
    error,
    retryable,
    saving,
    deleting,
    clearError: () => setError(''),
    reload: () => void reload(),
    saveEntry,
    removeEntry,
  };
}
