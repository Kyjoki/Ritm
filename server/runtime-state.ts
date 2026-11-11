import { DatabaseSync } from 'node:sqlite';
import { mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { parseSessionClient } from './session-policy.ts';

export type Awaitable<T> = T | Promise<T>;
export type SessionClient = 'web' | 'web-remembered' | 'ios';
export interface SessionMeta {
  client: SessionClient;
  deviceName: string;
  createdAt: number;
  lastSeenAt: number;
  absoluteExpiresAt: number;
}
export interface SessionRecord extends SessionMeta {
  hash: string;
  expiresAt: number;
}
export interface RuntimeState {
  createSession(hash: string, expiresAt: number, meta?: SessionMeta): Awaitable<void>;
  hasSession(hash: string): Awaitable<boolean>;
  deleteSession(hash: string): Awaitable<void>;
  getSession(hash: string): Awaitable<SessionRecord | null>;
  listSessions(prefix: string): Awaitable<SessionRecord[]>;
  touchSession(hash: string, lastSeenAt: number, expiresAt: number): Awaitable<void>;
  deleteOtherSessions(prefix: string, keepHash: string): Awaitable<void>;
  consumeRateLimit(
    key: string,
    maximum: number,
    windowMs: number,
  ): Awaitable<{ allowed: boolean; retryAfterMs: number }>;
  getServerSecret(name: string): Awaitable<string | null>;
  setServerSecret(name: string, value: string): Awaitable<void>;
  deleteServerSecret(name: string): Awaitable<void>;
  consumeServerSecret(name: string): Awaitable<string | null>;
  acquireLease(name: string, ttlMs: number): Awaitable<string | null>;
  releaseLease(name: string, token: string): Awaitable<void>;
}

/** Local counterpart of the PostgreSQL shared authentication/secret state. */
export class SqliteRuntimeState implements RuntimeState {
  private db: DatabaseSync;
  constructor(dataDir: string) {
    mkdirSync(dataDir, { recursive: true, mode: 0o700 });
    this.db = new DatabaseSync(join(dataDir, 'runtime.sqlite'));
    this.db.exec(`PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000;
      CREATE TABLE IF NOT EXISTS sessions (hash TEXT PRIMARY KEY, expires INTEGER NOT NULL,
        client TEXT NOT NULL DEFAULT 'web', device_name TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL DEFAULT 0, last_seen_at INTEGER NOT NULL DEFAULT 0,
        absolute_expires INTEGER NOT NULL DEFAULT 0) STRICT;
      CREATE TABLE IF NOT EXISTS rate_limits (key TEXT PRIMARY KEY, count INTEGER NOT NULL, resets INTEGER NOT NULL) STRICT;
      CREATE TABLE IF NOT EXISTS secrets (name TEXT PRIMARY KEY, value TEXT NOT NULL) STRICT;
      CREATE TABLE IF NOT EXISTS leases (name TEXT PRIMARY KEY, token TEXT NOT NULL, expires INTEGER NOT NULL) STRICT;
    `);
    // Databases created before device sessions lack the new columns.
    const columns = new Set(
      this.db
        .prepare('PRAGMA table_info(sessions)')
        .all()
        .map((row) => String(row.name)),
    );
    const additions: Record<string, string> = {
      client: "TEXT NOT NULL DEFAULT 'web'",
      device_name: "TEXT NOT NULL DEFAULT ''",
      created_at: 'INTEGER NOT NULL DEFAULT 0',
      last_seen_at: 'INTEGER NOT NULL DEFAULT 0',
      absolute_expires: 'INTEGER NOT NULL DEFAULT 0',
    };
    for (const [name, definition] of Object.entries(additions))
      if (!columns.has(name)) this.db.exec(`ALTER TABLE sessions ADD COLUMN ${name} ${definition}`);
  }
  close() {
    this.db.close();
  }
  createSession(hash: string, expiresAt: number, meta?: SessionMeta) {
    const now = Date.now();
    this.db.prepare('DELETE FROM sessions WHERE expires<=?').run(now);
    this.db
      .prepare(
        `INSERT INTO sessions(hash,expires,client,device_name,created_at,last_seen_at,absolute_expires)
         VALUES(?,?,?,?,?,?,?)`,
      )
      .run(
        hash,
        expiresAt,
        meta?.client ?? 'web',
        meta?.deviceName ?? '',
        meta?.createdAt ?? now,
        meta?.lastSeenAt ?? now,
        meta?.absoluteExpiresAt ?? expiresAt,
      );
  }
  private record(row: Record<string, unknown>): SessionRecord {
    return {
      hash: String(row.hash),
      expiresAt: Number(row.expires),
      client: parseSessionClient(row.client),
      deviceName: String(row.device_name),
      createdAt: Number(row.created_at),
      lastSeenAt: Number(row.last_seen_at),
      absoluteExpiresAt: Number(row.absolute_expires) || Number(row.expires),
    };
  }
  getSession(hash: string) {
    const row = this.db
      .prepare('SELECT * FROM sessions WHERE hash=? AND expires>?')
      .get(hash, Date.now());
    return row ? this.record(row) : null;
  }
  listSessions(prefix: string) {
    return this.db
      .prepare(
        'SELECT * FROM sessions WHERE expires>? AND substr(hash,1,?)=? ORDER BY created_at DESC',
      )
      .all(Date.now(), prefix.length, prefix)
      .map((row) => this.record(row));
  }
  touchSession(hash: string, lastSeenAt: number, expiresAt: number) {
    this.db
      .prepare('UPDATE sessions SET last_seen_at=?, expires=? WHERE hash=?')
      .run(lastSeenAt, expiresAt, hash);
  }
  deleteOtherSessions(prefix: string, keepHash: string) {
    this.db
      .prepare('DELETE FROM sessions WHERE substr(hash,1,?)=? AND hash<>?')
      .run(prefix.length, prefix, keepHash);
  }
  hasSession(hash: string) {
    return Boolean(
      this.db.prepare('SELECT hash FROM sessions WHERE hash=? AND expires>?').get(hash, Date.now()),
    );
  }
  deleteSession(hash: string) {
    this.db.prepare('DELETE FROM sessions WHERE hash=?').run(hash);
  }
  consumeRateLimit(key: string, maximum: number, windowMs: number) {
    const now = Date.now();
    this.db.prepare('DELETE FROM rate_limits WHERE resets<=?').run(now);
    const row = this.db
      .prepare(
        `INSERT INTO rate_limits(key,count,resets) VALUES(?,1,?)
      ON CONFLICT(key) DO UPDATE SET count=count+1 RETURNING count,resets`,
      )
      .get(key, now + windowMs)!;
    return {
      allowed: Number(row.count) <= maximum,
      retryAfterMs: Math.max(0, Number(row.resets) - now),
    };
  }
  getServerSecret(name: string) {
    const row = this.db.prepare('SELECT value FROM secrets WHERE name=?').get(name);
    return row ? String(row.value) : null;
  }
  setServerSecret(name: string, value: string) {
    this.db
      .prepare(
        'INSERT INTO secrets(name,value) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value',
      )
      .run(name, value);
  }
  deleteServerSecret(name: string) {
    this.db.prepare('DELETE FROM secrets WHERE name=?').run(name);
  }
  consumeServerSecret(name: string) {
    const row = this.db.prepare('DELETE FROM secrets WHERE name=? RETURNING value').get(name);
    return row ? String(row.value) : null;
  }
  acquireLease(name: string, ttlMs: number) {
    const token = randomUUID(),
      now = Date.now();
    const row = this.db
      .prepare(
        `INSERT INTO leases(name,token,expires) VALUES(?,?,?)
      ON CONFLICT(name) DO UPDATE SET token=excluded.token, expires=excluded.expires WHERE leases.expires<=?
      RETURNING token`,
      )
      .get(name, token, now + ttlMs, now);
    return row ? String(row.token) : null;
  }
  releaseLease(name: string, token: string) {
    this.db.prepare('DELETE FROM leases WHERE name=? AND token=?').run(name, token);
  }
}
