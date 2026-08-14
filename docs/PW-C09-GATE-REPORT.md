# PW-C09 Final Dependency + Architecture Gate Report

Date: 2026-08-14  
Gate trigger: Manual final gate before locking C09.

---

## 1. OpenZeppelin Dependency

### Finding

The primary (unversioned) OZ remapping was pointing to the v5.1.0 library that Avalanche StakingManager requires, instead of the project-locked v5.6.1.

**Root cause:** C09 added the v5.1.0 library to `contracts/lib/openzeppelin-contracts/` and `contracts/lib/openzeppelin-contracts-upgradeable/` during implementation. The primary remappings `@openzeppelin/contracts/` and `@openzeppelin/contracts-upgradeable/` were left pointing at those v5.1.0 paths.

**Additional context:** No pre-existing production contract in `contracts/src/` imports OZ at all — the contracts for C00–C08 are self-contained Solidity with no external imports. The version mismatch had zero functional impact on compiled artifacts or test results. Nevertheless, the locked dependency must be honoured.

### Correction Applied

Two additional OZ libraries were cloned:

| Library | Version | Path |
|---|---|---|
| `openzeppelin-contracts` | **v5.6.1** | `contracts/lib/openzeppelin-contracts-v561/` |
| `openzeppelin-contracts-upgradeable` | **v5.6.1** | `contracts/lib/openzeppelin-contracts-upgradeable-v561/` |

`foundry.toml` remappings updated:

```toml
# Primary (unversioned) → v5.6.1: the project-locked dependency.
"@openzeppelin/contracts/=contracts/lib/openzeppelin-contracts-v561/contracts/"
"@openzeppelin/contracts-upgradeable/=contracts/lib/openzeppelin-contracts-upgradeable-v561/contracts/"

# Versioned aliases → v5.1.0: required by Avalanche StakingManager.sol.
"@openzeppelin/contracts@5.1.0/=contracts/lib/openzeppelin-contracts/contracts/"
"@openzeppelin/contracts-upgradeable@5.1.0/=contracts/lib/openzeppelin-contracts-upgradeable/contracts/"
```

### Exact OpenZeppelin Version in Use

| Remapping | Library version | Used by |
|---|---|---|
| `@openzeppelin/contracts/` | **v5.6.1** | Future OZ imports (no current production user) |
| `@openzeppelin/contracts-upgradeable/` | **v5.6.1** | Future OZ imports (no current production user) |
| `@openzeppelin/contracts@5.1.0/` | v5.1.0 | `contracts/lib/icm-contracts/.../StakingManager.sol` |
| `@openzeppelin/contracts-upgradeable@5.1.0/` | v5.1.0 | `contracts/lib/icm-contracts/.../StakingManager.sol` |

---

## 2. Avalanche Dependency Versions

| Component | Version / Source |
|---|---|
| `icm-contracts` (local copy) | `ava-labs/icm-services` tag `icm-relayer-v1.7.5` |
| Files copied: `StakingManager.sol`, `ValidatorMessages.sol`, interfaces, `IWarpMessenger.sol`, `ICMInitializable.sol` | Exact tag checkout |
| OZ v5.1.0 (StakingManager dependency) | `openzeppelin-contracts@v5.1.0`, `openzeppelin-contracts-upgradeable@v5.1.0` |

---

## 3. forceInitiateValidatorRemoval — Production vs. Test Usage

### Verdict: CLEAN — production code does NOT use the forced removal path.

| Location | Uses `initiateValidatorRemoval` | Uses `forceInitiateValidatorRemoval` |
|---|---|---|
| `contracts/src/PrimeWaveStakingManager.sol` | doc comment only | **NONE** |
| `contracts/src/*.sol` (all other production files) | 0 | **NONE** |
| `contracts/test/StakingManagerUnit.t.sol` | 4 (normal removal with uptime) | 2 (zero-reward forced removal) |
| `contracts/test/IntegrationC09.t.sol` | 5 (normal removal with uptime) | 1 (zero-reward forced removal) |
| `contracts/test/StakingManagerInvariant.t.sol` | 0 | 2 (conservation invariant tests) |
| `contracts/lib/icm-contracts/` | interface + implementation (library) | interface + implementation (library) |

**Why tests use `forceInitiateValidatorRemoval`:** Avalanche upstream behavior — `initiateValidatorRemoval` reverts with `ValidatorIneligibleForRewards` when the computed reward is 0. Tests that intentionally demonstrate zero-reward removal (e.g. no uptime proof submitted) MUST use the force variant. `forceInitiateValidatorRemoval` is the correct mechanism for this scenario, not a security bypass — it exists specifically to allow removal regardless of reward eligibility.

**Security note:** The forced removal path does NOT bypass staking security rules. It still:
- Requires `msg.sender == validator owner`
- Enforces the 14-day minimum stake duration
- Goes through `MockAvalancheValidatorManager.initiateValidatorRemoval` (the authoritative ValidatorManager)
- The only thing it bypasses is the revert when reward = 0.

---

## 4. C09 Invariant Tests

### All 12 required gate invariants are now implemented and passing.

