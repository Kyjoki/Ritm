import { DatabaseSync } from 'node:sqlite';
import { randomUUID } from 'node:crypto';
import { mkdirSync } from 'node:fs';
import { join } from 'node:path';
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
} from '../shared/types.ts';
import { AppError, conflict, missing } from './errors.ts';
import {
  financeEntryInputSchema,
  minutes,
  scheduleInPast,
  taskInputSchema,
  validSchedule,
} from './validation.ts';
import {
  assertWorkspaceStorage,
  assertFinanceStorage,
  assertTransferTask,
  assertTransferSnapshot,
  assertTransferConnection,
  googleTransferKey,
  type GoogleTransferReceipt,
} from './repository.ts';

export const defaultSettings: Settings = {
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

export function localDate(now: Date, timeZone: string): string {
  const parts = new Intl.DateTimeFormat('en', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(now);
  const get = (type: string) => parts.find((part) => part.type === type)!.value;
  return `${get('year')}-${get('month')}-${get('day')}`;
}

function schedule(task: Task): ScheduleTime {
  return { date: task.date, time: task.time, duration: task.duration };
}
function sameSchedule(a: ScheduleTime, b: ScheduleTime) {
  return a.date === b.date && a.time === b.time && a.duration === b.duration;
}

function occursOn(task: Task, date: string) {
  if (!task.date || date < task.date) return false;
  if (task.date === date) return true;
  if (task.repeat === 'daily') return true;
  if (task.repeat === 'weekly') {
    return (
      (Date.parse(`${date}T00:00:00Z`) - Date.parse(`${task.date}T00:00:00Z`)) % (7 * 86400000) ===
      0
    );
  }
  return task.repeat === 'monthly' && task.date.slice(8) === date.slice(8);
}

/** One personal workspace. Synchronous transactions never cross an await. */
export class Store {
  private db: DatabaseSync;
  private latestStamp = 0;
  constructor(dataDir: string, seed = true) {
    mkdirSync(dataDir, { recursive: true, mode: 0o700 });
    this.db = new DatabaseSync(join(dataDir, 'ritm.sqlite'));
    this.db.exec(`
      PRAGMA journal_mode=WAL;
      PRAGMA busy_timeout=5000;
      PRAGMA foreign_keys=ON;
      CREATE TABLE IF NOT EXISTS tasks (id TEXT PRIMARY KEY, json TEXT NOT NULL) STRICT;
      CREATE TABLE IF NOT EXISTS deleted_tasks (id TEXT PRIMARY KEY, json TEXT NOT NULL) STRICT;
      CREATE TABLE IF NOT EXISTS conversations (id TEXT PRIMARY KEY, json TEXT NOT NULL) STRICT;
      CREATE TABLE IF NOT EXISTS finance_entries (id TEXT PRIMARY KEY, json TEXT NOT NULL) STRICT;
      CREATE TABLE IF NOT EXISTS config (key TEXT PRIMARY KEY, json TEXT NOT NULL) STRICT;
      CREATE TABLE IF NOT EXISTS chat_requests (
        id TEXT PRIMARY KEY, fingerprint TEXT NOT NULL, conversation_id TEXT,
        status TEXT NOT NULL CHECK(status IN ('running','complete')),
        FOREIGN KEY(conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
      ) STRICT;
    `);
    // A process that stopped during a provider call never committed chat text.
    // A retry may now start again, while completed request IDs remain durable.
    this.db.exec("DELETE FROM chat_requests WHERE status='running'");
    if (!this.db.prepare("SELECT key FROM config WHERE key='initialized'").get()) {
      this.transaction(() => {
        this.writeConfig('settings', defaultSettings);
        if (seed) this.seed();
        this.writeConfig('initialized', true);
      });
    }
    this.transaction(() => {
      for (const table of ['tasks', 'deleted_tasks'] as const) {
        for (const row of this.db.prepare(`SELECT json FROM ${table}`).all()) {
          const task = JSON.parse(String(row.json)) as Task;
          if (!Array.isArray(task.completedDates))
            // Schema normalization must not prevent opening a legacy workspace
            // above the new byte budget: deletion remains available to recover.
            this.db
              .prepare(`UPDATE ${table} SET json=? WHERE id=?`)
              .run(JSON.stringify({ ...task, completedDates: [] }), task.id);
        }
      }
      this.writeConfig('schemaVersion', 2);
    });
  }
  close() {
    this.db.close();
  }
  stamp(previous?: string) {
    this.latestStamp = Math.max(
      Date.now(),
      this.latestStamp + 1,
      previous ? Date.parse(previous) + 1 : 0,
    );
    return new Date(this.latestStamp).toISOString();
  }
  transaction<T>(operation: () => T): T {
    this.db.exec('BEGIN IMMEDIATE');
    try {
      const result = operation();
      this.db.exec('COMMIT');
      return result;
    } catch (error) {
      this.db.exec('ROLLBACK');
      throw error;
    }
  }
  private read<T>(table: 'tasks' | 'conversations' | 'deleted_tasks', id: string): T | undefined {
    const row = this.db.prepare(`SELECT json FROM ${table} WHERE id=?`).get(id);
    return row ? (JSON.parse(String(row.json)) as T) : undefined;
  }
  private write<T extends { id: string }>(
    table: 'tasks' | 'conversations' | 'deleted_tasks',
    value: T,
  ) {
    // Synchronous prospective check: rejection occurs before any row changes.
    // Multi-row operations already run inside the existing SQLite transaction.
    if (table === 'tasks')
      assertWorkspaceStorage(
        this.tasks()
          .filter((task) => task.id !== value.id)
          .concat(value as unknown as Task),
        this.conversations(),
      );
    else if (table === 'conversations')
      assertWorkspaceStorage(
        this.tasks(),
        this.conversations()
          .filter((conversation) => conversation.id !== value.id)
          .concat(value as unknown as Conversation),
      );
    this.db
      .prepare(
        `INSERT INTO ${table}(id,json) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET json=excluded.json`,
      )
      .run(value.id, JSON.stringify(value));
  }
  private writeConfig(key: string, value: unknown) {
    this.db
      .prepare(
        'INSERT INTO config(key,json) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET json=excluded.json',
      )
      .run(key, JSON.stringify(value));
  }
  financeEntries(): FinanceEntry[] {
    return this.db
      .prepare('SELECT json FROM finance_entries')
      .all()
      .map((row) => JSON.parse(String(row.json)) as FinanceEntry)
      .sort((a, b) => {
        const aDate = 'date' in a ? a.date : a.asOf;
        const bDate = 'date' in b ? b.date : b.asOf;
        return bDate.localeCompare(aDate) || b.createdAt.localeCompare(a.createdAt);
      });
  }
  createFinanceEntry(input: FinanceEntryInput): FinanceEntry {
    const fields = financeEntryInputSchema.parse(input);
    return this.transaction(() => {
      const entries = this.financeEntries();
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
      this.db
        .prepare('INSERT INTO finance_entries (id,json) VALUES (?,?)')
        .run(entry.id, JSON.stringify(entry));
      return entry;
    });
  }
  updateFinanceEntry(
    id: string,
    input: FinanceEntryInput,
    expectedUpdatedAt: string,
  ): FinanceEntry {
    const fields = financeEntryInputSchema.parse(input);
    return this.transaction(() => {
      const row = this.db.prepare('SELECT json FROM finance_entries WHERE id=?').get(id);
      if (!row)
        throw new AppError(404, 'NOT_FOUND', 'Финансовая запись не найдена. Обновите страницу.');
      const current = JSON.parse(String(row.json)) as FinanceEntry;
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
        this.financeEntries()
          .filter((item) => item.id !== id)
          .concat(entry),
      );
      this.db
        .prepare('UPDATE finance_entries SET json=? WHERE id=?')
        .run(JSON.stringify(entry), id);
      return entry;
    });
  }
  deleteFinanceEntry(id: string, expectedUpdatedAt: string): void {
    return this.transaction(() => {
      const row = this.db.prepare('SELECT json FROM finance_entries WHERE id=?').get(id);
      if (!row)
        throw new AppError(404, 'NOT_FOUND', 'Финансовая запись не найдена. Обновите страницу.');
      const current = JSON.parse(String(row.json)) as FinanceEntry;
      if (current.updatedAt !== expectedUpdatedAt)
        throw conflict('Финансовая запись изменилась. Обновите данные и повторите действие.');
      this.db.prepare('DELETE FROM finance_entries WHERE id=?').run(id);
    });
  }
  tasks(): Task[] {
    return this.db
      .prepare('SELECT json FROM tasks')
      .all()
      .map((row) => JSON.parse(String(row.json)) as Task)
      .sort(
        (a, b) =>
          (a.date ?? '9999').localeCompare(b.date ?? '9999') ||
          (a.time ?? '99').localeCompare(b.time ?? '99') ||
          a.createdAt.localeCompare(b.createdAt),
      );
  }
  task(id: string): Task {
    return (
      this.read<Task>('tasks', id) ??
      (() => {
        throw missing('Задание');
      })()
    );
  }
  settings(): Settings {
    const row = this.db.prepare("SELECT json FROM config WHERE key='settings'").get()!;
    return JSON.parse(String(row.json)) as Settings;
  }
  updateSettings(patch: Partial<Settings>): Settings {
    const value = { ...this.settings(), ...patch };
    if (minutes(value.workDayStart) >= minutes(value.workDayEnd)) {
      throw new AppError(
        400,
        'INVALID_WORKDAY',
        'Начало рабочего дня должно быть раньше окончания.',
      );
    }
    this.writeConfig('settings', value);
    return value;
  }
  createTask(input: TaskInput): Task {
    if (this.tasks().length >= 2000)
      throw new AppError(400, 'TASK_LIMIT', 'Достигнут лимит 2000 задач. Удалите ненужные записи.');
    const now = this.stamp();
    const task: Task = {
      ...taskInputSchema.parse(input),
      id: randomUUID(),
      createdAt: now,
      updatedAt: now,
      completedDates: [],
    };
    this.write('tasks', task);
    return task;
  }
  updateTask(id: string, patch: Partial<TaskInput> & { occurrenceDate?: string }): Task {
    const current = this.task(id);
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
      if (!occursOn(current, occurrenceDate) || changes.completed === undefined) {
        throw new AppError(
          400,
          'INVALID_OCCURRENCE',
          'Укажите дату существующего повторения задачи.',
        );
      }
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
    this.write('tasks', next);
    return next;
  }
  private deleteTaskInside(id: string, assertActive = () => {}) {
    const task = this.task(id);
    assertActive();
    this.write('deleted_tasks', task);
    assertActive();
    this.db.prepare('DELETE FROM tasks WHERE id=?').run(id);
    // Keep a bounded undo journal; it never includes provider credentials.
    this.db.exec(
      'DELETE FROM deleted_tasks WHERE rowid NOT IN (SELECT rowid FROM deleted_tasks ORDER BY rowid DESC LIMIT 50)',
    );
    assertActive();
    return task;
  }
  deleteTask(id: string): Task {
    return this.transaction(() => this.deleteTaskInside(id));
  }
  private transferReceipts() {
    return this.db
      .prepare("SELECT key,json FROM config WHERE key LIKE 'google-transfer:%'")
      .all()
      .map((row) => ({
        key: String(row.key),
        receipt: JSON.parse(String(row.json)) as GoogleTransferReceipt,
      }));
  }
  private transferReceipt(id: string): GoogleTransferReceipt | undefined {
    const row = this.db.prepare('SELECT json FROM config WHERE key=?').get(googleTransferKey(id));
    return row ? (JSON.parse(String(row.json)) as GoogleTransferReceipt) : undefined;
  }
  googleTransfer(id: string) {
    return this.transferReceipt(id);
  }
  beginGoogleTransfer(
    id: string,
    connectionIdentity: string,
    assertActive = () => {},
  ): GoogleTransferReceipt {
    return this.transaction(() => {
      const current = this.read<Task>('tasks', id),
        existing = this.transferReceipt(id);
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
      const task = this.task(id),
        timeZone = this.settings().timeZone;
      assertTransferTask(task);
      if (existing) {
        assertTransferSnapshot(task, existing, timeZone);
        assertTransferConnection(existing, connectionIdentity);
        return existing;
      }
      if (this.transferReceipts().filter((row) => row.receipt.status === 'pending').length >= 1000)
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
      this.writeConfig(googleTransferKey(id), receipt);
      assertActive();
      return receipt;
    });
  }
  markGoogleTransferAttempt(id: string, assertActive = () => {}): GoogleTransferReceipt {
    return this.transaction(() => {
      const receipt = this.transferReceipt(id);
      if (!receipt) throw conflict('Запрос переноса не найден. Начните заново.');
      if (receipt.status === 'complete') return receipt;
      assertTransferSnapshot(this.read<Task>('tasks', id), receipt, this.settings().timeZone);
      const attempted = { ...receipt, attempted: true };
      assertActive();
      this.writeConfig(googleTransferKey(id), attempted);
      assertActive();
      return attempted;
    });
  }
  finishGoogleTransfer(
    id: string,
    event: GoogleCalendarEvent,
    connectionIdentity: string,
    assertActive = () => {},
  ): GoogleTransferResult {
    return this.transaction(() => {
      const receipt = this.transferReceipt(id),
        task = this.read<Task>('tasks', id);
      if (!receipt)
        throw conflict('Запрос переноса не найден. Запись Ritm сохранена; начните заново.');
      assertTransferConnection(receipt, connectionIdentity);
      if (receipt.status === 'complete') {
        if (task) throw conflict('Перенесённая запись восстановлена. Обновите календарь.');
        return receipt.result;
      }
      assertTransferSnapshot(task, receipt, this.settings().timeZone);
      assertActive();
      this.deleteTaskInside(id, assertActive);
      const completed = this.transferReceipts().filter((row) => row.receipt.status === 'complete');
      const lastStamp = completed.reduce(
        (max, row) => Math.max(max, Date.parse(row.receipt.completedAt!)),
        0,
      );
      const result: GoogleTransferResult = { event, transferredTaskId: id };
      const saved: GoogleTransferReceipt = {
        ...receipt,
        status: 'complete',
        result,
        completedAt: new Date(Math.max(Date.now(), lastStamp + 1)).toISOString(),
      };
      assertActive();
      this.writeConfig(googleTransferKey(id), saved);
      const rows = this.transferReceipts();
      const complete = rows
        .filter((row) => row.receipt.status === 'complete')
        .sort((a, b) => b.receipt.completedAt!.localeCompare(a.receipt.completedAt!));
      for (const row of complete.slice(100)) {
        assertActive();
        this.db.prepare('DELETE FROM config WHERE key=?').run(row.key);
      }
      assertActive();
      return result;
    });
  }
  cancelGoogleTransfer(id: string, snapshot: Task, assertActive = () => {}) {
    return this.transaction(() => {
      const receipt = this.transferReceipt(id);
      if (receipt?.status === 'pending' && receipt.task.updatedAt === snapshot.updatedAt) {
        assertActive();
        this.db.prepare('DELETE FROM config WHERE key=?').run(googleTransferKey(id));
        assertActive();
      }
    });
  }
  restoreTask(snapshot: Task): Task {
    return this.transaction(() => {
      if (this.read('tasks', snapshot.id))
        throw conflict('Задание уже восстановлено. Обновите список.');
      const deleted = this.read<Task>('deleted_tasks', snapshot.id);
      if (!deleted || JSON.stringify(deleted) !== JSON.stringify(snapshot)) {
        throw conflict('Эту запись уже нельзя восстановить. Создайте новое задание.');
      }
      if (this.tasks().length >= 2000)
        throw new AppError(
          400,
          'TASK_LIMIT',
          'Достигнут лимит 2000 задач. Удалите ненужные записи.',
        );
      const task = { ...deleted, updatedAt: this.stamp(deleted.updatedAt) };
      this.write('tasks', task);
      this.db.prepare('DELETE FROM deleted_tasks WHERE id=?').run(task.id);
      return task;
    });
  }
  conversations(): Conversation[] {
    return this.db
      .prepare('SELECT json FROM conversations')
      .all()
      .map((row) => JSON.parse(String(row.json)) as Conversation)
      .sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
  }
  conversation(id: string): Conversation {
    return (
      this.read<Conversation>('conversations', id) ??
      (() => {
        throw missing('Диалог');
      })()
    );
  }
  createConversation(): Conversation {
    if (this.conversations().length >= 100)
      throw new AppError(
        400,
        'CONVERSATION_LIMIT',
        'Удалите ненужные диалоги, чтобы начать новый.',
      );
    const now = this.stamp();
    const value: Conversation = {
      id: randomUUID(),
      title: 'Новый диалог',
      messages: [],
      createdAt: now,
      updatedAt: now,
    };
    this.write('conversations', value);
    return value;
  }
  deleteConversation(id: string) {
    this.conversation(id);
    this.db.prepare('DELETE FROM conversations WHERE id=?').run(id);
  }
  saveConversation(value: Conversation) {
    this.write('conversations', value);
  }
  bootstrap(aiStatus: Bootstrap['aiStatus']): Bootstrap {
    return {
      tasks: this.tasks(),
      settings: this.settings(),
      conversations: this.conversations(),
      aiStatus,
    };
  }
  request(
    id: string,
  ): { fingerprint: string; conversationId: string | null; status: string } | undefined {
    const row = this.db
      .prepare('SELECT fingerprint,conversation_id,status FROM chat_requests WHERE id=?')
      .get(id);
    return row
      ? {
          fingerprint: String(row.fingerprint),
          conversationId: row.conversation_id ? String(row.conversation_id) : null,
          status: String(row.status),
        }
      : undefined;
  }
  startRequest(id: string, fingerprint: string, conversationId: string | null) {
    this.db
      .prepare(
        "INSERT INTO chat_requests(id,fingerprint,conversation_id,status) VALUES(?,?,?,'running')",
      )
      .run(id, fingerprint, conversationId);
  }
  abandonRequest(id: string) {
    this.db.prepare("DELETE FROM chat_requests WHERE id=? AND status='running'").run(id);
  }
  finishChat(
    requestId: string,
    originalConversationId: string | undefined,
    userText: string,
    assistant: ChatMessage,
  ): Conversation {
    return this.transaction(() => {
      const conversation = originalConversationId
        ? this.conversation(originalConversationId)
        : this.createConversation();
      const user: ChatMessage = {
        id: randomUUID(),
        role: 'user',
        text: userText,
        createdAt: this.stamp(),
        proposals: [],
        steps: [],
      };
      conversation.messages.push(user, { ...assistant, createdAt: this.stamp() });
      if (conversation.messages.length > 200)
        throw new AppError(
          400,
          'MESSAGE_LIMIT',
          'В этом диалоге уже 100 запросов. Начните новый диалог.',
        );
      if (conversation.messages.length === 2)
        conversation.title = userText.length > 50 ? `${userText.slice(0, 49)}…` : userText;
      conversation.updatedAt = this.stamp(conversation.updatedAt);
      this.saveConversation(conversation);
      this.db
        .prepare("UPDATE chat_requests SET status='complete',conversation_id=? WHERE id=?")
        .run(conversation.id, requestId);
      return conversation;
    });
  }

  proposalAction(
    action: 'apply' | 'undo' | 'reject',
    conversationId: string,
    messageId: string,
    ids: string[],
  ): ProposalResult {
    return this.transaction(() => {
      const conversation = this.conversation(conversationId);
      const message = conversation.messages.find(
        (item) => item.id === messageId && item.role === 'assistant',
      );
      if (!message) throw missing('Предложение');
      const selected = ids.map((id) => {
        const proposal = message.proposals.find((item) => item.id === id);
        if (!proposal) throw missing('Изменение');
        if (proposal.status !== (action === 'undo' ? 'applied' : 'pending')) {
          throw conflict('Это предложение уже обработано. Обновите диалог.');
        }
        return proposal;
      });
      if (new Set(selected.map((proposal) => proposal.taskId)).size !== selected.length) {
        throw conflict('Выберите одно изменение для каждого задания.');
      }
      if (action !== 'reject') {
        const changed = selected.map((proposal) => {
          const current = this.task(proposal.taskId);
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
          if (current.kind === 'event' || current.repeat !== 'none') {
            throw conflict('Встречи и повторяющиеся серии изменяйте в календаре вручную.');
          }
          const after = action === 'apply' ? proposal.after : proposal.before;
          if (!validSchedule(after))
            throw new AppError(400, 'INVALID_SCHEDULE', 'Невозможно применить это время.');
          if (action === 'apply' && scheduleInPast(after, this.settings().timeZone)) {
            throw conflict(
              'Предложенное время уже прошло. Попросите помощника подготовить новый план.',
            );
          }
          return { ...current, ...after, updatedAt: this.stamp(current.updatedAt) };
        });
        const changedIds = new Set(changed.map((task) => task.id));
        const finalTasks = this.tasks()
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
        changed.forEach((task, index) => {
          this.write('tasks', task);
          selected[index].taskUpdatedAt = task.updatedAt;
        });
      }
      selected.forEach((proposal) => {
        proposal.status =
          action === 'apply' ? 'applied' : action === 'undo' ? 'undone' : 'rejected';
      });
      conversation.updatedAt = this.stamp(conversation.updatedAt);
      this.saveConversation(conversation);
      return { tasks: this.tasks(), conversation };
    });
  }

  private seed() {
    const today = localDate(new Date(), defaultSettings.timeZone);
    const yesterday = new Date(`${today}T12:00:00Z`);
    yesterday.setUTCDate(yesterday.getUTCDate() - 1);
    const common: TaskInput = {
      title: '',
      description: '',
      date: today,
      time: null,
      duration: 30,
      priority: 'normal',
      repeat: 'none',
      kind: 'task',
      completed: false,
    };
    const examples: Partial<TaskInput>[] = [
      {
        title: 'Отправить отчёт по проекту',
        description: 'Итоги недели и планы следующего этапа.',
        time: '09:30',
        completed: true,
      },
      {
        title: 'Созвон с командой',
        description: 'Обсудить прототип Ritm.',
        time: '11:00',
        duration: 45,
        kind: 'event',
      },
      { title: 'Записаться к стоматологу', time: '13:00' },
      {
        title: 'Презентация для клиента',
        description: 'Проверить слайды и подготовить демонстрацию.',
        time: '15:00',
        duration: 60,
        priority: 'high',
      },
      { title: 'Купить продукты', time: '18:30' },
      { title: 'Обновить резюме', date: null, duration: 60 },
      {
        title: 'Оплатить интернет',
        date: yesterday.toISOString().slice(0, 10),
        priority: 'high',
        duration: 10,
      },
    ];
    examples.forEach((input) => this.createTask({ ...common, ...input }));
  }
}
