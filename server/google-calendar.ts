import { createHash, randomBytes, randomUUID, timingSafeEqual } from 'node:crypto';
import { performance } from 'node:perf_hooks';
import { CodeChallengeMethod, OAuth2Client, type Credentials } from 'google-auth-library';
import { z } from 'zod';
import { CALENDAR_PALETTE } from '../shared/calendar-colors.ts';
import type {
  GoogleCalendarEvent,
  GoogleCalendarResult,
  GoogleCalendarStatus,
  GoogleTaskCompletion,
  GoogleTasksStatus,
  GoogleEventInput,
  GoogleOAuthSetup,
  GoogleOAuthSetupInput,
  Settings,
} from '../shared/types.ts';
import { AppError, conflict } from './errors.ts';
import { calendarColorSchema, dateValue, minutes, timeValue } from './validation.ts';

export const GOOGLE_CALLBACK_PATH = '/api/integrations/google/callback';
export const GOOGLE_OAUTH_COOKIE = 'ritm_google_flow';
export const GOOGLE_CALENDAR_SCOPE = 'https://www.googleapis.com/auth/calendar.events';
export const GOOGLE_TASKS_SCOPE = 'https://www.googleapis.com/auth/tasks';
export const GOOGLE_CALENDAR_LABELS_SCOPE = 'https://www.googleapis.com/auth/calendar.calendars';
const CALENDAR_URL = 'https://www.googleapis.com/calendar/v3/calendars/primary';
const EVENTS_URL = 'https://www.googleapis.com/calendar/v3/calendars/primary/events';
const TASKS_URL = 'https://tasks.googleapis.com/tasks/v1';
const TOKEN_SLOT = 'google.tokens';
const CONFIGURATION_SLOT = 'google.oauth.configuration';
const EPOCH_SLOT = 'google.connection-epoch';
const CONNECTION_LEASE = 'google.connection';
const FLOW_TTL_MS = 10 * 60_000;
const MAX_EVENTS = 1000;
const hash = (value: string) => createHash('sha256').update(value).digest('hex');
const ownerHashPattern = /^(?:[a-f0-9]{64}:)?[a-f0-9]{64}$/;
const loopback = (host: string) => ['localhost', '127.0.0.1', '[::1]', '::1'].includes(host);
const sleep = (ms: number) => new Promise<void>((done) => setTimeout(done, ms));

export interface GoogleSecretStorage {
  getSecret(name: string): Promise<string | null>;
  saveSecret(name: string, value: string): Promise<void>;
  removeSecret(name: string): Promise<void>;
  consumeSecret(name: string): Promise<string | null>;
  acquireLease(name: string, ttlMs: number): Promise<string | null>;
  releaseLease(name: string, token: string): Promise<void>;
}
export interface GoogleSessionSecurity {
  hasOwnerSession(hash: string): Promise<boolean>;
}
export interface GoogleOAuthConfig {
  clientId: string;
  clientSecret: string;
  redirectUri: string;
}
export interface GoogleRequest {
  method: 'GET' | 'POST' | 'PATCH' | 'DELETE';
  resource?: 'calendar' | 'tasklists' | 'tasks';
  taskListId?: string;
  taskId?: string;
  eventId?: string;
  query?: Record<string, string | number | boolean>;
  body?: Record<string, unknown>;
  headers?: Record<string, string>;
  signal?: AbortSignal;
}
export interface GoogleTransport {
  exchangeCode(config: GoogleOAuthConfig, code: string, codeVerifier: string): Promise<Credentials>;
  refreshToken(config: GoogleOAuthConfig, refreshToken: string): Promise<Credentials>;
  request(config: GoogleOAuthConfig, accessToken: string, request: GoogleRequest): Promise<unknown>;
}
export interface GoogleCalendarOptions {
  secrets: GoogleSecretStorage;
  security: GoogleSessionSecurity;
  settings: () => Promise<Settings>;
  env?: NodeJS.ProcessEnv;
  transport?: GoogleTransport;
  now?: () => number;
  leaseClock?: () => number;
}

const flowSchema = z
  .object({
    ownerSessionHash: z.string().regex(ownerHashPattern),
    correlationHash: z.string().regex(/^[a-f0-9]{64}$/),
    codeVerifier: z.string().min(43).max(128),
    expiresAt: z.number().int(),
    configFingerprint: z.string().regex(/^[a-f0-9]{64}$/),
    epoch: z.string().uuid(),
    extendedColors: z.boolean().optional(),
    tasks: z.boolean().optional(),
  })
  .strict();
const tokensSchema = z
  .object({
    accessToken: z.string().max(8192),
    refreshToken: z.string().min(1).max(8192),
    expiresAt: z.number().int(),
    scope: z.string().max(2000),
    needsReauth: z.boolean(),
    configFingerprint: z.string().regex(/^[a-f0-9]{64}$/),
    connectionId: z.string().uuid(),
    epoch: z.string().uuid().optional(),
    lastFetchedAt: z.string().nullable(),
    extendedColors: z.boolean().optional(),
    tasks: z.boolean().optional(),
  })
  .strict();
type StoredTokens = z.infer<typeof tokensSchema>;
interface GoogleConnection {
  tokens: StoredTokens;
  config: GoogleOAuthConfig;
  epoch: string;
}
const googleClientIdSchema = z
  .string()
  .trim()
  .min(1)
  .max(512)
  .regex(/^[a-zA-Z0-9_-]+\.apps\.googleusercontent\.com$/);
const googleClientSecretSchema = z.string().trim().min(1).max(2048).regex(/^\S+$/);
const savedConfigurationSchema = z
  .object({ clientId: googleClientIdSchema, clientSecret: googleClientSecretSchema })
  .strict();
export const googleOAuthSetupInputSchema = z
  .object({
    clientId: googleClientIdSchema,
    clientSecret: z
      .string()
      .trim()
      .max(2048)
      .refine((value) => !value || /^\S+$/.test(value))
      .optional(),
  })
  .strict();
export const googleEventInputSchema = z
  .object({
    title: z.string().trim().min(1).max(160),
    description: z.string().max(4000),
    date: dateValue,
    time: timeValue.nullable(),
    duration: z.number().int().min(5).max(720),
    allDay: z.boolean(),
    colorId: calendarColorSchema.nullable().optional(),
    repeat: z.enum(['none', 'daily', 'weekly', 'monthly']).optional(),
  })
  .strict()
  .refine(
    (value) =>
      value.allDay
        ? value.time === null
        : Boolean(value.time) && minutes(value.time!) + value.duration <= 1440,
    'Укажите время события или выберите весь день; завершение должно быть до полуночи.',
  );
export const googleEventIdSchema = z
  .string()
  .min(5)
  .max(1024)
  .regex(/^[a-zA-Z0-9_-]+$/);
export const googleEtagSchema = z
  .string()
  .max(256)
  .regex(/^(?:W\/)?"[^"\r\n]+"$/);

function callbackUriFrom(env: NodeJS.ProcessEnv): string | null {
  const explicit = env.GOOGLE_REDIRECT_URI?.trim(),
    appOrigin = env.APP_ORIGIN?.trim();
  if (!explicit && !appOrigin) return null;
  const origin = appOrigin ? new URL(appOrigin) : null;
  if (
    origin &&
    (origin.username ||
      origin.password ||
      origin.pathname !== '/' ||
      origin.search ||
      origin.hash ||
      (origin.protocol !== 'https:' && !(origin.protocol === 'http:' && loopback(origin.hostname))))
  )
    throw new Error('Google OAuth requires a fixed HTTPS or localhost APP_ORIGIN.');
  const redirect = new URL(explicit || GOOGLE_CALLBACK_PATH, origin?.origin);
  if (
    redirect.username ||
    redirect.password ||
    redirect.search ||
    redirect.hash ||
    redirect.pathname !== GOOGLE_CALLBACK_PATH ||
    (redirect.protocol !== 'https:' &&
      !(redirect.protocol === 'http:' && loopback(redirect.hostname)))
  ) {
    throw new Error(
      'Invalid Google OAuth server configuration. Use a Web application client and a fixed HTTPS or localhost callback.',
    );
  }
  if (
    (origin && origin.origin !== redirect.origin) ||
    (!origin &&
      (!loopback(redirect.hostname) || env.NODE_ENV === 'production' || env.VERCEL === '1'))
  ) {
    throw new Error('GOOGLE_REDIRECT_URI must use the configured APP_ORIGIN.');
  }
  return redirect.href;
}

function oauthClient(config: GoogleOAuthConfig) {
  const client = new OAuth2Client({
    clientId: config.clientId,
    clientSecret: config.clientSecret,
    redirectUri: config.redirectUri,
    eagerRefreshThresholdMillis: 0,
  });
  client.transporter.interceptors.request.add({
    resolved: async (options) => ({
      ...options,
      timeout: 15_000,
      retry: false,
      retryConfig: { retry: 0 },
      maxRedirects: 0,
      maxContentLength: 4 * 1024 * 1024,
    }),
  });
  return client;
}

export const defaultGoogleTransport: GoogleTransport = {
  async exchangeCode(config, code, codeVerifier) {
    return (
      await oauthClient(config).getToken({ code, codeVerifier, redirect_uri: config.redirectUri })
    ).tokens;
  },
  async refreshToken(config, refreshToken) {
    const client = oauthClient(config);
    client.setCredentials({ refresh_token: refreshToken });
    return (await client.refreshAccessToken()).credentials;
  },
  async request(config, accessToken, request) {
    if (
      request.resource === 'calendar' &&
      (request.eventId || !['GET', 'PATCH'].includes(request.method))
    )
      throw new Error('Unsupported Google calendar metadata operation');
    if (
      request.resource === 'tasklists' &&
      (request.method !== 'GET' || request.taskListId || request.taskId)
    )
      throw new Error('Unsupported Google task lists operation');
    if (
      request.resource === 'tasks' &&
      (!request.taskListId ||
        !['GET', 'PATCH'].includes(request.method) ||
        (request.method === 'PATCH' && !request.taskId))
    )
      throw new Error('Unsupported Google tasks operation');
    const client = oauthClient(config);
    // Refresh is coordinated through the durable lease, never independently by this API client.
    client.setCredentials({ access_token: accessToken });
    const url =
      request.resource === 'tasklists'
        ? `${TASKS_URL}/users/@me/lists`
        : request.resource === 'tasks'
          ? `${TASKS_URL}/lists/${encodeURIComponent(request.taskListId!)}/tasks${request.taskId ? '/' + encodeURIComponent(request.taskId) : ''}`
          : request.resource === 'calendar'
            ? CALENDAR_URL
            : request.eventId
              ? `${EVENTS_URL}/${encodeURIComponent(request.eventId)}`
              : EVENTS_URL;
    const response = await client.request({
      url,
      method: request.method,
      params: request.query,
      data: request.body,
      headers: request.headers,
      signal: request.signal,
      retry: false,
    });
    return response.data;
  },
};

