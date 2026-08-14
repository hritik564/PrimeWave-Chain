# PW-C04 — Validator Fee Accounting Specification
**Status:** COMPLETE  
**Sprint:** C04 — ValidatorFeeVault Accounting  
**Depends on:** PW-C03 (FeeDistributor, chain live), PW-C00 (locked architecture)  
**Date:** 2026-08-14

---

## 1. Purpose

C04 introduces per-validator fee accounting to the ValidatorFeeVault. The C03 vault received the 70% validator share from FeeDistributor but had no per-validator ledger. C04 replaces that contract with one that implements the **reward-index model**, enabling O(1) fee accrual and O(1) per-validator claims, with no loops on receive.

This sprint does **not** implement staking, delegation, unbonding, slashing, or the RewardVault (15M PW staking reserve). Those belong to C05+ and Phase 2.

---

## 2. Accounting Model — Reward Index

PrimeWave adopts the same algorithm used by Synthetix and Compound's reward distribution:

### 2.1 Global Index

```
accFeePerWeight (scaled by PRECISION = 1e18)
```

When `amount` PW arrives at the vault:

```
if totalEffectiveWeight == 0:
    unallocated += amount
else:
    accFeePerWeight += amount * PRECISION / totalEffectiveWeight
```

### 2.2 Per-Validator Claimable

```
earned(v) = (accFeePerWeight - rewardDebt[v]) * effectiveWeight(v) / PRECISION
claimable(v) = pendingReward[v] + earned(v)
```

### 2.3 Checkpoint Pattern

Any operation that changes a validator's effective weight must checkpoint first:

```
pendingReward[v] += earned(v)
rewardDebt[v] = accFeePerWeight
```

Operations that checkpoint: `deactivateValidator`, `activateValidator`, `setUptimeBips`, `setBaseWeight`.

### 2.4 Complexity

| Operation | Gas complexity |
|---|---|
| `receive()` | O(1) |
| `claimFees()` | O(1) |
| `setUptimeBips()` | O(1) |
| `registerValidator()` | O(1) |
| `totalClaimableView()` | O(n) — off-chain / tests only |

---

## 3. Effective Weight

```
effectiveWeight(v) = baseWeight(v) × uptimeBips(v) / 10_000
```

- **baseWeight**: raw economic/consensus weight. All 15 Phase 1 PoA validators use `baseWeight = 1`.
- **uptimeBips**: eligibility factor in basis points [0, 10_000].
  - `10_000` = 100% eligible (full share)
  - `0` = fully ineligible (earns nothing)
  - Phase 1 default: `10_000` for all validators
- **Integer division floors**: sub-unit dust stays in vault (balance ≥ sum-of-claimable always).

---

## 4. Validator Registry

### 4.1 Phase 1 Configuration

| Field | Value |
|---|---|
| Count | 15 PoA validators |
| validationId | `keccak256("primewavedev-validator-N")` for N ∈ [1,15] |
| rewardRecipient | `address(0x1000 + N)` |
| baseWeight | 1 |
| uptimeBips | 10_000 (100%) |

### 4.2 ValidatorInfo struct

```solidity
struct ValidatorInfo {
    address rewardRecipient;  // EVM address receiving claimed PW
    uint128 baseWeight;       // consensus/economic weight
    uint16  uptimeBips;       // eligibility factor [0, 10_000]
    bool    active;           // whether currently accruing
    uint256 rewardDebt;       // accFeePerWeight snapshot at last checkpoint
    uint256 pendingReward;    // checkpointed but unclaimed PW (wei)
    uint256 totalClaimed;     // lifetime claimed PW (wei)
}
```

---

## 5. Access Control

| Role | Address (Phase 1) | Upgrade path |
|---|---|---|
| protocolAdmin | DEV0 EOA (0xf39F…2266) | Phase 2: multisig + 48h timelock |

**Admin operations:**
- `registerValidator(validationId, recipient, baseWeight, uptimeBips)`
- `deactivateValidator(validationId)`
- `activateValidator(validationId)`
- `setUptimeBips(validationId, newBips)`
- `setBaseWeight(validationId, newWeight)`

**Permissionless operations:**
- `distributeUnallocated()` — anyone, requires `totalEffectiveWeight > 0`
- `claimFees(validationId)` — restricted to `rewardRecipient` of that validator

**No admin withdrawal** — the contract has no function to withdraw arbitrary funds.

---

## 6. Lifecycle

### 6.1 Register

Validator starts active from current `accFeePerWeight`. Does not earn retroactively.

```
rewardDebt[v] = accFeePerWeight (current)
effectiveWeight added to totalEffectiveWeight
```

### 6.2 Deactivate

Checkpoints earned fees into `pendingReward`. Removes from `totalEffectiveWeight`.
Validator can still `claimFees` their checkpointed pending reward.

### 6.3 Reactivate

Sets `rewardDebt[v] = accFeePerWeight` (current). No retro-accrual for inactive period.
Adds effective weight back to `totalEffectiveWeight`.

### 6.4 Weight / Uptime Change

1. Checkpoint current earnings into `pendingReward`.
2. Remove old effective weight from `totalEffectiveWeight`.
3. Apply new value.
4. Add new effective weight to `totalEffectiveWeight`.

---

## 7. Fee Flow

```
Transaction fees
    │
    ▼
FeeDistributor (receives via AvalancheGo AddBalance → silent)
    │
    │ distribute() — permissionless
    │
    ├─ 70% → ValidatorFeeVault.receive() → accFeePerWeight update
    ├─ 20% → DevTreasury.receive()
    └─ 10% → 0xdEaD (burn)
```

