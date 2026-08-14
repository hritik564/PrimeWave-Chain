---
name: PrimeWave Chain PW-C06
description: RewardVault -- finite PW emission from pre-funded 15M pool; 282/282 tests pass
---

## Status: COMPLETE

## What Was Built
- `contracts/src/RewardVault.sol` -- continuous per-second emission, global reward-index model
- `contracts/test/RewardVaultUnit.t.sol` -- 72 unit tests
- `contracts/test/RewardVaultFuzz.t.sol` -- 8 fuzz + 8 stateful invariant tests
- `contracts/script/IntegrationC06.s.sol` -- 11-step live-chain verification script
- 3 docs: SPEC, TEST-REPORT, FINAL-REPORT

## Test Results
- C06 new: 72 unit + 8 fuzz + 8 invariant = 88 tests PASS
- C03-C05 regression: 190/190 PASS
- Grand total: 282/282 PASS

## Key Design Decisions

### Emission Model
- SECONDS_PER_YEAR = 31_536_000
- MAX_RATE_PER_SECOND = 3_000_000e18 / 31_536_000 = 95_129_375_951_293_760 wei/s (floor)
- Global reward index scaled by 1e18; per-recipient pending stored in struct
- totalFunded is the immutable accounting anchor -- NEVER use address(this).balance

### Critical: totalEmitted is write-only
- totalEmitted only updates on write transactions (_updateGlobal called by registerRecipient,
  activateRecipient, deactivateRecipient, setWeight, setEmissionRate, claim)
- View calls (claimable, isExhausted) simulate emission but do NOT write totalEmitted
- Tests that check totalEmitted must trigger a write first (e.g. claim)

### Rate Ratchet
- setEmissionRate reverts if newRate >= emissionRatePerSecond (strict less-than required)
- Constructor rate is the permanent ceiling; no admin bypass

### Zero-weight Pause
- _updateGlobal short-circuits when totalEligibleWeight == 0
- PW stays in vault; no unallocated bucket

### No Registry Coupling in Phase 1
- RewardVault standalone; admin manages recipient lifecycle directly
- C05 registry NOT wired; deferred to C07

### Integer Truncation Tolerance
- MAX_R and MAX_R/2 each truncate independently
- Rate-halving period test: allow +-2_592_000 wei tolerance (1 wei/s * 30-day seconds)

## Fixes Applied During Sprint
1. C05 fuzz F4: added vm.assume to exclude 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D
   (Foundry VM contract address rejects native transfers -- always exclude from recipient fuzz)
2. Several unit tests: totalEmitted assertions moved after a write call (claim/deactivate)

## Invariants Proven (8)
INV-1: totalEmitted <= totalFunded
INV-2: totalClaimed <= totalEmitted
INV-3: totalClaimed <= totalFunded
INV-4: emissionRatePerSecond <= MAX_RATE_PER_SECOND
INV-5: vaultBalance == totalFunded - totalClaimed
INV-6: totalPending == totalEmitted - totalClaimed
INV-7: deactivated fees never confiscated
INV-8: totalRemaining == totalFunded - totalEmitted
