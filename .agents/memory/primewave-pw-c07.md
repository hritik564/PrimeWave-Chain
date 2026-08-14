---
name: PrimeWave Chain PW-C07
description: C07 Phase-1 PoA Governance Hardening — lessons, constraints, and decisions
---

## Status: COMPLETE (391/391 tests pass)

## New Contracts
- `contracts/src/EmergencyMultisig.sol` — 3-of-5, proposalId = keccak256(target, data, nonce); immutable signer set; any account can execute once threshold met
- `contracts/src/PrimeWaveTimelock.sol` — 48h MIN_DELAY compile-time constant; open executor; predecessor chains; proposer-transferable

## Modified Contracts (backward-compatible)
- `FeeDistributor` — 3rd constructor param `address _pauseController`; `distribute()` gated by `whenNotPaused`
- `ValidatorFeeVault` — pause added; `setPauseController()` callable by `protocolAdmin` OR current `pauseController`; only `claimFees()` gated
- `RewardVault` — pause added; `setPauseController()` callable by `admin` OR current `pauseController`; only `claim()` gated

## Authority Rule (critical)
- `pause()` / `unpause()` = EmergencyMultisig domain only
- Timelock CANNOT call `pause()` directly (requires pauseController = timelock, which is wrong)
- `freeze(account)` is PWUSD-only (Phase 2). Phase 1 has NO freeze.

## Foundry Test Gotchas
- `vm.prank(addr)` + `{value: x}` requires `addr` to have ETH, not the test contract.
  Fix: `vm.deal(addr, x)` before prank, OR remove prank if function is permissionless.
- Stateful invariant `expectedNonce` must be updated in EVERY handler method that calls `ems.propose()`, not just the explicit `propose()` handler. Omission causes INV-2 false failure.

## FeeDistributor Genesis Gap
- C03 genesis FeeDistributor deployed with `pauseController = address(0)`. Cannot change (no admin).
- Production fix: deploy fresh with EmergencyMultisig as 3rd constructor arg from day one.
- Same applies to VFV: genesis admin is the genesis FeeDistributor (which has no forwarding method).

## Docs Written
- `docs/PW-C07-GOVERNANCE-INTEGRATION-SPEC.md`
- `docs/PW-C07-GOVERNANCE-TEST-REPORT.md`
- `docs/PW-C07-FINAL-REPORT.md`

## Script
- `contracts/script/IntegrationC07.s.sol` — 13-step live-chain governance scenario

## Next Sprint
Do not begin C08 without explicit user approval.
