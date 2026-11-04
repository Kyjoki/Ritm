import { randomUUID } from 'node:crypto';
import type { Request, Response, NextFunction } from 'express';
import { AppError } from './errors.ts';

const bodyLimit = 128 * 1024;
const methods = ['GET', 'HEAD', 'POST', 'PATCH', 'DELETE'];

// These checks run before JSON parsing and never decompress attacker input.
export function apiRequestGuard(req: Request, res: Response, next: NextFunction) {
  try {
    if (Buffer.byteLength(req.originalUrl) > 8192)
      throw new AppError(414, 'URL_TOO_LONG', 'Адрес запроса слишком длинный.');
    // PUT exists only for versioned workout documents.
    const putAllowed = req.method === 'PUT' && req.originalUrl.startsWith('/api/workouts/');
    if (!methods.includes(req.method) && !putAllowed) {
      res.setHeader('Allow', methods.join(', '));
      throw new AppError(405, 'METHOD_NOT_ALLOWED', 'Этот метод запроса не поддерживается.');
    }
    const encoding = req.get('content-encoding');
    if (encoding && encoding.toLowerCase() !== 'identity')
      throw new AppError(415, 'ENCODING_NOT_ALLOWED', 'Отправьте JSON без сжатия.');
    const length = req.get('content-length');
    if (length && (!/^\d+$/.test(length) || Number(length) > bodyLimit))
      throw new AppError(413, 'REQUEST_TOO_LARGE', 'Запрос слишком большой. Сократите текст.');
    if (
      ['GET', 'HEAD'].includes(req.method) &&
      ((length && Number(length) > 0) || req.get('transfer-encoding'))
    )
      throw new AppError(400, 'BODY_NOT_ALLOWED', 'Этот запрос не должен содержать тело.');
    next();
  } catch (error) {
    next(error);
  }
}

export type SecurityEvent =
  | 'request_blocked'
  | 'server_error'
  | 'login_success'
  | 'logout'
  | 'google_connected'
  | 'google_disconnected'
  | 'openai_saved'
  | 'openai_removed';
export interface SecurityRecord {
  time: string;
  event: SecurityEvent;
  requestId: string;
  status: number;
  ipHash?: string;
  route?: string;
}
export type SecurityLogger = (record: SecurityRecord) => void;

export function createSecurityAudit(logger: SecurityLogger, now = () => Date.now()) {
  let windowStart = now();
  let count = 0;
  return (
    res: Pick<Response, 'statusCode' | 'locals'>,
    event: SecurityEvent,
    status = res.statusCode,
  ) => {
    const time = now();
    if (time - windowStart >= 60_000) {
      windowStart = time;
      count = 0;
    }
    // Logging floods cannot grow memory or produce unbounded log volume. This
    // is per instance; edge traffic analytics remain a separate deployment gate.
    if (count++ >= 60) return;
    try {
      const result = logger({
        time: new Date(time).toISOString(),
        event,
        requestId: res.locals.requestId,
        status,
        ...(typeof res.locals.ipHash === 'string' ? { ipHash: res.locals.ipHash } : {}),
        ...(typeof res.locals.routeFamily === 'string' ? { route: res.locals.routeFamily } : {}),
      });
      // TypeScript void callbacks may still be async. Observe a rejected
      // exporter Promise without making request protection depend on it.
      void Promise.resolve(result).catch(() => {});
    } catch {
      // A failing log sink must not bypass authentication or fail a user action.
    }
  };
}

export function requestIdentity(_req: Request, res: Response, next: NextFunction) {
  // Never reflect client IDs, request URLs, bodies, IPs or credentials into logs.
  res.locals.requestId = randomUUID();
  res.setHeader('X-Request-Id', res.locals.requestId);
  next();
}
