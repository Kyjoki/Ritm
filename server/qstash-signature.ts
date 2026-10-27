import { createHash, timingSafeEqual } from 'node:crypto';
import { jwtVerify } from 'jose';

export async function verifyQstashSignature(input: {
  signature: string;
  body: Buffer;
  url: string;
  currentKey?: string;
  nextKey?: string;
}) {
  if (!input.signature || !input.currentKey || !input.nextKey) return false;
  const bodyHash = createHash('sha256').update(input.body).digest('base64url');
  for (const key of [input.currentKey, input.nextKey]) {
    try {
      const { payload } = await jwtVerify(input.signature, new TextEncoder().encode(key), {
        issuer: 'Upstash',
        subject: input.url,
        algorithms: ['HS256'],
      });
      const supplied = typeof payload.body === 'string' ? payload.body.replace(/=+$/, '') : '';
      const actual = Buffer.from(supplied);
      const expected = Buffer.from(bodyHash);
      if (actual.length === expected.length && timingSafeEqual(actual, expected)) return true;
    } catch {
      // QStash rotates signing keys; try the next key without exposing JWT details.
    }
  }
  return false;
}
