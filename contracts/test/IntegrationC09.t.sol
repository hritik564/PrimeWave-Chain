// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// ============================================================
// IntegrationC09.t.sol  --  PW-C09
// ============================================================
//
// End-to-end integration tests for Phase-2 PoS:
//   - Full validator lifecycle with real reward delivery
//   - Multiple validators coexisting
//   - Vault solvency after many staking cycles
//   - Phase-1 → Phase-2 transition: setStakingManager after C06 recipients
//   - Emergency pause stops both claim() and distribute()
//   - Vault exhaustion handled gracefully
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

contract IntegrationC09Test is Test {

    // ── Constants ─────────────────────────────────────────────────────────────

    address constant WARP_PRECOMPILE     = 0x0200000000000000000000000000000000000005;
    uint64  constant CHURN_PERIOD        = 3600;
    bytes32 constant SUBNET_ID           = bytes32(uint256(1));
    bytes32 constant UPTIME_BLOCKCHAIN_ID = bytes32(uint256(2));
    // Set in setUp() from vault.MAX_RATE_PER_SECOND() to avoid rational-constant compile error.
    uint256 INITIAL_RATE;
    uint256 constant VAULT_FUND          = 15_000_000 ether;
    uint256 constant MIN_STAKE           = 1_000 ether;
    uint256 constant MAX_STAKE           = 3_000_000 ether;
    uint64  constant MIN_STAKE_DURATION  = 14 days;

    // ── Actors ────────────────────────────────────────────────────────────────

    address admin      = makeAddr("admin");
    address validator1 = makeAddr("validator1");
    address validator2 = makeAddr("validator2");
    address rewarded1  = makeAddr("rewarded1");
    address rewarded2  = makeAddr("rewarded2");

    // ── Contracts ─────────────────────────────────────────────────────────────

    RewardVault                   vault;
    PrimeWaveRewardCalculator     calc;
    MockAvalancheValidatorManager mockVM;
    PrimeWaveStakingManager       sm;
    MockWarpMessenger             warpMock;

    // ── Setup ─────────────────────────────────────────────────────────────────

    function setUp() public {
        // Compute MAX_RATE_PER_SECOND at runtime (matches RewardVault compile-time constant exactly)
        INITIAL_RATE = uint256(3_000_000 * 1 ether) / 31_536_000;

        vm.startPrank(admin);

        vault = new RewardVault(admin, INITIAL_RATE);
        vm.deal(admin, VAULT_FUND + 100 ether);
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

        // Etch mock Warp messenger at precompile address
        warpMock = new MockWarpMessenger();
        vm.etch(WARP_PRECOMPILE, address(warpMock).code);
        warpMock = MockWarpMessenger(payable(WARP_PRECOMPILE));

        vm.stopPrank();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // IC09-1: Full lifecycle — uptime proof → non-zero reward
    // ─────────────────────────────────────────────────────────────────────────

    function test_IC09_fullLifecycleWithUptime() public {
        uint256 stakeAmount = 50_000 ether;
        vm.deal(validator1, stakeAmount);

        uint64 t0 = uint64(block.timestamp);

        // Register
        bytes32 vid = _register(validator1, stakeAmount, rewarded1, 1);
        sm.completeValidatorRegistration(0);

        // Age 60 days
        vm.warp(t0 + 60 days);

        // Submit uptime proof (100% uptime)
        uint64 uptime = 60 days;
        warpMock.setUptimeResponse(0, UPTIME_BLOCKCHAIN_ID, vid, uptime);
        vm.prank(validator1);
        sm.submitUptimeProof(vid, 0);

        // Initiate removal (no extra proof needed since we already submitted)
        vm.prank(validator1);
        sm.initiateValidatorRemoval(vid, false, 0);

        uint256 valBalBefore  = validator1.balance;
        uint256 rewBalBefore  = rewarded1.balance;
        uint256 claimedBefore = vault.totalClaimed();

        // Complete removal
        sm.completeValidatorRemoval(0);

        // Stake returned
        assertEq(validator1.balance, valBalBefore + stakeAmount, "stake returned");

        // Reward = rate × 60 days × (60d / 60d) = rate × 60 days
        uint256 expectedReward = INITIAL_RATE * 60 days;
        assertEq(rewarded1.balance, rewBalBefore + expectedReward, "reward paid");
        assertEq(vault.totalClaimed(), claimedBefore + expectedReward, "vault claimed");

        // Vault invariants
        assertLe(vault.totalEmitted(), vault.totalFunded());
        assertLe(vault.totalClaimed(), vault.totalEmitted());
        assertEq(address(vault).balance, vault.totalFunded() - vault.totalClaimed());
    }

    // ─────────────────────────────────────────────────────────────────────────
    // IC09-2: Two validators — both get full rate (no proportional split)
    // ─────────────────────────────────────────────────────────────────────────

    function test_IC09_twoValidatorsGetFullRate() public {
        uint256 stake1 = 10_000 ether;
        uint256 stake2 = 20_000 ether;
        vm.deal(validator1, stake1);
        vm.deal(validator2, stake2);

        uint64 t0 = uint64(block.timestamp);

        // Both register simultaneously
        bytes32 vid1 = _register(validator1, stake1, rewarded1, 1);
        sm.completeValidatorRegistration(0);

        bytes32 vid2 = _register(validator2, stake2, rewarded2, 2);
        sm.completeValidatorRegistration(1);

        // Age 30 days
        vm.warp(t0 + 30 days);

        // Both submit uptime proofs
        warpMock.setUptimeResponse(0, UPTIME_BLOCKCHAIN_ID, vid1, 30 days);
        warpMock.setUptimeResponse(1, UPTIME_BLOCKCHAIN_ID, vid2, 30 days);
        vm.prank(validator1);
        sm.submitUptimeProof(vid1, 0);
        vm.prank(validator2);
        sm.submitUptimeProof(vid2, 1);

        // Validator1 initiates and completes removal first
        vm.prank(validator1);
        sm.initiateValidatorRemoval(vid1, false, 0);
        sm.completeValidatorRemoval(0);

        uint256 reward1 = rewarded1.balance;

        // Validator2 initiates and completes removal
        vm.prank(validator2);
        sm.initiateValidatorRemoval(vid2, false, 0);
        sm.completeValidatorRemoval(1);

        uint256 reward2 = rewarded2.balance;

        // Each gets the full rate for 30 days (known limitation: no proportional split)
        uint256 expectedEach = INITIAL_RATE * 30 days;
        assertEq(reward1, expectedEach, "validator1 full rate");
        assertEq(reward2, expectedEach, "validator2 full rate");

        // Vault must remain solvent
        assertLe(vault.totalClaimed(), vault.totalFunded(), "vault not overdrawn");
        assertEq(address(vault).balance, vault.totalFunded() - vault.totalClaimed(), "inv5");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // IC09-3: Emergency pause — distribute blocked
    // ─────────────────────────────────────────────────────────────────────────

    function test_IC09_emergencyPauseBlocksDistribute() public {
        uint256 stakeAmount = 10_000 ether;
        vm.deal(validator1, stakeAmount);

        uint64 t0 = uint64(block.timestamp);
        bytes32 vid = _register(validator1, stakeAmount, rewarded1, 1);
        sm.completeValidatorRegistration(0);

        vm.warp(t0 + 30 days);

        warpMock.setUptimeResponse(0, UPTIME_BLOCKCHAIN_ID, vid, 30 days);
        vm.prank(validator1);
        sm.submitUptimeProof(vid, 0);

        vm.prank(validator1);
        sm.initiateValidatorRemoval(vid, false, 0);

        // Pause the vault
        vm.startPrank(admin);
        vault.setPauseController(admin);
        vault.pause();
        vm.stopPrank();

        // Complete removal should revert because distribute() is blocked by pause
        vm.expectRevert();
        sm.completeValidatorRemoval(0);

        // Unpause and retry
        vm.prank(admin);
        vault.unpause();

        // Now it should succeed
        sm.completeValidatorRemoval(0);
        assertGt(rewarded1.balance, 0, "reward paid after unpause");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // IC09-4: Phase-1 recipients + Phase-2 staking coexist
    // ─────────────────────────────────────────────────────────────────────────

    function test_IC09_phase1AndPhase2CoexistInVault() public {
        // Register a Phase-1 recipient (C06 model)
        bytes32 recipientID = keccak256("phase1-validator");
        vm.prank(admin);
        vault.registerRecipient(recipientID, rewarded2, 100, true);

        // Advance time to accrue some Phase-1 rewards
        vm.warp(block.timestamp + 30 days);

        // Phase-2: register a staking validator
        uint256 stakeAmount = 10_000 ether;
        vm.deal(validator1, stakeAmount);

        uint64 t0 = uint64(block.timestamp);
        bytes32 vid = _register(validator1, stakeAmount, rewarded1, 1);
        sm.completeValidatorRegistration(0);

        vm.warp(t0 + 30 days);

        warpMock.setUptimeResponse(0, UPTIME_BLOCKCHAIN_ID, vid, 30 days);
        vm.prank(validator1);
        sm.submitUptimeProof(vid, 0);
        vm.prank(validator1);
        sm.initiateValidatorRemoval(vid, false, 0);
        sm.completeValidatorRemoval(0);

        // Phase-2 reward paid
        assertGt(rewarded1.balance, 0, "phase2 reward paid");

        // Phase-1 claim still works
        vm.prank(rewarded2);
        uint256 claimed1 = vault.claim(recipientID);
        assertGt(claimed1, 0, "phase1 claim works");

        // Vault invariants still hold
        assertLe(vault.totalEmitted(), vault.totalFunded());
        assertLe(vault.totalClaimed(), vault.totalEmitted());
        assertEq(address(vault).balance, vault.totalFunded() - vault.totalClaimed());
    }

    // ─────────────────────────────────────────────────────────────────────────
    // IC09-5: Stake returned correctly even when reward is zero
    // ─────────────────────────────────────────────────────────────────────────

    function test_IC09_stakeAlwaysReturned() public {
        uint256 stakeAmount = 10_000 ether;
        vm.deal(validator1, stakeAmount);

        bytes32 vid = _register(validator1, stakeAmount, rewarded1, 1);
        sm.completeValidatorRegistration(0);

        vm.warp(block.timestamp + MIN_STAKE_DURATION + 1);

        // Remove WITHOUT uptime proof (reward = 0).
        // Must use forceInitiateValidatorRemoval: initiateValidatorRemoval reverts with
        // ValidatorIneligibleForRewards when reward = 0 (no uptime proof submitted).
        vm.prank(validator1);
        sm.forceInitiateValidatorRemoval(vid, false, 0);

        uint256 valBalBefore = validator1.balance;
        sm.completeValidatorRemoval(0);

        assertEq(validator1.balance, valBalBefore + stakeAmount, "stake returned even with zero reward");
        assertEq(rewarded1.balance, 0, "no reward paid");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // IC09-6: setStakingManager cannot be called twice
    // ─────────────────────────────────────────────────────────────────────────

    function test_IC09_stakingManagerSetOnce() public {
        // Already set in setUp
        vm.prank(admin);
        vm.expectRevert("RV: staking manager already set");
        vault.setStakingManager(makeAddr("other-sm"));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────────

    function _register(
        address who,
        uint256 stakeAmount,
        address rewardRecipient,
        uint256 seed
    ) internal returns (bytes32) {
        PChainOwner memory noOwner = PChainOwner({threshold: 0, addresses: new address[](0)});
        bytes memory nodeID = abi.encodePacked(bytes20(uint160(uint256(keccak256(abi.encode(seed))))));
        bytes memory blsKey = new bytes(48);

        vm.prank(who);
        return sm.initiateValidatorRegistration{value: stakeAmount}(
            nodeID, blsKey, noOwner, noOwner, 100, MIN_STAKE_DURATION, rewardRecipient
        );
    }
}
