import { createHmac, randomBytes, timingSafeEqual } from 'node:crypto';

/** RFC 6238 TOTP (HMAC-SHA1, 6 digits, 30 s) built on RFC 4226 HOTP and RFC 4648 base32. */
export const TOTP_DIGITS = 6;
export const TOTP_PERIOD_SECONDS = 30;
export const TOTP_WINDOW_STEPS = 1;

const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

export function base32Encode(bytes: Uint8Array) {
  let bits = 0,
    value = 0,
    output = '';
  for (const byte of bytes) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      output += alphabet[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) output += alphabet[(value << (5 - bits)) & 31];
  return output;
}

export function base32Decode(text: string) {
  const clean = text.replace(/[\s=-]/g, '').toUpperCase();
  const bytes: number[] = [];
  let bits = 0,
    value = 0;
  for (const char of clean) {
    const index = alphabet.indexOf(char);
    if (index < 0) throw new Error('Invalid base32 character.');
    value = (value << 5) | index;
    bits += 5;
    if (bits >= 8) {
      bytes.push((value >>> (bits - 8)) & 255);
      bits -= 8;
    }
  }
  return Buffer.from(bytes);
}

export const generateTotpSecret = () => base32Encode(randomBytes(20));

export function hotp(secret: Buffer, counter: number, digits = TOTP_DIGITS) {
  const message = Buffer.alloc(8);
  message.writeBigUInt64BE(BigInt(counter));
  const hash = createHmac('sha1', secret).update(message).digest();
  const offset = hash[hash.length - 1] & 15;
  const binary = hash.readUInt32BE(offset) & 0x7fffffff;
  return String(binary % 10 ** digits).padStart(digits, '0');
}

export const totpStep = (timeMs: number) => Math.floor(timeMs / 1000 / TOTP_PERIOD_SECONDS);

export function totpCode(secretBase32: string, timeMs: number, digits = TOTP_DIGITS) {
  return hotp(base32Decode(secretBase32), totpStep(timeMs), digits);
}

const sameText = (a: string, b: string) =>
  a.length === b.length && timingSafeEqual(Buffer.from(a), Buffer.from(b));

/** Returns the matching time step (so the caller can refuse a replay) or null. */
export function verifyTotp(secretBase32: string, code: string, timeMs: number): number | null {
  if (!/^\d{6}$/.test(code)) return null;
  const secret = base32Decode(secretBase32),
    current = totpStep(timeMs);
  let match: number | null = null;
  // Check every step in constant shape so timing does not reveal which one matched.
  for (let offset = -TOTP_WINDOW_STEPS; offset <= TOTP_WINDOW_STEPS; offset++)
    if (sameText(hotp(secret, current + offset), code)) match = current + offset;
  return match;
}

export function otpauthUrl(secretBase32: string, account: string, issuer = 'Ritm') {
  const label = encodeURIComponent(issuer) + ':' + encodeURIComponent(account);
  const query = new URLSearchParams({
    secret: secretBase32,
    issuer,
    algorithm: 'SHA1',
    digits: String(TOTP_DIGITS),
    period: String(TOTP_PERIOD_SECONDS),
  });
  return `otpauth://totp/${label}?${query}`;
}
