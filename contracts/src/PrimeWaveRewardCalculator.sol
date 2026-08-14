// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// ============================================================
// PrimeWaveRewardCalculator  --  PW-C09
// ============================================================
//
// PURPOSE:
//   Implements IRewardCalculator for PrimeWaveStakingManager.
//   Translates Avalanche's lump-sum-at-unbonding reward model into
//   PrimeWave's continuous-emission vault semantics.
//
// REWARD FORMULA:
//   grossReward = emissionRate × stakingDuration × uptimeFraction
//   where uptimeFraction = uptimeSeconds / (stakingEndTime - validatorStartTime)
//
//   Result is capped at the vault's remaining un-emitted reserve to
//   prevent insolvency.
//
// KNOWN LIMITATION (documented in PW-C09-AVALANCHE-STAKING-COMPATIBILITY.md §8):
//   Two validators staking simultaneously each earn the full per-second
//   rate for their period (not split proportionally). The vault's
//   `available` balance is the only shared constraint. A global
//   proportional emission index would require staking-weight tracking
//   not exposed by StakingManager's call-time API.
//
// ENVIRONMENT: LOCAL DEVELOPMENT  --  NOT FOR MAINNET
// ============================================================

import {IRewardCalculator} from "validator-manager/interfaces/IRewardCalculator.sol";
import {RewardVault} from "./RewardVault.sol";

contract PrimeWaveRewardCalculator is IRewardCalculator {

    // ── State ────────────────────────────────────────────────────────────────

    /// @notice The RewardVault whose emission rate governs staking rewards.
    RewardVault public immutable rewardVault;

    // ── Events ────────────────────────────────────────────────────────────────

    /// @notice Emitted during reward calculation (view-safe simulation only for tests).

    // ── Constructor ───────────────────────────────────────────────────────────

    /// @param _rewardVault The RewardVault whose emissionRatePerSecond governs rewards.
    constructor(RewardVault _rewardVault) {
        require(address(_rewardVault) != address(0), "PRC: zero vault");
        rewardVault = _rewardVault;
    }

    // ── IRewardCalculator ─────────────────────────────────────────────────────

    /// @notice Calculate the staking reward for a validator.
    ///
    /// @param stakeAmount       The amount of PW staked (wei). Not used in the rate model
    ///                          but preserved for interface compatibility and future stake-
    ///                          proportional extensions.
    /// @param validatorStartTime The timestamp when the validator started (used for uptime
    ///                          fraction denominator: stakingEndTime - validatorStartTime).
    /// @param stakingStartTime  The timestamp when staking began (may differ from
    ///                          validatorStartTime for delegators; equals it for direct stake).
    /// @param stakingEndTime    The timestamp when staking ended.
    /// @param uptimeSeconds     The total seconds the validator was live during the validation
    ///                          period. Sourced from an uptime proof Warp message.
    ///
    /// @return reward           The PW reward in wei, capped at vault's available reserve.
    function calculateReward(
        uint256 stakeAmount,
        uint64  validatorStartTime,
        uint64  stakingStartTime,
        uint64  stakingEndTime,
        uint64  uptimeSeconds
    ) external view override returns (uint256) {
        // Suppress unused-parameter warning (stakeAmount is preserved for future proportional model)
        stakeAmount;

        // No duration → no reward
        uint64 stakingDuration = stakingEndTime > stakingStartTime
            ? stakingEndTime - stakingStartTime : 0;
        if (stakingDuration == 0) return 0;

        // Validation duration = total time this validator has been in the set
        uint64 validationDuration = stakingEndTime > validatorStartTime
            ? stakingEndTime - validatorStartTime : 0;
        if (validationDuration == 0) return 0;

        // Clamp uptimeSeconds to validation duration (safety: uptime proof can't exceed wall clock)
        if (uptimeSeconds > validationDuration) uptimeSeconds = validationDuration;

        // Gross reward = rate × stakingDuration × uptimeFraction
        //   = rate × stakingDuration × uptimeSeconds / validationDuration
        //
        // Multiply before divide to preserve precision. Overflow analysis:
        //   rate     ≤ MAX_RATE_PER_SECOND = 95,129,375,951,293,760 ≈ 9.5e16 (fits uint256)
        //   duration ≤ ~1e8 s  (3+ years)
        //   product  ≤ 9.5e16 × 1e8 × 1e8 = 9.5e32 — well within uint256 range.
        uint256 rate = rewardVault.emissionRatePerSecond();
        uint256 grossReward = (rate * uint256(stakingDuration) * uint256(uptimeSeconds))
                              / uint256(validationDuration);

        if (grossReward == 0) return 0;

        // Cap at vault's remaining available reserve
        uint256 totalFunded  = rewardVault.totalFunded();
        uint256 totalEmitted = rewardVault.totalEmitted();
        uint256 available    = totalFunded > totalEmitted ? totalFunded - totalEmitted : 0;

        return grossReward < available ? grossReward : available;
    }
}
