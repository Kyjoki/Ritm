import {
  createHash,
  createHmac,
  randomBytes,
  randomUUID,
  scrypt,
  scryptSync,
  timingSafeEqual,
} from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { isIP } from 'node:net';
import { SignJWT, jwtVerify } from 'jose';
import type { NextFunction, Request, Response } from 'express';
import { AppError, missing } from './errors.ts';
import type { RuntimeState, SessionClient } from './runtime-state.ts';
import { SecretStore } from './secrets.ts';
import { TwoFactor, type TwoFactorInput } from './two-factor.ts';
import { LoginThrottle } from './login-throttle.ts';
import {
  TOUCH_INTERVAL_MS,
  cleanDeviceName,
  deviceNameFromUserAgent,
  sessionPolicy,
  slidingExpiry,
} from './session-policy.ts';

const digest = (value: string) => createHash('sha256').update(value).digest('hex');
const loopback = (address: string | undefined) =>
  Boolean(
    address && ['127.0.0.1', '::1', '[::1]', '::ffff:127.0.0.1', 'localhost'].includes(address),
  );
const sessionId = /^[a-f0-9]{64}$/;
const isoSeconds = (ms: number) => new Date(ms).toISOString().replace(/\.\d{3}Z$/, 'Z');
export interface LoginInput {
  login: string;
  password: string;
  totp?: string;
  recoveryCode?: string;
  client?: SessionClient;
  deviceName?: string;
}
const maxPasswordChecks = 4;

