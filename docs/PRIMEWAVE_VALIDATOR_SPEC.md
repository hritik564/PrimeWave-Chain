# PrimeWave Chain — Validator Specification
**Sprint PW-C00 | Status: DESIGN DOCUMENT — NOT FOR PRODUCTION**

---

## 1. Critical Issue: Standard PoS vs. Fixed Supply

### 1.1 The Conflict

The standard Avalanche `NativeTokenStakingManager` (ACP-99 reference implementation) distributes staking rewards by calling:

```solidity
function _reward(address account, uint256 amount) internal virtual override {
    NATIVE_MINTER.mintNativeCoin(account, amount);
}
```

This **mints new PW tokens** for every reward payment. This is incompatible with the 100,000,000 PW fixed supply.

The `ERC20TokenStakingManager` similarly requires an `IERC20Mintable` token interface and calls `mint()` for rewards.

**Both standard PoS implementations require inflation.** Neither can be used directly.

### 1.2 What MUST NOT Be Done

- DO NOT enable the `NativeMinter` precompile
- DO NOT use `NativeTokenStakingManager` as-is
- DO NOT change the 100M supply cap
- DO NOT remove the 15M staking allocation
- DO NOT invent fake reward mechanisms

### 1.3 Viable Alternatives (Comparison)

| Option | Mechanism | Fixed Supply Compatible | Complexity | Decentralization |
|---|---|---|---|---|
| **A. PoA + RewardVault** | Admin-controlled validators; 15M PW locked in vault; rewards distributed from vault | ✅ YES | Low | Low (Phase 1) |
| **B. Custom PoS + RewardVault** ✅ SELECTED | Custom extension of StakingManager; overrides `_reward()` to draw from vault instead of minting | ✅ YES | High | High |
| **C. PoA Only (No Rewards)** | Permissioned validators; no staking rewards | ✅ YES | Very Low | Very Low |
| **D. Off-chain Distribution** | Rewards calculated off-chain, sent from vault manually | ✅ YES | Low | None (centralized) |

### 1.4 Recommended Architecture (Updated — OQ-006 Approved)

**Phase 1 (Launch): PoAManager + RewardVault**

- Deploy `PoAManager` from `ava-labs/icm-services` (standard ACP-99, no minting, admin-controlled)
- At genesis, 15,000,000 PW locked in `RewardVault` contract
- On-chain reward accrual/claim model (reward-index algorithm) — see `PRIMEWAVE_REWARD_ECONOMICS.md`
- Separate `ValidatorFeeVault` accumulates 70% of gas fees for distribution to validators

**Phase 2 (PoS Transition): Custom PrimeWaveStakingManager — APPROVED IN PRINCIPLE**

- Extends `StakingManager` from `ava-labs/icm-services`
- Overrides ONLY `_reward()`: calls `RewardVault.distribute(account, amount)` instead of `NATIVE_MINTER.mintNativeCoin()`
- Vault enforces `require(balance >= amount)` — physically impossible to overpay
- When vault exhausted: `_reward()` is no-op, `RewardsExhausted` event emitted; validators continue earning from `ValidatorFeeVault`
- Full PoS semantics (staking, delegation, unbonding, slashing) — zero inflation

**Full Phase 1 and Phase 2 specification:** `PRIMEWAVE_POS_TRANSITION_SPEC.md`
**Full reward economics:** `PRIMEWAVE_REWARD_ECONOMICS.md`

---

## 2. Phase 1 Validator Architecture

### 2.1 Initial Validator Set

- **Count:** 15 validators at mainnet launch
- **Type:** Permissioned (PoA) via `PoAManager` (from `ava-labs/icm-services`)
- **Operators:** PrimeWave + vetted independent operators

### 2.2 PoAManager Mechanics

The `PoAManager` contract (from `ava-labs/icm-services`, ACP-99 compliant, Solidity 0.8.30):
- A single admin (owner — multisig) controls validator additions and removals
- No staking deposit required from validators in PoA mode
- Validators are identified by NodeID + BLS public key
- Validator set changes are propagated to P-Chain via Warp messaging

**Deployment:** Behind a `TimelockController` + multisig so validator set changes have a minimum delay and multi-party approval.

### 2.3 Initial Validator Registration Process

1. Each of the 15 validator operators:
   a. Runs an AvalancheGo node with Subnet-EVM
   b. Generates a NodeID and BLS keypair (node-local, never shared)
   c. Provides NodeID + BLS public key to PrimeWave
