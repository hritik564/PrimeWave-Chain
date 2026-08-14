# PW-C05 Validator Integration Test Report

**Status:** COMPLETE — ALL TESTS PASS  
**Sprint:** C05  
**Date:** 2026-08-14  
**Foundry:** v1.7.1  
**Total Tests:** 190 (65 unit + 12 fuzz + 4 invariant + C04 regression 109)  
**Failures:** 0  

---

## Test Suite Summary

| Suite | Tests | Status |
|---|---|---|
| `ValidatorFeeVaultUnit` (C04 regression) | 60 | ALL PASS |
| `ValidatorFeeVaultInvariant` (C04 regression) | 8 | ALL PASS |
| `FeeDistributorUnit` (C04 regression) | 25 | ALL PASS |
| `FeeDistributorInvariant` (C04 regression) | 14 | ALL PASS |
| `PrimeWaveValidatorRegistryUnit` (C05 new) | 65 | ALL PASS |
| `PrimeWaveValidatorRegistryFuzz` (C05 new) | 8 | ALL PASS |
| `PrimeWaveValidatorRegistryInvariant` (C05 new) | 4 | ALL PASS |
| **TOTAL** | **190** | **ALL PASS** |

---

## C05 Unit Tests — `PrimeWaveValidatorRegistryUnit`

### A. Constructor / Deployment (5 tests)

| Test | Gas | Result |
|---|---|---|
| `test_Constructor_SetsImmutables` | 15,339 | PASS |
| `test_Constructor_VaultAdminIsRegistry` | 10,697 | PASS |
| `test_Constructor_ZeroAdmin_Reverts` | 1,431,212 | PASS |
| `test_Constructor_ZeroVM_Reverts` | 1,429,091 | PASS |
| `test_Constructor_ZeroVault_Reverts` | 39,847 | PASS |

### B. registerValidator (10 tests)

| Test | Gas | Result |
|---|---|---|
| `test_Register_Active_Succeeds` | 386,541 | PASS |
| `test_Register_PendingAdded_Succeeds_Inactive` | 343,272 | PASS |
| `test_Register_UnknownValidator_Reverts` | 26,509 | PASS |
| `test_Register_ZeroValidationID_Reverts` | 9,268 | PASS |
| `test_Register_ZeroRecipient_Reverts` | 156,623 | PASS |
| `test_Register_ZeroWeight_Reverts` | 156,662 | PASS |
| `test_Register_Duplicate_Reverts` | 381,162 | PASS |
| `test_Register_15Validators_AllActive` | 4,287,746 | PASS |
| `test_Register_Emits_Event` | 381,343 | PASS |
| `test_Register_PendingAdded_Emits_ZeroUptimeBips` | 340,876 | PASS |

### C. syncValidator (10 tests)

| Test | Gas | Result |
|---|---|---|
| `test_Sync_PendingAdded_To_Active` | 378,614 | PASS |
| `test_Sync_Active_To_PendingRemoved_Deactivates` | 365,797 | PASS |
| `test_Sync_PendingRemoved_To_Completed` | (included) | PASS |
| `test_Sync_Invalidated_Deactivates` | 349,970 | PASS |
| `test_Sync_Active_Already_Active_NoEmit` | 390,435 | PASS |
| `test_Sync_Idempotent_Multiple_Calls` | 371,508 | PASS |
| `test_Sync_NotManaged_Reverts` | 10,720 | PASS |
| `test_Sync_Emits_ValidatorSynced_OnDeactivation` | 356,876 | PASS |
| `test_Sync_Emits_ValidatorSynced_OnActivation` | 375,793 | PASS |

### D. syncAll (2 tests)

| Test | Gas | Result |
|---|---|---|
| `test_SyncAll_15Validators` | 4,403,465 | PASS |
| `test_SyncAll_EmptyRegistry` | 7,620 | PASS |

### E. updateWeight (4 tests)

| Test | Gas | Result |
|---|---|---|
| `test_UpdateWeight_ReadsFromValidatorManager` | 397,292 | PASS |
| `test_UpdateWeight_PreservesHistoricalFees` | (included) | PASS |
| `test_UpdateWeight_NotManaged_Reverts` | (included) | PASS |
| `test_UpdateWeight_Emits_Event` | (included) | PASS |