function providerStatus(error: unknown): number | undefined {
  if (!error || typeof error !== 'object') return undefined;
  const value = error as { response?: { status?: unknown }; status?: unknown; code?: unknown };
  const status = value.response?.status ?? value.status ?? value.code;
  return typeof status === 'number' ? status : undefined;
}
function invalidGrant(error: unknown) {
  return Boolean(
    error &&
    typeof error === 'object' &&
    (error as { response?: { data?: { error?: unknown } } }).response?.data?.error ===
      'invalid_grant',
  );
}
function safeProviderError(error: unknown): AppError {
  const status = providerStatus(error);
  if (status === 412 || status === 409)
    return conflict('Событие Google изменилось. Обновите календарь и повторите редактирование.');
  if (status === 404 || status === 410)
    return new AppError(
      404,
      'GOOGLE_EVENT_NOT_FOUND',
      'Событие Google больше недоступно. Обновите календарь.',
    );
  if (status === 429)
    return new AppError(
      429,
      'GOOGLE_LIMIT',
      'Google сообщил о лимите запросов. Подождите немного и повторите.',
    );
  if (status === 401 || invalidGrant(error))
    return new AppError(
      401,
      'GOOGLE_REAUTH_REQUIRED',
      'Подключите Google Calendar заново в настройках.',
    );
  if (status === 403)
    return new AppError(
      403,
      'GOOGLE_FORBIDDEN',
      'Google не разрешил это действие. Проверьте права события и подключение Calendar API.',
    );
  if (error instanceof Error && ['AbortError', 'TimeoutError'].includes(error.name))
    return new AppError(
      504,
      'GOOGLE_TIMEOUT',
      'Google не успел ответить. Обновите календарь перед повторной записью.',
    );
  return new AppError(
    502,
    'GOOGLE_UNAVAILABLE',
    'Не удалось подтвердить ответ Google. Обновите календарь перед повторным сохранением.',
  );
}

function withAbort<T>(operation: () => Promise<T>, signal: AbortSignal): Promise<T> {
  if (signal.aborted) return Promise.reject(signal.reason);
  return new Promise<T>((resolve, reject) => {
    const abort = () => reject(signal.reason);
    signal.addEventListener('abort', abort, { once: true });
    Promise.resolve()
      .then(() => {
        signal.throwIfAborted();
        return operation();
      })
      .then(
        (value) => {
          signal.removeEventListener('abort', abort);
          resolve(value);
        },
        (error: unknown) => {
          signal.removeEventListener('abort', abort);
          reject(error);
        },
      );
  });
}

function localParts(instant: number, timeZone: string) {
  let formatter = zoneFormatters.get(timeZone);
  if (!formatter) {
    formatter = new Intl.DateTimeFormat('en', {
      timeZone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hourCycle: 'h23',
    });
    if (zoneFormatters.size >= 8) zoneFormatters.delete(zoneFormatters.keys().next().value!);
    zoneFormatters.set(timeZone, formatter);
  }
  const parts = formatter.formatToParts(instant);
  const get = (name: string) => parts.find((part) => part.type === name)!.value;
  return {
    date: `${get('year').padStart(4, '0')}-${get('month')}-${get('day')}`,
    time: `${get('hour')}:${get('minute')}:${get('second')}`,
  };
}
const zoneFormatters = new Map<string, Intl.DateTimeFormat>();
function dateShift(date: string, days: number) {
  const value = new Date(`${date}T12:00:00Z`);
  value.setUTCDate(value.getUTCDate() + days);
  const result = value.toISOString().slice(0, 10);
  return dateValue.parse(result);
}

/** Reject non-existent/ambiguous wall-clock times instead of silently moving the event. */
export function googleZonedInstant(date: string, time: string, timeZone: string) {
  const wall = `${date}T${time}:00`,
    target = Date.parse(`${wall}Z`);
  let instant = target;
  for (let attempt = 0; attempt < 4; attempt++) {
    const parts = localParts(instant, timeZone),
      delta = target - Date.parse(`${parts.date}T${parts.time}Z`);
    if (!delta) break;
    instant += delta;
  }
  const formatted = localParts(instant, timeZone);
  if (`${formatted.date}T${formatted.time}` !== wall)
    throw new AppError(
      400,
      'GOOGLE_TIME_GAP',
      'В выбранном часовом поясе такого времени нет из-за перевода часов. Выберите другое время.',
    );
  for (const difference of [-120, -90, -60, -30, -15, 15, 30, 60, 90, 120]) {
    const other = localParts(instant + difference * 60_000, timeZone);
    if (`${other.date}T${other.time}` === wall)
      throw new AppError(
        400,
        'GOOGLE_TIME_AMBIGUOUS',
        'Это время повторяется при переводе часов. Выберите однозначное время.',
      );
  }
  return instant;
}

function eventBody(input: GoogleEventInput, timeZone: string) {
  const frequency = { daily: 'DAILY', weekly: 'WEEKLY', monthly: 'MONTHLY' };
  const recurrence =
    input.repeat && input.repeat !== 'none'
      ? { recurrence: [`RRULE:FREQ=${frequency[input.repeat]}`] }
      : {};
  if (input.allDay)
    return {
      summary: input.title,
      description: input.description,
      start: { date: input.date, ...(input.repeat && input.repeat !== 'none' ? { timeZone } : {}) },
      end: {
        date: dateShift(input.date, 1),
        ...(input.repeat && input.repeat !== 'none' ? { timeZone } : {}),
      },
      ...recurrence,
    };
  const start = googleZonedInstant(input.date, input.time!, timeZone),
    end = start + input.duration * 60_000;
  const localEnd = localParts(end, timeZone);
  if (
    localEnd.date !== input.date &&
    !(localEnd.date === dateShift(input.date, 1) && localEnd.time === '00:00:00')
  )
    throw new AppError(
      400,
      'GOOGLE_TIME_RANGE',
      'Завершите событие до полуночи в выбранном часовом поясе.',
    );
  return {
    summary: input.title,
    description: input.description,
    start: { dateTime: new Date(start).toISOString(), timeZone },
    end: { dateTime: new Date(end).toISOString(), timeZone },
    ...recurrence,
  };
}

const eventSchema = z
  .object({
    id: googleEventIdSchema,
    etag: z.string().max(256),
    summary: z.string().optional(),
    colorId: z.string().max(64).optional(),
    eventLabelId: z.string().max(128).optional(),
    description: z.string().optional(),
    status: z.string().optional(),
    start: z.object({
      date: dateValue.optional(),
      dateTime: z.iso.datetime({ offset: true }).optional(),
    }),
    end: z.object({
      date: dateValue.optional(),
      dateTime: z.iso.datetime({ offset: true }).optional(),
    }),
    transparency: z.string().optional(),
    locked: z.boolean().optional(),
    eventType: z.string().optional(),
    organizer: z.object({ self: z.boolean().optional() }).optional(),
    creator: z.object({ self: z.boolean().optional() }).optional(),
    attendees: z.array(z.object({ self: z.boolean().optional() })).optional(),
    recurrence: z.array(z.string()).optional(),
    recurringEventId: z.string().min(1).max(1024).optional(),
  })
  .passthrough();

function isLinkedTaskMirrorCandidate(event: z.infer<typeof eventSchema>) {
  return (
    Boolean(event.summary?.trim()) &&
    event.summary!.trim().length <= 160 &&
    (event.description?.length ?? 0) <= 4000 &&
    event.eventType === 'focusTime' &&
    event.creator?.self === true &&
    event.organizer?.self === true &&
    !event.locked &&
    !event.attendees?.some((attendee) => attendee.self !== true) &&
    !event.recurringEventId &&
    event.recurrence === undefined &&
    Boolean(taskLinkFromDescription(event.description ?? ''))
  );
}

