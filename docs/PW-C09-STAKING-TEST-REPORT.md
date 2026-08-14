# PW-C09 Staking Test Report

Sprint: C09 — Phase-2 PoS + PrimeWaveStakingManager  
Date: 2026-08-14  
Forge version: v1.7.1  
Solc version: 0.8.30  

## Overall Result

| Scope | Tests | Result |
|---|---|---|
| Baseline (C00–C08) | 535 | ✅ ALL PASS |
| C09 new tests | 51 | ✅ ALL PASS |
| **Total** | **586** | **✅ ALL PASS** |

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
| 28 | `testFuzz_F1_rewardBounds` | 256 | ✅ PASS |
| 29 | `testFuzz_F1b_rewardMonotonicInUptime` | 256 | ✅ PASS |
| 30 | `testFuzz_F2_distributeInvariants` | 256 | ✅ PASS |
| 31 | `testFuzz_F2b_cannotOverdraw` | 256 | ✅ PASS |
| 32 | `testFuzz_F3_multipleDistributionsSolvent` | 256 | ✅ PASS |
| 33 | `testFuzz_F4_supplyCapHeld` | 256 | ✅ PASS |

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

### StakingManagerInvariant.t.sol (12 stateful invariant tests)

Added during final gate review to cover the full C09 invariant checklist.

#### INV-5: Annual rewards <= 3,000,000 PW

| # | Test | Runs | Result |
|---|---|---|---|
| 40 | `test_INV5_annualEmissionCapEnforced` | 1 | ✅ PASS |
| 41 | `testFuzz_INV5_rewardAtMaxRateNeverExceedsAnnualCap` | 256 | ✅ PASS |

#### INV-6: Total rewards <= 15,000,000 PW

| # | Test | Runs | Result |
|---|---|---|---|
| 42 | `testFuzz_INV6_totalRewardsBoundedByVaultFunding` | 256 | ✅ PASS |

#### INV-2: Stake conservation

| # | Test | Result |
|---|---|---|
| 43 | `test_INV2_stakeConservation_zeroReward` | ✅ PASS |
| 44 | `test_INV2_stakeConservation_withReward` | ✅ PASS |
| 45 | `testFuzz_INV2_stakeAlwaysReturned` (256 runs, aligned to 1 ether) | ✅ PASS |

#### INV-10: ValidatorManager remains authoritative

| # | Test | Result |
|---|---|---|
| 46 | `test_INV10_cannotCompleteUnissuedRegistration` | ✅ PASS |
| 47 | `test_INV10_completionRequiresValidatorManagerQueue` | ✅ PASS |

#### INV-11: FeeDistributor remains independent

| # | Test | Result |
|---|---|---|
| 48 | `test_INV11_feeDistributorUnaffectedByStaking` | ✅ PASS |

#### INV-12: Governance boundaries

| # | Test | Result |
|---|---|---|
| 49 | `test_INV12_setStakingManagerRequiresAdmin` | ✅ PASS |
| 50 | `test_INV12_setStakingManagerOnce` | ✅ PASS |
| 51 | `test_INV12_distributeOnlyByStakingManager` | ✅ PASS |

---

## C09 Invariant Coverage Summary

| Gate Invariant | Coverage | Test(s) |
|---|---|---|
| INV-1: No minting (total supply never increases) | ✅ | F2: `totalFunded unchanged` |
| INV-2: Stake conservation | ✅ | INV2 unit × 2 + fuzz × 256 |
| INV-3: Withdrawals <= deposits (cannot overdraw) | ✅ | F2b: `cannotOverdraw` |
| INV-4: Rewards <= vault reserve | ✅ | F1: `rewardBounds` |
| INV-5: Annual rewards <= 3M PW | ✅ | INV5 unit + fuzz × 256 |
| INV-6: Total rewards <= 15M PW | ✅ | F4: `supplyCapHeld` + INV6 fuzz × 256 |
| INV-7: Unauthorized reward claim impossible | ✅ | `distribute_revertsIfNotStakingManager` |
| INV-8: Unauthorized withdrawal impossible | ✅ | `security_onlyOwnerCanInitiateRemoval` |
| INV-9: 14-day unbonding cannot be bypassed | ✅ | `unbonding_earlyRemovalReverts` |
| INV-10: ValidatorManager remains authoritative | ✅ | INV10 × 2 |
| INV-11: FeeDistributor remains independent | ✅ | INV11 × 1 |
| INV-12: Governance boundaries intact | ✅ | INV12 × 3 |

---

## Build Warnings (non-blocking)

Pre-existing warnings in C00–C08 test files only. No new warnings in C09 production contracts or invariant test file.
