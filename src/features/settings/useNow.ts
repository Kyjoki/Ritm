import { useEffect, useState } from 'react';

const MINUTE_MS = 60_000;

/** The current time, refreshed every minute so zone clocks stay right. */
export function useNow(): Date {
  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    const timer = window.setInterval(() => setNow(new Date()), MINUTE_MS);
    return () => window.clearInterval(timer);
  }, []);
  return now;
}
