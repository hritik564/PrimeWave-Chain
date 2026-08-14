---
name: PrimeWave Chain C09
description: Phase-2 PoS + PrimeWaveStakingManager sprint — implementation decisions, blockers resolved, test count 574/574
---

## Sprint Result
C09 COMPLETE. 574/574 tests pass (535 baseline + 39 new). Date: 2026-08-14.

## Key Architecture Decisions

**Reward formula:** `rate × stakingDuration × clamp(uptimeSeconds, 0, validationDuration) / validationDuration`, capped at vault available reserve. Stake amount accepted by IRewardCalculator interface but intentionally unused — PrimeWave is rate-based not stake-proportional.

**ETH-native staking:** `_lock()` returns `msg.value` (ETH held in SM contract). `_unlock()` sends ETH back via `.call{value}`. No ERC-20.

**RewardVault.distribute():** Called by `PrimeWaveStakingManager._reward()`. Gated to `stakingManager` (one-time admin setter). Increments both `totalEmitted` AND `totalClaimed` together (PoS rewards bypass epoch accrual path).

**Delegation disabled:** `maximumStakeMultiplier = 1`.

**Unbonding:** `minimumStakeDuration = 1_209_600` (14 days).

## Pitfalls — Must Know for C10+

**Zero-reward removal:** `StakingManager.initiateValidatorRemoval` reverts `ValidatorIneligibleForRewards` when computed reward = 0. Use `forceInitiateValidatorRemoval` for validators with no uptime proof. This is Avalanche upstream behaviour, not a bug.

**vm.prank consumed by argument evaluation:** `vm.prank(x); foo.bar(baz.qux())` — `qux()` fires first and consumes the prank; `bar()` then has wrong msg.sender. Always capture arguments into local variables BEFORE `vm.prank`.

**INITIAL_RATE as constant:** `3_000_000 ether / (365*24*60*60)` is not an exact integer (GCD=48000 leaves remainder). Solidity compile-time evaluator keeps it as rational_const and refuses uint256 assignment. Use a non-constant state variable set in setUp() via `uint256(3_000_000 * 1 ether) / 31_536_000` (runtime floor division).

**IWarpMessenger calldata return:** Real precompile returns `WarpMessage calldata`; mock must use `memory`. Changed local copy of IWarpMessenger.sol — do not reset to calldata.

**OZ upgradeable v5.1.0 clone:** Must be explicitly cloned (`git clone --depth 1 --branch v5.1.0`). Previous session left directory empty (silent failure). Always verify `ls contracts/lib/openzeppelin-contracts-upgradeable/contracts/` before build.

## Test Infrastructure Added (C09)

- `MockAvalancheValidatorManager` — full IValidatorManager without Warp; sequential msgIndex queues
- `MockWarpMessenger` — etched at `0x0200…0005`; `setUptimeResponse()` configures uptime Warp messages
- `StakingManagerUnit.t.sol` (27 tests), `StakingManagerFuzz.t.sol` (6 fuzz), `IntegrationC09.t.sol` (6 integration)

## Files Modified (production)

- `contracts/src/RewardVault.sol` — added distribute(), setStakingManager(), stakingManager field
- `contracts/src/PrimeWaveStakingManager.sol` — new
- `contracts/src/PrimeWaveRewardCalculator.sol` — new
- `foundry.toml` — remappings for OZ v5.1.0 and Avalanche ICM interfaces
