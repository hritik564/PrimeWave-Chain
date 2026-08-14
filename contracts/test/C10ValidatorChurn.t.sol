// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// ============================================================
// C10ValidatorChurn.t.sol  --  PW-C10
// ============================================================
//
// Validator churn attacks. Covers C10 brief section 6.
//
// Tests rapid repeated join/leave/rejoin cycles to verify:
//   - No stale reward entitlement
//   - No retroactive rewards
//   - No duplicate rewards
//   - No lost principal
//   - No duplicate validator
//   - No historical accounting corruption
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

contract C10ValidatorChurnTest is Test {

    address constant WARP_PRECOMPILE      = 0x0200000000000000000000000000000000000005;
    uint64  constant CHURN_PERIOD         = 3600;
    bytes32 constant SUBNET_ID            = bytes32(uint256(1));
    bytes32 constant UPTIME_BLOCKCHAIN_ID = bytes32(uint256(2));
    uint64  constant MIN_STAKE_DURATION   = 14 days;
    uint256 constant MIN_STAKE            = 1_000 ether;
    uint256 constant MAX_STAKE            = 3_000_000 ether;
    uint256 constant VAULT_FUND           = 15_000_000 ether;

    address admin    = makeAddr("admin");
    address staker1  = makeAddr("staker1");
    address staker2  = makeAddr("staker2");
    address reward1  = makeAddr("reward1");
    address reward2  = makeAddr("reward2");

    RewardVault                   vault;
    PrimeWaveRewardCalculator     calc;
    MockAvalancheValidatorManager mockVM;
    PrimeWaveStakingManager       sm;
    MockWarpMessenger             warpMock;

    uint256 INITIAL_RATE;

    function setUp() public {
        INITIAL_RATE = uint256(3_000_000 * 1 ether) / 31_536_000;

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
    // VC-01: Stake → remove → restake → remove (A→B→A cycle)
    //         Principal returned each time; no lost funds
    // ─────────────────────────────────────────────────────────────────────────

    function test_VC01_stakeUnbondRestake_principalConserved() public {
        uint256 stake = 10_000 ether;
        vm.deal(staker1, stake * 3);

        uint256 initialBalance = staker1.balance;
        uint256 totalDeposited = 0;

        // Cycle 1
        uint64 t0 = uint64(block.timestamp);
        bytes32 vid1 = _register(staker1, stake, reward1, 1);
        sm.completeValidatorRegistration(0);
        totalDeposited += stake;

        uint64 t1 = t0 + 20 days;
        vm.warp(t1);

        uint64 uptime1 = uint64(20 days);
        warpMock.setUptimeResponse(0, UPTIME_BLOCKCHAIN_ID, vid1, uptime1);
        vm.prank(staker1); sm.submitUptimeProof(vid1, 0);
        vm.prank(staker1); sm.initiateValidatorRemoval(vid1, false, 0);
        sm.completeValidatorRemoval(0);

        // Staker has original stake back (+reward)
        assertGe(staker1.balance, initialBalance - totalDeposited + stake, "cycle1 stake returned");

        // Cycle 2: restake
        uint64 t2 = t1 + 1;
        vm.warp(t2);
        bytes32 vid2 = _register(staker1, stake, reward1, 2);
        sm.completeValidatorRegistration(1);
        totalDeposited += stake;

        uint64 t3 = t2 + 20 days;
        vm.warp(t3);

        uint64 uptime2 = uint64(20 days);
        warpMock.setUptimeResponse(1, UPTIME_BLOCKCHAIN_ID, vid2, uptime2);
        vm.prank(staker1); sm.submitUptimeProof(vid2, 1);
        vm.prank(staker1); sm.initiateValidatorRemoval(vid2, false, 0);
        sm.completeValidatorRemoval(1);

        // No funds lost — balance should be >= initial (plus rewards)
        assertGe(staker1.balance + reward1.balance, initialBalance, "no funds lost across 2 cycles");

        // Vault invariants
        assertLe(vault.totalEmitted(), vault.totalFunded());
        assertLe(vault.totalClaimed(), vault.totalEmitted());
        assertEq(address(vault).balance, vault.totalFunded() - vault.totalClaimed());
    }

    // ─────────────────────────────────────────────────────────────────────────
    // VC-02: Two validators — interleaved remove/rejoin
    //         No cross-contamination of rewards
    // ─────────────────────────────────────────────────────────────────────────

    function test_VC02_twoValidatorsInterleaved_noRewardCrossContamination() public {
        uint256 stake = 5_000 ether;
        vm.deal(staker1, stake * 2);
        vm.deal(staker2, stake * 2);

        uint64 t0 = uint64(block.timestamp);

        // Both register
        bytes32 v1a = _register(staker1, stake, reward1, 10);
        sm.completeValidatorRegistration(0);

        bytes32 v2a = _register(staker2, stake, reward2, 20);
        sm.completeValidatorRegistration(1);

        uint64 t1 = t0 + 20 days;
        vm.warp(t1);

        // v1 removes at 20 days
        warpMock.setUptimeResponse(0, UPTIME_BLOCKCHAIN_ID, v1a, uint64(20 days));
        vm.prank(staker1); sm.submitUptimeProof(v1a, 0);
        vm.prank(staker1); sm.initiateValidatorRemoval(v1a, false, 0);
        sm.completeValidatorRemoval(0);

        uint256 reward1_round1 = reward1.balance;

        // v2 stays longer
        uint64 t2 = t1 + 10 days;
        vm.warp(t2);

        warpMock.setUptimeResponse(1, UPTIME_BLOCKCHAIN_ID, v2a, uint64(30 days));
        vm.prank(staker2); sm.submitUptimeProof(v2a, 1);
        vm.prank(staker2); sm.initiateValidatorRemoval(v2a, false, 0);
        sm.completeValidatorRemoval(1);

        uint256 reward2_total = reward2.balance;

        // v2 staked 30 days, v1 staked 20 days — v2 gets more rewards
        assertGt(reward2_total, reward1_round1, "v2 longer staking = more reward");

        // v1 rejoins
        uint64 t3 = t2 + 1;
        vm.warp(t3);

        bytes32 v1b = _register(staker1, stake, reward1, 11);
        sm.completeValidatorRegistration(2);

        uint64 t4 = t3 + 15 days;
        vm.warp(t4);

        warpMock.setUptimeResponse(2, UPTIME_BLOCKCHAIN_ID, v1b, uint64(15 days));
        vm.prank(staker1); sm.submitUptimeProof(v1b, 2);
        vm.prank(staker1); sm.initiateValidatorRemoval(v1b, false, 0);
        sm.completeValidatorRemoval(2);

        uint256 reward1_round2 = reward1.balance - reward1_round1;
        assertGt(reward1_round2, 0, "v1 round2 reward positive");

        // Vault invariants
        assertLe(vault.totalEmitted(), vault.totalFunded());
        assertEq(address(vault).balance, vault.totalFunded() - vault.totalClaimed());
    }

    // ─────────────────────────────────────────────────────────────────────────
    // VC-03: Zero-reward removal followed by restaking — no stale entitlement
    // ─────────────────────────────────────────────────────────────────────────

    function test_VC03_zeroRewardRemoval_noStaleEntitlement() public {
        uint256 stake = 2_000 ether;
        vm.deal(staker1, stake * 2);

        uint64 t0 = uint64(block.timestamp);
        bytes32 vid1 = _register(staker1, stake, reward1, 100);
        sm.completeValidatorRegistration(0);

        // Remove WITHOUT uptime proof (reward = 0)
        uint64 t1 = t0 + MIN_STAKE_DURATION + 1;
        vm.warp(t1);

        vm.prank(staker1);
        sm.forceInitiateValidatorRemoval(vid1, false, 0);
        sm.completeValidatorRemoval(0);

        assertEq(reward1.balance, 0, "no reward for zero-uptime removal");
        assertEq(staker1.balance, stake * 2, "stake returned");

        // Restake
        uint64 t2 = t1 + 1;
        vm.warp(t2);

        bytes32 vid2 = _register(staker1, stake, reward1, 101);
        sm.completeValidatorRegistration(1);

        uint64 t3 = t2 + 30 days;
        vm.warp(t3);

        // Submit uptime and remove
        warpMock.setUptimeResponse(1, UPTIME_BLOCKCHAIN_ID, vid2, uint64(30 days));
        vm.prank(staker1); sm.submitUptimeProof(vid2, 1);
        vm.prank(staker1); sm.initiateValidatorRemoval(vid2, false, 0);
        sm.completeValidatorRemoval(1);

        // Reward for round 2 only — not backdated to round 1
        uint256 expectedReward = INITIAL_RATE * 30 days;
        assertEq(reward1.balance, expectedReward, "reward only for round 2");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // VC-04: Rapid churn (3 cycles) — vault remains solvent
    // ─────────────────────────────────────────────────────────────────────────

    function test_VC04_rapidChurnThreeCycles_vaultSolvent() public {
        uint256 stake = 1_000 ether;
        vm.deal(staker1, stake * 4);

        uint256 totalClaimed = 0;
        uint64 t = uint64(block.timestamp);

        for (uint32 cycle = 0; cycle < 3; cycle++) {
            uint32 regIdx = cycle;
            uint32 remIdx = cycle;

            bytes32 vid = _register(staker1, stake, reward1, cycle + 200);
            sm.completeValidatorRegistration(regIdx);

            uint64 tStart = t;
            uint64 tEnd   = tStart + 20 days;
            vm.warp(tEnd);

            uint64 uptime = uint64(20 days);
            warpMock.setUptimeResponse(regIdx, UPTIME_BLOCKCHAIN_ID, vid, uptime);
            vm.prank(staker1); sm.submitUptimeProof(vid, regIdx);
            vm.prank(staker1); sm.initiateValidatorRemoval(vid, false, 0);

            uint256 claimedBefore = vault.totalClaimed();
            sm.completeValidatorRemoval(remIdx);
            totalClaimed += vault.totalClaimed() - claimedBefore;

            t = tEnd + 1;
            vm.warp(t);
        }

        // Vault invariants hold through all cycles
        assertLe(vault.totalEmitted(), vault.totalFunded(), "totalEmitted <= totalFunded");
        assertLe(vault.totalClaimed(), vault.totalEmitted(), "totalClaimed <= totalEmitted");
        assertEq(address(vault).balance, vault.totalFunded() - vault.totalClaimed(), "balance exact");
        assertGt(totalClaimed, 0, "rewards were paid");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // VC-05: Weight-change churn on MockAvalancheValidatorManager
    //         Verify weight changes do not corrupt principal
    // ─────────────────────────────────────────────────────────────────────────

    function test_VC05_weightChangeDuringChurn_principalIntact() public {
        uint256 stake = 5_000 ether;
        vm.deal(staker1, stake);

        uint64 t0 = uint64(block.timestamp);
        bytes32 vid = _register(staker1, stake, reward1, 300);
        sm.completeValidatorRegistration(0);

        // Initiate weight update (mock)
        mockVM.initiateValidatorWeightUpdate(vid, 2000);
        mockVM.completeValidatorWeightUpdate(0);

        uint64 t1 = t0 + 20 days;
        vm.warp(t1);

        warpMock.setUptimeResponse(0, UPTIME_BLOCKCHAIN_ID, vid, uint64(20 days));
        vm.prank(staker1); sm.submitUptimeProof(vid, 0);
        vm.prank(staker1); sm.initiateValidatorRemoval(vid, false, 0);

        uint256 stakerBalBefore = staker1.balance;
        sm.completeValidatorRemoval(0);

        // Stake returned in full regardless of weight change
        assertEq(staker1.balance, stakerBalBefore + stake, "stake returned despite weight change");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // VC-06: Validator that was invalidated cannot receive rewards
    // ─────────────────────────────────────────────────────────────────────────

    function test_VC06_invalidatedValidator_cannotReceiveRewards() public {
        uint256 stake = 3_000 ether;
        vm.deal(staker1, stake);

        uint64 t0 = uint64(block.timestamp);
        bytes32 vid = _register(staker1, stake, reward1, 400);
        sm.completeValidatorRegistration(0);

        uint64 t1 = t0 + 20 days;
        vm.warp(t1);

        // Force invalidate (dev helper)
        mockVM.devInvalidate(vid);

        // Cannot submit uptime for invalidated validator (StakingManager checks status)
        // and cannot initiate removal for non-active validator
        vm.prank(staker1);
        vm.expectRevert();
        sm.submitUptimeProof(vid, 0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // VC-07: Two simultaneous removals — no double-counting
    // ─────────────────────────────────────────────────────────────────────────

    function test_VC07_simultaneousRemovals_noDoubleCounting() public {
        uint256 stake = 8_000 ether;
        vm.deal(staker1, stake);
        vm.deal(staker2, stake);

        uint64 t0 = uint64(block.timestamp);

        bytes32 vid1 = _register(staker1, stake, reward1, 500);
        sm.completeValidatorRegistration(0);
        bytes32 vid2 = _register(staker2, stake, reward2, 501);
        sm.completeValidatorRegistration(1);

        uint64 t1 = t0 + 25 days;
        vm.warp(t1);

        // Both submit uptime simultaneously
        warpMock.setUptimeResponse(0, UPTIME_BLOCKCHAIN_ID, vid1, uint64(25 days));
        warpMock.setUptimeResponse(1, UPTIME_BLOCKCHAIN_ID, vid2, uint64(25 days));

        vm.prank(staker1); sm.submitUptimeProof(vid1, 0);
        vm.prank(staker2); sm.submitUptimeProof(vid2, 1);

        vm.prank(staker1); sm.initiateValidatorRemoval(vid1, false, 0);
        vm.prank(staker2); sm.initiateValidatorRemoval(vid2, false, 0);

        uint256 vaultClaimedBefore = vault.totalClaimed();
        sm.completeValidatorRemoval(0);
        sm.completeValidatorRemoval(1);

        uint256 totalPaid = vault.totalClaimed() - vaultClaimedBefore;

        // Each validator gets RATE * 25 days (known dual-full-rate pattern)
        uint256 expectedEach = INITIAL_RATE * 25 days;
        assertEq(reward1.balance, expectedEach, "validator1 correct reward");
        assertEq(reward2.balance, expectedEach, "validator2 correct reward");
        assertEq(totalPaid, expectedEach * 2, "total paid matches");
        assertLe(vault.totalClaimed(), vault.totalFunded(), "vault solvent");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // VC-08: Churn does not create retroactive rewards for re-stakers
    // ─────────────────────────────────────────────────────────────────────────

    function test_VC08_noRetroactiveRewardsOnRejoin() public {
        uint256 stake = 4_000 ether;
        vm.deal(staker1, stake * 2);

        uint64 t0 = uint64(block.timestamp);

        bytes32 vid1 = _register(staker1, stake, reward1, 600);
        sm.completeValidatorRegistration(0);

        uint64 t1 = t0 + 15 days;
        vm.warp(t1);

        // Remove without uptime (zero reward)
        vm.prank(staker1);
        sm.forceInitiateValidatorRemoval(vid1, false, 0);
        sm.completeValidatorRemoval(0);

        uint256 rewardAfterRound1 = reward1.balance;
        assertEq(rewardAfterRound1, 0, "no retroactive reward");

        // Time passes while not staking
        uint64 t2 = t1 + 15 days;
        vm.warp(t2);

        // Rejoin
        bytes32 vid2 = _register(staker1, stake, reward1, 601);
        sm.completeValidatorRegistration(1);

        uint64 t3 = t2 + 15 days;
        vm.warp(t3);

        warpMock.setUptimeResponse(1, UPTIME_BLOCKCHAIN_ID, vid2, uint64(15 days));
        vm.prank(staker1); sm.submitUptimeProof(vid2, 1);
        vm.prank(staker1); sm.initiateValidatorRemoval(vid2, false, 0);
        sm.completeValidatorRemoval(1);

        // Reward only for round 2 staking period — not the 15 days between rounds
        uint256 expectedReward = INITIAL_RATE * 15 days;
        assertEq(reward1.balance, expectedReward, "reward only for round 2 staking period");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // VC-09: Full cycle A→B→A→B — four-phase churn
    // ─────────────────────────────────────────────────────────────────────────

    function test_VC09_ABAB_fourPhaseCycle() public {
        uint256 stake = 2_000 ether;
        vm.deal(staker1, stake * 5);

        uint256 totalReward = 0;
        uint64 t = uint64(block.timestamp);

        for (uint32 i = 0; i < 4; i++) {
            bytes32 vid = _register(staker1, stake, reward1, i + 700);
            sm.completeValidatorRegistration(i);

            uint64 tEnd = t + 16 days;
            vm.warp(tEnd);

            warpMock.setUptimeResponse(i, UPTIME_BLOCKCHAIN_ID, vid, uint64(16 days));
            vm.prank(staker1); sm.submitUptimeProof(vid, i);
            vm.prank(staker1); sm.initiateValidatorRemoval(vid, false, 0);

            uint256 rewardBefore = reward1.balance;
            sm.completeValidatorRemoval(i);
            totalReward += reward1.balance - rewardBefore;

            t = tEnd + 1;
            vm.warp(t);
        }

        // Exactly 4 * RATE * 16 days rewards
        uint256 expectedTotal = INITIAL_RATE * 16 days * 4;
        assertEq(totalReward, expectedTotal, "4-cycle total reward exact");
        assertLe(vault.totalClaimed(), vault.totalFunded(), "vault solvent");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // VC-10: Stake increase via weight update — accounting stays consistent
    // ─────────────────────────────────────────────────────────────────────────

    function test_VC10_weightIncrease_noAccountingCorruption() public {
        uint256 stake = 3_000 ether;
        vm.deal(staker1, stake);

        uint64 t0 = uint64(block.timestamp);

        bytes32 vid = _register(staker1, stake, reward1, 800);
        sm.completeValidatorRegistration(0);

        // Weight increases mid-period
        mockVM.initiateValidatorWeightUpdate(vid, 5000);
        mockVM.completeValidatorWeightUpdate(0);

        uint64 t1 = t0 + 30 days;
        vm.warp(t1);

        warpMock.setUptimeResponse(0, UPTIME_BLOCKCHAIN_ID, vid, uint64(30 days));
        vm.prank(staker1); sm.submitUptimeProof(vid, 0);
        vm.prank(staker1); sm.initiateValidatorRemoval(vid, false, 0);

        uint256 stakerBefore = staker1.balance;
        sm.completeValidatorRemoval(0);

        // Principal fully returned
        assertEq(staker1.balance - stakerBefore, stake, "full principal returned");

        // Vault still solvent
        assertLe(vault.totalEmitted(), vault.totalFunded());
        assertEq(address(vault).balance, vault.totalFunded() - vault.totalClaimed());
    }

    // ─────────────────────────────────────────────────────────────────────────
    // VC-11: Simultaneous staker and solo validator — no mutual interference
    // ─────────────────────────────────────────────────────────────────────────

    function test_VC11_parallelStakers_noInterference() public {
        uint256 stake = 6_000 ether;
        vm.deal(staker1, stake);
        vm.deal(staker2, stake);

        uint64 t0 = uint64(block.timestamp);

        bytes32 v1 = _register(staker1, stake, reward1, 900);
        sm.completeValidatorRegistration(0);

        bytes32 v2 = _register(staker2, stake, reward2, 901);
        sm.completeValidatorRegistration(1);

        // v1 exits early; v2 stays longer
        uint64 t1 = t0 + 15 days;
        vm.warp(t1);

        warpMock.setUptimeResponse(0, UPTIME_BLOCKCHAIN_ID, v1, uint64(15 days));
        vm.prank(staker1); sm.submitUptimeProof(v1, 0);
        vm.prank(staker1); sm.initiateValidatorRemoval(v1, false, 0);
        sm.completeValidatorRemoval(0);

        uint256 reward1a = reward1.balance;

        uint64 t2 = t1 + 15 days;
        vm.warp(t2);

        warpMock.setUptimeResponse(1, UPTIME_BLOCKCHAIN_ID, v2, uint64(30 days));
        vm.prank(staker2); sm.submitUptimeProof(v2, 1);
        vm.prank(staker2); sm.initiateValidatorRemoval(v2, false, 0);
        sm.completeValidatorRemoval(1);

        uint256 reward2a = reward2.balance;

        assertEq(reward1a, INITIAL_RATE * 15 days, "v1 exact 15-day reward");
        assertEq(reward2a, INITIAL_RATE * 30 days, "v2 exact 30-day reward");

        // Neither gets the other's reward
        assertEq(reward1.balance, INITIAL_RATE * 15 days, "reward1 not inflated");
        assertEq(reward2.balance, INITIAL_RATE * 30 days, "reward2 not inflated");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // VC-12: Stale removal queue cannot be replayed
    // ─────────────────────────────────────────────────────────────────────────

    function test_VC12_staleRemovalQueueNotReplayable() public {
        uint256 stake = 5_000 ether;
        vm.deal(staker1, stake);

        uint64 t0 = uint64(block.timestamp);
        bytes32 vid = _register(staker1, stake, reward1, 1000);
        sm.completeValidatorRegistration(0);

        uint64 t1 = t0 + 20 days;
        vm.warp(t1);

        warpMock.setUptimeResponse(0, UPTIME_BLOCKCHAIN_ID, vid, uint64(20 days));
        vm.prank(staker1); sm.submitUptimeProof(vid, 0);
        vm.prank(staker1); sm.initiateValidatorRemoval(vid, false, 0);
        sm.completeValidatorRemoval(0);

        // Attempt to complete removal again (replay)
        vm.expectRevert();
        sm.completeValidatorRemoval(0);
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
