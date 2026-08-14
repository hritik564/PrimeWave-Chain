# PW-C10 Security Audit Report
**PrimeWave Chain — Phase-2 PoS Hardening Sprint**
**Date:** 2026-08-14
**Auditor:** In-house (C10 Sprint)
**Scope:** All contracts in `contracts/src/`

---

## 1. Executive Summary

This audit was conducted as part of Sprint C10 — the hardening and attack-simulation sprint that follows the full Phase-2 PoS implementation (C00–C09). The audit covered reentrancy attacks, governance manipulation, malicious participants, timestamp manipulation, fee isolation violations, and long-horizon economic invariants.

**Result: No Critical or High severity issues found.**

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High     | 0 |
| Medium   | 2 |
| Low      | 3 |
| Info     | 4 |

All findings are documented below. No unresolved risks remain that would block production deployment.

---

## 2. Scope

| Contract | Source File |
|----------|-------------|
| `RewardVault` | `contracts/src/RewardVault.sol` |
| `FeeDistributor` | `contracts/src/FeeDistributor.sol` |
| `ValidatorFeeVault` | `contracts/src/ValidatorFeeVault.sol` |
| `PrimeWaveStakingManager` | `contracts/src/PrimeWaveStakingManager.sol` |
| `PrimeWaveRewardCalculator` | `contracts/src/PrimeWaveRewardCalculator.sol` |
| `EmergencyMultisig` | `contracts/src/EmergencyMultisig.sol` |
| `PrimeWaveTimelock` | `contracts/src/PrimeWaveTimelock.sol` |
| `ValidatorRegistryAdapter` | `contracts/src/ValidatorRegistryAdapter.sol` |

---

## 3. Attack Vectors Tested

### 3.1 Reentrancy (Section 21–25)

**Test file:** `contracts/test/C10MaliciousParticipant.t.sol`

| Test | Vector | Result |
|------|--------|--------|
| MP-01 | `RewardVault.distribute()` reentrancy via malicious receiver | BLOCKED — `nonReentrant` guard |
| MP-02 | `ValidatorFeeVault.claimFees()` reentrancy via malicious receiver | BLOCKED — `nonReentrant` guard |
| MP-05 | Staking Manager `completeValidatorRemoval()` reentrancy via malicious reward receiver | BLOCKED — ETH sent after state finalized |

**Finding:** All ETH transfer paths are protected by either `nonReentrant` (OpenZeppelin) or checks-effects-interactions ordering. The RewardVault uses `nonReentrant` on both `distribute()` and `claim()`. The StakingManager transfers stake return to the staker after clearing all validator state.

### 3.2 Governance Attack (Section 17–20)

**Test file:** `contracts/test/C10GovernanceAttack.t.sol`

| Test | Vector | Result |
|------|--------|--------|
| GA-16 | Attacker bypasses timelock minimum delay | BLOCKED — `PWTL: delay not elapsed` |
| GA-17 | Replay already-executed timelock operation | BLOCKED — operation deleted after execute |
| GA-18 | Non-proposer tries to schedule via timelock | BLOCKED — proposer-only modifier |
| GA-21 | EMS pause blocks vault claims | CONFIRMED — `RV: paused` enforced |
| GA-26 | Timelock with zero-delay schedule | BLOCKED — `MIN_DELAY = 172_800 seconds` |

**Finding:** The `PrimeWaveTimelock` correctly enforces `MIN_DELAY = 48 hours` on all operations. The `EmergencyMultisig` can pause/unpause but cannot bypass timelock delays for administrative changes. No privilege escalation paths found.

### 3.3 Malicious Participant (Sections 21–26)

