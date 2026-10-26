import type {
  Bootstrap,
  ChatMessage,
  Conversation,
  ProposalResult,
  Settings,
  Task,
  TaskInput,
  GoogleTransferResult,
  GoogleCalendarEvent,
  FinanceEntry,
  FinanceEntryInput,
  Habit,
  HabitInput,
} from '../shared/types.ts';
import { AppError } from './errors.ts';

/** UTF-8 bytes of the active task/history JSON sent to the client. */
export const MAX_WORKSPACE_BYTES = 8 * 1024 * 1024;
export const MAX_FINANCE_BYTES = 2 * 1024 * 1024;
export const MAX_HABITS_BYTES = 512 * 1024;
export function assertHabitStorage(habits: Habit[]) {
  if (Buffer.byteLength(JSON.stringify(habits), 'utf8') > MAX_HABITS_BYTES)
    throw new AppError(400, 'HABIT_STORAGE_LIMIT', 'Хранилище привычек заполнено.');
}
export function assertFinanceStorage(entries: FinanceEntry[]) {
  if (Buffer.byteLength(JSON.stringify(entries), 'utf8') > MAX_FINANCE_BYTES)
    throw new AppError(
      400,
      'FINANCE_STORAGE_LIMIT',
      'Достигнут предел хранения финансовых записей.',
    );
}
export function assertWorkspaceStorage(tasks: Task[], conversations: Conversation[]) {
  if (Buffer.byteLength(JSON.stringify({ tasks, conversations }), 'utf8') > MAX_WORKSPACE_BYTES)
    throw new AppError(
      400,
      'STORAGE_LIMIT',
      'Хранилище Ritm заполнено. Удалите старые задачи или диалоги и повторите действие.',
    );
}

/** SQLite may resolve synchronously; callers always await this contract. */
export type Awaitable<T> = T | Promise<T>;

export interface RequestRecord {
  fingerprint: string;
  conversationId: string | null;
  status: string;
  leaseExpiresAt?: number;
}

export type RequestClaim =
  | { leaseToken: string; completedConversationId?: never }
  | { completedConversationId: string; leaseToken?: never }
  | void;

export interface RateLimitResult {
  allowed: boolean;
  retryAfterMs: number;
}
export type GoogleTransferReceipt = {
  task: Task;
  timeZone: string;
  attempted: boolean;
  connectionIdentity: string;
} & (
  | { status: 'pending'; result?: never; completedAt?: never }
  | { status: 'complete'; result: GoogleTransferResult; completedAt: string }
);
export const googleTransferKey = (id: string) => 'google-transfer:' + id;
export function assertTransferTask(task: Task) {
  if (task.calendarEntry === false)
    throw new AppError(
      400,
      'GOOGLE_TRANSFER_NOT_SCHEDULED',
      'Эта задача сохранена только в списке дел и не переносится в календарь.',
    );
  if (task.completed || !task.date || task.completedDates.length > 0)
    throw new AppError(
      400,
      'GOOGLE_TRANSFER_INELIGIBLE',
      'Для переноса укажите дату незавершённой записи. Серия с историей выполнения остаётся в Ritm.',
    );
}
function canonicalTransferTask(task: Task) {
  return JSON.stringify(Object.entries(task).sort(([a], [b]) => a.localeCompare(b)));
}
export function assertTransferSnapshot(
  task: Task | undefined,
  receipt: GoogleTransferReceipt,
  timeZone: string,
) {
  if (
    !task ||
    canonicalTransferTask(task) !== canonicalTransferTask(receipt.task) ||
    timeZone !== receipt.timeZone
  )
    throw new AppError(
      409,
      'GOOGLE_TRANSFER_CHANGED',
      'Запись или часовой пояс изменились во время переноса. Новые правки Ritm сохранены; проверьте созданное событие Google перед следующим действием.',
    );
}
export function assertTransferConnection(receipt: GoogleTransferReceipt, identity: string) {
  if (receipt.connectionIdentity !== identity)
    throw new AppError(
      409,
      'GOOGLE_TRANSFER_CONNECTION_CHANGED',
      'Подключение Google изменилось во время переноса. Запись Ritm сохранена; проверьте событие в прежнем аккаунте Google.',
    );
}