const labelSchema = z
  .object({
    id: z.string().uuid(),
    backgroundColor: z.string().regex(/^#[0-9a-f]{6}$/i),
    name: z.string().max(50).optional(),
  })
  .passthrough();
const calendarLabelsSchema = z
  .object({
    etag: googleEtagSchema,
    labelProperties: z
      .object({ eventLabels: z.array(labelSchema).max(200).optional() })
      .passthrough()
      .optional(),
  })
  .passthrough();
type CalendarLabels = z.infer<typeof calendarLabelsSchema>;
const labelColors = (calendar: CalendarLabels) =>
  new Map(
    (calendar.labelProperties?.eventLabels ?? []).map(
      (label) => [label.id, label.backgroundColor.toLowerCase()] as const,
    ),
  );
function usesTasks(tokens: StoredTokens | null) {
  return Boolean(tokens?.tasks && tokens.scope.split(/\s+/).includes(GOOGLE_TASKS_SCOPE));
}
const taskIdSchema = z
  .string()
  .min(1)
  .max(1024)
  .regex(/^[a-zA-Z0-9_-]+$/);
const nativeTaskSchema = z
  .object({
    id: taskIdSchema,
    etag: googleEtagSchema,
    title: z.string().max(1024),
    due: z.iso.datetime({ offset: true }).optional(),
    webViewLink: z.string().max(2048).optional(),
    status: z.enum(['needsAction', 'completed']),
    completed: z.iso.datetime({ offset: true }).optional(),
    deleted: z.boolean().optional(),
  })
  .passthrough();
export function normalizeGoogleTaskLink(value: string): string | null {
  try {
    const url = new URL(value);
    if (
      url.protocol !== 'https:' ||
      url.hostname !== 'tasks.google.com' ||
      url.port ||
      url.username ||
      url.password ||
      url.search ||
      url.hash ||
      !/^\/task\/[a-zA-Z0-9_-]+\/?$/.test(url.pathname)
    )
      return null;
    return 'https://tasks.google.com' + url.pathname.replace(/\/$/, '');
  } catch {
    return null;
  }
}
function taskLinkFromDescription(description: string): string | null {
  const links = new Set(
    (description.match(/https:\/\/[^\s<>"']+/g) ?? [])
      .map((value) => normalizeGoogleTaskLink(value.replace(/[.,;:!?)]*$/, '')))
      .filter((value): value is string => Boolean(value)),
  );
  return links.size === 1 ? [...links][0] : null;
}
function taskMatchesMirror(task: z.infer<typeof nativeTaskSchema>, event: GoogleCalendarEvent) {
  const date = event.allDay
    ? event.start.date
    : localParts(Date.parse(event.start.dateTime!), event.timeZone).date;
  return task.title.trim() === event.title && Boolean(task.due) && task.due!.slice(0, 10) === date;
}
function usesExtendedColors(tokens: StoredTokens | null) {
  return Boolean(
    tokens?.extendedColors &&
    tokens.scope
      .split(/\s+/)
      .some((scope) =>
        [GOOGLE_CALENDAR_LABELS_SCOPE, 'https://www.googleapis.com/auth/calendar'].includes(scope),
      ),
  );
}
const colorValue = (hex: string) =>
  CALENDAR_PALETTE.find((color) => !color.id.startsWith('#') && color.hex === hex)?.id ?? hex;
function stableLabelId(hex: string) {
  const bytes = createHash('sha256')
    .update('Ritm:calendar-label:' + hex)
    .digest()
    .subarray(0, 16);
  bytes[6] = (bytes[6] & 15) | 80;
  bytes[8] = (bytes[8] & 63) | 128;
  const value = bytes.toString('hex');
  return `${value.slice(0, 8)}-${value.slice(8, 12)}-${value.slice(12, 16)}-${value.slice(16, 20)}-${value.slice(20)}`;
}

export function mapGoogleEvent(
  value: unknown,
  timeZone: string,
  accessRole = 'owner',
  labels: ReadonlyMap<string, string> = new Map(),
): GoogleCalendarEvent | null {
  if (value && typeof value === 'object' && (value as { status?: unknown }).status === 'cancelled')
    return null;
  const parsed = eventSchema.safeParse(value);
  if (!parsed.success)
    throw new AppError(
      502,
      'GOOGLE_INVALID_EVENT',
      'Google вернул неполное событие. Обновите календарь позднее.',
    );
  const event = parsed.data,
    allDay = Boolean(
      event.start.date && event.end.date && !event.start.dateTime && !event.end.dateTime,
    );
  let representable: boolean;
  if (allDay) {
    if (event.end.date! <= event.start.date!)
      throw new AppError(502, 'GOOGLE_INVALID_EVENT', 'Google вернул некорректные даты события.');
    representable = event.end.date === dateShift(event.start.date!, 1);
  } else {
    if (!event.start.dateTime || !event.end.dateTime || event.start.date || event.end.date)
      throw new AppError(502, 'GOOGLE_INVALID_EVENT', 'Google вернул некорректное время события.');
    const start = Date.parse(event.start.dateTime),
      end = Date.parse(event.end.dateTime),
      duration = (end - start) / 60_000;
    if (duration <= 0)
      throw new AppError(
        502,
        'GOOGLE_INVALID_EVENT',
        'Google вернул некорректную длительность события.',
      );
    const localStart = localParts(start, timeZone),
      localEnd = localParts(end, timeZone);
    representable =
      duration >= 5 &&
      duration <= 720 &&
      Number.isInteger(duration) &&
      localStart.time.endsWith(':00') &&
      localEnd.time.endsWith(':00') &&
      (localStart.date === localEnd.date ||
        (localEnd.date === dateShift(localStart.date, 1) && localEnd.time === '00:00:00'));
    if (representable) {
      const wallDuration =
        (Date.parse(`${localEnd.date}T${localEnd.time}Z`) -
          Date.parse(`${localStart.date}T${localStart.time}Z`)) /
        60_000;
      try {
        representable =
          wallDuration === duration &&
          start % 60_000 === 0 &&
          end % 60_000 === 0 &&
          googleZonedInstant(localStart.date, localStart.time.slice(0, 5), timeZone) === start &&
          googleZonedInstant(localEnd.date, localEnd.time.slice(0, 5), timeZone) === end;
      } catch (error) {
        if (!(error instanceof AppError)) throw error;
        representable = false;
      }
    }
  }
  const title = event.summary?.trim() || 'Событие без названия',
    description = event.description ?? '';
  const readOnlyReason = !['writer', 'owner'].includes(accessRole)
    ? 'В этом календаре доступно только чтение. Измените событие в Google Calendar.'
    : event.locked
      ? 'Google заблокировал изменение этой записи. Откройте её в Google Calendar.'
      : !representable
        ? 'Событие занимает несколько дней, имеет сложное время или связано с переводом часов. Измените его в Google Calendar.'
        : event.eventType !== undefined && event.eventType !== 'default'
          ? 'Это специальное событие Google. Измените его в Google Calendar.'
          : event.organizer?.self === false ||
              event.attendees?.some((attendee) => attendee.self !== true)
            ? 'У встречи есть другие участники или организатор. Измените её в Google Calendar.'
            : event.recurrence !== undefined
              ? 'Это вся повторяющаяся серия. В Ritm можно изменить отдельную запись, а серию — в Google Calendar.'
              : title.length > 160 || description.length > 4000
                ? 'У события длинное название или описание. Измените его в Google Calendar.'
                : !googleEtagSchema.safeParse(event.etag).success
                  ? 'Не удалось определить версию события. Обновите календарь перед изменением.'
                  : undefined;
  const nativeColor = event.eventLabelId ? labels.get(event.eventLabelId) : undefined;
  const selectedColor = nativeColor ? colorValue(nativeColor) : event.colorId;
  return {
    id: event.id,
    source: 'google',
    calendarId: 'primary',
    title: title.slice(0, 160),
    description: description.slice(0, 4000),
    etag: event.etag,
    start: allDay ? { date: event.start.date! } : { dateTime: event.start.dateTime! },
    end: allDay ? { date: event.end.date! } : { dateTime: event.end.dateTime! },
    timeZone,
    allDay,
    busy: event.transparency !== 'transparent',
    readOnly: Boolean(readOnlyReason),
    recurring: Boolean(event.recurringEventId || event.recurrence !== undefined),
    ...(selectedColor ? { colorId: selectedColor } : {}),
    ...(readOnlyReason ? { readOnlyReason } : {}),
    ...(isLinkedTaskMirrorCandidate(event) ? { taskLink: true } : {}),
  };
}

function inRange(event: GoogleCalendarEvent, from: string, to: string, timeZone: string) {
  if (event.allDay) return event.end.date! > from && event.start.date! < to;
  const start = localParts(Date.parse(event.start.dateTime!), timeZone),
    end = localParts(Date.parse(event.end.dateTime!), timeZone);
  return (
    `${start.date}T${start.time}` < `${to}T00:00:00` &&
    `${end.date}T${end.time}` > `${from}T00:00:00`
  );
}

export class GoogleCalendarService {
  private transport: GoogleTransport;
  private now: () => number;
  constructor(private options: GoogleCalendarOptions) {
    callbackUriFrom(options.env ?? process.env);
    this.transport = options.transport ?? defaultGoogleTransport;
    this.now = options.now ?? Date.now;
  }
  private environmentManaged() {
    const env = this.options.env ?? process.env;
    return env.GOOGLE_CLIENT_ID !== undefined || env.GOOGLE_CLIENT_SECRET !== undefined;
  }
  private async savedConfiguration() {
    const value = await this.options.secrets.getSecret(CONFIGURATION_SLOT);
    if (!value) return null;
    try {
      return savedConfigurationSchema.parse(JSON.parse(value));
    } catch {
      throw new AppError(
        500,
        'GOOGLE_STORE_ERROR',
        'Не удалось прочитать настройку Google. Сохраните её заново.',
      );
    }
  }
  private async resolvedConfiguration() {
    const env = this.options.env ?? process.env,
      managed = this.environmentManaged(),
      redirectUri = callbackUriFrom(env),
      credentials = managed
        ? {
            clientId: env.GOOGLE_CLIENT_ID?.trim() || '',
            clientSecret: env.GOOGLE_CLIENT_SECRET?.trim() || '',
          }
        : await this.savedConfiguration(),
      parsed = savedConfigurationSchema.safeParse(credentials),
      config: GoogleOAuthConfig | null =
        parsed.success && redirectUri ? { ...parsed.data, redirectUri } : null;
    const setup: GoogleOAuthSetup = {
      configured: Boolean(config),
      source: managed ? 'environment' : credentials ? 'saved' : 'none',
      clientId: credentials?.clientId || '',
      hasClientSecret: Boolean(credentials?.clientSecret),
      redirectUri,
    };
    return { config, setup };
  }
  async configuration(): Promise<GoogleOAuthSetup> {
    return (await this.resolvedConfiguration()).setup;
  }
  private async oauthConfiguration() {
    const { config } = await this.resolvedConfiguration();
    if (!config)
      throw new AppError(
        503,
        'GOOGLE_NOT_CONFIGURED',
        'Настройте OAuth Google Calendar в разделе «Подключения».',
      );
    return config;
  }
  private fingerprint(config: GoogleOAuthConfig) {
    return hash(JSON.stringify(config));
  }
  private async invalidateConnection(assertActive: () => void) {
    // Rotate first: even an interrupted write cannot revive an old OAuth flow.
    assertActive();
    await this.options.secrets.saveSecret(EPOCH_SLOT, randomUUID());
    assertActive();
    await this.options.secrets.removeSecret(TOKEN_SLOT);
  }
  private assertEditable() {
    if (this.environmentManaged())
      throw new AppError(
        409,
        'GOOGLE_ENVIRONMENT_CONFIGURATION',
        'OAuth Google задан переменными сервера. Измените их, чтобы настроить подключение.',
      );
  }
  async saveConfiguration(value: GoogleOAuthSetupInput): Promise<GoogleOAuthSetup> {
    const parsed = googleOAuthSetupInputSchema.safeParse(value);
    if (!parsed.success)
      throw new AppError(
        400,
        'GOOGLE_SETUP_INVALID',
        'Проверьте Client ID Google и Client Secret без пробелов.',
      );
    return this.withLease(async (assertActive) => {
      this.assertEditable();
      if (!callbackUriFrom(this.options.env ?? process.env))
        throw new AppError(
          503,
          'GOOGLE_ORIGIN_REQUIRED',
          'Для Google OAuth настройте на сервере APP_ORIGIN — адрес приложения.',
        );
      const previous = await this.savedConfiguration(),
        clientId = parsed.data.clientId,
        clientSecret =
          parsed.data.clientSecret ||
          (previous?.clientId === clientId ? previous.clientSecret : undefined);
      if (!clientSecret)
        throw new AppError(
          400,
          'GOOGLE_CLIENT_SECRET_REQUIRED',
          'Введите Client Secret для нового Client ID Google.',
        );
      if (previous?.clientId !== clientId || previous.clientSecret !== clientSecret) {
        await this.invalidateConnection(assertActive);
        assertActive();
        await this.options.secrets.saveSecret(
          CONFIGURATION_SLOT,
          JSON.stringify({ clientId, clientSecret }),
        );
      }
      return this.configuration();
    });
  }
  async removeConfiguration(): Promise<GoogleOAuthSetup> {
    return this.withLease(async (assertActive) => {
      this.assertEditable();
      await this.invalidateConnection(assertActive);
      assertActive();
      await this.options.secrets.removeSecret(CONFIGURATION_SLOT);
      return this.configuration();
    });
  }
  private async assertConfiguration(config: GoogleOAuthConfig, epoch: string) {
    const current = (await this.resolvedConfiguration()).config;
    if (
      !current ||
      this.fingerprint(current) !== this.fingerprint(config) ||
      (await this.options.secrets.getSecret(EPOCH_SLOT)) !== epoch
    )
      throw conflict('Настройка Google изменилась. Начните подключение заново.');
  }
  private async assertConnection(connection: GoogleConnection) {
    await this.assertConfiguration(connection.config, connection.epoch);
    const current = await this.readTokens();
    if (
      !current ||
      current.connectionId !== connection.tokens.connectionId ||
      current.configFingerprint !== this.fingerprint(connection.config) ||
      current.epoch !== connection.epoch ||
      current.needsReauth
    )
      throw conflict('Подключение Google изменилось. Обновите страницу.');
    return current;
  }
  private identity(connection: GoogleConnection) {
    return hash(
      connection.tokens.connectionId +
        '\0' +
        connection.epoch +
        '\0' +
        connection.tokens.configFingerprint,
    );
  }
  private async identitySnapshot(): Promise<GoogleConnection> {
    const config = await this.oauthConfiguration(),
      tokens = await this.readTokens(),
      epoch = await this.options.secrets.getSecret(EPOCH_SLOT);
    if (!tokens)
      throw new AppError(503, 'GOOGLE_NOT_CONNECTED', 'Подключите Google Calendar в настройках.');
    if (
      !epoch ||
      tokens.needsReauth ||
      tokens.epoch !== epoch ||
      tokens.configFingerprint !== this.fingerprint(config)
    )
      throw new AppError(
        401,
        'GOOGLE_REAUTH_REQUIRED',
        'Подключите Google Calendar заново в настройках.',
      );
    return { config, tokens, epoch };
  }
  async connectionIdentity(): Promise<string> {
    return this.withLease(async () => this.identity(await this.identitySnapshot()));
  }
  async withConnectionIdentity<T>(
    identity: string,
    operation: (assertActive: () => void) => Promise<T>,
  ): Promise<T> {
    return this.withLease(async (assertActive) => {
      if (this.identity(await this.identitySnapshot()) !== identity)
        throw new AppError(
          409,
          'GOOGLE_TRANSFER_CONNECTION_CHANGED',
          'Подключение Google изменилось во время переноса. Запись Ritm сохранена; проверьте событие в прежнем аккаунте.',
        );
      assertActive();
      return operation(assertActive);
    });
  }
  private async readTokens() {
    const value = await this.options.secrets.getSecret(TOKEN_SLOT);
    if (!value) return null;
    try {
      return tokensSchema.parse(JSON.parse(value));
    } catch {
      throw new AppError(
        500,
        'GOOGLE_STORE_ERROR',
        'Не удалось прочитать подключение Google. Настройте его заново.',
      );
    }
  }
  private async withLease<T>(operation: (assertActive: () => void) => Promise<T>): Promise<T> {
    const clock = this.options.leaseClock ?? (() => performance.now()),
      // Leave 135 seconds before expiry: enough for the bounded PostgreSQL
      // secret transaction (connection <=10s and seven queries <=16s each).
      deadline = clock() + 45_000;
    const assertActive = () => {
      if (clock() >= deadline)
        throw new AppError(
          503,
          'GOOGLE_OPERATION_TIMEOUT',
          'Обновление Google заняло слишком долго. Повторите из настроек.',
        );
    };
    let token: string | null = null;
    for (let attempt = 0; attempt < 21 && !token; attempt++) {
      assertActive();
      token = await this.options.secrets.acquireLease(CONNECTION_LEASE, 180_000);
      if (!token && attempt < 20) await sleep(50);
    }
    if (!token)
      throw conflict('Подключение Google уже обновляется. Подождите немного и повторите.');
    try {
      assertActive();
      const result = await operation(assertActive);
      assertActive();
      return result;
    } finally {
      await this.options.secrets.releaseLease(CONNECTION_LEASE, token);
    }
  }
  async status(): Promise<GoogleCalendarStatus> {
    const { config } = await this.resolvedConfiguration(),
      tokens = config ? await this.readTokens() : null,
      epoch = tokens ? await this.options.secrets.getSecret(EPOCH_SLOT) : null;
    return {
      configured: Boolean(config),
      status: !config
        ? 'unconfigured'
        : !tokens
          ? 'disconnected'
          : tokens.needsReauth ||
              tokens.configFingerprint !== this.fingerprint(config) ||
              tokens.epoch !== epoch
            ? 'reauth_required'
            : 'connected',
      mode: 'readwrite',
      calendarId: 'primary',
      lastFetchedAt: tokens?.lastFetchedAt ?? null,
      tasksEnabled:
        usesTasks(tokens) &&
        Boolean(config) &&
        tokens?.configFingerprint === this.fingerprint(config!) &&
        tokens?.epoch === epoch &&
        !tokens?.needsReauth,
      extendedColors:
        usesExtendedColors(tokens) &&
        Boolean(config) &&
        tokens?.configFingerprint === this.fingerprint(config!) &&
        tokens?.epoch === epoch &&
        !tokens?.needsReauth,
    };
  }
  async connect(
    ownerSessionHash: string,
    options: { extendedColors?: boolean; tasks?: boolean } = {},
  ) {
    if (
      !ownerHashPattern.test(ownerSessionHash) ||
      !(await this.options.security.hasOwnerSession(ownerSessionHash))
    )
      throw new AppError(401, 'AUTH_REQUIRED', 'Войдите в Ritm перед подключением Google.');
    return this.withLease(async (assertActive) => {
      const config = await this.oauthConfiguration(),
        previousTokens = await this.readTokens(),
        extendedColors = options.extendedColors === true || usesExtendedColors(previousTokens),
        tasks = options.tasks === true || usesTasks(previousTokens),
        client = oauthClient(config),
        verifier = await client.generateCodeVerifierAsync();
      if (!(await this.options.security.hasOwnerSession(ownerSessionHash)))
        throw new AppError(401, 'AUTH_REQUIRED', 'Войдите в Ritm перед подключением Google.');
      const state = randomBytes(32).toString('hex'),
        correlationCookie = randomBytes(32).toString('base64url'),
        stateHash = hash(state),
        ownerSlot = `google.oauth.owner.${ownerSessionHash}`,
        expiresAt = this.now() + FLOW_TTL_MS;
      const previous = await this.options.secrets.getSecret(ownerSlot);
      if (previous && /^[a-f0-9]{64}$/.test(previous)) {
        assertActive();
        await this.options.secrets.removeSecret(`google.oauth.flow.${previous}`);
      }
      let epoch = await this.options.secrets.getSecret(EPOCH_SLOT);
      if (!epoch) {
        epoch = randomUUID();
        assertActive();
        await this.options.secrets.saveSecret(EPOCH_SLOT, epoch);
      }
      assertActive();
      await this.options.secrets.saveSecret(
        `google.oauth.flow.${stateHash}`,
        JSON.stringify({
          ownerSessionHash,
          correlationHash: hash(correlationCookie),
          codeVerifier: verifier.codeVerifier,
          expiresAt,
          configFingerprint: this.fingerprint(config),
          epoch,
          extendedColors,
          tasks,
        }),
      );
      assertActive();
      await this.options.secrets.saveSecret(ownerSlot, stateHash);
      await this.assertConfiguration(config, epoch);
      const authorizationUrl = client.generateAuthUrl({
        scope: [
          GOOGLE_CALENDAR_SCOPE,
          ...(extendedColors ? [GOOGLE_CALENDAR_LABELS_SCOPE] : []),
          ...(tasks ? [GOOGLE_TASKS_SCOPE] : []),
        ],
        state,
        access_type: 'offline',
        prompt: 'consent',
        include_granted_scopes: false,
        code_challenge_method: CodeChallengeMethod.S256,
        code_challenge: verifier.codeChallenge,
      });
      return {
        authorizationUrl,
        correlationCookie,
        expiresAt,
        secureCookie: config.redirectUri.startsWith('https://'),
      };
    });
  }
  async callback(input: {
    state: string;
    code?: string;
    error?: string;
    correlationCookie?: string;
  }) {
    if (
      !/^[a-f0-9]{64}$/.test(input.state) ||
      !input.correlationCookie ||
      !/^[a-zA-Z0-9_-]{43}$/.test(input.correlationCookie)
    )
      throw new AppError(
        400,
        'GOOGLE_INVALID_STATE',
        'Подключение Google не подтверждено. Начните заново из настроек.',
      );
    const slot = `google.oauth.flow.${hash(input.state)}`,
      value = await this.options.secrets.getSecret(slot);
    let flow: z.infer<typeof flowSchema>;
    try {
      flow = flowSchema.parse(JSON.parse(value ?? 'null'));
    } catch {
      throw new AppError(
        400,
        'GOOGLE_INVALID_STATE',
        'Подключение Google устарело или уже использовано. Начните заново.',
      );
    }
    const validCookie = timingSafeEqual(
      Buffer.from(flow.correlationHash, 'hex'),
      Buffer.from(hash(input.correlationCookie), 'hex'),
    );
    if (
      !validCookie ||
      flow.expiresAt <= this.now() ||
      !(await this.options.security.hasOwnerSession(flow.ownerSessionHash))
    )
      throw new AppError(
        400,
        'GOOGLE_INVALID_STATE',
        'Подключение Google устарело. Войдите в Ritm и повторите.',
      );
    const consumed = await this.options.secrets.consumeSecret(slot);
    if (consumed !== value)
      throw new AppError(400, 'GOOGLE_INVALID_STATE', 'Это подключение Google уже обработано.');
    await this.withLease(async (assertActive) => {
      const config = (await this.resolvedConfiguration()).config;
      if (!config || flow.configFingerprint !== this.fingerprint(config))
        throw conflict('Настройка Google изменилась. Начните подключение заново.');
      if ((await this.options.secrets.getSecret(EPOCH_SLOT)) !== flow.epoch)
        throw conflict('Подключение было отменено. Начните подключение Google заново.');
      if (!(await this.options.security.hasOwnerSession(flow.ownerSessionHash)))
        throw new AppError(
          401,
          'AUTH_REQUIRED',
          'Сессия Ritm завершилась. Войдите и подключите Google заново.',
        );
      const ownerSlot = `google.oauth.owner.${flow.ownerSessionHash}`;
      if ((await this.options.secrets.getSecret(ownerSlot)) !== hash(input.state))
        throw conflict(
          'Начато новое подключение Google. Используйте последний запрос из настроек.',
        );
      assertActive();
      await this.options.secrets.removeSecret(ownerSlot);
      if (input.error)
        throw new AppError(
          400,
          'GOOGLE_CONSENT_DENIED',
          'Доступ Google не предоставлен. Ваши задачи Ritm сохранены.',
        );
      if (!input.code || input.code.length > 2048)
        throw new AppError(
          400,
          'GOOGLE_INVALID_CODE',
          'Google не передал код подключения. Повторите из настроек.',
        );
      let credentials: Credentials;
      await this.assertConfiguration(config, flow.epoch);
      assertActive();
      try {
        credentials = await this.transport.exchangeCode(config, input.code!, flow.codeVerifier);
      } catch (error) {
        throw safeProviderError(error);
      }
      const scope = credentials.scope ?? '';
      if (
        !scope
          .split(/\s+/)
          .some((scope) =>
            [GOOGLE_CALENDAR_SCOPE, 'https://www.googleapis.com/auth/calendar'].includes(scope),
          )
      )
        throw new AppError(
          403,
          'GOOGLE_SCOPE_REQUIRED',
          'Для сохранения событий разрешите доступ к событиям Google Calendar.',
        );
      if (!credentials.access_token || !credentials.refresh_token || !credentials.expiry_date)
        throw new AppError(
          502,
          'GOOGLE_OFFLINE_REQUIRED',
          'Google не предоставил постоянный доступ. Подключите календарь заново с подтверждением разрешения.',
        );
      if (
        flow.extendedColors &&
        !scope
          .split(/\s+/)
          .some((scope) =>
            [GOOGLE_CALENDAR_LABELS_SCOPE, 'https://www.googleapis.com/auth/calendar'].includes(
              scope,
            ),
          )
      )
        throw new AppError(
          403,
          'GOOGLE_LABEL_SCOPE_REQUIRED',
          'Для всей палитры разрешите изменение свойств календаря Google. Прежнее подключение сохранено.',
        );
      if (flow.tasks && !scope.split(/\s+/).includes(GOOGLE_TASKS_SCOPE))
        throw new AppError(
          403,
          'GOOGLE_TASKS_SCOPE_REQUIRED',
          'Разрешите доступ к Google Tasks. Прежнее подключение календаря сохранено.',
        );
      const tokens: StoredTokens = {
        accessToken: credentials.access_token,
        refreshToken: credentials.refresh_token,
        expiresAt: credentials.expiry_date,
        scope,
        needsReauth: false,
        configFingerprint: this.fingerprint(config),
        connectionId: randomUUID(),
        epoch: flow.epoch,
        lastFetchedAt: null,
        extendedColors: flow.extendedColors === true,
        tasks: flow.tasks === true,
      };
      if (!(await this.options.security.hasOwnerSession(flow.ownerSessionHash)))
        throw new AppError(
          401,
          'AUTH_REQUIRED',
          'Сессия Ritm завершилась. Войдите и подключите Google заново.',
        );
      await this.assertConfiguration(config, flow.epoch);
      assertActive();
      await this.options.secrets.saveSecret(TOKEN_SLOT, JSON.stringify(tokens));
    });
    return this.status();
  }
  private async token(): Promise<GoogleConnection> {
    return this.withLease(async (assertActive) => {
      const config = await this.oauthConfiguration(),
        latest = await this.readTokens(),
        epoch = await this.options.secrets.getSecret(EPOCH_SLOT);
      if (!latest)
        throw new AppError(503, 'GOOGLE_NOT_CONNECTED', 'Подключите Google Calendar в настройках.');
      if (
        latest.needsReauth ||
        latest.configFingerprint !== this.fingerprint(config) ||
        latest.epoch !== epoch ||
        !epoch ||
        !z.string().uuid().safeParse(epoch).success
      )
        throw new AppError(
          401,
          'GOOGLE_REAUTH_REQUIRED',
          'Подключите Google Calendar заново в настройках.',
        );
      const connection: GoogleConnection = { tokens: latest, config, epoch };
      if (latest.accessToken && latest.expiresAt > this.now() + 60_000) return connection;
      await this.assertConnection(connection);
      assertActive();
      try {
        const response = await this.transport.refreshToken(config, latest.refreshToken);
        if (!response.access_token || !response.expiry_date)
          throw new Error('Incomplete token response');
        const updated: StoredTokens = {
          ...latest,
          accessToken: response.access_token,
          refreshToken: response.refresh_token || latest.refreshToken,
          expiresAt: response.expiry_date,
          scope: response.scope || latest.scope,
        };
        if (
          !updated.scope
            .split(/\s+/)
            .some((scope) =>
              [GOOGLE_CALENDAR_SCOPE, 'https://www.googleapis.com/auth/calendar'].includes(scope),
            )
        )
          throw new AppError(
            401,
            'GOOGLE_REAUTH_REQUIRED',
            'Подключите Google Calendar заново с разрешением изменения событий.',
          );
        await this.assertConnection(connection);
        assertActive();
        await this.options.secrets.saveSecret(TOKEN_SLOT, JSON.stringify(updated));
        return { ...connection, tokens: updated };
      } catch (error) {
        if (
          invalidGrant(error) ||
          providerStatus(error) === 401 ||
          (error instanceof AppError && error.code === 'GOOGLE_REAUTH_REQUIRED')
        ) {
          await this.assertConnection(connection);
          assertActive();
          await this.options.secrets.saveSecret(
            TOKEN_SLOT,
            JSON.stringify({ ...latest, needsReauth: true, accessToken: '' }),
          );
        }
        throw error instanceof AppError ? error : safeProviderError(error);
      }
    });
  }
  private async api(connection: GoogleConnection, request: GoogleRequest) {
    return this.withLease(async (assertActive) => {
      await this.assertConnection(connection);
      assertActive();
      try {
        const result = request.signal
          ? await withAbort(
              () =>
                this.transport.request(connection.config, connection.tokens.accessToken, request),
              request.signal,
            )
          : await this.transport.request(connection.config, connection.tokens.accessToken, request);
        await this.assertConnection(connection);
        assertActive();
        return result;
      } catch (error) {
        if (providerStatus(error) === 401 || invalidGrant(error)) {
          const latest = await this.assertConnection(connection);
          assertActive();
          await this.options.secrets.saveSecret(
            TOKEN_SLOT,
            JSON.stringify({ ...latest, needsReauth: true, accessToken: '' }),
          );
        }
        if (
          providerStatus(error) === 403 &&
          ['tasks', 'tasklists'].includes(request.resource ?? '')
        )
          throw new AppError(
            403,
            'GOOGLE_TASKS_FORBIDDEN',
            'Google не разрешил доступ к задачам. Включите Google Tasks API в проекте Google Cloud и проверьте разрешение Google Tasks.',
          );
        throw error instanceof AppError ? error : safeProviderError(error);
      }
    });
  }
  private async taskCatalog(connection: GoogleConnection, signal: AbortSignal) {
    const lists: string[] = [],
      entries = new Map<string, Array<{ list: string; task: z.infer<typeof nativeTaskSchema> }>>();
    let requests = 0,
      records = 0;
    const pages = async (request: GoogleRequest, item: z.ZodType) => {
      const result: unknown[] = [],
        seenTokens = new Set<string>();
      let pageToken: string | undefined;
      do {
        signal.throwIfAborted();
        if (++requests > 30)
          throw new AppError(
            502,
            'GOOGLE_TASKS_PARTIAL',
            'Слишком много списков Google Tasks. Не все статусы удалось проверить.',
          );
        const data = await this.api(connection, {
          ...request,
          signal,
          query: { ...request.query, ...(pageToken ? { pageToken } : {}) },
        });
        const parsed = z
          .object({
            items: z.array(item).max(1000).optional(),
            nextPageToken: z.string().min(1).max(4096).optional(),
          })
          .safeParse(data);
        if (!parsed.success)
          throw new AppError(
            502,
            'GOOGLE_TASKS_INVALID_RESPONSE',
            'Google Tasks вернул неполные данные. Повторите обновление.',
          );
        result.push(...(parsed.data.items ?? []));
        records += parsed.data.items?.length ?? 0;
        if (records > 2100)
          throw new AppError(
            502,
            'GOOGLE_TASKS_PARTIAL',
            'Слишком много задач Google. Не все статусы удалось проверить.',
          );
        pageToken = parsed.data.nextPageToken;
        if (pageToken && seenTokens.has(pageToken))
          throw new AppError(
            502,
            'GOOGLE_TASKS_PARTIAL',
            'Google Tasks не завершил загрузку. Повторите обновление.',
          );
        if (pageToken) seenTokens.add(pageToken);
      } while (pageToken);
      return result;
    };
    const listData = await pages(
      {
        resource: 'tasklists',
        method: 'GET',
        query: { maxResults: 100, fields: 'items(id),nextPageToken' },
      },
      z.object({ id: taskIdSchema }),
    );
    for (const value of listData) {
      const id = (value as { id: string }).id;
      if (!lists.includes(id)) lists.push(id);
      if (lists.length > 100)
        throw new AppError(
          502,
          'GOOGLE_TASKS_PARTIAL',
          'Слишком много списков Google Tasks. Не все статусы удалось проверить.',
        );
    }
    const seenTasks = new Set<string>();
    for (const list of lists) {
      const items = await pages(
        {
          resource: 'tasks',
          taskListId: list,
          method: 'GET',
          query: {
            maxResults: 100,
            showCompleted: true,
            showHidden: true,
            showDeleted: false,
            showAssigned: true,
            fields: 'items(id,etag,title,due,webViewLink,status,completed,deleted),nextPageToken',
          },
        },
        nativeTaskSchema,
      );
      for (const item of items) {
        const task = item as z.infer<typeof nativeTaskSchema>,
          key = list + '\0' + task.id;
        if (task.deleted || seenTasks.has(key)) continue;
        seenTasks.add(key);
        const link = task.webViewLink && normalizeGoogleTaskLink(task.webViewLink);
        if (link) entries.set(link, [...(entries.get(link) ?? []), { list, task }]);
      }
    }
    return entries;
  }
  private taskInfo(
    connection: GoogleConnection,
    list: string,
    task: z.infer<typeof nativeTaskSchema>,
  ): GoogleTaskCompletion {
    return {
      taskListId: list,
      id: task.id,
      etag: task.etag,
      status: task.status,
      ...(task.completed ? { completed: task.completed } : {}),
      connectionId: this.identity(connection),
    };
  }
  private async enrichTasks(
    events: GoogleCalendarEvent[],
    connection: GoogleConnection,
    signal: AbortSignal,
  ): Promise<GoogleTasksStatus> {
    const candidates = events.filter((event) => event.taskLink);
    if (!usesTasks(connection.tokens)) {
      for (const event of candidates)
        event.taskUnavailableReason =
          'Разрешите Google Tasks в настройках, чтобы отмечать выполнение здесь.';
      return { status: 'permission_required' };
    }
    if (!candidates.length) return { status: 'enabled' };
    try {
      const catalog = await this.taskCatalog(
        connection,
        AbortSignal.any([signal, AbortSignal.timeout(12_000)]),
      );
      const mirrorCounts = new Map<string, number>();
      for (const event of candidates) {
        const link = taskLinkFromDescription(event.description);
        if (link) mirrorCounts.set(link, (mirrorCounts.get(link) ?? 0) + 1);
      }
      for (const event of candidates) {
        const link = taskLinkFromDescription(event.description),
          matches = link && mirrorCounts.get(link) === 1 ? catalog.get(link) : undefined;
        if (matches?.length === 1 && taskMatchesMirror(matches[0].task, event))
          event.googleTask = this.taskInfo(connection, matches[0].list, matches[0].task);
        else
          event.taskUnavailableReason = matches?.length
            ? 'Не удалось однозначно определить задачу Google. Откройте её в Google Tasks.'
            : 'Задача не найдена в Google Tasks. Обновите календарь или откройте её в Google.';
      }
      return { status: 'enabled' };
    } catch (error) {
      if (error instanceof AppError && ['CONFLICT', 'GOOGLE_REAUTH_REQUIRED'].includes(error.code))
        throw error;
      const message =
        error instanceof AppError &&
        ['GOOGLE_FORBIDDEN', 'GOOGLE_TASKS_FORBIDDEN'].includes(error.code)
          ? 'Включите Google Tasks API в проекте Google Cloud и проверьте разрешение Google Tasks.'
          : 'Не удалось загрузить статусы Google Tasks. Календарь доступен; повторите обновление.';
      for (const event of candidates) event.taskUnavailableReason = message;
      return {
        status:
          error instanceof AppError && error.code === 'GOOGLE_TASKS_PARTIAL'
            ? 'partial'
            : 'unavailable',
        message,
      };
    }
  }
  private async assertSingleTaskMirror(
    connection: GoogleConnection,
    eventId: string,
    link: string,
    signal: AbortSignal,
  ) {
    const ids = new Set<string>(),
      seenTokens = new Set<string>();
    let pageToken: string | undefined;
    for (let page = 0; page < 5; page++) {
      const data = await this.api(connection, {
        method: 'GET',
        signal,
        query: {
          singleEvents: false,
          showDeleted: false,
          eventTypes: 'focusTime',
          maxResults: 250,
          fields: 'items(id,description,eventType,recurrence,recurringEventId),nextPageToken',
          ...(pageToken ? { pageToken } : {}),
        },
      });
      const parsed = z
        .object({
          items: z
            .array(
              z.object({
                id: googleEventIdSchema,
                description: z.string().optional(),
                eventType: z.string().optional(),
                recurrence: z.array(z.string()).optional(),
                recurringEventId: z.string().optional(),
              }),
            )
            .max(250)
            .optional(),
          nextPageToken: z.string().min(1).max(4096).optional(),
        })
        .safeParse(data);
      if (!parsed.success)
        throw new AppError(
          502,
          'GOOGLE_TASKS_INVALID_RESPONSE',
          'Не удалось проверить связь задачи с календарём Google.',
        );
      for (const event of parsed.data.items ?? []) {
        if (
          event.eventType !== 'focusTime' ||
          taskLinkFromDescription(event.description ?? '') !== link
        )
          continue;
        if (event.recurrence !== undefined || event.recurringEventId)
          throw new AppError(
            409,
            'GOOGLE_TASK_NOT_LINKED',
            'Повторяющаяся задача изменяется в Google Tasks.',
          );
        ids.add(event.id);
        if (ids.size > 1)
          throw new AppError(
            409,
            'GOOGLE_TASK_NOT_LINKED',
            'У задачи несколько записей в календаре. Измените выполнение в Google Tasks.',
          );
      }
      pageToken = parsed.data.nextPageToken;
      if (!pageToken) {
        if (ids.size !== 1 || !ids.has(eventId))
          throw new AppError(
            409,
            'GOOGLE_TASK_NOT_LINKED',
            'Не удалось однозначно проверить запись задачи Google. Обновите календарь.',
          );
        return;
      }
      if (seenTokens.has(pageToken)) break;
      seenTokens.add(pageToken);
    }
    throw new AppError(
      409,
      'GOOGLE_TASK_NOT_LINKED',
      'Связь задачи Google не удалось проверить полностью. Откройте её в Google Tasks.',
    );
  }
  async completeTask(
    id: string,
    input: { etag: string; taskEtag: string; completed: boolean; connectionId: string },
  ): Promise<{ event: GoogleCalendarEvent }> {
    const eventId = googleEventIdSchema.parse(id),
      version = googleEtagSchema.parse(input.etag),
      taskVersion = googleEtagSchema.parse(input.taskEtag),
      connection = await this.token();
    if (this.identity(connection) !== input.connectionId)
      throw conflict(
        'Подключение Google изменилось. Обновите календарь перед отметкой выполнения.',
      );
    if (!usesTasks(connection.tokens))
      throw new AppError(
        403,
        'GOOGLE_TASKS_SCOPE_REQUIRED',
        'Разрешите Google Tasks в настройках перед отметкой выполнения.',
      );
    const settings = await this.options.settings(),
      signal = AbortSignal.timeout(20_000);
    const readEvent = async () => {
      const data = await this.api(connection, { method: 'GET', eventId, signal });
      const raw = eventSchema.safeParse(data);
      if (!raw.success || !isLinkedTaskMirrorCandidate(raw.data))
        throw new AppError(
          403,
          'GOOGLE_TASK_NOT_LINKED',
          'Эта запись не является поддерживаемой личной задачей Google. Откройте её в Google.',
        );
      const event = await this.mapReturnedEvent(data, connection, settings.timeZone);
      if (!event || event.id !== eventId)
        throw new AppError(
          404,
          'GOOGLE_EVENT_NOT_FOUND',
          'Запись Google больше недоступна. Обновите календарь.',
        );
      if (event.etag !== version)
        throw conflict('Запись Google изменилась. Обновите календарь перед отметкой выполнения.');
      return event;
    };
    const original = await readEvent(),
      link = taskLinkFromDescription(original.description);
    if (!link)
      throw new AppError(
        403,
        'GOOGLE_TASK_NOT_LINKED',
        'Для этой записи не найдено однозначной ссылки Google Tasks.',
      );
    await this.assertSingleTaskMirror(connection, eventId, link, signal);
    const catalog = await this.taskCatalog(connection, signal),
      matches = catalog.get(link);
    if (matches?.length !== 1)
      throw new AppError(
        409,
        'GOOGLE_TASK_NOT_LINKED',
        'Не удалось однозначно определить задачу Google. Обновите календарь.',
      );
    const { list, task: match } = matches[0];
    const data = await this.api(connection, {
      resource: 'tasks',
      taskListId: list,
      taskId: match.id,
      method: 'GET',
      signal,
    });
    const parsed = nativeTaskSchema.safeParse(data);
    if (
      !parsed.success ||
      parsed.data.id !== match.id ||
      parsed.data.deleted ||
      normalizeGoogleTaskLink(parsed.data.webViewLink ?? '') !== link
    )
      throw new AppError(
        409,
        'GOOGLE_TASK_NOT_LINKED',
        'Задача Google изменилась или недоступна. Обновите календарь.',
      );
    const task = parsed.data;
    if (!taskMatchesMirror(task, original))
      throw new AppError(
        409,
        'GOOGLE_TASK_NOT_LINKED',
        'Название или день задачи Google не совпадают с записью календаря. Обновите календарь или откройте Google Tasks.',
      );
    if (task.etag !== taskVersion)
      throw conflict(
        'Статус задачи Google изменился. Обновите календарь перед повторной отметкой.',
      );
    const fresh = await readEvent();
    if (taskLinkFromDescription(fresh.description) !== link || !taskMatchesMirror(task, fresh))
      throw conflict('Связь задачи Google изменилась. Обновите календарь.');
    const desired = input.completed ? 'completed' : 'needsAction';
    if (task.status === desired)
      return { event: { ...fresh, googleTask: this.taskInfo(connection, list, task) } };
    if (signal.aborted) throw safeProviderError(signal.reason);
    const updated = await this.api(connection, {
      resource: 'tasks',
      taskListId: list,
      taskId: task.id,
      method: 'PATCH',
      headers: { 'If-Match': taskVersion },
      body: input.completed ? { status: desired } : { status: desired, completed: null },
    });
    const confirmed = nativeTaskSchema.safeParse(updated);
    if (
      !confirmed.success ||
      confirmed.data.deleted ||
      confirmed.data.id !== task.id ||
      confirmed.data.status !== desired ||
      !taskMatchesMirror(confirmed.data, fresh) ||
      normalizeGoogleTaskLink(confirmed.data.webViewLink ?? '') !== link
    )
      throw new AppError(
        502,
        'GOOGLE_TASKS_UNCONFIRMED',
        'Не удалось подтвердить выполнение в Google. Обновите календарь перед повторной отметкой.',
      );
    return { event: { ...fresh, googleTask: this.taskInfo(connection, list, confirmed.data) } };
  }
  private async calendarLabels(
    connection: GoogleConnection,
    signal?: AbortSignal,
  ): Promise<CalendarLabels> {
    const data = await this.api(connection, {
      method: 'GET',
      resource: 'calendar',
      signal,
      query: { fields: 'etag,labelProperties' },
    });
    const parsed = calendarLabelsSchema.safeParse(data);
    if (
      !parsed.success ||
      new Set((parsed.data.labelProperties?.eventLabels ?? []).map((label) => label.id)).size !==
        (parsed.data.labelProperties?.eventLabels?.length ?? 0)
    )
      throw new AppError(
        502,
        'GOOGLE_INVALID_LABELS',
        'Google вернул неполную палитру календаря. Обновите календарь позднее.',
      );
    return parsed.data;
  }
  private async ensureLabel(connection: GoogleConnection, hex: string) {
    const id = stableLabelId(hex);
    for (let attempt = 0; attempt < 3; attempt++) {
      const calendar = await this.calendarLabels(connection),
        labels = calendar.labelProperties?.eventLabels ?? [];
      const existing = labels.find((label) => label.backgroundColor.toLowerCase() === hex);
      if (existing) return { id: existing.id, labels: labelColors(calendar) };
      if (labels.some((label) => label.id === id))
        throw conflict(
          'Идентификатор цвета Google уже занят другой меткой. Обновите палитру в Google Calendar.',
        );
      if (labels.length >= 200)
        throw new AppError(
          400,
          'GOOGLE_LABEL_LIMIT',
          'В Google Calendar уже 200 цветовых меток. Удалите ненужную метку в Google, затем повторите.',
        );
      const name = CALENDAR_PALETTE.find((color) => color.hex === hex)?.name ?? hex;
      const next = { id, backgroundColor: hex, name: 'Ritm · ' + name };
      try {
        const data = await this.api(connection, {
          method: 'PATCH',
          resource: 'calendar',
          headers: { 'If-Match': calendar.etag },
          body: {
            labelProperties: { ...calendar.labelProperties, eventLabels: [...labels, next] },
          },
        });
        const updated = calendarLabelsSchema.safeParse(data);
        if (
          !updated.success ||
          !updated.data.labelProperties?.eventLabels?.some(
            (label) => label.id === id && label.backgroundColor.toLowerCase() === hex,
          )
        )
          throw new AppError(
            502,
            'GOOGLE_INVALID_LABELS',
            'Не удалось подтвердить цветовую метку Google. Обновите календарь перед повторным сохранением.',
          );
        return { id, labels: labelColors(updated.data) };
      } catch (error) {
        if (!(error instanceof AppError) || error.code !== 'CONFLICT' || attempt === 2) throw error;
      }
    }
    throw conflict('Палитра Google изменилась. Обновите календарь и повторите.');
  }
  private async eventColor(
    connection: GoogleConnection,
    value: string | null | undefined,
  ): Promise<{
    body: Record<string, unknown>;
    labels?: ReadonlyMap<string, string>;
    useLabels: boolean;
  }> {
    if (value === undefined) return { body: {}, useLabels: false };
    if (!usesExtendedColors(connection.tokens)) {
      if (value?.startsWith('#'))
        throw new AppError(
          403,
          'GOOGLE_EXTENDED_COLORS_REQUIRED',
          'Разрешите новые цвета в подключении Google Calendar, чтобы этот цвет сохранялся и в Google.',
        );
      return { body: { colorId: value }, useLabels: false };
    }
    if (value === null) return { body: { eventLabelId: '' }, useLabels: true };
    const hex = value.startsWith('#')
      ? value
      : CALENDAR_PALETTE.find((color) => color.id === value)!.hex;
    const label = await this.ensureLabel(connection, hex);
    return { body: { eventLabelId: label.id }, labels: label.labels, useLabels: true };
  }
  private async mapReturnedEvent(
    data: unknown,
    connection: GoogleConnection,
    timeZone: string,
    labels?: ReadonlyMap<string, string>,
  ) {
    if (
      !labels &&
      usesExtendedColors(connection.tokens) &&
      data &&
      typeof data === 'object' &&
      (data as { eventLabelId?: unknown }).eventLabelId
    )
      labels = labelColors(await this.calendarLabels(connection));
    return mapGoogleEvent(data, timeZone, 'owner', labels);
  }
  async listEvents(
    input: {
      from: string;
      to: string;
      timeZone: string;
    },
    options: { signal?: AbortSignal } = {},
  ): Promise<GoogleCalendarResult> {
    const timeout = AbortSignal.timeout(25_000);
    const signal = options.signal ? AbortSignal.any([timeout, options.signal]) : timeout;
    const from = dateValue.parse(input.from),
      to = dateValue.parse(input.to);
    const distance = (Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / 86_400_000;
    if (distance <= 0 || distance > 93)
      throw new AppError(
        400,
        'GOOGLE_RANGE',
        'Выберите период Google Calendar от одного до 93 дней.',
      );
    try {
      new Intl.DateTimeFormat('ru', { timeZone: input.timeZone });
    } catch {
      throw new AppError(400, 'GOOGLE_TIMEZONE', 'Проверьте часовой пояс календаря.');
    }
    const tokens = await withAbort(() => this.token(), signal).catch((error: unknown) => {
        throw error instanceof AppError ? error : safeProviderError(error);
      }),
      events: GoogleCalendarEvent[] = [],
      seen = new Set<string>(),
      pageTokens = new Set<string>();
    const labels = usesExtendedColors(tokens.tokens)
      ? labelColors(await this.calendarLabels(tokens, signal))
      : undefined;
    let pageToken: string | undefined,
      partial = false,
      scanned = 0;
    for (let page = 0; page < 10; page++) {
      const data = await this.api(tokens, {
        method: 'GET',
        signal,
        query: {
          singleEvents: true,
          orderBy: 'startTime',
          showDeleted: false,
          timeMin: `${dateShift(from, -1)}T00:00:00Z`,
          timeMax: `${dateShift(to, 1)}T00:00:00Z`,
          timeZone: input.timeZone,
          maxResults: 250,
          fields:
            'items(id,summary,description,colorId,eventLabelId,etag,status,start,end,transparency,locked,eventType,creator(self),organizer(self),attendees(self),recurrence,recurringEventId),nextPageToken,accessRole',
          ...(pageToken ? { pageToken } : {}),
        },
      });
      const parsed = z
        .object({
          items: z.array(z.unknown()).max(2500).optional(),
          nextPageToken: z.string().max(4096).optional(),
          accessRole: z.string().optional(),
        })
        .safeParse(data);
      if (!parsed.success)
        throw new AppError(
          502,
          'GOOGLE_INVALID_RESPONSE',
          'Google вернул неполный календарь. Попробуйте позднее.',
        );
      let processed = 0;
      for (const item of parsed.data.items ?? []) {
        processed++;
        scanned++;
        const event = mapGoogleEvent(
          item,
          input.timeZone,
          parsed.data.accessRole ?? 'reader',
          labels,
        );
        if (event && !seen.has(event.id) && inRange(event, from, to, input.timeZone)) {
          events.push(event);
          seen.add(event.id);
        }
        if (scanned >= MAX_EVENTS) break;
      }
      if (scanned >= MAX_EVENTS) {
        partial =
          Boolean(parsed.data.nextPageToken) || processed < (parsed.data.items?.length ?? 0);
        break;
      }
      pageToken = parsed.data.nextPageToken;
      if (!pageToken) break;
      if (pageTokens.has(pageToken))
        throw new AppError(
          502,
          'GOOGLE_INVALID_RESPONSE',
          'Google не завершил загрузку календаря. Повторите позднее.',
        );
      pageTokens.add(pageToken);
      if (page === 9) partial = true;
    }
    const tasks = await this.enrichTasks(events, tokens, signal);
    const fetchedAt = new Date(this.now()).toISOString();
    await this.withLease(async (assertActive) => {
      if (signal.aborted) throw safeProviderError(signal.reason);
      const latest = await this.assertConnection(tokens);
      assertActive();
      await this.options.secrets.saveSecret(
        TOKEN_SLOT,
        JSON.stringify({ ...latest, lastFetchedAt: fetchedAt }),
      );
    });
    return { events, from, to, timeZone: input.timeZone, fetchedAt, partial, tasks };
  }
  async createEvent(
    value: GoogleEventInput,
    requestId: string,
    options: {
      timeZone?: string;
      expectedConnectionIdentity?: string;
      transparency?: 'transparent' | 'opaque';
    } = {},
  ): Promise<GoogleCalendarEvent> {
    const input = googleEventInputSchema.parse(value),
      request = z.string().uuid().parse(requestId),
      tokens = await this.token(),
      timeZone = options.timeZone ?? (await this.options.settings()).timeZone;
    if (
      options.expectedConnectionIdentity &&
      this.identity(tokens) !== options.expectedConnectionIdentity
    )
      throw new AppError(
        409,
        'GOOGLE_TRANSFER_CONNECTION_CHANGED',
        'Подключение Google изменилось. Запись Ritm сохранена; повторный перенос в другой аккаунт отменён.',
      );
    try {
      new Intl.DateTimeFormat('ru', { timeZone });
    } catch {
      throw new AppError(400, 'GOOGLE_TIMEZONE', 'Проверьте часовой пояс календаря.');
    }
    const fingerprint = hash(
        JSON.stringify({
          input,
          timeZone,
          ...(options.transparency === undefined ? {} : { transparency: options.transparency }),
        }),
      ),
      eventId = hash(`Ritm:${request}`);
    const fields = eventBody(input, timeZone),
      color = await this.eventColor(tokens, input.colorId);
    const body = {
      ...fields,
      ...color.body,
      ...(options.transparency === undefined ? {} : { transparency: options.transparency }),
      id: eventId,
      extendedProperties: { private: { ritmRequestHash: fingerprint } },
    };
    let data: unknown;
    try {
      data = await this.api(tokens, {
        method: 'POST',
        body,
        query: { sendUpdates: 'none', ...(color.useLabels ? { eventLabelVersion: 1 } : {}) },
      });
    } catch (error) {
      if (!(error instanceof AppError) || error.status !== 409) throw error;
      data = await this.api(tokens, { method: 'GET', eventId });
      if (
        !data ||
        typeof data !== 'object' ||
        (data as { extendedProperties?: { private?: { ritmRequestHash?: unknown } } })
          .extendedProperties?.private?.ritmRequestHash !== fingerprint
      )
        throw conflict(
          'Идентификатор сохранения уже использован. Обновите календарь и начните новую запись.',
        );
    }
    const event = await this.mapReturnedEvent(data, tokens, timeZone, color.labels);
    if (!event || event.id !== eventId)
      throw new AppError(
        502,
        'GOOGLE_INVALID_EVENT',
        'Не удалось подтвердить сохранённое событие. Обновите календарь.',
      );
    return event;
  }
  async updateEvent(
    id: string,
    value: GoogleEventInput,
    etag: string,
  ): Promise<GoogleCalendarEvent> {
    if (value.repeat !== undefined)
      throw new AppError(
        400,
        'GOOGLE_SERIES_READ_ONLY',
        'Повторение задаётся при создании. Для изменения всей серии откройте Google Calendar.',
      );
    const eventId = googleEventIdSchema.parse(id),
      input = googleEventInputSchema.parse(value),
      version = googleEtagSchema.parse(etag),
      tokens = await this.token(),
      settings = await this.options.settings();
    const original = mapGoogleEvent(
      await this.api(tokens, { method: 'GET', eventId }),
      settings.timeZone,
    );
    if (!original)
      throw new AppError(
        404,
        'GOOGLE_EVENT_NOT_FOUND',
        'Событие Google удалено. Обновите календарь.',
      );
    if (original.id !== eventId)
      throw new AppError(
        502,
        'GOOGLE_INVALID_EVENT',
        'Google вернул другую запись. Обновите календарь перед изменением.',
      );
    if (original.readOnly)
      throw new AppError(
        403,
        'GOOGLE_EVENT_READ_ONLY',
        original.readOnlyReason || 'Это событие изменяется в Google Calendar.',
      );
    if (original.etag !== version)
      throw conflict('Событие Google изменилось. Обновите календарь перед сохранением.');
    const fields = eventBody(input, settings.timeZone),
      color = await this.eventColor(tokens, input.colorId);
    const data = await this.api(tokens, {
      method: 'PATCH',
      eventId,
      body: { ...fields, ...color.body },
      headers: { 'If-Match': version },
      query: { sendUpdates: 'none', ...(color.useLabels ? { eventLabelVersion: 1 } : {}) },
    });
    const event = await this.mapReturnedEvent(data, tokens, settings.timeZone, color.labels);
    if (!event || event.id !== eventId)
      throw new AppError(
        502,
        'GOOGLE_INVALID_EVENT',
        'Не удалось подтвердить изменение Google. Обновите календарь.',
      );
    return event;
  }
  async deleteEvent(id: string, etag: string): Promise<{ deleted: true }> {
    const eventId = googleEventIdSchema.parse(id),
      version = googleEtagSchema.parse(etag),
      connection = await this.token(),
      settings = await this.options.settings();
    let data: unknown;
    try {
      data = await this.api(connection, { method: 'GET', eventId });
    } catch (error) {
      if (error instanceof AppError && error.code === 'GOOGLE_EVENT_NOT_FOUND')
        return { deleted: true };
      throw error;
    }
    if (data && typeof data === 'object' && (data as { status?: unknown }).status === 'cancelled') {
      if ((data as { id?: unknown }).id !== eventId)
        throw new AppError(
          502,
          'GOOGLE_INVALID_EVENT',
          'Google вернул другую запись. Обновите календарь.',
        );
      return { deleted: true };
    }
    const original = mapGoogleEvent(data, settings.timeZone)!;
    if (original.id !== eventId)
      throw new AppError(
        502,
        'GOOGLE_INVALID_EVENT',
        'Google вернул другую запись. Обновите календарь.',
      );
    if (original.readOnly)
      throw new AppError(
        403,
        'GOOGLE_EVENT_READ_ONLY',
        original.readOnlyReason || 'Это событие удаляется в Google Calendar.',
      );
    if (original.etag !== version)
      throw conflict('Событие Google изменилось. Обновите календарь перед удалением.');
    try {
      await this.api(connection, {
        method: 'DELETE',
        eventId,
        headers: { 'If-Match': version },
        query: { sendUpdates: 'none' },
      });
    } catch (error) {
      if (!(error instanceof AppError) || error.code !== 'GOOGLE_EVENT_NOT_FOUND') throw error;
    }
    return { deleted: true };
  }
  async disconnect(): Promise<GoogleCalendarStatus> {
    await this.withLease(async (assertActive) => {
      await this.invalidateConnection(assertActive);
    });
    // Google revocation affects other clients in a shared Cloud project. This is local disconnection only.
    return this.status();
  }
  async assertFreeSlots(
    slots: { date: string | null; time: string | null; duration: number; title: string }[],
    timeZone: string,
  ) {
    const status = await this.status();
    if (['unconfigured', 'disconnected'].includes(status.status)) return;
    if (status.status === 'reauth_required')
      throw new AppError(
        401,
        'GOOGLE_REAUTH_REQUIRED',
        'Подключите Google заново, чтобы проверить план перед применением.',
      );
    const dates = [
      ...new Set(
        slots.filter((slot) => slot.date && slot.time).map((slot) => dateValue.parse(slot.date)),
      ),
    ];
    if (dates.length > 20)
      throw new AppError(
        400,
        'GOOGLE_PLAN_LIMIT',
        'Проверяйте не больше 20 дней за одно применение плана.',
      );
    const controller = new AbortController(),
      signal = AbortSignal.any([controller.signal, AbortSignal.timeout(25_000)]);
    let cursor = 0;
    const worker = async () => {
      while (cursor < dates.length) {
        const date = dates[cursor++];
        const result = await this.listEvents(
          { from: date, to: dateShift(date, 1), timeZone },
          { signal },
        );
        if (result.partial)
          throw conflict(
            'Google вернул неполное расписание. Уточните период перед применением плана.',
          );
        for (const slot of slots.filter((slot) => slot.date === date && slot.time)) {
          const start = googleZonedInstant(date, slot.time!, timeZone),
            end = start + slot.duration * 60_000;
          if (
            result.events.some(
              (event) =>
                event.busy &&
                (event.allDay ||
                  (start < Date.parse(event.end.dateTime!) &&
                    end > Date.parse(event.start.dateTime!))),
            )
          )
            throw conflict(
              `«${slot.title}» пересекается с событием Google. Выберите другое время.`,
            );
        }
      }
    };
    try {
      await Promise.all(Array.from({ length: Math.min(4, dates.length) }, worker));
    } catch (error) {
      controller.abort();
      throw error;
    }
  }
}

export const createGoogleCalendarService = (options: GoogleCalendarOptions) =>
  new GoogleCalendarService(options);
