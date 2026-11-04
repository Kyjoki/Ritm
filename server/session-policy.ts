import type { SessionClient } from './runtime-state.ts';

const HOUR = 60 * 60_000;
const DAY = 24 * HOUR;
export const TOUCH_INTERVAL_MS = 5 * 60_000;
export const MAX_DEVICE_NAME = 60;

export const sessionPolicy: Record<SessionClient, { slidingMs: number; absoluteMs: number }> = {
  web: { slidingMs: 12 * HOUR, absoluteMs: 7 * DAY },
  ios: { slidingMs: 30 * DAY, absoluteMs: 180 * DAY },
};

/** Sliding expiry never exceeds the absolute limit. */
export const slidingExpiry = (client: SessionClient, now: number, absoluteExpiresAt: number) =>
  Math.min(now + sessionPolicy[client].slidingMs, absoluteExpiresAt);

export function cleanDeviceName(value: string | undefined) {
  // eslint-disable-next-line no-control-regex
  return (value ?? '')
    .replace(/[\u0000-\u001f\u007f]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, MAX_DEVICE_NAME);
}

/** Coarse, human-readable label from a User-Agent; never stores the raw header. */
export function deviceNameFromUserAgent(userAgent: string | undefined) {
  const ua = userAgent ?? '';
  const system = /iPhone/.test(ua)
    ? 'iPhone'
    : /iPad/.test(ua)
      ? 'iPad'
      : /Android/.test(ua)
        ? 'Android'
        : /Windows/.test(ua)
          ? 'Windows'
          : /Mac OS X|Macintosh/.test(ua)
            ? 'Mac'
            : /Linux/.test(ua)
              ? 'Linux'
              : '';
  const browser = /Edg\//.test(ua)
    ? 'Edge'
    : /OPR\/|Opera/.test(ua)
      ? 'Opera'
      : /Firefox\//.test(ua)
        ? 'Firefox'
        : /Chrome\/|CriOS/.test(ua)
          ? 'Chrome'
          : /Safari\//.test(ua)
            ? 'Safari'
            : '';
  return (
    cleanDeviceName(
      [browser, system && (browser ? 'на ' + system : system)].filter(Boolean).join(' '),
    ) || 'Неизвестное устройство'
  );
}
