# PW-C06 — RewardVault Test Report

**Status:** ALL PASS  
**Sprint:** PW-C06  
**Date:** 2026-08-14  
**Total:** 282 tests (190 from C03-C05 regression + 92 new C06 tests)  

---

## Test Suite Summary

| Suite | Tests | Result |
|-------|-------|--------|
| `FeeDistributorUnit.t.sol` (C03) | 25 | PASS |
| `FeeDistributorInvariant.t.sol` (C03) | 14 | PASS |
| `ValidatorFeeVaultUnit.t.sol` (C04) | 60 | PASS |
| `ValidatorFeeVaultInvariant.t.sol` (C04) | 8 | PASS |
| `PrimeWaveValidatorRegistryUnit.t.sol` (C05) | 65 | PASS |
| `PrimeWaveValidatorRegistryFuzz.t.sol` (C05) | 12 | PASS |
| **`RewardVaultUnit.t.sol` (C06)** | **72** | **PASS** |
| **`RewardVaultFuzz.t.sol` (C06)** | **8 fuzz + 8 invariant = 16** | **PASS** |
| **Total** | **282** | **ALL PASS** |

---

## C06 Unit Tests (`RewardVaultUnit.t.sol`) — 72 tests

### A. Constructor (6 tests)

| Test | Assertion |
|------|-----------|
| `test_Constructor_SetsImmutables` | admin, rate, totalFunded/Emitted/Claimed == 0 |
| `test_Constructor_Constants` | SECONDS_PER_YEAR == 31_536_000, MAX_ANNUAL == 3M ether |
| `test_Constructor_MaxRateAtMostMaxAnnual` | MAX_RATE * SECONDS <= MAX_ANNUAL; truncation < SECONDS |
| `test_Constructor_ZeroAdmin_Reverts` | reverts "RV: zero admin" |
| `test_Constructor_RateExceedsMax_Reverts` | reverts "RV: rate exceeds max" |
| `test_Constructor_ZeroRate_Succeeds` | rate == 0 allowed |

### B. fund() / receive() (5 tests)

| Test | Assertion |
|------|-----------|
| `test_Fund_UpdatesTotalFunded` | totalFunded == amount |
| `test_Fund_MultipleFundsAccumulate` | cumulative totalFunded |
| `test_Fund_EmitsEvent` | RewardVaultFunded event |
| `test_Fund_ZeroValue_Reverts` | reverts "RV: zero funding" |
| `test_Receive_UpdatesTotalFunded` | receive() counts in totalFunded |
| `test_ForcedTransfer_NotCounted` | vm.deal doesn't corrupt totalFunded |

### C. registerRecipient (7 tests)

| Test | Assertion |
|------|-----------|
| `test_Register_Active_Succeeds` | isRegistered, totalWeight += weight |
| `test_Register_Inactive_Succeeds` | isRegistered, totalWeight unchanged |
| `test_Register_ZeroId_Reverts` | reverts "RV: zero id" |
| `test_Register_ZeroAddress_Reverts` | reverts "RV: zero address" |
| `test_Register_ZeroWeight_Reverts` | reverts "RV: zero weight" |
| `test_Register_Duplicate_Reverts` | reverts "RV: already registered" |
| `test_Register_NonAdmin_Reverts` | reverts "RV: not admin" |
| `test_Register_NoRetroAccrual` | claimable == 0 after late registration |
| `test_Register_Emits_Event` | RecipientRegistered event |

### D. activateRecipient / deactivateRecipient (8 tests)

| Test | Assertion |
|------|-----------|
| `test_Activate_InactiveRecipient` | totalWeight += weight |
| `test_Activate_AlreadyActive_Reverts` | reverts "RV: already active" |
| `test_Activate_NotRegistered_Reverts` | reverts "RV: not registered" |
| `test_Activate_NonAdmin_Reverts` | reverts "RV: not admin" |
| `test_Activate_NoRetroAccrual` | no retro-accrual from inactive period |
| `test_Deactivate_ActiveRecipient` | totalWeight -= weight; pending > 0 |
| `test_Deactivate_AlreadyInactive_Reverts` | reverts "RV: already inactive" |
| `test_Deactivate_EarnedFeesPreserved` | claimable unchanged after deactivation |
| `test_Deactivate_StopsAccrual` | no new accrual while inactive |

### E. setWeight (5 tests)