2. PrimeWave admin calls `PoAManager.initiateValidatorRegistration(nodeID, blsPublicKey, ...)`
3. Contract emits a Warp message to P-Chain
4. Node picks up and confirms validator registration via Warp callback
5. Validator is active and begins participating in consensus

### 2.4 Validator Weight

In the PoA phase, validator weight (consensus influence) is configured by the admin. All 15 initial validators should have equal weight (1/15 each) unless a technical reason requires otherwise.

### 2.5 Phase 1 Staking Rewards (from RewardVault)

During Phase 1:
- No user staking or delegation (PoA only)
- The 15M PW `RewardVault` is active
- Validators receive rewards via periodic distribution from vault
- Distribution can be:
  - **On-chain:** Admin calls `RewardVault.distribute(validatorAddress, amount)` on a schedule
  - **Automated:** A trusted keeper/bot calls distribution based on uptime data
- Reward amounts are proportional to validated uptime

> **Governance question (to be resolved before PW-C01):** Who controls `RewardVault.distribute()` in Phase 1? Recommended: multisig with time-delayed disbursements.

---

## 3. Validator Parameters (Target — to be benchmarked)

| Parameter | Target Value | Notes |
|---|---|---|
| Minimum stake (Phase 2) | TBD | Must be set on testnet |
| Maximum stake (Phase 2) | TBD | Must be set on testnet |
| Delegation | YES (Phase 2) | Not available in Phase 1 PoA |
| Validator commission | 5–10% | Range — individual validators set their own |
| Unbonding period | 14–21 days | Exact value set on testnet |
| Uptime requirement | ≥80% (target) | Exact threshold TBD through testnet |
| Slashing | YES — provable violations only | Ordinary downtime: moderate penalty |

---

## 4. Phase 1 → Phase 2 Transition Plan

The transition from permissioned PoA to permissionless PoS requires:

1. **Governance approval** from PrimeWave leadership
2. **Custom PrimeWaveStakingManager** contract audited and deployed
3. **Upgrade path:** `PoAManager` → `PrimeWaveStakingManager`
   - New contract deployed
   - Current validators migrated (re-registered under new manager)
   - Admin role transferred to new manager's internal logic
4. **Public staking enabled:** Users can stake PW to become validators (above minimum stake)
5. **Delegation enabled:** PW holders can delegate to validators
6. **RewardVault** continues to fund rewards until exhausted or governance changes distribution rate

### 4.1 Churn Limitations

Avalanche imposes churn limits on validator set changes (maximum weight change per churn period) to maintain consensus stability. In Phase 2, the staking manager must enforce these limits.

---

## 5. Delegation (Phase 2 Target)

| Parameter | Target | Notes |
|---|---|---|
| Delegation supported | YES | Via PrimeWaveStakingManager |
| Minimum delegation | TBD | Testnet benchmarking |
| Delegation commission | 5–10% of delegator rewards to validator | Set per-validator |
| Unbonding | Same as validator (14–21 days) | |
| Reward eligibility | Must maintain validator uptime | |

---

## 6. Slashing

Slashing applies ONLY for:
- **Double signing** (provable equivocation)
- **Malicious behavior** (clearly documented protocol violations)

Slashing does NOT apply for:
- Routine downtime (moderate penalty, not slash)
- Network issues outside validator control

Slashing mechanics (Phase 2):
- Slashed stake is NOT burned (anti-inflation)
- Slashed stake is transferred to PrimeWave Treasury
- Slash requires multisig governance approval (no automatic slash without evidence)

---

## 7. Uptime and Reward Eligibility

- Validators must maintain ≥80% uptime (exact threshold to be set on testnet)
- Uptime is tracked on-chain via the uptime blockchain proof mechanism in Subnet-EVM
- Validators below threshold in a period receive reduced or zero rewards for that period
- Repeated underperformance triggers removal process (Phase 1: admin removal; Phase 2: protocol enforcement)

---

## 8. Validator Removal and Replacement

**Phase 1 (PoA):**
- Admin calls `PoAManager.initiateValidatorRemoval(validationID)`
- Warp message sent to P-Chain
- Validator is deregistered after P-Chain confirmation
- Replacement validator can be added independently

**Phase 2 (PoS):**
- Validator initiates removal via contract (after unbonding period)
- Forced removal by governance for slashable offenses
- Replacement is permissionless (new validator stakes above minimum)

---

*This document is a PW-C00 design specification. No production deployment has occurred.*
