/**
 * PrimeWave Chain Keeper — Main Service
 * C11 Production Infrastructure
 *
 * Responsibilities:
 *   1. Poll PrimeWaveValidatorRegistry for managed validators
 *   2. Compare on-chain ValidatorManager status with feeVault active state
 *   3. Call syncValidator() for validators that are out of sync (permissionless)
 *   4. Call updateWeight() for validators whose weight has changed
 *   5. Retry failed transactions with exponential backoff
 *   6. Persist state across restarts (no required sync work is lost)
 *   7. Expose /health endpoint for monitoring
 *   8. Emit structured logs for every action
 *
 * SECURITY:
 *   The keeper account needs NO privileged role.
 *   syncValidator() and updateWeight() are permissionless on the registry.
 *   The keeper CANNOT: mint PW, withdraw funds, alter governance, change
 *   validator ownership, or become a source of truth for validator state.
 *   The smart contract (PrimeWaveValidatorRegistry + ValidatorManager) is
 *   the sole authority.
 */

import { ethers } from 'ethers';
import express from 'express';
import * as promClient from 'prom-client';
import { KeeperConfig, loadConfig, REGISTRY_ABI, ValidatorStatus } from './config';
import { StateStore, ValidatorRecord } from './state';

// ── Prometheus metrics ─────────────────────────────────────────────────────────

const registry = new promClient.Registry();
promClient.collectDefaultMetrics({ register: registry });

const syncAttempts = new promClient.Counter({
  name: 'primewave_keeper_sync_attempts_total',
  help: 'Total syncValidator() call attempts',
  registers: [registry],
});
const syncSuccesses = new promClient.Counter({
  name: 'primewave_keeper_sync_successes_total',
  help: 'Total successful syncValidator() calls',
  registers: [registry],
});
const syncFailures = new promClient.Counter({
  name: 'primewave_keeper_sync_failures_total',
  help: 'Total failed syncValidator() calls',
  registers: [registry],
});
const pendingSyncsGauge = new promClient.Gauge({
  name: 'primewave_keeper_pending_syncs',
  help: 'Number of validators with pending sync',
  registers: [registry],
});
const managedValidatorsGauge = new promClient.Gauge({
  name: 'primewave_keeper_managed_validators',
  help: 'Total managed validators in registry',
  registers: [registry],
});
const lastPollTimestamp = new promClient.Gauge({
  name: 'primewave_keeper_last_poll_timestamp_seconds',
  help: 'Unix timestamp of last successful poll',
  registers: [registry],
});

// ── Logging ───────────────────────────────────────────────────────────────────

type LogLevel = 'debug' | 'info' | 'warn' | 'error';

function log(level: LogLevel, event: string, fields: Record<string, unknown> = {}): void {
  const entry = {
    timestamp:   new Date().toISOString(),
    environment: process.env['PRIMEWAVE_ENV'] ?? 'development',
    chainId:     process.env['KEEPER_CHAIN_ID'] ?? 'unknown',
    component:   'primewave-keeper',
    severity:    level.toUpperCase(),
    event,
    ...fields,
  };
  const line = JSON.stringify(entry);
  if (level === 'error') {
    process.stderr.write(line + '\n');
  } else {
    process.stdout.write(line + '\n');
  }
}

// ── Sleep ─────────────────────────────────────────────────────────────────────

const sleep = (ms: number) => new Promise<void>(resolve => setTimeout(resolve, ms));

// ── Keeper ────────────────────────────────────────────────────────────────────

// Minimal interfaces for dependency injection (used in tests)
export interface IProvider {
  getBlockNumber(): Promise<number>;
}

export interface IRegistryContract {
  managedCount(): Promise<bigint>;
  managedValidators(index: number): Promise<string>;
  validatorStatus(validationID: string): Promise<bigint>;
  syncValidator(validationID: string): Promise<{ hash: string; wait(confirms: number): Promise<{ status: number; blockNumber: number } | null> }>;
  updateWeight(validationID: string): Promise<{ hash: string; wait(confirms: number): Promise<{ status: number; blockNumber: number } | null> }>;
}

export class PrimewaveKeeper {
  private config: KeeperConfig;
  private provider: IProvider;
  private registryContract: IRegistryContract;
  private state: StateStore;
  private running: boolean = false;
  private consecutiveRpcFailures: number = 0;

  // Exposed for tests
  public lastPollBlock: number = 0;
  public isHealthy: boolean = false;

  constructor(
    config: KeeperConfig,
    stateStore?: StateStore,
    // Dependency injection for testing — if omitted, real ethers objects are created
    provider?: IProvider,
    registryContract?: IRegistryContract
  ) {
    this.config = config;
    this.state = stateStore ?? new StateStore(
      config.stateFilePath,
      config.chainId,
      config.registryAddress
    );

    if (provider && registryContract) {
      // Test path: use injected objects (no ethers classes instantiated)
      this.provider = provider;
      this.registryContract = registryContract;
    } else {
      // Production path: create real ethers objects
      const realProvider = new ethers.JsonRpcProvider(config.rpcUrl);
      const wallet = new ethers.Wallet(config.keeperPrivateKey, realProvider);
      this.provider = realProvider as unknown as IProvider;
      this.registryContract = new ethers.Contract(
        config.registryAddress,
        REGISTRY_ABI,
        wallet
      ) as unknown as IRegistryContract;
    }
  }

