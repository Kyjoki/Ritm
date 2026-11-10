import { useCallback, useEffect, useRef, useState } from 'react';
import type { Session } from './session';

/** The running workout and its rest timer stay in this browser only (the iPhone does the same). */
const STORAGE_KEY = 'ritm.workouts.active.v1';
export interface Rest {
  endsAt: number;
  length: number;
}
interface Stored {
  session: Session | null;
  rest: Rest | null;
}
const isSession = (value: unknown): value is Session => {
  const s = value as Session | null;
  return (
    !!s &&
    typeof s.id === 'string' &&
    typeof s.programID === 'string' &&
    typeof s.startedAt === 'string' &&
    Array.isArray(s.items) &&
    s.items.length > 0 &&
    s.items.every(
      (item) =>
        typeof item?.id === 'string' &&
        typeof item.exerciseID === 'string' &&
        Array.isArray(item.sets) &&
        item.sets.every((set) => typeof set?.id === 'string' && typeof set.done === 'boolean'),
    )
  );
};
export function readStored(raw: string | null): Stored {
  try {
    const parsed = raw ? (JSON.parse(raw) as Partial<Stored>) : null;
    const rest = parsed?.rest;
    return {
      session: isSession(parsed?.session) ? parsed.session : null,
      rest:
        rest && Number.isFinite(rest.endsAt) && Number.isFinite(rest.length) && rest.length > 0
          ? { endsAt: rest.endsAt, length: rest.length }
          : null,
    };
  } catch {
    return { session: null, rest: null };
  }
}
function load(): Stored {
  try {
    return readStored(window.localStorage.getItem(STORAGE_KEY));
  } catch {
    return { session: null, rest: null };
  }
}

export function useActiveWorkout(active: boolean) {
  const [stored, setStored] = useState<Stored>(load);
  const [now, setNow] = useState(() => Date.now());
  const latest = useRef(stored);
  latest.current = stored;
  const { session } = stored;

  useEffect(() => {
    try {
      if (stored.session) window.localStorage.setItem(STORAGE_KEY, JSON.stringify(stored));
      else window.localStorage.removeItem(STORAGE_KEY);
    } catch {
      /* The workout stays in memory when storage is unavailable. */
    }
  }, [stored]);
  useEffect(() => {
    if (!active || !session) return;
    setNow(Date.now());
    const timer = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(timer);
  }, [active, session]);

  const update = useCallback((change: (current: Session) => Session) => {
    setStored((old) => (old.session ? { ...old, session: change(old.session) } : old));
  }, []);
  const begin = useCallback((next: Session) => setStored({ session: next, rest: null }), []);
  const end = useCallback(() => setStored({ session: null, rest: null }), []);
  const startRest = useCallback((seconds: number) => {
    setStored((old) => ({
      ...old,
      rest: { endsAt: Date.now() + seconds * 1000, length: seconds },
    }));
  }, []);
  const extendRest = useCallback((seconds: number) => {
    setStored((old) =>
      old.rest
        ? {
            ...old,
            rest: { endsAt: old.rest.endsAt + seconds * 1000, length: old.rest.length + seconds },
          }
        : old,
    );
  }, []);
  const stopRest = useCallback(() => setStored((old) => ({ ...old, rest: null })), []);
  const rest = stored.rest;
  const restLeft = rest ? Math.max(0, Math.ceil((rest.endsAt - now) / 1000)) : 0;
  const restRunning = rest !== null && restLeft > 0;
  /** The current stored workout, for async handlers that must not read a stale closure. */
  const current = useCallback(() => latest.current.session, []);
  return {
    session,
    now,
    rest,
    restLeft,
    restRunning,
    update,
    begin,
    end,
    startRest,
    extendRest,
    stopRest,
    current,
  };
}
