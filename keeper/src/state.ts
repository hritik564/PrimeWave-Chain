/**
 * PrimeWave Chain Keeper — Persistent State
 * C11 Production Infrastructure
 *
 * State is stored as a JSON file on disk so the keeper
 * survives restarts without losing required sync work.
 *
 * SECURITY: The state file contains no private keys.
 * It only records validator IDs, pending sync status, and retry counts.
 */

import fs from 'fs';
import path from 'path';

export interface ValidatorRecord {
  validationId: string;          // bytes32 hex string
  lastKnownStatus: number;       // ValidatorStatus enum value
  syncPending: boolean;          // needs a syncValidator() call
  weightUpdatePending: boolean;  // needs an updateWeight() call
  consecutiveFailures: number;   // reset to 0 on success
  lastSyncAttemptAt: number;     // unix timestamp ms
  lastSuccessfulSyncAt: number;  // unix timestamp ms (0 if never)
  lastTxHash: string | null;     // most recent submitted tx hash
}

export interface KeeperState {
  schemaVersion: number;         // increment if structure changes
  chainId: number;
  registryAddress: string;
  lastPollAt: number;            // unix timestamp ms
  lastBlockProcessed: number;    // for event replay-safety
  validators: Record<string, ValidatorRecord>;
  totalSyncsAttempted: number;
  totalSyncsSucceeded: number;
  totalSyncsFailed: number;
}

const SCHEMA_VERSION = 1;

function emptyState(chainId: number, registryAddress: string): KeeperState {
  return {
    schemaVersion: SCHEMA_VERSION,
    chainId,
    registryAddress,
    lastPollAt: 0,
    lastBlockProcessed: 0,
    validators: {},
    totalSyncsAttempted: 0,
    totalSyncsSucceeded: 0,
    totalSyncsFailed: 0,
  };
}

export class StateStore {
  private filePath: string;
  private state: KeeperState;

  constructor(filePath: string, chainId: number, registryAddress: string) {
    this.filePath = path.resolve(filePath);
    this.state = emptyState(chainId, registryAddress);
  }

  /** Load state from disk. Creates empty state if file does not exist. */
  load(): void {
    if (!fs.existsSync(this.filePath)) {
      this.save(); // create initial file
      return;
    }

    const raw = fs.readFileSync(this.filePath, 'utf-8');
    const parsed: KeeperState = JSON.parse(raw);

    if (parsed.schemaVersion !== SCHEMA_VERSION) {
      throw new Error(
        `KeeperState: schema version mismatch -- file=${parsed.schemaVersion} expected=${SCHEMA_VERSION}. ` +
        `Delete ${this.filePath} to reset state.`
      );
    }

    if (parsed.chainId !== this.state.chainId) {
      throw new Error(
        `KeeperState: chain ID mismatch -- file=${parsed.chainId} config=${this.state.chainId}. ` +
        `Delete ${this.filePath} or fix KEEPER_CHAIN_ID.`
      );
    }

    if (parsed.registryAddress.toLowerCase() !== this.state.registryAddress.toLowerCase()) {
      throw new Error(
        `KeeperState: registry address mismatch -- file=${parsed.registryAddress} config=${this.state.registryAddress}. ` +
        `Delete ${this.filePath} or fix KEEPER_REGISTRY_ADDRESS.`
      );
    }

    this.state = parsed;
  }

  /** Atomically write state to disk (write + rename). */
  save(): void {
    const tmp = this.filePath + '.tmp';
    fs.writeFileSync(tmp, JSON.stringify(this.state, null, 2), 'utf-8');
    fs.renameSync(tmp, this.filePath);
  }

  // ── Accessors ─────────────────────────────────────────────────────────────

  getState(): Readonly<KeeperState> { return this.state; }

  getValidator(id: string): ValidatorRecord | undefined {
    return this.state.validators[id.toLowerCase()];
  }

  upsertValidator(record: ValidatorRecord): void {
    this.state.validators[record.validationId.toLowerCase()] = record;
  }

  markSyncAttempted(id: string, txHash: string | null): void {
    const r = this.ensureRecord(id);
    r.syncPending = false; // will be re-evaluated on next poll
    r.lastSyncAttemptAt = Date.now();
    r.lastTxHash = txHash;
    r.consecutiveFailures++;
    this.state.totalSyncsAttempted++;
    this.save();
  }

  markSyncSucceeded(id: string, txHash: string): void {
    const r = this.ensureRecord(id);
    r.lastSuccessfulSyncAt = Date.now();
    r.lastTxHash = txHash;
    r.consecutiveFailures = 0;
    this.state.totalSyncsSucceeded++;
    this.save();
  }

  markSyncFailed(id: string): void {
    const r = this.ensureRecord(id);
    r.syncPending = true; // will be retried
    this.state.totalSyncsFailed++;
    this.save();
  }

  updateLastPoll(blockNumber: number): void {
    this.state.lastPollAt = Date.now();
    this.state.lastBlockProcessed = blockNumber;
    this.save();
  }

  getPendingSyncs(): ValidatorRecord[] {
    return Object.values(this.state.validators).filter(r => r.syncPending);
  }

  getConsecutiveFailures(id: string): number {
    return this.state.validators[id.toLowerCase()]?.consecutiveFailures ?? 0;
  }

  private ensureRecord(id: string): ValidatorRecord {
    const key = id.toLowerCase();
    if (!this.state.validators[key]) {
      this.state.validators[key] = {
        validationId:          key,
        lastKnownStatus:       0,
        syncPending:           false,
        weightUpdatePending:   false,
        consecutiveFailures:   0,
        lastSyncAttemptAt:     0,
        lastSuccessfulSyncAt:  0,
        lastTxHash:            null,
      };
    }
    return this.state.validators[key];
  }
}
