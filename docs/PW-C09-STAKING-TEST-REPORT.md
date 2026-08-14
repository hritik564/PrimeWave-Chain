# PW-C09 Staking Test Report

Sprint: C09 — Phase-2 PoS + PrimeWaveStakingManager  
Date: 2026-08-14  
Forge version: v1.7.1  
Solc version: 0.8.30  

## Overall Result

| Scope | Tests | Result |
|---|---|---|
| Baseline (C00–C08) | 535 | ✅ ALL PASS |
| C09 new tests | 39 | ✅ ALL PASS |
| **Total** | **574** | **✅ ALL PASS** |

---

## C09 New Tests

### StakingManagerUnit.t.sol (27 unit tests)

#### A) RewardVault.distribute() — role, invariants, zero-amount

| # | Test | Result |
|---|---|---|
| 1 | `test_distribute_basic` | ✅ PASS |
| 2 | `test_distribute_revertsIfNotStakingManager` | ✅ PASS |
| 3 | `test_distribute_zeroAmountIsNoOp` | ✅ PASS |
| 4 | `test_distribute_revertsIfExceedsReserve` | ✅ PASS |
| 5 | `test_distribute_revertsZeroRecipient` | ✅ PASS |
| 6 | `test_distribute_invariantsHoldAfterDistribute` | ✅ PASS |
| 7 | `test_distribute_setStakingManagerOnce` | ✅ PASS |
| 8 | `test_distribute_revertsWhenPaused` | ✅ PASS |
| 9 | `test_distribute_reentrancyGuard` | ✅ PASS |

#### B) PrimeWaveRewardCalculator — uptime / duration edge cases

| # | Test | Result |
|---|---|---|
| 10 | `test_calc_fullUptimeReward` | ✅ PASS |
| 11 | `test_calc_zeroUptimeReward` | ✅ PASS |
| 12 | `test_calc_halfUptimeReward` | ✅ PASS |
| 13 | `test_calc_zeroStakingDuration` | ✅ PASS |
| 14 | `test_calc_cappedByVaultAvailable` | ✅ PASS |
| 15 | `test_calc_vaultExhausted` | ✅ PASS |
| 16 | `test_calc_uptimeClampedToValidationDuration` | ✅ PASS |

#### C) PrimeWaveStakingManager.initialize() validation

| # | Test | Result |
|---|---|---|
| 17 | `test_init_revertsZeroVault` | ✅ PASS |
| 18 | `test_init_revertsZeroUptimeBlockchainID` | ✅ PASS |
| 19 | `test_init_revertsMinStakeDurationBelowChurnPeriod` | ✅ PASS |
| 20 | `test_init_cannotInitializeTwice` | ✅ PASS |

#### D) Full staking lifecycle

| # | Test | Result |
|---|---|---|
| 21 | `test_lifecycle_noUptimeProof_zeroReward` | ✅ PASS |
| 22 | `test_lifecycle_withUptimeProof_nonZeroReward` | ✅ PASS |

#### E) Unbonding enforcement

| # | Test | Result |
|---|---|---|
| 23 | `test_unbonding_earlyRemovalReverts` | ✅ PASS |
| 24 | `test_unbonding_exactBoundarySucceeds` | ✅ PASS |

#### F) Security

| # | Test | Result |
|---|---|---|
| 25 | `test_security_stakeBelowMinReverts` | ✅ PASS |
| 26 | `test_security_stakeAboveMaxReverts` | ✅ PASS |
| 27 | `test_security_onlyOwnerCanInitiateRemoval` | ✅ PASS |

---

### StakingManagerFuzz.t.sol (6 fuzz tests)

Each fuzz test ran 256 runs with randomised inputs.

| # | Test | Runs | Result |
|---|---|---|---|
| 28 | `testFuzz_rewardBoundedByVaultReserve` | 256 | ✅ PASS |
| 29 | `testFuzz_rewardMonotonicInUptime` | 256 | ✅ PASS |
| 30 | `testFuzz_rewardMonotonicInDuration` | 256 | ✅ PASS |
| 31 | `testFuzz_stakeReturnedInvariant` | 256 | ✅ PASS |
| 32 | `testFuzz_vaultTotalClaimedLeqTotalEmitted` | 256 | ✅ PASS |
| 33 | `testFuzz_vaultTotalEmittedLeqTotalFunded` | 256 | ✅ PASS |

---

### IntegrationC09.t.sol (6 integration tests)

| # | Test | Result |
|---|---|---|
| 34 | `test_IC09_fullLifecycleWithUptime` | ✅ PASS |
| 35 | `test_IC09_twoValidatorsGetFullRate` | ✅ PASS |
| 36 | `test_IC09_emergencyPauseBlocksDistribute` | ✅ PASS |
| 37 | `test_IC09_phase1AndPhase2CoexistInVault` | ✅ PASS |
| 38 | `test_IC09_stakeAlwaysReturned` | ✅ PASS |
| 39 | `test_IC09_stakingManagerSetOnce` | ✅ PASS |

---

## Build Warnings (non-blocking)

- Unused local variables in pre-existing test files (GovernanceFuzz, IntegrationC08, RewardVaultUnit).
- `_lock()` can be declared `pure` — intentional; override signature matches base.
- `forge-lint`: divide-before-multiply in pre-existing invariant test (not C09 code).

All warnings are pre-existing or intentional design choices. No warnings in C09 production contracts.
