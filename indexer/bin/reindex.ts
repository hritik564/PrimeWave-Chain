#!/usr/bin/env ts-node
/**
 * PrimeWave Indexer — Reindex Tool
 *
 * Safe administrative tool to reindex a specific block range.
 * For local/development use only. Never expose via API.
 *
 * Usage:
 *   ts-node bin/reindex.ts --from 0 --to 100
 *   ts-node bin/reindex.ts --from 500 --to 600 --verify
 *
 * What it does:
 *   1. Validates the range
 *   2. Removes existing data for those blocks (tx, receipts, logs, decoded events)
 *   3. Re-indexes from RPC
 *   4. Verifies resulting state if --verify flag is set
 *
 * What it does NOT do:
 *   - Drop the schema
 *   - Touch blocks outside the range
 *   - Run automatically (must be invoked explicitly)
 *
 * Production guard: refuses to run if PRIMEWAVE_ALLOW_REINDEX != 'yes'
 */

import { createPool, setPool } from '../src/db/client';
import { runMigrations } from '../src/db/migrate';
import { RpcClient } from '../src/rpc';
import { IndexerEngine } from '../src/indexer/engine';
import { runAllChecks } from '../src/integrity/checks';
import { loadConfig } from '../src/config';
import { Pool } from 'pg';

// ── CLI arg parsing ───────────────────────────────────────────────────────────

function parseArgs(): { from: number; to: number; verify: boolean } {
  const args = process.argv.slice(2);
  let from: number | null = null;
  let to:   number | null = null;
  let verify = false;

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--from' && args[i + 1]) {
      from = parseInt(args[++i]!, 10);
    } else if (args[i] === '--to' && args[i + 1]) {
      to = parseInt(args[++i]!, 10);
    } else if (args[i] === '--verify') {
      verify = true;
    }
  }

  if (from === null || isNaN(from) || from < 0) {
    console.error('Usage: reindex --from BLOCK --to BLOCK [--verify]');
    process.exit(1);
  }
  if (to === null || isNaN(to) || to < from) {
    console.error('--to must be >= --from');
    process.exit(1);
  }

  return { from, to, verify };
}

// ── Clear data for a block range ──────────────────────────────────────────────

async function clearRange(pool: Pool, fromBlock: number, toBlock: number): Promise<void> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    console.log(`[reindex] Clearing blocks ${fromBlock}..${toBlock}...`);

    // Order: decoded_events → transaction_logs → receipts → transactions → blocks
    // (respects FK cascade, but we delete explicitly for clarity)
    await client.query(
      `DELETE FROM decoded_events WHERE block_number BETWEEN $1 AND $2`, [fromBlock, toBlock]
    );
    await client.query(
      `DELETE FROM transaction_logs WHERE block_number BETWEEN $1 AND $2`, [fromBlock, toBlock]
    );
    await client.query(
      `DELETE FROM transaction_receipts WHERE block_number BETWEEN $1 AND $2`, [fromBlock, toBlock]
    );
    await client.query(
      `DELETE FROM transactions WHERE block_number BETWEEN $1 AND $2`, [fromBlock, toBlock]
    );
    await client.query(
      `DELETE FROM blocks WHERE number BETWEEN $1 AND $2`, [fromBlock, toBlock]
    );

    // Clear domain state derived only from this range
    await client.query(
      `DELETE FROM fee_distribution WHERE block_number BETWEEN $1 AND $2`, [fromBlock, toBlock]
    );
    await client.query(
      `DELETE FROM governance_events WHERE block_number BETWEEN $1 AND $2`, [fromBlock, toBlock]
    );
    await client.query(
      `DELETE FROM reward_events WHERE block_number BETWEEN $1 AND $2`, [fromBlock, toBlock]
    );
    await client.query(
      `DELETE FROM staking_events WHERE block_number BETWEEN $1 AND $2`, [fromBlock, toBlock]
    );
    await client.query(
      `DELETE FROM validator_events WHERE block_number BETWEEN $1 AND $2`, [fromBlock, toBlock]
    );
    await client.query(
      `DELETE FROM reward_vault_state WHERE block_number BETWEEN $1 AND $2`, [fromBlock, toBlock]
    );

    // Reset sync_state to one before fromBlock (if it was at or above fromBlock)
    await client.query(
      `UPDATE sync_state SET
         latest_block      = LEAST(latest_block, $1 - 1),
         latest_block_hash = CASE WHEN latest_block >= $1 THEN NULL ELSE latest_block_hash END,
         updated_at        = NOW()`,
      [fromBlock]
    );

    await client.query('COMMIT');
    console.log(`[reindex] Cleared ${fromBlock}..${toBlock}`);
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

// ── Main ──────────────────────────────────────────────────────────────────────

async function main(): Promise<void> {
  // Production guard
  if (process.env['PRIMEWAVE_ALLOW_REINDEX'] !== 'yes') {
    console.error(
      '[reindex] Refused: set PRIMEWAVE_ALLOW_REINDEX=yes to run reindex.\n' +
      '          This guard prevents accidental execution in production.'
    );
    process.exit(1);
  }

  const { from: fromBlock, to: toBlock, verify } = parseArgs();
  const config = loadConfig();

  console.log(`[reindex] PrimeWave Reindex Tool`);
  console.log(`[reindex] Range: blocks ${fromBlock}..${toBlock} (${toBlock - fromBlock + 1} blocks)`);

  const pool = createPool(config.dbUrl, 1, 3);
  setPool(pool);

  await runMigrations(pool);

  const rpc = new RpcClient({ url: config.rpcUrl });

  // Verify range exists on chain
  const headBlock = await rpc.getBlockNumber();
  if (toBlock > headBlock) {
    console.error(`[reindex] --to ${toBlock} exceeds chain head ${headBlock}`);
    await pool.end();
    process.exit(1);
  }

  // Confirm
  console.log(`[reindex] ⚠  This will DELETE and re-index blocks ${fromBlock}..${toBlock}.`);
  console.log(`[reindex] Proceeding in 3 seconds... (Ctrl+C to abort)`);
  await new Promise(r => setTimeout(r, 3000));

  // Clear
  await clearRange(pool, fromBlock, toBlock);

  // Re-index
  const engine = new IndexerEngine(rpc, config);
  const { indexed, errors } = await engine.indexRange(fromBlock, toBlock);

  console.log(`[reindex] Done. Indexed: ${indexed}, Errors: ${errors}`);

  // Optional integrity check
  if (verify) {
    console.log('[reindex] Running integrity checks...');
    const report = await runAllChecks(rpc, config.chainId);
    const failed = report.filter(r => !r.passed);
    if (failed.length > 0) {
      console.error(`[reindex] ✗ ${failed.length} integrity check(s) FAILED`);
      for (const f of failed) console.error(`  ${f.id}: ${f.details}`);
      await pool.end();
      process.exit(1);
    } else {
      console.log('[reindex] ✓ All integrity checks passed');
    }
  }

  await pool.end();
  process.exit(errors > 0 ? 1 : 0);
}

main().catch(err => {
  console.error('[reindex] Fatal:', err);
  process.exit(1);
});
