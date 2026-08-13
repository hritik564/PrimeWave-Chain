# PrimeWave Chain — PoS Transition Specification
**Sprint PW-C00 Decision Resolution | Status: DESIGN DOCUMENT — NOT FOR PRODUCTION**

---

## 1. Overview

PrimeWave Chain launches in Phase 1 with a Proof-of-Authority (PoA) validator set. This document specifies:
- Phase 1: PoA architecture and operation
- Phase 2: Custom PoS staking/delegation architecture (approved in principle)
- Transition process between phases

> **DO NOT IMPLEMENT THE CUSTOM STAKING MANAGER.** This is architecture documentation only.

---

## 2. Phase 1 — PoA Launch

### 2.1 Architecture

| Parameter | Value |
|---|---|
| Validator Manager | `PoAManager` (from `ava-labs/icm-services`) |
| Validator count | 15 |
| Staking | None — validators do not stake tokens |
| Delegation | Not available |
| Validator selection | PrimeWave admin + vetted independent operators |
| Validator weight | Equal (1/15 each) |
| Admin control | Multisig + timelock |

### 2.2 PoAManager Operation

`PoAManager` wraps `ValidatorManager` and restricts registration/removal to its owner (multisig). Key functions:

```solidity
// Only multisig owner can call these:
initiateValidatorRegistration(nodeID, blsPublicKey, remainingBalanceOwner, disableOwner, weight)
initiateValidatorRemoval(validationID)
initiateValidatorWeightUpdate(validationID, newWeight)

// Anyone can complete these (after P-Chain Warp confirmation):
completeValidatorRegistration(messageIndex)
completeValidatorRemoval(messageIndex)
```

### 2.3 Phase 1 Rewards

- Validators receive rewards from the 15M PW **RewardVault** (not minted)
- Rewards accrue using the reward-index model defined in `PRIMEWAVE_REWARD_ECONOMICS.md`
- Equal split among 15 validators (equal weight, equal uptime assumed)
- No delegation rewards in Phase 1

### 2.4 Phase 1 Fee Distribution

Transaction fees split 70/20/10 via `FeeDistributor`:
- 70% → `ValidatorFeeVault` → distributed equally among 15 validators
- 20% → PrimeWave Treasury
- 10% → Burned

---

## 3. Phase 2 — Custom PoS Architecture (Approved in Principle)

> **This Phase requires a separate sprint, a security audit, and explicit PrimeWave approval before implementation.**

### 3.1 Architecture Overview

```
Avalanche P-Chain
        │ Warp/ICM
        ▼
ValidatorManager (ACP-99, from icm-services)
        │ owner
        ▼
PrimeWaveStakingManager (custom — extends StakingManager)
        │
        ├── Validator accounting (stake, weight, registration)
        ├── Delegator accounting (delegation, commission)
        ├── Uptime/eligibility tracking
        └── Reward accounting
                 │
                 ├── RewardVault (15M PW finite reserve)
                 └── ValidatorFeeVault (ongoing gas fees)
```

### 3.2 Inheritance / Extension Point

`StakingManager` (abstract, from `ava-labs/icm-services`) provides the full PoS logic and exposes one key hook for reward delivery:

```solidity
// In StakingManager (abstract):
function _reward(address account, uint256 amount) internal virtual;

// In NativeTokenStakingManager (standard — CANNOT USE — mints tokens):
function _reward(address account, uint256 amount) internal override {
    NATIVE_MINTER.mintNativeCoin(account, amount);  // ← INFLATION — FORBIDDEN
}

// In PrimeWaveStakingManager (custom — PROPOSED):
function _reward(address account, uint256 amount) internal override {
    // Draw from pre-funded vault — NO MINTING
    rewardVault.distribute(account, amount);
}
```

`PrimeWaveStakingManager` MUST:
- Extend `StakingManager` exactly (no changes to validator registration, P-Chain Warp semantics)
- Override ONLY `_reward()` and `_lock()`/`_unlock()` (stake deposit/return)
- Use `RewardVault.distribute()` which enforces `require(balance >= amount)`

`PrimeWaveStakingManager` MUST NOT:
- Bypass `ValidatorManager` for P-Chain communication
- Call `NATIVE_MINTER.mintNativeCoin()` directly or indirectly
- Override validator registration/removal logic (use inherited implementation)
- Create arbitrary validator balances
- Add any hidden inflation mechanism

### 3.3 Validator Registration (Phase 2)

Any account with sufficient PW can become a validator:

```
User calls PrimeWaveStakingManager.initiateValidatorRegistration(
  nodeID, blsPublicKey, remainingBalanceOwner, disableOwner,
  delegationFeeBips, minStakeDuration, rewardRecipient
)
  msg.value = stake amount (must be >= minimumStakeAmount)
  stake is locked in the contract until unbonding completes
```

The contract then propagates the validator set change to P-Chain via Warp — identical to the standard `NativeTokenStakingManager` flow, except rewards draw from the vault.

### 3.4 Validator Parameters (Phase 2 Targets)

| Parameter | Target | Notes |
|---|---|---|
| Minimum stake | TBD | Testnet benchmark; consider economic barrier |
| Maximum stake | TBD | Testnet benchmark |
| Delegation fee (commission) | 5–10% | Set per-validator in basis points |
| Minimum stake duration | TBD | Testnet benchmark |
| Unbonding period | **14 days** (LOCKED August 13, 2026) | Applies to validators and delegators |
| Uptime threshold | ≥80% | Exact threshold: testnet benchmark |
| Maximum stake multiplier | TBD | Caps delegation relative to validator self-stake |
| Weight-to-value factor | TBD | Converts PW amount to P-Chain validator weight |

