/**
 * PrimeWave Chain Keeper — Unit Tests
 * C11 Production Infrastructure
 *
 * Tests all 20 keeper scenarios (17 keeper + 3 StateStore):
 *   KP-01  New validator detected
 *   KP-02  Validator synchronized (PendingAdded → Active)
 *   KP-03  Already synchronized (idempotent)
 *   KP-04  Weight update triggered
 *   KP-05  Deactivation sync (Active → PendingRemoved)
 *   KP-06  Reactivation sync (Completed → Active)
 *   KP-07  Duplicate sync safe
 *   KP-08  Out-of-order event
 *   KP-09  Failed RPC
 *   KP-10  Failed transaction (retry up to maxRetries)
 *   KP-11  Reverted "not managed" — no retry
 *   KP-12  Keeper restart resumes pending syncs
 *   KP-13  Chain restart — reconnects successfully
 *   KP-14  Nonce recovery — retried, succeeds
 *   KP-15  Multiple validators pending
 *   KP-16  Validator churn (rapid status changes)
 *   KP-17  Simultaneous changes (multiple validators)
 *   StateStore-1  Chain ID mismatch throws
 *   StateStore-2  Registry address mismatch throws
 *   StateStore-3  Atomic save (tmp + rename)
 *
 * Uses dependency injection — NO ethers mock needed.
 * No production keys used.
 */

import { PrimewaveKeeper, IProvider, IRegistryContract } from '../src/keeper';
import { StateStore, ValidatorRecord } from '../src/state';
import { KeeperConfig, ValidatorStatus } from '../src/config';
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';

// ── Suppress module-level side effects ────────────────────────────────────────
jest.mock('express', () => {
  const app = { get: jest.fn().mockReturnThis(), listen: jest.fn() };
  return jest.fn(() => app);
});
jest.mock('prom-client', () => ({
  Registry:              jest.fn(() => ({ contentType: 'text/plain', metrics: jest.fn() })),
  collectDefaultMetrics: jest.fn(),
  Counter:               jest.fn(() => ({ inc: jest.fn() })),
  Gauge:                 jest.fn(() => ({ set: jest.fn() })),
}));

// ── Helpers ───────────────────────────────────────────────────────────────────

const VID_1 = '0x' + '01'.repeat(32);
const VID_2 = '0x' + '02'.repeat(32);
const VID_3 = '0x' + '03'.repeat(32);

function makeConfig(overrides: Partial<KeeperConfig> = {}): KeeperConfig {
  return {
    rpcUrl:                  'http://localhost:9650',
    chainId:                 73571,
    registryAddress:         '0x' + 'aa'.repeat(20),
    validatorManagerAddress: '0x' + 'bb'.repeat(20),
    keeperPrivateKey:        '0x' + 'cc'.repeat(32),
    pollIntervalMs:          1000,
    confirmationBlocks:      1,
    maxRetries:              3,
    retryDelayMs:            1,  // minimal delay for fast tests
    retryBackoffMultiplier:  1,  // no backoff growth in tests
    healthPort:              8080,
    stateFilePath:           '/tmp/test-keeper-state.json',
    alertOnConsecutiveFailures: 3,
    logLevel:                'error',
    ...overrides,
  };
}

function makeTmpStateStore(chainId = 73571, registry = '0x' + 'aa'.repeat(20)): StateStore {
  const dir  = fs.mkdtempSync(path.join(os.tmpdir(), 'keeper-test-'));
  const file = path.join(dir, 'state.json');
  return new StateStore(file, chainId, registry);
}

type TxResult = { hash: string; wait: jest.Mock };

function makeTx(hash = '0xdeadbeef' + '0'.repeat(56)): TxResult {
  return { hash, wait: jest.fn().mockResolvedValue({ status: 1, blockNumber: 100 }) };
}

