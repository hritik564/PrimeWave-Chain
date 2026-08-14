/**
 * PrimeWave Indexer — Block Indexer
 *
 * Upserts block data into the `blocks` table.
 * All inserts use ON CONFLICT DO NOTHING for idempotency.
 */

import { PoolClient } from 'pg';
import { RpcBlock, hexToNumber, hexToBigInt, normalizeAddress, normalizeHash } from '../rpc';

export interface IndexedBlock {
  number:           number;
  hash:             string;
  parentHash:       string;
  timestampUnix:    number;
  gasLimit:         string;
  gasUsed:          string;
  baseFeePerGas:    string | null;
  transactionCount: number;
  coinbase:         string | null;
  stateRoot:        string | null;
  receiptsRoot:     string | null;
}

export function parseBlock(rpc: RpcBlock): IndexedBlock {
  return {
    number:           hexToNumber(rpc.number),
    hash:             rpc.hash.toLowerCase(),
    parentHash:       rpc.parentHash.toLowerCase(),
    timestampUnix:    hexToNumber(rpc.timestamp),
    gasLimit:         hexToBigInt(rpc.gasLimit).toString(),
    gasUsed:          hexToBigInt(rpc.gasUsed).toString(),
    baseFeePerGas:    rpc.baseFeePerGas ? hexToBigInt(rpc.baseFeePerGas).toString() : null,
    transactionCount: rpc.transactions.length,
    coinbase:         normalizeAddress(rpc.miner),
    stateRoot:        normalizeHash(rpc.stateRoot),
    receiptsRoot:     normalizeHash(rpc.receiptsRoot),
  };
}

export async function upsertBlock(
  client: PoolClient,
  block:  IndexedBlock
): Promise<void> {
  await client.query(
    `INSERT INTO blocks (
       number, hash, parent_hash, timestamp_unix,
       gas_limit, gas_used, base_fee_per_gas,
       transaction_count, coinbase, state_root, receipts_root
     ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
     ON CONFLICT (number) DO UPDATE SET
       hash              = EXCLUDED.hash,
       parent_hash       = EXCLUDED.parent_hash,
       timestamp_unix    = EXCLUDED.timestamp_unix,
       gas_limit         = EXCLUDED.gas_limit,
       gas_used          = EXCLUDED.gas_used,
       base_fee_per_gas  = EXCLUDED.base_fee_per_gas,
       transaction_count = EXCLUDED.transaction_count,
       coinbase          = EXCLUDED.coinbase,
       state_root        = EXCLUDED.state_root,
       receipts_root     = EXCLUDED.receipts_root`,
    [
      block.number, block.hash, block.parentHash, block.timestampUnix,
      block.gasLimit, block.gasUsed, block.baseFeePerGas,
      block.transactionCount, block.coinbase, block.stateRoot, block.receiptsRoot,
    ]
  );
}

/**
 * Verify parent hash consistency between a new block and what we have in the DB.
 * Returns: 'ok' | 'mismatch' | 'first_block'
 */
export async function verifyParentHash(
  client:     PoolClient,
  block:      IndexedBlock,
  startBlock: number
): Promise<'ok' | 'mismatch' | 'first_block'> {
  if (block.number === startBlock) return 'first_block';

  const res = await client.query<{ hash: string }>(
    'SELECT hash FROM blocks WHERE number = $1',
    [block.number - 1]
  );

  if (res.rowCount === 0) {
    // Previous block not yet in DB (normal during initial sync)
    return 'ok';
  }

  const prevHash = res.rows[0]!.hash;
  if (prevHash === block.parentHash) return 'ok';

  return 'mismatch';
}
