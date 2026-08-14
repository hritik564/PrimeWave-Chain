# PW-C04 — Final Report: Validator Fee Vault Accounting
**Status:** COMPLETE ✅  
**Sprint:** C04 — ValidatorFeeVault Accounting  
**Date:** 2026-08-14  
**Chain:** primewavedev | Chain ID: 73571  
**Blockchain ID:** `2F3BHmNJWP4DNaBbMFQog3TvfcF6GRY7PX99r7Xzae4cRwAv6a`

---

## What C04 Delivered

C04 replaced the C03 `ValidatorFeeVault` (a simple ETH receiver with `totalReceived`) with a full per-validator fee accounting contract implementing the **reward-index model** (O(1) accrual, O(1) claim, no loops on `receive()`).

### Core changes

| File | Status | Description |
|---|---|---|
| `contracts/src/ValidatorFeeVault.sol` | **REPLACED** | Full reward-index accounting, 15-validator registry, pull-claim |
| `contracts/test/ValidatorFeeVaultUnit.t.sol` | **NEW** | 60 unit tests across 5 scenarios + access control + events |
| `contracts/test/ValidatorFeeVaultInvariant.t.sol` | **NEW** | 8 invariant tests (stateful harness) + 6 fuzz tests |
| `contracts/script/DeployC04.s.sol` | **NEW** | Deploy vault+treasury+distributor, register 15 validators |
| `contracts/script/IntegrationC04.s.sol` | **NEW** | Live-chain integration test (18 on-chain assertions) |
| `contracts/test/FeeDistributorUnit.t.sol` | **UPDATED** | One event signature updated for new `FeeReceived` |
| `docs/PW-C04-VALIDATOR-FEE-ACCOUNTING-SPEC.md` | **NEW** | Full 16-section spec |
| `docs/PW-C04-TEST-REPORT.md` | **NEW** | Test results |

### Unchanged contracts

`FeeDistributor.sol` and `DevTreasury.sol` are unchanged from C03. All 39 C03 tests still pass.

---

## Architecture

```
Transaction fees (AvalancheGo AddBalance)
         │
         ▼
  FeeDistributor (address = genesis rewardAddress)
         │ distribute() — permissionless
         │
         ├─ 70% → ValidatorFeeVault.receive()
         │         │
         │         └─ accFeePerWeight += amount * 1e18 / totalEffectiveWeight
         │                              (O(1) global index update)
         │
         ├─ 20% → DevTreasury.receive()
         └─ 10% → 0xdEaD (burn)

Validators pull their share:
   claimFees(validationId) → sends pendingReward to rewardRecipient
```

---

## Accounting Model

**Reward index algorithm** (same as Synthetix/Compound):

```
accFeePerWeight += amount * PRECISION / totalEffectiveWeight   (on receive)

claimable(v) = (accFeePerWeight - rewardDebt[v]) * effectiveWeight(v) / PRECISION
               + pendingReward[v]

effectiveWeight(v) = baseWeight(v) × uptimeBips(v) / 10_000
```

**Rounding**: floor division at every step. Dust (< `totalEffectiveWeight` wei per distribution event) stays in vault balance forever and is never lost.

---

## Phase 1 Validator Configuration

| Parameter | Value |
|---|---|
| Count | 15 PoA validators |
| validationId | `keccak256("primewavedev-validator-N")` for N in [1,15] |
| rewardRecipient | `address(0x1000 + N)` |
| baseWeight | 1 |
| uptimeBips | 10,000 (100%) |
| totalEffectiveWeight | 15 |

---

## Test Results

| Suite | Tests | Result |
|---|---|---|
| ValidatorFeeVaultUnit | 60 | ✅ PASS |
| ValidatorFeeVaultInvariant (stateful, 128K calls) | 8 | ✅ PASS |
| ValidatorFeeVaultFuzz (6 × 256 runs) | 6 | ✅ PASS |
| FeeDistributorUnit (C03 regression) | 25 | ✅ PASS |
| FeeDistributorInvariant (C03 regression) | 14 | ✅ PASS |
| **Total** | **113** | ✅ **ALL PASS** |
| Integration (live chain, 18 assertions) | 18 | ✅ PASS |

---

## Integration Test Summary (Live Chain)

- ValidatorFeeVault deployed to `0xB7f8BC63BbcaD18155201308C8f3540b07f84F5e` on primewavedev
- 15 validators registered; `totalEffectiveWeight = 15`
- Round 1: 15 PW received → each validator earns exactly 1 PW (zero rounding dust for exact multiples of 15)
- `claimFees(vid1)` transferred exactly 1 PW to DEV0
- INV-1: `balance == totalReceived - totalClaimed` exact after claim (14 PW)
- Round 2: 7.5 PW received → vid1 earns 0.5 PW, others earn 1.5 PW each
- Total claimable after 2 rounds: 21.5 PW = expected (exact arithmetic)
- All 8 conservation invariants verified on-chain

---

## Invariants (all verified)

| # | Invariant |
|---|---|
| INV-1 | `balance == totalReceived - totalClaimed` (exact) |
| INV-2 | `balance >= sum(claimable) + unallocated` |
| INV-3 | `totalClaimed <= totalReceived` |
| INV-4 | `accFeePerWeight` monotonically non-decreasing |
| INV-5 | `totalEffectiveWeight` = Σ active effective weights |
| INV-6 | `unallocated <= totalReceived` |
| INV-7 | `Σ per-validator totalClaimed == vault.totalClaimed` |
| INV-8 | `roundingDust >= 0` (no over-allocation) |

---

## Out of Scope (C04)

- Staking, delegation, unbonding, slashing → C05+
- RewardVault (15M PW staking reserve) → C05+
- Production multisig / timelock → C05+
- Phase 2 PoS transition (Warp-based StakingManager) → Phase 2

---

## Phase 2 Migration Path

When Phase 2 PoS begins, `protocolAdmin` (currently DEV0) is replaced by `PrimeWaveStakingManager`, which reads Warp-verified uptime from the P-Chain and calls `setUptimeBips()` and `registerValidator()`. The accounting interface (`ValidatorFeeVault`) remains unchanged.

---

## C04 Acceptance Gate

✅ 60 unit tests pass  
✅ 8 invariants pass (128,000 stateful calls, 0 reverts)  
✅ 6 fuzz tests pass (256 runs each)  
✅ 39 C03 regression tests pass  
✅ Integration test passes (18 on-chain assertions, live primewavedev chain)  
✅ Spec document complete  
✅ Test report complete  

**PW-C04 COMPLETE — awaiting C05 approval before proceeding.**

---

*Sprint locked after acceptance gate passes.*