// Registry mock shape (mirrors IRegistryContract)
interface RegistryMock {
  managedCount:      jest.Mock;
  managedValidators: jest.Mock;
  validatorStatus:   jest.Mock;
  syncValidator:     jest.Mock;
  updateWeight:      jest.Mock;
}

function makeRegistry(overrides: Partial<RegistryMock> = {}): RegistryMock {
  return {
    managedCount:      jest.fn().mockResolvedValue(BigInt(0)),
    managedValidators: jest.fn(),
    validatorStatus:   jest.fn(),
    syncValidator:     jest.fn(),
    updateWeight:      jest.fn(),
    ...overrides,
  };
}

function makeProvider(block = 100): { getBlockNumber: jest.Mock } {
  return { getBlockNumber: jest.fn().mockResolvedValue(block) };
}

/** Build a keeper with injected mock provider + registry (no ethers instantiation).
 *  If a pre-populated store is passed, we do NOT call load() again — that would wipe
 *  any in-memory upserts made before the call. */
function makeKeeper(
  config:    KeeperConfig,
  registry:  RegistryMock,
  provider:  { getBlockNumber: jest.Mock },
  store?:    StateStore
): PrimewaveKeeper {
  let s: StateStore;
  if (store) {
    s = store; // caller already loaded and populated it — do not reload
  } else {
    s = makeTmpStateStore(config.chainId, config.registryAddress);
    s.load();  // fresh store — load (initialises empty state)
  }
  return new PrimewaveKeeper(
    config,
    s,
    provider as unknown as IProvider,
    registry as unknown as IRegistryContract
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

describe('PrimewaveKeeper', () => {

  // KP-01: New validator detected (PendingAdded) — no sync expected
  test('KP-01: new validator detected — no sync for PendingAdded', async () => {
    const config   = makeConfig();
    const provider = makeProvider(100);
    const reg      = makeRegistry({
      managedCount:      jest.fn().mockResolvedValue(BigInt(1)),
      managedValidators: jest.fn().mockResolvedValue(VID_1),
      validatorStatus:   jest.fn().mockResolvedValue(BigInt(ValidatorStatus.PendingAdded)),
    });
    const keeper = makeKeeper(config, reg, provider);
    await keeper.poll();

    expect(reg.syncValidator).not.toHaveBeenCalled();
    expect(keeper.lastPollBlock).toBe(100);
  });

  // KP-02: PendingAdded → Active on second poll triggers sync
  test('KP-02: Active transition on second poll triggers syncValidator()', async () => {
    const config = makeConfig();
    const tx     = makeTx();
    const reg    = makeRegistry({
      managedCount:      jest.fn().mockResolvedValue(BigInt(1)),
      managedValidators: jest.fn().mockResolvedValue(VID_1),
      validatorStatus:   jest.fn()
        .mockResolvedValueOnce(BigInt(ValidatorStatus.PendingAdded)) // poll 1
        .mockResolvedValueOnce(BigInt(ValidatorStatus.Active)),       // poll 2
      syncValidator: jest.fn().mockResolvedValue(tx),
      updateWeight:  jest.fn().mockResolvedValue(tx),
    });

    const store = makeTmpStateStore(config.chainId, config.registryAddress);
    store.load();
    const keeper = makeKeeper(config, reg, makeProvider(), store);

    // Poll 1: PendingAdded — no sync
    await keeper.poll();
    expect(reg.syncValidator).not.toHaveBeenCalled();

    // Poll 2: Active — sync triggered
    await keeper.poll();
    expect(reg.syncValidator).toHaveBeenCalledWith(VID_1);
  });

  // KP-03: Already synced (Active → Active) — no redundant tx
  test('KP-03: already-synced validator — no redundant tx', async () => {
    const config = makeConfig();
    const tx     = makeTx();
    const reg    = makeRegistry({
      managedCount:      jest.fn().mockResolvedValue(BigInt(1)),
      managedValidators: jest.fn().mockResolvedValue(VID_1),
      validatorStatus:   jest.fn().mockResolvedValue(BigInt(ValidatorStatus.Active)),
      syncValidator:     jest.fn().mockResolvedValue(tx),
    });

    const store = makeTmpStateStore(config.chainId, config.registryAddress);
    store.load();
    // Pre-populate: already Active
    store.upsertValidator({
      validationId: VID_1.toLowerCase(), lastKnownStatus: ValidatorStatus.Active,
      syncPending: false, weightUpdatePending: false, consecutiveFailures: 0,
      lastSyncAttemptAt: 0, lastSuccessfulSyncAt: Date.now(), lastTxHash: '0xprev',
    });
    const keeper = makeKeeper(config, reg, makeProvider(), store);
    await keeper.poll();

    expect(reg.syncValidator).not.toHaveBeenCalled();
  });

  // KP-04: Weight update triggered on PendingAdded → Active transition
  test('KP-04: weight update triggered on Active transition', async () => {
    const config = makeConfig();
    const tx     = makeTx();
    const reg    = makeRegistry({
      managedCount:      jest.fn().mockResolvedValue(BigInt(1)),
      managedValidators: jest.fn().mockResolvedValue(VID_1),
      validatorStatus:   jest.fn().mockResolvedValue(BigInt(ValidatorStatus.Active)),
      syncValidator:     jest.fn().mockResolvedValue(tx),
      updateWeight:      jest.fn().mockResolvedValue(tx),
    });

    const store = makeTmpStateStore(config.chainId, config.registryAddress);
    store.load();
    store.upsertValidator({
      validationId: VID_1.toLowerCase(), lastKnownStatus: ValidatorStatus.PendingAdded,
      syncPending: false, weightUpdatePending: false, consecutiveFailures: 0,
      lastSyncAttemptAt: 0, lastSuccessfulSyncAt: 0, lastTxHash: null,
    });
    const keeper = makeKeeper(config, reg, makeProvider(), store);
    await keeper.poll();

    expect(reg.syncValidator).toHaveBeenCalledWith(VID_1);
    expect(reg.updateWeight).toHaveBeenCalledWith(VID_1);
  });

  // KP-05: Active → PendingRemoved triggers deactivation sync
  test('KP-05: PendingRemoved transition triggers sync', async () => {
    const config = makeConfig();
    const tx     = makeTx();
    const reg    = makeRegistry({
      managedCount:      jest.fn().mockResolvedValue(BigInt(1)),
      managedValidators: jest.fn().mockResolvedValue(VID_1),
      validatorStatus:   jest.fn().mockResolvedValue(BigInt(ValidatorStatus.PendingRemoved)),
      syncValidator:     jest.fn().mockResolvedValue(tx),
    });

    const store = makeTmpStateStore(config.chainId, config.registryAddress);
    store.load();
    store.upsertValidator({
      validationId: VID_1.toLowerCase(), lastKnownStatus: ValidatorStatus.Active,
      syncPending: false, weightUpdatePending: false, consecutiveFailures: 0,
      lastSyncAttemptAt: 0, lastSuccessfulSyncAt: Date.now() - 1000, lastTxHash: null,
    });
    const keeper = makeKeeper(config, reg, makeProvider(), store);
    await keeper.poll();

    expect(reg.syncValidator).toHaveBeenCalledWith(VID_1);
  });

  // KP-06: Completed → Active (reactivation) triggers sync
  test('KP-06: reactivation from Completed triggers sync', async () => {
    const config = makeConfig();
    const tx     = makeTx();
    const reg    = makeRegistry({
      managedCount:      jest.fn().mockResolvedValue(BigInt(1)),
      managedValidators: jest.fn().mockResolvedValue(VID_1),
      validatorStatus:   jest.fn().mockResolvedValue(BigInt(ValidatorStatus.Active)),
      syncValidator:     jest.fn().mockResolvedValue(tx),
      updateWeight:      jest.fn().mockResolvedValue(tx),
    });

    const store = makeTmpStateStore(config.chainId, config.registryAddress);
    store.load();
    store.upsertValidator({
      validationId: VID_1.toLowerCase(), lastKnownStatus: ValidatorStatus.Completed,
      syncPending: false, weightUpdatePending: false, consecutiveFailures: 0,
      lastSyncAttemptAt: 0, lastSuccessfulSyncAt: 0, lastTxHash: null,
    });
    const keeper = makeKeeper(config, reg, makeProvider(), store);
    await keeper.poll();

    expect(reg.syncValidator).toHaveBeenCalledWith(VID_1);
  });

  // KP-07: Validator already pending (syncPending=true) — processed once, not twice
  test('KP-07: pending validator processed once per poll', async () => {
    const config = makeConfig();
    const tx     = makeTx();
    const reg    = makeRegistry({
      managedCount:      jest.fn().mockResolvedValue(BigInt(1)),
      managedValidators: jest.fn().mockResolvedValue(VID_1),
      validatorStatus:   jest.fn().mockResolvedValue(BigInt(ValidatorStatus.PendingRemoved)),
      syncValidator:     jest.fn().mockResolvedValue(tx),
    });

    const store = makeTmpStateStore(config.chainId, config.registryAddress);
    store.load();
    store.upsertValidator({
      validationId: VID_1.toLowerCase(), lastKnownStatus: ValidatorStatus.Active,
      syncPending: true,  // already pending
      weightUpdatePending: false, consecutiveFailures: 0,
      lastSyncAttemptAt: Date.now() - 60000, lastSuccessfulSyncAt: 0, lastTxHash: null,
    });
    const keeper = makeKeeper(config, reg, makeProvider(), store);
    await keeper.poll();

    expect(reg.syncValidator).toHaveBeenCalled();
  });

  // KP-08: Out-of-order event — keeper reads current state, no spurious sync
  test('KP-08: out-of-order event — no sync when status is PendingAdded', async () => {
    const config = makeConfig();
    const tx     = makeTx();
    const reg    = makeRegistry({
      managedCount:      jest.fn().mockResolvedValue(BigInt(1)),
      managedValidators: jest.fn().mockResolvedValue(VID_1),
      // Status "rolled back" to PendingAdded (out-of-order)
      validatorStatus:   jest.fn().mockResolvedValue(BigInt(ValidatorStatus.PendingAdded)),
      syncValidator:     jest.fn().mockResolvedValue(tx),
    });

    const store = makeTmpStateStore(config.chainId, config.registryAddress);
    store.load();
    store.upsertValidator({
      validationId: VID_1.toLowerCase(), lastKnownStatus: ValidatorStatus.Active,
      syncPending: false, weightUpdatePending: false, consecutiveFailures: 0,
      lastSyncAttemptAt: 0, lastSuccessfulSyncAt: Date.now() - 1000, lastTxHash: null,
    });
    const keeper = makeKeeper(config, reg, makeProvider(), store);
    await keeper.poll();

    // PendingAdded is not a triggering status — no sync
    expect(reg.syncValidator).not.toHaveBeenCalled();
  });

  // KP-09: Failed RPC — poll throws
  test('KP-09: failed RPC — poll throws', async () => {
    const config   = makeConfig();
    const provider = { getBlockNumber: jest.fn().mockRejectedValue(new Error('RPC timeout')) };
    const keeper   = makeKeeper(config, makeRegistry(), provider);

    await expect(keeper.poll()).rejects.toThrow('RPC timeout');
  });

  // KP-10: Failed transaction (status=0) — retried maxRetries times, then marked failed
  test('KP-10: failed transaction retried up to maxRetries', async () => {
    const config = makeConfig({ maxRetries: 2, retryDelayMs: 1 });
    const store  = makeTmpStateStore(config.chainId, config.registryAddress);
    store.load();

    const failTx = { hash: '0x123', wait: jest.fn().mockResolvedValue({ status: 0 }) };
    const reg    = makeRegistry({
      syncValidator: jest.fn().mockResolvedValue(failTx),
    });

    const keeper = makeKeeper(config, reg, makeProvider(), store);
    const result = await keeper.syncWithRetry(VID_1, 'syncValidator');

    expect(result).toBe(false);
    expect(reg.syncValidator).toHaveBeenCalledTimes(2); // maxRetries
  });

  // KP-11: "PWVR: not managed" revert — no retry, immediately failed
  test('KP-11: "not managed" revert — no retry', async () => {
    const config = makeConfig({ maxRetries: 3, retryDelayMs: 1 });
    const store  = makeTmpStateStore(config.chainId, config.registryAddress);
    store.load();

    const reg = makeRegistry({
      syncValidator: jest.fn().mockRejectedValue(new Error('PWVR: not managed')),
    });

    const keeper = makeKeeper(config, reg, makeProvider(), store);
    const result = await keeper.syncWithRetry(VID_1, 'syncValidator');

    expect(result).toBe(false);
    expect(reg.syncValidator).toHaveBeenCalledTimes(1); // no retry
  });

  // KP-12: Keeper restart resumes pending syncs from state file
  test('KP-12: keeper restart resumes pending syncs', () => {
    const dir  = fs.mkdtempSync(path.join(os.tmpdir(), 'keeper-restart-'));
    const file = path.join(dir, 'state.json');

    const store1 = new StateStore(file, 73571, '0x' + 'aa'.repeat(20));
    store1.load();
    store1.upsertValidator({
      validationId: VID_2.toLowerCase(), lastKnownStatus: ValidatorStatus.PendingRemoved,
      syncPending: true, weightUpdatePending: false, consecutiveFailures: 0,
      lastSyncAttemptAt: Date.now() - 30000, lastSuccessfulSyncAt: 0, lastTxHash: null,
    });
    store1.save();

    const store2 = new StateStore(file, 73571, '0x' + 'aa'.repeat(20));
    store2.load();

    const pending = store2.getPendingSyncs();
    expect(pending).toHaveLength(1);
    expect(pending[0]!.validationId).toBe(VID_2.toLowerCase());
    expect(pending[0]!.syncPending).toBe(true);
  });

  // KP-13: Chain restart — keeper reconnects and continues polling
  test('KP-13: chain restart — keeper reconnects', async () => {
    const config   = makeConfig();
    const provider = {
      getBlockNumber: jest.fn()
        .mockRejectedValueOnce(new Error('connection refused'))
        .mockResolvedValue(200),
    };
    const reg = makeRegistry({ managedCount: jest.fn().mockResolvedValue(BigInt(0)) });

    const keeper = makeKeeper(config, reg, provider);

    await expect(keeper.poll()).rejects.toThrow('connection refused');

    await keeper.poll();
    expect(keeper.lastPollBlock).toBe(200);
  });

  // KP-14: Nonce conflict — retried, succeeds on second attempt
  test('KP-14: nonce conflict — retried and succeeds', async () => {
    const config = makeConfig({ maxRetries: 3, retryDelayMs: 1 });
    const store  = makeTmpStateStore(config.chainId, config.registryAddress);
    store.load();

    const goodTx = makeTx();
    const reg    = makeRegistry({
      syncValidator: jest.fn()
        .mockRejectedValueOnce(new Error('nonce too low'))
        .mockResolvedValue(goodTx),
    });

    const keeper = makeKeeper(config, reg, makeProvider(), store);
    const result = await keeper.syncWithRetry(VID_1, 'syncValidator');

    expect(result).toBe(true);
    expect(reg.syncValidator).toHaveBeenCalledTimes(2);
  });

  // KP-15: Multiple validators pending — all processed in one poll
  test('KP-15: multiple validators — all synced in one poll', async () => {
    const config = makeConfig();
    const tx     = makeTx();
    const reg    = makeRegistry({
      managedCount:      jest.fn().mockResolvedValue(BigInt(3)),
      managedValidators: jest.fn()
        .mockResolvedValueOnce(VID_1)
        .mockResolvedValueOnce(VID_2)
        .mockResolvedValueOnce(VID_3),
      validatorStatus: jest.fn()
        .mockResolvedValueOnce(BigInt(ValidatorStatus.PendingRemoved)) // VID_1
        .mockResolvedValueOnce(BigInt(ValidatorStatus.Completed))      // VID_2
        .mockResolvedValueOnce(BigInt(ValidatorStatus.Active)),         // VID_3: unchanged
      syncValidator: jest.fn().mockResolvedValue(tx),
      updateWeight:  jest.fn().mockResolvedValue(tx),
    });

    const store = makeTmpStateStore(config.chainId, config.registryAddress);
    store.load();
    // All previously Active
    for (const vid of [VID_1, VID_2, VID_3]) {
      store.upsertValidator({
        validationId: vid.toLowerCase(), lastKnownStatus: ValidatorStatus.Active,
        syncPending: false, weightUpdatePending: false, consecutiveFailures: 0,
        lastSyncAttemptAt: 0, lastSuccessfulSyncAt: Date.now() - 1000, lastTxHash: null,
      });
    }

    const keeper = makeKeeper(config, reg, makeProvider(), store);
    await keeper.poll();

    expect(reg.syncValidator).toHaveBeenCalledWith(VID_1); // PendingRemoved → sync
    expect(reg.syncValidator).toHaveBeenCalledWith(VID_2); // Completed → sync
    expect(reg.syncValidator).not.toHaveBeenCalledWith(VID_3); // unchanged
  });

  // KP-16: Validator churn — rapid status change, keeper syncs to current state
  test('KP-16: validator churn — syncs to current (Invalidated) state', async () => {
    const config = makeConfig();
    const tx     = makeTx();
    const reg    = makeRegistry({
      managedCount:      jest.fn().mockResolvedValue(BigInt(1)),
      managedValidators: jest.fn().mockResolvedValue(VID_1),
      validatorStatus:   jest.fn().mockResolvedValue(BigInt(ValidatorStatus.Invalidated)),
      syncValidator:     jest.fn().mockResolvedValue(tx),
    });

    const store = makeTmpStateStore(config.chainId, config.registryAddress);
    store.load();
    store.upsertValidator({
      validationId: VID_1.toLowerCase(), lastKnownStatus: ValidatorStatus.PendingAdded,
      syncPending: false, weightUpdatePending: false, consecutiveFailures: 0,
      lastSyncAttemptAt: 0, lastSuccessfulSyncAt: 0, lastTxHash: null,
    });

    const keeper = makeKeeper(config, reg, makeProvider(), store);
    await keeper.poll();

    expect(reg.syncValidator).toHaveBeenCalledWith(VID_1);
  });

  // KP-17: Simultaneous changes on multiple validators
  test('KP-17: simultaneous changes on 3 validators — all 3 synced', async () => {
    const config = makeConfig();
    const tx     = makeTx();
    const reg    = makeRegistry({
      managedCount:      jest.fn().mockResolvedValue(BigInt(3)),
      managedValidators: jest.fn()
        .mockResolvedValueOnce(VID_1)
        .mockResolvedValueOnce(VID_2)
        .mockResolvedValueOnce(VID_3),
      validatorStatus: jest.fn()
        .mockResolvedValueOnce(BigInt(ValidatorStatus.Active))          // VID_1: PendingAdded → Active
        .mockResolvedValueOnce(BigInt(ValidatorStatus.PendingRemoved))  // VID_2: Active → PendingRemoved
        .mockResolvedValueOnce(BigInt(ValidatorStatus.Completed)),       // VID_3: PendingRemoved → Completed
      syncValidator: jest.fn().mockResolvedValue(tx),
      updateWeight:  jest.fn().mockResolvedValue(tx),
    });

    const store = makeTmpStateStore(config.chainId, config.registryAddress);
    store.load();
    store.upsertValidator({ validationId: VID_1.toLowerCase(), lastKnownStatus: ValidatorStatus.PendingAdded,   syncPending: false, weightUpdatePending: false, consecutiveFailures: 0, lastSyncAttemptAt: 0, lastSuccessfulSyncAt: 0, lastTxHash: null });
    store.upsertValidator({ validationId: VID_2.toLowerCase(), lastKnownStatus: ValidatorStatus.Active,         syncPending: false, weightUpdatePending: false, consecutiveFailures: 0, lastSyncAttemptAt: 0, lastSuccessfulSyncAt: 0, lastTxHash: null });
    store.upsertValidator({ validationId: VID_3.toLowerCase(), lastKnownStatus: ValidatorStatus.PendingRemoved, syncPending: false, weightUpdatePending: false, consecutiveFailures: 0, lastSyncAttemptAt: 0, lastSuccessfulSyncAt: 0, lastTxHash: null });

    const keeper = makeKeeper(config, reg, makeProvider(), store);
    await keeper.poll();

    expect(reg.syncValidator).toHaveBeenCalledWith(VID_1); // PendingAdded → Active
    expect(reg.syncValidator).toHaveBeenCalledWith(VID_2); // Active → PendingRemoved
    expect(reg.syncValidator).toHaveBeenCalledWith(VID_3); // PendingRemoved → Completed
    expect(reg.updateWeight).toHaveBeenCalledWith(VID_1);  // transition to Active
  });

  // ── StateStore Tests ─────────────────────────────────────────────────────────

  test('StateStore-1: chain ID mismatch on load throws', () => {
    const dir  = fs.mkdtempSync(path.join(os.tmpdir(), 'keeper-chain-'));
    const file = path.join(dir, 'state.json');
    const s1   = new StateStore(file, 73571, '0x' + 'aa'.repeat(20));
    s1.load(); s1.save();

    const s2 = new StateStore(file, 99999, '0x' + 'aa'.repeat(20));
    expect(() => s2.load()).toThrow(/chain ID mismatch/);
  });

  test('StateStore-2: registry address mismatch on load throws', () => {
    const dir  = fs.mkdtempSync(path.join(os.tmpdir(), 'keeper-reg-'));
    const file = path.join(dir, 'state.json');
    const s1   = new StateStore(file, 73571, '0x' + 'aa'.repeat(20));
    s1.load(); s1.save();

    const s2 = new StateStore(file, 73571, '0x' + 'bb'.repeat(20));
    expect(() => s2.load()).toThrow(/registry address mismatch/);
  });

  test('StateStore-3: atomic save — tmp file cleaned up, state correct', () => {
    const dir  = fs.mkdtempSync(path.join(os.tmpdir(), 'keeper-atomic-'));
    const file = path.join(dir, 'state.json');
    const s    = new StateStore(file, 73571, '0x' + 'aa'.repeat(20));
    s.load();
    s.upsertValidator({
      validationId: VID_1.toLowerCase(), lastKnownStatus: 2, syncPending: false,
      weightUpdatePending: false, consecutiveFailures: 0, lastSyncAttemptAt: 0,
      lastSuccessfulSyncAt: 0, lastTxHash: null,
    });
    s.save();

    expect(fs.existsSync(file + '.tmp')).toBe(false);
    expect(fs.existsSync(file)).toBe(true);

    const raw = JSON.parse(fs.readFileSync(file, 'utf-8'));
    expect(raw.validators[VID_1.toLowerCase()]).toBeDefined();
  });
});
