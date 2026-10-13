import test from 'node:test';
import assert from 'node:assert/strict';
import { googleAuthorizationUrl } from '../src/lib/navigation.ts';

test('Google authorization navigation accepts only the fixed HTTPS OAuth endpoint', () => {
  const valid =
    'https://accounts.google.com/o/oauth2/v2/auth?client_id=example&redirect_uri=https%3A%2F%2Fritm.example%2Fapi%2Fintegrations%2Fgoogle%2Fcallback&response_type=code&state=one-time';
  assert.equal(googleAuthorizationUrl(valid).href, valid);
  for (const invalid of [
    'javascript:alert(1)',
    'http://accounts.google.com/o/oauth2/v2/auth',
    'https://accounts.google.com.attacker.example/o/oauth2/v2/auth',
    'https://accounts.google.com@attacker.example/o/oauth2/v2/auth',
    'https://attacker@accounts.google.com/o/oauth2/v2/auth',
    'https://accounts.google.com:8443/o/oauth2/v2/auth',
    'https://accounts.google.com/url?next=https://attacker.example',
    'https://accounts.google.com/o/oauth2/v2/auth#fragment',
    'https://accounts.google.com/o/oauth2/v2/auth?' + 'x'.repeat(8192),
    null,
    { href: valid },
  ])
    assert.throws(() => googleAuthorizationUrl(invalid), /неверный адрес/);
});