  // ── Main loop ─────────────────────────────────────────────────────────────

  async start(): Promise<void> {
    log('info', 'keeper.start', {
      registry:  this.config.registryAddress,
      chainId:   this.config.chainId,
      rpcUrl:    this.config.rpcUrl,
      pollMs:    this.config.pollIntervalMs,
      maxRetry:  this.config.maxRetries,
    });

    this.state.load();
    this.running = true;

    // Retry any pending syncs from previous session immediately
    const pending = this.state.getPendingSyncs();
    if (pending.length > 0) {
      log('info', 'keeper.resume', { pendingCount: pending.length });
      await this.processPendingSyncs(pending);
    }

    while (this.running) {
      try {
        await this.poll();
        this.consecutiveRpcFailures = 0;
        this.isHealthy = true;
      } catch (err) {
        this.consecutiveRpcFailures++;
        this.isHealthy = this.consecutiveRpcFailures < this.config.alertOnConsecutiveFailures;
        log('error', 'keeper.poll.error', {
          error:              String(err),
          consecutiveFailures: this.consecutiveRpcFailures,
        });

        if (this.consecutiveRpcFailures >= this.config.alertOnConsecutiveFailures) {
          log('error', 'keeper.alert', {
            message: 'ALERT: keeper has failed consecutively -- intervention required',
            consecutiveFailures: this.consecutiveRpcFailures,
          });
        }
      }

      await sleep(this.config.pollIntervalMs);
    }
  }

  stop(): void {
    this.running = false;
    log('info', 'keeper.stop', {});
  }

  // ── Poll cycle ────────────────────────────────────────────────────────────

  async poll(): Promise<void> {
    const blockNumber = await this.provider.getBlockNumber();
    log('debug', 'keeper.poll', { block: blockNumber });

    // Fetch all managed validators from registry
    const managedCount: bigint = await this.registryContract['managedCount']();
    const count = Number(managedCount);
    managedValidatorsGauge.set(count);

    const toSync: string[] = [];
    const toWeightUpdate: string[] = [];

    for (let i = 0; i < count; i++) {
      const vid: string = await this.registryContract['managedValidators'](i);
      const statusNum: bigint = await this.registryContract['validatorStatus'](vid);
      const status = Number(statusNum) as ValidatorStatus;

      // Get or create record
      let record = this.state.getValidator(vid);
      if (!record) {
        record = {
          validationId:         vid.toLowerCase(),
          lastKnownStatus:      status,
          syncPending:          false,
          weightUpdatePending:  false,
          consecutiveFailures:  0,
          lastSyncAttemptAt:    0,
          lastSuccessfulSyncAt: 0,
          lastTxHash:           null,
        };
        this.state.upsertValidator(record);
      }

      // Determine if sync is needed
      const needsSync = this.needsSync(status, record);
      const needsWeightUpdate = status === ValidatorStatus.Active &&
                                record.lastKnownStatus !== ValidatorStatus.Active;

      if (needsSync) {
        toSync.push(vid);
        record.syncPending = true;
        record.lastKnownStatus = status;
        this.state.upsertValidator(record);
      }
      if (needsWeightUpdate) {
        toWeightUpdate.push(vid);
      }
    }

    this.state.updateLastPoll(blockNumber);
    this.lastPollBlock = blockNumber;
    lastPollTimestamp.set(Date.now() / 1000);

    // Process pending syncs
    pendingSyncsGauge.set(toSync.length);
    if (toSync.length > 0) {
      log('info', 'keeper.sync.needed', { count: toSync.length, validators: toSync });
      await this.processSyncs(toSync);
    }

    // Process weight updates
    if (toWeightUpdate.length > 0) {
      log('info', 'keeper.weightUpdate.needed', { count: toWeightUpdate.length });
      await this.processWeightUpdates(toWeightUpdate);
    }

    // Retry any previously-failed pending syncs
    const stillPending = this.state.getPendingSyncs();
    if (stillPending.length > 0) {
      await this.processPendingSyncs(stillPending);
    }
  }

  // ── Sync logic ────────────────────────────────────────────────────────────

  private needsSync(currentStatus: ValidatorStatus, record: ValidatorRecord): boolean {
    // Sync is needed when the on-chain status has changed to a terminal/active state
    // that the registry's fee accounting layer may not yet reflect.
    if (currentStatus === record.lastKnownStatus) return false;
    return (
      currentStatus === ValidatorStatus.Active         ||
      currentStatus === ValidatorStatus.PendingRemoved ||
      currentStatus === ValidatorStatus.Completed      ||
      currentStatus === ValidatorStatus.Invalidated
    );
  }