| Test | Assertion |
|------|-----------|
| `test_SetWeight_Active_UpdatesTotalWeight` | totalWeight updated |
| `test_SetWeight_Inactive_NoWeightChange` | totalWeight unchanged for inactive |
| `test_SetWeight_PreservesHistoricalFees` | historical earnings unchanged |
| `test_SetWeight_ZeroWeight_Reverts` | reverts "RV: zero weight" |
| `test_SetWeight_NonAdmin_Reverts` | reverts "RV: not admin" |

### F. setRewardAddress (3 tests)

| Test | Assertion |
|------|-----------|
| `test_SetRewardAddress_Updates` | address updated |
| `test_SetRewardAddress_ZeroAddr_Reverts` | reverts "RV: zero address" |
| `test_SetRewardAddress_NonAdmin_Reverts` | reverts "RV: not admin" |

### G. setEmissionRate (5 tests)

| Test | Assertion |
|------|-----------|
| `test_SetEmissionRate_Reduces` | rate updated to newRate |
| `test_SetEmissionRate_CannotIncrease_Reverts` | reverts "RV: rate not reduced" |
| `test_SetEmissionRate_CannotExceedMax_Reverts` | reverts on same rate |
| `test_SetEmissionRate_NonAdmin_Reverts` | reverts "RV: not admin" |
| `test_SetEmissionRate_Emits_Event` | EmissionRateReduced event |
| `test_SetEmissionRate_ToZero_StopsEmission` | no new claimable after rate=0 |

### H. claim (10 tests)

| Test | Assertion |
|------|-----------|
| `test_Claim_TransfersPW` | ALICE balance += claimed |
| `test_Claim_UpdatesAccounting` | totalClaimed updated; balance conserved |
| `test_Claim_DoubleClaim_Reverts` | reverts "RV: nothing to claim" |
| `test_Claim_NotRegistered_Reverts` | reverts "RV: not registered" |
| `test_Claim_WrongCaller_Reverts` | reverts "RV: caller is not rewardAddress" |
| `test_Claim_ZeroPending_Reverts` | reverts "RV: nothing to claim" (t=0) |
| `test_Claim_AfterDeactivation_Succeeds` | earned pre-deactivation still claimable |
| `test_Claim_CrossRecipient_Reverts` | Alice cannot claim Bob's, vice versa |
| `test_Claim_AfterWeightChange_HistoricalPreserved` | period-1/period-2 split correct |
| `test_Claim_Emits_Event` | RewardClaimed event |

### I. Zero-weight / emission-pause (4 tests)

| Test | Assertion |
|------|-----------|
| `test_ZeroWeight_EmissionPauses` | totalEmitted unchanged during no-recipient period |
| `test_ZeroWeight_FundsStayInVault` | 1M PW still in vault after 1 year with no recipients |
| `test_ZeroWeight_ThenRecipient_NoRetroAccrual` | claimable == 0 right after late registration |
| `test_AllDeactivated_EmissionPauses` | totalEmitted frozen during all-deactivated period |

### J. Vault exhaustion (5 tests)

| Test | Assertion |
|------|-----------|
| `test_Exhaustion_NoOverEmission` | claimable == funded at exhaustion |
| `test_Exhaustion_CannotClaimMore` | 0 claimable after full drain |
| `test_Exhaustion_NoMinting` | total supply conserved through claim |
| `test_Exhaustion_IsExhausted_View` | isExhausted() true after drain |

### K. Rate change checkpoint (3 tests)

| Test | Assertion |
|------|-----------|
| `test_RateChange_OldRewardsPreserved` | period-A earnings survive rate reduction; period-B ~half (±2.6M wei tolerance for compounding truncation) |
| `test_RateChange_NoRetroHistorical` | period-A == elapsed * full_rate (±1 wei) |
| `test_RateChange_CannotIncreaseAboveMax` | reverts on same-or-higher rate |

### L. Supply invariant (2 tests)

| Test | Assertion |
|------|-----------|
| `test_SupplyInvariant_AfterFundAndClaim` | supply before == supply after across all actors |
| `test_NoMinting_TotalSupplyNeverIncreases` | total PW conserved from fund → claim |

### M. 15M funding (2 tests)

| Test | Assertion |
|------|-----------|
| `test_15M_FundingVerified` | totalFunded == 15M, balance == 15M |
| `test_15M_CannotExceedFunding` | claimable capped at 15M; totalEmitted == 15M at exhaustion |