### 3.5 Delegation (Phase 2)

```
User calls PrimeWaveStakingManager.initiateDelegatorRegistration(
  validationID,
  rewardRecipient
)
  msg.value = delegation amount (must be >= minimumDelegationAmount)
```

Delegation adds weight to the validator. Delegator rewards:
```
delegatorReward = epochReward × (delegationWeight / totalValidatorWeight)
                  × (1 - validatorCommissionBips / 10_000)
```

### 3.6 Unbonding

- Validator initiates removal: calls `initiateValidatorRemoval(validationID)`
- Unbonding period begins: **14 days** (locked)
- Rewards continue accruing during unbonding
- After 14 days: stake returned, validator deregistered from P-Chain
- Delegators must also unbond (or redelegate) if their validator removes

Forced removal (slashing):
- Governance multisig initiates forced removal with evidence
- Slashed portion transferred to Treasury (NOT burned)
- No forced removal without documented evidence of protocol violation

### 3.7 Uptime and Reward Eligibility

- Uptime is tracked via the Subnet-EVM uptime blockchain proof mechanism
- Validators submit uptime proofs during validator removal flow
- Proofs are validated on-chain against the registered uptimeBlockchainID
- Below uptime threshold → reduced rewards for that period

### 3.8 Slashing (Phase 2)

| Violation | Penalty |
|---|---|
| Double signing (provable equivocation) | Partial stake slash → Treasury |
| Routine downtime | Reduced rewards (not slash) |
| Protocol abuse (documented) | Partial stake slash → Treasury |

Slashing process:
1. Evidence submitted by any party
2. Governance multisig reviews and approves slash
3. `PrimeWaveStakingManager.slash(validationID, slashBips, evidence)` called
4. Slashed PW transferred to Treasury (preserves supply invariant)
5. Remaining stake returned to validator on unbonding

> Slashed PW is NOT burned. Total supply is preserved. Slashed PW enters Treasury where it can be used per governance.

### 3.9 Reward Vault Behavior in Phase 2

- RewardVault continues operating as in Phase 1
- `PrimeWaveStakingManager._reward()` calls `RewardVault.distribute(account, amount)`
- Vault enforces: `require(balance >= amount, "RewardVault: insufficient balance")`
- When vault balance reaches 0: `_reward()` is a no-op; `RewardsExhausted` event emitted
- Validators continue earning from ValidatorFeeVault (gas fees) after vault is exhausted

---

## 4. Transition Trigger and Process

### 4.1 Trigger Conditions

Phase 2 deployment may proceed when ALL of the following are met:

- [ ] Phase 1 has been operating on mainnet for minimum 3 months
- [ ] `PrimeWaveStakingManager` contract has been written and audited
- [ ] Audit report is public with all critical/high findings resolved
- [ ] Testnet has validated Phase 2 staking for minimum 4 weeks
- [ ] All Phase 2 parameters (min stake, etc.) are finalized — unbonding: 14 days (already locked)
- [ ] Explicit PrimeWave leadership approval
- [ ] Community announcement made ≥7 days before activation

### 4.2 Transition Sequence

```
Step 1: Deploy PrimeWaveStakingManager (behind upgradeable proxy)
Step 2: Transfer ValidatorManager.owner() from PoAManager to PrimeWaveStakingManager
Step 3: Initialize PrimeWaveStakingManager with existing validator set
Step 4: Public staking opens — new validators can register
Step 5: PoAManager is deprecated (no new operations)
Step 6: Existing Phase 1 validators may re-register under PoS or exit
Step 7: Phase 2 is fully active
```

### 4.3 Rollback Considerations

If Phase 2 encounters a critical issue:
- Emergency multisig can pause `PrimeWaveStakingManager`
- ValidatorManager ownership can be transferred back to PoAManager via governance
- Existing staked positions are frozen (not lost) during a pause
- Full rollback requires 14-day unbonding period to complete for all stakers
- Governance vote required for any rollback that affects staker funds

---

## 5. Security Controls for Phase 2

| Control | Mechanism |
|---|---|
| No minting | `_reward()` draws from vault; NativeMinter not activated |
| Supply invariant | RewardVault enforces `require(balance >= amount)` |
| Validator set security | P-Chain Warp confirmation required for all changes |
| Admin key separation | PoAManager multisig ≠ Protocol Admin multisig |
| Upgrade protection | TimelockController + multisig required for upgrades |
| Emergency pause | Emergency multisig can pause without timelock |
| Slashing governance | Multisig approval required; no autonomous slash |

---

## 6. Dependency on Avalanche Interfaces

`PrimeWaveStakingManager` must be compatible with the `StakingManager` abstract contract from `ava-labs/icm-services`. Before implementation, the following must be confirmed:

- [x] ~~`StakingManager` exposes `_reward()` as `internal virtual`~~ → **Substantively confirmed** (OQ-019): `NativeTokenStakingManager` overrides `_reward()`, proving `internal virtual` in base. Final source review at commit `40e1c89` in PW-C01.
- [ ] `StakingManager._lock()` and `_unlock()` are overridable for native PW handling
- [ ] Warp message format for validator registration/removal has not changed between icm-contracts and icm-services
- [ ] No new interface requirements have been added in icm-services that affect the extension model

> **If any of the above cannot be confirmed, STOP and report before Phase 2 implementation begins.**

---

*This document is a PW-C00 Decision Resolution specification. No production deployment has occurred.*
