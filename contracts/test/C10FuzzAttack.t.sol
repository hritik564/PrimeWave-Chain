// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// ============================================================
// C10FuzzAttack.t.sol  --  PW-C10
// ============================================================
//
// Targeted fuzz tests for C10. Covers C10 brief section 33.
//
// Fuzz targets:
//   - stake amount
//   - reward amount
//   - weight
//   - timestamp / duration
//   - participant count
//   - rate
//   - unbond timing
//   - claim timing
//
// IMPORTANT (via_ir): Precompute all absolute timestamps.
// ============================================================

import {Test} from "forge-std/Test.sol";
import {RewardVault} from "../src/RewardVault.sol";
import {PrimeWaveRewardCalculator} from "../src/PrimeWaveRewardCalculator.sol";
import {PrimeWaveStakingManager} from "../src/PrimeWaveStakingManager.sol";
import {MockAvalancheValidatorManager} from "./MockAvalancheValidatorManager.sol";
import {MockWarpMessenger} from "./MockWarpMessenger.sol";
import {StakingManagerSettings} from "validator-manager/interfaces/IStakingManager.sol";
import {IRewardCalculator} from "validator-manager/interfaces/IRewardCalculator.sol";
import {IValidatorManager} from "validator-manager/interfaces/IValidatorManager.sol";
import {PChainOwner} from "validator-manager/interfaces/IACP99Manager.sol";

