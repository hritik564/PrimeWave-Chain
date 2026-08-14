# PW-C06 — RewardVault Specification

**Status:** COMPLETE  
**Sprint:** PW-C06  
**Date:** 2026-08-14  

---

## 1. Purpose

RewardVault distributes the pre-funded 15,000,000 PW validator reward pool to active validators on a continuous per-second emission schedule. It is a **pull-based, no-minting** contract: all PW was loaded once at genesis; the contract can only pay out what it already holds.

---

## 2. Design Principles

| Principle | Implementation |
|-----------|---------------|
| No minting | `totalClaimed + unaccrued + totalPending == totalFunded` at all times |
| Pre-funded only | `fund()` / `receive()` are the only ways PW enters; `claim()` is the only way PW exits |
| Forced-transfer safe | All accounting uses `totalFunded`, not `address(this).balance` |
| Rate monotone-decreasing | `setEmissionRate()` can only reduce; never increase above initial |
| Zero-weight pauses | When `totalEligibleWeight == 0`, emission clock stops; PW stays in vault |
| Pull-based O(1) claim | Reward-index model; no loops over recipients |
| No retroaccrual | Recipients earn only from their registration/activation block onwards |

---

## 3. Emission Model

### Constants

```
SECONDS_PER_YEAR    = 31_536_000
MAX_ANNUAL_EMISSION = 3_000_000 ether
MAX_RATE_PER_SECOND = 3_000_000e18 / 31_536_000
                    = 95_129_375_951_293_760 wei/s   (floor division)
```

The truncation remainder (≈5.12e-9 PW/year) accumulates silently in the vault and is never emitted.

### Global Index

```
globalIndex     += elapsed * emissionRatePerSecond * PRECISION / totalEligibleWeight
totalEmitted    += min(elapsed * rate, totalFunded - totalEmitted)
lastUpdateTime   = block.timestamp
```

`PRECISION = 1e18` to preserve fractional shares across weight ratios.

### Recipient Share

```
pending[r] += weight[r] * (globalIndex - recipientIndex[r]) / PRECISION
```

---

## 4. State Variables

| Variable | Type | Description |
|----------|------|-------------|
| `admin` | `address immutable` | Only admin may call permissioned functions |
| `emissionRatePerSecond` | `uint256` | Current per-second rate (monotone-decreasing) |
| `totalFunded` | `uint256` | Total PW ever received via `fund()` / `receive()` |
| `totalEmitted` | `uint256` | Total PW allocated to the reward index (capped at `totalFunded`) |
| `totalClaimed` | `uint256` | Total PW transferred out via `claim()` |
| `globalIndex` | `uint256` | Cumulative reward per unit weight × PRECISION |
| `lastUpdateTime` | `uint256` | Block timestamp of last `_updateGlobal()` call |
| `totalEligibleWeight` | `uint256` | Sum of weights of all active recipients |
| `recipientCount` | `uint256` | Count of registered recipients (active + inactive) |

### Recipient Struct

```solidity
struct Recipient {
    bool     active;
    uint128  weight;
    uint256  index;        // globalIndex at last recipient update
    uint256  pending;      // accrued but unclaimed PW (wei)
    bytes32  id;           // immutable ID
    address  rewardAddress;
}
```

---

## 5. Public Interface

### Admin Functions

| Function | Description |
|----------|-------------|
| `registerRecipient(id, addr, weight, active)` | Register a new recipient; active=true adds weight immediately |
| `activateRecipient(id)` | Re-add recipient weight to emission pool |
| `deactivateRecipient(id)` | Checkpoint pending rewards; remove from emission pool |
| `setWeight(id, newWeight)` | Checkpoint then update recipient weight |
| `setRewardAddress(id, addr)` | Change the address that can call `claim()` for this recipient |
| `setEmissionRate(newRate)` | Reduce emission rate; reverts if `newRate >= current` |
| `fund()` | Deposit PW into the vault (payable) |

