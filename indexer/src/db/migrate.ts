/**
 * PrimeWave Indexer — Database Migration Runner
 *
 * Reads migration files from src/db/migrations/*.sql (numbered ascending).
 * Applies only unapplied migrations. Safe to run multiple times.
 *
 * Usage:
 *   ts-node src/db/migrate.ts
 *   OR  node dist/db/migrate.js
 */

import * as fs from 'fs';
import * as path from 'path';
import { Pool } from 'pg';
import { assertDevelopmentDatabaseSafety } from '../startup-safety';

const MIGRATIONS_DIR = path.join(__dirname, 'migrations');

export interface Migration {
  version:  number;
  filename: string;
  sql:      string;
}

const REQUIRED_INDEXER_TABLES = [
  'schema_migrations',
  'sync_state',
  'blocks',
  'transactions',
  'transaction_receipts',
  'transaction_logs',
  'decoded_events',
  'addresses',
  'contracts',
  'validators',
  'validator_events',
  'staking_positions',
  'staking_events',
  'reward_vault_state',
  'reward_events',
  'fee_distribution',
  'governance_events',
] as const;

export function loadMigrations(dir: string = MIGRATIONS_DIR): Migration[] {
  if (!fs.existsSync(dir)) {
    throw new Error(`Migrations directory not found: ${dir}`);
  }
  const files = fs.readdirSync(dir)
    .filter(f => f.endsWith('.sql'))
    .sort();

  return files.map(filename => {
    const match = filename.match(/^(\d+)_/);
    if (!match) throw new Error(`Migration filename must start with a number: ${filename}`);
    const version = parseInt(match[1]!, 10);
    const sql = fs.readFileSync(path.join(dir, filename), 'utf-8');
    return { version, filename, sql };
  });
}

export async function runMigrations(pool: Pool, dir?: string): Promise<number> {
  const migrations = loadMigrations(dir);

  // Ensure schema_migrations table exists (idempotent)
  await pool.query(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      version     INTEGER PRIMARY KEY,
      applied_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);

  const applied = await pool.query<{ version: number }>(
    'SELECT version FROM schema_migrations ORDER BY version'
  );
  const appliedVersions = new Set(applied.rows.map(r => r.version));

  let count = 0;
  for (const migration of migrations) {
    if (appliedVersions.has(migration.version)) {
      console.log(`[migrate] Skip ${migration.filename} (already applied)`);
      continue;
    }

    console.log(`[migrate] Applying ${migration.filename}...`);
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query(migration.sql);
      await client.query(
        'INSERT INTO schema_migrations (version) VALUES ($1) ON CONFLICT DO NOTHING',
        [migration.version]
      );
      await client.query('COMMIT');
      count++;
      console.log(`[migrate] Applied ${migration.filename} ✓`);
    } catch (err) {
      await client.query('ROLLBACK');
      throw new Error(`Migration ${migration.filename} failed: ${(err as Error).message}`);
    } finally {
      client.release();
    }
  }

  return count;
}

/**
 * Production-safe schema check.
 *
 * Replit applies managed PostgreSQL schema changes during Publish. Production
 * startup must therefore not issue DDL; it only verifies that the published
 * C12 schema is present before the indexer begins serving traffic.
 */
export async function assertSchemaReady(pool: Pool): Promise<void> {
  const result = await pool.query<{ table_name: string }>(
    `SELECT table_name
       FROM information_schema.tables
      WHERE table_schema = 'public'
        AND table_name = ANY($1::text[])`,
    [REQUIRED_INDEXER_TABLES],
  );

  const present = new Set(result.rows.map(row => row.table_name));
  const missing = REQUIRED_INDEXER_TABLES.filter(table => !present.has(table));

  if (missing.length > 0) {
    throw new Error(
      `Production indexer schema is incomplete; missing tables: ${missing.join(', ')}`,
    );
  }
}

// ── CLI entry ─────────────────────────────────────────────────────────────────
if (require.main === module) {
  const dbUrl = process.env['INDEXER_DB_URL'];
  if (!dbUrl) {
    console.error('INDEXER_DB_URL env var required');
    process.exit(1);
  }
  if (process.env.NODE_ENV === 'production') {
    console.error('Direct migrations are disabled in production; apply schema changes through Publish.');
    process.exit(1);
  }
  try {
    assertDevelopmentDatabaseSafety(process.env);
  } catch (error) {
    console.error(`[migrate] ${(error as Error).message}`);
    process.exit(1);
  }
  const pool = new Pool({ connectionString: dbUrl });
  runMigrations(pool)
    .then(count => {
      console.log(`[migrate] Done. ${count} migration(s) applied.`);
      return pool.end();
    })
    .catch(err => {
      console.error('[migrate] Error:', err.message);
      process.exit(1);
    });
}