| Test | Vector | Result |
|------|--------|--------|
| MP-03 | Double-claim same validation ID | BLOCKED — `RV: nothing to claim` |
| MP-11 | Cross-validator claim (claim another's rewards) | BLOCKED — `RV: caller is not rewardAddress` |
| MP-12 | Unauthorized validator removal | BLOCKED — `SS: unauthorized` |
| MP-13 | Duplicate uptime proof submission | ACCEPTED (idempotent / best-wins) — intentional |
| MP-14 | Removal with exhausted vault | Clean zero-reward exit via `forceInitiateValidatorRemoval` |
| MP-15 | Force-send ETH to StakingManager | ETH stranded (no attack surface) |
| MP-16 | Forced ETH + direct storage overwrite | BLOCKED — no `receive()`/`fallback()` storage writes |

**Finding MP-13 (Info):** `submitUptimeProof` is idempotent — a second submission with higher uptime is accepted (best-wins semantics). This is intentional per Avalanche upstream behavior and does not create an attack surface.

---

## 4. Findings

### SEC-M-01: `forceInitiateValidatorRemoval` bypasses uptime eligibility check

**Severity:** Medium
**Contract:** `PrimeWaveStakingManager`
**Function:** `forceInitiateValidatorRemoval()`

**Description:** When the `RewardVault` is fully exhausted, `initiateValidatorRemoval()` reverts with `ValidatorIneligibleForRewards` because the calculator returns zero reward. The `forceInitiateValidatorRemoval()` variant bypasses this check. Any validator owner can call it after the vault is exhausted, enabling exit even if the Avalanche upstream would otherwise block it.

**Risk:** Low — the invariant that stake is always returnable is preserved. The only "bypass" is that a validator can exit when it would otherwise be locked indefinitely due to zero-reward eligibility.

**Recommendation:** Document `forceInitiateValidatorRemoval` as the intended liveness escape hatch when the reward vault is exhausted. Consider emitting a `ForcedExit` event to make this pattern visible in analytics.

### SEC-M-02: Timelock `execute()` is permissionless after delay

**Severity:** Medium
**Contract:** `PrimeWaveTimelock`

**Description:** After the minimum delay elapses, any EOA can call `execute()` on a scheduled operation — not only the original proposer. This is standard OpenZeppelin `TimelockController` behavior but represents a griefing vector if a malicious actor front-runs a governance cancellation by executing just before cancel arrives.

**Risk:** Low in practice — a proposer can cancel before the delay elapses. The race window only opens after `MIN_DELAY` passes.

**Recommendation:** Accept as designed (consistent with OZ TimelockController). Document the cancellation window in governance runbooks.

### SEC-L-01: EMS signers cannot be revoked post-deployment

**Severity:** Low
**Contract:** `EmergencyMultisig`

**Description:** The signer set is frozen at deployment. If a signer's key is compromised, there is no on-chain mechanism to revoke it without redeploying EMS and updating the `pauseController` reference on all contracts.

**Recommendation (C11):** Add a timelock-governed `updateSigner(old, new)` function protected by `onlyTimelock`.

### SEC-L-02: Dust accumulation in `FeeDistributor` due to integer division

**Severity:** Low
**Contract:** `FeeDistributor`

**Description:** The 70/20/10 split uses integer division. For inputs not divisible evenly, 1–2 wei per distribution are permanently stranded in `FeeDistributor`.

**Impact:** Negligible economic impact at production fee levels. No attack surface.

**Recommendation:** Accept as designed. Document in economic audit.

### SEC-L-03: `RewardVault.fund()` has no access control

**Severity:** Low
**Contract:** `RewardVault`

**Description:** Any address can fund the vault by calling `fund()`. While this cannot drain funds or bypass access controls, a griefing actor could front-run a rate-reduction schedule by adding a tiny fund to extend the vault's runway, diluting the governance action's urgency.

**Recommendation:** Accept as designed — permissionless funding is a feature (community members can contribute). The rate ratchet (`setEmissionRate` only reduces) prevents any economic harm from unexpected funding.

### SEC-I-01: `vm.prank` consumed by view call in argument position (test hygiene)

During C10 test development, several test failures arose from `vm.prank(X); contract.fn(vault.view())` patterns where the prank was consumed by the view call rather than `fn`. All tests were corrected by precomputing view results before the prank. No production contract issue.

### SEC-I-02: `block.timestamp` caching under `via_ir = true` (test hygiene)

The Solidity IR pipeline can cache `block.timestamp` at function entry when compiled with `--via-ir`. Test functions that called `vm.warp()` and then read `block.timestamp` again for subsequent warp targets observed the stale pre-warp value. All tests fixed by precomputing all absolute timestamps from `t0` at function entry.

### SEC-I-03: `totalEmitted` is lazy-updated (invariant documentation)

`RewardVault.totalEmitted()` only advances when a state-changing function triggers `_updateEmissionIndex()`. The view function `claimable()` correctly computes the live accrued amount without updating storage. Tests that read `totalEmitted` must trigger an update first (via `claim`, `setEmissionRate`, `registerRecipient`, or `setWeight`).

### SEC-I-04: `initiateValidatorRemoval` vs `forceInitiateValidatorRemoval` semantics

When reward is zero (exhausted vault), `initiateValidatorRemoval` reverts with `ValidatorIneligibleForRewards` per Avalanche upstream. Use `forceInitiateValidatorRemoval` for the liveness escape path. Both enforce 14-day unbonding and ownership checks.

---

## 5. Test Coverage Summary (C10 Security Tests)

| File | Tests | Pass |
|------|-------|------|
| `C10PhaseTransition.t.sol` | 25 | 25 |
| `C10ValidatorChurn.t.sol` | 12 | 12 |
| `C10RewardAccountingAttack.t.sol` | 21 | 21 |
| `C10TimestampUnbonding.t.sol` | 15 | 15 |
| `C10FeeIsolation.t.sol` | 12 | 12 |
| `C10GovernanceAttack.t.sol` | 28 | 28 |
| `C10MaliciousParticipant.t.sol` | 16 | 16 |
| `C10LongRun.t.sol` | 20 | 20 |
| `C10FuzzAttack.t.sol` | 10 | 10 |

**C10 security tests: 159/159 pass**
**Full regression (C00–C10): 676/676 pass**

---

## 6. Conclusion

The PrimeWave Chain Phase-2 PoS architecture survives all tested attack vectors. No critical or high severity vulnerabilities were found. Two medium findings are accepted-as-designed with documentation recommendations. The contracts are ready for external audit engagement (C11 prerequisite).
