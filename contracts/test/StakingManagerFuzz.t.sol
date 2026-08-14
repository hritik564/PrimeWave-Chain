// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// ============================================================
// StakingManagerFuzz.t.sol  --  PW-C09
// ============================================================
//
// Fuzz + invariant tests covering:
//   F1) calculateReward — arbitrary durations and uptimes
//   F2) distribute — arbitrary amounts preserve invariants
//   F3) Multiple validators — vault solvency under concurrent staking
//   F4) Rate exhaustion — vault can never over-pay
// ============================================================

import {Test} from "forge-std/Test.sol";
import {RewardVault} from "../src/RewardVault.sol";
import {PrimeWaveRewardCalculator} from "../src/PrimeWaveRewardCalculator.sol";
import {PrimeWaveStakingManager} from "../src/PrimeWaveStakingManager.sol";
import {MockAvalancheValidatorManager} from "./MockAvalancheValidatorManager.sol";
import {StakingManagerSettings} from "validator-manager/interfaces/IStakingManager.sol";
import {IRewardCalculator} from "validator-manager/interfaces/IRewardCalculator.sol";
import {IValidatorManager} from "validator-manager/interfaces/IValidatorManager.sol";
import {PChainOwner} from "validator-manager/interfaces/IACP99Manager.sol";

