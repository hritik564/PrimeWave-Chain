# PW-C09 Final Report

Sprint: C09 — Phase-2 PoS + PrimeWaveStakingManager  
Date: 2026-08-14  
Status: **COMPLETE — LOCKED**

---

## Summary

C09 introduces Phase-2 Proof-of-Stake validation on PrimeWave Chain by implementing `PrimeWaveStakingManager` — a concrete Avalanche `StakingManager` subclass — paired with `PrimeWaveRewardCalculator` (continuous uptime-weighted emissions). The existing `RewardVault` was extended with a new `distribute()` path gated to the staking manager. All 574 tests pass.

---

## Deliverables

### New Production Contracts

| Contract | Purpose |
|---|---|
| `contracts/src/PrimeWaveStakingManager.sol` | Extends Avalanche `StakingManager`; overrides `_reward()` → `vault.distribute()`, `_lock()` → stake receipt, `_unlock()` → ETH `.call{value}` return |
| `contracts/src/PrimeWaveRewardCalculator.sol` | Implements `IRewardCalculator`; formula: `rate × stakingDuration × (uptimeSeconds / validationDuration)`, capped at vault available reserve |

### Modified Production Contracts

| Contract | Change |
|---|---|
| `contracts/src/RewardVault.sol` | Added `stakingManager` address, `setStakingManager()` (admin, one-time), `distribute(address, uint256)` (nonReentrant, whenNotPaused), two events |

### New Test Infrastructure

| File | Purpose |
|---|---|
| `contracts/test/MockAvalancheValidatorManager.sol` | Full `IValidatorManager` mock; sequential message-index queues for registration/removal; no Warp dependency |
| `contracts/test/MockWarpMessenger.sol` | Etched at `0x0200…0005`; `setUptimeResponse()` builds valid uptime Warp messages via `ValidatorMessages.packValidationUptimeMessage` |
| `contracts/test/StakingManagerUnit.t.sol` | 27 unit tests (sections A–F) |
| `contracts/test/StakingManagerFuzz.t.sol` | 6 fuzz tests (256 runs each) |
| `contracts/test/IntegrationC09.t.sol` | 6 integration tests |

### New Library Dependencies

| Library | Version | Location |
|---|---|---|
| `openzeppelin-contracts` | v5.1.0 | `contracts/lib/openzeppelin-contracts/` |
| `openzeppelin-contracts-upgradeable` | v5.1.0 | `contracts/lib/openzeppelin-contracts-upgradeable/` |
| ICM StakingManager + interfaces (local copy) | icm-relayer-v1.7.5 | `contracts/lib/icm-contracts/avalanche/` |

### New Scripts / Docs

| File | Purpose |
|---|---|
| `contracts/script/DeployC09.s.sol` | Forge deployment script: calculator → staking manager → initialize → setStakingManager |
| `docs/PW-C09-AVALANCHE-STAKING-COMPATIBILITY.md` | Pre-implementation compatibility report (20 stop conditions evaluated) |
| `docs/PW-C09-STAKING-SPEC.md` | Full staking specification |
| `docs/PW-C09-STAKING-TEST-REPORT.md` | Per-test pass/fail record |

---

## Architecture Decisions

### 1. Continuous Uptime-Weighted Reward Formula

```
reward = rate × stakingDuration × (min(uptimeSeconds, validationDuration) / validationDuration)
```

- `rate` = `RewardVault.emissionRatePerSecond` at the time of removal (snapshot on each calculator call)
- `stakingDuration` = `stakingEndTime - stakingStartTime` (seconds)
- Uptime fraction is clamped at 1 (no over-credit for reported uptime > validation window)
- Result is additionally capped at `vault.totalFunded() - vault.totalClaimed()` (available reserve)

This bridges Avalanche's lump-sum `IRewardCalculator.calculateReward()` interface with PrimeWave's continuous emission model. The stake amount parameter is accepted by the interface but intentionally unused — PrimeWave rewards are rate-based, not stake-proportional.

### 2. ETH-Native Staking via _lock / _unlock

`StakingManager._lock(uint256 value)` is called by the base class during `_initiateValidatorRegistration`. PrimeWave's override simply returns `value` (the ETH sent as `msg.value`), holding funds in the contract. `_unlock(address owner, uint256 value)` is called by the base class during `completeValidatorRemoval` and transfers ETH back to the owner via low-level `.call{value}`.

No ERC-20 token or wrapping is used. ETH held in `PrimeWaveStakingManager` equals total active stake.

### 3. RewardVault.distribute() Gated to Staking Manager

`_reward(address recipient, uint256 amount)` is called by `StakingManager.completeValidatorRemoval` after unlock. PrimeWave's override calls `rewardVault.distribute(recipient, amount)`, which:
- Requires `msg.sender == stakingManager` (one-time set by admin)
- Requires `whenNotPaused` (respects EMS emergency stop)
- Is `nonReentrant`
- Increments both `totalEmitted` and `totalClaimed`

**Why both counters?** In C08's model, `totalEmitted` tracks epoch accrual and `totalClaimed` tracks actual transfers. PoS rewards bypass epoch accrual (they are computed per-validator on removal), so both counters are incremented together in `distribute()`. The invariant `totalClaimed ≤ totalEmitted ≤ totalFunded` is preserved.

### 4. Zero-Reward Removal via forceInitiateValidatorRemoval

