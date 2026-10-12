import { createHash, randomBytes, scryptSync, timingSafeEqual } from 'node:crypto';
import type { NextFunction, Request, Response } from 'express';
import { AppError } from './errors.ts';

const digest = (value: string) => createHash('sha256').update(value).digest('hex');
const loopback = (address: string | undefined) =>
  Boolean(
    address && ['127.0.0.1', '::1', '[::1]', '::ffff:127.0.0.1', 'localhost'].includes(address),
  );

export class Security {
  private passwordHash: Buffer | null;
  private salt = randomBytes(32);
  private sessions = new Map<string, number>();
  private limits = new Map<string, { count: number; resets: number }>();
  private origins: Set<string>;
  private publicOrigin: string | undefined;
  private secureCookie: boolean;
  constructor(private env: NodeJS.ProcessEnv = process.env) {
    const password = env.APP_PASSWORD;
    const host = env.HOST || '127.0.0.1';
    const localHost = loopback(host);
    if ((!localHost || env.NODE_ENV === 'production') && !password) {
      throw new Error('APP_PASSWORD is required for production or a non-loopback HOST.');
    }
    if (password && (password.length < 12 || password.length > 512))
      throw new Error('APP_PASSWORD must contain 12–512 characters.');
    this.passwordHash = password ? scryptSync(password, this.salt, 32) : null;
    const port = env.PORT || '3001';
    this.origins = new Set([`http://127.0.0.1:${port}`, `http://localhost:${port}`]);
    if (host === '::1') this.origins.add(`http://[::1]:${port}`);
    if (env.NODE_ENV !== 'production') {
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
      ) {
        throw new Error('APP_ORIGIN must be an http(s) origin without a path.');
      }
      if (!loopback(url.hostname) && url.protocol !== 'https:')
        throw new Error('Public APP_ORIGIN must use HTTPS.');
      this.publicOrigin = url.origin;
      this.origins.add(url.origin);
    } else if (!localHost) {
      throw new Error('APP_ORIGIN is required for a non-loopback HOST.');
    }
    this.secureCookie = this.publicOrigin?.startsWith('https://') ?? false;
  }
  private token(req: Request): string | undefined {
    return req.headers.cookie
      ?.split(';')
      .map((part) => part.trim())
      .find((part) => part.startsWith('ritm_session='))
      ?.slice('ritm_session='.length);
  }
  private prune() {
    const now = Date.now();
    for (const [id, expires] of this.sessions) if (expires <= now) this.sessions.delete(id);
    for (const [id, value] of this.limits) if (value.resets <= now) this.limits.delete(id);
  }
  authenticated(req: Request) {
    if (!this.passwordHash) return loopback(req.socket.remoteAddress);
    const token = this.token(req);
    return Boolean(token && (this.sessions.get(digest(token)) ?? 0) > Date.now());
  }
  session(req: Request) {
    return { authenticated: this.authenticated(req), requiresLogin: Boolean(this.passwordHash) };
  }
  requireAuth = (req: Request, _res: Response, next: NextFunction) => {
    if (!this.authenticated(req))
      return next(new AppError(401, 'AUTH_REQUIRED', 'Войдите в Ritm, чтобы продолжить.'));
    next();
  };
  originGuard = (req: Request, _res: Response, next: NextFunction) => {
    try {
      this.prune();
      const host = req.get('host');
      let hostname: string;
      try {
        hostname = new URL(`http://${host}`).hostname;
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
      if (!origin && req.get('sec-fetch-site') === 'cross-site')
        throw new AppError(403, 'INVALID_ORIGIN', 'Запрос с другого сайта запрещён.');
      if (
        !['GET', 'HEAD', 'OPTIONS'].includes(req.method) &&
        !/^application\/json(?:\s*;|$)/i.test(req.get('content-type') ?? '')
      ) {
        throw new AppError(415, 'JSON_REQUIRED', 'Запрос должен содержать JSON.');
      }
      next();
    } catch (error) {
      next(error);
    }
  };
  limit(req: Request, key: string, maximum: number, windowMs: number) {
    const id = `${key}:${req.socket.remoteAddress ?? 'unknown'}`;
    const now = Date.now();
    let bucket = this.limits.get(id);
    if (!bucket || bucket.resets <= now) {
      bucket = { count: 0, resets: now + windowMs };
      this.limits.set(id, bucket);
    }
    if (++bucket.count > maximum)
      throw new AppError(
        429,
        'RATE_LIMIT',
        'Слишком много запросов. Подождите немного и повторите.',
      );
  }
  login(req: Request, res: Response, password: string) {
    this.limit(req, 'login', 10, 15 * 60_000);
    if (
      this.passwordHash &&
      !timingSafeEqual(scryptSync(password, this.salt, 32), this.passwordHash)
    ) {
      throw new AppError(401, 'INVALID_PASSWORD', 'Неверный пароль приложения.');
    }
    if (this.passwordHash) {
      const token = randomBytes(32).toString('base64url');
      this.sessions.set(digest(token), Date.now() + 8 * 60 * 60_000);
      res.cookie('ritm_session', token, {
        httpOnly: true,
        sameSite: 'strict',
        secure: this.secureCookie,
        maxAge: 8 * 60 * 60_000,
        path: '/',
      });
    }
    return { authenticated: true, requiresLogin: Boolean(this.passwordHash) };
  }
  logout(req: Request, res: Response) {
    const token = this.token(req);
    if (token) this.sessions.delete(digest(token));
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
