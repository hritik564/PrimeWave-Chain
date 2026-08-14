// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// ============================================================
// C10TimestampUnbonding.t.sol  --  PW-C10
// ============================================================
//
// Timestamp attacks + unbonding attacks + principal conservation.
// Covers C10 brief sections 13, 14, 15.
//
// IMPORTANT: via_ir = true is enabled.
// NEVER use vm.warp(block.timestamp + N) inside loops.
// All timestamps are pre-computed absolute values.
// ============================================================

import {Test, Vm} from "forge-std/Test.sol";
import {RewardVault} from "../src/RewardVault.sol";
import {PrimeWaveRewardCalculator} from "../src/PrimeWaveRewardCalculator.sol";
import {PrimeWaveStakingManager} from "../src/PrimeWaveStakingManager.sol";
import {MockAvalancheValidatorManager} from "./MockAvalancheValidatorManager.sol";
import {MockWarpMessenger} from "./MockWarpMessenger.sol";
import {StakingManagerSettings} from "validator-manager/interfaces/IStakingManager.sol";
import {IRewardCalculator} from "validator-manager/interfaces/IRewardCalculator.sol";
import {IValidatorManager} from "validator-manager/interfaces/IValidatorManager.sol";
import {PChainOwner} from "validator-manager/interfaces/IACP99Manager.sol";