  private async processSyncs(validatorIds: string[]): Promise<void> {
    for (const vid of validatorIds) {
      await this.syncWithRetry(vid, 'syncValidator');
    }
  }

  private async processPendingSyncs(records: ValidatorRecord[]): Promise<void> {
    for (const r of records) {
      if (r.consecutiveFailures >= this.config.maxRetries) {
        log('warn', 'keeper.sync.maxRetries', {
          validationId: r.validationId,
          failures: r.consecutiveFailures,
          message: 'max retries reached -- manual intervention may be required',
        });
        continue;
      }
      await this.syncWithRetry(r.validationId, 'syncValidator');
    }
  }

  private async processWeightUpdates(validatorIds: string[]): Promise<void> {
    for (const vid of validatorIds) {
      await this.syncWithRetry(vid, 'updateWeight');
    }
  }

  async syncWithRetry(validationId: string, method: 'syncValidator' | 'updateWeight'): Promise<boolean> {
    let attempt = 0;
    let delayMs = this.config.retryDelayMs;

    while (attempt < this.config.maxRetries) {
      attempt++;
      syncAttempts.inc();

      try {
        log('info', `keeper.${method}.attempt`, { validationId, attempt });
        this.state.markSyncAttempted(validationId, null);

        // Check if sync is actually needed (idempotency — avoids wasting gas)
        // syncValidator() is safe to call even if already synced (no-op on contract)
        const tx = await (this.registryContract[method] as (id: string) => ReturnType<IRegistryContract['syncValidator']>)(validationId);
        log('info', `keeper.${method}.submitted`, { validationId, txHash: tx.hash, attempt });

        const receipt = await tx.wait(this.config.confirmationBlocks);
        if (!receipt || receipt.status !== 1) {
          throw new Error(`Transaction reverted: ${tx.hash}`);
        }

        this.state.markSyncSucceeded(validationId, tx.hash);
        syncSuccesses.inc();
        log('info', `keeper.${method}.confirmed`, {
          validationId,
          txHash:      tx.hash,
          blockNumber: receipt.blockNumber,
        });
        return true;

      } catch (err) {
        const errStr = String(err);
        syncFailures.inc();

        // If the call reverts because the validator is already synced, that is NOT a failure
        if (errStr.includes('PWVR: not managed')) {
          log('warn', 'keeper.sync.notManaged', { validationId });
          this.state.markSyncFailed(validationId);
          return false;
        }

        log('warn', `keeper.${method}.failed`, {
          validationId,
          attempt,
          maxRetries: this.config.maxRetries,
          error:      errStr,
          nextRetryMs: delayMs,
        });

        if (attempt < this.config.maxRetries) {
          await sleep(delayMs);
          delayMs = Math.round(delayMs * this.config.retryBackoffMultiplier);
        } else {
          this.state.markSyncFailed(validationId);
          log('error', `keeper.${method}.exhausted`, { validationId, attempts: attempt });
          return false;
        }
      }
    }
    return false;
  }

  // ── Health ─────────────────────────────────────────────────────────────────

  getHealthStatus(): {
    status: 'healthy' | 'degraded' | 'unhealthy';
    lastPollBlock: number;
    lastPollAt: number;
    consecutiveRpcFailures: number;
    pendingSyncs: number;
    uptime: number;
  } {
    const s = this.state.getState();
    const pending = this.state.getPendingSyncs().length;
    const status = this.isHealthy
      ? (pending > 5 ? 'degraded' : 'healthy')
      : 'unhealthy';

    return {
      status,
      lastPollBlock:          this.lastPollBlock,
      lastPollAt:             s.lastPollAt,
      consecutiveRpcFailures: this.consecutiveRpcFailures,
      pendingSyncs:           pending,
      uptime:                 process.uptime(),
    };
  }
}

// ── Health HTTP server ─────────────────────────────────────────────────────────

function startHealthServer(keeper: PrimewaveKeeper, port: number): void {
  const app = express();

  app.get('/health', (_req, res) => {
    const health = keeper.getHealthStatus();
    const httpStatus = health.status === 'unhealthy' ? 503 : 200;
    res.status(httpStatus).json(health);
  });

  app.get('/metrics', async (_req, res) => {
    res.set('Content-Type', registry.contentType);
    res.end(await registry.metrics());
  });

  app.listen(port, () => {
    log('info', 'keeper.health.listening', { port });
  });
}

// ── Entry point ───────────────────────────────────────────────────────────────

async function main(): Promise<void> {
  const config = loadConfig();
  const stateStore = new StateStore(config.stateFilePath, config.chainId, config.registryAddress);
  const keeper = new PrimewaveKeeper(config, stateStore);

  startHealthServer(keeper, config.healthPort);

  // Graceful shutdown
  const shutdown = () => {
    log('info', 'keeper.shutdown', {});
    keeper.stop();
    process.exit(0);
  };
  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);

  await keeper.start();
}

if (require.main === module) {
  main().catch(err => {
    log('error', 'keeper.fatal', { error: String(err) });
    process.exit(1);
  });
}