`StakingManager.initiateValidatorRemoval` reverts with `ValidatorIneligibleForRewards` when the computed reward is 0. This is Avalanche upstream behaviour. To remove a validator with zero reward (e.g. no uptime proof ever submitted), call `forceInitiateValidatorRemoval` instead, which ignores the return value and proceeds with removal regardless.

### 5. Delegation Disabled

`maximumStakeMultiplier = 1` in `StakingManagerSettings`, preventing any delegation. This enforces the solo-validator Phase-2 design.

### 6. 14-Day Unbonding

`minimumStakeDuration = 1_209_600` seconds (14 × 86,400). Validators cannot initiate removal before their stake has been active for at least 14 days. The base class enforces this at `initiateValidatorRemoval` time using `validator.endTime < validator.startTime + minStakeDuration`.

---

## Implementation Blockers Encountered and Resolved

### Blocker 1: OZ contracts-upgradeable not cloned

The shallow git clone of `openzeppelin-contracts-upgradeable@v5.1.0` in the previous session produced an empty directory. Fixed by re-cloning in the current session.

**Resolution:** `git clone --depth 1 --branch v5.1.0 https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable.git`

### Blocker 2: IWarpMessenger calldata return type incompatible with mock

The Avalanche `IWarpMessenger` interface declares `getVerifiedWarpMessage()` returning `WarpMessage calldata`. Solidity prohibits concrete contracts from returning a `storage` slot as `calldata`. Fixed by changing the local copy's return type to `memory` — valid for test purposes since the mock is never deployed as an actual precompile.

**Resolution:** Modified `contracts/lib/icm-contracts/avalanche/subnet-evm/IWarpMessenger.sol` to use `memory` return data location.

### Blocker 3: MockAvalancheValidatorManager missing initializeValidatorSet stub

`IACP99Manager` declares `initializeValidatorSet(ConversionData, uint32)` which was not implemented in the mock. Added a no-op stub since this function is only called during Phase-1 → Phase-2 network bootstrap, not during per-validator tests.

### Blocker 4: INITIAL_RATE rational constant

`3_000_000 ether / (365 * 24 * 60 * 60)` does not produce an exact integer (GCD = 48,000 leaves remainder in numerator). Solidity's compile-time evaluator kept it as `rational_const 62500000000000000000/657` and refused to assign it to `uint256`.

**Resolution:** Made `INITIAL_RATE` a non-constant state variable, computed at test runtime as `uint256(3_000_000 * 1 ether) / 31_536_000` in `setUp()`, which uses runtime integer (floor) division matching `RewardVault.MAX_RATE_PER_SECOND` exactly.

### Blocker 5: vm.prank consumed by argument evaluation

In `test_calc_vaultExhausted`, the test called `vault.distribute(rewarded, vault.totalFunded())`. Solidity evaluates arguments left-to-right before the outer call; `vault.totalFunded()` (a staticcall) consumed the active `vm.prank`, leaving `distribute()` called without the prank, causing "RV: not staking manager".

**Resolution:** Captured `totalFunded` in a local variable before `vm.prank`.

### Blocker 6: initiateValidatorRemoval reverts on zero reward

Avalanche upstream: `initiateValidatorRemoval` calls `_initiatePoSValidatorRemoval` which returns `reward > 0`, and the outer `_initiateValidatorRemovalWithCheck` reverts with `ValidatorIneligibleForRewards` when false. Tests that remove a validator with no uptime proof (reward = 0) must use `forceInitiateValidatorRemoval` instead.

**Resolution:** Updated `test_lifecycle_noUptimeProof_zeroReward`, `test_unbonding_exactBoundarySucceeds`, and `test_IC09_stakeAlwaysReturned` to call `forceInitiateValidatorRemoval`.

---

## Test Coverage

| Area | Unit | Fuzz | Integration |
|---|---|---|---|
| RewardVault.distribute() | 9 | 2 | 3 |
| PrimeWaveRewardCalculator | 7 | 3 | 1 |
| PrimeWaveStakingManager init | 4 | — | — |
| Full lifecycle (with uptime) | 1 | 1 | 2 |
| Full lifecycle (zero uptime) | 1 | — | 1 |
| Unbonding enforcement | 2 | — | — |
| Security / access control | 3 | — | — |
| Phase-1 / Phase-2 coexistence | — | — | 1 |
| Emergency pause | — | — | 1 |

---

## Invariants Verified by Fuzz

1. **Reward bounded by vault reserve** — `reward ≤ vault.totalFunded() - vault.totalClaimed()` for all inputs
2. **Reward monotonic in uptime** — more uptime ≥ more reward (for same stake and duration)
3. **Reward monotonic in duration** — longer duration ≥ more reward (for same stake and uptime fraction)
4. **Stake return invariant** — validator balance after removal = balance before removal + stakeAmount, regardless of reward
5. **totalClaimed ≤ totalEmitted** — always holds after distribute()
6. **totalEmitted ≤ totalFunded** — always holds after distribute()

---

## Gate Checklist

- [x] Compatibility report written before implementation (`PW-C09-AVALANCHE-STAKING-COMPATIBILITY.md`)
- [x] All 20 stop conditions evaluated — none triggered
- [x] All baseline tests still passing (535/535)
- [x] All C09 tests passing (39/39)
- [x] Total: 574/574
- [x] No new compiler errors
- [x] Staking spec written (`PW-C09-STAKING-SPEC.md`)
- [x] Test report written (`PW-C09-STAKING-TEST-REPORT.md`)
- [x] Final report written (this document)

**C09 is complete and locked.**
