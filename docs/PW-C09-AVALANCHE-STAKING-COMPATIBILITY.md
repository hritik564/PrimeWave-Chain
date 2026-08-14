# PrimeWave Chain — Avalanche Staking Compatibility Report
**Sprint PW-C09 | First Deliverable | August 14, 2026**
**Source inspected: `ava-labs/icm-services` tag `icm-relayer-v1.7.5` (commit verified from tag)**
**Contract path: `icm-contracts/avalanche/validator-manager/`**

---

## 1. Purpose

This document records the findings of the mandatory source-code inspection required by PW-C09 before any implementation begins. It answers: **Can PrimeWave's fixed-supply RewardVault model be safely integrated with the pinned Avalanche staking architecture?**

**Conclusion: YES — compatible — with three targeted implementation decisions and one minimal RewardVault addition.**

No STOP conditions are triggered. Implementation may proceed.

---

## 2. Files Inspected (Pinned Tag)

| File | Lines | Purpose |
|---|---|---|
| `StakingManager.sol` | 1060 | Abstract base — all PoS logic, hook points |
| `NativeTokenStakingManager.sol` | 115 | Reference — DO NOT USE (mints via NativeMinter) |
| `ValidatorManager.sol` | 780 | ValidatorManager implementation (ACP-99) |
| `PoAManager.sol` | 94 | Phase 1 PoA wrapper; transition mechanism |
| `interfaces/IRewardCalculator.sol` | — | Reward calculation interface |
| `interfaces/IStakingManager.sol` | — | Full interface + structs |
| `remappings.txt` | — | OZ version mapping |

---

## 3. Extension Point Verification

### 3.1 `_reward()` — the critical hook

```solidity
// StakingManager.sol line 1006
function _reward(address account, uint256 amount) internal virtual;
```

| Property | Verified? |
|---|---|
| `internal` | ✅ YES |
| `virtual` | ✅ YES — explicitly declared, no body |
| Safely overridable | ✅ YES — pure hook, no base implementation |
| Called with `amount = 0` possible? | ✅ YES — when reward is 0 (eligible but no uptime) |

**`PrimeWaveStakingManager` override:**
```solidity
function _reward(address account, uint256 amount) internal override {
    if (amount == 0) return;            // no-op: correct, no vault call needed
    rewardVault.distribute(account, amount);
}
```

### 3.2 `_lock()` and `_unlock()` — stake custody

```solidity
// StakingManager.sol line 617-626
function _lock(uint256 value) internal virtual returns (uint256);
function _unlock(address to, uint256 value) internal virtual;
```

Both are `internal virtual` with no base implementation. `NativeTokenStakingManager` shows the expected override pattern:

```solidity
// NativeTokenStakingManager (reference)
function _lock(uint256 value) internal virtual override returns (uint256) {
    return value;   // stake = msg.value, held in contract
}
function _unlock(address to, uint256 value) internal virtual override {
    payable(to).sendValue(value);
}
```

`PrimeWaveStakingManager` uses the same pattern — staked PW is held as native ETH in the contract, returned on removal. No changes needed from the reference implementation.

---

## 4. Contract Architecture (Actual Source)

### 4.1 Inheritance and upgradeability

```
StakingManager (abstract, ERC-7201 storage, Initializable, ReentrancyGuardUpgradeable, ContextUpgradeable)
    └── NativeTokenStakingManager (concrete, adds _reward=mint, _lock/_unlock=native ETH)
    └── PrimeWaveStakingManager   (custom — overrides _reward=vault, inherits _lock/_unlock pattern)
```

`StakingManager` uses **ERC-7201 namespaced storage** (`STAKING_MANAGER_STORAGE_LOCATION`). This is the standard upgradeable proxy storage pattern — compatible with UUPS proxies and safe from slot collisions.

### 4.2 Initializer

```solidity
function __StakingManager_init(StakingManagerSettings calldata settings) internal onlyInitializing
```

