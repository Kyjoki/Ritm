import pg, { type Pool as PgPool, type PoolClient } from 'pg';
import { postgresConnectionString } from './postgres-connection.ts';
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
  GoogleCalendarEvent,
  GoogleTransferResult,
  FinanceEntry,
  FinanceEntryInput,
  Habit,
  HabitInput,
  WorkoutDoc,
  WorkoutKind,
  WorkoutsSnapshot,
} from '../shared/types.ts';
import { AppError, conflict, missing } from './errors.ts';
import {
  financeEntryInputSchema,
  habitInputSchema,
  minutes,
  scheduleInPast,
  taskInputSchema,
  validSchedule,
} from './validation.ts';
import type {
  RequestClaim,
  RequestRecord,
  RuntimeStateRepository,
  WorkspaceRepository,
} from './repository.ts';
import {
  assertWorkspaceStorage,
  assertFinanceStorage,
  assertFinanceAccountDeletion,
  assertHabitStorage,
  assertTransferTask,
  assertTransferSnapshot,
  assertTransferConnection,
  googleTransferKey,
  type GoogleTransferReceipt,
} from './repository.ts';
import {
  assertHabitDay,
  assertHabitProgress,
  assertHabitVersion,
  habitProgress,
  updateHabitDefinition,
  updateHabitProgress,
} from './habits.ts';
import { localDate } from './store.ts';
import { assertWorkoutDelete, assertWorkoutPut } from './workouts.ts';

