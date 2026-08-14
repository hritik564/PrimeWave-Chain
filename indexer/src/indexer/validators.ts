/**
 * PrimeWave Indexer — Validator State Indexer
 *
 * Mirrors validator state from PrimeWaveValidatorRegistry and ValidatorFeeVault events.
 * This is a READ-ONLY mirror — it never mutates chain state.
 *
 * Events handled:
 *   PrimeWaveValidatorRegistry:
 *     ValidatorRegistered(validationID, rewardRecipient, acp99Weight, uptimeBips)
 *     ValidatorSynced(validationID, newStatus, nowActive)
 *     ValidatorWeightUpdated(validationID, newWeight)
 *     ValidatorUptimeBipsSet(validationID, newBips)
 *     ValidatorRewardRecipientUpdated(validationID, newRecipient)
 *
 *   ValidatorFeeVault:
 *     ValidatorRegistered(validationId, rewardRecipient, baseWeight, uptimeBips)
 *     ValidatorActivated(validationId)
 *     ValidatorDeactivated(validationId, checkpointedReward)
 *     ValidatorUpdated(validationId, baseWeight, uptimeBips)
 *     ValidatorFeeClaimed(validationId, recipient, amount)
 *     ValidatorRecipientUpdated(validationId, newRecipient)
 */

import { PoolClient } from 'pg';
import { DecodedLog } from '../abi/events';

export async function handleValidatorEvent(
  client:      PoolClient,
  log:         { txHash: string; blockNumber: number; logIndex: number; contractAddress: string },
  decoded:     DecodedLog
): Promise<void> {
  const { eventName, args } = decoded;
  const { txHash, blockNumber, logIndex, contractAddress } = log;
  const addr = contractAddress.toLowerCase();

  // Persist to validator_events table (idempotent)
  await client.query(
    `INSERT INTO validator_events
       (tx_hash, block_number, log_index, validation_id, event_name, contract_address, event_data)
     VALUES ($1, $2, $3, $4, $5, $6, $7)
     ON CONFLICT (tx_hash, log_index) DO NOTHING`,
    [
      txHash, blockNumber, logIndex,
      (args['validationId'] as string ?? args['validationID'] as string ?? null),
      eventName, addr, JSON.stringify(args),
    ]
  );

  // Update the validators mirror table
  switch (eventName) {
    case 'ValidatorRegistered':
      await _handleRegistered(client, args, blockNumber, addr);
      break;
    case 'ValidatorSynced':
      await _handleSynced(client, args, blockNumber);
      break;
    case 'ValidatorWeightUpdated':
      await _handleWeightUpdated(client, args, blockNumber);
      break;
    case 'ValidatorUptimeBipsSet':
      await _handleUptimeBipsSet(client, args, blockNumber);
      break;
    case 'ValidatorRewardRecipientUpdated':
    case 'ValidatorRecipientUpdated':
      await _handleRecipientUpdated(client, args, blockNumber);
      break;
    case 'ValidatorActivated':
      await _handleActivated(client, args, blockNumber);
      break;
    case 'ValidatorDeactivated':
      await _handleDeactivated(client, args, blockNumber);
      break;
    case 'ValidatorUpdated':
      await _handleUpdated(client, args, blockNumber);
      break;
    case 'ValidatorFeeClaimed':
      await _handleFeeClaimed(client, args, blockNumber);
      break;
  }
}

async function _handleRegistered(
  client: PoolClient, args: Record<string, unknown>, block: number, addr: string
): Promise<void> {
  const vid       = (args['validationId'] ?? args['validationID']) as string;
  const recipient = (args['rewardRecipient'] as string).toLowerCase();
  const weight    = args['acp99Weight'] ?? args['baseWeight'];
  const uptime    = args['uptimeBips'];

  // Registry event: set acp99_weight and status = 1 (PendingAdded)
  const isVFV = !('acp99Weight' in args);

  await client.query(
    `INSERT INTO validators (
       validation_id, reward_recipient, acp99_weight, uptime_bips, status,
       is_active_in_vault, vault_base_weight, vault_uptime_bips,
       first_seen_block, last_updated_block
     ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$9)
     ON CONFLICT (validation_id) DO UPDATE SET
       reward_recipient   = COALESCE(EXCLUDED.reward_recipient, validators.reward_recipient),
       acp99_weight       = CASE WHEN $10 THEN validators.acp99_weight ELSE EXCLUDED.acp99_weight END,
       vault_base_weight  = CASE WHEN $10 THEN EXCLUDED.acp99_weight ELSE validators.vault_base_weight END,
       vault_uptime_bips  = CASE WHEN $10 THEN EXCLUDED.uptime_bips ELSE validators.vault_uptime_bips END,
       last_updated_block = GREATEST(validators.last_updated_block, $9),
       updated_at         = NOW()`,
    [
      vid, recipient, String(weight), Number(uptime), 1,
      false, isVFV ? String(weight) : null, isVFV ? Number(uptime) : null,
      block, isVFV,
    ]
  );
}

