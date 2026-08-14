/**
 * PrimeWave Indexer — Data Integrity Checks
 *
 * INDEX-1:  Indexed latest block exists on chain
 * INDEX-2:  Every indexed block's parent hash matches the previous block
 * INDEX-3:  All transactions belong to indexed blocks
 * INDEX-4:  All receipts belong to indexed transactions
 * INDEX-5:  All logs belong to indexed receipts (via tx_hash)
 * INDEX-6:  No duplicate transaction hashes
 * INDEX-7:  No duplicate logs (tx_hash, log_index)
 * INDEX-8:  No duplicate blocks (number)
 * INDEX-9:  Sync state matches actual DB
 * INDEX-10: Known contract events decode correctly
 * INDEX-11: 70/20/10 accounting: validatorShare + treasuryShare + burnShare == totalAmount
 * INDEX-12: RewardVault state: total_emitted <= total_funded
 * INDEX-13: Validator indexed state: at least one validator in DB if registry events exist
 */

import { query } from '../db/client';
import { RpcClient } from '../rpc';

export interface CheckResult {
  id:      string;
  name:    string;
  passed:  boolean;
  details: string;
  count?:  number;
}

export type IntegrityReport = CheckResult[];

export async function runAllChecks(
  rpc:     RpcClient,
  chainId: number,
  logFn:   (msg: string) => void = console.log
): Promise<IntegrityReport> {
  const results: CheckResult[] = [];
  const checks = [
    checkIndex1, checkIndex2, checkIndex3, checkIndex4, checkIndex5,
    checkIndex6, checkIndex7, checkIndex8, checkIndex9,
    checkIndex10, checkIndex11, checkIndex12, checkIndex13,
  ];

  for (const check of checks) {
    try {
      const result = await check(rpc, chainId);
      results.push(result);
      logFn(`${result.passed ? '✓' : '✗'} ${result.id}: ${result.name} — ${result.details}`);
    } catch (err) {
      results.push({
        id:      'ERROR',
        name:    check.name,
        passed:  false,
        details: `Check threw: ${(err as Error).message}`,
      });
    }
  }

  return results;
}

// ── Individual checks ─────────────────────────────────────────────────────────

async function checkIndex1(rpc: RpcClient, chainId: number): Promise<CheckResult> {
  const res = await query<{ latest_block: string }>(
    'SELECT latest_block FROM sync_state WHERE chain_id = $1', [chainId]
  );
  if (!res.rowCount || Number(res.rows[0]!.latest_block) < 0) {
    return { id: 'INDEX-1', name: 'Latest block exists on chain', passed: false, details: 'No sync state row' };
  }

  const indexed = Number(res.rows[0]!.latest_block);
  const block   = await rpc.getBlockByNumber(indexed);

  if (!block) {
    return { id: 'INDEX-1', name: 'Latest block exists on chain', passed: false, details: `Block ${indexed} not found on RPC` };
  }

  const dbBlock = await query<{ hash: string }>('SELECT hash FROM blocks WHERE number = $1', [indexed]);
  if (!dbBlock.rowCount) {
    return { id: 'INDEX-1', name: 'Latest block exists on chain', passed: false, details: `Block ${indexed} in sync_state but not in blocks table` };
  }

  const hashMatch = dbBlock.rows[0]!.hash === block.hash.toLowerCase();
  return {
    id: 'INDEX-1', name: 'Latest block exists on chain',
    passed: hashMatch,
    details: hashMatch ? `Block ${indexed} confirmed on chain` : `Hash mismatch at block ${indexed}`,
  };
}

async function checkIndex2(_rpc: RpcClient, _chainId: number): Promise<CheckResult> {
  // Check parent hash chain for all indexed blocks
  const res = await query<{ violations: string }>(
    `SELECT COUNT(*) AS violations FROM (
       SELECT b1.number
       FROM blocks b1
       JOIN blocks b0 ON b0.number = b1.number - 1
       WHERE b1.parent_hash <> b0.hash
     ) t`
  );
  const violations = Number(res.rows[0]?.violations ?? 0);
  return {
    id: 'INDEX-2', name: 'Block parent hash chain intact',
    passed: violations === 0,
    details: violations === 0 ? 'All parent hashes match' : `${violations} parent hash violation(s) found`,
    count: violations,
  };
}

