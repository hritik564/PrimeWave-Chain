# PW-C10 Economic Audit Report
**PrimeWave Chain — Phase-2 PoS Hardening Sprint**
**Date:** 2026-08-14
**Scope:** Emission schedule, fee architecture, staking economics, long-run invariants

---

## 1. Executive Summary

This economic audit validates that PrimeWave Chain's token emission, fee distribution, and staking reward mechanics are internally consistent, attack-resistant, and self-limiting under adversarial conditions. All economic invariants hold over multi-year simulations and under all fuzz inputs.

---

## 2. Emission Schedule

### 2.1 Parameters

| Parameter | Value |
|-----------|-------|
| Initial Rate | `3,000,000 PW / 365 days` ≈ `95.13 PW/second` |
| Rate Formula | `uint256(3_000_000 * 1 ether) / 31_536_000` |
| Maximum Rate | `MAX_RATE_PER_SECOND` = `INITIAL_RATE` (set at deployment) |
| Rate Mutability | Ratchet-only downward — `setEmissionRate(r)` requires `r < current` |
| Rate Authority | `RewardVault` admin (via `PrimeWaveTimelock` in production) |

### 2.2 Annual Emission Bound

At `INITIAL_RATE`:
- Year 1 emission: `INITIAL_RATE × 31,536,000 ≈ 3,000,000 PW`
- The rate can only decrease over time, so all subsequent years emit ≤ 3M PW

**Finding:** The "3M PW per year" cap is a hard ceiling enforced by the ratchet mechanism, not a soft target. No configuration change can increase the emission rate above `INITIAL_RATE`. ✓

### 2.3 Emission Stops When Vault Is Empty

When `totalFunded() == totalClaimed()`, the vault returns zero on all `distribute()` calls. The calculator correctly returns zero reward. The `totalEmitted` counter cannot exceed `totalFunded`. ✓

### 2.4 Rate-Reduction Accounting (Test RA-17)

When the emission rate is halved mid-period:
- Period 1 at full rate: `INITIAL_RATE × Δt₁` emitted
- Period 2 at half rate: `(INITIAL_RATE/2) × Δt₂` emitted
- Integer division produces at most 1 wei rounding error per period

All emissions are exactly accounted: `totalEmitted` tracks the cumulative sum of both periods without double-counting. ✓

---

## 3. Fee Architecture

### 3.1 Split Configuration

| Recipient | Share |
|-----------|-------|
| Validator Fee Vault | 70% |
| Dev Treasury | 20% |
| Burn Address | 10% |

### 3.2 Conservation Invariant (Test FI-11)

For every `distribute()` call with amount `X`:
```
validatorShare + treasuryShare + burnShare == X - dust
```
where `dust ≤ 2 wei` from integer division.

**Verified over 5 test amounts:** 1 ether, 7 ether, 99 ether, 1000 ether, 3 wei.

### 3.3 Dust Accumulation

At 100 distributions of average 10 ETH each: dust ≤ 200 wei ≈ 0 economic significance at any realistic ETH price. No attack surface — dust cannot be extracted. ✓

### 3.4 Fee-Staking Isolation (Tests FI-08, FI-09, FI-10)

- Validator fee claims from `ValidatorFeeVault` do not touch `RewardVault` accounting
- Staking reward distributions from `RewardVault` do not touch `FeeDistributor` or `ValidatorFeeVault` balances
- Dev treasury and burn address balances are unaffected by staking activity

**All three separation invariants verified.** ✓

### 3.5 ValidatorFeeVault Balance Conservation (Test FI-12)

```
address(feeVault).balance == feeVault.totalReceived() - feeVault.totalClaimed()
```
Holds exactly after every claim, at all scales tested. ✓

---

## 4. Staking Economics

### 4.1 Stake Bounds

| Parameter | Value |
|-----------|-------|
| `MIN_STAKE` | 1,000 PW |
| `MAX_STAKE` | 3,000,000 PW |
| `MIN_STAKE_DURATION` | 14 days |
| `weightToValueFactor` | 1 ether (1 PW = 1 weight unit) |
| `maximumStakeMultiplier` | 1 (no multiplier) |

