# PW-C05 Validator Integration Specification

**Status:** COMPLETE  
**Sprint:** C05  
**Date:** 2026-08-14  
**Chain:** primewavedev (Chain ID 73571)  
**Foundry:** v1.7.1  

---

## 1. Objective

Implement the secure integration between Avalanche's on-chain ValidatorManager layer and the PrimeWave EVM-side fee accounting (ValidatorFeeVault, C04). The integration must:

- Use the authoritative ACP-99 ValidatorManager as the sole source of truth for validator existence, status, and weight.
- Preserve all C04 accounting invariants without modification.
- Not invent an insecure admin oracle (no unrestricted `setValidatorActive()` etc.).
- Document and respect all EVM/P-Chain boundaries.
- Stop cleanly at uptime — do not implement a production uptime oracle.

---

## 2. Architecture

```
Avalanche P-Chain (Warp/ICM)
      | validator set changes (Warp messages)
      v
ValidatorManager (ACP-99 — ava-labs/icm-services@40e1c89)
      | getValidator(validationID) — EVM-readable
      v
PrimeWaveValidatorRegistry  (NEW — C05)
      | registerValidator / syncValidator / updateWeight
      v
ValidatorFeeVault           (C04 — unchanged except §11)
      | reward-index accounting
      v
Validator claimFees()
```

### Contract Deployment Order (pre-computed addresses)

Given deployer nonce N at deployment time:
- `nonce N+0` → MockValidatorManager (dev) or real ValidatorManager (production)
- `nonce N+1` → ValidatorFeeVault (admin = `computeCreateAddress(deployer, N+2)`)
- `nonce N+2` → PrimeWaveValidatorRegistry

The registry address must be pre-computed and passed into the ValidatorFeeVault constructor. This is deterministic and verified by an `assertEq` in the deployment scripts.

---

## 3. Validator Identity

The canonical validator identifier is the `validationID` (bytes32) returned by `ValidatorManager.initiateValidatorRegistration()` and confirmed after the P-Chain Warp round-trip via `completeValidatorRegistration()`.

The same `validationID` is used as the key in both `PrimeWaveValidatorRegistry` and `ValidatorFeeVault`.

NodeID is NOT used as a key in PrimeWave accounting (it is accessible via `getValidator().nodeID` if needed for display).

---

## 4. EVM-Accessible Validator Data (Architecture Map)

| Data | Source | EVM Accessible? | Method |
|---|---|---|---|
| validationID | ValidatorManager | YES | returned from `initiateValidatorRegistration()` |
| Validator status | ValidatorManager | YES | `getValidator(id).status` |
| Validator weight | ValidatorManager | YES | `getValidator(id).weight` |
| nodeID | ValidatorManager | YES | `getValidator(id).nodeID` |
| nodeID → validationID | ValidatorManager | YES | `getNodeValidationID(nodeID)` |
| Total L1 weight | ValidatorManager | YES | `l1TotalWeight()` |
| Validator uptime | P-Chain tracking | **NO** | P-Chain only; no EVM interface |
| Reward eligibility threshold | P-Chain/Protocol | **NO** | Not exposed to EVM |

Source: `ava-labs/icm-services` tag `icm-relayer-v1.7.5` commit `40e1c89`, path `icm-contracts/avalanche/validator-manager/`

---

## 5. ACP-99 Validator Status Lifecycle

```
Unknown(0)
    |
    | initiateValidatorRegistration()
    v
PendingAdded(1)  <-- registration initiated, P-Chain Warp not yet confirmed
    |                    (fee accrual: INACTIVE)
    | completeValidatorRegistration()  [Warp confirmed]
    v
Active(2)        <-- normal operating state
    |                    (fee accrual: ACTIVE)
    | initiateValidatorRemoval()
    v
PendingRemoved(3) <-- removal initiated, P-Chain Warp not yet confirmed
    |                    (fee accrual: INACTIVE — immediately on sync)
    | completeValidatorRemoval()       [Warp confirmed]
    v
Completed(4)     <-- fully removed; earned fees remain claimable forever
                        (fee accrual: INACTIVE)

PendingAdded or PendingRemoved can also expire:
    |
    | (Warp message timeout)
    v
Invalidated(5)   <-- message expired without P-Chain confirmation
                        (fee accrual: INACTIVE)
```

**PrimeWaveValidatorRegistry sync rules:**

