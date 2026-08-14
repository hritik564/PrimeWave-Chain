# PrimeWave Chain — Phase-2 PoS Staking Specification
**Sprint PW-C09 | August 14, 2026**

---

## 1. Overview

Phase-2 introduces Proof-of-Stake (PoS) validator staking to PrimeWave Chain, replacing the Phase-1 PoA model for new validators. Stake is locked as native PW, reward delivery comes from the pre-funded RewardVault, and all logic is built on Avalanche's audited `StakingManager` base contract from `ava-labs/icm-services@icm-relayer-v1.7.5`.

**Supply invariant is preserved: no minting occurs. Staking rewards come exclusively from the 15M PW pre-funded reserve.**

---

## 2. Contracts Delivered

| Contract | File | Purpose |
|---|---|---|
| `PrimeWaveStakingManager` | `contracts/src/PrimeWaveStakingManager.sol` | Main PoS staking entry point; extends StakingManager |
| `PrimeWaveRewardCalculator` | `contracts/src/PrimeWaveRewardCalculator.sol` | Implements IRewardCalculator; computes lump-sum reward at unbonding |
| `RewardVault` (modified) | `contracts/src/RewardVault.sol` | Adds `distribute()` + `setStakingManager()` for Phase-2 reward delivery |
| `MockAvalancheValidatorManager` | `contracts/test/MockAvalancheValidatorManager.sol` | Test mock implementing IValidatorManager without Warp round-trips |
| `MockWarpMessenger` | `contracts/test/MockWarpMessenger.sol` | Test mock etched at Warp precompile address for uptime proof simulation |

---

## 3. Architecture

```
Validator (EOA)
    │
    │  msg.value (PW stake)
    ▼
PrimeWaveStakingManager
    │  extends StakingManager (icm-services@v1.7.5)
    │  _lock()  → holds PW in contract
    │  _unlock() → sends PW back on removal
    │  _reward() → calls RewardVault.distribute()
    │
    ├─ IValidatorManager (ValidatorManager / MockAvalancheValidatorManager)
    │    Warp round-trips to P-Chain for registration / removal
    │
    └─ IRewardCalculator (PrimeWaveRewardCalculator)
         calculateReward(stakeAmount, validatorStartTime, stakingStart, stakingEnd, uptimeSeconds)
         │  = emissionRate × stakingDuration × (uptimeSeconds / validationDuration)
         │  capped at vault.totalFunded - vault.totalEmitted
         ▼
     RewardVault.distribute(rewardRecipient, amount)
         Sends PW from pre-funded reserve to validator reward recipient.
         Increments both totalEmitted and totalClaimed atomically.
```

---

## 4. Staking Lifecycle

```
PHASE 1 (PoA):
  PoAManager owns ValidatorManager
  PoA validators registered and managed by PoAManager

TRANSITION (one-time):
  PoAManager.transferValidatorManagerOwnership(address(stakingManager))
  → PrimeWaveStakingManager is now ValidatorManager.owner()

PHASE 2 (PoS) — validator lifecycle:
  1. Validator calls initiateValidatorRegistration{value: stakeAmount}(nodeID, blsKey, ...)
     → _lock(stakeAmount) holds PW in contract
     → ValidatorManager.initiateValidatorRegistration() sends Warp to P-Chain

  2. ICM relayer delivers P-Chain acknowledgment (minutes)
     → Anyone calls completeValidatorRegistration(messageIndex)
     → ValidatorManager activates validator on-chain

  3. Validator is active. Uptime tracked by P-Chain.
     → Validator may call submitUptimeProof(validationID, messageIndex) at any time
       to update on-chain uptimeSeconds from a Warp uptime proof

  4. After minimumStakeDuration (14 days), validator calls initiateValidatorRemoval(validationID, ...)
     → ValidatorManager sends weight-zero Warp to P-Chain
     → PrimeWaveRewardCalculator.calculateReward(...) computes lump-sum reward
       based on stakeAmount, staking duration, and uptimeSeconds

  5. ICM relayer delivers P-Chain acknowledgment (minutes)
     → Anyone calls completeValidatorRemoval(messageIndex)
     → _reward(rewardRecipient, calculatedReward) → RewardVault.distribute()
     → _unlock(validatorOwner, stakeAmount) → returns PW to validator
```

---

## 5. Reward Formula

```
grossReward = emissionRatePerSecond × stakingDuration × (uptimeSeconds / validationDuration)

Where:
  emissionRatePerSecond = vault.emissionRatePerSecond() [wei/second]
  stakingDuration       = stakingEndTime - stakingStartTime [seconds]
  uptimeSeconds         = seconds validator was live (from uptime proof)
  validationDuration    = stakingEndTime - validatorStartTime [seconds]

Final reward = min(grossReward, vault.totalFunded - vault.totalEmitted)
```

### 5.1 Uptime requirement

