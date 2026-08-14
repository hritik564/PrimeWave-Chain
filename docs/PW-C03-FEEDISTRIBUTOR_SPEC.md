# PW-C03 FeeDistributor Specification

**Sprint:** PW-C03 — FeeDistributor + 70/20/10 Native PW Proof  
**Status:** Implementation complete; integration test pending  
**Date:** 2026-08-14  
**Author:** PrimeWave Chain engineering

---

## 1. Purpose

This document specifies the FeeDistributor contract and the three-contract fee routing system deployed in sprint PW-C03.

PW-C02 confirmed that all transaction fees flow to the Avalanche blackhole address (`0x0100000000000000000000000000000000000000`) under the default genesis configuration. PW-C03 activates the Avalanche `RewardManager` precompile in the genesis, configures FeeDistributor as the `rewardAddress`, and proves that native PW transaction fees are split 70/20/10 across ValidatorFeeVault, DevTreasury, and a permanent burn address.

---

## 2. Contracts Deployed

| Contract | Address | Nonce |
|---|---|---|
| ValidatorFeeVault | `0x5FbDB2315678afecb367f032d93F642f64180aa3` | DEV0 nonce 0 |
| DevTreasury | `0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512` | DEV0 nonce 1 |
| FeeDistributor | `0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0` | DEV0 nonce 2 |

Addresses are deterministic (EVM CREATE). Deployer: `DEV_ACCOUNT_0 = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` with nonce 0 at chain genesis.

---

## 3. Fee Split (Locked)

| Destination | Basis Points | Percentage | Calculation |
|---|---|---|---|
| ValidatorFeeVault | 7000 | 70.00% | `floor(amount × 7000 / 10000)` |
| DevTreasury | 2000 | 20.00% | `floor(amount × 2000 / 10000)` |
| BURN_ADDRESS | 1000 (implied) | ~10.00% | `amount − validatorShare − treasuryShare` |

The burn share uses floor-absorb: it receives the integer remainder. This guarantees `v + t + b == amount` with zero dust. Maximum excess over exact 10%: 2 wei per distribution call.

These constants are compile-time constants in Solidity (`uint256 public constant`). They cannot be changed without redeploying and updating the genesis rewardManagerConfig (which requires protocol governance + 48-hour timelock in production).

---

## 4. Burn Mechanism

```
BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD
```

This is the Ethereum ecosystem standard "dead" address. No private key exists for it. Funds sent here are permanently inaccessible (burn by inaccessibility).

Important: this does NOT reduce the EVM state balance — the EVM still counts those wei as existing. The total supply in EVM state remains constant at 100,000,000 PW; the burned portion is simply permanently frozen.

**Out of scope for C03:** Native protocol-level supply reduction (would require a custom AvalancheGo precompile or a dedicated supply-tracking contract).

---

## 5. Genesis Configuration Change

PW-C02 genesis had `allowFeeRecipients: false` and no `rewardManagerConfig`. This sent all fees to the Avalanche blackhole.

PW-C03 genesis adds:

```json
"rewardManagerConfig": {
  "blockTimestamp": 0,
  "initialRewardConfig": {
    "allowFeeRecipients": false,
    "rewardAddress": "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0"
  }
}
```

With `rewardAddress` set, AvalancheGo credits block fees to FeeDistributor via `StateDB.AddBalance()`. This is NOT an EVM call — FeeDistributor's `receive()` does NOT fire. The balance increases directly in the EVM state.

**This is why `distribute()` reads `address(this).balance`** rather than tracking received fees in `receive()`.

---

## 6. Fee Loop Analysis

A potential concern: if a caller pays gas to call `distribute()`, does that gas fee end up in FeeDistributor and then get re-distributed in the same call, creating a recursive loop?

**Answer: No.** AvalancheGo credits the block fee to the `rewardAddress` AFTER transaction execution completes (at block finalization). During the `distribute()` call itself, `address(this).balance` does NOT include the gas fee for that transaction. That fee is processed by the NEXT call to `distribute()`.

This is not a loop. It is a monotonic queue: each `distribute()` call drains the current accumulated balance, and the fee for that call becomes part of the next batch.

---

## 7. Reentrancy Analysis

`distribute()` sends PW to three addresses using `.call{value:...}("")`. If any recipient is a malicious contract that calls `distribute()` from its `receive()`, the `_distributing` flag blocks the reentrant call with "FeeDistributor: reentrant call".

Checks-Effects-Interactions is followed:
1. **Check:** `amount > 0` and `!_distributing`
2. **Effects:** Update all accumulators + emit event BEFORE any transfer
3. **Interactions:** `.call()` to vault, treasury, burn

If a transfer fails (`.call` returns false), `require()` reverts the transaction. Because effects were applied before interactions, the revert undoes the accounting. This is safe.

---

## 8. ValidatorFeeVault (C03 Scope)

The ValidatorFeeVault is a recording receiver only in C03.

- Accepts PW via `receive()` from FeeDistributor
- Updates `totalReceived` counter and emits `ValidatorFeeReceived`
- No per-validator distribution — deferred to the validator economics sprint
- No admin withdrawal functions

C03 proof goal: verify 70% of every batch reaches this contract's balance.

---

## 9. DevTreasury (C03 Scope)

Same pattern as ValidatorFeeVault. Records and holds 20% of every distribution. No governance, no spending logic, no disbursement. These belong to the production treasury sprint.

---

## 10. Out of Scope for C03

| Feature | Sprint |
|---|---|
| Per-validator claims / weight accounting | Validator economics sprint |
| Staking integration (15M PW reserve) | RewardVault sprint |
| Treasury governance (multisig, timelock) | Governance sprint |
| Protocol-level supply reduction | Custom precompile sprint |
| Upgradeability | Not planned (immutable by design) |

---

## 11. Burn Address Accounting Note

The 0xdead address functions as a receive-only black hole. In this sprint:

- `burnShare` wei is sent to 0xdead with `.call{value: burnShare}("")`
- 0xdead has no code — the call is a simple ETH transfer to an empty address
- The EVM state balance of 0xdead increases permanently
- No event is emitted from 0xdead (it has no code)
- FeeDistributor's own `totalBurnShare` tracks this cumulatively

---

## 12. Access Control Summary

| Function | Access | Notes |
|---|---|---|
| `distribute()` | Any caller | Permissionless |
| `withdraw()` | NONE | Does not exist |
| `ownerWithdraw()` | NONE | Does not exist |
| `setValidatorFeeVault()` | NONE | Does not exist |
| `setTreasury()` | NONE | Does not exist |
| `setSplit()` | NONE | Does not exist |
| `pause()` | NONE | Does not exist |

---

## 13. ValidatorFeeVault Future Architecture (Out of C03)

When the validator economics sprint is implemented:
- `distribute()` on ValidatorFeeVault will use weight × uptime scores
- Pull model: validators claim their earned share; vault never pushes
- Uptime snapshots will be sourced from the Avalanche consensus layer or an oracle
- No centralized dispatcher; each validator calls `claimFee()` on their own

This design is deferred. C03 only proves the 70% arrives at the vault address.
