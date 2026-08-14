/**
 * PrimeWave Indexer — Address Tracker
 *
 * Tracks all addresses observed: tx senders, recipients, contract creators,
 * event emitters, and known protocol contracts.
 *
 * Uses UPSERT so running the same block twice is safe.
 */

import { PoolClient } from 'pg';
import { RpcClient } from '../rpc';

export async function touchAddress(
  client:     PoolClient,
  address:    string,
  blockNumber: number,
  role:       'sender' | 'recipient' | 'emitter' | 'contract' | 'protocol'
): Promise<void> {
  if (!address) return;
  const addr = address.toLowerCase();

  await client.query(
    `INSERT INTO addresses (
       address, first_seen_block, last_seen_block,
       tx_count, sent_count, received_count, is_contract
     ) VALUES ($1, $2, $2, 0, 0, 0, false)
     ON CONFLICT (address) DO UPDATE SET
       last_seen_block = GREATEST(addresses.last_seen_block, EXCLUDED.last_seen_block),
       updated_at = NOW()`,
    [addr, blockNumber]
  );

  // Increment appropriate counter
  if (role === 'sender') {
    await client.query(
      `UPDATE addresses SET sent_count = sent_count + 1, tx_count = tx_count + 1
       WHERE address = $1`,
      [addr]
    );
  } else if (role === 'recipient') {
    await client.query(
      `UPDATE addresses SET received_count = received_count + 1, tx_count = tx_count + 1
       WHERE address = $1`,
      [addr]
    );
  }
}

/** Mark an address as a contract (from receipt.contractAddress or bytecode check). */
export async function markAsContract(
  client:     PoolClient,
  address:    string,
  creationTx: string | null,
  blockNumber: number,
  isKnownProtocol: boolean = false,
  protocolName:    string | null = null
): Promise<void> {
  const addr = address.toLowerCase();

  // Ensure address row exists
  await client.query(
    `INSERT INTO addresses (address, first_seen_block, last_seen_block, is_contract)
     VALUES ($1, $2, $2, true)
     ON CONFLICT (address) DO UPDATE SET
       is_contract     = true,
       last_seen_block = GREATEST(addresses.last_seen_block, EXCLUDED.last_seen_block),
       updated_at      = NOW()`,
    [addr, blockNumber]
  );

  // Upsert into contracts table
  await client.query(
    `INSERT INTO contracts (
       address, creation_tx, creation_block,
       is_known_protocol, protocol_name
     ) VALUES ($1, $2, $3, $4, $5)
     ON CONFLICT (address) DO UPDATE SET
       creation_tx        = COALESCE(contracts.creation_tx, EXCLUDED.creation_tx),
       creation_block     = COALESCE(contracts.creation_block, EXCLUDED.creation_block),
       is_known_protocol  = EXCLUDED.is_known_protocol OR contracts.is_known_protocol,
       protocol_name      = COALESCE(EXCLUDED.protocol_name, contracts.protocol_name),
       updated_at         = NOW()`,
    [addr, creationTx?.toLowerCase() ?? null, blockNumber, isKnownProtocol, protocolName]
  );
}

/** Register all known protocol contracts at startup. */
export async function registerProtocolContracts(
  client:    PoolClient,
  contracts: Record<string, string | null>
): Promise<void> {
  const PROTOCOL_NAMES: Record<string, string> = {
    feeDistributor:    'FeeDistributor',
    validatorFeeVault: 'ValidatorFeeVault',
    devTreasury:       'DevTreasury',
    rewardVault:       'RewardVault',
    validatorRegistry: 'PrimeWaveValidatorRegistry',
    stakingManager:    'PrimeWaveStakingManager',
    emergencyMultisig: 'EmergencyMultisig',
    timelock:          'PrimeWaveTimelock',
  };

  for (const [key, address] of Object.entries(contracts)) {
    if (!address) continue;
    await markAsContract(client, address, null, 0, true, PROTOCOL_NAMES[key] ?? key);
  }
}

/** Detect whether an address is a contract by checking its bytecode. */
export async function detectContract(
  rpc:     RpcClient,
  address: string
): Promise<boolean> {
  try {
    const code = await rpc.getCode(address);
    return code !== '0x' && code !== '' && code.length > 2;
  } catch {
    return false;
  }
}