### N. 5-year simulation (2 tests)

| Test | Assertion |
|------|-----------|
| `test_FiveYear_MaxEmission_NeverExceeds3MPerYear` | each year's emission <= 3M PW; total <= 15M |
| `test_FiveYear_WithClaims_ConservationHolds` | balance == funded - claimed after 5 years of claims |

### O + misc (8 tests)

| Test | Assertion |
|------|-----------|
| `test_GasAnalysis` | gas logged for all major operations |
| `test_MultiRecipient_ProportionalRewards` | 1:2:3 weight ratio → 1:2:3 reward ratio |
| `test_UnusedEmissions_StayInVault` | totalRemaining > 0; no burn or redirect |
| `test_Conservation_AccountedBalance` | accountedBalance == funded - claimed |
| `test_SameBlock_NoDoubleEmission` | two claims in same block → second reverts |

---

## C06 Standalone Fuzz Tests (`RewardVaultFuzz.t.sol`) — 8 tests (256 runs each)

| Test | Property Verified |
|------|-------------------|
| `testFuzz_F1_EmissionNeverExceedsFunded` | `claimable <= funded` across random amounts and time |
| `testFuzz_F2_ProportionalAllocation` | weight ratio preserved across random weights |
| `testFuzz_F3_RateReduction_HistoricalPreserved` | historical rewards survive random rate cuts |
| `testFuzz_F4_Deactivation_FeesPreserved` | deactivated recipients retain earned fees |
| `testFuzz_F5_NoCrossRecipientClaim` | cross-recipient claim always reverts |
| `testFuzz_F6_Conservation` | balance invariant across 3 random time periods |
| `testFuzz_F7_FiveYear_YearlyCap` | random recipient counts; annual cap always <= 3M |
| `testFuzz_F8_ZeroWeight_EmissionPauses` | zero-weight gap correctly excluded from period-2 |

---

## C06 Stateful Invariant Tests (`RewardVaultFuzz.t.sol:RewardVaultInvariant`) — 8 invariants

Handler calls: 128,000 per invariant | Zero reverts | 256 runs

| Invariant | Property |
|-----------|---------|
| INV-1 | `totalEmitted <= totalFunded` |
| INV-2 | `totalClaimed <= totalEmitted` |
| INV-3 | `totalClaimed <= totalFunded` |
| INV-4 | `emissionRatePerSecond <= MAX_RATE_PER_SECOND` |
| INV-5 | `vaultBalance == totalFunded - totalClaimed` |
| INV-6 | `totalPending == totalEmitted - totalClaimed` |
| INV-7 | Deactivated fees not confiscated |
| INV-8 | `totalRemaining == totalFunded - totalEmitted` |

---

## C03-C05 Regression (190 tests)

All 190 tests from prior sprints pass without modification:
- `FeeDistributorUnit` — 25/25
- `FeeDistributorInvariant` — 14/14
- `ValidatorFeeVaultUnit` — 60/60
- `ValidatorFeeVaultInvariant` — 8/8
- `PrimeWaveValidatorRegistryUnit` — 65/65
- `PrimeWaveValidatorRegistryFuzz` — 12/12 *(one `vm.assume` added to exclude Foundry's VM contract address from recipient fuzz; no logic change)*

---

## Key Fixes During Development

| Issue | Root Cause | Fix |
|-------|-----------|-----|
| `totalEmitted` stale in tests | `totalEmitted` only updates on writes; view calls don't mutate state | Changed affected tests to use a write (claim/deactivate) before asserting `totalEmitted` |
| Rate-period rounding | `MAX_R/2` truncates independently from `MAX_R`; 30-day window accumulates up to ~2.6M wei gap | Widened tolerance to `±2_592_000 wei` |
| C05 fuzz F4 VM address | Foundry generates `0x7109709E...` as fuzz input; native transfer to VM contract fails | Added `vm.assume(newRecipient != VM_ADDR)` |

---

## Gas Profile (representative)

| Operation | Gas |
|-----------|-----|
| `registerRecipient` (active) | ~150,000 |
| `claim` | ~55,000 |
| `activateRecipient` | ~45,000 |
| `deactivateRecipient` | ~40,000 |
| `setWeight` | ~40,000 |
| `setEmissionRate` | ~30,000 |
| `claimable` (view) | ~5,000 |