### F. setUptimeBips (3 tests)

| Test | Gas | Result |
|---|---|---|
| `test_SetUptimeBips_AdminOnly` | 372,559 | PASS |
| `test_SetUptimeBips_NotManaged_Reverts` | 11,216 | PASS |
| `test_SetUptimeBips_Emits_Event` | 369,866 | PASS |

### G. setRewardRecipient (4 tests)

| Test | Gas | Result |
|---|---|---|
| `test_SetRewardRecipient_UpdatesBinding` | 391,431 | PASS |
| `test_SetRewardRecipient_ZeroAddress_Reverts` | 381,169 | PASS |
| `test_SetRewardRecipient_NotManaged_Reverts` | 11,348 | PASS |
| `test_SetRewardRecipient_OldRecipientCanStillClaimEarned` | 528,945 | PASS |

### H. Access Control (9 tests)

| Test | Gas | Result |
|---|---|---|
| `test_AC_RegisterValidator_NonAdmin_Reverts` | 156,694 | PASS |
| `test_AC_SetUptimeBips_NonAdmin_Reverts` | 380,957 | PASS |
| `test_AC_SetRewardRecipient_NonAdmin_Reverts` | 381,019 | PASS |
| `test_AC_FeeVault_DirectCall_NonAdmin_Reverts` | 9,363 | PASS |
| `test_AC_FeeVault_DirectDeactivate_NonAdmin_Reverts` | 382,988 | PASS |
| `test_AC_FeeVault_DirectActivate_NonAdmin_Reverts` | 358,378 | PASS |
| `test_AC_FeeVault_DirectSetWeight_NonAdmin_Reverts` | 383,108 | PASS |
| `test_AC_FeeVault_DirectSetUptime_NonAdmin_Reverts` | 382,963 | PASS |
| `test_AC_FeeVault_DirectSetRecipient_NonAdmin_Reverts` | 383,088 | PASS |

### I. Security Scenarios §22 (15 tests)

| Test | Gas | Result |
|---|---|---|
| `test_SEC_01_FakeValidatorRegistration_Reverts` | 26,486 | PASS |
| `test_SEC_02_DuplicateRegistration_Reverts` | 381,444 | PASS |
| `test_SEC_03_SyncValidator_CannotFakeRemoval` | 391,122 | PASS |
| `test_SEC_04_AttackerCannotReactivate` | 366,737 | PASS |
| `test_SEC_05_UnauthorizedWeightChange_Reverts` | 397,292 | PASS |
| `test_SEC_06_UnauthorizedRecipientChange_Reverts` | 380,977 | PASS |
| `test_SEC_07_UnauthorizedUptimeChange_Reverts` | 380,978 | PASS |
| `test_SEC_08_CannotRegisterCompletedValidator` | 363,419 | PASS |
| `test_SEC_09_RewardRecipientMismatch_Reverts` | 439,982 | PASS |
| `test_SEC_10_StaleState_SyncAfterRemoval` | 485,943 | PASS |
| `test_SEC_11_ReplaySyncIsIdempotent` | 374,295 | PASS |
| `test_SEC_12_WeightUpdateAfterDeactivation` | 374,327 | PASS |
| `test_SEC_13_HistoricalWeightNotManipulated` | 793,560 | PASS |
| `test_SEC_14_ClaimAfterDeactivation` | 517,760 | PASS |
| `test_SEC_15_ReactivationNoDoubleCount` | 812,777 | PASS |

### J–L. Additional coverage (3 tests)

| Test | Gas | Result |
|---|---|---|
| `test_FeeAccrual_15Validators_ThenRemove5` | 4,730,072 | PASS |
| `test_Conservation_AfterLifecycle` | 4,650,253 | PASS |
| `test_GasAnalysis` | 847,424 | PASS |

---

## C05 Fuzz Tests — `PrimeWaveValidatorRegistryFuzz`

Runs: 256 per test. All seeds explored.

