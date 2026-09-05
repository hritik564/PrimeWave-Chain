/**
 * PrimeWave Indexer — Main Entry Point
 *
 * Starts:
 *   1. Database migrations
 *   2. IndexerEngine (sync loop)
 *   3. API server (read-only REST)
 *
 * All configuration from environment variables. See src/config.ts.
 *
 * Usage:
 *   npm start
 *   OR  ts-node src/main.ts
 */

import { loadConfig } from './config';
import { createPool } from './db/client';
import { assertSchemaReady, runMigrations } from './db/migrate';
import { RpcClient } from './rpc';
import { IndexerEngine } from './indexer/engine';
import { startApiServer } from './api/server';

async function main(): Promise<void> {
  const config = loadConfig();

  console.log('[main] PrimeWave Indexer starting');
  console.log(`[main] Chain: ${config.chainId}  RPC: ${config.rpcUrl}`);

  // Initialise DB
  const pool = createPool(config.dbUrl, config.dbPoolMin, config.dbPoolMax);

  // Development owns the existing idempotent migration runner. Replit
  // production PostgreSQL schema changes are applied during Publish, so
  // production startup performs a read-only preflight instead of issuing DDL.
  if (process.env.NODE_ENV === 'production') {
    console.log('[main] Verifying published production database schema...');
    await assertSchemaReady(pool);
    console.log('[main] Production database schema verified');
  } else {
    console.log('[main] Running database migrations...');
    const migrated = await runMigrations(pool);
    console.log(`[main] Migrations complete (${migrated} applied)`);
  }

  // Verify chain ID
  const rpc       = new RpcClient({ url: config.rpcUrl, maxRetries: config.maxRetries, retryDelayMs: config.retryDelayMs });
  const chainId   = await rpc.chainId();
  if (chainId !== config.chainId) {
    throw new Error(`Chain ID mismatch: config says ${config.chainId}, RPC says ${chainId}`);
  }
  console.log(`[main] Chain ID confirmed: ${chainId}`);

  // Start indexer + API
  const engine = new IndexerEngine(rpc, config);
  startApiServer(config, engine);

  // Graceful shutdown
  let stopping = false;
  const shutdown = async () => {
    if (stopping) return;
    stopping = true;
    console.log('[main] Shutting down...');
    engine.stop();
    await pool.end();
    process.exit(0);
  };
  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);

  // Start sync loop (blocks until stopped)
  await engine.start();
}

main().catch(err => {
  console.error('[main] Fatal error:', err);
  process.exit(1);
});