async function _handleSynced(
  client: PoolClient, args: Record<string, unknown>, block: number
): Promise<void> {
  const vid    = args['validationID'] as string;
  const status = Number(args['newStatus']);
  await client.query(
    `UPDATE validators SET status = $1, last_updated_block = GREATEST(last_updated_block, $2), updated_at = NOW()
     WHERE validation_id = $3`,
    [status, block, vid]
  );
}

async function _handleWeightUpdated(
  client: PoolClient, args: Record<string, unknown>, block: number
): Promise<void> {
  const vid    = args['validationID'] as string;
  const weight = String(args['newWeight']);
  await client.query(
    `UPDATE validators SET acp99_weight = $1, last_updated_block = GREATEST(last_updated_block, $2), updated_at = NOW()
     WHERE validation_id = $3`,
    [weight, block, vid]
  );
}

async function _handleUptimeBipsSet(
  client: PoolClient, args: Record<string, unknown>, block: number
): Promise<void> {
  const vid   = args['validationID'] as string;
  const bips  = Number(args['newBips']);
  await client.query(
    `UPDATE validators SET uptime_bips = $1, last_updated_block = GREATEST(last_updated_block, $2), updated_at = NOW()
     WHERE validation_id = $3`,
    [bips, block, vid]
  );
}

async function _handleRecipientUpdated(
  client: PoolClient, args: Record<string, unknown>, block: number
): Promise<void> {
  const vid       = (args['validationId'] ?? args['validationID']) as string;
  const recipient = ((args['newRecipient'] ?? args['newRecipient']) as string).toLowerCase();
  await client.query(
    `UPDATE validators SET reward_recipient = $1, last_updated_block = GREATEST(last_updated_block, $2), updated_at = NOW()
     WHERE validation_id = $3`,
    [recipient, block, vid]
  );
}

async function _handleActivated(
  client: PoolClient, args: Record<string, unknown>, block: number
): Promise<void> {
  const vid = args['validationId'] as string;
  await client.query(
    `UPDATE validators SET is_active_in_vault = true, last_updated_block = GREATEST(last_updated_block, $1), updated_at = NOW()
     WHERE validation_id = $2`,
    [block, vid]
  );
}

async function _handleDeactivated(
  client: PoolClient, args: Record<string, unknown>, block: number
): Promise<void> {
  const vid = args['validationId'] as string;
  await client.query(
    `UPDATE validators SET is_active_in_vault = false, last_updated_block = GREATEST(last_updated_block, $1), updated_at = NOW()
     WHERE validation_id = $2`,
    [block, vid]
  );
}

async function _handleUpdated(
  client: PoolClient, args: Record<string, unknown>, block: number
): Promise<void> {
  const vid   = args['validationId'] as string;
  const bw    = String(args['baseWeight']);
  const bips  = Number(args['uptimeBips']);
  await client.query(
    `UPDATE validators SET vault_base_weight = $1, vault_uptime_bips = $2,
       last_updated_block = GREATEST(last_updated_block, $3), updated_at = NOW()
     WHERE validation_id = $4`,
    [bw, bips, block, vid]
  );
}

async function _handleFeeClaimed(
  client: PoolClient, args: Record<string, unknown>, block: number
): Promise<void> {
  const vid    = args['validationId'] as string;
  const amount = String(args['amount']);
  await client.query(
    `UPDATE validators SET
       total_fees_claimed = (COALESCE(total_fees_claimed::numeric, 0) + $1::numeric)::text,
       last_updated_block = GREATEST(last_updated_block, $2),
       updated_at = NOW()
     WHERE validation_id = $3`,
    [amount, block, vid]
  );
}
