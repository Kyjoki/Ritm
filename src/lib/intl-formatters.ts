const dateFormats = new Map<string, Intl.DateTimeFormat>();
const numberFormats = new Map<string, Intl.NumberFormat>();
const capacity = 48;
function cached<T>(cache: Map<string, T>, locale: string, options: object, create: () => T): T {
  const key = JSON.stringify([
    locale,
    Object.entries(options).sort(([a], [b]) => a.localeCompare(b)),
  ]);
  const found = cache.get(key);
  if (found) return found;
  const formatter = create();
  if (cache.size >= capacity) cache.delete(cache.keys().next().value!);
  cache.set(key, formatter);
  return formatter;
}
export function dateTimeFormatter(
  locale: string,
  options: Intl.DateTimeFormatOptions,
): Intl.DateTimeFormat {
  return cached(dateFormats, locale, options, () => new Intl.DateTimeFormat(locale, options));
}
export function numberFormatter(
  locale: string,
  options: Intl.NumberFormatOptions,
): Intl.NumberFormat {
  return cached(numberFormats, locale, options, () => new Intl.NumberFormat(locale, options));
}