contract C10TimestampUnbondingTest is Test {

    address constant WARP_PRECOMPILE      = 0x0200000000000000000000000000000000000005;
    uint64  constant CHURN_PERIOD         = 3600;
    bytes32 constant SUBNET_ID            = bytes32(uint256(1));
    bytes32 constant UPTIME_BLOCKCHAIN_ID = bytes32(uint256(2));
    uint64  constant MIN_STAKE_DURATION   = 14 days;
    uint256 constant MIN_STAKE            = 1_000 ether;
    uint256 constant MAX_STAKE            = 3_000_000 ether;
    uint256 constant VAULT_FUND           = 15_000_000 ether;

    address admin   = makeAddr("admin");
    address staker1 = makeAddr("staker1");
    address staker2 = makeAddr("staker2");
    address reward1 = makeAddr("reward1");

    RewardVault                   vault;
    PrimeWaveRewardCalculator     calc;
    MockAvalancheValidatorManager mockVM;
    PrimeWaveStakingManager       sm;
    MockWarpMessenger             warpMock;

    uint256 INITIAL_RATE;

    // Absolute base timestamp for all tests (avoids block.timestamp + N pattern)
    uint64 constant BASE_TS = 1_800_000_000; // 2027-01-15 approx

    function setUp() public {
        INITIAL_RATE = uint256(3_000_000 * 1 ether) / 31_536_000;

        vm.warp(BASE_TS);

        vm.startPrank(admin);
        vault = new RewardVault(admin, INITIAL_RATE);
        vm.deal(admin, VAULT_FUND + 100 ether);
        vault.fund{value: VAULT_FUND}();

        mockVM = new MockAvalancheValidatorManager(SUBNET_ID, CHURN_PERIOD);
        calc   = new PrimeWaveRewardCalculator(vault);
        sm     = new PrimeWaveStakingManager();
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

        warpMock = new MockWarpMessenger();
        vm.etch(WARP_PRECOMPILE, address(warpMock).code);
        warpMock = MockWarpMessenger(payable(WARP_PRECOMPILE));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TU-01: 1 second before 14-day minimum → REVERT
    // (Section 14 — unbonding 1 second early)
    // ─────────────────────────────────────────────────────────────────────────

    function test_TU01_unbondOneSecondEarly_reverts() public {
        uint256 stake = 5_000 ether;
        vm.deal(staker1, stake);

        uint64 t0 = uint64(block.timestamp);
        uint64 t_early = t0 + MIN_STAKE_DURATION - 1; // 1 second early

        bytes32 vid = _register(staker1, stake, reward1, 1);
        sm.completeValidatorRegistration(0);

        vm.warp(t_early);

        // Cannot initiate removal 1 second before minimum
        vm.prank(staker1);
        vm.expectRevert();
        sm.initiateValidatorRemoval(vid, false, 0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TU-02: Exactly at 14-day boundary → PASS
    // (Section 14 — withdraw exactly at 14 days)
    // ─────────────────────────────────────────────────────────────────────────

    function test_TU02_unbondAtExactBoundary_succeeds() public {
        uint256 stake = 5_000 ether;
        vm.deal(staker1, stake);

        uint64 t0  = uint64(block.timestamp);
        uint64 t14 = t0 + MIN_STAKE_DURATION; // exactly 14 days

        bytes32 vid = _register(staker1, stake, reward1, 2);
        sm.completeValidatorRegistration(0);

        vm.warp(t14);

        // No uptime proof → must use force
        vm.prank(staker1);
        sm.forceInitiateValidatorRemoval(vid, false, 0);

        uint256 balBefore = staker1.balance;
        sm.completeValidatorRemoval(0);

        assertEq(staker1.balance - balBefore, stake, "stake returned at exact 14-day boundary");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TU-03: 1 second after 14-day boundary → PASS
    // (Section 14 — withdraw 1 second after)
    // ─────────────────────────────────────────────────────────────────────────

    function test_TU03_unbondOneSecondAfterBoundary_succeeds() public {
        uint256 stake = 5_000 ether;
        vm.deal(staker1, stake);

        uint64 t0    = uint64(block.timestamp);
        uint64 t14p1 = t0 + MIN_STAKE_DURATION + 1;

        bytes32 vid = _register(staker1, stake, reward1, 3);
        sm.completeValidatorRegistration(0);

        vm.warp(t14p1);

        vm.prank(staker1);
        sm.forceInitiateValidatorRemoval(vid, false, 0);

        uint256 balBefore = staker1.balance;
        sm.completeValidatorRemoval(0);

        assertEq(staker1.balance - balBefore, stake, "stake returned 1s after boundary");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TU-04: Withdraw immediately (t=0) → REVERT
    // (Section 14 — withdraw immediately)
    // ─────────────────────────────────────────────────────────────────────────

    function test_TU04_withdrawImmediately_reverts() public {
        uint256 stake = 5_000 ether;
        vm.deal(staker1, stake);

        bytes32 vid = _register(staker1, stake, reward1, 4);
        sm.completeValidatorRegistration(0);

        // No warp — still at registration timestamp
        vm.prank(staker1);
        vm.expectRevert();
        sm.initiateValidatorRemoval(vid, false, 0);

        vm.prank(staker1);
        vm.expectRevert();
        sm.forceInitiateValidatorRemoval(vid, false, 0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TU-05: Duplicate withdrawal → REVERT
    // (Section 14 — duplicate withdrawal)
    // ─────────────────────────────────────────────────────────────────────────

    function test_TU05_duplicateWithdrawal_reverts() public {
        uint256 stake = 5_000 ether;
        vm.deal(staker1, stake);

        uint64 t0 = uint64(block.timestamp);
        uint64 t1 = t0 + MIN_STAKE_DURATION + 1;

        bytes32 vid = _register(staker1, stake, reward1, 5);
        sm.completeValidatorRegistration(0);

        vm.warp(t1);

        vm.prank(staker1);
        sm.forceInitiateValidatorRemoval(vid, false, 0);
        sm.completeValidatorRemoval(0);

        // Try to complete removal again
        vm.expectRevert();
        sm.completeValidatorRemoval(0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TU-06: Withdrawal by unauthorized party → REVERT
    // (Section 14 — withdraw from another participant)
    // ─────────────────────────────────────────────────────────────────────────

    function test_TU06_withdrawByUnauthorized_reverts() public {
        uint256 stake = 5_000 ether;
        vm.deal(staker1, stake);

        uint64 t0 = uint64(block.timestamp);
        uint64 t1 = t0 + MIN_STAKE_DURATION + 1;

        bytes32 vid = _register(staker1, stake, reward1, 6);
        sm.completeValidatorRegistration(0);

        vm.warp(t1);

        // Attacker tries to initiate removal for staker1's validator
        vm.prank(staker2);
        vm.expectRevert();
        sm.initiateValidatorRemoval(vid, false, 0);

        vm.prank(staker2);
        vm.expectRevert();
        sm.forceInitiateValidatorRemoval(vid, false, 0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TU-07: Timestamp attack — exact reward boundary (1 second before/after)
    // (Section 13 — exact reward boundary)
    // ─────────────────────────────────────────────────────────────────────────

    function test_TU07_rewardBoundaryOneSec_beforeAndAfter() public {
        uint256 stake = 10_000 ether;
        vm.deal(staker1, stake);
        vm.deal(staker2, stake);

        // Two validators: same start, different end timestamps (1 sec apart)
        uint64 t0        = uint64(block.timestamp);
        uint64 t_before  = t0 + 30 days - 1;
        uint64 t_after   = t0 + 30 days + 1;

        bytes32 v1 = _register(staker1, stake, reward1, 10);
        sm.completeValidatorRegistration(0);
        bytes32 v2 = _register(staker2, stake, makeAddr("r2"), 11);
        sm.completeValidatorRegistration(1);

        // v1: remove at 30 days - 1 second
        vm.warp(t_before);
        warpMock.setUptimeResponse(0, UPTIME_BLOCKCHAIN_ID, v1, uint64(t_before - t0));
        vm.prank(staker1); sm.submitUptimeProof(v1, 0);
        vm.prank(staker1); sm.initiateValidatorRemoval(v1, false, 0);
        sm.completeValidatorRemoval(0);

        uint256 reward1_29d = reward1.balance;
        uint256 expected1   = INITIAL_RATE * (t_before - t0);
        assertEq(reward1_29d, expected1, "reward for 30d-1s");

        // v2: remove at 30 days + 1 second
        vm.warp(t_after);
        warpMock.setUptimeResponse(1, UPTIME_BLOCKCHAIN_ID, v2, uint64(t_after - t0));
        vm.prank(staker2); sm.submitUptimeProof(v2, 1);
        vm.prank(staker2); sm.initiateValidatorRemoval(v2, false, 0);
        sm.completeValidatorRemoval(1);

        uint256 reward2_30d = makeAddr("r2").balance;
        uint256 expected2   = INITIAL_RATE * (t_after - t0);
        assertEq(reward2_30d, expected2, "reward for 30d+1s");

        assertGt(reward2_30d, reward1_29d, "more time = more reward");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TU-08: Year boundary — reward accrual crosses year boundary correctly
    // (Section 13 — year boundary)
    // ─────────────────────────────────────────────────────────────────────────

    function test_TU08_yearBoundary_rewardCorrect() public {
        uint256 stake = 50_000 ether;
        vm.deal(staker1, stake);

        // Start near end of year 1
        uint64 t0      = BASE_TS;
        uint64 t_cross = t0 + uint64(31_536_000); // exactly 1 year later

        bytes32 vid = _register(staker1, stake, reward1, 20);
        sm.completeValidatorRegistration(0);

        vm.warp(t_cross);

        warpMock.setUptimeResponse(0, UPTIME_BLOCKCHAIN_ID, vid, uint64(31_536_000));
        vm.prank(staker1); sm.submitUptimeProof(vid, 0);
        vm.prank(staker1); sm.initiateValidatorRemoval(vid, false, 0);
        sm.completeValidatorRemoval(0);

        uint256 reward = reward1.balance;
        // Exactly RATE * 1 year (floor)
        uint256 expectedReward = INITIAL_RATE * 31_536_000;
        assertEq(reward, expectedReward, "year-boundary reward exact");
        assertLe(reward, 3_000_000 ether, "within annual cap");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TU-09: 14-day exact boundary with uptime proof
    // (Section 13 — exact 14-day boundary)
    // ─────────────────────────────────────────────────────────────────────────

    function test_TU09_exactFourteenDayBoundary_withUptimeProof() public {
        uint256 stake = 8_000 ether;
        vm.deal(staker1, stake);

        uint64 t0  = uint64(block.timestamp);
        uint64 t14 = t0 + MIN_STAKE_DURATION;

        bytes32 vid = _register(staker1, stake, reward1, 30);
        sm.completeValidatorRegistration(0);

        vm.warp(t14);

        uint64 uptime = uint64(MIN_STAKE_DURATION);
        warpMock.setUptimeResponse(0, UPTIME_BLOCKCHAIN_ID, vid, uptime);
        vm.prank(staker1); sm.submitUptimeProof(vid, 0);
        vm.prank(staker1); sm.initiateValidatorRemoval(vid, false, 0);
        sm.completeValidatorRemoval(0);

        uint256 expectedReward = INITIAL_RATE * MIN_STAKE_DURATION;
        assertEq(reward1.balance, expectedReward, "14-day exact reward");
        assertEq(staker1.balance, stake, "stake returned");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TU-10: Principal conservation — 10 stake/unstake cycles
    // (Section 15 — principal conservation)
    // ─────────────────────────────────────────────────────────────────────────

    function test_TU10_principalConservation_tenCycles() public {
        uint256 stake = 3_000 ether;
        vm.deal(staker1, stake * 11); // extra ETH for gas

        uint256 startBalance = staker1.balance;
        uint256 totalDeposited = 0;
        uint64 t = uint64(block.timestamp);

        for (uint32 i = 0; i < 10; i++) {
            bytes32 vid = _register(staker1, stake, reward1, i + 50);
            sm.completeValidatorRegistration(i);
            totalDeposited += stake;

            uint64 tEnd = t + MIN_STAKE_DURATION + 1;
            vm.warp(tEnd);

            vm.prank(staker1);
            sm.forceInitiateValidatorRemoval(vid, false, 0);

            uint256 balBefore = staker1.balance;
            sm.completeValidatorRemoval(i);
            uint256 returned = staker1.balance - balBefore;

            assertEq(returned, stake, string(abi.encodePacked("cycle ", i, " stake returned")));

            t = tEnd + 1;
            vm.warp(t);
        }

        // Net: staker started with startBalance, deposited and withdrew 10 times
        // Final balance should equal startBalance (no stake lost)
        assertEq(staker1.balance, startBalance, "principal fully conserved across 10 cycles");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TU-11: Principal invariant: deposited = active + pending + withdrawn
    // (Section 15 — principal conservation formal invariant)
    // ─────────────────────────────────────────────────────────────────────────

    function test_TU11_principalInvariant_depositEqualsReturnPlusPending() public {
        uint256 stake = 10_000 ether;
        vm.deal(staker1, stake);

        uint64 t0 = uint64(block.timestamp);
        uint64 t1 = t0 + MIN_STAKE_DURATION + 1;

        uint256 balAtDeposit = staker1.balance;

        bytes32 vid = _register(staker1, stake, reward1, 70);
        sm.completeValidatorRegistration(0);

        // After deposit: staker balance decreased by stake; SM balance increased by stake
        assertEq(staker1.balance, balAtDeposit - stake, "stake locked in SM");
        assertGe(address(sm).balance, stake, "SM holds stake");

        vm.warp(t1);

        vm.prank(staker1);
        sm.forceInitiateValidatorRemoval(vid, false, 0);

        uint256 smBalAfterInitiate = address(sm).balance;

        // After initiate: SM still holds stake (pending withdrawal)
        assertGe(smBalAfterInitiate, stake, "SM holds stake during unbonding");

        uint256 stakerBefore = staker1.balance;
        sm.completeValidatorRemoval(0);

        // After complete: stake returned to staker
        assertEq(staker1.balance - stakerBefore, stake, "stake fully returned on completion");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TU-12: Uptime proof at exact validation duration — 100% reward
    // (Section 13 — exact timestamp)
    // ─────────────────────────────────────────────────────────────────────────

    function test_TU12_uptimeEqualsValidationDuration_fullReward() public {
        uint256 stake = 20_000 ether;
        vm.deal(staker1, stake);

        uint64 t0 = uint64(block.timestamp);
        uint64 duration = 30 days;
        uint64 t1 = t0 + duration;

        bytes32 vid = _register(staker1, stake, reward1, 80);
        sm.completeValidatorRegistration(0);

        vm.warp(t1);

        // uptime == validationDuration → 100% reward multiplier
        warpMock.setUptimeResponse(0, UPTIME_BLOCKCHAIN_ID, vid, duration);
        vm.prank(staker1); sm.submitUptimeProof(vid, 0);
        vm.prank(staker1); sm.initiateValidatorRemoval(vid, false, 0);
        sm.completeValidatorRemoval(0);

        uint256 expectedReward = INITIAL_RATE * duration;
        assertEq(reward1.balance, expectedReward, "100% uptime => full reward");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TU-13: 50% uptime — reward is exactly half
    // (Section 13 — partial uptime)
    // ─────────────────────────────────────────────────────────────────────────

    function test_TU13_halfUptime_halfReward() public {
        uint256 stake = 20_000 ether;
        vm.deal(staker1, stake);

        uint64 t0       = uint64(block.timestamp);
        uint64 duration = 30 days;
        uint64 t1       = t0 + duration;

        bytes32 vid = _register(staker1, stake, reward1, 90);
        sm.completeValidatorRegistration(0);

        vm.warp(t1);

        // 50% uptime: uptime = duration / 2
        uint64 uptime = duration / 2;
        warpMock.setUptimeResponse(0, UPTIME_BLOCKCHAIN_ID, vid, uptime);
        vm.prank(staker1); sm.submitUptimeProof(vid, 0);
        vm.prank(staker1); sm.initiateValidatorRemoval(vid, false, 0);
        sm.completeValidatorRemoval(0);

        // reward = RATE * duration * uptime / duration = RATE * uptime
        uint256 expectedReward = INITIAL_RATE * duration * uptime / duration;
        assertEq(reward1.balance, expectedReward, "50% uptime => half reward");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TU-14: Uptime clamped to validation duration (cannot exceed 100%)
    // (Section 13 — uptime clamped)
    // ─────────────────────────────────────────────────────────────────────────

    function test_TU14_uptimeExceedsValidationDuration_clampedToFull() public {
        uint256 stake = 15_000 ether;
        vm.deal(staker1, stake);

        uint64 t0       = uint64(block.timestamp);
        uint64 duration = 20 days;
        uint64 t1       = t0 + duration;

        bytes32 vid = _register(staker1, stake, reward1, 91);
        sm.completeValidatorRegistration(0);

        vm.warp(t1);

        // Uptime > validationDuration — calculator clamps to validationDuration
        uint64 uptimeExcessive = duration + 1 days;
        warpMock.setUptimeResponse(0, UPTIME_BLOCKCHAIN_ID, vid, uptimeExcessive);
        vm.prank(staker1); sm.submitUptimeProof(vid, 0);
        vm.prank(staker1); sm.initiateValidatorRemoval(vid, false, 0);
        sm.completeValidatorRemoval(0);

        // Reward should be same as 100% uptime (clamped)
        uint256 expectedReward = INITIAL_RATE * duration;
        assertEq(reward1.balance, expectedReward, "excessive uptime clamped to full duration");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TU-15: Principal conservation with rewards — staker and recipient separate
    // (Section 15 — deposited principal == returned principal, rewards separate)
    // ─────────────────────────────────────────────────────────────────────────

    function test_TU15_principalAndRewardSeparate() public {
        uint256 stake = 50_000 ether;
        vm.deal(staker1, stake);

        uint64 t0 = uint64(block.timestamp);
        uint64 t1 = t0 + 60 days;

        bytes32 vid = _register(staker1, stake, reward1, 92);
        sm.completeValidatorRegistration(0);

        vm.warp(t1);

        warpMock.setUptimeResponse(0, UPTIME_BLOCKCHAIN_ID, vid, uint64(60 days));
        vm.prank(staker1); sm.submitUptimeProof(vid, 0);
        vm.prank(staker1); sm.initiateValidatorRemoval(vid, false, 0);

        uint256 stakerBefore = staker1.balance;
        uint256 rewardBefore = reward1.balance;

        sm.completeValidatorRemoval(0);

        uint256 stakeReturned = staker1.balance - stakerBefore;
        uint256 rewardPaid    = reward1.balance - rewardBefore;

        // Principal always goes to staker
        assertEq(stakeReturned, stake, "principal returned to staker");

        // Reward always goes to reward1 (separate address)
        assertEq(rewardPaid, INITIAL_RATE * 60 days, "reward to reward recipient");

        // Staker did not receive reward (they are different addresses)
        assertEq(staker1.balance - stakerBefore, stake, "staker gets only principal");
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    function _register(
        address who,
        uint256 amount,
        address rewardRecipient,
        uint256 seed
    ) internal returns (bytes32) {
        bytes memory nodeID = abi.encodePacked(bytes20(uint160(uint256(keccak256(abi.encode(seed))))));
        bytes memory blsKey = new bytes(48);
        PChainOwner memory noOwner = PChainOwner({threshold: 0, addresses: new address[](0)});
        vm.prank(who);
        return sm.initiateValidatorRegistration{value: amount}(
            nodeID, blsKey, noOwner, noOwner, 100, MIN_STAKE_DURATION, rewardRecipient
        );
    }
}