contract StakingManagerFuzzTest is Test {

    // ── Constants ─────────────────────────────────────────────────────────────

    uint64  constant CHURN_PERIOD       = 3600;
    bytes32 constant SUBNET_ID          = bytes32(uint256(1));
    bytes32 constant UPTIME_BLOCKCHAIN_ID = bytes32(uint256(2));
    // Set in setUp() from vault.MAX_RATE_PER_SECOND() to avoid rational-constant compile error.
    uint256 INITIAL_RATE;
    uint256 constant VAULT_FUND   = 15_000_000 ether;
    uint256 constant MIN_STAKE    = 1_000 ether;
    uint256 constant MAX_STAKE    = 3_000_000 ether;
    uint64  constant MIN_STAKE_DURATION = 14 days;

    // ── Actors ────────────────────────────────────────────────────────────────

    address admin     = makeAddr("admin");
    address rewarded  = makeAddr("rewarded");

    // ── Contracts ─────────────────────────────────────────────────────────────

    RewardVault                   vault;
    PrimeWaveRewardCalculator     calc;
    MockAvalancheValidatorManager mockVM;
    PrimeWaveStakingManager       sm;

    // ── Setup ─────────────────────────────────────────────────────────────────

    function setUp() public {
        // Compute MAX_RATE_PER_SECOND at runtime (matches RewardVault compile-time constant exactly)
        INITIAL_RATE = uint256(3_000_000 * 1 ether) / 31_536_000;

        vm.startPrank(admin);

        vault = new RewardVault(admin, INITIAL_RATE);
        vm.deal(admin, VAULT_FUND + 10 ether);
        vault.fund{value: VAULT_FUND}();

        mockVM = new MockAvalancheValidatorManager(SUBNET_ID, CHURN_PERIOD);
        calc   = new PrimeWaveRewardCalculator(vault);

        sm = new PrimeWaveStakingManager();
        sm.initialize(
            StakingManagerSettings({
                manager:                  IValidatorManager(address(mockVM)),
                minimumStakeAmount:       MIN_STAKE,
                maximumStakeAmount:       MAX_STAKE,
                minimumStakeDuration:     MIN_STAKE_DURATION,
                minimumDelegationFeeBips: 100,
                maximumStakeMultiplier:   1,
                weightToValueFactor:      1 ether,
                rewardCalculator:         IRewardCalculator(address(calc)),
                uptimeBlockchainID:       UPTIME_BLOCKCHAIN_ID
            }),
            vault
        );
        vault.setStakingManager(address(sm));

        vm.stopPrank();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // F1) calculateReward — fuzz durations and uptimes
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev testFuzz_F1: reward never exceeds rate × stakingDuration (gross)
    ///      and never exceeds vault available balance.
    function testFuzz_F1_rewardBounds(
        uint256 stakeAmount,
        uint64  validatorStartTime,
        uint64  stakingDurationDays,
        uint64  uptimePct          // 0–100
    ) public view {
        // Bound inputs
        stakeAmount          = bound(stakeAmount, 0, 1_000_000 ether);
        stakingDurationDays  = uint64(bound(stakingDurationDays, 0, 3650));
        uptimePct            = uint64(bound(uptimePct, 0, 100));
        validatorStartTime   = uint64(bound(validatorStartTime, 1, 1_000_000));

        uint64 stakingDuration  = stakingDurationDays * 1 days;
        uint64 stakingEndTime   = validatorStartTime + stakingDuration;
        uint64 uptimeSeconds    = (stakingDuration * uptimePct) / 100;

        uint256 reward = calc.calculateReward(
            stakeAmount,
            validatorStartTime,
            validatorStartTime,
            stakingEndTime,
            uptimeSeconds
        );

        // Reward must not exceed gross (rate × duration)
        uint256 gross = INITIAL_RATE * uint256(stakingDuration);
        assertLe(reward, gross, "F1: reward <= gross");

        // Reward must not exceed vault available
        uint256 available = vault.totalFunded() - vault.totalEmitted();
        assertLe(reward, available, "F1: reward <= available");
    }

    /// @dev testFuzz_F1b: reward is monotonically non-decreasing in uptimeSeconds
    function testFuzz_F1b_rewardMonotonicInUptime(
        uint64 stakingDurationDays,
        uint64 uptime1Pct,
        uint64 uptime2Pct
    ) public view {
        stakingDurationDays = uint64(bound(stakingDurationDays, 1, 365));
        uptime1Pct          = uint64(bound(uptime1Pct,  0, 100));
        uptime2Pct          = uint64(bound(uptime2Pct,  uptime1Pct, 100));

        uint64 t0           = 1000;
        uint64 t1           = t0 + stakingDurationDays * 1 days;
        uint64 duration     = t1 - t0;
        uint64 up1          = (duration * uptime1Pct) / 100;
        uint64 up2          = (duration * uptime2Pct) / 100;

        uint256 r1 = calc.calculateReward(1 ether, t0, t0, t1, up1);
        uint256 r2 = calc.calculateReward(1 ether, t0, t0, t1, up2);

        // Higher uptime → higher or equal reward
        assertLe(r1, r2, "F1b: reward monotonic in uptime");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // F2) distribute — arbitrary amounts preserve invariants
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev testFuzz_F2: distribute arbitrary amount preserves all vault invariants
    function testFuzz_F2_distributeInvariants(uint256 amount) public {
        uint256 available = vault.totalFunded() - vault.totalEmitted();
        amount = bound(amount, 1, available);

        uint256 fundedBefore  = vault.totalFunded();
        uint256 emittedBefore = vault.totalEmitted();
        uint256 claimedBefore = vault.totalClaimed();

        vm.prank(address(sm));
        vault.distribute(rewarded, amount);

        // Invariant 1: totalFunded unchanged (no minting)
        assertEq(vault.totalFunded(), fundedBefore, "F2: no minting");

        // Invariant 2: totalEmitted <= totalFunded
        assertLe(vault.totalEmitted(), vault.totalFunded(), "F2: inv2");

        // Invariant 3: totalClaimed <= totalEmitted
        assertLe(vault.totalClaimed(), vault.totalEmitted(), "F2: inv3");

        // Invariant 5: balance == totalFunded - totalClaimed
        assertEq(address(vault).balance, vault.totalFunded() - vault.totalClaimed(), "F2: inv5");

        // Delta checks
        assertEq(vault.totalEmitted(), emittedBefore + amount, "F2: emitted delta");
        assertEq(vault.totalClaimed(), claimedBefore + amount, "F2: claimed delta");
    }

    /// @dev testFuzz_F2b: distribute never pays more than funded
    function testFuzz_F2b_cannotOverdraw(uint256 excess) public {
        uint256 available = vault.totalFunded() - vault.totalEmitted();
        excess = bound(excess, 1, type(uint256).max - available);
        uint256 tooMuch = available + excess;

        vm.prank(address(sm));
        vm.expectRevert("RV: insufficient reserve");
        vault.distribute(rewarded, tooMuch);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // F3) Multiple sequential distributions — vault solvency
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev testFuzz_F3: N sequential distributions remain solvent
    function testFuzz_F3_multipleDistributionsSolvent(uint8 n, uint256 seed) public {
        n = uint8(bound(n, 1, 20));

        for (uint256 i = 0; i < n; i++) {
            uint256 available = vault.totalFunded() - vault.totalEmitted();
            if (available == 0) break;

            // Random amount between 1 and available
            uint256 amount = bound(
                uint256(keccak256(abi.encode(seed, i))),
                1,
                available
            );

            vm.prank(address(sm));
            vault.distribute(rewarded, amount);
        }

        // After all distributions, invariants must hold
        assertLe(vault.totalEmitted(), vault.totalFunded(), "F3: inv2 after N distributions");
        assertLe(vault.totalClaimed(), vault.totalEmitted(), "F3: inv3 after N distributions");
        assertEq(address(vault).balance, vault.totalFunded() - vault.totalClaimed(), "F3: inv5");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // F4) Supply invariant — total out never exceeds total in
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev testFuzz_F4: total PW that leaves vault <= total PW funded
    function testFuzz_F4_supplyCapHeld(uint256[5] memory amounts) public {
        uint256 totalOut = 0;

        for (uint256 i = 0; i < 5; i++) {
            uint256 available = vault.totalFunded() - vault.totalEmitted();
            if (available == 0) break;

            uint256 amount = bound(amounts[i], 0, available);
            if (amount == 0) continue;

            vm.prank(address(sm));
            vault.distribute(rewarded, amount);
            totalOut += amount;
        }

        // Total PW that left the vault must not exceed what was funded
        assertLe(totalOut, VAULT_FUND, "F4: total out <= total funded");
        assertLe(vault.totalClaimed(), vault.totalFunded(), "F4: claimed <= funded");
    }
}
