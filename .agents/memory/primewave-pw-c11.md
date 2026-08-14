---
name: PrimeWave Chain PW-C11
description: C11 COMPLETE — Production Infrastructure + Validator Keeper + Genesis Finalization. 792/792 Forge tests. 20/20 keeper Jest tests.
---

# PW-C11: Production Infrastructure

## Status
COMPLETE. Gate passed. Locked forever.

## Final Test Counts
- Forge: 792/792 tests passing (745 from C00–C10 + 47 new C11)
- Keeper Jest: 20/20 passing

## Key Deliverables

### Contracts / Scripts (new)
- `contracts/test/C11Infrastructure.t.sol` — 47 tests: INV-G, FUND, SYNC, PROT, EMS-ROT, FEE, SOL sections
- `contracts/script/IntegrationC11.s.sol` — 30-step local rehearsal script
- `contracts/script/DeployProduction.s.sol` — Hardened with 3 guards + address prediction + 15M PW invariant

### Bug Fix
- `contracts/script/ValidateGenesis.s.sol` — removed `view` from all `_validate*` helper functions (they call state-writing `_pass`/`_warn`/`_fail`); added `require(failCount == 0)` at end

### Keeper Service
- `keeper/src/config.ts`, `keeper/src/state.ts`, `keeper/src/keeper.ts`
- `keeper/test/keeper.test.ts` — uses dependency injection, NOT ethers class mocking
- **DI pattern**: `new PrimewaveKeeper(config, store, provider, contract)` — 4th and 5th args for test injection

### Shell Scripts (all chmod +x)
- `scripts/validate-production-genesis.sh`
- `scripts/health-check.sh`
- `scripts/start-validator.sh`
- `scripts/node-replacement.sh`

### Documentation (10 new + 4 updated)
New: PW-C11-PRODUCTION-INFRASTRUCTURE, VALIDATOR-OPERATIONS, KEEPER-SPEC, GENESIS-FINALIZATION, MONITORING-AND-ALERTING, DISASTER-RECOVERY, DEPLOYMENT-REHEARSAL, PRODUCTION-DEPLOYMENT-CEREMONY, TEST-REPORT, FINAL-REPORT
Updated: PRIMEWAVE_INFRASTRUCTURE, PRIMEWAVE_GENESIS_SPEC, PRIMEWAVE_KEY_SECURITY_PROCEDURE, PRIMEWAVE_GOVERNANCE_POLICY

## Critical Architecture Facts (C11)

### Address Prediction Pattern
Both `ValidatorFeeVault.protocolAdmin` (= registry) and `DevTreasury.feeDistributor` are immutable.
Circular dependency: feeVault needs registry, devTreasury needs FD, FD needs devTreasury, registry needs feeVault.
**Solution:** `vm.computeCreateAddress(deployer, nonce + N)` predict before deploy. Verify with `require(addr == predicted)` after each deployment.

### Keeper Permissionless Design
Keeper EOA needs NO privileged role. `syncValidator()` and `updateWeight()` are permissionless on `PrimeWaveValidatorRegistry`.
Blast radius of keeper key compromise: wasted gas only.

### Jest Keeper Test Pattern
Use dependency injection NOT ethers mocking.
`makeKeeper` does NOT call `store.load()` on a pre-provided store — that would wipe in-memory upserts.
ethers class mocking is fragile because `import { ethers } from 'ethers'` gets the namespace object; mock must shadow `.ethers.*` not just top-level exports.

### ValidateGenesis.s.sol
All `_validate*` helper functions must NOT have `view` — they call `_pass()`/`_warn()`/`_fail()` which write state (increment counters).

### ValidatorStatus Enum (test file C11)
All `public view` test functions must drop `view` if they call `makeAddr()` (StdUtils — state-writing).

## EMS Rotation
No on-chain `updateSigner` exists. Rotation = new EMS deployment + `setPauseController` via Protocol Admin + 48h Timelock. Documented in KEY_SECURITY_PROCEDURE section 13 and GOVERNANCE_POLICY section 8.
