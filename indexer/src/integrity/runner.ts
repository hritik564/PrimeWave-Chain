/**
 * PrimeWave Indexer — Integrity Check Runner (CLI)
 *
 * Usage:
 *   ts-node src/integrity/runner.ts
 */

import { createPool, setPool } from '../db/client';
import { RpcClient } from '../rpc';
import { runAllChecks } from './checks';
import { loadConfig } from '../config';

async function main(): Promise<void> {
  const config = loadConfig();
  const pool   = createPool(config.dbUrl, 1, 2);
  setPool(pool);

  const rpc    = new RpcClient({ url: config.rpcUrl });
  console.log('[integrity] Running all integrity checks...\n');

  const report = await runAllChecks(rpc, config.chainId);
  const passed  = report.filter(r => r.passed).length;
  const failed  = report.filter(r => !r.passed).length;

  console.log(`\n[integrity] Results: ${passed} passed, ${failed} failed`);

  await pool.end();
  process.exit(failed > 0 ? 1 : 0);
}

main().catch(err => {
  console.error('[integrity] Fatal:', err);
  process.exit(1);
});
