/**
 * PrimeWave Indexer — Transaction + Receipt Indexer
 */

import { PoolClient } from 'pg';
import {
  RpcTransaction, RpcReceipt, RpcLog,
  hexToNumber, hexToBigInt, normalizeAddress, normalizeHash,
} from '../rpc';

export interface IndexedTransaction {
  hash:             string;
  blockNumber:      number;
  blockHash:        string;
  transactionIndex: number;
  fromAddress:      string;
  toAddress:        string | null;
  value:            string;
  gasLimit:         string;
  gasPrice:         string | null;
  maxFeePerGas:     string | null;
  maxPriorityFee:   string | null;
  nonce:            number;
  input:            string | null;
  chainId:          number | null;
  txType:           number | null;
}

export interface IndexedReceipt {
  txHash:           string;
  blockNumber:      number;
  status:           number | null;
  gasUsed:          string;
  cumulativeGasUsed: string;
  effectiveGasPrice: string | null;
  transactionFee:   string | null;
  contractAddress:  string | null;
}

export interface IndexedLog {
  blockNumber:     number;
  blockHash:       string;
  txHash:          string;
  txIndex:         number;
  logIndex:        number;
  contractAddress: string;
  topic0:          string | null;
  topic1:          string | null;
  topic2:          string | null;
  topic3:          string | null;
  data:            string | null;
  removed:         boolean;
}

export function parseTx(rpc: RpcTransaction): IndexedTransaction {
  return {
    hash:             rpc.hash.toLowerCase(),
    blockNumber:      hexToNumber(rpc.blockNumber),
    blockHash:        rpc.blockHash.toLowerCase(),
    transactionIndex: hexToNumber(rpc.transactionIndex),
    fromAddress:      rpc.from.toLowerCase(),
    toAddress:        normalizeAddress(rpc.to),
    value:            hexToBigInt(rpc.value).toString(),
    gasLimit:         hexToBigInt(rpc.gas).toString(),
    gasPrice:         rpc.gasPrice ? hexToBigInt(rpc.gasPrice).toString() : null,
    maxFeePerGas:     rpc.maxFeePerGas ? hexToBigInt(rpc.maxFeePerGas).toString() : null,
    maxPriorityFee:   rpc.maxPriorityFeePerGas ? hexToBigInt(rpc.maxPriorityFeePerGas).toString() : null,
    nonce:            hexToNumber(rpc.nonce),
    input:            rpc.input && rpc.input !== '0x' ? rpc.input : null,
    chainId:          rpc.chainId ? hexToNumber(rpc.chainId) : null,
    txType:           rpc.type ? hexToNumber(rpc.type) : null,
  };
}

export function parseReceipt(rpc: RpcReceipt): IndexedReceipt {
  const gasUsed     = hexToBigInt(rpc.gasUsed);
  const effPrice    = rpc.effectiveGasPrice ? hexToBigInt(rpc.effectiveGasPrice) : null;
  const fee         = effPrice !== null ? (gasUsed * effPrice).toString() : null;
  const statusHex   = rpc.status;
  const status      = statusHex === '0x1' ? 1 : statusHex === '0x0' ? 0 : null;

  return {
    txHash:            rpc.transactionHash.toLowerCase(),
    blockNumber:       hexToNumber(rpc.blockNumber),
    status,
    gasUsed:           gasUsed.toString(),
    cumulativeGasUsed: hexToBigInt(rpc.cumulativeGasUsed).toString(),
    effectiveGasPrice: effPrice ? effPrice.toString() : null,
    transactionFee:    fee,
    contractAddress:   normalizeAddress(rpc.contractAddress ?? null),
  };
}

export function parseLog(rpc: RpcLog): IndexedLog {
  const topics = rpc.topics ?? [];
  return {
    blockNumber:     hexToNumber(rpc.blockNumber),
    blockHash:       rpc.blockHash.toLowerCase(),
    txHash:          rpc.transactionHash.toLowerCase(),
    txIndex:         hexToNumber(rpc.transactionIndex),
    logIndex:        hexToNumber(rpc.logIndex),
    contractAddress: rpc.address.toLowerCase(),
    topic0:          topics[0]?.toLowerCase() ?? null,
    topic1:          topics[1]?.toLowerCase() ?? null,
    topic2:          topics[2]?.toLowerCase() ?? null,
    topic3:          topics[3]?.toLowerCase() ?? null,
    data:            rpc.data && rpc.data !== '0x' ? rpc.data : null,
    removed:         rpc.removed ?? false,
  };
}

// ── DB writes (idempotent) ────────────────────────────────────────────────────

export async function upsertTransaction(
  client: PoolClient,
  tx:     IndexedTransaction
): Promise<void> {
  await client.query(
    `INSERT INTO transactions (
       hash, block_number, block_hash, transaction_index,
       from_address, to_address, value, gas_limit,
       gas_price, max_fee_per_gas, max_priority_fee,
       nonce, input, chain_id, tx_type
     ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15)
     ON CONFLICT (hash) DO NOTHING`,
    [
      tx.hash, tx.blockNumber, tx.blockHash, tx.transactionIndex,
      tx.fromAddress, tx.toAddress, tx.value, tx.gasLimit,
      tx.gasPrice, tx.maxFeePerGas, tx.maxPriorityFee,
      tx.nonce, tx.input, tx.chainId, tx.txType,
    ]
  );
}

export async function upsertReceipt(
  client:  PoolClient,
  receipt: IndexedReceipt
): Promise<void> {
  await client.query(
    `INSERT INTO transaction_receipts (
       tx_hash, block_number, status, gas_used,
       cumulative_gas_used, effective_gas_price, transaction_fee, contract_address
     ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
     ON CONFLICT (tx_hash) DO NOTHING`,
    [
      receipt.txHash, receipt.blockNumber, receipt.status, receipt.gasUsed,
      receipt.cumulativeGasUsed, receipt.effectiveGasPrice, receipt.transactionFee,
      receipt.contractAddress,
    ]
  );
}

/**
 * Insert a raw log. Returns the assigned `id` for use in decoded_events.
 * ON CONFLICT DO NOTHING — duplicate (tx_hash, log_index) is silently skipped.
 */
export async function upsertLog(
  client: PoolClient,
  log:    IndexedLog
): Promise<number | null> {
  const res = await client.query<{ id: number }>(
    `INSERT INTO transaction_logs (
       block_number, block_hash, tx_hash, tx_index, log_index,
       contract_address, topic0, topic1, topic2, topic3, data, removed
     ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
     ON CONFLICT (tx_hash, log_index) DO NOTHING
     RETURNING id`,
    [
      log.blockNumber, log.blockHash, log.txHash, log.txIndex, log.logIndex,
      log.contractAddress, log.topic0, log.topic1, log.topic2, log.topic3,
      log.data, log.removed,
    ]
  );
  return res.rows[0]?.id ?? null;
}

export async function insertDecodedEvent(
  client:    PoolClient,
  logId:     number,
  blockNumber: number,
  txHash:    string,
  contractAddress: string,
  eventName: string,
  signature: string,
  decoded:   Record<string, unknown>
): Promise<void> {
  await client.query(
    `INSERT INTO decoded_events (
       log_id, block_number, tx_hash, contract_address,
       event_name, event_signature, decoded_json
     ) VALUES ($1,$2,$3,$4,$5,$6,$7)
     ON CONFLICT (log_id) DO NOTHING`,
    [
      logId, blockNumber, txHash.toLowerCase(), contractAddress.toLowerCase(),
      eventName, signature, JSON.stringify(decoded),
    ]
  );
}
