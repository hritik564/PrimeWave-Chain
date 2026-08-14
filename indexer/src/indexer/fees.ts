/**
 * PrimeWave Indexer — Fee Distribution Indexer
 *
 * Handles FeeDistributor events:
 *   FeeDistributed(amount, validatorShare, treasuryShare, burnShare, blockNumber)
 *   FeeReceived(amount, blockNumber, sender)   — from FeeDistributor
 *   Paused/Unpaused/PauseControllerUpdated
 *
 * The 70/20/10 split is recorded from the authoritative on-chain event.
 * Do NOT calculate the split from transaction gas fees alone.
 */

import { PoolClient } from 'pg';
import { DecodedLog } from '../abi/events';

export async function handleFeeEvent(
  client:  PoolClient,
  log:     { txHash: string; blockNumber: number; logIndex: number },
  decoded: DecodedLog
): Promise<void> {
  const { eventName, args } = decoded;
  const { txHash, blockNumber, logIndex } = log;

  if (eventName === 'FeeDistributed') {
    await client.query(
      `INSERT INTO fee_distribution
         (tx_hash, block_number, log_index, total_amount, validator_share, treasury_share, burn_share)
       VALUES ($1,$2,$3,$4,$5,$6,$7)
       ON CONFLICT (tx_hash, log_index) DO NOTHING`,
      [
        txHash, blockNumber, logIndex,
        String(args['amount']),
        String(args['validatorShare']),
        String(args['treasuryShare']),
        String(args['burnShare']),
      ]
    );
  }

  // FeeReceived, Paused, Unpaused etc. → decoded_events only (already handled by event decoder)
}

export async function handleGovernanceEvent(
  client:  PoolClient,
  log:     { txHash: string; blockNumber: number; logIndex: number; contractAddress: string },
  decoded: DecodedLog
): Promise<void> {
  const { eventName, args } = decoded;
  const { txHash, blockNumber, logIndex, contractAddress } = log;

  await client.query(
    `INSERT INTO governance_events
       (tx_hash, block_number, log_index, contract_address, event_name, event_data)
     VALUES ($1,$2,$3,$4,$5,$6)
     ON CONFLICT (tx_hash, log_index) DO NOTHING`,
    [txHash, blockNumber, logIndex, contractAddress.toLowerCase(), eventName, JSON.stringify(args)]
  );
}