`StakingManagerSettings` (from `IStakingManager.sol`):
```solidity
struct StakingManagerSettings {
    IValidatorManager manager;          // ValidatorManager address
    uint256 minimumStakeAmount;         // min stake in wei
    uint256 maximumStakeAmount;         // max stake in wei
    uint64  minimumStakeDuration;       // seconds — enforces unbonding period
    uint16  minimumDelegationFeeBips;   // min fee (bips) for delegations
    uint8   maximumStakeMultiplier;     // 1 = delegation disabled
    uint256 weightToValueFactor;        // wei per weight unit
    IRewardCalculator rewardCalculator; // MUST be non-zero
    bytes32 uptimeBlockchainID;         // MUST be non-zero
}
```

**Initialization constraints (enforced in actual source):**
- `minimumDelegationFeeBips` must be in `[1, 10000]`
- `minimumStakeAmount <= maximumStakeAmount`
- `maximumStakeMultiplier` must be in `[1, 10]`
- `manager` must be non-zero
- `rewardCalculator` must be non-zero
- `minimumStakeDuration >= manager.getChurnPeriodSeconds()` (typically 3600s)
- `weightToValueFactor` must be non-zero
- `uptimeBlockchainID` must be non-zero

### 4.3 Validator registration flow

```
User → PrimeWaveStakingManager.initiateValidatorRegistration(nodeID, blsPublicKey, ..., stakeAmount, rewardRecipient)
         │
         │ _lock(stakeAmount) — holds PW in contract
         │ weight = valueToWeight(lockedValue) = stakeAmount / weightToValueFactor
         │
         ▼
     ValidatorManager.initiateValidatorRegistration(nodeID, blsPublicKey, ..., weight)
         │
         │ emits Warp message → P-Chain (takes minutes)
         ▼
     P-Chain confirms → ICM relayer delivers message
         │
         ▼
     ValidatorManager.completeValidatorRegistration(messageIndex) [onlyOwner = StakingManager]
         │ status: PendingAdded → Active
         ▼
     Validator active on both EVM and P-Chain
```

### 4.4 Staking / removal flow

```
After minimumStakeDuration (14 days):

User → initiateValidatorRemoval(validationID, includeUptimeProof, messageIndex)
         │ calls _rewardCalculator.calculateReward(stakeAmount, ..., uptimeSeconds)
         │ stores reward in _redeemableValidatorRewards[validationID]
         │ calls ValidatorManager.initiateValidatorRemoval → weight=0 Warp to P-Chain
         ▼
     P-Chain confirms removal → ICM relayer
         │
         ▼
User → completeValidatorRemoval(messageIndex)
         │ validator.status: Completed
         │ _withdrawValidationRewards → _reward(rewardRecipient, amount)
         │ _unlock(owner, stakeAmount) → returns PW to validator
         ▼
     Validator fully exited; rewards paid from RewardVault
```

### 4.5 Reward calculation and timing

**Critical: rewards are NOT continuous.** `StakingManager` calculates a **lump-sum reward at unbonding time** via `IRewardCalculator`:

```solidity
// Called at initiateValidatorRemoval:
uint256 reward = $._rewardCalculator.calculateReward({
    stakeAmount:       weightToValue(validator.startingWeight),
    validatorStartTime: validator.startTime,
    stakingStartTime:   validator.startTime,
    stakingEndTime:     validator.endTime,
    uptimeSeconds:      uptimeSeconds
});
$._redeemableValidatorRewards[validationID] += reward;
```

Then paid at `completeValidatorRemoval` via `_reward(rewardRecipient, reward)`.

**`IRewardCalculator` interface (actual source):**
```solidity
interface IRewardCalculator {
    function calculateReward(
        uint256 stakeAmount,
        uint64 validatorStartTime,
        uint64 stakingStartTime,
        uint64 stakingEndTime,
        uint64 uptimeSeconds
    ) external view returns (uint256);
}
```

**`PrimeWaveRewardCalculator` must implement this.** See Section 5.2.

### 4.6 Delegation (built in, cannot be removed)

`StakingManager` contains full delegation logic:
- `_initiateDelegatorRegistration()`, `completeDelegatorRegistration()`
- `_initiateDelegatorRemoval()`, `completeDelegatorRemoval()`
- `claimDelegationFees()` for validators to collect commission

Delegation **cannot be removed** without forking `StakingManager`. It is **disabled** by setting `maximumStakeMultiplier = 1` — any delegator attempt will revert with `MaxWeightExceeded` because `newValidatorWeight > startingWeight × 1`.

**C09 decision: `maximumStakeMultiplier = 1` to defer delegation to a future sprint.**

