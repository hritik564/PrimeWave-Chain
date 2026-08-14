/**
 * PrimeWave Indexer — Sync Engine
 *
 * Main loop:
 *   1. Read sync_state → last indexed block
 *   2. Fetch chain head
 *   3. For each block in [last+1 .. head-confirmations]:
 *      a. Fetch block (full txs)
 *      b. Fetch receipts
 *      c. Write block, txs, receipts, logs, decoded events, domain state
 *         — all inside one transaction
 *      d. Update sync_state
 *   4. Sleep pollIntervalMs, repeat
 *
 * Restart safety: sync_state.latest_block is updated only after a block is
 * fully committed. If the process dies mid-block, next restart re-indexes it.
 *
 * Idempotency: all DB writes use ON CONFLICT DO NOTHING / DO UPDATE.
 */

import { PoolClient } from 'pg';
import { withTransaction, getPool } from '../db/client';
import { RpcClient } from '../rpc';
import { IndexerConfig } from '../config';
import { parseBlock, upsertBlock, verifyParentHash } from './blocks';
import { parseTx, parseReceipt, parseLog, upsertTransaction, upsertReceipt, upsertLog, insertDecodedEvent } from './transactions';
import { touchAddress, markAsContract, registerProtocolContracts } from './addresses';
import { tryDecodeLog, registerContractAddress, ContractKey } from '../abi/events';
import { handleValidatorEvent } from './validators';
import { handleStakingEvent } from './staking';
import { handleRewardEvent } from './rewards';
import { handleFeeEvent, handleGovernanceEvent } from './fees';

// ── Event routing ─────────────────────────────────────────────────────────────

const VALIDATOR_EVENTS = new Set([
  'ValidatorRegistered', 'ValidatorSynced', 'ValidatorWeightUpdated',
  'ValidatorUptimeBipsSet', 'ValidatorRewardRecipientUpdated',
  'ValidatorActivated', 'ValidatorDeactivated', 'ValidatorUpdated',
  'ValidatorFeeClaimed', 'ValidatorRecipientUpdated',
]);

const STAKING_EVENTS = new Set([
  'StakeDeposited', 'StakeReturned',
  'PhaseTransitionInitiated', 'PhaseTransitionCompleted',
]);

const REWARD_EVENTS = new Set([
  'RewardVaultFunded', 'GlobalUpdated', 'RewardClaimed', 'EmissionRateReduced',
  'RecipientRegistered', 'RecipientWeightUpdated', 'RecipientActivated',
  'RecipientDeactivated', 'RecipientAddressUpdated',
  'StakingManagerSet', 'StakingRewardDistributed',
]);

const FEE_EVENTS = new Set([
  'FeeDistributed', 'FeeReceived',
]);

const GOVERNANCE_EVENTS = new Set([
  'ProposalCreated', 'ProposalApproved', 'ProposalExecuted', 'ProposalCancelled',
  'OperationScheduled', 'OperationExecuted', 'OperationCancelled', 'ProposerTransferred',
]);

// ── Sync state helpers ────────────────────────────────────────────────────────

async function getLatestIndexed(client: PoolClient, chainId: number): Promise<number> {
  const res = await client.query<{ latest_block: string }>(
    'SELECT latest_block FROM sync_state WHERE chain_id = $1',
    [chainId]
  );
  if (res.rowCount === 0) {
    await client.query(
      'INSERT INTO sync_state (chain_id, latest_block) VALUES ($1, -1) ON CONFLICT DO NOTHING',
      [chainId]
    );
    return -1;
  }
  return Number(res.rows[0]!.latest_block);
}

async function updateSyncState(
  client: PoolClient,
  chainId: number,
  blockNumber: number,
  blockHash:   string
): Promise<void> {
  await client.query(
    `INSERT INTO sync_state (chain_id, latest_block, latest_block_hash, is_syncing, updated_at)
     VALUES ($1, $2, $3, true, NOW())
     ON CONFLICT (chain_id) DO UPDATE SET
       latest_block      = EXCLUDED.latest_block,
       latest_block_hash = EXCLUDED.latest_block_hash,
       updated_at        = NOW()`,
    [chainId, blockNumber, blockHash]
  );
}

// ── Main indexer class ────────────────────────────────────────────────────────

