/** Preserve pg 8's certificate AND hostname verification across future driver upgrades. */
export function postgresConnectionString(connection: string): string {
  // Keep pg's local Unix socket syntax; it does not negotiate TLS.
  if (connection.startsWith('/')) return connection;
  let url: URL;
  try {
    url = new URL(connection);
    if (!['postgres:', 'postgresql:'].includes(url.protocol)) throw new Error();
  } catch {
    // URL errors can contain the password-bearing input. Never propagate those.
    throw new Error('Invalid PostgreSQL connection URL.');
  }
  // pg resolves duplicate query parameters to their last value.
  const mode = url.searchParams.getAll('sslmode').at(-1);
  if (
    url.searchParams.getAll('uselibpqcompat').at(-1) !== 'true' &&
    mode &&
    ['prefer', 'require', 'verify-ca'].includes(mode)
  ) {
    url.searchParams.set('sslmode', 'verify-full');
    return url.href;
  }
  return connection;
}
