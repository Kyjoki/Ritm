/** The only external navigation the app initiates is Google's OAuth endpoint. */
export function googleAuthorizationUrl(value: unknown): URL {
  let url: URL;
  try {
    if (typeof value !== 'string' || value.length > 8192) throw new Error();
    url = new URL(value);
  } catch {
    throw new Error('Сервер вернул неверный адрес подключения Google.');
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
    throw new Error('Сервер вернул неверный адрес подключения Google.');
  return url;
}
