/**
 * PrimeWave Indexer — RewardVault Indexer
 *
 * Handles events from RewardVault:
 *   RewardVaultFunded(funder, amount, newTotalFunded)
 *   GlobalUpdated(emitted, newAccRewardPerWeight, totalEligibleWeight)
 *   RewardClaimed(recipientId, rewardAddress, amount)
 *   EmissionRateReduced(oldRatePerSecond, newRatePerSecond)
 *   RecipientRegistered(recipientId, rewardAddress, weight, startActive)
 *   RecipientWeightUpdated(recipientId, oldWeight, newWeight)
 *   RecipientActivated(recipientId)
 *   RecipientDeactivated(recipientId, checkpointed)
 *   RecipientAddressUpdated(recipientId, newRewardAddress)
 *   StakingManagerSet(stakingManager)
 *   StakingRewardDistributed(to, amount)
 *   Paused/Unpaused/PauseControllerUpdated
 */

import { PoolClient } from 'pg';
import { DecodedLog } from '../abi/events';

export async function handleRewardEvent(
  client:  PoolClient,
  log:     { txHash: string; blockNumber: number; logIndex: number },
  decoded: DecodedLog
): Promise<void> {
  const { eventName, args } = decoded;
  const { txHash, blockNumber, logIndex } = log;

  const recipientId    = (args['recipientId'] as string | undefined) ?? null;
  const rewardAddress  = ((args['rewardAddress'] ?? args['to']) as string | undefined)?.toLowerCase() ?? null;
  const amount         = (args['amount'] as string | undefined) ?? null;

  // Persist to reward_events
  await client.query(
    `INSERT INTO reward_events
       (tx_hash, block_number, log_index, event_name, recipient_id, reward_address, amount, event_data)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
     ON CONFLICT (tx_hash, log_index) DO NOTHING`,
    [txHash, blockNumber, logIndex, eventName, recipientId, rewardAddress, amount, JSON.stringify(args)]
  );

  // Update reward_vault_state snapshot on funding/emission events
  switch (eventName) {
    case 'RewardVaultFunded': {
      const totalFunded = String(args['newTotalFunded']);
      await client.query(
        `INSERT INTO reward_vault_state (block_number, total_funded)
         VALUES ($1, $2)
         ON CONFLICT (block_number) DO UPDATE SET
           total_funded = EXCLUDED.total_funded,
           updated_at   = NOW()`,
        [blockNumber, totalFunded]
      );
      break;
    }
    case 'GlobalUpdated': {
      const emitted = String(args['emitted']);
      await client.query(
        `INSERT INTO reward_vault_state (block_number, total_emitted)
         VALUES ($1, $2)
         ON CONFLICT (block_number) DO UPDATE SET
           total_emitted = (
             COALESCE((SELECT MAX(total_emitted::numeric) FROM reward_vault_state WHERE block_number < $1), 0)
             + $2::numeric
           )::text,
           updated_at = NOW()`,
        [blockNumber, emitted]
      );
      break;
    }
    case 'EmissionRateReduced': {
      const newRate = String(args['newRatePerSecond']);
      await client.query(
        `INSERT INTO reward_vault_state (block_number, emission_rate)
         VALUES ($1, $2)
         ON CONFLICT (block_number) DO UPDATE SET
           emission_rate = EXCLUDED.emission_rate,
           updated_at    = NOW()`,
        [blockNumber, newRate]
      );
      break;
    }
  }
}
