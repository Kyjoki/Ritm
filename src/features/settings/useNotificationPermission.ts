import { useCallback, useEffect, useState } from 'react';

export type BrowserPermission = 'granted' | 'denied' | 'default' | 'unsupported';

export function readBrowserPermission(): BrowserPermission {
  return typeof Notification === 'undefined' ? 'unsupported' : Notification.permission;
}

export interface NotificationPermission {
  permission: BrowserPermission;
  busy: boolean;
  /** Asks the browser when it has not been asked yet; resolves with the resulting state. */
  ensure: () => Promise<BrowserPermission>;
}

export function useNotificationPermission(): NotificationPermission {
  const [permission, setPermission] = useState(readBrowserPermission);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    const refresh = () => setPermission(readBrowserPermission());
    window.addEventListener('focus', refresh);
    return () => window.removeEventListener('focus', refresh);
  }, []);

  const ensure = useCallback(async () => {
    const current = readBrowserPermission();
    if (current !== 'default') {
      setPermission(current);
      return current;
    }
    setBusy(true);
    try {
      const result = await Notification.requestPermission();
      setPermission(result);
      return result;
    } finally {
      setBusy(false);
    }
  }, []);

  return { permission, busy, ensure };
}
