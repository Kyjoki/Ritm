import type {
  AiStatus,
  ChatMode,
  Bootstrap,
  Conversation,
  FinanceEntry,
  FinanceEntryInput,
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
} from '../../shared/types';
import { getLanguage, translate } from './i18n';
const tr = (source: string) => translate(getLanguage(), source);

export class ApiError extends Error {
  constructor(
    message: string,
    public status: number,
    public code?: string,
    public retryAfterSeconds?: number,
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
    );
  }
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
  login: (login: string, password: string) => request('/login', 'POST', { login, password }),
  logout: () => request('/logout', 'POST'),
  bootstrap: () => request<Bootstrap>('/bootstrap'),
  finance: () => request<{ entries: FinanceEntry[] }>('/finance'),
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
  createTask: (task: TaskInput) => request<Task>('/tasks', 'POST', task),
  updateTask: (id: string, task: Partial<TaskInput> & { occurrenceDate?: string }) =>
    request<Task>(`/tasks/${encodeURIComponent(id)}`, 'PATCH', task),
  deleteTask: (id: string) =>
    request<{ deletedTask: Task }>(`/tasks/${encodeURIComponent(id)}`, 'DELETE'),
  restoreTask: (task: Task) => request<Task>('/tasks/restore', 'POST', { task }),
  transferTaskToGoogle: (id: string) =>
    request<GoogleTransferResult>(`/tasks/${encodeURIComponent(id)}/google`, 'POST', {}),
  saveSettings: (settings: Settings) => request<Settings>('/settings', 'PATCH', settings),
  configureAI: (apiKey: string, model: string) =>
    request<AiStatus>('/settings/openai', 'POST', { apiKey, model }),
  disconnectAI: () => request<AiStatus>('/settings/openai', 'DELETE'),
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
