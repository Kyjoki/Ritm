import type {
  AiStatus,
  GoogleCalendarStatus,
  Settings,
  TelegramStatus,
} from '../../../shared/types';

/** Colour family of a status dot; maps to CSS tokens. */
export type Tone = 'ok' | 'warn' | 'idle' | 'accent';

export interface ConnectionSummary {
  tone: Tone;
  /** Russian source string for the status text. */
  label: string;
  /** Russian source string for the quick action button shown in the row, if any. */
  cta: string | null;
}

export const THEME_LABELS: Record<Settings['theme'], string> = {
  light: 'Светлая',
  dark: 'Тёмная',
  system: 'Системная',
};

export const SIDEBAR_LABELS: Record<Settings['sidebar'], string> = {
  dark: 'Графитовая',
  light: 'Светлая',
};

export const LANGUAGE_LABELS: Record<Settings['language'], string> = {
  ru: 'Русский',
  en: 'English',
};

export function workDaySummary(settings: Pick<Settings, 'workDayStart' | 'workDayEnd'>): string {
  return `${settings.workDayStart} – ${settings.workDayEnd}`;
}

/** Source string plus interpolation values for a Telegram lead time. */
export function leadLabel(minutes: number): { source: string; values?: { minutes: number } } {
  return minutes === 0
    ? { source: 'В момент начала' }
    : { source: 'за {minutes} мин', values: { minutes } };
}

export function openAiSummary(status: AiStatus): ConnectionSummary {
  if (status.source === 'environment')
    return { tone: 'accent', label: 'Задан сервером', cta: null };
  if (status.configured) return { tone: 'ok', label: 'Ключ задан', cta: null };
  return { tone: 'idle', label: 'Не настроен', cta: 'Добавить ключ' };
}

export type GoogleQuickAction = 'setup' | 'connect' | null;

export interface GoogleSummary extends ConnectionSummary {
  action: GoogleQuickAction;
}

export function googleSummary(
  status: GoogleCalendarStatus,
  configured: boolean,
  statusUnknown: boolean,
): GoogleSummary {
  if (statusUnknown) return { tone: 'warn', label: 'Статус не обновился', cta: null, action: null };
  if (!configured)
    return { tone: 'warn', label: 'Нужна настройка OAuth', cta: 'Указать клиент', action: 'setup' };
  if (status.status === 'connected')
    return { tone: 'ok', label: 'Подключён', cta: null, action: null };
  if (status.status === 'reauth_required')
    return {
      tone: 'warn',
      label: 'Нужно подключить заново',
      cta: 'Переподключить',
      action: 'connect',
    };
  return { tone: 'idle', label: 'Не подключён', cta: 'Подключить', action: 'connect' };
}

export function telegramSummary(
  status: TelegramStatus | null,
  loadFailed: boolean,
): ConnectionSummary {
  if (!status)
    return loadFailed
      ? { tone: 'warn', label: 'Не удалось проверить', cta: null }
      : { tone: 'idle', label: 'Проверяем…', cta: null };
  if (status.linked) return { tone: 'ok', label: 'Чат привязан', cta: null };
  if (status.configured) return { tone: 'warn', label: 'Чат не привязан', cta: 'Привязать чат' };
  return { tone: 'idle', label: 'Не настроен', cta: 'Добавить бота' };
}
