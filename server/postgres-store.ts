import pg, { type Pool as PgPool, type PoolClient } from 'pg';
import { randomUUID } from 'node:crypto';
import type {
  Bootstrap,
  ChatMessage,
  Conversation,
  ProposalResult,
  ScheduleTime,
  Settings,
  Task,
  TaskInput,
} from '../shared/types.ts';
import { AppError, conflict, missing } from './errors.ts';
import { minutes, scheduleInPast, taskInputSchema, validSchedule } from './validation.ts';
import type {
  RequestClaim,
  RequestRecord,
  RuntimeStateRepository,
  WorkspaceRepository,
} from './repository.ts';

const { Pool } = pg;
type Connection = Pick<PgPool | PoolClient, 'query'>;
type EntityTable = 'ritm_tasks' | 'ritm_deleted_tasks' | 'ritm_conversations';
const WORKSPACE_LOCK = 812014;
const defaultSettings: Settings = {
  displayName: 'Максим',
  email: '',
  theme: 'dark',
  sidebar: 'dark',
  language: 'ru',
  timeZone: 'Asia/Qyzylorda',
  notifications: false,
  dailyBriefing: false,
  workDayStart: '09:00',
  workDayEnd: '18:00',
};

function decoded<T>(value: unknown): T {
  return typeof value === 'string' ? (JSON.parse(value) as T) : (structuredClone(value) as T);
}
function canonical(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  if (value && typeof value === 'object') {
    const entries = Object.entries(value).sort(([a], [b]) => a.localeCompare(b));
    return `{${entries.map(([key, item]) => `${JSON.stringify(key)}:${canonical(item)}`).join(',')}}`;
  }
  return JSON.stringify(value);
}
function schedule(task: Task): ScheduleTime {
  return { date: task.date, time: task.time, duration: task.duration };
}
function sameSchedule(a: ScheduleTime, b: ScheduleTime) {
  return a.date === b.date && a.time === b.time && a.duration === b.duration;
}
function occursOn(task: Task, date: string) {
  if (!task.date || date < task.date) return false;
  if (task.date === date || task.repeat === 'daily') return true;
  if (task.repeat === 'weekly') {
    return (
      (Date.parse(`${date}T00:00:00Z`) - Date.parse(`${task.date}T00:00:00Z`)) % (7 * 86400000) ===
      0
    );
  }
  return task.repeat === 'monthly' && task.date.slice(8) === date.slice(8);
}

export interface PostgresStoreOptions {
  ownsPool?: boolean;
  /** Test clock; production uses Date.now. */
  now?: () => number;
  /** Must exceed the provider's bounded 90 second timeout. */
  requestLeaseMs?: number;
}

/**
 * One owner, shared PostgreSQL state. Construction never runs DDL or seed.
 * Every mutation takes the same transaction-scoped advisory/workspace row lock.
 * No transaction or connection is kept open while waiting for the AI provider.
 */
