import type {
  AiStatus,
  Bootstrap,
  Conversation,
  ProposalResult,
  Settings,
  Task,
  TaskInput,
} from '../../shared/types';

export class ApiError extends Error {
  constructor(
    message: string,
    public status: number,
    public code?: string,
  ) {
    super(message);
    this.name = 'ApiError';
  }
}
async function request<T>(path: string, method = 'GET', body?: unknown): Promise<T> {
  let response: Response;
  try {
    response = await fetch(`/api${path}`, {
      method,
      credentials: 'same-origin',
      headers:
        method === 'GET' || method === 'HEAD' ? undefined : { 'Content-Type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  } catch {
    throw new ApiError(
      'Не удалось связаться с сервером. Проверьте соединение и попробуйте снова.',
      0,
      'NETWORK',
    );
  }
  const data = await response.json().catch(() => null);
  if (!response.ok) {
    if (data?.code === 'AUTH_REQUIRED' && typeof window !== 'undefined')
      window.dispatchEvent(new Event('ritm:auth-required'));
    throw new ApiError(
      data?.error ?? 'Не удалось выполнить действие.',
      response.status,
      data?.code,
    );
  }
  return data as T;
}
export const api = {
  session: () => request<{ authenticated: boolean; requiresLogin: boolean }>('/session'),
  login: (password: string) => request('/login', 'POST', { password }),
  logout: () => request('/logout', 'POST'),
  bootstrap: () => request<Bootstrap>('/bootstrap'),
  createTask: (task: TaskInput) => request<Task>('/tasks', 'POST', task),
  updateTask: (id: string, task: Partial<TaskInput> & { occurrenceDate?: string }) =>
    request<Task>(`/tasks/${encodeURIComponent(id)}`, 'PATCH', task),
  deleteTask: (id: string) =>
    request<{ deletedTask: Task }>(`/tasks/${encodeURIComponent(id)}`, 'DELETE'),
  restoreTask: (task: Task) => request<Task>('/tasks/restore', 'POST', { task }),
  saveSettings: (settings: Settings) => request<Settings>('/settings', 'PATCH', settings),
  configureAI: (apiKey: string, model: string) =>
    request<AiStatus>('/settings/openai', 'POST', { apiKey, model }),
  disconnectAI: () => request<AiStatus>('/settings/openai', 'DELETE'),
  createConversation: () => request<Conversation>('/conversations', 'POST', {}),
  deleteConversation: (id: string) => request(`/conversations/${encodeURIComponent(id)}`, 'DELETE'),
  chat: (conversationId: string | undefined, message: string, requestId: string) =>
    request<Conversation>('/chat', 'POST', { conversationId, message, requestId }),
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
