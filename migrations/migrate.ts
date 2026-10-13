import pg, { type Pool as PgPool } from 'pg';
import { readFile, readdir } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const { Pool } = pg;
const migrationDir = dirname(fileURLToPath(import.meta.url));

/** Explicit migration only: called by an operator after target/env verification. */
export async function migrate(pool: PgPool): Promise<string[]> {
  const files = (await readdir(migrationDir)).filter((name) => /^\d{3}-.+\.sql$/.test(name)).sort();
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query('SELECT pg_advisory_xact_lock($1)', [812015]);
    await client.query(
      'CREATE TABLE IF NOT EXISTS ritm_schema_migrations (version TEXT PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now())',
    );
    const applied = await client.query('SELECT version FROM ritm_schema_migrations');
    const known = new Set(applied.rows.map((row) => String(row.version)));
    const added: string[] = [];
    for (const name of files) {
      if (known.has(name)) continue;
      await client.query(await readFile(resolve(migrationDir, name), 'utf8'));
      await client.query('INSERT INTO ritm_schema_migrations (version) VALUES ($1)', [name]);
      added.push(name);
    }
    await client.query('COMMIT');
    return added;
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    throw error;
  } finally {
    client.release();
  }
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  if (!process.env.DATABASE_URL) {
    console.error(
      'DATABASE_URL не задан. Сначала выберите проект и проверьте серверное окружение.',
    );
    process.exitCode = 1;
  } else {
    const pool = new Pool({
      connectionString: process.env.DATABASE_URL,
      max: 1,
      connectionTimeoutMillis: 10_000,
    });
    try {
      const added = await migrate(pool);
      console.log(
        added.length
          ? `Миграции Ritm применены: ${added.join(', ')}`
          : 'Миграции Ritm уже применены.',
      );
    } catch {
      console.error(
        'Миграция Ritm не выполнена. Проверьте целевую базу, подключение и права; подробности соединения и секреты не выводятся.',
      );
      process.exitCode = 1;
    } finally {
      await pool.end();
    }
  }
}
