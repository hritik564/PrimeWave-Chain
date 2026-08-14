---
name: PrimeWave Chain PW-C10
description: C10 hardening sprint — 9 attack test files, 1 integration script, 4 audit docs; all 745 tests passing
---

## C10 Sprint Outcome

COMPLETE and LOCKED. 745/745 tests pass (676 non-fuzz + 69 fuzz).

New tests: 159 non-fuzz + 10 fuzz functions across 9 attack test files.
C00–C09 regression: all 517 tests still green.

## Key Architectural Facts Confirmed

**`forceInitiateValidatorRemoval`**: required when vault reward = 0 (exhausted vault or no uptime). `initiateValidatorRemoval` reverts `ValidatorIneligibleForRewards` per Avalanche upstream when reward = 0. Both enforce ownership and 14-day unbonding.

**`vault.claim` requires `msg.sender == rewardAddress`**: error string `"RV: caller is not rewardAddress"`. Always `vm.prank(rewardAddress)` before claim in tests.

**`totalEmitted` is lazy**: only updates when a state-changing function calls `_updateEmissionIndex()`. `claimable()` view computes correctly without updating storage. Trigger a state change before reading `totalEmitted` in assertions.

**`vm.prank` consumed by view calls in argument**: any `f(vault.view())` with preceding `vm.prank` consumes prank on the view, not `f`. Always precompute view results.

**`via_ir` + `block.timestamp` caching**: compiler caches `block.timestamp` at function entry. Never re-read after `vm.warp`. Precompute ALL absolute timestamps from `t0` at function start.

**RewardVault admin in production = PrimeWaveTimelock**: all admin-gated calls (`registerRecipient`, `setEmissionRate`, `setStakingManager`, `setPauseController`) must prank as `address(timelock)`. In GovernanceAttack tests the vault is deployed with `address(timelock)` as admin.

**`feeVault.claimFees(id)`** requires `msg.sender == rewardAddress` (error `"VFV: caller is not recipient"`). Always `vm.prank(feeRecv)` before calling.

**`setEmissionRate` error string**: `"RV: rate not reduced"` (not "rate must be reduced" or similar). Ratchet-only downward.

## Security Findings (no critical/high)

- SEC-M-01: `forceInitiateValidatorRemoval` bypasses uptime eligibility — accepted as liveness escape hatch
- SEC-M-02: Timelock `execute()` permissionless after delay — accepted OZ behavior
- SEC-L-01: EMS signers immutable post-deployment — deferred to C11 (add `updateSigner` via timelock)
- SEC-L-02/L-03: FeeDistributor dust / permissionless fund — accepted

## Fuzz Pitfall

`testFuzz_FA05_fuzzUnbondTiming(uint64 waitSeconds)`: bound waitSeconds to ≤ 315_360_000 (10 years) to prevent `t0 + waitSeconds` overflow.

## Documentation

- `docs/PW-C10-SECURITY-AUDIT.md`
- `docs/PW-C10-ECONOMIC-AUDIT.md`
- `docs/PW-C10-PHASE-TRANSITION-AUDIT.md`
- `docs/PW-C10-FINAL-REPORT.md`

## C11 Prerequisites

- External security audit engagement
- EMS signer rotation (`updateSigner` via timelock)
- Mainnet deployment runbook
- Monitoring/event-indexing setup
- Formal verification scope for RewardVault index model