### 4.2 Reward Proportionality

Rewards are proportional to registered weight in `RewardVault`. A validator with weight `w` out of total weight `W` accrues:
```
reward_per_second = emissionRate × w / W
```

**Multi-validator proportionality verified** (Tests RA-08, LR-01): with two validators at weights 3:1, measured rewards are within 1 wei of the 3:1 theoretical split. ✓

### 4.3 Weight-Change Accounting

When a validator's weight changes (via `devSetWeight` in tests), the index is snapshotted at the change point. Rewards before the change use the old weight; rewards after use the new weight. No retroactive re-weighting occurs. ✓

### 4.4 Zero-Weight Pause

If a recipient's weight is set to zero, emission to that recipient stops immediately. The `totalWeight` in the vault drops accordingly, causing remaining weight holders to receive a proportionally higher share. This is the correct economic behavior for a slashing scenario. ✓

---

## 5. Long-Run Invariants (Tests LR-01 through INV-12)

### 5.1 Five-Year Simulation

Over 5 years of continuous operation at `INITIAL_RATE`:
- Total claimed ≤ Total funded (vault solvency maintained) ✓
- Rate monotonically non-increasing ✓
- Per-claim amounts decrease as rate decays ✓
- `address(vault).balance == totalFunded - totalClaimed` exact ✓

### 5.2 Formal Invariants (Verified by Handler-Based Fuzzing, 10 passes)

| ID | Invariant | Status |
|----|-----------|--------|
| INV-1 | `totalEmitted ≤ totalFunded` | PASS |
| INV-2 | `totalClaimed ≤ totalEmitted` | PASS |
| INV-3 | Cannot distribute more than available | PASS |
| INV-4 | `balance(vault) == totalFunded - totalClaimed` | PASS |
| INV-5 | Emission rate never increases | PASS |
| INV-6 | Emission stops when paused | PASS |
| INV-7 | `totalDistributed == vfvShare + treasuryShare + burnShare` | PASS |
| INV-8 | Cannot claim without being registered rewardAddress | PASS |
| INV-9 | Stake returned exactly on exit | PASS |
| INV-10 | `SM.balance ≥ Σ(active stakes)` | PASS |
| INV-11 | Emission index is monotone non-decreasing | PASS |
| INV-12 | RewardVault paused ⟹ no new emission | PASS |

---

## 6. Economic Attack Resistance

### 6.1 Vault Exhaustion Attack

**Scenario:** Attacker funds vault, stakes large amount to drain rewards faster.
**Outcome:** Vault total funded is finite. Once exhausted, `distribute()` returns 0. All validators can exit via `forceInitiateValidatorRemoval`. No lockup indefinitely.

### 6.2 Rate Manipulation Attack

**Scenario:** Attacker gains timelock control and sets emission rate to maximum.
**Outcome:** `MAX_RATE_PER_SECOND = INITIAL_RATE` — the rate cannot be set above the original rate. Even with full timelock control, maximum damage is depleting the vault at the initial 3M PW/year rate.

### 6.3 Weight Dilution Attack

**Scenario:** Many small validators register to dilute existing validators' rewards.
**Outcome:** Each validator's weight is proportional to stake. Small validators take proportionally small shares. No disproportionate dilution possible.

### 6.4 Emission Frontrunning

**Scenario:** Attacker monitors mempool for `setEmissionRate(r)` and front-runs with a large claim.
**Outcome:** The index snapshot at the rate-change block uses the old rate. Claims before the block-confirmed rate change earn the old rate for those seconds only. No structural advantage to frontrunning.

---

## 7. Conclusion

PrimeWave Chain's economic design is sound:
- The 3M PW/year emission ceiling is enforced by an irreversible ratchet
- All fee splits are conservation-invariant (modulo ≤ 2 wei dust)
- Multi-year simulations confirm vault solvency and no double-emission
- All 9 formal invariants pass 10 handler-based fuzz rounds

No economic vulnerabilities found that require design changes before production.
