# PrimeWave Chain — Tokenomics Specification
**Sprint PW-C00 | Status: DESIGN DOCUMENT — NOT FOR PRODUCTION**

---

## 1. Native Asset: PW

| Parameter | Value |
|---|---|
| Name | PrimeWave |
| Ticker | PW |
| Maximum Supply | 100,000,000 PW (LOCKED — cannot be changed) |
| Denomination | 18 decimals (standard EVM wei) |
| Mint Function | NONE — no arbitrary post-genesis minting |
| Burn | YES — 10% of gas fees burned |
| BEP-20 Relationship | None — PrimeWave Chain PW is independent of BNB Chain BEP-20 PW |

> ⚠️ **HARD RULE:** The `NativeMinter` precompile MUST NOT be activated. No PW can be created after genesis.

---

## 2. Token Distribution

Total: **100,000,000 PW**

| Allocation | Amount (PW) | % | Notes |
|---|---|---|---|
| PWSwap Liquidity | 40,000,000 | 40% | Initial PW/PWUSD liquidity pool, locked 36 months |
| PrimeWave Treasury | 15,000,000 | 15% | Multisig + timelock governance |
| Team & Development | 10,000,000 | 10% | Vesting terms TBD — see OQ-023 |
| Validator & Staking Rewards | 15,000,000 | 15% | Pre-funded RewardVault contract |
| Presale Phase 1 | 5,000,000 | 5% | $0.01/PW — no vesting (LOCKED decision) |
| Presale Phase 2 | 7,500,000 | 7.5% | $0.025/PW — no vesting (LOCKED decision) |
| Presale Phase 3 | 7,500,000 | 7.5% | $0.04/PW — no vesting (LOCKED decision) |
| **TOTAL** | **100,000,000** | **100%** | |

All allocations are seeded at genesis in the `alloc` block of the genesis file. No PW is minted after block 0.

### 2.1 Presale Parameters

| Phase | Allocation | Price | Raise (if sold out) |
|---|---|---|---|
| Phase 1 | 5,000,000 PW | $0.01 | $50,000 |
| Phase 2 | 7,500,000 PW | $0.025 | $187,500 |
| Phase 3 | 7,500,000 PW | $0.04 | $300,000 |

No vesting applies to presale allocations (OQ-015 — locked decision, previously approved by PrimeWave leadership). Presale buyers receive their PW allocation immediately at TGE with no lock-up.

> **Team allocation vesting** (10M PW) is a separate question — see OQ-023 in `PRIMEWAVE_OPEN_QUESTIONS.md`. This does not block Phase 1 launch.

---

## 3. Supply Invariant (Formal Definition)

The following invariant MUST hold at all times:

```
∀ block B:
  genesis_allocation(PW)
  + sum(rewards_paid_from_RewardVault)
  ≤ 100,000,000 PW × 10^18 wei
```

More precisely:
```
TOTAL_PW_SUPPLY = 100,000,000 PW (fixed at genesis, never increases)

At any point in time:
  circulating(PW)
  + locked_in_RewardVault(PW)
  + burned(PW)
  = 100,000,000 PW

Where:
  circulating  = all non-burned, non-vault PW
  locked       = 15,000,000 PW initial vault minus distributed rewards
  burned       = cumulative gas burns
```

### 3.1 Invariant Enforcement

The invariant is enforced by:

1. **Genesis:** All 100M PW allocated in genesis `alloc` block. No `NativeMinter` enabled.
2. **Protocol level:** `NativeMinter` precompile not activated → physically impossible to mint new PW.
3. **RewardVault contract:** Rewards can only be paid out from vault balance — the vault can never pay more than it holds.
4. **RewardVault test specification:**
   ```
   INVARIANT: RewardVault.totalDistributed() + RewardVault.balance() == 15_000_000e18
   INVARIANT: RewardVault.balance() >= 0
   INVARIANT: RewardVault.totalDistributed() <= 15_000_000e18
   ```
5. **Automated verification:** Foundry invariant tests (fuzz) must verify these conditions continuously. See `/testing/invariants/SupplyInvariant.t.sol`.

---

## 3B. Staking Reward Emission Rate (OQ-017 Resolved)

The 15M PW RewardVault distributes staking rewards at a maximum rate of **3,000,000 PW per year**.