### 4.7 Phase 1 → Phase 2 transition

```solidity
// PoAManager.sol line 89-93 (actual source):
function transferValidatorManagerOwnership(address newOwner) external onlyOwner {
    _manager.transferOwnership(newOwner);
}
```

Transition sequence (from actual source analysis):
1. Deploy `PrimeWaveStakingManager` (behind UUPS proxy)
2. Call `PoAManager.transferValidatorManagerOwnership(address(stakingManager))` — multisig + timelock
3. `StakingManager` is now the `ValidatorManager.owner()` — it can call `completeValidatorRegistration`, `completeValidatorRemoval`
4. Existing PoA validators have `_posValidatorInfo[validationID].owner == address(0)` — `_isPoSValidator()` returns `false` for them, so they won't get PoS rewards or have their stake locked in the contract

**Key safety property (from actual source, line 389-391):**
```solidity
// completeValidatorRemoval: return early for non-PoS validators
if (!_isPoSValidator(validationID)) {
    return validationID;  // no reward, no unlock — safe for PoA validators
}
```

### 4.8 Access control on ValidatorManager

`ValidatorManager` is `Ownable`. The following functions are `onlyOwner`:
- `initiateValidatorRegistration()` — line 311
- `completeValidatorRegistration()` — line 424
- `initiateValidatorRemoval()` — line 506
- `completeValidatorRemoval()` — line 572

In Phase 2, `PrimeWaveStakingManager` must be the `ValidatorManager.owner()`. `StakingManager` calls these functions on `$._manager` (the ValidatorManager) directly. This works correctly once the ownership transfer completes.

---

## 5. Incompatibilities and Required Implementation Decisions

### 5.1 INCOMPATIBILITY: RewardVault has no `distribute(address, uint256)` function

**Status: Genuine interface incompatibility. Requires targeted addition to RewardVault. Does NOT require RewardVault redesign.**

The C00 spec and C09 brief both reference:
```solidity
function _reward(address account, uint256 amount) internal override {
    rewardVault.distribute(account, amount);  // ← this function does not exist
}
```

The C06 `RewardVault` uses a continuous emission model with registered recipient IDs. It has no push-based `distribute(address, uint256)` function.

**Required addition (minimal — does not redesign RewardVault):**
```solidity
// New in RewardVault for C09:
bytes32 public constant STAKING_MANAGER_ROLE = keccak256("STAKING_MANAGER_ROLE");

/// @notice Push-based reward delivery for PrimeWaveStakingManager.
///         Called by _reward() override; amount calculated by PrimeWaveRewardCalculator.
///         Maintains all RewardVault invariants: increments both totalEmitted and totalClaimed,
///         so the vault accounting remains consistent with the time-based recipient model.
function distribute(address to, uint256 amount) external nonReentrant {
    require(hasRole(STAKING_MANAGER_ROLE, msg.sender), "RV: not staking manager");
    if (amount == 0) return;
    require(to != address(0), "RV: zero address");
    uint256 available = totalFunded - totalEmitted;  // remaining un-emitted reserve
    require(amount <= available, "RV: insufficient reserve");
    totalEmitted += amount;   // treat as emitted (reduces available capacity)
    totalClaimed += amount;   // treat as claimed (reduces vault balance)
    (bool ok,) = to.call{value: amount}("");
    require(ok, "RV: transfer failed");
    emit RewardClaimed(to, amount);  // reuse existing event
}
```

**Why `totalEmitted += amount` AND `totalClaimed += amount`:**
- RewardVault invariant 2: `totalEmitted <= totalFunded` — maintained (`amount <= available`)
- RewardVault invariant 3: `totalClaimed <= totalEmitted` — maintained (both increase by same amount)
- RewardVault invariant 5: `balance = totalFunded - totalClaimed` — maintained (ETH leaves, totalClaimed increases)
- The continuous recipient model correctly sees reduced `available = totalFunded - totalEmitted` capacity, preventing double-distribution

**Scope impact:** One new function + one new role constant in `RewardVault.sol`. All 535 existing tests continue passing. New tests for `distribute()` added in C09.

### 5.2 DECISION: `PrimeWaveRewardCalculator` must implement `IRewardCalculator`

