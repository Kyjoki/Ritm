import type {
  AiStatus,
  ChatMode,
  Bootstrap,
  Conversation,
  FinanceEntry,
  FinanceEntryInput,
  Habit,
  HabitInput,
  GoogleCalendarStatus,
  GoogleCalendarResult,
  GoogleCalendarEvent,
  GoogleEventInput,
  GoogleOAuthSetup,
  GoogleOAuthSetupInput,
  GoogleTransferResult,
  ProposalResult,
  Settings,
  Task,
  TaskInput,
  WorkoutDoc,
  WorkoutKind,
  WorkoutsSnapshot,
} from '../../shared/types';
import { getLanguage, translate } from './i18n';
import type { TelegramStatus } from '../../shared/types';
const tr = (source: string) => translate(getLanguage(), source);

export interface DeviceSession {
  id: string;
  client: 'web' | 'ios';
  deviceName: string;
  createdAt: string;
  lastSeenAt: string;
  current: boolean;
}
export interface SecurityOverview {
  totpEnabled: boolean;
  recoveryCodesLeft: number;
  sessions: DeviceSession[];
}
export interface LoginSecondFactor {
  totp?: string;
  recoveryCode?: string;
}
export class ApiError extends Error {
  constructor(
    message: string,
    public status: number,
    public code?: string,
    public retryAfterSeconds?: number,
    /** The stored document the server sent with a 409 on /api/workouts. */
    public current?: unknown,
  ) {
    super(message);
    this.name = 'ApiError';
  }
}
async function request<T>(
  path: string,
  method = 'GET',
  body?: unknown,
  signal?: AbortSignal,
): Promise<T> {
  let response: Response;
  try {
    response = await fetch(`/api${path}`, {
      method,
      credentials: 'same-origin',
      headers: {
        'Accept-Language': getLanguage(),
        ...(method === 'GET' || method === 'HEAD' ? {} : { 'Content-Type': 'application/json' }),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal,
    });
  } catch {
    throw new ApiError(
      tr('Не удалось связаться с сервером. Проверьте соединение и попробуйте снова.'),
      0,
      'NETWORK',
    );
  }
  const data = await response.json().catch(() => null);
  if (!response.ok) {
    const bodyDelay = data?.retryAfterSeconds;
    const headerDelay = response.headers.get('Retry-After');
    const delay =
      typeof bodyDelay === 'number'
        ? bodyDelay
        : headerDelay && /^\d+$/.test(headerDelay)
          ? Number(headerDelay)
          : undefined;
    if (data?.code === 'AUTH_REQUIRED' && typeof window !== 'undefined')
      window.dispatchEvent(new Event('ritm:auth-required'));
    throw new ApiError(
      data?.error ?? tr('Не удалось выполнить действие.'),
      response.status,
      data?.code,
      response.status === 429 && Number.isInteger(delay) && delay! > 0 && delay! <= 3600
        ? delay
        : undefined,
      data?.current,
    );
  }
  if (response.status === 204) return undefined as T;
  if (data === null || typeof data !== 'object')
    throw new ApiError(
      tr('Сервер вернул некорректный ответ. Обновите страницу или проверьте настройку сервера.'),
      502,
      'INVALID_RESPONSE',
    );
  return data as T;
}
export const api = {
  session: () => request<{ authenticated: boolean; requiresLogin: boolean }>('/session'),
  login: (login: string, password: string, factor: LoginSecondFactor = {}) =>
    request('/login', 'POST', { login, password, client: 'web', ...factor }),
  security: () => request<SecurityOverview>('/security'),
  setupTotp: () => request<{ secret: string; otpauthUrl: string }>('/security/totp/setup', 'POST'),
  confirmTotp: (code: string) =>
    request<{ recoveryCodes: string[] }>('/security/totp/confirm', 'POST', { code }),
  disableTotp: (password: string, factor: LoginSecondFactor & { code?: string }) =>
    request<{ totpEnabled: false }>('/security/totp/disable', 'POST', {
      password,
      code: factor.totp ?? factor.code,
      recoveryCode: factor.recoveryCode,
    }),
  regenerateRecoveryCodes: (code: string) =>
    request<{ recoveryCodes: string[] }>('/security/recovery-codes', 'POST', { code }),
  revokeSession: (id: string) =>
    request<void>(`/security/sessions/${encodeURIComponent(id)}`, 'DELETE'),
  revokeOtherSessions: () => request<void>('/security/sessions/revoke-others', 'POST'),
  logout: () => request('/logout', 'POST'),
  bootstrap: () => request<Bootstrap>('/bootstrap'),
  habits: (signal?: AbortSignal) =>
    request<{ habits: Habit[] }>('/habits', 'GET', undefined, signal),
  createHabit: (habit: HabitInput) => request<{ habit: Habit }>('/habits', 'POST', habit),
  updateHabit: (id: string, habit: HabitInput, expectedUpdatedAt: string) =>
    request<{ habit: Habit }>(`/habits/${encodeURIComponent(id)}`, 'PATCH', {
      habit,
      expectedUpdatedAt,
    }),
  setHabitDay: (id: string, date: string, completed: boolean, expectedUpdatedAt: string) =>
    request<{ habit: Habit }>(
      `/habits/${encodeURIComponent(id)}/days/${encodeURIComponent(date)}`,
      'PATCH',
      { completed, expectedUpdatedAt },
    ),
  setHabitProgress: (id: string, date: string, count: number, expectedUpdatedAt: string) =>
    request<{ habit: Habit }>(
      `/habits/${encodeURIComponent(id)}/days/${encodeURIComponent(date)}/progress`,
      'PATCH',
      { count, expectedUpdatedAt },
    ),
  deleteHabit: (id: string, expectedUpdatedAt: string) =>
    request<{ deleted: true }>(`/habits/${encodeURIComponent(id)}`, 'DELETE', {
      expectedUpdatedAt,
    }),
  finance: (signal?: AbortSignal) =>
    request<{ entries: FinanceEntry[] }>('/finance', 'GET', undefined, signal),
  createFinanceEntry: (entry: FinanceEntryInput) =>
    request<{ entry: FinanceEntry }>('/finance', 'POST', entry),
  updateFinanceEntry: (id: string, entry: FinanceEntryInput, expectedUpdatedAt: string) =>
    request<{ entry: FinanceEntry }>(`/finance/${encodeURIComponent(id)}`, 'PATCH', {
      entry,
      expectedUpdatedAt,
    }),
  deleteFinanceEntry: (id: string, expectedUpdatedAt: string) =>
    request<{ deleted: true }>(`/finance/${encodeURIComponent(id)}`, 'DELETE', {
      expectedUpdatedAt,
    }),
  workouts: (signal?: AbortSignal) =>
    request<WorkoutsSnapshot>('/workouts', 'GET', undefined, signal),
  putWorkout: (
    kind: WorkoutKind,
    id: string,
    data: Record<string, unknown>,
    expectedUpdatedAt: string | null,
  ) =>
    request<WorkoutDoc>(`/workouts/${kind}/${encodeURIComponent(id)}`, 'PUT', {
      data,
      expectedUpdatedAt,
    }),
  deleteWorkout: (kind: WorkoutKind, id: string, expectedUpdatedAt: string) =>
    request<void>(
      `/workouts/${kind}/${encodeURIComponent(id)}?expectedUpdatedAt=${encodeURIComponent(expectedUpdatedAt)}`,
      'DELETE',
    ),
  createTask: (task: TaskInput) => request<Task>('/tasks', 'POST', task),
  updateTask: (id: string, task: Partial<TaskInput> & { occurrenceDate?: string }) =>
    request<Task>(`/tasks/${encodeURIComponent(id)}`, 'PATCH', task),
  deleteTask: (id: string) =>
    request<{ deletedTask: Task }>(`/tasks/${encodeURIComponent(id)}`, 'DELETE'),
  restoreTask: (task: Task) => request<Task>('/tasks/restore', 'POST', { task }),
  transferTaskToGoogle: (id: string) =>
    request<GoogleTransferResult>(`/tasks/${encodeURIComponent(id)}/google`, 'POST', {}),
  saveSettings: (settings: Partial<Settings>) => request<Settings>('/settings', 'PATCH', settings),
  configureAI: (apiKey: string, model: string) =>
    request<AiStatus>('/settings/openai', 'POST', { apiKey, model }),
  disconnectAI: () => request<AiStatus>('/settings/openai', 'DELETE'),
  telegramStatus: () => request<TelegramStatus>('/integrations/telegram/status'),
  saveTelegramReminders: (enabled: boolean, leadMinutes: 0 | 5 | 10 | 15 | 30 | 60) =>
    request<TelegramStatus>('/integrations/telegram/reminders', 'PATCH', { enabled, leadMinutes }),
  testTelegramReminder: () =>
    request<{ ok: true }>('/integrations/telegram/reminders/test', 'POST', {}),
  configureTelegram: (botToken: string) =>
    request<TelegramStatus>('/integrations/telegram/configuration', 'POST', { botToken }),
  pairTelegram: () => request<TelegramStatus>('/integrations/telegram/pairing', 'POST', {}),
  disconnectTelegram: () => request<TelegramStatus>('/integrations/telegram/connection', 'DELETE'),
  googleConfiguration: () => request<GoogleOAuthSetup>('/integrations/google/configuration'),
  configureGoogle: (configuration: GoogleOAuthSetupInput) =>
    request<GoogleOAuthSetup>('/integrations/google/configuration', 'POST', configuration),
  removeGoogleConfiguration: () =>
    request<GoogleOAuthSetup>('/integrations/google/configuration', 'DELETE'),
  googleStatus: () => request<GoogleCalendarStatus>('/integrations/google/status'),
  connectGoogle: (extendedColors?: boolean, tasks?: boolean) =>
    request<{ authorizationUrl: string }>('/integrations/google/connect', 'POST', {
      ...(extendedColors === undefined ? {} : { extendedColors }),
      ...(tasks === undefined ? {} : { tasks }),
    }),
  disconnectGoogle: () =>
    request<GoogleCalendarStatus>('/integrations/google/connection', 'DELETE'),
  googleEvents: (from: string, to: string, timeZone: string, signal?: AbortSignal) =>
    request<GoogleCalendarResult>(
      `/integrations/google/events?from=${encodeURIComponent(from)}&to=${encodeURIComponent(to)}&timeZone=${encodeURIComponent(timeZone)}`,
      'GET',
      undefined,
      signal,
    ),
  createGoogleEvent: (event: GoogleEventInput, requestId: string) =>
    request<GoogleCalendarEvent>('/integrations/google/events', 'POST', { event, requestId }),
  completeGoogleTask: (event: GoogleCalendarEvent, completed: boolean) => {
    if (!event.googleTask) throw new Error(tr('Подключи Google Tasks, чтобы отмечать выполнение.'));
    return request<{ event: GoogleCalendarEvent }>(
      `/integrations/google/events/${encodeURIComponent(event.id)}/task`,
      'PATCH',
      {
        etag: event.etag,
        taskEtag: event.googleTask.etag,
        completed,
        connectionId: event.googleTask.connectionId,
      },
    );
  },
  updateGoogleEvent: (id: string, event: GoogleEventInput, etag: string) =>
    request<GoogleCalendarEvent>(`/integrations/google/events/${encodeURIComponent(id)}`, 'PATCH', {
      event,
      etag,
    }),
  deleteGoogleEvent: (id: string, etag: string) =>
    request<{ deleted: true }>(`/integrations/google/events/${encodeURIComponent(id)}`, 'DELETE', {
      etag,
    }),
  createConversation: () => request<Conversation>('/conversations', 'POST', {}),
  deleteConversation: (id: string) => request(`/conversations/${encodeURIComponent(id)}`, 'DELETE'),
  chat: (
    conversationId: string | undefined,
    message: string,
    requestId: string,
    mode?: ChatMode,
    reviewMessageId?: string,
  ) =>
    request<Conversation>('/chat', 'POST', {
      conversationId,
      message,
      requestId,
      mode,
      ...(reviewMessageId ? { reviewMessageId } : {}),
    }),
  proposals: (
    action: 'apply' | 'undo',
    conversationId: string,
    messageId: string,
    proposalIds: string[],
  ) =>
    request<ProposalResult>(`/proposals/${action}`, 'POST', {
      conversationId,
      messageId,
      proposalIds,
    }),
  reject: (conversationId: string, messageId: string, proposalIds: string[]) =>
    request<Conversation>('/proposals/reject', 'POST', { conversationId, messageId, proposalIds }),
};