| ACP-99 Status | feeVault action |
|---|---|
| Active | `activateValidator()` if currently inactive |
| PendingRemoved | `deactivateValidator()` if currently active |
| Completed | `deactivateValidator()` if currently active |
| Invalidated | `deactivateValidator()` if currently active |
| PendingAdded | no action (awaiting P-Chain confirmation) |
| Unknown | revert (not managed) |

---

## 6. Uptime — Explicit Stop Boundary

**Validator uptime is tracked exclusively by the P-Chain and is NOT exposed to the EVM layer through any mechanism at this time (August 2026).**

The P-Chain tracks per-validator uptime as part of its consensus protocol. No standard ACP-99 interface or Warp message type exists to relay uptime percentages to EVM contracts.

**Phase 1 decision:** All PoA validators are assumed fully eligible. `uptimeBips` defaults to `10,000` (100%) for all registered validators. The `setUptimeBips()` function exists as an admin-only hook for a future trusted oracle.

**Future oracle requirement:** A Phase 2 uptime integration MUST design and implement:
1. An off-chain service that reads P-Chain uptime data.
2. An on-chain attestation mechanism (e.g. multisig-attested uptime reports).
3. An economic security model ensuring the oracle cannot be manipulated.

This is explicitly out of scope for C05. The `setUptimeBips()` admin hook must not be called with unauthenticated data until a proper oracle is approved.

---

## 7. Reward Recipient Binding Security

The ValidatorManager does NOT store an EVM reward recipient. Binding is a PrimeWave protocol-level operation.

**Why attackers cannot self-register:**

1. `registerValidator()` is `onlyAdmin` — admin key (multisig+timelock in production) required.
2. The `validationID` must exist in ValidatorManager with `status != Unknown` — meaning the actual P-Chain validator was already registered by the admin using the PoAManager.
3. The admin controls both the PoAManager registration AND the recipient binding ceremony.
4. A node operator (who has a validating node but not the admin key) cannot unilaterally bind their address.

