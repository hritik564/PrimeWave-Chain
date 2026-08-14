/**
 * PrimeWave Indexer — PostgreSQL Client
 *
 * Thin wrapper around node-postgres (pg) Pool.
 * All queries use parameterised SQL — no string interpolation of user data.
 */

import { Pool, PoolClient, QueryResult, QueryResultRow } from 'pg';

let _pool: Pool | null = null;

export function createPool(connectionString: string, min = 2, max = 10): Pool {
  _pool = new Pool({
    connectionString,
    min,
    max,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 5000,
  });

  _pool.on('error', (err) => {
    console.error('[db] Unexpected pool error:', err.message);
  });

  return _pool;
}

export function getPool(): Pool {
  if (!_pool) throw new Error('DB pool not initialised. Call createPool() first.');
  return _pool;
}

export async function query<R extends QueryResultRow = QueryResultRow>(
  sql: string,
  params?: unknown[]
): Promise<QueryResult<R>> {
  return getPool().query<R>(sql, params);
}

/** Run multiple queries in a single transaction. Rolls back on any error. */
export async function withTransaction<T>(
  fn: (client: PoolClient) => Promise<T>
): Promise<T> {
  const client = await getPool().connect();
  try {
    await client.query('BEGIN');
    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

/** Close all connections. Call on shutdown. */
export async function closePool(): Promise<void> {
  if (_pool) {
    await _pool.end();
    _pool = null;
  }
}

/** Replace the global pool — used in tests to inject a mock. */
export function setPool(pool: Pool): void {
  _pool = pool;
}