const { Pool } = pg;
type Connection = Pick<PgPool | PoolClient, 'query'>;
type EntityTable =
  'ritm_tasks' | 'ritm_deleted_tasks' | 'ritm_conversations' | 'ritm_finance_entries';
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
            connectionString: postgresConnectionString(connection),
            max: 3,
            idleTimeoutMillis: 10_000,
            connectionTimeoutMillis: 10_000,
            statement_timeout: 15_000,
            lock_timeout: 5_000,
            query_timeout: 16_000,
          })
        : connection;
    this.ownsPool = options.ownsPool ?? typeof connection === 'string';
    this.clock = options.now ?? Date.now;
    this.requestLeaseMs = options.requestLeaseMs ?? 180_000;
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
      // Neon PgBouncer does not preserve these startup parameters. Apply them
      // to the transaction before taking any shared workspace locks.
      await client.query("SET LOCAL statement_timeout = '15s'");
      await client.query("SET LOCAL lock_timeout = '5s'");
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
    // Every active write is prospective and inside the shared workspace lock.
    // Deleting records remains available even when legacy data exceeds the cap.
    if (table === 'ritm_tasks')
      assertWorkspaceStorage(
        (await this.listTasks(client))
          .filter((task) => task.id !== value.id)
          .concat(value as unknown as Task),
        await this.listConversations(client),
      );
    else if (table === 'ritm_conversations')
      assertWorkspaceStorage(
        await this.listTasks(client),
        (await this.listConversations(client))
          .filter((conversation) => conversation.id !== value.id)
          .concat(value as unknown as Conversation),
      );
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
  private async listFinanceEntries(client: Connection): Promise<FinanceEntry[]> {
    const result = await client.query('SELECT json FROM ritm_finance_entries');
    return result.rows
      .map((row) => decoded<FinanceEntry>(row.json))
      .sort((a, b) => {
        const aDate = 'date' in a ? a.date : a.asOf;
        const bDate = 'date' in b ? b.date : b.asOf;
        return bDate.localeCompare(aDate) || b.createdAt.localeCompare(a.createdAt);
      });
  }
  private async listHabits(client: Connection): Promise<Habit[]> {
    const result = await client.query("SELECT json FROM ritm_config WHERE key = 'habits'");
    return result.rows[0] ? decoded<Habit[]>(result.rows[0].json) : [];
  }
  private async writeHabits(client: Connection, habits: Habit[]) {
    assertHabitStorage(habits);
    await client.query(
      "INSERT INTO ritm_config(key,json) VALUES('habits',$1::jsonb) ON CONFLICT(key) DO UPDATE SET json=EXCLUDED.json",
      [JSON.stringify(habits)],
    );
  }
  async habits(): Promise<Habit[]> {
    return this.listHabits(this.pool);
  }
  async createHabit(input: HabitInput): Promise<Habit> {
    const fields = habitInputSchema.parse(input);
    return this.transaction(async (client) => {
      const habits = await this.listHabits(client);
      if (habits.length >= 100)
        throw new AppError(400, 'HABIT_LIMIT', 'Достигнут предел в 100 привычек.');
      const now = this.stamp();
      const habit: Habit = {
        ...fields,
        icon: fields.icon ?? 'sparkles',
        weekdays: fields.weekdays ?? [0, 1, 2, 3, 4, 5, 6],
        target: fields.target ?? null,
        unit: fields.unit ?? '',
        archived: fields.archived ?? false,
        id: randomUUID(),
        startDate: localDate(new Date(this.clock()), (await this.readSettings(client)).timeZone),
        completedDates: [],
        progressByDate: {},
        achievements: [],
        createdAt: now,
        updatedAt: now,
      };
      await this.writeHabits(client, habits.concat(habit));
      return habit;
    });
  }
  async updateHabit(id: string, input: HabitInput, expectedUpdatedAt: string): Promise<Habit> {
    const fields = habitInputSchema.parse(input);
    return this.transaction(async (client) => {
      const habits = await this.listHabits(client);
      const current = habits.find((habit) => habit.id === id);
      if (!current) throw new AppError(404, 'NOT_FOUND', 'Привычка не найдена. Обновите страницу.');
      assertHabitVersion(current, expectedUpdatedAt);
      const habit = {
        ...updateHabitDefinition(
          current,
          fields,
          localDate(new Date(this.clock()), (await this.readSettings(client)).timeZone),
        ),
        updatedAt: this.stamp(current.updatedAt),
      };
      await this.writeHabits(
        client,
        habits.map((item) => (item.id === id ? habit : item)),
      );
      return habit;
    });
  }
  async setHabitDay(
    id: string,
    date: string,
    completed: boolean,
    expectedUpdatedAt: string,
  ): Promise<Habit> {
    return this.transaction(async (client) => {
      const habits = await this.listHabits(client);
      const current = habits.find((habit) => habit.id === id);
      if (!current) throw new AppError(404, 'NOT_FOUND', 'Привычка не найдена. Обновите страницу.');
      assertHabitVersion(current, expectedUpdatedAt);
      const eligible = assertHabitDay(
        current,
        date,
        localDate(new Date(this.clock()), (await this.readSettings(client)).timeZone),
        completed,
      );
      if (current.completedDates.includes(date) === completed) return current;
      const updated = updateHabitProgress(eligible, date, completed ? (current.target ?? 1) : 0);
      const habit = {
        ...updated,
        updatedAt: this.stamp(current.updatedAt),
      };
      await this.writeHabits(
        client,
        habits.map((item) => (item.id === id ? habit : item)),
      );
      return habit;
    });
  }
  async setHabitProgress(
    id: string,
    date: string,
    count: number,
    expectedUpdatedAt: string,
  ): Promise<Habit> {
    return this.transaction(async (client) => {
      const habits = await this.listHabits(client);
      const current = habits.find((habit) => habit.id === id);
      if (!current) throw new AppError(404, 'NOT_FOUND', 'Привычка не найдена. Обновите страницу.');
      assertHabitVersion(current, expectedUpdatedAt);
      const eligible = assertHabitDay(
        current,
        date,
        localDate(new Date(this.clock()), (await this.readSettings(client)).timeZone),
        count > 0,
      );
      assertHabitProgress(current, count);
      if (habitProgress(current, date) === count) return current;
      const habit = {
        ...updateHabitProgress(eligible, date, count),
        updatedAt: this.stamp(current.updatedAt),
      };
      await this.writeHabits(
        client,
        habits.map((item) => (item.id === id ? habit : item)),
      );
      return habit;
    });
  }
  async deleteHabit(id: string, expectedUpdatedAt: string): Promise<void> {
    await this.transaction(async (client) => {
      const habits = await this.listHabits(client);
      const current = habits.find((habit) => habit.id === id);
      if (!current) throw new AppError(404, 'NOT_FOUND', 'Привычка не найдена. Обновите страницу.');
      assertHabitVersion(current, expectedUpdatedAt);
      await this.writeHabits(
        client,
        habits.filter((habit) => habit.id !== id),
      );
    });
  }
  private workoutTable(kind: WorkoutKind) {
    return kind === 'programs' ? 'workout_programs' : 'workout_sessions';
  }
  private workoutFrom(row: Record<string, unknown>): WorkoutDoc {
    return {
      id: String(row.id),
      updatedAt: new Date(row.updated_at as string | Date).toISOString(),
      data: decoded<Record<string, unknown>>(row.data),
    };
  }
  private async workoutDocs(client: Connection, kind: WorkoutKind): Promise<WorkoutDoc[]> {
    const result = await client.query(
      `SELECT id, data, updated_at FROM ${this.workoutTable(kind)} ORDER BY updated_at DESC, id`,
    );
    return result.rows.map((row) => this.workoutFrom(row));
  }
  async workouts(): Promise<WorkoutsSnapshot> {
    return {
      programs: await this.workoutDocs(this.pool, 'programs'),
      sessions: await this.workoutDocs(this.pool, 'sessions'),
    };
  }
  private async lockedWorkout(
    client: Connection,
    kind: WorkoutKind,
    id: string,
  ): Promise<WorkoutDoc | undefined> {
    const result = await client.query(
      `SELECT id, data, updated_at FROM ${this.workoutTable(kind)} WHERE id = $1 FOR UPDATE`,
      [id],
    );
    return result.rows[0] ? this.workoutFrom(result.rows[0]) : undefined;
  }
  async putWorkout(
    kind: WorkoutKind,
    id: string,
    data: Record<string, unknown>,
    expectedUpdatedAt: string | null,
  ): Promise<WorkoutDoc> {
    return this.transaction(async (client) => {
      const table = this.workoutTable(kind);
      const current = await this.lockedWorkout(client, kind, id);
      const counted = await client.query(`SELECT count(*) AS n FROM ${table}`);
      assertWorkoutPut(current, expectedUpdatedAt, Number(counted.rows[0]?.n ?? 0), kind);
      const updatedAt = this.stamp(current?.updatedAt);
      await client.query(
        `INSERT INTO ${table} (id, data, updated_at) VALUES ($1, $2::jsonb, $3::timestamptz) ON CONFLICT (id) DO UPDATE SET data = EXCLUDED.data, updated_at = EXCLUDED.updated_at`,
        [id, JSON.stringify(data), updatedAt],
      );
      return { id, updatedAt, data };
    });
  }
  async deleteWorkout(kind: WorkoutKind, id: string, expectedUpdatedAt: string): Promise<void> {
    await this.transaction(async (client) => {
      assertWorkoutDelete(await this.lockedWorkout(client, kind, id), expectedUpdatedAt);
      await client.query(`DELETE FROM ${this.workoutTable(kind)} WHERE id = $1`, [id]);
    });
  }
  async financeEntries(): Promise<FinanceEntry[]> {
    return this.listFinanceEntries(this.pool);
  }
  async createFinanceEntry(input: FinanceEntryInput): Promise<FinanceEntry> {
    const fields = financeEntryInputSchema.parse(input);
    return this.transaction(async (client) => {
      const entries = await this.listFinanceEntries(client);
      if (
        fields.type === 'account' &&
        entries.some((entry) => entry.type === 'account' && entry.currency === fields.currency)
      )
        throw new AppError(
          409,
          'FINANCE_ACCOUNT_EXISTS',
          'Основной счёт в этой валюте уже есть. Обновите данные.',
        );
      if (entries.length >= 2000)
        throw new AppError(
          400,
          'FINANCE_LIMIT',
          'Достигнут предел финансовых записей. Удалите ненужные записи.',
        );
      const now = this.stamp();
      const entry: FinanceEntry = { ...fields, id: randomUUID(), createdAt: now, updatedAt: now };
      assertFinanceStorage(entries.concat(entry));
      await this.write(client, 'ritm_finance_entries', entry);
      return entry;
    });
  }
  async updateFinanceEntry(
    id: string,
    input: FinanceEntryInput,
    expectedUpdatedAt: string,
  ): Promise<FinanceEntry> {
    const fields = financeEntryInputSchema.parse(input);
    return this.transaction(async (client) => {
      const current = await this.read<FinanceEntry>(client, 'ritm_finance_entries', id, true);
      if (!current)
        throw new AppError(404, 'NOT_FOUND', 'Финансовая запись не найдена. Обновите страницу.');
      if (current.updatedAt !== expectedUpdatedAt)
        throw conflict('Финансовая запись изменилась. Обновите данные и повторите действие.');
      if (current.type !== fields.type)
        throw new AppError(400, 'FINANCE_TYPE_IMMUTABLE', 'Тип финансовой записи нельзя изменить.');
      if (fields.type === 'account' && current.currency !== fields.currency)
        throw new AppError(
          400,
          'FINANCE_ACCOUNT_CURRENCY',
          'Валюту основного счёта нельзя изменить.',
        );
      const entry: FinanceEntry = {
        ...fields,
        id,
        createdAt: current.createdAt,
        updatedAt: this.stamp(current.updatedAt),
      };
      assertFinanceStorage(
        (await this.listFinanceEntries(client)).filter((item) => item.id !== id).concat(entry),
      );
      await this.write(client, 'ritm_finance_entries', entry);
      return entry;
    });
  }
  async deleteFinanceEntry(id: string, expectedUpdatedAt: string): Promise<void> {
    await this.transaction(async (client) => {
      const current = await this.read<FinanceEntry>(client, 'ritm_finance_entries', id, true);
      if (!current)
        throw new AppError(404, 'NOT_FOUND', 'Финансовая запись не найдена. Обновите страницу.');
      if (current.updatedAt !== expectedUpdatedAt)
        throw conflict('Финансовая запись изменилась. Обновите данные и повторите действие.');
      assertFinanceAccountDeletion(await this.listFinanceEntries(client), id);
      await client.query('DELETE FROM ritm_finance_entries WHERE id = $1', [id]);
    });
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
  private async deleteTaskInside(client: PoolClient, id: string, assertActive = () => {}) {
    const task = await this.readTask(client, id, true);
    assertActive();
    await this.write(client, 'ritm_deleted_tasks', task);
    assertActive();
    await client.query('UPDATE ritm_deleted_tasks SET deleted_at = $1 WHERE id = $2', [
      this.clock(),
      id,
    ]);
    assertActive();
    await client.query('DELETE FROM ritm_tasks WHERE id = $1', [id]);
    assertActive();
    await client.query(
      'DELETE FROM ritm_deleted_tasks WHERE id NOT IN (SELECT id FROM ritm_deleted_tasks ORDER BY deleted_at DESC, id DESC LIMIT 50)',
    );
    assertActive();
    return task;
  }
  async deleteTask(id: string): Promise<Task> {
    return this.transaction((client) => this.deleteTaskInside(client, id));
  }
  private async transferReceipt(
    client: Connection,
    id: string,
  ): Promise<GoogleTransferReceipt | undefined> {
    const result = await client.query('SELECT json FROM ritm_config WHERE key=$1', [
      googleTransferKey(id),
    ]);
    return result.rows[0] ? decoded<GoogleTransferReceipt>(result.rows[0].json) : undefined;
  }
  private async transferReceipts(client: Connection) {
    const result = await client.query(
      "SELECT key,json FROM ritm_config WHERE key LIKE 'google-transfer:%'",
    );
    return result.rows.map((row) => ({
      key: String(row.key),
      receipt: decoded<GoogleTransferReceipt>(row.json),
    }));
  }
  private async writeTransfer(client: Connection, id: string, receipt: GoogleTransferReceipt) {
    await client.query(
      'INSERT INTO ritm_config(key,json) VALUES($1,$2::jsonb) ON CONFLICT(key) DO UPDATE SET json=EXCLUDED.json',
      [googleTransferKey(id), JSON.stringify(receipt)],
    );
  }
  googleTransfer(id: string) {
    return this.transferReceipt(this.pool, id);
  }
  async beginGoogleTransfer(
    id: string,
    connectionIdentity: string,
    assertActive = () => {},
  ): Promise<GoogleTransferReceipt> {
    return this.transaction(async (client) => {
      const current = await this.read<Task>(client, 'ritm_tasks', id, true),
        existing = await this.transferReceipt(client, id);
      if (existing?.status === 'complete') {
        assertTransferConnection(existing, connectionIdentity);
        if (current)
          throw new AppError(
            409,
            'GOOGLE_TRANSFER_CHANGED',
            'Эту запись уже переносили в Google. Восстановленную копию Ritm нельзя перенести повторно.',
          );
        return existing;
      }
      const task =
          current ??
          (() => {
            throw missing('Задание');
          })(),
        timeZone = (await this.readSettings(client)).timeZone;
      assertTransferTask(task);
      if (existing) {
        assertTransferSnapshot(task, existing, timeZone);
        assertTransferConnection(existing, connectionIdentity);
        return existing;
      }
      if (
        (await this.transferReceipts(client)).filter((row) => row.receipt.status === 'pending')
          .length >= 1000
      )
        throw new AppError(
          400,
          'GOOGLE_TRANSFER_LIMIT',
          'Есть 1000 незавершённых переносов. Завершите синхронизацию существующих записей перед добавлением новых.',
        );
      const receipt: GoogleTransferReceipt = {
        status: 'pending',
        task,
        timeZone,
        attempted: false,
        connectionIdentity,
      };
      assertActive();
      await this.writeTransfer(client, id, receipt);
      assertActive();
      return receipt;
    });
  }
  async markGoogleTransferAttempt(
    id: string,
    assertActive = () => {},
  ): Promise<GoogleTransferReceipt> {
    return this.transaction(async (client) => {
      const receipt = await this.transferReceipt(client, id);
      if (!receipt) throw conflict('Запрос переноса не найден. Начните заново.');
      if (receipt.status === 'complete') return receipt;
      assertTransferSnapshot(
        await this.read<Task>(client, 'ritm_tasks', id, true),
        receipt,
        (await this.readSettings(client)).timeZone,
      );
      const attempted = { ...receipt, attempted: true };
      assertActive();
      await this.writeTransfer(client, id, attempted);
      assertActive();
      return attempted;
    });
  }
  async finishGoogleTransfer(
    id: string,
    event: GoogleCalendarEvent,
    connectionIdentity: string,
    assertActive = () => {},
  ): Promise<GoogleTransferResult> {
    return this.transaction(async (client) => {
      const receipt = await this.transferReceipt(client, id),
        task = await this.read<Task>(client, 'ritm_tasks', id, true);
      if (!receipt)
        throw conflict('Запрос переноса не найден. Запись Ritm сохранена; начните заново.');
      assertTransferConnection(receipt, connectionIdentity);
      if (receipt.status === 'complete') {
        if (task) throw conflict('Перенесённая запись восстановлена. Обновите календарь.');
        return receipt.result;
      }
      assertTransferSnapshot(task, receipt, (await this.readSettings(client)).timeZone);
      assertActive();
      await this.deleteTaskInside(client, id, assertActive);
      const completed = (await this.transferReceipts(client)).filter(
        (row) => row.receipt.status === 'complete',
      );
      const lastStamp = completed.reduce(
        (max, row) => Math.max(max, Date.parse(row.receipt.completedAt!)),
        0,
      );
      const result: GoogleTransferResult = { event, transferredTaskId: id };
      const saved: GoogleTransferReceipt = {
        ...receipt,
        status: 'complete',
        result,
        completedAt: new Date(Math.max(this.clock(), lastStamp + 1)).toISOString(),
      };
      assertActive();
      await this.writeTransfer(client, id, saved);
      const rows = await this.transferReceipts(client);
      const complete = rows
        .filter((row) => row.receipt.status === 'complete')
        .sort((a, b) => b.receipt.completedAt!.localeCompare(a.receipt.completedAt!));
      const remove = complete.slice(100).map((row) => row.key);
      if (remove.length) {
        assertActive();
        await client.query(
          `DELETE FROM ritm_config WHERE key IN (${remove.map((_, index) => '$' + (index + 1)).join(',')})`,
          remove,
        );
      }
      assertActive();
      return result;
    });
  }
  async cancelGoogleTransfer(id: string, snapshot: Task, assertActive = () => {}) {
    await this.transaction(async (client) => {
      const receipt = await this.transferReceipt(client, id);
      if (receipt?.status === 'pending' && receipt.task.updatedAt === snapshot.updatedAt) {
        assertActive();
        await client.query('DELETE FROM ritm_config WHERE key=$1', [googleTransferKey(id)]);
        assertActive();
      }
    });
  }
  async restoreTask(snapshot: Task): Promise<Task> {
    return this.transaction(async (client) => {
      if (await this.read(client, 'ritm_tasks', snapshot.id, true))
        throw conflict('Задание уже восстановлено. Обновите список.');
      const deleted = await this.read<Task>(client, 'ritm_deleted_tasks', snapshot.id, true);
      if (!deleted || canonical(deleted) !== canonical(snapshot))
        throw conflict('Эту запись уже нельзя восстановить. Создайте новое задание.');
      const count = await client.query('SELECT count(*) AS count FROM ritm_tasks');
      if (Number(count.rows[0].count) >= 2000)
        throw new AppError(
          400,
          'TASK_LIMIT',
          'Достигнут лимит 2000 задач. Удалите ненужные записи.',
        );
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