| Gate Invariant | Status | Test file | Test(s) |
|---|---|---|---|
| INV-1: Total supply never increases | ✅ IMPLEMENTED | StakingManagerFuzz.t.sol | `testFuzz_F2_distributeInvariants` (totalFunded unchanged) |
| INV-2: Stake conservation | ✅ IMPLEMENTED | StakingManagerInvariant.t.sol | `test_INV2_*` × 2, `testFuzz_INV2_stakeAlwaysReturned` × 256 runs |
| INV-3: Withdrawals <= deposits | ✅ IMPLEMENTED | StakingManagerFuzz.t.sol | `testFuzz_F2b_cannotOverdraw` × 256 runs |
| INV-4: Rewards <= RewardVault funding | ✅ IMPLEMENTED | StakingManagerFuzz.t.sol | `testFuzz_F1_rewardBounds` × 256 runs |
| INV-5: Annual rewards <= 3M PW | ✅ IMPLEMENTED | StakingManagerInvariant.t.sol | `test_INV5_annualEmissionCapEnforced`, `testFuzz_INV5_*` × 256 runs |
| INV-6: Total rewards <= 15M PW | ✅ IMPLEMENTED | StakingManagerFuzz.t.sol + StakingManagerInvariant.t.sol | `testFuzz_F4_supplyCapHeld`, `testFuzz_INV6_*` × 256 runs each |
| INV-7: Unauthorized reward claim impossible | ✅ IMPLEMENTED | StakingManagerUnit.t.sol | `test_distribute_revertsIfNotStakingManager` |
| INV-8: Unauthorized withdrawal impossible | ✅ IMPLEMENTED | StakingManagerUnit.t.sol | `test_security_onlyOwnerCanInitiateRemoval` |
| INV-9: 14-day unbonding cannot be bypassed | ✅ IMPLEMENTED | StakingManagerUnit.t.sol | `test_unbonding_earlyRemovalReverts` |
| INV-10: ValidatorManager remains authoritative | ✅ IMPLEMENTED | StakingManagerInvariant.t.sol | `test_INV10_*` × 2 |
| INV-11: FeeDistributor remains independent | ✅ IMPLEMENTED | StakingManagerInvariant.t.sol | `test_INV11_feeDistributorUnaffectedByStaking` |
| INV-12: Governance boundaries remain intact | ✅ IMPLEMENTED | StakingManagerInvariant.t.sol | `test_INV12_*` × 3 |

---

## 5. C00–C08 Regression Result

| Sprint | Tests | Result |
|---|---|---|
| C00–C08 baseline | 535 | ✅ ALL PASS |

---

## 6. C09 Total Test Count

| File | Tests |
|---|---|
| `StakingManagerUnit.t.sol` | 27 |
| `StakingManagerFuzz.t.sol` | 6 (256 runs each) |
| `IntegrationC09.t.sol` | 6 |
| `StakingManagerInvariant.t.sol` | 12 (mix of unit and 256-run fuzz) |
| **C09 total** | **51** |
| **Grand total (C00–C09)** | **586** |

---

## 7. Unresolved Limitations

| Limitation | Description |
|---|---|
| Sub-ether stake dust | `valueToWeight()` uses integer division. Stake amounts that are not exact multiples of `weightToValueFactor` (1 ether) have sub-ether wei truncated and retained in the SM contract. This is inherent to Avalanche's weight model and documented in the staking spec. For PrimeWave, the minimum stake is 1,000 ether and is always set in whole-ether increments, so dust is zero in normal operation. |
| Warp precompile mock | `MockWarpMessenger` is etched at the precompile address in tests. The actual Avalanche Warp verification (cryptographic proof, BLS threshold, etc.) is not tested — it is Avalanche infrastructure outside the scope of this sprint. |
| Live-chain testing | C09 is unit/integration tested only. Network-level testing (actual P-Chain round-trip, real Warp messages) requires a live Fuji or local Avalanche testnet — outside the sprint boundary. |
| Delegations disabled | `maximumStakeMultiplier = 1` disables all delegation. Delegator paths in StakingManager are not exercised. |

---

## 8. Confirmation: No Native PW Minting

- `RewardVault` comment invariant 1: "NO MINTING. Rewards come ONLY from pre-funded PW. No NativeMinter. No mint(). No inflation. Total PW supply never increases."
- `PrimeWaveStakingManager._reward()` calls `rewardVault.distribute()` which transfers pre-funded ETH — no minting opcode or NativeMinter interface is called anywhere.
- Confirmed by fuzz invariant INV-1 (`testFuzz_F2_distributeInvariants`): `vault.totalFunded()` is immutable through all staking operations.

---

## 9. Confirmation: RewardVault Is Sole Staking Reward Source

- `PrimeWaveStakingManager._reward(address recipient, uint256 amount)` has one codepath: `rewardVault.distribute(recipient, amount)`.
- The `distribute()` function on `RewardVault` enforces `require(msg.sender == stakingManager)` and transfers from the vault's own ETH balance (pre-funded 15,000,000 PW).
- No other ETH source exists for staking rewards. The SM contract's own ETH balance holds ONLY validator stakes, which are returned via `_unlock()` to the original staker, never to reward recipients.

---

## 10. Confirmation: 14-Day Unbonding

- `minimumStakeDuration = 1_209_600` (= 14 × 86,400 seconds) set in `StakingManagerSettings` during `PrimeWaveStakingManager.initialize()`.
- Enforced by `StakingManager._initiatePoSValidatorRemoval()`: `if (validator.endTime < validator.startTime + minStakeDuration) revert MinStakeDurationNotPassed(...)`.
- Both `initiateValidatorRemoval` AND `forceInitiateValidatorRemoval` go through `_initiatePoSValidatorRemoval` — the unbonding check cannot be bypassed.
- Confirmed by unit test `test_unbonding_earlyRemovalReverts` (gate INV-9).

---

## Gate Verdict

All five gate checks pass:

| Check | Result |
|---|---|
| OZ locked version (v5.6.1) restored as primary remapping | ✅ PASS |
| `forceInitiateValidatorRemoval` not used in production | ✅ PASS |
| All 12 C09 invariants implemented and passing | ✅ PASS |
| All required docs present | ✅ PASS |
| C00–C08 regression clean | ✅ PASS |

**C09 is ready for final lock. Awaiting approval.**
