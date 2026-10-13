import {
  createHash,
  createHmac,
  randomBytes,
  randomUUID,
  scryptSync,
  timingSafeEqual,
} from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { isIP } from 'node:net';
import { SignJWT, jwtVerify } from 'jose';
import type { NextFunction, Request, Response } from 'express';
import { AppError } from './errors.ts';
import type { RuntimeState } from './runtime-state.ts';

const digest = (value: string) => createHash('sha256').update(value).digest('hex');
const loopback = (address: string | undefined) =>
  Boolean(
    address && ['127.0.0.1', '::1', '[::1]', '::ffff:127.0.0.1', 'localhost'].includes(address),
  );
const sessionLifetime = 8 * 60 * 60_000;

export class Security {
  private passwordHash: Buffer | null;
  private salt = randomBytes(32);
  private origins: Set<string>;
  private publicOrigin: string | undefined;
  private secureCookie: boolean;
  private sessionKey: Buffer;
  private credentialVersion: string;
  private loginName: string;
  constructor(
    private env: NodeJS.ProcessEnv,
    private state: RuntimeState,
    dataDir: string,
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
    this.secureCookie = this.publicOrigin?.startsWith('https://') ?? false;
  }
  private token(req: Request) {
    return req.headers.cookie
      ?.split(';')
      .map((part) => part.trim())
      .find((part) => part.startsWith('ritm_session='))
      ?.slice('ritm_session='.length);
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
        maxTokenAge: '8h',
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
    return (await this.state.hasSession(id)) ? id : null;
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
        hostname = new URL('http://' + host).hostname;
      } catch {
        throw new AppError(403, 'INVALID_HOST', 'Недопустимый адрес приложения.');
      }
      const publicHost = this.publicOrigin ? new URL(this.publicOrigin).host : undefined;
      if (!loopback(hostname) && host !== publicHost)
        throw new AppError(403, 'INVALID_HOST', 'Откройте Ritm по настроенному адресу приложения.');
      if (!this.passwordHash && !loopback(req.socket.remoteAddress))
        throw new AppError(403, 'LOCAL_ONLY', 'Настройте пароль приложения для сетевого доступа.');
      const origin = req.get('origin');
      if (origin && !this.origins.has(origin))
        throw new AppError(403, 'INVALID_ORIGIN', 'Запрос с этого сайта запрещён.');
      const oauthCallback =
        req.method === 'GET' &&
        req.originalUrl.split('?')[0] === '/api/integrations/google/callback';
      if (!origin && req.get('sec-fetch-site') === 'cross-site' && !oauthCallback)
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
    if (key === 'login') {
      // Vercel supplies this header; ordinary servers never trust it. Lists,
      // malformed addresses and absent headers fall back to the socket peer.
      // https://vercel.com/docs/headers/request-headers#x-vercel-forwarded-for
      const forwarded =
        this.env.VERCEL === '1' ? req.get('x-vercel-forwarded-for')?.trim() : undefined;
      const address =
        forwarded && isIP(forwarded) ? forwarded : (req.socket.remoteAddress ?? 'unknown');
      bucket = createHmac('sha256', this.sessionKey)
        .update('ritm:login:client:' + address)
        .digest('hex');
    } else {
      bucket = digest('ritm:owner:' + key);
    }
    const result = await this.state.consumeRateLimit(bucket, maximum, windowMs);
    if (!result.allowed)
      throw new AppError(
        429,
        'RATE_LIMIT',
        'Слишком много запросов. Подождите немного и повторите.',
      );
  }
  async login(req: Request, res: Response, login: string, password: string) {
    await this.limit(req, 'login', 10, 15 * 60_000);
    const inputHash = scryptSync(password, this.salt, 32);
    const passwordMatches = !this.passwordHash || timingSafeEqual(inputHash, this.passwordHash);
    const loginMatches = timingSafeEqual(
      Buffer.from(digest(login.trim().toLocaleLowerCase('en-US')), 'hex'),
      Buffer.from(digest(this.loginName), 'hex'),
    );
    if (this.passwordHash && (!passwordMatches || !loginMatches))
      throw new AppError(401, 'INVALID_PASSWORD', 'Неверный логин или пароль.');
    if (this.passwordHash) {
      const id = randomUUID(),
        expiry = Date.now() + sessionLifetime;
      const token = await new SignJWT({ version: this.credentialVersion })
        .setProtectedHeader({ alg: 'HS256', typ: 'JWT' })
        .setSubject('owner')
        .setIssuer('ritm')
        .setAudience('ritm-owner')
        .setJti(id)
        .setIssuedAt()
        .setExpirationTime(Math.floor(expiry / 1000))
        .sign(this.sessionKey);
      await this.state.createSession(this.credentialVersion + ':' + digest(id), expiry);
      res.cookie('ritm_session', token, {
        httpOnly: true,
        sameSite: 'strict',
        secure: this.secureCookie,
        maxAge: sessionLifetime,
        path: '/',
      });
    }
    return { authenticated: true, requiresLogin: Boolean(this.passwordHash) };
  }
  async logout(req: Request, res: Response) {
    const hash = await this.ownerSession(req);
    if (hash && this.passwordHash) await this.state.deleteSession(hash);
    res.clearCookie('ritm_session', {
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