async function checkIndex3(_rpc: RpcClient, _chainId: number): Promise<CheckResult> {
  const res = await query<{ orphans: string }>(
    `SELECT COUNT(*) AS orphans FROM transactions t
     WHERE NOT EXISTS (SELECT 1 FROM blocks b WHERE b.number = t.block_number)`
  );
  const orphans = Number(res.rows[0]?.orphans ?? 0);
  return {
    id: 'INDEX-3', name: 'All transactions belong to indexed blocks',
    passed: orphans === 0,
    details: orphans === 0 ? 'No orphan transactions' : `${orphans} transaction(s) without block`,
    count: orphans,
  };
}

async function checkIndex4(_rpc: RpcClient, _chainId: number): Promise<CheckResult> {
  const res = await query<{ orphans: string }>(
    `SELECT COUNT(*) AS orphans FROM transaction_receipts r
     WHERE NOT EXISTS (SELECT 1 FROM transactions t WHERE t.hash = r.tx_hash)`
  );
  const orphans = Number(res.rows[0]?.orphans ?? 0);
  return {
    id: 'INDEX-4', name: 'All receipts belong to indexed transactions',
    passed: orphans === 0,
    details: orphans === 0 ? 'No orphan receipts' : `${orphans} receipt(s) without transaction`,
    count: orphans,
  };
}

async function checkIndex5(_rpc: RpcClient, _chainId: number): Promise<CheckResult> {
  const res = await query<{ orphans: string }>(
    `SELECT COUNT(*) AS orphans FROM transaction_logs l
     WHERE NOT EXISTS (SELECT 1 FROM transactions t WHERE t.hash = l.tx_hash)`
  );
  const orphans = Number(res.rows[0]?.orphans ?? 0);
  return {
    id: 'INDEX-5', name: 'All logs belong to indexed transactions',
    passed: orphans === 0,
    details: orphans === 0 ? 'No orphan logs' : `${orphans} log(s) without transaction`,
    count: orphans,
  };
}

async function checkIndex6(_rpc: RpcClient, _chainId: number): Promise<CheckResult> {
  const res = await query<{ dups: string }>(
    'SELECT COUNT(*) AS dups FROM (SELECT hash FROM transactions GROUP BY hash HAVING COUNT(*) > 1) t'
  );
  const dups = Number(res.rows[0]?.dups ?? 0);
  return {
    id: 'INDEX-6', name: 'No duplicate transaction hashes',
    passed: dups === 0,
    details: dups === 0 ? 'No duplicates' : `${dups} duplicate transaction hash(es)`,
    count: dups,
  };
}

async function checkIndex7(_rpc: RpcClient, _chainId: number): Promise<CheckResult> {
  const res = await query<{ dups: string }>(
    'SELECT COUNT(*) AS dups FROM (SELECT tx_hash, log_index FROM transaction_logs GROUP BY tx_hash, log_index HAVING COUNT(*) > 1) t'
  );
  const dups = Number(res.rows[0]?.dups ?? 0);
  return {
    id: 'INDEX-7', name: 'No duplicate logs',
    passed: dups === 0,
    details: dups === 0 ? 'No duplicates' : `${dups} duplicate log key(s)`,
    count: dups,
  };
}

async function checkIndex8(_rpc: RpcClient, _chainId: number): Promise<CheckResult> {
  const res = await query<{ dups: string }>(
    'SELECT COUNT(*) AS dups FROM (SELECT number FROM blocks GROUP BY number HAVING COUNT(*) > 1) t'
  );
  const dups = Number(res.rows[0]?.dups ?? 0);
  return {
    id: 'INDEX-8', name: 'No duplicate blocks',
    passed: dups === 0,
    details: dups === 0 ? 'No duplicates' : `${dups} duplicate block number(s)`,
    count: dups,
  };
}

