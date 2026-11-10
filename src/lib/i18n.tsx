import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react';
import type { Language } from '../../shared/types';
export type { Language } from '../../shared/types';
import { coreEnglish } from '../locales/core';
import { settingsAssistantEnglish } from '../locales/settings-assistant';
import { settingsPageEnglish } from '../locales/settings-page';
import { calendarEnglish } from '../locales/calendar';
import { financeEnglish } from '../locales/finance';
import { habitsEnglish } from '../locales/habits';
import { workoutsEnglish } from '../locales/workouts';

const LANGUAGE_KEY = 'ritm.language.v1';
export function normalizeLanguage(value: unknown): Language {
  return value === 'en' ? 'en' : 'ru';
}
function readLanguage(): Language {
  try {
    return typeof window === 'undefined'
      ? 'ru'
      : normalizeLanguage(window.localStorage.getItem(LANGUAGE_KEY));
  } catch {
    return 'ru';
  }
}
let activeLanguage: Language = readLanguage();
/** Request metadata for plain API helpers; UI uses the React context below. */
export function getLanguage(): Language {
  return activeLanguage;
}
const english: Record<string, string> = {
  ...coreEnglish,
  ...settingsAssistantEnglish,
  ...settingsPageEnglish,
  ...calendarEnglish,
  ...financeEnglish,
  ...habitsEnglish,
  ...workoutsEnglish,
};
export function translate(
  language: Language,
  source: string,
  values?: Record<string, string | number>,
): string {
  const value = language === 'en' ? (english[source] ?? source) : source;
  return values
    ? value.replace(/\{([a-zA-Z][a-zA-Z0-9_]*)\}/g, (match, key) =>
        Object.hasOwn(values, key) ? String(values[key]) : match,
      )
    : value;
}
export function localeFor(language: Language) {
  return language === 'en' ? 'en-US' : 'ru-RU';
}
type I18nValue = {
  language: Language;
  locale: string;
  t: (source: string, values?: Record<string, string | number>) => string;
  setLanguage: (language: Language) => void;
};
const I18nContext = createContext<I18nValue>({
  language: 'ru',
  locale: 'ru-RU',
  t: (source, values) => translate('ru', source, values),
  setLanguage: () => {},
});
export function I18nProvider({ children }: { children: ReactNode }) {
  const [language, setSelected] = useState<Language>(readLanguage);
  const setLanguage = useCallback((selected: Language) => {
    const next = normalizeLanguage(selected);
    activeLanguage = next;
    setSelected(next);
    try {
      window.localStorage.setItem(LANGUAGE_KEY, next);
    } catch {
      /* Preferences remain available in memory. */
    }
  }, []);
  useEffect(() => {
    document.documentElement.lang = language;
  }, [language]);
  const value = useMemo(
    () => ({
      language,
      locale: localeFor(language),
      t: (source: string, values?: Record<string, string | number>) =>
        translate(language, source, values),
      setLanguage,
    }),
    [language, setLanguage],
  );
  return <I18nContext.Provider value={value}>{children}</I18nContext.Provider>;
}
export function useI18n() {
  return useContext(I18nContext);
}
