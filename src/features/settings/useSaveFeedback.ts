import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

export const SAVED_VISIBLE_MS = 1800;
export const ERROR_VISIBLE_MS = 8000;

export interface SaveMessage {
  id: number;
  kind: 'saved' | 'error';
  /** Already translated text; empty for the default "Сохранено". */
  message: string;
}

export interface SaveFeedback {
  message: SaveMessage | null;
  showSaved: (message?: string) => void;
  showError: (message: string) => void;
  dismiss: () => void;
}

/** One slot for the "Сохранено" / error toast; a newer message replaces the older one. */
export function useSaveFeedback(): SaveFeedback {
  const [message, setMessage] = useState<SaveMessage | null>(null);
  const counter = useRef(0);
  const show = useCallback((kind: SaveMessage['kind'], text: string) => {
    counter.current += 1;
    setMessage({ id: counter.current, kind, message: text });
  }, []);
  const showSaved = useCallback((text = '') => show('saved', text), [show]);
  const showError = useCallback((text: string) => show('error', text), [show]);
  const dismiss = useCallback(() => setMessage(null), []);
  useEffect(() => {
    if (!message) return;
    const timer = window.setTimeout(
      dismiss,
      message.kind === 'error' ? ERROR_VISIBLE_MS : SAVED_VISIBLE_MS,
    );
    return () => window.clearTimeout(timer);
  }, [message, dismiss]);
  return useMemo(
    () => ({ message, showSaved, showError, dismiss }),
    [message, showSaved, showError, dismiss],
  );
}
