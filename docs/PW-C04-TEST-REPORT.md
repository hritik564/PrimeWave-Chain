# PW-C04 — Test Report: Validator Fee Vault Accounting
**Status:** PASS — all tests green  
**Date:** 2026-08-14  
**Chain:** primewavedev | Chain ID: 73571  
**Blockchain ID:** `2F3BHmNJWP4DNaBbMFQog3TvfcF6GRY7PX99r7Xzae4cRwAv6a`

---

## Summary

| Suite | Tests | Result |
|---|---|---|
| ValidatorFeeVaultUnit | 60 | ✅ PASS |
| ValidatorFeeVaultInvariant (stateful harness) | 8 | ✅ PASS |
| ValidatorFeeVaultFuzz (standalone) | 6 | ✅ PASS |
| FeeDistributorUnit (C03 — regression) | 25 | ✅ PASS |
| FeeDistributorInvariant (C03 — regression) | 14 | ✅ PASS |
| **Total unit/fuzz/invariant** | **113** | ✅ **ALL PASS** |
| Integration test (live primewavedev chain) | 18 checks | ✅ PASS |

---

## 1. ValidatorFeeVaultUnit (60 tests)

### Scenarios

| Scenario | Tests | Result |
|---|---|---|
| A: 15 equal-weight, 100% eligibility, exact split | 4 | PASS |
| A: Non-divisible amounts (rounding/dust) | 2 | PASS |
| B: 1 ineligible (uptimeBips=0), 14 eligible | 2 | PASS |
| C: Fractional uptime factors | 2 | PASS |
| D: Validator deactivated after earning | 3 | PASS |
| E: Reactivated — no retro-accrual | 2 | PASS |
| Weighted distribution (V1=1, V2=2, V3=3) | 2 | PASS |
| Uptime-weighted (100%/50%/0%) | 1 | PASS |
| Zero-weight / no-validator (unallocated) | 4 | PASS |
| Access control (all 10 unauthorized paths) | 10 | PASS |
| Claim model (pull, only recipient, no double-claim) | 8 | PASS |
| setUptimeBips / setBaseWeight | 4 | PASS |
| 15-validator full flow | 1 | PASS |
| Conservation invariant across scenarios | 1 | PASS |
| View functions | 3 | PASS |
| Events (4 events verified) | 4 | PASS |
| Constructor | 3 | PASS |
| **Total** | **60** | **PASS** |

### Key assertions verified

- Scenario A (151 PW, 15 validators): dust ≤ 15 wei (rounding bounded by totalEffectiveWeight)
- Scenario A (1 wei): goes entirely to dust (delta = 0 because 1 < 15)
- Scenario B: ineligible validator (uptimeBips=0) earns 0 and cannot claim
- Scenario D: deactivated validator retains pre-deactivation pendingReward; does NOT earn while inactive
- Scenario E: reactivated validator starts at current accFeePerWeight (no retro-accrual)
- All 10 access control paths revert with correct error strings
- Double-claim reverts with "VFV: nothing to claim"
- Wrong-recipient claim reverts with "VFV: caller is not recipient"

---

## 2. ValidatorFeeVaultInvariant (8 invariants, 256 runs × 128,000 calls)

All 8 invariants held across 128,000 handler calls with 0 reverts.

| Invariant | Description | Result |
|---|---|---|
| INV-1 | `balance == totalReceived - totalClaimed` | PASS |
| INV-2 | `balance >= sum(claimable) + unallocated` | PASS |
| INV-3 | `totalClaimed <= totalReceived` | PASS |
| INV-4 | `accFeePerWeight` monotonically non-decreasing | PASS |
| INV-5 | `totalEffectiveWeight` = Σ active validator effective weights | PASS |
| INV-6 | `unallocated <= totalReceived` | PASS |
| INV-7 | `Σ per-validator totalClaimed == vault.totalClaimed` | PASS |
| INV-8 | `roundingDust >= 0` (no over-allocation from rounding) | PASS |

**Handler call breakdown (per invariant run):**

| Handler | Calls |
|---|---|
| activate | 16,064 |
| claim | 16,004 |
| deactivate | 15,897 |
| distributeUnallocated | 16,176 |
| registerNext | 16,034 |
| sendFees | 15,802 |
| setUptime | 16,146 |
| setWeight | 15,877 |