export class IndexerEngine {
  private rpc:       RpcClient;
  private config:    IndexerConfig;
  private running:   boolean = false;
  private contractAddressMap: Map<string, ContractKey>;

  constructor(rpc: RpcClient, config: IndexerConfig) {
    this.rpc    = rpc;
    this.config = config;

    // Build address → contractKey map for event routing
    this.contractAddressMap = new Map();
    const addrs = config.contracts;
    if (addrs.feeDistributor)   { this.contractAddressMap.set(addrs.feeDistributor,   'feeDistributor');   registerContractAddress(addrs.feeDistributor,   'feeDistributor'); }
    if (addrs.validatorFeeVault){ this.contractAddressMap.set(addrs.validatorFeeVault, 'validatorFeeVault');registerContractAddress(addrs.validatorFeeVault, 'validatorFeeVault');}
    if (addrs.devTreasury)      { this.contractAddressMap.set(addrs.devTreasury,       'devTreasury');      registerContractAddress(addrs.devTreasury,       'devTreasury'); }
    if (addrs.rewardVault)      { this.contractAddressMap.set(addrs.rewardVault,       'rewardVault');      registerContractAddress(addrs.rewardVault,       'rewardVault'); }
    if (addrs.validatorRegistry){ this.contractAddressMap.set(addrs.validatorRegistry, 'validatorRegistry');registerContractAddress(addrs.validatorRegistry, 'validatorRegistry');}
    if (addrs.stakingManager)   { this.contractAddressMap.set(addrs.stakingManager,    'stakingManager');   registerContractAddress(addrs.stakingManager,    'stakingManager'); }
    if (addrs.emergencyMultisig){ this.contractAddressMap.set(addrs.emergencyMultisig, 'emergencyMultisig');registerContractAddress(addrs.emergencyMultisig, 'emergencyMultisig');}
    if (addrs.timelock)         { this.contractAddressMap.set(addrs.timelock,          'timelock');         registerContractAddress(addrs.timelock,          'timelock'); }
  }

  /** Register known protocol contracts at startup (addresses table). */
  async registerKnownContracts(): Promise<void> {
    await withTransaction(async (client) => {
      await registerProtocolContracts(client, this.config.contracts as Record<string, string | null>);
    });
  }

  /** Index a single block and all its data. Returns false if block is null. */
  async indexBlock(blockNumber: number): Promise<boolean> {
    const rpcBlock = await this.rpc.getBlockByNumber(blockNumber, true);
    if (!rpcBlock) {
      console.warn(`[engine] Block ${blockNumber} returned null — skipping`);
      return false;
    }

    // Fetch all receipts — try batch first, fall back to per-tx
    const blockReceipts = await this.rpc.getBlockReceipts(blockNumber);
    const receiptMap = new Map<string, typeof blockReceipts[0]>();

    if (blockReceipts.length > 0) {
      for (const r of blockReceipts) receiptMap.set(r.transactionHash.toLowerCase(), r);
    } else {
      // Per-tx fallback
      for (const tx of rpcBlock.transactions) {
        const receipt = await this.rpc.getTransactionReceipt(tx.hash);
        if (receipt) receiptMap.set(receipt.transactionHash.toLowerCase(), receipt);
      }
    }

    await withTransaction(async (client) => {
      const block = parseBlock(rpcBlock);

      // Verify parent hash consistency
      const parentCheck = await verifyParentHash(client, block, this.config.startBlock);
      if (parentCheck === 'mismatch') {
        throw new Error(
          `[engine] CONSISTENCY ERROR: block ${block.number} parentHash mismatch. ` +
          `Expected ${block.parentHash} from DB. Possible reorg.`
        );
      }

      await upsertBlock(client, block);

      // Index each transaction + receipt + logs
      for (const rpcTx of rpcBlock.transactions) {
        const tx = parseTx(rpcTx);
        await upsertTransaction(client, tx);

        // Track addresses
        await touchAddress(client, tx.fromAddress, block.number, 'sender');
        if (tx.toAddress) await touchAddress(client, tx.toAddress, block.number, 'recipient');

        const rpcReceipt = receiptMap.get(tx.hash);
        if (!rpcReceipt) continue;

        const receipt = parseReceipt(rpcReceipt);
        await upsertReceipt(client, receipt);

        // If this tx created a contract, record it
        if (receipt.contractAddress) {
          await markAsContract(
            client, receipt.contractAddress, tx.hash, block.number,
            this.contractAddressMap.has(receipt.contractAddress),
            undefined
          );
        }

        // Index logs + decode known events
        for (const rpcLog of rpcReceipt.logs) {
          const log = parseLog(rpcLog);
          const logId = await upsertLog(client, log);

          // Track emitter address
          await touchAddress(client, log.contractAddress, block.number, 'emitter');

          // Try to decode
          const decoded = tryDecodeLog(
            log.contractAddress,
            [log.topic0, log.topic1, log.topic2, log.topic3].filter(Boolean) as string[],
            rpcLog.data
          );

          if (decoded && logId !== null) {
            await insertDecodedEvent(
              client, logId, block.number, tx.hash,
              log.contractAddress, decoded.eventName, decoded.eventSignature, decoded.args
            );

            const logCtx = { txHash: tx.hash, blockNumber: block.number, logIndex: log.logIndex, contractAddress: log.contractAddress };

            // Route to domain handlers
            if (VALIDATOR_EVENTS.has(decoded.eventName)) {
              await handleValidatorEvent(client, logCtx, decoded);
            } else if (STAKING_EVENTS.has(decoded.eventName)) {
              await handleStakingEvent(client, logCtx, decoded);
            } else if (REWARD_EVENTS.has(decoded.eventName)) {
              await handleRewardEvent(client, logCtx, decoded);
            } else if (FEE_EVENTS.has(decoded.eventName)) {
              await handleFeeEvent(client, logCtx, decoded);
            } else if (GOVERNANCE_EVENTS.has(decoded.eventName)) {
              await handleGovernanceEvent(client, logCtx, decoded);
            }
          }
        }
      }

      // Update sync_state — only after full block commit
      await updateSyncState(client, this.config.chainId, block.number, block.hash);
    });

    return true;
  }