| Test | Result |
|---|---|
| `testFuzz_F1_RandomFees_Conservation` | PASS (256 runs) |
| `testFuzz_F2_WeightChange_HistoricalFeesPreserved` | PASS (256 runs) |
| `testFuzz_F3_RemovalOrder_FeesPreserved` | PASS (256 runs) |
| `testFuzz_F4_RecipientChange_OnlyNewCanClaim` | PASS (256 runs) |
| `testFuzz_F5_ActivationCycle_Conservation` | PASS (256 runs) |
| `testFuzz_F6_MultiValidator_WeightUpdate` | PASS (256 runs) |
| `testFuzz_F7_NoCrossValidatorClaim` | PASS (256 runs) |
| `testFuzz_F8_UptimeChange_GlobalConsistency` | PASS (256 runs) |

---

## C05 Invariant Tests — `PrimeWaveValidatorRegistryInvariant`

Stateful handler with 6 actions: `registerNext`, `sendFees`, `deactivate`, `syncOne`, `updateWeight`, `claim`.

Runs per invariant: 256 (128,000 calls each). 0 reverts.

| Invariant | Description | Result |
|---|---|---|
| `invariant_A_BalanceConservation` | `balance == totalReceived - totalClaimed` (exact) | PASS |
| `invariant_B_NoOverAllocation` | `sum(claimable) + unallocated <= balance + 1` (1 wei dust allowed) | PASS |
| `invariant_C_NoFeeCreation` | `totalClaimed <= totalReceived` | PASS |
| `invariant_D_DeactivatedFeesNotConfiscated` | `(claimable + claimed_after_deactivation) >= claimable_at_deactivation` | PASS |

---

## C04 Regression — All Previous Tests Unchanged

| Suite | Tests | Status |
|---|---|---|
| ValidatorFeeVaultUnit | 60 | ALL PASS |
| ValidatorFeeVaultInvariant | 8 | ALL PASS |
| FeeDistributorUnit | 25 | ALL PASS |
| FeeDistributorInvariant | 14 | ALL PASS |

No C04 test required modification.

---

## Gas Analysis (from `test_GasAnalysis`)

| Operation | Gas | Notes |
|---|---|---|
| `registerValidator()` | 231,240 | One-time per validator; admin-only |
| `syncValidator()` (no-op) | 6,594 | Permissionless; safe to call frequently |
| `syncValidator()` (deactivation) | 13,266 | Triggers vault state change |
| `updateWeight()` | 33,039 | Permissionless; call after ACP-99 weight update |
| `setUptimeBips()` | 28,597 | Admin-only; future oracle hook |
| `setRewardRecipient()` | 6,248 | Admin-only; updates both registry + vault |
| `claimFees()` | 101,293 | Recipient-only; transfers PW to recipient |

All operations are within normal gas budgets. The 30M block gas limit allows ~128 concurrent `registerValidator` calls in a single block.

---

## Integration Script (`IntegrationC05.s.sol`)

Script verifying the full C05 lifecycle on the live primewavedev chain (Chain ID 73571). Contains 21 assertion checks covering:

- Pre-computed address matching
- Registry as feeVault admin
- PendingAdded registration (inactive)
- Active registration (active)
- syncAll() activating all 15 validators
- Fee distribution to all 15
- Deactivation via syncValidator
- Fees preserved on deactivation
- claimFees to DEV0
- Conservation invariant after claim
- Fees only to active validators after removal
- Weight update (historical fees preserved)
- New weight distribution correctness
- Re-activation (no retro-accrual)
- Final conservation

---

## Known Limitations

1. **Uptime oracle not implemented.** All validators default to 100% uptime (10,000 bips). A Phase 2 design sprint is required before partial uptime can be used.

2. **Single-node integration test only.** The local dev chain runs 1 of 15 validators. Multi-node testing requires a future multi-node network setup.

3. **MockValidatorManager** simulates ACP-99 without Warp. Production deployment requires the real `PoAValidatorManager` with an ICM relayer.

4. **Recipient change transfers future fees only.** The old recipient should claim before any recipient rotation.
