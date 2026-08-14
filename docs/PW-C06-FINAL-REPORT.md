# PW-C06 — Final Report

**Status:** COMPLETE  
**Sprint:** PW-C06  
**Date:** 2026-08-14  
**Previous sprint:** PW-C05 (validator registry adapter)  
**Next sprint:** PW-C07 (awaiting approval)  

---

## Deliverables

| Deliverable | Status |
|-------------|--------|
| `contracts/src/RewardVault.sol` | DONE — production contract, ~330 lines |
| `contracts/test/RewardVaultUnit.t.sol` | DONE — 72 unit tests, all PASS |
| `contracts/test/RewardVaultFuzz.t.sol` | DONE — 8 fuzz + 8 stateful invariants, all PASS |
| `contracts/script/IntegrationC06.s.sol` | DONE — 11-step live-chain script |
| `docs/PW-C06-REWARDVAULT-SPEC.md` | DONE |
| `docs/PW-C06-REWARDVAULT-TEST-REPORT.md` | DONE |
| `docs/PW-C06-FINAL-REPORT.md` | DONE (this file) |
| C03-C05 regression | DONE — 190/190 PASS |
| **Total tests** | **282/282 PASS** |

---

## What Was Built

### RewardVault.sol

A production Solidity 0.8.30 contract implementing the PrimeWave validator reward pool:

- **Emission model:** Continuous per-second rate; global reward-index model scaled by 1e18
- **Cap:** `MAX_RATE_PER_SECOND = 95,129,375,951,293,760 wei/s` (floor of 3M ether / 31,536,000)
- **Funding:** 15,000,000 PW pre-fund; `totalFunded` is the single source of truth for all accounting
- **Pull claims:** Each recipient pulls via `claim(id)`; O(1), no iteration
- **Rate ratchet:** `setEmissionRate` can only reduce; enforced by revert on `newRate >= current`
- **Zero-weight pause:** `_updateGlobal()` short-circuits when `totalEligibleWeight == 0`
- **Exhaustion cap:** `totalEmitted` is capped at `totalFunded`; claimable is capped at remaining
- **Forced-transfer immunity:** `address(this).balance` is never used for accounting

### Key Design Decisions

**No registry coupling in Phase 1.** The spec allows connection to `PrimeWaveValidatorRegistry` only "if genuinely required." It is not required: the `admin` address manages recipient lifecycle directly. This keeps RewardVault independently deployable, testable, and auditable.

**`totalFunded` accounting anchor.** All invariants are expressed in terms of `totalFunded`, not `address(this).balance`. This means arbitrary PW sent via `selfdestruct` (or in Solidity 0.8.30, any forced transfer) cannot corrupt emission math — the surplus sits unaccounted as an implicit vault reserve.

**`setEmissionRate` is monotone-decreasing.** The initial rate is set in the constructor and is immutably the ceiling. Any call that does not strictly reduce the rate reverts. There is no admin bypass.

---

## Test Coverage

### Unit (72 tests)

Covers every public function path including all revert conditions, event emissions, zero-weight pauses, vault exhaustion, 15M funding, 5-year simulation (using `vm.warp`), supply conservation, and gas logging.

### Fuzz (8 standalone × 256 runs each = 2,048 runs)

Covers random funding amounts, random weights, random rate reductions, random deactivation timing, cross-recipient isolation, conservation across 3 random time periods, 5-year yearly-cap verification, and zero-weight pause correctness.

### Stateful Invariants (8 invariants × 256 sequences × 500 calls each = 1,024,000 state transitions)

Handler dispatches: `fund`, `registerNext`, `advance`, `deactivate`, `activate`, `doClaim`, `reduceRate`, `updateWeight` — zero reverts in 128,000 calls per invariant. All 8 supply invariants hold across every discovered state.

### Regression (190/190)

All prior sprint tests pass. The only change to a prior test file is a single `vm.assume` added to `PrimeWaveValidatorRegistryFuzz.t.sol` to exclude Foundry's internal VM contract address from native-transfer fuzz targets — no logic change.

---

## Invariants Proven

1. `totalEmitted <= totalFunded`
2. `totalClaimed <= totalEmitted`
3. `totalClaimed <= totalFunded`
4. `emissionRatePerSecond <= MAX_RATE_PER_SECOND`
5. `vaultBalance == totalFunded - totalClaimed`
6. `totalPending == totalEmitted - totalClaimed`
7. Deactivated recipients' fees are never confiscated
8. `totalRemaining == totalFunded - totalEmitted`

---

## Security Properties Verified

| Property | Test coverage |
|----------|--------------|
| No minting (supply conserved) | unit L1-L2, fuzz F1, F6, invariant INV-1,2,3,5 |
| Admin-only gates | unit A-G access control tests |
| Claim caller == rewardAddress | unit H4, H7, H8, fuzz F5 |
| Rate can only decrease | unit G2-G3, fuzz F3 |
| Zero-weight pauses emission | unit I1-I4, fuzz F8, invariant all |
| Exhaustion capped at funded | unit J1-J4, fuzz F1, F7 |
| No retroaccrual | unit C8, D5, I3 |
| Historical fees preserved through deactivation | unit D6-D9, fuzz F4, invariant INV-7 |
| Historical fees preserved through rate change | unit K1-K2, fuzz F3 |
| Forced-transfer safe | unit B6 |

---

## Integration Script

`contracts/script/IntegrationC06.s.sol` performs 11 live-chain verification steps:

1. Deploy RewardVault with MAX emission rate
2. Fund with 15M PW; verify all accounting views
3. Register 5 dev recipients; verify no retro-accrual
4. Verify `claimable == 0` in same block
5. Verify all accounting invariants at t=0
6. Spot-check annual emission math (≤ 3M PW)
7. Reduce rate to 2M/year; verify increase is rejected
8. Reduce rate to zero
9. Deactivate/activate cycle; verify weight tracking
10. Weight update; verify totalEligibleWeight
11. Final conservation and rate invariants

**Note:** Live-chain integration does not use `vm.warp`; time-dependent emission accrual is verified through the unit and fuzz suites.

---

## Locked Decisions (carry to C07)

- RewardVault does **not** call `PrimeWaveValidatorRegistry`; admin manages recipients directly in Phase 1
- `totalFunded` is the immutable accounting anchor; never use `address(this).balance` in emission math
- Rate is monotone-decreasing; the constructor-set rate is the permanent ceiling
- Zero-weight periods silently pause emission; no special "unallocated" bucket
- Claim caller must be `recipients[id].rewardAddress`; no admin override for claims

---

## What PW-C07 Should Address

- Wiring `PrimeWaveValidatorRegistry` as the admin of `RewardVault` (permissioned lifecycle automation)
- Governance over `setEmissionRate` (multisig or timelock)
- Upgradeability / migration path for the 15M PW allocation
- On-chain uptime integration when P-Chain data becomes accessible via Warp