**Recipient change security:** `setRewardRecipient()` is also `onlyAdmin`. Unclaimed fees earned before the recipient change remain claimable by the new recipient (the vault's `claimFees` checks `msg.sender == rewardRecipient` at claim time). The old recipient should claim before the change is made.

---

## 8. Local Dev vs. Production

### Local Dev (primewavedev chain)

| Component | Dev | Production |
|---|---|---|
| ValidatorManager | `MockValidatorManager` (no Warp) | Real `PoAValidatorManager` (Warp + ICM relayer) |
| P-Chain | Not needed | Required (Warp round-trips) |
| ICM relayer | Not needed | Required |
| BLS signatures | Not needed | Required from validator nodes |
| Admin | DEV0 EOA | Multisig + timelock |

`MockValidatorManager` has `devRegister`, `devActivate`, `devInitiateRemoval`, `devComplete`, `devInvalidate`, `devSetWeight`, `devForceStatus` — all DEV-ONLY functions that simulate the ACP-99 state machine without Warp. It is clearly labeled and MUST NOT be deployed in production.

### Production Path

```
1. Admin calls PoAManager.initiateValidatorRegistration(nodeID, bls_pub_key, ...)
2. ICM relayer picks up the Warp message and relays to P-Chain
3. P-Chain confirms; ICM relayer calls PoAManager.completeValidatorRegistration(warpMsg)
   → validator is now Active in ValidatorManager
4. Admin calls registry.registerValidator(validationID, recipient, weight)
   → validator is registered in feeVault and starts earning fees
```

---

## 9. Multi-Node Testing Limitation

The local primewavedev setup is a single-node network (1 of 15 validators running). A full multi-node test would require:

1. Starting all 15 nodes concurrently.
2. Verifying that block fees are distributed by the genesis-hardcoded FeeDistributor.
3. Confirming that ValidatorFeeVault receives its 70% share.
4. Running all 15 validators through full lifecycle transitions.

This is documented as a future integration requirement. The current single-node integration test (IntegrationC05.s.sol) validates the complete smart-contract lifecycle against the live chain.

---

## 10. New Contracts (C05)

### `contracts/src/PrimeWaveValidatorRegistry.sol`

| Property | Value |
|---|---|
| Purpose | Bridge ACP-99 ValidatorManager → ValidatorFeeVault |
| Admin | `protocolAdmin` (immutable; DEV0 in dev, multisig+timelock in prod) |
| Immutables | `protocolAdmin`, `validatorManager`, `feeVault` |
| Key functions | `registerValidator()`, `syncValidator()`, `syncAll()`, `updateWeight()`, `setUptimeBips()`, `setRewardRecipient()` |
| Access control | `registerValidator`, `setUptimeBips`, `setRewardRecipient` are `onlyAdmin`; sync/updateWeight are permissionless |
| State | `isManaged`, `managedValidators[]`, `rewardRecipient` |

### `contracts/test/MockValidatorManager.sol`

DEV-ONLY. Implements `IACP99ManagerReader` plus write functions for test state control. Never use in production.

---

## 11. Changes to `contracts/src/ValidatorFeeVault.sol` (C05 additions)

Two backward-compatible additions to ValidatorFeeVault (no changes to existing logic):

1. **`setRewardRecipient(bytes32 validationId, address newRecipient) external onlyAdmin`** — allows the registry (as admin) to update a validator's reward recipient. Emits `ValidatorRecipientUpdated`.

2. **`isActive(bytes32 validationId) external view returns (bool)`** — convenience view so the registry can query active status without decoding the full `ValidatorInfo` struct.

3. **`event ValidatorRecipientUpdated(bytes32 indexed validationId, address indexed newRecipient)`** — new event.

All existing C04 logic, storage layout, and interfaces are unchanged.

---

## 12. Gas Profile (from `test_GasAnalysis`)

| Operation | Gas |
|---|---|
| `registerValidator()` (Active validator) | ~231,240 |
| `syncValidator()` (no-op, already synced) | ~6,594 |
| `syncValidator()` (deactivation) | ~13,266 |
| `updateWeight()` | ~33,039 |
| `setUptimeBips()` | ~28,597 |
| `setRewardRecipient()` | ~6,248 |
| `claimFees()` | ~101,293 |

All operations are comfortably within the 30M block gas limit. The most expensive operation (`registerValidator`) is an admin-only one-time call per validator.

---

## 13. Security Properties Proven (C05 §22)

All 15 security scenarios from the C05 specification were tested and verified:

| # | Scenario | Test | Result |
|---|---|---|---|
| 1 | Fake validator registration | `test_SEC_01_FakeValidatorRegistration_Reverts` | PASS |
| 2 | Duplicate registration | `test_SEC_02_DuplicateRegistration_Reverts` | PASS |
| 3 | Sync cannot fake removal | `test_SEC_03_SyncValidator_CannotFakeRemoval` | PASS |
| 4 | Cannot bypass deactivation | `test_SEC_04_AttackerCannotReactivate` | PASS |
| 5 | Unauthorized weight change | `test_SEC_05_UnauthorizedWeightChange_Reverts` | PASS |
| 6 | Unauthorized recipient change | `test_SEC_06_UnauthorizedRecipientChange_Reverts` | PASS |
| 7 | Unauthorized uptime change | `test_SEC_07_UnauthorizedUptimeChange_Reverts` | PASS |
| 8 | Cannot register completed validator | `test_SEC_08_CannotRegisterCompletedValidator` | PASS |
| 9 | Reward recipient mismatch | `test_SEC_09_RewardRecipientMismatch_Reverts` | PASS |
| 10 | Stale state after removal | `test_SEC_10_StaleState_SyncAfterRemoval` | PASS |
| 11 | Replay sync is idempotent | `test_SEC_11_ReplaySyncIsIdempotent` | PASS |
| 12 | Weight update after deactivation | `test_SEC_12_WeightUpdateAfterDeactivation` | PASS |
| 13 | Historical weight not manipulated | `test_SEC_13_HistoricalWeightNotManipulated` | PASS |
| 14 | Claim after deactivation | `test_SEC_14_ClaimAfterDeactivation` | PASS |
| 15 | Re-activation no retro-accrual | `test_SEC_15_ReactivationNoDoubleCount` | PASS |

---

## 14. Acceptance Criteria

- [x] New contract `PrimeWaveValidatorRegistry` bridges ACP-99 ValidatorManager to ValidatorFeeVault
- [x] ValidatorManager is the sole source of truth for validator existence and status
- [x] No unrestricted admin oracle for validator activation
- [x] All 15 C05 security scenarios tested and proven
- [x] C04 regression: all 113 C04 tests still pass
- [x] `setRewardRecipient` and `isActive` added to ValidatorFeeVault (backward-compatible)
- [x] MockValidatorManager clearly labeled dev-only
- [x] Uptime stop boundary documented; `setUptimeBips` admin hook in place
- [x] Gas profile documented
- [x] Multi-node limitation documented
- [x] No Phase 2 / PoS / staking / RewardVault work done

---

*C05 specification locked. Do not begin C06 without user approval.*