async function checkIndex9(_rpc: RpcClient, chainId: number): Promise<CheckResult> {
  const syncRes = await query<{ latest_block: string }>(
    'SELECT latest_block FROM sync_state WHERE chain_id = $1', [chainId]
  );
  if (!syncRes.rowCount) {
    return { id: 'INDEX-9', name: 'Sync state matches DB', passed: false, details: 'No sync_state row' };
  }

  const latest = Number(syncRes.rows[0]!.latest_block);
  if (latest < 0) {
    return { id: 'INDEX-9', name: 'Sync state matches DB', passed: true, details: 'No blocks indexed yet' };
  }

  const blockExists = await query<{ exists: boolean }>(
    'SELECT EXISTS(SELECT 1 FROM blocks WHERE number = $1) AS exists', [latest]
  );
  const exists = blockExists.rows[0]?.exists ?? false;
  return {
    id: 'INDEX-9', name: 'Sync state matches DB',
    passed: exists,
    details: exists ? `sync_state.latest_block=${latest} exists in blocks table` : `Block ${latest} in sync_state but missing from blocks`,
  };
}

async function checkIndex10(_rpc: RpcClient, _chainId: number): Promise<CheckResult> {
  const res = await query<{ count: string }>(
    'SELECT COUNT(*) AS count FROM decoded_events'
  );
  const count = Number(res.rows[0]?.count ?? 0);
  // Pass if either 0 events (nothing to check) or all have a non-empty event_name
  const bad = await query<{ bad: string }>(
    "SELECT COUNT(*) AS bad FROM decoded_events WHERE event_name IS NULL OR event_name = ''"
  );
  const badCount = Number(bad.rows[0]?.bad ?? 0);
  return {
    id: 'INDEX-10', name: 'Known contract events decode correctly',
    passed: badCount === 0,
    details: `${count} decoded event(s); ${badCount} with missing event_name`,
    count,
  };
}

async function checkIndex11(_rpc: RpcClient, _chainId: number): Promise<CheckResult> {
  const res = await query<{ violations: string }>(
    `SELECT COUNT(*) AS violations FROM fee_distribution
     WHERE total_amount::numeric <>
       (validator_share::numeric + treasury_share::numeric + burn_share::numeric)`
  );
  const violations = Number(res.rows[0]?.violations ?? 0);
  return {
    id: 'INDEX-11', name: '70/20/10 fee accounting consistent',
    passed: violations === 0,
    details: violations === 0 ? 'All fee splits balance' : `${violations} fee_distribution row(s) with inconsistent split`,
    count: violations,
  };
}

async function checkIndex12(_rpc: RpcClient, _chainId: number): Promise<CheckResult> {
  const res = await query<{ violations: string }>(
    `SELECT COUNT(*) AS violations FROM reward_vault_state
     WHERE total_emitted::numeric > total_funded::numeric`
  );
  const violations = Number(res.rows[0]?.violations ?? 0);
  return {
    id: 'INDEX-12', name: 'RewardVault: total_emitted <= total_funded',
    passed: violations === 0,
    details: violations === 0 ? 'Vault solvency invariant holds' : `${violations} snapshot(s) where emitted > funded`,
    count: violations,
  };
}

async function checkIndex13(_rpc: RpcClient, _chainId: number): Promise<CheckResult> {
  const evCount = await query<{ count: string }>(
    "SELECT COUNT(*) AS count FROM validator_events WHERE event_name = 'ValidatorRegistered'"
  );
  const regEvents = Number(evCount.rows[0]?.count ?? 0);

  if (regEvents === 0) {
    return { id: 'INDEX-13', name: 'Validator state consistent', passed: true, details: 'No validator registration events yet' };
  }

  const valCount = await query<{ count: string }>('SELECT COUNT(*) AS count FROM validators');
  const validators = Number(valCount.rows[0]?.count ?? 0);

  return {
    id: 'INDEX-13', name: 'Validator state consistent',
    passed: validators > 0,
    details: `${regEvents} ValidatorRegistered event(s) → ${validators} validator row(s)`,
    count: validators,
  };
}