The C09 implementation has no hard uptime threshold (unlike Avalanche's `ExampleRewardCalculator` which uses 80%). If `uptimeSeconds == 0`, reward is 0 (no vault call). Any positive uptime earns a proportional reward. This can be changed by modifying `PrimeWaveRewardCalculator` in a future sprint.

### 5.2 Known limitation

Two validators staking simultaneously both earn the full `emissionRate × duration` (not proportionally split). The vault's `available` balance is the only shared constraint. A proportional global emission index would require staking-weight tracking not exposed by StakingManager. This is acceptable for Phase 2a (low validator count).

---

## 6. RewardVault Changes (C09 additions)

The `distribute()` function is the bridge between StakingManager's lump-sum reward model and RewardVault's continuous-emission accounting:

```solidity
function distribute(address to, uint256 amount) external nonReentrant whenNotPaused {
    require(msg.sender == stakingManager, "RV: not staking manager");
    if (amount == 0) return;
    require(to != address(0), "RV: zero recipient");
    uint256 available = totalFunded - totalEmitted;
    require(amount <= available, "RV: insufficient reserve");
    totalEmitted += amount;   // reduces capacity for future emissions
    totalClaimed += amount;   // maintains balance invariant
    (bool ok,) = to.call{value: amount}("");
    require(ok, "RV: transfer failed");
    emit StakingRewardDistributed(to, amount);
}
```

**Invariants preserved by `distribute()`:**
1. No minting (sends existing funded PW)
2. `totalEmitted <= totalFunded` — enforced by `amount <= available`
3. `totalClaimed <= totalEmitted` — both increment by same amount
4. Rate cap unchanged
5. `balance = totalFunded - totalClaimed` — ETH leaves, totalClaimed increases

---

## 7. Security Properties

| Property | Mechanism |
|---|---|
| No minting | `_reward()` calls `distribute()` which sends existing ETH, no mint path |
| Supply cap | `distribute()` checks `amount <= totalFunded - totalEmitted` |
| Stake custody | `_lock(value)` returns value unchanged; PW held in PrimeWaveStakingManager |
| Stake return | `_unlock(to, value)` sends PW via `.call{value}` to validator owner |
| Only owner can remove | StakingManager checks `_posValidatorInfo[id].owner == msg.sender` |
| Distribute caller gated | `require(msg.sender == stakingManager)` |
| Distribute one-time set | `require(stakingManager == address(0))` on setStakingManager() |
| Reentrancy safe | `nonReentrant` modifier on `distribute()` |
| Pause stops distribute | `whenNotPaused` modifier on `distribute()` (C07 integration) |
| 14-day unbonding | `minimumStakeDuration = 1,209,600` enforced by StakingManager |
| Delegation disabled | `maximumStakeMultiplier = 1` causes `MaxWeightExceeded` on any delegation |
| PoA validator safety | `_isPoSValidator()` guard: PoA validators get no PoS rewards |

---

## 8. Configuration

| Parameter | Value | Rationale |
|---|---|---|
| `minimumStakeDuration` | 1,209,600 s (14 days) | C00 spec: 14-day unbonding lock |
| `maximumStakeMultiplier` | 1 | Disables delegation for Phase 2a |
| `minimumDelegationFeeBips` | 100 (1%) | Informational only; delegation disabled |
| `minimumStakeAmount` | 1,000 PW | Prevents spam registrations |
| `maximumStakeAmount` | 3,000,000 PW | Full reserve; prevents monopoly stake |
| `weightToValueFactor` | 1e18 (1 PW = 1 weight unit) | Linear 1:1 mapping |
| `uptimeBlockchainID` | PrimeWave Chain blockchain ID | Non-zero required by StakingManager |

---

## 9. Library Dependency

| Dependency | Version | Path |
|---|---|---|
| `StakingManager` | `icm-relayer-v1.7.5` | `contracts/lib/icm-contracts/avalanche/validator-manager/` |
| `IWarpMessenger` | `icm-relayer-v1.7.5` | `contracts/lib/icm-contracts/avalanche/subnet-evm/` |
| `openzeppelin-contracts` | v5.1.0 | `contracts/lib/openzeppelin-contracts/` |
| `openzeppelin-contracts-upgradeable` | v5.1.0 | `contracts/lib/openzeppelin-contracts-upgradeable/` |

OZ v5.1.0 was used (instead of the project's pinned v5.6.1) to match the versioned import paths in StakingManager.sol. v5.1.0 and v5.6.1 are API-compatible for all classes used.

---

## 10. Test Coverage Summary

| File | Tests | Coverage |
|---|---|---|
| `StakingManagerUnit.t.sol` | Unit — distribute, calculator, lifecycle, security | Core paths |
| `StakingManagerFuzz.t.sol` | Fuzz — reward bounds, monotonicity, multi-distribution invariants | Statistical |
| `IntegrationC09.t.sol` | E2E — full lifecycle, two validators, pause, phase coexistence | System |

All 535 pre-C09 tests continue passing. New C09 tests add to the baseline.