Inside `ValidatorFeeVault.receive()`:
- `totalReceived += msg.value`
- If `totalEffectiveWeight > 0`: `accFeePerWeight += amount * PRECISION / totalEffectiveWeight`
- If `totalEffectiveWeight == 0`: `unallocated += amount`
- Emits `FeeReceived`

---

## 8. Unallocated Fees

Fees arriving when `totalEffectiveWeight == 0` accumulate in `unallocated`. This handles the period before any validators are registered (chain genesis) or if all validators are simultaneously deactivated.

`distributeUnallocated()` is permissionless. Any caller can flush `unallocated` into `accFeePerWeight` once at least one active validator exists. Admin is expected to call this after initial validator registration.

---

## 9. Claim Model

Pull-only. Push (automatic distribution) is not implemented because of reentrancy surface and gas cost.

```solidity
function claimFees(bytes32 validationId)
    external
    nonReentrant
    returns (uint256 amount)
```

- Only `rewardRecipient` may call.
- CEI: `pendingReward = 0` before native PW transfer.
- Emits `ValidatorFeeClaimed`.

---

## 10. Rounding / Dust

- All arithmetic uses integer floor division.
- Dust = `balance - sum(claimable) - unallocated`.
- Dust accumulates as rounding remainder each time fees arrive.
- Dust is bounded by `totalEffectiveWeight` wei per fee-receipt event.
- Dust is not lost; it stays in vault balance forever.

**Conservation invariants:**
1. `balance == totalReceived - totalClaimed` (exact)
2. `balance >= sum(claimable) + unallocated` (no over-allocation)
3. `totalClaimed <= totalReceived` (no phantom payout)

---

## 11. Reentrancy Guard

Inline reentrancy guard (no OZ dependency):

```solidity
uint256 private constant _NOT_ENTERED = 1;
uint256 private constant _ENTERED     = 2;
uint256 private _reentrancyStatus = _NOT_ENTERED;
```

`claimFees()` is the only external function with a native-PW transfer; it carries `nonReentrant`. `receive()` updates state only, no external calls.

---

## 12. What C04 Does Not Implement

| Feature | Planned sprint |
|---|---|
| Staking / delegation | C05+ |
| Unbonding / slashing | C05+ |
| RewardVault (15M PW staking reserve) | C05+ |
| Production multisig / timelock | C05+ |
| PoS validator discovery | Phase 2 (Warp-based StakingManager) |
| PWUSD / stablecoin interactions | Separate module |

---

## 13. Invariants (8 total)

| # | Invariant | Verified by |
|---|---|---|
| INV-1 | `balance == totalReceived - totalClaimed` | Unit + Fuzz |
| INV-2 | `balance >= sum(claimable) + unallocated` | Unit + Fuzz + Invariant harness |
| INV-3 | `totalClaimed <= totalReceived` | Unit + Fuzz + Invariant harness |
| INV-4 | `accFeePerWeight` monotonically non-decreasing | Invariant harness |
| INV-5 | `totalEffectiveWeight` = Σ active validator effective weights | Invariant harness |
| INV-6 | `unallocated <= totalReceived` | Invariant harness |
| INV-7 | `Σ per-validator totalClaimed == vault.totalClaimed` | Invariant harness |
| INV-8 | `roundingDust >= 0` (no over-allocation from rounding) | Unit + Invariant harness |

---

## 14. Events

| Event | Trigger |
|---|---|
| `ValidatorRegistered(validationId, recipient, baseWeight, uptimeBips)` | `registerValidator` |
| `ValidatorActivated(validationId)` | `activateValidator` |
| `ValidatorDeactivated(validationId, checkpointedReward)` | `deactivateValidator` |
| `ValidatorUpdated(validationId, baseWeight, uptimeBips)` | `setUptimeBips` / `setBaseWeight` |
| `FeeReceived(amount, newAccFeePerWeight, totalEffectiveWeight)` | `receive()` |
| `FeeAccrued(validationId, amount)` | `_checkpoint` (internal) |
| `ValidatorFeeClaimed(validationId, recipient, amount)` | `claimFees` |
| `UnallocatedDistributed(amount)` | `distributeUnallocated` |

---

## 15. Unchanged Contracts

The following C03 contracts are **unchanged** in C04:

| Contract | Address | Note |
|---|---|---|
| `DevTreasury.sol` | `0xe7f172…` | Simple receiver |
| `FeeDistributor.sol` | `0x9fE467…` | 70/20/10 split; permissionless `distribute()` |

The `ValidatorFeeVault` is redeployed at the same deterministic address (`nonce=0` from DEV0) because CREATE uses `sender+nonce` only, not bytecode. The address `0x5FbDB2315678afecb367f032d93F642f64180aa3` is preserved.

---

## 16. Phase 2 Migration Path

In Phase 2, `protocolAdmin` (currently DEV0) is replaced by `PrimeWaveStakingManager`:
- Staking manager reads Warp-verified validator uptime and stake from P-Chain.
- Calls `setUptimeBips(validationId, newBips)` periodically to update eligibility.
- Calls `registerValidator` / `deactivateValidator` as validators enter/exit.
- `ValidatorFeeVault` accounting interface remains unchanged.
- `rewardRecipient` = staker's EVM address (set at registration).

---

*Document locked after C04 acceptance gate passes.*