| Parameter | Value |
|---|---|
| Maximum annual emission | 3,000,000 PW |
| Daily maximum | ≈ 8,219.18 PW/day |
| Vault minimum duration | 5 years (at sustained max emissions; extends if validators under-earn) |
| Unused emissions | Remain in vault — not burned, not redistributed |

**Phase 1 (15 validators, equal weight, fully eligible):**
- Max per-validator per year: 200,000 PW (3M ÷ 15)
- Max per-validator per day: ≈ 547.95 PW

Full specification and Solidity constants: `PRIMEWAVE_REWARD_ECONOMICS.md` Section 2.5.

---

## 4. Gas Economics

### 4.0 Important: Two Separate Mechanisms

Gas fee economics and staking rewards are **completely separate mechanisms** that must never be conflated:

| Mechanism | Source | Amount | Exhaustible? |
|---|---|---|---|
| **ValidatorFeeVault** | Ongoing gas/tx fees → 70% share | Unlimited (function of chain activity) | NO |
| **RewardVault** | Genesis pre-allocation | 15,000,000 PW (finite) | YES |

See `PRIMEWAVE_REWARD_ECONOMICS.md` for the full dual-mechanism specification with invariants.

### 4.1 70/20/10 Fee Model (LOCKED)

| Destination | Share | Mechanism |
|---|---|---|
| ValidatorFeeVault | 70% | Accumulates; distributed to validators by weight × uptime |
| PrimeWave Treasury | 20% | Auto-forwarded by FeeDistributor |
| Burn | 10% | Sent to 0x000...dead by FeeDistributor |

### 4.2 Implementation Architecture

Subnet-EVM's built-in `RewardManager` precompile supports three modes:
- `allowFeeRecipients: true` — validators collect their coinbase fees directly
- `rewardAddress` — all fees go to one address
- Burn — fees are burned

**None of these natively support a three-way percentage split.**

**Resolved implementation (OQ-004):**

```
RewardManager → rewardAddress: FeeDistributor contract address

FeeDistributor.distribute() (called periodically):
  totalFees = FeeDistributor.balance

  validatorShare = totalFees × 70 / 100  → ValidatorFeeVault contract
  treasuryShare  = totalFees × 20 / 100  → PrimeWaveTreasury multisig
  burnShare      = totalFees - validatorShare - treasuryShare  → 0x000...dead

ValidatorFeeVault distributes to validators:
  each validator's share ∝ validator_weight × uptime_eligibility_factor
  Phase 1: equal weight, equal uptime → approximately equal split (1/15 each)
  Phase 2: proportional to PoS stake weight
```

### 4.3 Gas Parameters (Preliminary — to be benchmarked on testnet)

| Parameter | Preliminary Value | Notes |
|---|---|---|
| Target block gas limit | 15,000,000 | Standard Subnet-EVM default, tune on testnet |
| Min base fee | 1 gwei (1,000,000,000 wei) | Tune on testnet |
| Target block rate | 2 seconds | ACP-224 compatible |
| Gas price | EIP-1559 dynamic | Standard Subnet-EVM |

> These values MUST be benchmarked and validated on testnet before mainnet genesis is finalized.

---

## 5. PWUSD — PrimeWave USD

PWUSD is a separate ERC-20 token on PrimeWave Chain. It is NOT the native gas asset.

| Parameter | Value |
|---|---|
| Name | PrimeWave USD |
| Ticker | PWUSD |
| Standard | ERC-20 on PrimeWave Chain |
| Max Supply | None (fixed max supply not set at launch) |
| Mint Authority | One designated Monetary Authority role (narrowly scoped) |
| Burn Authority | Monetary Authority (narrowly scoped) |

For full PWUSD architecture, see `PRIMEWAVE_PWUSD_ARCHITECTURE.md`.

---

## 6. PW Inflation: Formal Statement

**PrimeWave Chain has zero PW inflation.**

All PW that will ever exist is created at genesis. Staking rewards come from the pre-allocated 15,000,000 PW in the `RewardVault` contract. As rewards are paid:
- Total circulating PW increases (from vault to validator/delegator)
- Total PW in existence does not change
- Burns from gas fees permanently reduce total circulating PW

The supply curve over time:
```
t=0:       100,000,000 PW (genesis)
t=1..N:    100,000,000 PW minus cumulative burns (deflationary over time)
```

---

*This document is a PW-C00 design specification. No production deployment has occurred.*
