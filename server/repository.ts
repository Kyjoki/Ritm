import type {
  Bootstrap,
  ChatMessage,
  Conversation,
  ProposalResult,
  Settings,
  Task,
  TaskInput,
} from '../shared/types.ts';

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
  tasks(): Awaitable<Task[]>;
  task(id: string): Awaitable<Task>;
  settings(): Awaitable<Settings>;
  updateSettings(patch: Partial<Settings>): Awaitable<Settings>;
  createTask(input: TaskInput): Awaitable<Task>;
  updateTask(id: string, patch: Partial<TaskInput> & { occurrenceDate?: string }): Awaitable<Task>;
  deleteTask(id: string): Awaitable<Task>;
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