/** Shared by PostgreSQL and the local durable security state. */
export interface RuntimeStateRepository {
  createSession(idHash: string, expiresAt: number): Awaitable<void>;
  hasSession(idHash: string): Awaitable<boolean>;
  deleteSession(idHash: string): Awaitable<void>;
  consumeRateLimit(key: string, maximum: number, windowMs: number): Awaitable<RateLimitResult>;
  getServerSecret(name: string): Awaitable<string | null>;
  setServerSecret(name: string, ciphertext: string): Awaitable<void>;
  deleteServerSecret(name: string): Awaitable<void>;
  consumeServerSecret(name: string): Awaitable<string | null>;
  acquireLease(name: string, ttlMs: number): Awaitable<string | null>;
  releaseLease(name: string, token: string): Awaitable<void>;
  close(): Awaitable<void>;
}

export interface WorkspaceRepository {
  habits(): Awaitable<Habit[]>;
  createHabit(input: HabitInput): Awaitable<Habit>;
  updateHabit(id: string, input: HabitInput, expectedUpdatedAt: string): Awaitable<Habit>;
  setHabitDay(
    id: string,
    date: string,
    completed: boolean,
    expectedUpdatedAt: string,
  ): Awaitable<Habit>;
  setHabitProgress(
    id: string,
    date: string,
    count: number,
    expectedUpdatedAt: string,
  ): Awaitable<Habit>;
  deleteHabit(id: string, expectedUpdatedAt: string): Awaitable<void>;
  financeEntries(): Awaitable<FinanceEntry[]>;
  createFinanceEntry(input: FinanceEntryInput): Awaitable<FinanceEntry>;
  updateFinanceEntry(
    id: string,
    input: FinanceEntryInput,
    expectedUpdatedAt: string,
  ): Awaitable<FinanceEntry>;
  deleteFinanceEntry(id: string, expectedUpdatedAt: string): Awaitable<void>;
  tasks(): Awaitable<Task[]>;
  task(id: string): Awaitable<Task>;
  settings(): Awaitable<Settings>;
  updateSettings(patch: Partial<Settings>): Awaitable<Settings>;
  createTask(input: TaskInput): Awaitable<Task>;
  updateTask(id: string, patch: Partial<TaskInput> & { occurrenceDate?: string }): Awaitable<Task>;
  deleteTask(id: string): Awaitable<Task>;
  googleTransfer(id: string): Awaitable<GoogleTransferReceipt | undefined>;
  beginGoogleTransfer(
    id: string,
    connectionIdentity: string,
    assertActive?: () => void,
  ): Awaitable<GoogleTransferReceipt>;
  markGoogleTransferAttempt(
    id: string,
    assertActive?: () => void,
  ): Awaitable<GoogleTransferReceipt>;
  finishGoogleTransfer(
    id: string,
    event: GoogleCalendarEvent,
    connectionIdentity: string,
    assertActive?: () => void,
  ): Awaitable<GoogleTransferResult>;
  cancelGoogleTransfer(id: string, snapshot: Task, assertActive?: () => void): Awaitable<void>;
  restoreTask(snapshot: Task): Awaitable<Task>;
  conversations(): Awaitable<Conversation[]>;
  conversation(id: string): Awaitable<Conversation>;
  createConversation(): Awaitable<Conversation>;
  deleteConversation(id: string): Awaitable<void>;
  saveConversation(value: Conversation): Awaitable<void>;
  bootstrap(aiStatus: Bootstrap['aiStatus']): Awaitable<Bootstrap>;
  request(id: string): Awaitable<RequestRecord | undefined>;
  startRequest(
    id: string,
    fingerprint: string,
    conversationId: string | null,
  ): Awaitable<RequestClaim>;
  abandonRequest(id: string, leaseToken?: string): Awaitable<void>;
  finishChat(
    requestId: string,
    originalConversationId: string | undefined,
    userText: string,
    assistant: ChatMessage,
    leaseToken?: string,
  ): Awaitable<Conversation>;
  proposalAction(
    action: 'apply' | 'undo' | 'reject',
    conversationId: string,
    messageId: string,
    ids: string[],
  ): Awaitable<ProposalResult>;
  close(): Awaitable<void>;
}

export type Repository = WorkspaceRepository & Partial<RuntimeStateRepository>;
