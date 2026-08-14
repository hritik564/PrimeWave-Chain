/**
 * PrimeWave Indexer — Staking Indexer
 *
 * Handles events from PrimeWaveStakingManager:
 *   StakeDeposited(validationID, staker, amount)
 *   StakeReturned(to, amount)
 *   PhaseTransitionInitiated(stakingManager, rewardVault)
 *   PhaseTransitionCompleted(stakingManager, rewardVault)
 */

import { PoolClient } from 'pg';
import { DecodedLog } from '../abi/events';

export async function handleStakingEvent(
  client:  PoolClient,
  log:     { txHash: string; blockNumber: number; logIndex: number; contractAddress: string },
  decoded: DecodedLog
): Promise<void> {
  const { eventName, args } = decoded;
  const { txHash, blockNumber, logIndex, contractAddress } = log;

  const validationId = (args['validationID'] as string | undefined) ?? null;
  const address = (
    (args['staker'] as string | undefined) ??
    (args['to'] as string | undefined) ??
    (args['stakingManager'] as string | undefined)
  )?.toLowerCase() ?? null;
  const amount = (args['amount'] as string | undefined) ?? null;

  // Persist event
  await client.query(
    `INSERT INTO staking_events
       (tx_hash, block_number, log_index, event_name, validation_id, address, amount, event_data)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
     ON CONFLICT (tx_hash, log_index) DO NOTHING`,
    [txHash, blockNumber, logIndex, eventName, validationId, address, amount, JSON.stringify(args)]
  );

  // Update staking_positions mirror
  switch (eventName) {
    case 'StakeDeposited': {
      const vid    = args['validationID'] as string;
      const staker = (args['staker'] as string).toLowerCase();
      const amt    = String(args['amount']);
      await client.query(
        `INSERT INTO staking_positions (validation_id, staker, amount, stake_block)
         VALUES ($1, $2, $3, $4)
         ON CONFLICT (validation_id) DO UPDATE SET
           amount    = EXCLUDED.amount,
           staker    = EXCLUDED.staker,
           is_returned = false,
           updated_at = NOW()`,
        [vid, staker, amt, blockNumber]
      );
      break;
    }
    case 'StakeReturned': {
      // StakeReturned doesn't carry validationID — match by address + most recent non-returned
      const to = (args['to'] as string).toLowerCase();
      await client.query(
        `UPDATE staking_positions SET
           is_returned = true, return_block = $1, updated_at = NOW()
         WHERE staker = $2 AND is_returned = false
         ORDER BY stake_block DESC LIMIT 1`,
        [blockNumber, to]
      );
      break;
    }
    // PhaseTransition events: no staking_positions change needed — recorded in staking_events only
  }
}