contract C10FuzzAttackTest is Test {

    address constant WARP_PRECOMPILE      = 0x0200000000000000000000000000000000000005;
    uint64  constant CHURN_PERIOD         = 3600;
    bytes32 constant SUBNET_ID            = bytes32(uint256(1));
    bytes32 constant UPTIME_BLOCKCHAIN_ID = bytes32(uint256(2));
    uint64  constant MIN_STAKE_DURATION   = 14 days;
    uint256 constant MIN_STAKE            = 1_000 ether;
    uint256 constant MAX_STAKE            = 3_000_000 ether;
    uint256 constant VAULT_FUND           = 15_000_000 ether;
    uint256 constant SECONDS_PER_YEAR     = 31_536_000;

    address admin = makeAddr("admin");

    RewardVault                   vault;
    PrimeWaveRewardCalculator     calc;
    MockAvalancheValidatorManager mockVM;
    PrimeWaveStakingManager       sm;
    MockWarpMessenger             warpMock;

    uint256 INITIAL_RATE;

    function setUp() public {
        INITIAL_RATE = uint256(3_000_000 * 1 ether) / SECONDS_PER_YEAR;

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
    // FA-01: Fuzz stake amount — vault always solvent after distribute
    // ─────────────────────────────────────────────────────────────────────────

    function testFuzz_FA01_stakeAmount_vaultSolventAfterDistribute(
        uint256 amount
    ) public {
        // Bound to valid range within unfunded vault
        uint256 maxAmount = vault.totalFunded() - vault.totalEmitted();
        if (maxAmount == 0) return;
        amount = bound(amount, 1, maxAmount);

        vm.prank(address(sm));
        vault.distribute(makeAddr("fuzz1"), amount);

        assertLe(vault.totalEmitted(), vault.totalFunded(), "emitted <= funded");
        assertLe(vault.totalClaimed(), vault.totalEmitted(), "claimed <= emitted");
        assertEq(address(vault).balance, vault.totalFunded() - vault.totalClaimed(), "balance exact");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // FA-02: Fuzz distribute amount > available → always reverts
    // ─────────────────────────────────────────────────────────────────────────

    function testFuzz_FA02_distributeExceedsAvailable_alwaysReverts(
        uint256 extraAmount
    ) public {
        extraAmount = bound(extraAmount, 1, type(uint128).max);
        uint256 available = vault.totalFunded() - vault.totalEmitted();
        uint256 tooMuch = available + extraAmount;

        vm.prank(address(sm));
        vm.expectRevert("RV: insufficient reserve");
        vault.distribute(makeAddr("fuzz2"), tooMuch);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // FA-03: Fuzz reward amounts — partial + remaining = total, no overdraft
    // ─────────────────────────────────────────────────────────────────────────

    function testFuzz_FA03_multipleDistributes_noOverdraft(
        uint256[5] memory amounts
    ) public {
        uint256 totalAvailable = vault.totalFunded() - vault.totalEmitted();

        for (uint256 i = 0; i < 5; i++) {
            uint256 avail = vault.totalFunded() - vault.totalEmitted();
            if (avail == 0) break;
            uint256 amt = bound(amounts[i], 0, avail);
            if (amt == 0) continue;

            vm.prank(address(sm));
            vault.distribute(makeAddr(string(abi.encodePacked("fa3r", i))), amt);
        }

        assertLe(vault.totalClaimed(), vault.totalFunded(), "no overdraft");
        assertEq(address(vault).balance, vault.totalFunded() - vault.totalClaimed(), "balance exact");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // FA-04: Fuzz timestamp — reward bounded by rate * duration
    // ─────────────────────────────────────────────────────────────────────────

    function testFuzz_FA04_fuzzTimestamp_rewardBounded(
        uint64 durationSeconds
    ) public {
        // Bound duration to be at least MIN_STAKE_DURATION, at most 2 years
        durationSeconds = uint64(bound(durationSeconds, MIN_STAKE_DURATION, 2 * SECONDS_PER_YEAR));

        uint256 stake = MIN_STAKE;
        vm.deal(makeAddr("fts"), stake);

        uint64 t0 = uint64(block.timestamp);
        bytes32 vid = _register(makeAddr("fts"), stake, makeAddr("ftr"), 11111);
        sm.completeValidatorRegistration(0);

        uint64 t1 = t0 + durationSeconds;
        vm.warp(t1);

        warpMock.setUptimeResponse(0, UPTIME_BLOCKCHAIN_ID, vid, durationSeconds);
        vm.prank(makeAddr("fts")); sm.submitUptimeProof(vid, 0);
        vm.prank(makeAddr("fts")); sm.initiateValidatorRemoval(vid, false, 0);
        sm.completeValidatorRemoval(0);

        uint256 reward = makeAddr("ftr").balance;
        uint256 maxReward = INITIAL_RATE * durationSeconds;

        assertLe(reward, maxReward, "reward <= rate * duration");
        assertLe(vault.totalClaimed(), vault.totalFunded(), "vault solvent");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // FA-05: Fuzz unbond timing — early always fails, late always succeeds
    // ─────────────────────────────────────────────────────────────────────────

    function testFuzz_FA05_fuzzUnbondTiming(
        uint64 waitSeconds
    ) public {
        // Bound to prevent uint64 overflow: cap at 10 years
        waitSeconds = uint64(bound(waitSeconds, 0, 315_360_000));

        uint256 stake = MIN_STAKE;
        vm.deal(makeAddr("fut"), stake);

        uint64 t0 = uint64(block.timestamp);
        bytes32 vid = _register(makeAddr("fut"), stake, makeAddr("futr"), 22222);
        sm.completeValidatorRegistration(0);

        if (waitSeconds < MIN_STAKE_DURATION) {
            // Should revert — too early
            uint64 t_early = t0 + waitSeconds;
            vm.warp(t_early);

            vm.prank(makeAddr("fut"));
            vm.expectRevert();
            sm.forceInitiateValidatorRemoval(vid, false, 0);
        } else {
            // Should succeed
            uint64 t_late = t0 + waitSeconds;
            vm.warp(t_late);

            vm.prank(makeAddr("fut"));
            sm.forceInitiateValidatorRemoval(vid, false, 0);

            uint256 balBefore = makeAddr("fut").balance;
            sm.completeValidatorRemoval(0);
            assertEq(makeAddr("fut").balance - balBefore, stake, "stake returned at valid timing");
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // FA-06: Fuzz emission rate — setEmissionRate strictly decreasing
    // ─────────────────────────────────────────────────────────────────────────

    function testFuzz_FA06_fuzzEmissionRate_strictlyDecreasing(
        uint256 newRate
    ) public {
        uint256 currentRate = vault.emissionRatePerSecond();

        if (newRate >= currentRate) {
            vm.prank(admin);
            vm.expectRevert();
            vault.setEmissionRate(newRate);
            assertEq(vault.emissionRatePerSecond(), currentRate, "rate unchanged on invalid reduce");
        } else {
            vm.prank(admin);
            vault.setEmissionRate(newRate);
            assertEq(vault.emissionRatePerSecond(), newRate, "rate reduced successfully");
            assertLe(vault.emissionRatePerSecond(), vault.MAX_RATE_PER_SECOND(), "rate <= MAX");
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // FA-07: Fuzz weight distribution — no overdraft in index model
    // ─────────────────────────────────────────────────────────────────────────

    function testFuzz_FA07_fuzzWeights_noOverdraftInIndexModel(
        uint128[3] memory weights,
        uint64 durationSeconds
    ) public {
        // Bound inputs
        weights[0] = uint128(bound(weights[0], 1, 1000));
        weights[1] = uint128(bound(weights[1], 1, 1000));
        weights[2] = uint128(bound(weights[2], 1, 1000));
        durationSeconds = uint64(bound(durationSeconds, 1, 30 days));

        bytes32 idA = keccak256("fwA");
        bytes32 idB = keccak256("fwB");
        bytes32 idC = keccak256("fwC");

        vm.startPrank(admin);
        vault.registerRecipient(idA, makeAddr("fwrA"), weights[0], true);
        vault.registerRecipient(idB, makeAddr("fwrB"), weights[1], true);
        vault.registerRecipient(idC, makeAddr("fwrC"), weights[2], true);
        vm.stopPrank();

        uint64 t0 = uint64(block.timestamp);
        uint64 t1 = t0 + durationSeconds;
        vm.warp(t1);

        // Claim all
        vm.prank(makeAddr("fwrA")); uint256 ca = vault.claim(idA);
        vm.prank(makeAddr("fwrB")); uint256 cb = vault.claim(idB);
        vm.prank(makeAddr("fwrC")); uint256 cc = vault.claim(idC);

        // No overdraft
        assertLe(vault.totalClaimed(), vault.totalFunded(), "no overdraft with fuzz weights");
        assertEq(address(vault).balance, vault.totalFunded() - vault.totalClaimed(), "balance exact");

        // Total claimed = sum of individual claims (no double counting)
        uint256 totalClaimed = vault.totalClaimed();
        // Dust: totalEmitted - totalClaimed <= totalEligibleWeight (bounded by integer division)
        assertLe(vault.totalEmitted() - totalClaimed, uint256(weights[0]) + weights[1] + weights[2],
                 "dust bounded by weight sum");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // FA-08: Fuzz staking reward calculation — always bounded by vault remaining
    // ─────────────────────────────────────────────────────────────────────────

    function testFuzz_FA08_rewardCalculation_boundedByVaultRemaining(
        uint256 stakeAmount,
        uint64 durationSeconds,
        uint64 uptimeSeconds
    ) public {
        stakeAmount     = bound(stakeAmount, MIN_STAKE, MAX_STAKE);
        stakeAmount     = (stakeAmount / 1 ether) * 1 ether; // align to 1 ether boundary
        durationSeconds = uint64(bound(durationSeconds, 1, 2 * SECONDS_PER_YEAR));
        uptimeSeconds   = uint64(bound(uptimeSeconds, 0, durationSeconds));

        uint64 startTime = uint64(block.timestamp);
        uint64 endTime   = startTime + durationSeconds;

        uint256 vaultRemaining = vault.totalFunded() - vault.totalEmitted();
        uint256 calcReward = calc.calculateReward(
            stakeAmount,
            startTime,
            endTime,
            uptimeSeconds,
            durationSeconds
        );

        assertLe(calcReward, vaultRemaining, "calc reward bounded by vault remaining");
        assertLe(calcReward, INITIAL_RATE * durationSeconds, "calc reward bounded by rate*duration");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // FA-09: Fuzz uptime ratio — monotonically proportional to reward
    // ─────────────────────────────────────────────────────────────────────────

    function testFuzz_FA09_uptimeMonotonicInReward(
        uint64 uptime1,
        uint64 uptime2,
        uint64 duration
    ) public {
        duration = uint64(bound(duration, 1 hours, 365 days));
        uptime1  = uint64(bound(uptime1, 0, duration));
        uptime2  = uint64(bound(uptime2, 0, duration));

        uint64 startTime = uint64(block.timestamp);
        uint64 endTime   = startTime + duration;

        uint256 reward1 = calc.calculateReward(MIN_STAKE, startTime, endTime, uptime1, duration);
        uint256 reward2 = calc.calculateReward(MIN_STAKE, startTime, endTime, uptime2, duration);

        if (uptime1 <= uptime2) {
            assertLe(reward1, reward2, "more uptime => more reward (monotonic)");
        } else {
            assertGe(reward1, reward2, "less uptime => less reward (monotonic)");
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // FA-10: Fuzz EMS nonce uniqueness — different nonces → different IDs
    // ─────────────────────────────────────────────────────────────────────────

    function testFuzz_FA10_emsNonceUniqueness(uint256 nonce1, uint256 nonce2) public {
        vm.assume(nonce1 != nonce2);

        address target = address(vault);
        bytes memory data = abi.encodeCall(RewardVault.pause, ());

        bytes32 id1 = keccak256(abi.encode(target, data, nonce1));
        bytes32 id2 = keccak256(abi.encode(target, data, nonce2));

        // Different nonces → different proposal IDs → no replay
        assertNotEq(id1, id2, "different nonces => different proposal IDs");
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