### Permissionless Functions

| Function | Access | Description |
|----------|--------|-------------|
| `claim(id)` | `rewardAddress` of recipient | Claim all accrued PW for `id` |
| `receive()` | anyone | Accepts PW; counted in `totalFunded` |

### View Functions

| Function | Returns |
|----------|---------|
| `claimable(id)` | Simulated pending PW for recipient (no state change) |
| `isExhausted()` | `true` when `totalEmitted >= totalFunded` |
| `vaultBalance()` | `address(this).balance` |
| `accountedBalance()` | `totalFunded - totalClaimed` |
| `totalPending()` | `totalEmitted - totalClaimed` |
| `totalRemaining()` | `totalFunded - totalEmitted` |

---

## 6. Supply Invariants (§29)

All must hold at every state transition:

| # | Invariant |
|---|-----------|
| INV-1 | `totalEmitted <= totalFunded` |
| INV-2 | `totalClaimed <= totalEmitted` |
| INV-3 | `totalClaimed <= totalFunded` |
| INV-4 | `emissionRatePerSecond <= MAX_RATE_PER_SECOND` |
| INV-5 | `vaultBalance == totalFunded - totalClaimed` |
| INV-6 | `totalPending == totalEmitted - totalClaimed` |
| INV-7 | Deactivated pending fees are never reduced (`claimable + claimed_after >= claimable_at_deactivation`) |
| INV-8 | `totalRemaining == totalFunded - totalEmitted` |

---

## 7. Security Properties

- **No minting:** Contract never creates PW; all transfers are from pre-funded balance.
- **Admin-only gate:** `registerRecipient`, `activateRecipient`, `deactivateRecipient`, `setWeight`, `setRewardAddress`, `setEmissionRate` are admin-only.
- **Claim gate:** `claim(id)` reverts unless `msg.sender == recipients[id].rewardAddress`.
- **Cross-recipient isolation:** Alice cannot claim Bob's rewards.
- **Rate ratchet:** `setEmissionRate` reverts if `newRate >= emissionRatePerSecond`.
- **Forced-transfer immunity:** `totalFunded` is the accounting anchor; `address(this).balance` can exceed it without corrupting emission math.
- **Zero-weight pause:** No PW leaves the vault when `totalEligibleWeight == 0`.
- **Exhaustion cap:** `totalEmitted` is capped at `totalFunded`; claimable is capped at remaining.

---

## 8. Integration with Other C06 Contracts

RewardVault is **intentionally standalone** in Phase 1. It does not call `PrimeWaveValidatorRegistry` or `ValidatorFeeVault`. The admin address (initially DEV0) is responsible for calling `registerRecipient`, `activateRecipient`, and `deactivateRecipient` in response to validator lifecycle events.

Connection to the C05 registry is deferred to a future sprint when the full lifecycle automation is required.

---

## 9. Genesis Funding Plan

```
Vault pre-fund: 15,000,000 PW
Max annual:      3,000,000 PW
Min vault life:  5 years (at MAX_RATE continuously)
```

In practice the vault life is longer because:
- Emission pauses during zero-weight periods
- Rate can only be reduced (never increased)
- Unused emission stays in vault (not burned or redistributed)

---

## 10. Events

```solidity
event RewardVaultFunded(address indexed funder, uint256 amount, uint256 totalFunded);
event RecipientRegistered(bytes32 indexed id, address rewardAddress, uint128 weight, bool active);
event RecipientActivated(bytes32 indexed id);
event RecipientDeactivated(bytes32 indexed id);
event RecipientWeightUpdated(bytes32 indexed id, uint128 oldWeight, uint128 newWeight);
event RewardAddressUpdated(bytes32 indexed id, address oldAddress, address newAddress);
event EmissionRateReduced(uint256 oldRate, uint256 newRate);
event RewardClaimed(bytes32 indexed id, address indexed recipient, uint256 amount);
```
