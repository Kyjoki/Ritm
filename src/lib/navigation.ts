/** The only external navigation the app initiates is Google's OAuth endpoint. */
import { getLanguage, translate } from './i18n';
const tr = (source: string) => translate(getLanguage(), source);
export function googleAuthorizationUrl(value: unknown): URL {
  let url: URL;
  try {
    if (typeof value !== 'string' || value.length > 8192) throw new Error();
    url = new URL(value);
  } catch {
    throw new Error(tr('Сервер вернул неверный адрес подключения Google.'));
  }
  if (
    url.protocol !== 'https:' ||
    url.hostname !== 'accounts.google.com' ||
    url.port ||
    url.username ||
    url.password ||
    url.hash ||
    url.pathname !== '/o/oauth2/v2/auth'
  )
    throw new Error(tr('Сервер вернул неверный адрес подключения Google.'));
  return url;
}