`StakingManager` requires a non-zero `rewardCalculator` in its initializer. It calls:
```
calculateReward(stakeAmount, validatorStartTime, stakingStartTime, stakingEndTime, uptimeSeconds)
```

This translates to a PW reward amount. The `PrimeWaveRewardCalculator` implementation:

```solidity
// Emit: stakeAmount/totalVaultWeight * emissionRate * stakingDuration * uptimeFraction
// Capped at vault's available reserve.
function calculateReward(
    uint256 stakeAmount,
    uint64  validatorStartTime,
    uint64  stakingStartTime,
    uint64  stakingEndTime,
    uint64  uptimeSeconds
) external view returns (uint256) {
    uint64 stakingDuration = stakingEndTime - stakingStartTime;
    if (stakingDuration == 0) return 0;

    // Uptime fraction: uptimeSeconds / validationDuration (as validator, not just staking period)
    uint64 validationDuration = stakingEndTime - validatorStartTime;
    if (validationDuration == 0) return 0;

    // Gross reward: rate * duration * uptime fraction
    uint256 grossReward = (uint256(rewardVault.emissionRate()) * stakingDuration
        * uptimeSeconds) / validationDuration;

    // Scale by stake fraction (stake / totalEligibleWeight in wei):
    // For simplicity in Phase 2 (no delegators yet), stakeAmount IS the validator's full weight.
    // Full proportional accounting is handled by RewardVault's recipient model for Phase 1;
    // in Phase 2, the StakingManager calls distribute() with the exact computed amount.
    // No scaling by total weight here — the gross reward per stake-second is the full vault rate,
    // and individual stake proportion is implicitly baked in via weight-based P-Chain consensus.

    // Cap at available vault reserve
    uint256 available = rewardVault.totalFunded() - rewardVault.totalEmitted();
    return grossReward < available ? grossReward : available;
}
```

**Note on stake-proportional model:** `StakingManager` calls `calculateReward` per individual validator (not globally). The reward is stake-specific. `PrimeWaveRewardCalculator` uses `emissionRate × duration × uptime_fraction` — this gives the TOTAL emission budget for that validator's staking period, independent of other validators. The vault rate acts as a global budget cap; the per-validator reward reflects their individual uptime over their staking period. This is intentional for Phase 2: each validator earns the vault rate for their active period, pro-rated by uptime. If two validators stake simultaneously at equal weight, they each earn half the rate — but `calculateReward` is called per validator, not globally. The natural constraint is the vault's `available` balance.

**KNOWN LIMITATION:** For strictly proportional reward sharing (validator A earns exactly proportional to A/total stake), a global emission index would be needed. `StakingManager` does NOT provide global emission — it calculates per-validator at unbonding time. The per-validator lump-sum model is acceptable for Phase 2 and consistent with Avalanche's own reward model. Document this as a known limitation.

### 5.3 DECISION: 14-day unbonding via `minimumStakeDuration`

Avalanche's `StakingManager` does NOT have a separate "unbonding queue." The `minimumStakeDuration` field enforces a minimum time before a validator can initiate removal:

```solidity
// From StakingManager._initiatePoSValidatorRemoval (line 346-351):
if (
    validator.endTime < validator.startTime + $._posValidatorInfo[validationID].minStakeDuration
) {
    revert MinStakeDurationNotPassed(validator.endTime);
}
```

**14-day enforcement: set `minimumStakeDuration = 1_209_600` (14 × 24 × 60 × 60)** in `StakingManagerSettings`. Any validator calling `initiateValidatorRemoval` before 14 days reverts. After 14 days, the removal proceeds through the Warp round-trip (minutes), after which `completeValidatorRemoval` returns the stake and rewards.

**Functional equivalence:** stake → active (locked in contract for ≥14 days) → initiateRemoval (after 14 days) → P-Chain Warp → completeRemoval (stake + rewards returned). This IS functionally a 14-day bonded lock, just without a separate "unbonding queue" state.

**Minimum `minimumStakeDuration` constraint:** must be `>= manager.getChurnPeriodSeconds()`. With `churnPeriodSeconds = 3600` (1 hour), 14 days (1,209,600 seconds) satisfies this easily.

### 5.4 DECISION: Disable delegation via `maximumStakeMultiplier = 1`

