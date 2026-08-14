/**
 * C12 DB Tests
 *
 * Tests: migrations loader, schema validation, migration idempotency.
 * Mocks: pg.Pool (no real PostgreSQL required).
 */

import * as fs from 'fs';
import * as path from 'path';
import { loadMigrations } from '../src/db/migrate';

// ── Migration loader tests ────────────────────────────────────────────────────

describe('Migration loader', () => {
  const MIGRATIONS_DIR = path.join(__dirname, '../src/db/migrations');

  test('DB-01: migrations directory exists', () => {
    expect(fs.existsSync(MIGRATIONS_DIR)).toBe(true);
  });

  test('DB-02: at least one migration file exists', () => {
    const migrations = loadMigrations(MIGRATIONS_DIR);
    expect(migrations.length).toBeGreaterThanOrEqual(1);
  });

  test('DB-03: migration files are numbered and sorted ascending', () => {
    const migrations = loadMigrations(MIGRATIONS_DIR);
    for (let i = 1; i < migrations.length; i++) {
      expect(migrations[i]!.version).toBeGreaterThan(migrations[i - 1]!.version);
    }
  });

  test('DB-04: migration 001 contains all required tables', () => {
    const migrations = loadMigrations(MIGRATIONS_DIR);
    const m001 = migrations.find(m => m.version === 1);
    expect(m001).toBeDefined();

    const requiredTables = [
      'schema_migrations', 'sync_state', 'blocks', 'transactions',
      'transaction_receipts', 'transaction_logs', 'decoded_events',
      'addresses', 'contracts', 'validators', 'validator_events',
      'staking_positions', 'staking_events', 'reward_vault_state',
      'reward_events', 'fee_distribution', 'governance_events',
    ];

    for (const table of requiredTables) {
      expect(m001!.sql).toContain(`CREATE TABLE IF NOT EXISTS ${table}`);
    }
  });

  test('DB-05: migration 001 contains required indexes', () => {
    const migrations = loadMigrations(MIGRATIONS_DIR);
    const m001 = migrations.find(m => m.version === 1)!;

    const requiredIndexes = [
      'idx_blocks_hash', 'idx_tx_from', 'idx_logs_topic0',
      'idx_validators_status', 'idx_fee_dist_block',
    ];

    for (const idx of requiredIndexes) {
      expect(m001.sql).toContain(idx);
    }
  });

  test('DB-06: migration uses ON CONFLICT DO NOTHING for version insert', () => {
    const migrations = loadMigrations(MIGRATIONS_DIR);
    const m001 = migrations.find(m => m.version === 1)!;
    expect(m001.sql).toContain('ON CONFLICT (version) DO NOTHING');
  });

  test('DB-07: migration uses IF NOT EXISTS for all tables', () => {
    const migrations = loadMigrations(MIGRATIONS_DIR);
    const m001 = migrations.find(m => m.version === 1)!;
    // All CREATE TABLE statements should use IF NOT EXISTS
    const tableStmts = m001.sql.match(/CREATE TABLE[^;]+;/g) ?? [];
    for (const stmt of tableStmts) {
      expect(stmt).toContain('IF NOT EXISTS');
    }
  });
});

// ── Mock pool migration runner ────────────────────────────────────────────────

describe('Migration runner (mocked pool)', () => {
  // We test the logic of runMigrations without a real DB

  test('DB-08: runMigrations applies unapplied migrations only', async () => {
    const calls: string[] = [];

    // Mock pool.query to simulate already-applied version 1
    const mockClient = {
      query: jest.fn(async (sql: string, params?: unknown[]) => {
        calls.push(typeof sql === 'string' ? sql.slice(0, 60) : '?');
        if (sql.includes('SELECT version FROM schema_migrations')) {
          return { rows: [{ version: 1 }] };  // version 1 already applied
        }
        return { rows: [] };
      }),
      release: jest.fn(),
    };

    const mockPool = {
      query: jest.fn(async (sql: string) => {
        if (sql.includes('SELECT version FROM schema_migrations')) {
          return { rows: [{ version: 1 }] };
        }
        return { rows: [] };
      }),
      connect: jest.fn(async () => mockClient),
    } as unknown as import('pg').Pool;

    const { runMigrations } = await import('../src/db/migrate');
    // Since version 1 is already applied, count should be 0
    const count = await runMigrations(mockPool);
    expect(count).toBe(0);
    expect(mockClient.query).not.toHaveBeenCalledWith(
      expect.stringContaining('CREATE TABLE IF NOT EXISTS blocks'), expect.anything()
    );
  });
});
