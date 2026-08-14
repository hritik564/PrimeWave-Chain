# PW-C11: Validator Operations

**Sprint:** C11 — Production Infrastructure + Validator Keeper + Genesis Finalization
**Status:** COMPLETE
**Date:** 2026-08-14

---

## Overview

This document defines the full validator lifecycle for PrimeWave Chain production operations. All procedures must be followed exactly. Deviations require a protocol admin approval (via PrimeWaveTimelock + 48h delay).

---

## 1. Validator Lifecycle States

```
                            ┌──────────────────┐
                            │   NOT REGISTERED  │
                            └────────┬─────────┘
                                     │ 1. registerValidator() [protocol admin]
                                     ▼
                            ┌──────────────────┐
                            │   PendingAdded    │  fee accrual: OFF
                            └────────┬─────────┘
                                     │ P-Chain confirms Warp msg
                                     │ syncValidator() [keeper]
                                     ▼
                            ┌──────────────────┐
                            │     Active        │  fee accrual: ON
                            └────────┬─────────┘
                                     │ forceInitiateValidatorRemoval()
                                     │ or graceful removal
                                     ▼
                            ┌──────────────────┐
                            │  PendingRemoved   │  fee accrual: STOPPED
                            └────────┬─────────┘
                                     │ P-Chain confirms removal
                                     │ syncValidator() [keeper]
                                     ▼
                            ┌──────────────────┐
                            │    Completed      │  earned fees: still claimable
                            └──────────────────┘

     Alternate: PendingAdded → Invalidated (Warp msg expired — registration failed)
```

---

## 2. Validator Registration Procedure (15 Steps)

### Prerequisites

Before starting, confirm:
- [ ] AvalancheGo v1.14.2 is installed on the validator node
- [ ] Validator node is synced with the PrimeWave Chain
- [ ] NodeID is known (run: `curl 127.0.0.1:9650/ext/info | jq .result.nodeID`)
- [ ] BLS public key is generated per `PRIMEWAVE_KEY_SECURITY_PROCEDURE.md`
- [ ] Reward recipient address is confirmed (cold wallet)
- [ ] Protocol admin key is available (hardware wallet, offline)
- [ ] At least 3 EMS signers are available for emergency recovery

### Step 1: Generate Validator Identity

```bash
# On the validator node (offline if possible)
# NodeID is derived from the staking certificate
cat /var/lib/avalanchego/staking/staker.crt | openssl x509 -noout -fingerprint -sha256

# Record NodeID from AvalancheGo info endpoint
NODE_ID=$(curl -sf http://127.0.0.1:9650/ext/info | jq -r .result.nodeID)
echo "NodeID: $NODE_ID"
```

### Step 2: Prepare Registration Parameters

```
validationID:    bytes32  — computed from NodeID + registration params
recipient:       address  — reward recipient (cold wallet, not validator hot wallet)
weight:          uint64   — initial staking weight (per PRIMEWAVE_GOVERNANCE_POLICY.md)
```

### Step 3: Submit to P-Chain (AvalancheGo)

```bash
# Via Avalanche Wallet or AvalancheCLI
# This creates the Warp message that triggers ValidatorManager registration
avalanche validator add \
  --node-id $NODE_ID \
  --delegation-fee 0 \
  --stake-amount $STAKE_AMOUNT \
  --start-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time "$(date -d '+365 days' -u +%Y-%m-%dT%H:%M:%SZ)" \
  --subnet-id $PRIMEWAVE_SUBNET_ID
```

### Step 4: Obtain validationID

After P-Chain submission, retrieve the `validationID` (bytes32) from the ValidatorManager:

```bash
# Via forge call or direct eth_call
forge call $VALIDATOR_MANAGER_ADDRESS \
  "getValidator(bytes32)(status,nodeID,weight)" $VALIDATION_ID \
  --rpc-url $CHAIN_RPC_URL
```

### Step 5: Call registerValidator() (Protocol Admin)

```bash
# Protocol admin calls registry.registerValidator
# Requires: admin key (hardware wallet)
forge script contracts/script/DeployProduction.s.sol:RegisterValidator \
  --rpc-url $CHAIN_RPC_URL \
  --broadcast \
  --sig "registerValidator(bytes32,address,uint64)" \
  $VALIDATION_ID $RECIPIENT_ADDRESS $WEIGHT
```

Or via Gnosis Safe / Timelock if admin is multisig.

### Step 6: Verify PendingAdded State

```bash
# Confirm validator is now managed and in PendingAdded state
forge call $REGISTRY_ADDRESS \
  "validatorStatus(bytes32)(uint8)" $VALIDATION_ID \
  --rpc-url $CHAIN_RPC_URL
# Expected: 1 (PendingAdded)
```

### Step 7: Wait for P-Chain Confirmation

P-Chain → ValidatorManager Warp message relay typically takes 30–120 seconds. Monitor ValidatorManager:

```bash
watch -n 10 "forge call $VM_ADDRESS \
  'getValidator(bytes32)(uint8,bytes,uint64,uint64,uint64,uint64,uint64,uint64)' \
  $VALIDATION_ID --rpc-url $CHAIN_RPC_URL"
# Wait for status to become 2 (Active)
```

### Step 8: Keeper Syncs Automatically

Once ValidatorManager shows Active, the keeper calls `syncValidator()` within the next poll interval (default: 30 seconds). This activates fee accrual in `ValidatorFeeVault`.

Manual override if needed:
```bash
forge send $REGISTRY_ADDRESS \
  "syncValidator(bytes32)" $VALIDATION_ID \
  --rpc-url $CHAIN_RPC_URL \
  --private-key $KEEPER_PRIVATE_KEY
```

### Step 9: Verify Active State

```bash
# Confirm Active in registry
forge call $REGISTRY_ADDRESS \
  "validatorStatus(bytes32)(uint8)" $VALIDATION_ID \
  --rpc-url $CHAIN_RPC_URL
# Expected: 2 (Active)

# Confirm active in fee vault
forge call $FEE_VAULT_ADDRESS \
  "isActive(bytes32)(bool)" $VALIDATION_ID \
  --rpc-url $CHAIN_RPC_URL
# Expected: true
```

### Step 10: Verify Fee Accrual

After 60 seconds of active state:
```bash
forge call $FEE_VAULT_ADDRESS \
  "pendingFees(bytes32)(uint256)" $VALIDATION_ID \
  --rpc-url $CHAIN_RPC_URL
# Expected: > 0 (growing over time)
```

### Steps 11–15: Ongoing Operations

| Step | Action | Frequency |
|------|--------|-----------|
| 11 | Monitor keeper `/health` endpoint | Continuous |
| 12 | Monitor `pendingFees` accumulation | Daily |
| 13 | Claim fees via `claimFees(validationID)` | Weekly or as needed |
| 14 | Update weight if consensus weight changes | As needed (keeper handles) |
| 15 | Rotate BLS keys per security schedule | Annually |

---

## 3. Validator Removal Procedure

### Graceful Removal (Planned)

1. Submit removal to P-Chain via AvalancheCLI
2. ValidatorManager status → PendingRemoved
3. Keeper calls `syncValidator()` — fee vault deactivated
4. P-Chain confirms removal → Completed
5. Validator claims any remaining fees via `claimFees()`

### Emergency Removal (Validator Vault Exhausted)

If `forceInitiateValidatorRemoval()` is required (e.g., vault exhausted mid-period):

```bash
# Requires protocol admin (timelock in production)
forge send $STAKING_MANAGER_ADDRESS \
  "forceInitiateValidatorRemoval(bytes32)" $VALIDATION_ID \
  --rpc-url $CHAIN_RPC_URL \
  --private-key $ADMIN_KEY
```

**Note:** Only necessary when the vault runs out of ETH before the unbonding period ends. See C10 audit findings.

---

## 4. Fee Claiming Procedure

Validators (or their delegated reward recipient) call `claimFees()` directly on `ValidatorFeeVault`:

```bash
forge send $FEE_VAULT_ADDRESS \
  "claimFees(bytes32)" $VALIDATION_ID \
  --rpc-url $CHAIN_RPC_URL \
  --private-key $RECIPIENT_PRIVATE_KEY
```

**Important:** The claim must be made from the registered `rewardRecipient` address. The registry admin can update `rewardRecipient` via `setRewardRecipient()`.

---

## 5. Weight Management

Validator weight is updated automatically by the keeper when `ValidatorManager` reports a changed weight. Manual override:

```bash
forge send $REGISTRY_ADDRESS \
  "updateWeight(bytes32)" $VALIDATION_ID \
  --rpc-url $CHAIN_RPC_URL \
  --private-key $ANY_EOA_PRIVATE_KEY  # permissionless
```

---

## 6. Invariants to Monitor

| Invariant | Check | Alert Threshold |
|-----------|-------|-----------------|
| `isActive` matches P-Chain status | keeper syncs | > 5 min lag |
| `pendingFees` never exceeds vault balance | vault solvency | 90% consumed |
| Keeper `consecutiveFailures` | health endpoint | ≥ 3 |
| `totalEmitted` ≤ `totalFunded` | RewardVault | Immediate if violated |
| `syncAll()` completes without revert | daily check | Any revert |

---

## 7. References

- `docs/PRIMEWAVE_KEY_SECURITY_PROCEDURE.md` — Key generation and storage
- `docs/PW-C11-DISASTER-RECOVERY.md` — Node failure procedures
- `docs/PW-C11-KEEPER-SPEC.md` — Keeper design
- `contracts/src/PrimeWaveValidatorRegistry.sol` — Registry source
- `contracts/src/ValidatorFeeVault.sol` — Fee vault source