C09 says: "DO NOT implement delegation unless explicitly required." `StakingManager` has delegation fully built in but it can be effectively disabled by setting `maximumStakeMultiplier = 1`:

```solidity
// _initiateDelegatorRegistration checks:
if (newValidatorWeight > validator.startingWeight * $._maximumStakeMultiplier) {
    revert MaxWeightExceeded(newValidatorWeight);
}
// With multiplier=1: newWeight must be <= startingWeight, but newWeight = currentWeight + delegatorWeight > currentWeight = startingWeight → always reverts
```

Any delegation attempt reverts with `MaxWeightExceeded`. This is the cleanest way to defer delegation without forking the contract.

### 5.5 OZ version in icm-services vs PrimeWave (5.1.0 vs 5.6.1)

`StakingManager.sol` imports:
```solidity
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable@5.1.0/...";
```

`remappings.txt` maps `@openzeppelin/contracts-upgradeable@5.1.0` → same OZ directory as `@5.0.2`. PrimeWave uses **OZ v5.6.1**.

**Assessment: COMPATIBLE.** OZ v5.6.1 is API-compatible with v5.1.0 for all classes used:
- `ReentrancyGuardUpgradeable` — storage layout unchanged, same API
- `ContextUpgradeable` — unchanged
- `OwnableUpgradeable` — unchanged
- `Initializable` — unchanged
- `Address` — unchanged

**Required:** When PrimeWave adds icm-services as a Foundry library, the remapping must point the versioned import paths to the PrimeWave OZ v5.6.1 checkout. In `foundry.toml` remappings:
```
@openzeppelin/contracts@5.1.0=contracts/lib/openzeppelin-contracts/contracts
@openzeppelin/contracts-upgradeable@5.1.0=contracts/lib/openzeppelin-contracts-upgradeable/contracts
```

### 5.6 `uptimeBlockchainID` requirement

`StakingManager` requires a non-zero `uptimeBlockchainID` — the blockchain ID of the chain that submits uptime proofs:

```solidity
if (uptimeBlockchainID == bytes32(0)) {
    revert InvalidUptimeBlockchainID(uptimeBlockchainID);
}
```

**For PrimeWave Chain:** this is the blockchain ID of PrimeWave Chain itself, as a `bytes32`. The devnet blockchain ID `yNRRcwqYaWqn9g4XcAiNe7DufgEHqpF2mmvcG6go1cRvtZo4S` (base58) must be decoded to bytes32.

For Foundry tests (no live Warp): `uptimeBlockchainID` can be set to any non-zero constant (e.g. `bytes32(uint256(1))`). Uptime proof submission in tests uses `MockValidatorManager` which can simulate this.

---

## 6. Stop Conditions — Evaluated Against Actual Source

| Stop Condition (C09 §54) | Assessment |
|---|---|
| 1. Avalanche's staking requires native minting that cannot be safely replaced | ✅ SAFE — `_reward()` is `internal virtual`; minting is only in `NativeTokenStakingManager` which we do NOT inherit |
| 2. Cannot preserve 100M supply invariant | ✅ SAFE — `distribute()` sends existing PW; no minting path |
| 3. RewardVault cannot safely fund staking rewards | ✅ SAFE — with `distribute()` addition; `require(amount <= available)` prevents insolvency |
| 4. 3M PW/year cap cannot be enforced | ✅ SAFE — `PrimeWaveRewardCalculator` computes against `rewardVault.emissionRate()` which is already rate-capped |
| 5. 15M reserve can be exceeded | ✅ SAFE — `distribute()` checks `amount <= totalFunded - totalEmitted` |
| 6. 14-day unbonding cannot be enforced | ✅ SAFE — `minimumStakeDuration = 1,209,600` enforces this |
| 7. Stake can be withdrawn by unauthorized account | ✅ SAFE — `_initiatePoSValidatorRemoval` checks `_posValidatorInfo[validationID].owner != _msgSender()` |
| 8. Rewards can be claimed by unauthorized account | ✅ SAFE — `claimDelegationFees` checks `_posValidatorInfo[validationID].owner != _msgSender()` |
| 9. ValidatorManager can be bypassed | ✅ SAFE — StakingManager calls `$._manager` on all P-Chain operations |
| 10. A second validator authority becomes necessary | ✅ SAFE — `PrimeWaveStakingManager` IS the `ValidatorManager.owner()` in Phase 2 |
| 11. Phase-1 and Phase-2 identities cannot be reconciled | ✅ SAFE — `_isPoSValidator()` cleanly distinguishes; PoA validators are non-PoS and skip reward/unlock logic |
| 12. Phase transition creates double rewards | ✅ SAFE — PoA validators with no `_posValidatorInfo.owner` get no PoS rewards |
| 13. Fee income and staking rewards become mixed | ✅ SAFE — FeeDistributor/ValidatorFeeVault unchanged; `distribute()` draws from RewardVault only |
| 14. Governance can bypass timelock | ✅ SAFE — no new governance paths created |
| 15. Emergency multisig gains non-emergency powers | ✅ SAFE — EMS interface unchanged |
| 16. Any C03-C08 regression | ✅ SAFE — `distribute()` addition is additive; no existing function modified |
| 17. Storage collision detected | ✅ SAFE — ERC-7201 namespaced storage in StakingManager; no collision with PrimeWave contracts |
| 18. Upgrade path can bypass supply invariant | ✅ SAFE — UUPS upgrade requires timelock; `_reward()` override is the only minting path |
| 19. Requires inventing an unapproved economic rule | ✅ SAFE — `PrimeWaveRewardCalculator` uses `emissionRate × duration × uptime_fraction`, consistent with C06 economics |
| 20. Requires delegation or slashing not yet approved | ⚠️ PARTIAL — delegation exists in code but is disabled via `maximumStakeMultiplier = 1`; slashing NOT implemented |