export class PostgresStore implements WorkspaceRepository, RuntimeStateRepository {
  private pool: PgPool;
  private ownsPool: boolean;
  private clock: () => number;
  private requestLeaseMs: number;
  constructor(connection: string | PgPool, options: PostgresStoreOptions = {}) {
    this.pool =
      typeof connection === 'string'
        ? new Pool({
            connectionString: connection,
            max: 3,
            idleTimeoutMillis: 10_000,
            connectionTimeoutMillis: 10_000,
          })
        : connection;
    this.ownsPool = options.ownsPool ?? typeof connection === 'string';
    this.clock = options.now ?? Date.now;
    this.requestLeaseMs = options.requestLeaseMs ?? 120_000;
    if (this.requestLeaseMs < 100_000)
      throw new Error('The chat request lease must exceed the provider timeout.');
  }
  async close() {
    if (this.ownsPool) await this.pool.end();
  }
  private stamp(previous?: string) {
    return new Date(Math.max(this.clock(), previous ? Date.parse(previous) + 1 : 0)).toISOString();
  }
  private async transaction<T>(operation: (client: PoolClient) => Promise<T>): Promise<T> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      await client.query('SELECT pg_advisory_xact_lock($1)', [WORKSPACE_LOCK]);
      const workspace = await client.query('SELECT id FROM ritm_workspace WHERE id = 1 FOR UPDATE');
      if (!workspace.rows.length)
        throw new AppError(
          503,
          'DATABASE_NOT_INITIALIZED',
          'Серверная база ещё не подготовлена. Выполните миграции Ritm.',
        );
      const value = await operation(client);
      await client.query('COMMIT');
      return value;
    } catch (error) {
      await client.query('ROLLBACK').catch(() => {});
      throw error;
    } finally {
      client.release();
    }
  }
  private async read<T>(
    client: Connection,
    table: EntityTable,
    id: string,
    lock = false,
  ): Promise<T | undefined> {
    const result = await client.query(
      `SELECT json FROM ${table} WHERE id = $1${lock ? ' FOR UPDATE' : ''}`,
      [id],
    );
    return result.rows[0] ? decoded<T>(result.rows[0].json) : undefined;
  }
  private async write<T extends { id: string }>(client: Connection, table: EntityTable, value: T) {
    await client.query(
      `INSERT INTO ${table} (id, json) VALUES ($1, $2::jsonb) ON CONFLICT (id) DO UPDATE SET json = EXCLUDED.json`,
      [value.id, JSON.stringify(value)],
    );
  }
  private async listTasks(client: Connection): Promise<Task[]> {
    const result = await client.query('SELECT json FROM ritm_tasks');
    return result.rows
      .map((row) => decoded<Task>(row.json))
      .sort(
        (a, b) =>
          (a.date ?? '9999').localeCompare(b.date ?? '9999') ||
          (a.time ?? '99').localeCompare(b.time ?? '99') ||
          a.createdAt.localeCompare(b.createdAt),
      );
  }
  private async readTask(client: Connection, id: string, lock = false): Promise<Task> {
    const task = await this.read<Task>(client, 'ritm_tasks', id, lock);
    if (!task) throw missing('Задание');
    return task;
  }
  private async readSettings(client: Connection): Promise<Settings> {
    const result = await client.query("SELECT json FROM ritm_config WHERE key = 'settings'");
    if (!result.rows[0])
      throw new AppError(
        503,
        'DATABASE_NOT_INITIALIZED',
        'Выполните миграции Ritm перед запуском приложения.',
      );
    return { ...defaultSettings, ...decoded<Settings>(result.rows[0].json) };
  }
  private async readConversation(
    client: Connection,
    id: string,
    lock = false,
  ): Promise<Conversation> {
    const conversation = await this.read<Conversation>(client, 'ritm_conversations', id, lock);
    if (!conversation) throw missing('Диалог');
    return conversation;
  }
  private async listConversations(client: Connection): Promise<Conversation[]> {
    const result = await client.query('SELECT json FROM ritm_conversations');
    return result.rows
      .map((row) => decoded<Conversation>(row.json))
      .sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
  }
  private async newConversation(client: Connection): Promise<Conversation> {
    const count = await client.query('SELECT count(*) AS count FROM ritm_conversations');
    if (Number(count.rows[0].count) >= 100)
      throw new AppError(
        400,
        'CONVERSATION_LIMIT',
        'Удалите ненужные диалоги, чтобы начать новый.',
      );
    const now = this.stamp();
    const conversation: Conversation = {
      id: randomUUID(),
      title: 'Новый диалог',
      messages: [],
      createdAt: now,
      updatedAt: now,
    };
    await this.write(client, 'ritm_conversations', conversation);
    return conversation;
  }

  async tasks() {
    return this.listTasks(this.pool);
  }
  async task(id: string) {
    return this.readTask(this.pool, id);
  }
  async settings() {
    return this.readSettings(this.pool);
  }
  async conversations() {
    return this.listConversations(this.pool);
  }
  async conversation(id: string) {
    return this.readConversation(this.pool, id);
  }
  async bootstrap(aiStatus: Bootstrap['aiStatus']): Promise<Bootstrap> {
    return this.transaction(async (client) => ({
      tasks: await this.listTasks(client),
      settings: await this.readSettings(client),
      conversations: await this.listConversations(client),
      aiStatus,
    }));
  }
  async updateSettings(patch: Partial<Settings>): Promise<Settings> {
    return this.transaction(async (client) => {
      const value = { ...(await this.readSettings(client)), ...patch };
      if (minutes(value.workDayStart) >= minutes(value.workDayEnd))
        throw new AppError(
          400,
          'INVALID_WORKDAY',
          'Начало рабочего дня должно быть раньше окончания.',
        );
      await client.query("UPDATE ritm_config SET json = $1::jsonb WHERE key = 'settings'", [
        JSON.stringify(value),
      ]);
      return value;
    });
  }
  async createTask(input: TaskInput): Promise<Task> {
    const fields = taskInputSchema.parse(input);
    return this.transaction(async (client) => {
      const count = await client.query('SELECT count(*) AS count FROM ritm_tasks');
      if (Number(count.rows[0].count) >= 2000)
        throw new AppError(
          400,
          'TASK_LIMIT',
          'Достигнут лимит 2000 задач. Удалите ненужные записи.',
        );
      const now = this.stamp();
      const task: Task = {
        ...fields,
        id: randomUUID(),
        createdAt: now,
        updatedAt: now,
        completedDates: [],
      };
      await this.write(client, 'ritm_tasks', task);
      return task;
    });
  }
  async updateTask(
    id: string,
    patch: Partial<TaskInput> & { occurrenceDate?: string },
  ): Promise<Task> {
    return this.transaction(async (client) => {
      const current = await this.readTask(client, id, true);
      const {
        id: _id,
        createdAt: _created,
        updatedAt: _updated,
        completedDates: currentDates,
        ...fields
      } = current;
      const { occurrenceDate, ...changes } = patch;
      let dates = currentDates ?? [];
      if (current.repeat !== 'none' && occurrenceDate) {
        if (!occursOn(current, occurrenceDate) || changes.completed === undefined)
          throw new AppError(
            400,
            'INVALID_OCCURRENCE',
            'Укажите дату существующего повторения задачи.',
          );
        const completed = new Set(dates);
        if (changes.completed) completed.add(occurrenceDate);
        else completed.delete(occurrenceDate);
        dates = [...completed].sort();
        changes.completed = false;
      } else if (current.repeat !== 'none' && changes.completed) {
        throw new AppError(
          400,
          'COMPLETION_DATE_REQUIRED',
          'Укажите дату повторения, которое хотите завершить.',
        );
      }
      if (dates.length > 5000)
        throw new AppError(
          400,
          'OCCURRENCE_LIMIT',
          'Достигнут предел выполненных повторений. Создайте новую серию.',
        );
      const input = taskInputSchema.parse({ ...fields, ...changes });
      const next: Task = {
        ...input,
        id,
        createdAt: current.createdAt,
        updatedAt: this.stamp(current.updatedAt),
        completedDates: input.repeat === 'none' ? [] : dates,
      };
      await this.write(client, 'ritm_tasks', next);
      return next;
    });
  }
  async deleteTask(id: string): Promise<Task> {
    return this.transaction(async (client) => {
      const task = await this.readTask(client, id, true);
      await this.write(client, 'ritm_deleted_tasks', task);
      await client.query('UPDATE ritm_deleted_tasks SET deleted_at = $1 WHERE id = $2', [
        this.clock(),
        id,
      ]);
      await client.query('DELETE FROM ritm_tasks WHERE id = $1', [id]);
      await client.query(
        'DELETE FROM ritm_deleted_tasks WHERE id NOT IN (SELECT id FROM ritm_deleted_tasks ORDER BY deleted_at DESC, id DESC LIMIT 50)',
      );
      return task;
    });
  }
  async restoreTask(snapshot: Task): Promise<Task> {
    return this.transaction(async (client) => {
      if (await this.read(client, 'ritm_tasks', snapshot.id, true))
        throw conflict('Задание уже восстановлено. Обновите список.');
      const deleted = await this.read<Task>(client, 'ritm_deleted_tasks', snapshot.id, true);
      if (!deleted || canonical(deleted) !== canonical(snapshot))
        throw conflict('Эту запись уже нельзя восстановить. Создайте новое задание.');
      const task = { ...deleted, updatedAt: this.stamp(deleted.updatedAt) };
      await this.write(client, 'ritm_tasks', task);
      await client.query('DELETE FROM ritm_deleted_tasks WHERE id = $1', [task.id]);
      return task;
    });
  }
  async createConversation() {
    return this.transaction((client) => this.newConversation(client));
  }
  async saveConversation(value: Conversation) {
    await this.transaction((client) => this.write(client, 'ritm_conversations', value));
  }
  async deleteConversation(id: string) {
    await this.transaction(async (client) => {
      await this.readConversation(client, id, true);
      const active = await client.query(
        "SELECT id FROM ritm_chat_requests WHERE conversation_id = $1 AND status = 'running' AND lease_expires_at > $2",
        [id, this.clock()],
      );
      if (active.rows.length) throw conflict('Дождитесь ответа помощника перед удалением диалога.');
      await client.query('DELETE FROM ritm_conversations WHERE id = $1', [id]);
    });
  }

  async request(id: string): Promise<RequestRecord | undefined> {
    const result = await this.pool.query(
      'SELECT fingerprint, conversation_id, status, lease_expires_at FROM ritm_chat_requests WHERE id = $1',
      [id],
    );
    const row = result.rows[0];
    if (!row || (row.status === 'running' && Number(row.lease_expires_at) <= this.clock()))
      return undefined;
    return {
      fingerprint: row.fingerprint,
      conversationId: row.conversation_id,
      status: row.status,
      ...(row.lease_expires_at === null ? {} : { leaseExpiresAt: Number(row.lease_expires_at) }),
    };
  }
  async startRequest(
    id: string,
    fingerprint: string,
    conversationId: string | null,
  ): Promise<Exclude<RequestClaim, void>> {
    return this.transaction(async (client) => {
      const now = this.clock();
      const existing = (
        await client.query(
          'SELECT fingerprint, conversation_id, status, lease_expires_at FROM ritm_chat_requests WHERE id = $1 FOR UPDATE',
          [id],
        )
      ).rows[0];
      if (existing) {
        if (existing.fingerprint !== fingerprint)
          throw conflict('Этот идентификатор запроса уже использован для другого сообщения.');
        if (existing.status === 'complete' && existing.conversation_id)
          return { completedConversationId: String(existing.conversation_id) };
        if (Number(existing.lease_expires_at) > now)
          throw conflict('Помощник уже обрабатывает этот запрос. Дождитесь ответа.');
      }
      if (conversationId) {
        const conversation = await this.readConversation(client, conversationId, true);
        if (conversation.messages.length >= 200)
          throw new AppError(
            400,
            'MESSAGE_LIMIT',
            'В этом диалоге уже 100 запросов. Начните новый диалог.',
          );
        const busy = await client.query(
          "SELECT id FROM ritm_chat_requests WHERE conversation_id = $1 AND status = 'running' AND lease_expires_at > $2 AND id <> $3",
          [conversationId, now, id],
        );
        if (busy.rows.length)
          throw conflict('В этом диалоге помощник уже отвечает. Дождитесь завершения.');
      }
      const leaseToken = randomUUID();
      await client.query(
        "INSERT INTO ritm_chat_requests (id, fingerprint, conversation_id, status, lease_token, lease_expires_at) VALUES ($1, $2, $3, 'running', $4, $5) ON CONFLICT (id) DO UPDATE SET status = 'running', lease_token = EXCLUDED.lease_token, lease_expires_at = EXCLUDED.lease_expires_at",
        [id, fingerprint, conversationId, leaseToken, now + this.requestLeaseMs],
      );
      return { leaseToken };
    });
  }
  async abandonRequest(id: string, leaseToken?: string) {
    if (!leaseToken) return;
    await this.transaction(async (client) => {
      await client.query(
        "DELETE FROM ritm_chat_requests WHERE id = $1 AND status = 'running' AND lease_token = $2",
        [id, leaseToken],
      );
    });
  }
  async finishChat(
    requestId: string,
    originalConversationId: string | undefined,
    userText: string,
    assistant: ChatMessage,
    leaseToken?: string,
  ): Promise<Conversation> {
    return this.transaction(async (client) => {
      const request = (
        await client.query(
          'SELECT conversation_id, status, lease_token, lease_expires_at FROM ritm_chat_requests WHERE id = $1 FOR UPDATE',
          [requestId],
        )
      ).rows[0];
      if (
        !request ||
        !leaseToken ||
        request.status !== 'running' ||
        request.lease_token !== leaseToken ||
        Number(request.lease_expires_at) <= this.clock() ||
        (request.conversation_id ?? undefined) !== originalConversationId
      ) {
        throw conflict(
          'Срок обработки запроса истёк или ответ уже сохранён. Обновите диалог и повторите.',
        );
      }
      const conversation = originalConversationId
        ? await this.readConversation(client, originalConversationId, true)
        : await this.newConversation(client);
      const user: ChatMessage = {
        id: randomUUID(),
        role: 'user',
        text: userText,
        createdAt: this.stamp(),
        proposals: [],
        steps: [],
      };
      conversation.messages.push(user, { ...assistant, createdAt: this.stamp(user.createdAt) });
      if (conversation.messages.length > 200)
        throw new AppError(
          400,
          'MESSAGE_LIMIT',
          'В этом диалоге уже 100 запросов. Начните новый диалог.',
        );
      if (conversation.messages.length === 2)
        conversation.title = userText.length > 50 ? `${userText.slice(0, 49)}…` : userText;
      conversation.updatedAt = this.stamp(conversation.updatedAt);
      await this.write(client, 'ritm_conversations', conversation);
      await client.query(
        "UPDATE ritm_chat_requests SET status = 'complete', conversation_id = $1, lease_token = NULL, lease_expires_at = NULL WHERE id = $2",
        [conversation.id, requestId],
      );
      return conversation;
    });
  }

  async proposalAction(
    action: 'apply' | 'undo' | 'reject',
    conversationId: string,
    messageId: string,
    ids: string[],
  ): Promise<ProposalResult> {
    return this.transaction(async (client) => {
      const conversation = await this.readConversation(client, conversationId, true);
      const message = conversation.messages.find(
        (item) => item.id === messageId && item.role === 'assistant',
      );
      if (!message) throw missing('Предложение');
      const selected = ids.map((id) => {
        const proposal = message.proposals.find((item) => item.id === id);
        if (!proposal) throw missing('Изменение');
        if (proposal.status !== (action === 'undo' ? 'applied' : 'pending'))
          throw conflict('Это предложение уже обработано. Обновите диалог.');
        return proposal;
      });
      if (new Set(selected.map((item) => item.taskId)).size !== selected.length)
        throw conflict('Выберите одно изменение для каждого задания.');
      if (action !== 'reject') {
        const settings = await this.readSettings(client);
        const changed: Task[] = [];
        for (const proposal of selected) {
          const current = await this.readTask(client, proposal.taskId, true);
          const expected = action === 'apply' ? proposal.before : proposal.after;
          if (
            current.updatedAt !== proposal.taskUpdatedAt ||
            !sameSchedule(schedule(current), expected) ||
            current.completed
          ) {
            throw conflict(
              action === 'undo'
                ? 'Задание изменилось после применения плана. Отмена не затронет новые изменения — обновите диалог.'
                : 'Расписание изменилось с момента ответа ИИ. Попросите помощника подготовить новый план.',
            );
          }
          if (current.kind === 'event' || current.repeat !== 'none')
            throw conflict('Встречи и повторяющиеся серии изменяйте в календаре вручную.');
          const after = action === 'apply' ? proposal.after : proposal.before;
          if (!validSchedule(after))
            throw new AppError(400, 'INVALID_SCHEDULE', 'Невозможно применить это время.');
          if (action === 'apply' && scheduleInPast(after, settings.timeZone))
            throw conflict(
              'Предложенное время уже прошло. Попросите помощника подготовить новый план.',
            );
          changed.push({ ...current, ...after, updatedAt: this.stamp(current.updatedAt) });
        }
        const changedIds = new Set(changed.map((task) => task.id));
        const finalTasks = (await this.listTasks(client))
          .filter((task) => !changedIds.has(task.id))
          .concat(changed);
        for (const next of changed) {
          if (!next.date || !next.time) continue;
          const start = minutes(next.time),
            end = start + next.duration;
          const overlap = finalTasks.some(
            (other) =>
              other.id !== next.id &&
              !other.completed &&
              !(other.completedDates ?? []).includes(next.date!) &&
              other.time &&
              occursOn(other, next.date!) &&
              start < minutes(other.time) + other.duration &&
              end > minutes(other.time),
          );
          if (overlap)
            throw conflict(
              `«${next.title}» пересекается с другой записью. Выберите другое время или попросите новый план.`,
            );
        }
        for (let index = 0; index < changed.length; index++) {
          await this.write(client, 'ritm_tasks', changed[index]);
          selected[index].taskUpdatedAt = changed[index].updatedAt;
        }
      }
      selected.forEach((proposal) => {
        proposal.status =
          action === 'apply' ? 'applied' : action === 'undo' ? 'undone' : 'rejected';
      });
      conversation.updatedAt = this.stamp(conversation.updatedAt);
      await this.write(client, 'ritm_conversations', conversation);
      return { tasks: await this.listTasks(client), conversation };
    });
  }

  async createSession(idHash: string, expiresAt: number) {
    await this.transaction(async (client) => {
      await client.query('DELETE FROM ritm_sessions WHERE expires_at <= $1', [this.clock()]);
      await client.query(
        'INSERT INTO ritm_sessions (id_hash, expires_at) VALUES ($1, $2) ON CONFLICT (id_hash) DO UPDATE SET expires_at = EXCLUDED.expires_at',
        [idHash, expiresAt],
      );
    });
  }
  async hasSession(idHash: string) {
    const result = await this.pool.query(
      'SELECT id_hash FROM ritm_sessions WHERE id_hash = $1 AND expires_at > $2',
      [idHash, this.clock()],
    );
    return result.rows.length > 0;
  }
  async deleteSession(idHash: string) {
    await this.transaction(async (client) => {
      await client.query('DELETE FROM ritm_sessions WHERE id_hash = $1', [idHash]);
    });
  }
  async consumeRateLimit(key: string, maximum: number, windowMs: number) {
    if (!Number.isInteger(maximum) || maximum < 1 || !Number.isFinite(windowMs) || windowMs <= 0)
      throw new Error('Invalid server rate-limit policy.');
    return this.transaction(async (client) => {
      const now = this.clock();
      await client.query('DELETE FROM ritm_rate_limits WHERE expires_at <= $1', [now]);
      const previous = (
        await client.query(
          'SELECT count, expires_at FROM ritm_rate_limits WHERE key = $1 FOR UPDATE',
          [key],
        )
      ).rows[0];
      const count = previous ? Number(previous.count) + 1 : 1;
      const expiresAt = previous ? Number(previous.expires_at) : now + windowMs;
      await client.query(
        'INSERT INTO ritm_rate_limits (key, count, expires_at) VALUES ($1, $2, $3) ON CONFLICT (key) DO UPDATE SET count = EXCLUDED.count, expires_at = EXCLUDED.expires_at',
        [key, Math.min(count, maximum + 1), expiresAt],
      );
      return {
        allowed: count <= maximum,
        retryAfterMs: count <= maximum ? 0 : Math.max(0, expiresAt - now),
      };
    });
  }
  async getServerSecret(name: string): Promise<string | null> {
    const result = await this.pool.query(
      'SELECT ciphertext FROM ritm_server_secrets WHERE name = $1',
      [name],
    );
    return result.rows[0]?.ciphertext ?? null;
  }
  async setServerSecret(name: string, ciphertext: string) {
    await this.transaction(async (client) => {
      await client.query(
        'INSERT INTO ritm_server_secrets (name, ciphertext) VALUES ($1, $2) ON CONFLICT (name) DO UPDATE SET ciphertext = EXCLUDED.ciphertext',
        [name, ciphertext],
      );
    });
  }
  async deleteServerSecret(name: string) {
    await this.transaction(async (client) => {
      await client.query('DELETE FROM ritm_server_secrets WHERE name = $1', [name]);
    });
  }
  async consumeServerSecret(name: string): Promise<string | null> {
    return this.transaction(async (client) => {
      const result = await client.query(
        'DELETE FROM ritm_server_secrets WHERE name = $1 RETURNING ciphertext',
        [name],
      );
      return result.rows[0]?.ciphertext ?? null;
    });
  }
  async acquireLease(name: string, ttlMs: number): Promise<string | null> {
    if (!Number.isFinite(ttlMs) || ttlMs <= 0) throw new Error('Invalid server lease duration.');
    return this.transaction(async (client) => {
      const now = this.clock();
      const previous = (
        await client.query('SELECT expires_at FROM ritm_leases WHERE name = $1 FOR UPDATE', [name])
      ).rows[0];
      if (previous && Number(previous.expires_at) > now) return null;
      const token = randomUUID();
      await client.query(
        'INSERT INTO ritm_leases (name, token, expires_at) VALUES ($1, $2, $3) ON CONFLICT (name) DO UPDATE SET token = EXCLUDED.token, expires_at = EXCLUDED.expires_at',
        [name, token, now + ttlMs],
      );
      return token;
    });
  }
  async releaseLease(name: string, token: string) {
    await this.transaction(async (client) => {
      await client.query('DELETE FROM ritm_leases WHERE name = $1 AND token = $2', [name, token]);
    });
  }
}
