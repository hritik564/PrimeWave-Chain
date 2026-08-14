// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// ============================================================
// StakingManagerUnit.t.sol  --  PW-C09
// ============================================================
//
// Unit tests covering:
//   A) RewardVault.distribute()     — role, invariants, zero-amount
//   B) PrimeWaveRewardCalculator    — all uptime/duration edge cases
//   C) PrimeWaveStakingManager init — parameter validation
//   D) Full staking lifecycle       — register → complete → age → remove → complete
//   E) Unbonding enforcement        — early removal reverts
//   F) Attack / security            — unauthorized distribute, reentrancy guard
//
// Test naming: test_<section>_<what>
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

/// @dev Helper contract to test reentrancy guard on distribute()
contract ReentrantReceiver {
    RewardVault public vault;
    bool public attacked;

    constructor(RewardVault _vault) { vault = _vault; }

    receive() external payable {
        if (!attacked) {
            attacked = true;
            try vault.distribute(address(this), 1 ether) {
                // should not reach here
            } catch {
                // expected: reentrant call rejected
            }
        }
    }
}

contract StakingManagerUnitTest is Test {

    // ── Constants ─────────────────────────────────────────────────────────────

    address constant WARP_PRECOMPILE = 0x0200000000000000000000000000000000000005;
    uint64  constant MIN_STAKE_DURATION = 14 days;
    uint64  constant CHURN_PERIOD       = 3600;
    bytes32 constant SUBNET_ID          = bytes32(uint256(1));
    bytes32 constant UPTIME_BLOCKCHAIN_ID = bytes32(uint256(2));

    // Set in setUp() from vault.MAX_RATE_PER_SECOND() to avoid rational-constant compile error.
    uint256 INITIAL_RATE;
    uint256 constant VAULT_FUND   = 15_000_000 ether;
    uint256 constant MIN_STAKE    = 1_000 ether;
    uint256 constant MAX_STAKE    = 3_000_000 ether;

    // ── Actors ────────────────────────────────────────────────────────────────

    address admin     = makeAddr("admin");
    address validator = makeAddr("validator");
    address rewarded  = makeAddr("rewarded");

    // ── Contracts ─────────────────────────────────────────────────────────────

    RewardVault                    vault;
    PrimeWaveRewardCalculator      calc;
    MockAvalancheValidatorManager  mockVM;
    PrimeWaveStakingManager        sm;
    MockWarpMessenger              warpMock;

    // ── Setup ─────────────────────────────────────────────────────────────────

    function setUp() public {
        // Compute MAX_RATE_PER_SECOND at runtime (matches RewardVault compile-time constant exactly)
        INITIAL_RATE = uint256(3_000_000 * 1 ether) / 31_536_000;

        vm.startPrank(admin);

        // Deploy RewardVault with MAX rate
        vault = new RewardVault(admin, INITIAL_RATE);
        vm.deal(admin, VAULT_FUND + 10 ether);
        vault.fund{value: VAULT_FUND}();

        // Deploy MockAvalancheValidatorManager
        mockVM = new MockAvalancheValidatorManager(SUBNET_ID, CHURN_PERIOD);

        // Deploy PrimeWaveRewardCalculator
        calc = new PrimeWaveRewardCalculator(vault);

        // Deploy PrimeWaveStakingManager
        sm = new PrimeWaveStakingManager();
        PChainOwner memory noOwner = PChainOwner({threshold: 0, addresses: new address[](0)});
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

        // Register staking manager with vault
        vault.setStakingManager(address(sm));

        // Etch MockWarpMessenger at precompile address
        warpMock = new MockWarpMessenger();
        vm.etch(WARP_PRECOMPILE, address(warpMock).code);
        // Re-reference via interface at precompile address for uptime configuration
        warpMock = MockWarpMessenger(payable(WARP_PRECOMPILE));

        vm.stopPrank();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // A) RewardVault.distribute()
    // ─────────────────────────────────────────────────────────────────────────

    function test_distribute_basic() public {
        uint256 amount = 1 ether;
        uint256 balBefore = address(rewarded).balance;
        uint256 emittedBefore = vault.totalEmitted();
        uint256 claimedBefore = vault.totalClaimed();

        vm.prank(address(sm));
        vm.expectEmit(true, false, false, true, address(vault));
        emit RewardVault.StakingRewardDistributed(rewarded, amount);
        vault.distribute(rewarded, amount);

        assertEq(address(rewarded).balance, balBefore + amount, "recipient balance");
        assertEq(vault.totalEmitted(), emittedBefore + amount,  "totalEmitted");
        assertEq(vault.totalClaimed(), claimedBefore + amount,  "totalClaimed");
    }

    function test_distribute_revertsIfNotStakingManager() public {
        vm.prank(validator);
        vm.expectRevert("RV: not staking manager");
        vault.distribute(rewarded, 1 ether);
    }

    function test_distribute_zeroAmountIsNoOp() public {
        uint256 emittedBefore = vault.totalEmitted();
        uint256 balBefore = address(rewarded).balance;

        vm.prank(address(sm));
        vault.distribute(rewarded, 0);

        assertEq(vault.totalEmitted(), emittedBefore, "no emit on zero");
        assertEq(address(rewarded).balance, balBefore, "no transfer on zero");
    }

    function test_distribute_revertsIfExceedsReserve() public {
        uint256 tooMuch = vault.totalFunded() + 1;
        vm.prank(address(sm));
        vm.expectRevert("RV: insufficient reserve");
        vault.distribute(rewarded, tooMuch);
    }

    function test_distribute_revertsZeroRecipient() public {
        vm.prank(address(sm));
        vm.expectRevert("RV: zero recipient");
        vault.distribute(address(0), 1 ether);
    }

    function test_distribute_invariantsHoldAfterDistribute() public {
        uint256 amount = 5_000 ether;

        vm.prank(address(sm));
        vault.distribute(rewarded, amount);

        // Invariant 2: totalEmitted <= totalFunded
        assertLe(vault.totalEmitted(), vault.totalFunded(), "inv2");
        // Invariant 3: totalClaimed <= totalEmitted
        assertLe(vault.totalClaimed(), vault.totalEmitted(), "inv3");
        // Invariant 5: balance == totalFunded - totalClaimed
        assertEq(address(vault).balance, vault.totalFunded() - vault.totalClaimed(), "inv5");
    }

    function test_distribute_setStakingManagerOnce() public {
        vm.prank(admin);
        vm.expectRevert("RV: staking manager already set");
        vault.setStakingManager(makeAddr("other"));
    }

    function test_distribute_revertsWhenPaused() public {
        // Set up a pause controller and pause
        vm.startPrank(admin);
        vault.setPauseController(admin);
        vault.pause();
        vm.stopPrank();

        vm.prank(address(sm));
        vm.expectRevert("RV: paused");
        vault.distribute(rewarded, 1 ether);
    }

    function test_distribute_reentrancyGuard() public {
        // Deploy a malicious receiver that tries to re-enter
        ReentrantReceiver attacker = new ReentrantReceiver(vault);

        // Give attacker some ETH for gas
        vm.deal(address(attacker), 1 ether);

        // Have staking manager try to distribute to the attacker
        vm.prank(address(sm));
        // This should succeed (reentrancy attempt inside receive() fails)
        vault.distribute(address(attacker), 1 ether);

        // Verify the attacker's re-entry was blocked
        assertTrue(attacker.attacked(), "reentrancy was attempted");
        // Verify only 1 ether was distributed (not 2)
        assertEq(vault.totalClaimed(), 1 ether, "only one distribution");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // B) PrimeWaveRewardCalculator
    // ─────────────────────────────────────────────────────────────────────────

    function test_calc_fullUptimeReward() public view {
        uint64 t0 = 1000;
        uint64 t1 = t0 + 30 days;

        // 100% uptime: uptimeSeconds == validationDuration
        uint256 reward = calc.calculateReward(
            100 ether, // stakeAmount (not used in formula)
            t0,        // validatorStartTime
            t0,        // stakingStartTime
            t1,        // stakingEndTime
            uint64(30 days) // uptimeSeconds == validationDuration → uptime fraction = 1
        );

        // Expected: rate × 30 days × 1 = INITIAL_RATE × 30 × 86400
        uint256 expected = INITIAL_RATE * 30 days;
        assertEq(reward, expected, "full uptime reward");
    }

    function test_calc_zeroUptimeReward() public view {
        uint64 t0 = 1000;
        uint64 t1 = t0 + 30 days;

        uint256 reward = calc.calculateReward(100 ether, t0, t0, t1, 0);
        assertEq(reward, 0, "zero uptime = zero reward");
    }

    function test_calc_halfUptimeReward() public view {
        uint64 t0 = 1000;
        uint64 t1 = t0 + 30 days;
        uint64 halfUptime = uint64(15 days); // 50% uptime

        uint256 reward = calc.calculateReward(100 ether, t0, t0, t1, halfUptime);

        uint256 expectedFull = INITIAL_RATE * 30 days;
        uint256 expectedHalf = expectedFull / 2;
        assertEq(reward, expectedHalf, "half uptime = half reward");
    }

    function test_calc_zeroStakingDuration() public view {
        uint64 t = 1000;
        uint256 reward = calc.calculateReward(100 ether, t, t, t, 0);
        assertEq(reward, 0, "zero duration = zero reward");
    }

    function test_calc_cappedByVaultAvailable() public {
        // Drain all but 1 wei of available reserve
        uint256 fundedMinus1 = vault.totalFunded() - 1;
        // Simulate all but 1 being emitted
        // We achieve this by distributing most of the vault balance
        vm.prank(address(sm));
        vault.distribute(rewarded, fundedMinus1);

        uint64 t0 = 1000;
        uint64 t1 = t0 + 365 days;

        // Would earn INITIAL_RATE * 365 days >> 1 wei
        uint256 reward = calc.calculateReward(100 ether, t0, t0, t1, uint64(365 days));
        assertEq(reward, 1, "capped at available=1 wei");
    }

    function test_calc_vaultExhausted() public {
        // Drain entire vault.
        // NOTE: Capture totalFunded() BEFORE vm.prank — prank applies to the next call only,
        // and argument expressions are evaluated first which would consume the prank.
        uint256 totalFunded = vault.totalFunded();
        vm.prank(address(sm));
        vault.distribute(rewarded, totalFunded);

        uint64 t0 = 1000;
        uint64 t1 = t0 + 30 days;

        uint256 reward = calc.calculateReward(100 ether, t0, t0, t1, uint64(30 days));
        assertEq(reward, 0, "exhausted vault = zero reward");
    }

    function test_calc_uptimeClampedToValidationDuration() public view {
        uint64 t0 = 1000;
        uint64 t1 = t0 + 30 days;
        uint64 overUptime = uint64(60 days); // 2× validation duration

        // Should be clamped to validationDuration → same as 100% uptime
        uint256 reward = calc.calculateReward(100 ether, t0, t0, t1, overUptime);
        uint256 expectedFull = INITIAL_RATE * 30 days;
        assertEq(reward, expectedFull, "over-uptime clamped to validation duration");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // C) PrimeWaveStakingManager.initialize() validation
    // ─────────────────────────────────────────────────────────────────────────

    function test_init_revertsZeroVault() public {
        PrimeWaveStakingManager sm2 = new PrimeWaveStakingManager();
        vm.expectRevert();
        sm2.initialize(
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
            RewardVault(payable(address(0)))
        );
    }

    function test_init_revertsZeroUptimeBlockchainID() public {
        PrimeWaveStakingManager sm2 = new PrimeWaveStakingManager();
        vm.expectRevert();
        sm2.initialize(
            StakingManagerSettings({
                manager:                  IValidatorManager(address(mockVM)),
                minimumStakeAmount:       MIN_STAKE,
                maximumStakeAmount:       MAX_STAKE,
                minimumStakeDuration:     MIN_STAKE_DURATION,
                minimumDelegationFeeBips: 100,
                maximumStakeMultiplier:   1,
                weightToValueFactor:      1 ether,
                rewardCalculator:         IRewardCalculator(address(calc)),
                uptimeBlockchainID:       bytes32(0)  // invalid
            }),
            vault
        );
    }

    function test_init_revertsMinStakeDurationBelowChurnPeriod() public {
        PrimeWaveStakingManager sm2 = new PrimeWaveStakingManager();
        vm.expectRevert();
        sm2.initialize(
            StakingManagerSettings({
                manager:                  IValidatorManager(address(mockVM)),
                minimumStakeAmount:       MIN_STAKE,
                maximumStakeAmount:       MAX_STAKE,
                minimumStakeDuration:     CHURN_PERIOD - 1, // below churn period
                minimumDelegationFeeBips: 100,
                maximumStakeMultiplier:   1,
                weightToValueFactor:      1 ether,
                rewardCalculator:         IRewardCalculator(address(calc)),
                uptimeBlockchainID:       UPTIME_BLOCKCHAIN_ID
            }),
            vault
        );
    }

    function test_init_cannotInitializeTwice() public {
        // Already initialized in setUp
        vm.expectRevert();
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
    }

    // ─────────────────────────────────────────────────────────────────────────
    // D) Full staking lifecycle — no uptime proof (zero reward)
    // ─────────────────────────────────────────────────────────────────────────

    function test_lifecycle_noUptimeProof_zeroReward() public {
        uint256 stakeAmount = 10_000 ether;
        vm.deal(validator, stakeAmount);

        // 1. Register
        bytes32 validationID = _initiateRegistration(stakeAmount);

        // 2. Complete registration (msg index 0)
        sm.completeValidatorRegistration(0);

        // 3. Age past minimum stake duration
        vm.warp(block.timestamp + MIN_STAKE_DURATION + 1);

        // 4. Initiate removal WITHOUT uptime proof.
        // Must use forceInitiateValidatorRemoval: initiateValidatorRemoval reverts with
        // ValidatorIneligibleForRewards when reward = 0 (zero uptime, no proof submitted).
        vm.prank(validator);
        sm.forceInitiateValidatorRemoval(validationID, false, 0);

        uint256 rewardedBalBefore = address(rewarded).balance;
        uint256 validatorBalBefore = address(validator).balance;
        uint256 claimedBefore = vault.totalClaimed();

        // 5. Complete removal (msg index 0)
        sm.completeValidatorRemoval(0);

        // With no uptime → reward = 0 → distribute NOT called
        assertEq(address(rewarded).balance, rewardedBalBefore, "no reward for zero uptime");
        assertEq(vault.totalClaimed(), claimedBefore, "vault unchanged");
        // Stake returned to validator
        assertEq(address(validator).balance, validatorBalBefore + stakeAmount, "stake returned");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // D2) Full lifecycle — with uptime proof (non-zero reward)
    // ─────────────────────────────────────────────────────────────────────────

    function test_lifecycle_withUptimeProof_nonZeroReward() public {
        uint256 stakeAmount = 10_000 ether;
        vm.deal(validator, stakeAmount);

        uint64 startTime = uint64(block.timestamp);

        // 1. Register
        bytes32 validationID = _initiateRegistration(stakeAmount);

        // 2. Complete
        sm.completeValidatorRegistration(0);

        // 3. Age 30 days
        uint64 endTime = startTime + 30 days;
        vm.warp(endTime);

        // 4. Submit uptime proof (100% uptime)
        uint64 uptimeSeconds = 30 days;
        warpMock.setUptimeResponse(0, UPTIME_BLOCKCHAIN_ID, validationID, uptimeSeconds);
        vm.prank(validator);
        sm.submitUptimeProof(validationID, 0);

        // 5. Initiate removal WITHOUT additional uptime proof
        vm.prank(validator);
        sm.initiateValidatorRemoval(validationID, false, 0);

        // 6. Complete removal
        uint256 rewardedBalBefore  = address(rewarded).balance;
        uint256 claimedBefore      = vault.totalClaimed();

        sm.completeValidatorRemoval(0);

        // Reward should be positive: rate × 30 days × (uptimeSeconds / validationDuration)
        // validationDuration = endTime - startTime = 30 days
        // uptimeFraction = 30 days / 30 days = 1
        uint256 expectedReward = INITIAL_RATE * 30 days;
        uint256 actualReward = address(rewarded).balance - rewardedBalBefore;

        assertEq(actualReward, expectedReward, "expected full reward");
        assertEq(vault.totalClaimed(), claimedBefore + expectedReward, "vault claims updated");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // E) Unbonding enforcement
    // ─────────────────────────────────────────────────────────────────────────

    function test_unbonding_earlyRemovalReverts() public {
        uint256 stakeAmount = 10_000 ether;
        vm.deal(validator, stakeAmount);

        bytes32 validationID = _initiateRegistration(stakeAmount);
        sm.completeValidatorRegistration(0);

        // Try to remove BEFORE 14 days
        vm.warp(block.timestamp + MIN_STAKE_DURATION - 1);

        vm.prank(validator);
        vm.expectRevert();
        sm.initiateValidatorRemoval(validationID, false, 0);
    }

    function test_unbonding_exactBoundarySucceeds() public {
        uint256 stakeAmount = 10_000 ether;
        vm.deal(validator, stakeAmount);

        bytes32 validationID = _initiateRegistration(stakeAmount);
        sm.completeValidatorRegistration(0);

        // At exactly 14 days: should succeed.
        // Use forceInitiateValidatorRemoval since no uptime proof was submitted (reward = 0),
        // and initiateValidatorRemoval would revert with ValidatorIneligibleForRewards.
        vm.warp(block.timestamp + MIN_STAKE_DURATION);

        vm.prank(validator);
        sm.forceInitiateValidatorRemoval(validationID, false, 0);

        // Complete removal
        sm.completeValidatorRemoval(0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // F) Security
    // ─────────────────────────────────────────────────────────────────────────

    function test_security_stakeBelowMinReverts() public {
        uint256 tooSmall = MIN_STAKE - 1;
        vm.deal(validator, tooSmall);

        PChainOwner memory noOwner = PChainOwner({threshold: 0, addresses: new address[](0)});
        bytes memory nodeID = abi.encodePacked(bytes20(uint160(1)));
        bytes memory blsKey = new bytes(48);

        vm.prank(validator);
        vm.expectRevert();
        sm.initiateValidatorRegistration{value: tooSmall}(
            nodeID, blsKey, noOwner, noOwner, 100, MIN_STAKE_DURATION, rewarded
        );
    }

    function test_security_stakeAboveMaxReverts() public {
        uint256 tooLarge = MAX_STAKE + 1 ether;
        vm.deal(validator, tooLarge);

        PChainOwner memory noOwner = PChainOwner({threshold: 0, addresses: new address[](0)});
        bytes memory nodeID = abi.encodePacked(bytes20(uint160(1)));
        bytes memory blsKey = new bytes(48);

        vm.prank(validator);
        vm.expectRevert();
        sm.initiateValidatorRegistration{value: tooLarge}(
            nodeID, blsKey, noOwner, noOwner, 100, MIN_STAKE_DURATION, rewarded
        );
    }

    function test_security_onlyOwnerCanInitiateRemoval() public {
        uint256 stakeAmount = 10_000 ether;
        vm.deal(validator, stakeAmount);

        bytes32 validationID = _initiateRegistration(stakeAmount);
        sm.completeValidatorRegistration(0);
        vm.warp(block.timestamp + MIN_STAKE_DURATION + 1);

        // Attacker (not validator) tries to initiate removal
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert();
        sm.initiateValidatorRemoval(validationID, false, 0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────────

    function _initiateRegistration(uint256 stakeAmount) internal returns (bytes32 validationID) {
        PChainOwner memory noOwner = PChainOwner({threshold: 0, addresses: new address[](0)});
        bytes memory nodeID = abi.encodePacked(bytes20(uint160(uint256(keccak256(abi.encode(stakeAmount, block.timestamp))))));
        bytes memory blsKey = new bytes(48);

        vm.prank(validator);
        validationID = sm.initiateValidatorRegistration{value: stakeAmount}(
            nodeID, blsKey, noOwner, noOwner, 100, MIN_STAKE_DURATION, rewarded
        );
    }
}