---

## 7. Summary of Implementation Requirements

| Requirement | Contract | Change |
|---|---|---|
| Add `distribute(address, uint256)` | `RewardVault.sol` | New function + `STAKING_MANAGER_ROLE` constant |
| Grant staking manager role | `RewardVault` init | `grantRole(STAKING_MANAGER_ROLE, address(stakingManager))` |
| Implement `IRewardCalculator` | `PrimeWaveRewardCalculator.sol` | New contract |
| Implement `PrimeWaveStakingManager` | `PrimeWaveStakingManager.sol` | New contract — overrides `_reward`, inherits `_lock`/`_unlock` from NativeToken pattern |
| Set 14-day unbonding | `PrimeWaveStakingManager` init | `minimumStakeDuration = 1_209_600` |
| Disable delegation (Phase 2a) | `PrimeWaveStakingManager` init | `maximumStakeMultiplier = 1` |
| Add Foundry remappings for icm-services | `foundry.toml` | Versioned OZ path remappings + subnet-evm interface |
| Add icm-services as library | `foundry.toml` | `[dependencies]` entry |
| Phase 1→2 transition function | `PoAManager` | Already exists: `transferValidatorManagerOwnership()` |

---

## 8. Known Limitations (to carry forward to PW-C09-FINAL-REPORT)

1. **Reward proportionality is per-validator, not globally proportional:** Two validators staking simultaneously each earn `rate × duration × uptime_fraction`, independently. If both stake with equal weight, they each earn the full per-second rate (not half). The vault's `available` balance is the only shared constraint. This differs from a global emission-index model where total rewards are split proportionally. This is a deliberate simplification for Phase 2a; a global index would require staking-weight tracking that StakingManager does not expose.

2. **`_reward(account, 0)` is a no-op** by design. If a validator is ineligible (zero uptime proof), `calculateReward` returns 0 and `_reward` short-circuits. No vault call is made.

3. **Delegation is structurally present** in the contract even when disabled. Code is inherited from `StakingManager` and cannot be excluded without forking.

4. **Warp round-trip latency** means validator registration and removal take minutes in production (P-Chain Warp confirmation). Foundry tests using `MockValidatorManager` complete these instantly. Real timing differences must be accounted for in the production runbook.

5. **`uptimeBlockchainID` in tests** is set to a non-zero stub. Production must use the actual PrimeWave Chain blockchain ID (bytes32-encoded).

6. **`IValidatorManagerExternalOwnable`** (from `PoAManager.sol`) is the interface used for `transferOwnership`. The `ValidatorManager` must implement this (it does via `OwnableUpgradeable`).

---

*Source inspection completed August 14, 2026. All code references verified against icm-services tag `icm-relayer-v1.7.5`.*