---

## 3. ValidatorFeeVaultFuzz (6 fuzz tests, 256 runs each)

| Test | Runs | Result |
|---|---|---|
| FUZZ-1: 15 validators, random fee amounts, conservation | 256 | PASS |
| FUZZ-2: 3 validators, partial claims, conservation | 256 | PASS |
| FUZZ-3: Random uptime changes, no overflow | 256 | PASS |
| FUZZ-4: 4 validators, multiple rounds, claim mask | 256 | PASS |
| FUZZ-5: Single validator, claimable == totalReceived | 256 | PASS |
| FUZZ-6: Register-then-deactivate, zero weight | 256 | PASS |

---

## 4. FeeDistributorUnit (C03 regression, 25 tests)

All 25 C03 tests pass with no modifications except `test_vaultEmitsEvent`, which was updated to reflect the new C04 `FeeReceived` event signature (replacing the old `ValidatorFeeReceived`). The new event correctly emits `(amount, accFeePerWeight, totalEffectiveWeight)` — verified in the test.

---

## 5. FeeDistributorInvariant (C03 regression, 14 tests)

All 14 C03 fuzz/invariant tests pass unchanged. The C04 ValidatorFeeVault has no interface that C03 invariant tests depend on beyond `receive()`.

---

## 6. Integration Test (live primewavedev chain)

Executed via `contracts/script/IntegrationC04.s.sol` on the running primewavedev L1.

**Note:** The live chain genesis has the C03 FeeDistributor address as `rewardAddress`. This is immutable without a genesis reset. The integration test therefore sends ETH directly from DEV0 to the C04 vault (simulating what `FeeDistributor.distribute()` does in production). This correctly exercises all C04 vault logic on a live EVM chain.

### Deployment

| Contract | Address (dynamic — chain nonce 11+) |
|---|---|
| ValidatorFeeVault (C04) | `0xB7f8BC63BbcaD18155201308C8f3540b07f84F5e` |

### On-chain assertions (18 checks)

| # | Check | Result |
|---|---|---|
| 1 | Contracts deployed; distributor pre-computation matches | PASS |
| 2 | validatorCount == 15 | PASS |
| 3 | totalEffectiveWeight == 15 | PASS |
| 4 | Sent 15 PW → vault.totalReceived == 15 PW | PASS |
| 5 | accFeePerWeight > 0 | PASS |
| 6 | unallocated == 0 | PASS |
| 7 | All 15 validators: claimable == 1 PW (exact) | PASS |
| 8 | claimFees(vid1) returned 1 PW | PASS |
| 9 | vault.totalClaimed == 1 PW | PASS |
| 10 | INV-1: balance == totalReceived - totalClaimed (14 PW == 15 - 1) | PASS |
| 11 | INV-2: sum(14 remaining) == 14 PW <= balance | PASS |
| 12 | Rounding dust == 0 wei | PASS |
| 13 | Round 2: 7.5 PW received → totalReceived == 22.5 PW | PASS |
| 14 | validator-1 (post-claim): claimable == 0.5 PW | PASS |
| 15 | validators 2-15: claimable == 1.5 PW each | PASS |
| 16 | INV-1 holds after round 2 | PASS |
| 17 | Total claimable 21.5 PW == expected (exact arithmetic) | PASS |
| 18 | Rounding dust == 0 wei after round 2 | PASS |

### Key metrics

| Metric | Value |
|---|---|
| Total PW sent to vault | 22.5 PW |
| Total PW claimed | 1 PW (validator-1) |
| Final vault balance | 21.5 PW |
| accFeePerWeight | 1.5e18 (after both rounds) |
| Rounding dust | 0 wei (exact amounts used) |
| Gas estimate | 214,604,350,004,292 gwei (includes all 15 registrations + 2 sends + 1 claim) |

---

## Toolchain

| Tool | Version |
|---|---|
| Foundry (forge/cast/anvil) | v1.7.1 (pinned, commit 4072e48705) |
| Solidity | 0.8.30 |
| AvalancheGo | v1.14.2 |
| subnet-evm | shipped with AvalancheGo v1.14.2 |

---

*Test report locked after C04 acceptance gate passes.*
