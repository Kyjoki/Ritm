import { useCallback, useEffect, useRef, useState } from 'react';

export const TEXT_AUTOSAVE_DELAY_MS = 700;

interface AutosaveTextOptions {
  /** The saved value; the field follows it whenever the user is not editing. */
  value: string;
  /** Returns an error message (already translated) when the text must not be saved. */
  validate: (text: string) => string | null;
  /** Persists the text; resolves false when saving failed. */
  commit: (text: string) => Promise<boolean>;
  delay?: number;
}

export interface AutosaveText {
  text: string;
  error: string;
  onChange: (next: string) => void;
  onBlur: () => void;
}

/**
 * A text input that saves itself: it waits for a pause in typing, never commits invalid text
 * and falls back to the saved value when it is left in an invalid state.
 */
export function useAutosaveText({
  value,
  validate,
  commit,
  delay = TEXT_AUTOSAVE_DELAY_MS,
}: AutosaveTextOptions): AutosaveText {
  const [text, setText] = useState(value);
  const [error, setError] = useState('');
  const editing = useRef(false);
  const timer = useRef<number | null>(null);
  const latest = useRef({ text, validate, commit });
  latest.current = { text, validate, commit };

  useEffect(() => {
    // Trimmed comparison keeps a trailing space the user has just typed.
    if (!editing.current && value !== latest.current.text.trim()) setText(value);
  }, [value]);

  const clearTimer = useCallback(() => {
    if (timer.current !== null) window.clearTimeout(timer.current);
    timer.current = null;
  }, []);

  const flush = useCallback(
    async (next: string) => {
      clearTimer();
      const problem = latest.current.validate(next);
      setError(problem ?? '');
      if (problem) return false;
      editing.current = false;
      return latest.current.commit(next);
    },
    [clearTimer],
  );

  const onChange = useCallback(
    (next: string) => {
      editing.current = true;
      setText(next);
      clearTimer();
      timer.current = window.setTimeout(() => void flush(next), delay);
    },
    [clearTimer, flush, delay],
  );

  const onBlur = useCallback(() => {
    if (!editing.current) return;
    void flush(latest.current.text).then((saved) => {
      if (saved) return;
      editing.current = false;
      setError('');
      setText(value);
    });
  }, [flush, value]);

  useEffect(
    () => () => {
      clearTimer();
      if (editing.current && !latest.current.validate(latest.current.text))
        void latest.current.commit(latest.current.text);
    },
    [clearTimer],
  );

  return { text, error, onChange, onBlur };
}