export class Security {
  private passwordHash: Buffer | null;
  private salt = randomBytes(32);
  private origins: Set<string>;
  private publicOrigin: string | undefined;
  private deploymentHost: string | undefined;
  private secureCookie: boolean;
  private sessionKey: Buffer;
  private credentialVersion: string;
  private loginName: string;
  private cookieName: string;
  private passwordChecks = 0;
  readonly twoFactor: TwoFactor;
  private throttle: LoginThrottle;
  constructor(
    private env: NodeJS.ProcessEnv,
    private state: RuntimeState,
    dataDir: string,
    secrets?: SecretStore,
  ) {
    const password = env.APP_PASSWORD;
    const host = env.HOST || '127.0.0.1';
    const localHost = loopback(host),
      production = env.NODE_ENV === 'production' || env.VERCEL === '1';
    if ((!localHost || production) && !password)
      throw new Error('APP_PASSWORD is required for production or a non-loopback HOST.');
    if (password && (password.length < 12 || password.length > 512))
      throw new Error('APP_PASSWORD must contain 12–512 characters.');
    if (production && !env.APP_LOGIN?.trim())
      throw new Error('APP_LOGIN is required for production.');
    this.loginName = (env.APP_LOGIN?.trim() || 'maksim').toLocaleLowerCase('en-US');
    if (this.loginName.length > 100)
      throw new Error('APP_LOGIN must contain at most 100 characters.');
    if (env.APP_SESSION_SECRET) {
      this.sessionKey = Buffer.from(env.APP_SESSION_SECRET, 'utf8');
      if (this.sessionKey.length < 32)
        throw new Error('APP_SESSION_SECRET must contain at least 32 bytes.');
    } else {
      if (production || env.DATABASE_URL)
        throw new Error('APP_SESSION_SECRET is required for shared/production sessions.');
      mkdirSync(dataDir, { recursive: true, mode: 0o700 });
      const path = join(dataDir, '.session-key');
      if (!existsSync(path)) writeFileSync(path, randomBytes(32), { flag: 'wx', mode: 0o600 });
      this.sessionKey = readFileSync(path);
      if (this.sessionKey.length !== 32) throw new Error('Invalid local session key.');
    }
    this.credentialVersion = createHmac('sha256', this.sessionKey)
      .update(this.loginName + '\0' + (password ?? ''))
      .digest('hex');
    this.passwordHash = password ? scryptSync(password, this.salt, 32) : null;
    const port = env.PORT || '3001';
    this.origins = new Set(['http://127.0.0.1:' + port, 'http://localhost:' + port]);
    if (host === '::1') this.origins.add('http://[::1]:' + port);
    if (!production) {
      this.origins.add('http://127.0.0.1:5173');
      this.origins.add('http://localhost:5173');
    }
    if (env.APP_ORIGIN) {
      const url = new URL(env.APP_ORIGIN);
      if (
        !['http:', 'https:'].includes(url.protocol) ||
        url.username ||
        url.password ||
        url.pathname !== '/' ||
        url.search ||
        url.hash
      )
        throw new Error('APP_ORIGIN must be an http(s) origin without a path.');
      if (!loopback(url.hostname) && url.protocol !== 'https:')
        throw new Error('Public APP_ORIGIN must use HTTPS.');
      this.publicOrigin = url.origin;
      this.origins.add(url.origin);
    } else if (!localHost || env.VERCEL === '1')
      throw new Error('APP_ORIGIN is required for public access.');
    if (env.VERCEL === '1' && env.VERCEL_URL) {
      // Vercel supplies the current deployment hostname without a scheme.
      // Only this exact host is added, never a wildcard for other deployments.
      // https://vercel.com/docs/environment-variables/system-environment-variables#vercel_url
      if (!/^[a-z\d](?:[a-z\d-]{0,61}[a-z\d])?\.vercel\.app$/i.test(env.VERCEL_URL))
        throw new Error('VERCEL_URL must be a deployment hostname ending in .vercel.app.');
      this.deploymentHost = env.VERCEL_URL.toLowerCase();
      this.origins.add('https://' + this.deploymentHost);
    }
    this.twoFactor = new TwoFactor(
      secrets ?? new SecretStore(dataDir, env, state, Boolean(env.DATABASE_URL)),
      state,
      this.sessionKey,
    );
    this.throttle = new LoginThrottle(state);
    this.secureCookie = this.publicOrigin?.startsWith('https://') ?? false;
    this.cookieName = this.secureCookie ? '__Host-ritm_session' : 'ritm_session';
  }
  private token(req: Request) {
    const values = req.headers.cookie
      ?.split(';')
      .map((part) => part.trim())
      .filter((part) => part.startsWith(this.cookieName + '='));
    // An ambiguous cookie list must never select whichever identity came first.
    return values?.length === 1 ? values[0].slice(this.cookieName.length + 1) : undefined;
  }
  private async checkPassword(password: string) {
    if (this.passwordChecks >= maxPasswordChecks) {
      throw new AppError(
        429,
        'AUTH_BUSY',
        'Сейчас обрабатывается несколько входов. Повторите через несколько секунд.',
      );
    }
    this.passwordChecks++;
    try {
      return await new Promise<Buffer>((done, reject) => {
        scrypt(password, this.salt, 32, (error, derivedKey) => {
          if (error) reject(error);
          else done(derivedKey);
        });
      });
    } finally {
      this.passwordChecks--;
    }
  }
  async ownerSession(req: Request): Promise<string | null> {
    if (!this.passwordHash)
      return loopback(req.socket.remoteAddress) ? digest('local:' + this.credentialVersion) : null;
    const token = this.token(req);
    if (!token || token.length > 4096) return null;
    let id: string;
    try {
      const { payload } = await jwtVerify(token, this.sessionKey, {
        algorithms: ['HS256'],
        issuer: 'ritm',
        audience: 'ritm-owner',
        requiredClaims: ['jti', 'exp', 'iat', 'sub'],
      });
      if (
        payload.sub !== 'owner' ||
        payload.version !== this.credentialVersion ||
        typeof payload.jti !== 'string'
      )
        return null;
      id = this.credentialVersion + ':' + digest(payload.jti);
    } catch {
      return null;
    }
    const record = await this.state.getSession(id);
    if (!record) return null;
    const now = Date.now();
    if (now >= record.absoluteExpiresAt) return null;
    // Sliding expiry is renewed at most once per five minutes to bound database writes.
    if (now - record.lastSeenAt >= TOUCH_INTERVAL_MS)
      await this.state.touchSession(
        id,
        now,
        slidingExpiry(record.client, now, record.absoluteExpiresAt),
      );
    return id;
  }
  private get sessionPrefix() {
    return this.credentialVersion + ':';
  }
  /** Same address rule as the per-client rate limit: only the Vercel header is trusted. */
  private clientAddress(req: Request) {
    const forwarded =
      this.env.VERCEL === '1' ? req.get('x-vercel-forwarded-for')?.trim() : undefined;
    return forwarded && isIP(forwarded) ? forwarded : (req.socket.remoteAddress ?? 'unknown');
  }
  /** Keyed hash for security logs; the raw address is never written. */
  hashClient(req: Request) {
    return createHmac('sha256', this.sessionKey)
      .update('ritm:log:ip:' + this.clientAddress(req))
      .digest('hex')
      .slice(0, 16);
  }
  async hasOwnerSession(hash: string) {
    if (!this.passwordHash) return hash === digest('local:' + this.credentialVersion);
    if (!hash.startsWith(this.credentialVersion + ':')) return false;
    return this.state.hasSession(hash);
  }
  async authenticated(req: Request) {
    return Boolean(await this.ownerSession(req));
  }
  async session(req: Request) {
    return {
      authenticated: await this.authenticated(req),
      requiresLogin: Boolean(this.passwordHash),
    };
  }
  requireAuth = async (req: Request, _res: Response, next: NextFunction) => {
    try {
      if (!(await this.authenticated(req)))
        throw new AppError(401, 'AUTH_REQUIRED', 'Войдите в Ritm, чтобы продолжить.');
      next();
    } catch (error) {
      next(error);
    }
  };
  originGuard = (req: Request, _res: Response, next: NextFunction) => {
    try {
      const host = req.get('host');
      let hostname: string;
      try {
        const authority = host?.match(/^(\[[\da-fA-F:.]+\]|[a-zA-Z\d.-]+)(?::\d{1,5})?$/);
        if (!authority) throw new Error('Invalid authority');
        const parsed = new URL('http://' + host);
        if (parsed.hostname.toLowerCase() !== authority[1].toLowerCase())
          throw new Error('Noncanonical host');
        hostname = parsed.hostname;
      } catch {
        throw new AppError(403, 'INVALID_HOST', 'Недопустимый адрес приложения.');
      }
      const publicHost = this.publicOrigin ? new URL(this.publicOrigin).host : undefined;
      if (!loopback(hostname) && host !== publicHost && host !== this.deploymentHost)
        throw new AppError(403, 'INVALID_HOST', 'Откройте Ritm по настроенному адресу приложения.');
      if (!this.passwordHash && !loopback(req.socket.remoteAddress))
        throw new AppError(403, 'LOCAL_ONLY', 'Настройте пароль приложения для сетевого доступа.');
      const origin = req.get('origin');
      if (origin && !this.origins.has(origin))
        throw new AppError(403, 'INVALID_ORIGIN', 'Запрос с этого сайта запрещён.');
      const oauthCallback =
        req.method === 'GET' &&
        req.originalUrl.split('?')[0] === '/api/integrations/google/callback';
      const telegramWebhook =
        req.method === 'POST' &&
        req.originalUrl.split('?')[0] === '/api/integrations/telegram/webhook';
      if (
        !origin &&
        req.get('sec-fetch-site') === 'cross-site' &&
        !oauthCallback &&
        !telegramWebhook
      )
        throw new AppError(403, 'INVALID_ORIGIN', 'Запрос с другого сайта запрещён.');
      if (
        !['GET', 'HEAD', 'OPTIONS'].includes(req.method) &&
        !/^application\/json(?:\s*;|$)/i.test(req.get('content-type') ?? '')
      )
        throw new AppError(415, 'JSON_REQUIRED', 'Запрос должен содержать JSON.');
      next();
    } catch (error) {
      next(error);
    }
  };
  async limit(req: Request, key: string, maximum: number, windowMs: number) {
    let bucket: string;
    if (['login', 'public-session', 'oauth-callback'].includes(key)) {
      // Vercel supplies this header; ordinary servers never trust it. Lists,
      // malformed addresses and absent headers fall back to the socket peer.
      // https://vercel.com/docs/headers/request-headers#x-vercel-forwarded-for
      const address = this.clientAddress(req);
      bucket = createHmac('sha256', this.sessionKey)
        .update('ritm:' + key + ':client:' + address)
        .digest('hex');
    } else {
      bucket = digest('ritm:owner:' + key);
    }
    const result = await this.state.consumeRateLimit(bucket, maximum, windowMs);
    if (!result.allowed) {
      const retryAfterSeconds = Math.max(1, Math.ceil(result.retryAfterMs / 1000));
      throw new AppError(
        429,
        key === 'idea-review' ? 'IDEA_REVIEW_RATE_LIMIT' : 'RATE_LIMIT',
        key === 'idea-review'
          ? `Ritm временно ограничил частоту разбора идей. Повторите через ${retryAfterSeconds} с.`
          : `Слишком много запросов в Ritm. Повторите через ${retryAfterSeconds} с.`,
        retryAfterSeconds,
      );
    }
  }
  private async passwordMatches(password: string) {
    if (!this.passwordHash) return true;
    const input = await this.checkPassword(password);
    return timingSafeEqual(input, this.passwordHash);
  }
  /** Failed password or second-factor attempts spend the account-wide budget. */
  private async countFailure<T>(action: () => Promise<T>) {
    try {
      return await action();
    } catch (error) {
      if (error instanceof AppError && ['TOTP_INVALID', 'INVALID_PASSWORD'].includes(error.code))
        await this.throttle.recordFailure();
      throw error;
    }
  }
  async login(req: Request, res: Response, credentials: LoginInput | string, secret?: string) {
    const input: LoginInput =
      typeof credentials === 'string'
        ? { login: credentials, password: secret ?? '' }
        : credentials;
    await this.limit(req, 'login', 10, 15 * 60_000);
    await this.throttle.assertOpen();
    const passwordOk = await this.passwordMatches(input.password);
    const loginMatches = timingSafeEqual(
      Buffer.from(digest(input.login.trim().toLocaleLowerCase('en-US')), 'hex'),
      Buffer.from(digest(this.loginName), 'hex'),
    );
    if (this.passwordHash) {
      await this.countFailure(async () => {
        if (!passwordOk || !loginMatches)
          throw new AppError(401, 'INVALID_PASSWORD', 'Неверный логин или пароль.');
        await this.twoFactor.verify({ code: input.totp, recoveryCode: input.recoveryCode });
      });
      await this.throttle.recordSuccess();
      const client: SessionClient = input.client ?? 'web';
      const now = Date.now(),
        policy = sessionPolicy[client],
        absolute = now + policy.absoluteMs;
      const id = randomUUID();
      const token = await new SignJWT({ version: this.credentialVersion })
        .setProtectedHeader({ alg: 'HS256', typ: 'JWT' })
        .setSubject('owner')
        .setIssuer('ritm')
        .setAudience('ritm-owner')
        .setJti(id)
        .setIssuedAt()
        .setExpirationTime(Math.floor(absolute / 1000))
        .sign(this.sessionKey);
      await this.state.createSession(
        this.sessionPrefix + digest(id),
        slidingExpiry(client, now, absolute),
        {
          client,
          deviceName:
            cleanDeviceName(input.deviceName) || deviceNameFromUserAgent(req.get('user-agent')),
          createdAt: now,
          lastSeenAt: now,
          absoluteExpiresAt: absolute,
        },
      );
      res.cookie(this.cookieName, token, {
        httpOnly: true,
        sameSite: 'strict',
        secure: this.secureCookie,
        maxAge: policy.absoluteMs,
        path: '/',
      });
    }
    return { authenticated: true, requiresLogin: Boolean(this.passwordHash) };
  }
  private requirePasswordMode() {
    if (!this.passwordHash)
      throw new AppError(
        409,
        'PASSWORD_REQUIRED',
        'Защита аккаунта доступна, когда для приложения задан пароль.',
      );
  }
  private clearSessionCookie(res: Response) {
    res.clearCookie(this.cookieName, {
      httpOnly: true,
      sameSite: 'strict',
      secure: this.secureCookie,
      path: '/',
    });
  }
  async overview(req: Request) {
    const current = await this.ownerSession(req);
    const records = this.passwordHash ? await this.state.listSessions(this.sessionPrefix) : [];
    return {
      ...(await this.twoFactor.status()),
      sessions: records.map((record) => ({
        id: record.hash.slice(this.sessionPrefix.length),
        client: record.client,
        deviceName: record.deviceName || 'Неизвестное устройство',
        createdAt: isoSeconds(
          record.createdAt ||
            Math.max(0, record.expiresAt - sessionPolicy[record.client].slidingMs),
        ),
        lastSeenAt: isoSeconds(record.lastSeenAt || record.createdAt || record.expiresAt),
        current: record.hash === current,
      })),
    };
  }
  async revokeSession(req: Request, res: Response, id: string) {
    this.requirePasswordMode();
    if (!sessionId.test(id)) throw missing('Сессия');
    const hash = this.sessionPrefix + id;
    const current = await this.ownerSession(req);
    if (!(await this.state.hasSession(hash))) throw missing('Сессия');
    await this.state.deleteSession(hash);
    if (hash === current) this.clearSessionCookie(res);
  }
  async revokeOtherSessions(req: Request) {
    this.requirePasswordMode();
    const current = await this.ownerSession(req);
    if (current) await this.state.deleteOtherSessions(this.sessionPrefix, current);
  }
  async startTotp() {
    this.requirePasswordMode();
    return this.twoFactor.setup(this.loginName);
  }
  async confirmTotp(code: string) {
    this.requirePasswordMode();
    return { recoveryCodes: await this.countFailure(() => this.twoFactor.confirm(code)) };
  }
  async regenerateRecoveryCodes(code: string) {
    this.requirePasswordMode();
    return { recoveryCodes: await this.countFailure(() => this.twoFactor.regenerate(code)) };
  }
  async disableTotp(password: string, input: TwoFactorInput) {
    this.requirePasswordMode();
    await this.countFailure(async () => {
      if (!(await this.passwordMatches(password)))
        throw new AppError(401, 'INVALID_PASSWORD', 'Неверный пароль.');
      await this.twoFactor.verify(input);
    });
    await this.twoFactor.disable();
    return { totpEnabled: false };
  }
  async logout(req: Request, res: Response) {
    const hash = await this.ownerSession(req);
    if (hash && this.passwordHash) await this.state.deleteSession(hash);
    res.clearCookie(this.cookieName, {
      httpOnly: true,
      sameSite: 'strict',
      secure: this.secureCookie,
      path: '/',
    });
    return {
      authenticated: !this.passwordHash && loopback(req.socket.remoteAddress),
      requiresLogin: Boolean(this.passwordHash),
    };
  }
}