  /** Index a range [fromBlock, toBlock] inclusive. Used by reindex tool. */
  async indexRange(fromBlock: number, toBlock: number): Promise<{ indexed: number; errors: number }> {
    let indexed = 0;
    let errors  = 0;

    for (let n = fromBlock; n <= toBlock; n++) {
      try {
        await this.indexBlock(n);
        indexed++;
        if (indexed % 100 === 0) console.log(`[engine] Indexed block ${n} (${indexed} in batch)`);
      } catch (err) {
        console.error(`[engine] Error indexing block ${n}:`, (err as Error).message);
        errors++;
        // Continue — don't let one bad block stop the batch
      }
    }

    return { indexed, errors };
  }

  /** Main sync loop. Runs until stop() is called. */
  async start(): Promise<void> {
    this.running = true;
    console.log(`[engine] Starting sync on chain ${this.config.chainId}`);

    // Register known protocol contracts
    await this.registerKnownContracts();

    while (this.running) {
      try {
        await this._syncOnce();
      } catch (err) {
        console.error('[engine] Sync error:', (err as Error).message);
      }
      await sleep(this.config.pollIntervalMs);
    }
  }

  stop(): void {
    this.running = false;
    console.log('[engine] Stopping sync');
  }

  private async _syncOnce(): Promise<void> {
    const pool   = getPool();
    const client = await pool.connect();
    let lastIndexed: number;
    try {
      lastIndexed = await getLatestIndexed(client, this.config.chainId);
    } finally {
      client.release();
    }

    const chainHead  = await this.rpc.getBlockNumber();
    const finalHead  = chainHead - this.config.confirmations;
    const startBlock = Math.max(lastIndexed + 1, this.config.startBlock);

    if (startBlock > finalHead) return; // Up to date

    // Process up to batchSize blocks per round
    const endBlock = Math.min(startBlock + this.config.batchSize - 1, finalHead);

    for (let n = startBlock; n <= endBlock && this.running; n++) {
      await this.indexBlock(n);
    }
  }

  /** Expose current sync status for health/stats API. */
  async getSyncStatus(): Promise<{ latestIndexed: number; chainHead: number; isSynced: boolean }> {
    const pool   = getPool();
    const client = await pool.connect();
    try {
      const latestIndexed = await getLatestIndexed(client, this.config.chainId);
      const chainHead     = await this.rpc.getBlockNumber();
      return {
        latestIndexed,
        chainHead,
        isSynced: latestIndexed >= chainHead - this.config.confirmations,
      };
    } finally {
      client.release();
    }
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}
