# PW-C10 Phase Transition Audit Report
**PrimeWave Chain — Phase-1 → Phase-2 PoS Transition**
**Date:** 2026-08-14
**Scope:** Phase transition mechanics, validator churn, unbonding timing

---

## 1. Executive Summary

This document audits the Phase-1 → Phase-2 PoS transition from the perspective of correctness, atomicity, and adversarial resistance. The transition is triggered by deploying and initializing `PrimeWaveStakingManager`, which registers itself with `RewardVault` and begins Phase-2 emission.

**Result:** All 25 phase-transition tests and 12 validator-churn tests pass. No transition integrity issues found.

---

## 2. Transition Mechanics

### 2.1 Transition Trigger

Phase-2 begins when `PrimeWaveStakingManager.initialize()` is called. This call:

1. Validates the `RewardVault` address
2. Calls `rewardVault.setStakingManager(address(this))` — this is the point of no return
3. Emits `PhaseTransitionInitiated` and `PhaseTransitionCompleted` events

The vault's `setStakingManager()` function is admin-gated and can only be called once (`stakingManager` slot cannot be overwritten). After this call, the vault is in Phase-2 mode.

### 2.2 Atomicity

The transition is atomic from the EVM's perspective: either `initialize()` completes (including the `setStakingManager` call) or it reverts entirely. There is no partial transition state. ✓

### 2.3 Observability

Two events are emitted during initialization:
- `PhaseTransitionInitiated(stakingManager, rewardVault)` — at start of `initialize()`
- `PhaseTransitionCompleted(stakingManager, rewardVault)` — at end of `initialize()`

Off-chain monitoring can confirm Phase-2 activation by scanning for both events in the same transaction. ✓

---

## 3. Phase-Transition Test Coverage

### 3.1 Pre-Transition State (Tests PT-01 through PT-05)

| Test | Description | Result |
|------|-------------|--------|
| PT-01 | Vault accrues emission before StakingManager registered | PASS |
| PT-02 | Phase-2 initialization emits both transition events | PASS |
| PT-03 | `setStakingManager` cannot be called twice | PASS — `RV: staking manager already set` |
| PT-04 | Validator registration blocked until Phase-2 active | PASS |
| PT-05 | Emission index is consistent across transition boundary | PASS |

### 3.2 Transition Boundary (Tests PT-06 through PT-10)

| Test | Description | Result |
|------|-------------|--------|
| PT-06 | First validator registered immediately after transition | PASS |
| PT-07 | Emission accounting is continuous (no gap at boundary) | PASS |
| PT-08 | Multiple validators can register in the same block as transition | PASS |
| PT-09 | Transition with non-zero pre-existing vault balance | PASS |
| PT-10 | Transition event order: Initiated before Completed | PASS |

### 3.3 Post-Transition Invariants (Tests PT-11 through PT-25)

| Test | Description | Result |
|------|-------------|--------|
| PT-11 | Phase-2 validators accrue rewards from registration block | PASS |
| PT-12 | Phase-2 claim correctly separated from Phase-1 accrual | PASS |
| PT-13 | Cannot re-initialize StakingManager after first init | PASS |
| PT-14 | Pausing vault does not revert transition | PASS |
| PT-15 | Transition with minimum stake validators | PASS |
| PT-16 | Transition with maximum stake validators | PASS |
| PT-17 | Weight proportionality correct immediately post-transition | PASS |
| PT-18 | Rate reduction post-transition affects only future emission | PASS |
| PT-19 | Emergency pause post-transition blocks new claims | PASS |
| PT-20 | Timelock can operate normally post-transition | PASS |
| PT-21–25 | Multi-validator churn, edge cases | PASS |

---

## 4. Validator Churn Tests

**Test file:** `contracts/test/C10ValidatorChurn.t.sol`

| Test | Scenario | Result |
|------|----------|--------|
| VC-01 | Rapid registration of 10 validators in quick succession | PASS |
| VC-02 | Simultaneous exit of all validators | PASS |
| VC-03 | Validator exits and immediately re-registers | PASS |
| VC-04 | High churn with reward continuity across registrations | PASS |
| VC-05 | Validator exits at exactly minimum stake duration boundary | PASS |
| VC-06 | `MAX_CHURN_PERIOD` enforcement at validator registration | PASS |
| VC-07 | Partial exit (some validators remain active) | PASS |
| VC-08 | Zero-weight validator cannot register | PASS |
| VC-09 | Weight update during active validation period | PASS |
| VC-10 | Reward accounting preserved through high-churn epoch | PASS |
| VC-11 | Churn with paused vault — registration blocked | PASS |
| VC-12 | Re-registration after full exit — fresh reward accrual | PASS |

**All 12 churn tests pass.** ✓

---

## 5. Unbonding Timing Tests

**Test file:** `contracts/test/C10TimestampUnbonding.t.sol`

### 5.1 Critical Timing Invariants

| Test | Scenario | Result |
|------|----------|--------|
| TU-01 | Exit before minimum stake duration — reverts | PASS |
| TU-02 | Exit at exactly minimum stake duration boundary — succeeds | PASS |
| TU-03 | 14-day unbonding period enforced on `completeValidatorRemoval` | PASS |
| TU-04 | Timestamp manipulation cannot bypass unbonding | PASS |
| TU-05 | Reward accrual during unbonding period is zero | PASS |
| TU-06 | Stake returned at exactly correct amount after unbonding | PASS |
| TU-07 | Multi-day unbonding with warp — correct reward cutoff | PASS |
| TU-08 | Forced exit does not bypass unbonding | PASS |
| TU-09 | Rapid `initiateRemoval` + `completeRemoval` before delay — reverts | PASS |
| TU-10 | Long-duration stake (1 year) — full reward, correct exit | PASS |
| TU-11 | Reward stops accruing at removal initiation timestamp | PASS |
| TU-12 | Simultaneous unbonding of multiple validators | PASS |
| TU-13 | Validator cannot re-register during unbonding period | PASS |
| TU-14 | Uptime proof submitted during unbonding not counted for reward | PASS |
| TU-15 | Fork safety: block.timestamp monotone — no retroactive unbonding bypass | PASS |

**All 15 unbonding tests pass.** ✓

---

## 6. Phase-Transition Attack Resistance

### 6.1 Double-Initialization Attack

**Attempt:** Call `initialize()` twice to reset the staking manager slot and re-link a malicious vault.
**Outcome:** OZ `Initializable` reverts on second call with `InvalidInitialization`. ✓

### 6.2 Transition Race — Register Before Vault Set

**Attempt:** Register a validator before `setStakingManager()` links the vault, to receive rewards with no vault backing.
**Outcome:** The validator registration flow calls `rewardVault.registerRecipient()` via the staking manager, which requires `stakingManager == msg.sender`. Before the link is established, this call reverts. ✓

### 6.3 Timestamp Frontrunning on Unbonding

**Attempt:** Submit a `completeValidatorRemoval` in the same block as `initiateValidatorRemoval` to bypass the 14-day wait.
**Outcome:** The unbonding end time is stored as `block.timestamp + unbondingPeriod` and checked strictly in `completeValidatorRemoval`. Same-block completion reverts. ✓

---

## 7. Conclusion

The Phase-1 → Phase-2 transition is atomic, observable, and irreversible. All 52 phase-transition, churn, and unbonding tests pass. No transition integrity vulnerabilities were found.
