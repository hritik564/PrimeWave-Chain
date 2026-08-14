---
name: PrimeWave Chain PW-C05
description: C05 COMPLETE — validator registry adapter; 190/190 tests; locked
---

## Status
COMPLETE AND LOCKED — 2026-08-14

## What C05 delivered
- `contracts/src/PrimeWaveValidatorRegistry.sol` — bridges ACP-99 ValidatorManager to ValidatorFeeVault
- `contracts/test/MockValidatorManager.sol` — DEV-ONLY ACP-99 simulator (no Warp needed)
- Two backward-compatible additions to `ValidatorFeeVault`: `setRewardRecipient()` + `isActive()` view + `ValidatorRecipientUpdated` event
- 65 unit + 8 fuzz + 4 invariant = 77 new tests; 190 total (including C04 regression)

## Test count history
C02: 13 | C03: 52 | C04: 120 | C05: 190 (all PASS)

## Key design decisions

### Deployment order (pre-computed address)
nonce N+0 = MockVM, N+1 = ValidatorFeeVault(admin=registry_addr), N+2 = PrimeWaveValidatorRegistry
Use `vm.computeCreateAddress(deployer, nonce+2)` to get registry address before deployment.
Verified with assertEq in IntegrationC05.s.sol.

### Lazy sync model
syncValidator(id) and syncAll() are permissionless pull operations — no event hooks.
Source-anchored to ValidatorManager; cannot be exploited to fake state changes.

### Uptime stop boundary
Uptime is P-Chain only — NOT exposed to EVM. Phase 1 defaults to uptimeBips=10_000 (100%).
setUptimeBips() is an admin-only hook for a future oracle; DO NOT call with unauthenticated data.

### validationID lifecycle
Once managed (isManaged=true), a validationID cannot be re-registered.
Re-joining validators get a NEW validationID from ValidatorManager.

### MockValidatorManager devSetWeight pitfall
devSetWeight() does `_totalWeight -= old; _totalWeight += new` — requires Active status AND non-zero _totalWeight.
After devInitiateRemoval(), _totalWeight is already decremented. Calling devSetWeight after devForceStatus(Active) causes underflow.
Pattern: use devForceStatus(Active) then updateWeight() (reads existing weight from VM, no devSetWeight needed).

## Docs written
- docs/PW-C05-VALIDATOR-INTEGRATION-SPEC.md
- docs/PW-C05-VALIDATOR-INTEGRATION-TEST-REPORT.md
- docs/PW-C05-FINAL-REPORT.md

## IntegrationC05.s.sol
Live-chain script with 21 assertions covering full lifecycle on primewavedev (Chain ID 73571).
Run pattern same as C04: export path, start node, wait for RPC, export DEV_PRIVATE_KEY_0, forge script --via-ir.
DEV0 nonce continues from wherever C04 left off (~30+). Pre-computation uses vm.getNonce(deployer) at script start.

## C06 gate
STOP HERE. Do not begin C06 without explicit user approval.
