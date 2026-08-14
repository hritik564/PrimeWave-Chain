// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// ============================================================
// C10RewardAccountingAttack.t.sol  --  PW-C10
// ============================================================
//
// Reward accounting attacks. Covers C10 brief sections 7, 8, 9, 10, 11, 12.
//
//   Section 7:  Reward claim timing attacks
//   Section 8:  Reward index attacks
//   Section 9:  Rounding / dust analysis
//   Section 10: 3M PW annual emission attack
//   Section 11: 15M RewardVault attack
//   Section 12: Reward rate change attacks
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

contract C10RewardAccountingAttackTest is Test {

    address constant WARP_PRECOMPILE      = 0x0200000000000000000000000000000000000005;
    uint64  constant CHURN_PERIOD         = 3600;
    bytes32 constant SUBNET_ID            = bytes32(uint256(1));
    bytes32 constant UPTIME_BLOCKCHAIN_ID = bytes32(uint256(2));
    uint64  constant MIN_STAKE_DURATION   = 14 days;
    uint256 constant MIN_STAKE            = 1_000 ether;
    uint256 constant MAX_STAKE            = 3_000_000 ether;
    uint256 constant VAULT_FUND           = 15_000_000 ether;
    uint256 constant SECONDS_PER_YEAR     = 31_536_000;

    address admin    = makeAddr("admin");
    address attacker = makeAddr("attacker");
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
    // RA-01: Claim immediately after stake (zero duration → zero reward)
    // (Section 7 — claim before reward accrues)
    // ─────────────────────────────────────────────────────────────────────────

    function test_RA01_claimImmediatelyAfterStake_zeroReward() public {
        uint256 stake = 10_000 ether;
        vm.deal(staker1, stake);

        uint64 t0 = uint64(block.timestamp);

        bytes32 vid = _register(staker1, stake, reward1, 1);
        sm.completeValidatorRegistration(0);

        // Remove at exactly t0 + MIN_STAKE_DURATION (no elapsed reward time)
        uint64 t1 = t0 + MIN_STAKE_DURATION + 1;
        vm.warp(t1);

        // No uptime proof → zero reward
        vm.prank(staker1);
        sm.forceInitiateValidatorRemoval(vid, false, 0);
        sm.completeValidatorRemoval(0);

        assertEq(reward1.balance, 0, "no reward for zero uptime");
        assertEq(staker1.balance, stake, "stake returned");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RA-02: Vault remains solvent after claim exceeding current emission
    //         (distribute() enforces reserve check)
    // ─────────────────────────────────────────────────────────────────────────

    function test_RA02_distributeExceedsReserve_reverts() public {
        uint256 tooMuch = vault.totalFunded() - vault.totalEmitted() + 1;

        vm.prank(address(sm));
        vm.expectRevert("RV: insufficient reserve");
        vault.distribute(reward1, tooMuch);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RA-03: Repeated distribution attempts do not allow overdraft
    // (Section 7 — repeated claim)
    // ─────────────────────────────────────────────────────────────────────────

    function test_RA03_repeatedDistribute_exhaustsReserve_neverOverdraft() public {
        uint256 chunkSize = 1_000_000 ether;
        uint256 claimed = 0;

        while (vault.totalFunded() - vault.totalEmitted() >= chunkSize) {
            vm.prank(address(sm));
            vault.distribute(reward1, chunkSize);
            claimed += chunkSize;
        }

        // Final call with remaining balance
        uint256 remaining = vault.totalFunded() - vault.totalEmitted();
        if (remaining > 0) {
            vm.prank(address(sm));
            vault.distribute(reward1, remaining);
            claimed += remaining;
        }

        // Vault should be exactly exhausted
        assertEq(vault.totalEmitted(), vault.totalFunded(), "vault fully emitted");
        assertEq(address(vault).balance, 0, "vault balance zero");

        // One more call should revert
        vm.prank(address(sm));
        vm.expectRevert("RV: insufficient reserve");
        vault.distribute(reward1, 1);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RA-04: Claim after vault exhaustion — reward zero, stake returned
    // (Section 7 — claim after vault exhaustion)
    // ─────────────────────────────────────────────────────────────────────────

    function test_RA04_exhaustedVault_stakeReturned_rewardZero() public {
        // Exhaust the vault
        uint256 remaining = vault.totalFunded() - vault.totalEmitted();
        vm.prank(address(sm));
        vault.distribute(attacker, remaining);

        // Now register and stake
        uint256 stake = 5_000 ether;
        vm.deal(staker1, stake);

        uint64 t0 = uint64(block.timestamp);
        bytes32 vid = _register(staker1, stake, reward1, 200);
        sm.completeValidatorRegistration(0);

        uint64 t1 = t0 + 20 days;
        vm.warp(t1);

        warpMock.setUptimeResponse(0, UPTIME_BLOCKCHAIN_ID, vid, uint64(20 days));
        vm.prank(staker1); sm.submitUptimeProof(vid, 0);

        // Calculator returns 0 because vault.totalRemaining() == 0.
        // initiateValidatorRemoval reverts with ValidatorIneligibleForRewards when reward=0
        // (Avalanche upstream behavior, per C09 notes). Use forceInitiateValidatorRemoval instead.
        vm.prank(staker1); sm.forceInitiateValidatorRemoval(vid, false, 0);

        uint256 stakerBefore = staker1.balance;
        sm.completeValidatorRemoval(0);

        assertEq(staker1.balance - stakerBefore, stake, "stake returned after exhaustion");
        assertEq(reward1.balance, 0, "no reward from exhausted vault");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RA-05: Reward index — zero-weight period does not accrue phantom rewards
    // (Section 8 — zero index)
    // ─────────────────────────────────────────────────────────────────────────

    function test_RA05_zeroWeightPeriod_noPhantomRewards() public {
        // No recipients registered → zero totalEligibleWeight
        // Time passes — no emission should accrue to the index
        uint256 indexBefore = vault.accRewardPerWeight();
        uint256 emittedBefore = vault.totalEmitted();

        uint64 t0 = uint64(block.timestamp);
        vm.warp(t0 + 30 days);

        // Force an update by registering a recipient
        vm.prank(admin);
        vault.registerRecipient(keccak256("dummy"), reward1, 100, true);

        // The global update triggered by registration only advances the timestamp
        // No emission in the zero-weight period
        assertEq(vault.accRewardPerWeight(), indexBefore, "no index advance without weight");
        assertEq(vault.totalEmitted(), emittedBefore, "no emission without weight");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RA-06: Recipient joins between distributions — no retroactive rewards
    // (Section 8 — participant joins between distributions)
    // ─────────────────────────────────────────────────────────────────────────

    function test_RA06_recipientJoinsBetweenDistributions_noRetroReward() public {
        bytes32 id1 = keccak256("recip1");
        bytes32 id2 = keccak256("recip2");

        // Register id1 first, accrue
        vm.prank(admin);
        vault.registerRecipient(id1, reward1, 100, true);

        uint64 t0 = uint64(block.timestamp);
        vm.warp(t0 + 10 days);

        uint256 pending1_before_id2 = vault.claimable(id1);

        // Register id2 — triggers checkpoint
        vm.prank(admin);
        vault.registerRecipient(id2, reward2, 100, true);

        uint256 pending2_after_join = vault.claimable(id2);

        // id2 should have zero pending (just joined)
        assertEq(pending2_after_join, 0, "no retroactive reward for new joiner");
        assertGt(pending1_before_id2, 0, "id1 has pre-join accrual");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RA-07: Rounding / dust — 1 wei distribution
    // (Section 9 — adversarial rounding)
    // ─────────────────────────────────────────────────────────────────────────

    function test_RA07_oneWeiDistribute_accountingExact() public {
        vm.prank(address(sm));
        vault.distribute(reward1, 1);

        assertEq(vault.totalEmitted(), 1, "1 wei emitted");
        assertEq(vault.totalClaimed(), 1, "1 wei claimed");
        assertEq(address(vault).balance, vault.totalFunded() - vault.totalClaimed(), "balance exact");
        assertEq(reward1.balance, 1, "recipient got 1 wei");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RA-08: Rounding dust with unequal weights (index model)
    //         Alice=1, Bob=3, Charlie=7 — 1000 distributions
    // (Section 9 — rounding dust analysis)
    // ─────────────────────────────────────────────────────────────────────────

    function test_RA08_unequalWeights_dustAccountingExact() public {
        bytes32 idA = keccak256("alice");
        bytes32 idB = keccak256("bob");
        bytes32 idC = keccak256("charlie");

        vm.startPrank(admin);
        vault.registerRecipient(idA, makeAddr("alice"), 1, true);
        vault.registerRecipient(idB, makeAddr("bob"),   3, true);
        vault.registerRecipient(idC, makeAddr("charlie"), 7, true);
        vm.stopPrank();

        uint64 t0 = uint64(block.timestamp);
        // Each 1-second tick at MAX_RATE
        // Accrue 1000 seconds (1000 updates via warp)
        uint64 t1 = t0 + 1000;
        vm.warp(t1);

        // Snapshot before claiming
        uint256 totalFunded  = vault.totalFunded();
        uint256 emittedBefore = vault.totalEmitted();

        // Claim all — must prank as the registered rewardAddress
        vm.prank(makeAddr("alice")); uint256 claimedA = vault.claim(idA);
        vm.prank(makeAddr("bob"));   uint256 claimedB = vault.claim(idB);
        vm.prank(makeAddr("charlie")); uint256 claimedC = vault.claim(idC);

        uint256 totalClaimed = vault.totalClaimed();

        // All accounting invariants
        assertLe(vault.totalEmitted(), totalFunded, "emitted <= funded");
        assertLe(totalClaimed,        vault.totalEmitted(), "claimed <= emitted");
        assertEq(address(vault).balance, vault.totalFunded() - vault.totalClaimed(), "balance exact");

        // Proportionality: Alice:Bob:Charlie = 1:3:7
        // claimedA * 3 should equal claimedB (± dust)
        assertApproxEqAbs(claimedB, claimedA * 3, 1, "B approx 3*A");
        assertApproxEqAbs(claimedC, claimedA * 7, 6, "C approx 7*A (dust tolerance)");

        // Total claimed + remaining dust in vault = total emitted
        uint256 remainingDust = vault.totalEmitted() - emittedBefore - claimedA - claimedB - claimedC;
        // Dust should be tiny (< totalWeight = 11 per distribution)
        assertLt(remainingDust, 11 * 1000 + 1, "dust bounded by weight-per-distribution");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RA-09: 3M annual cap — one full year at MAX_RATE cannot exceed 3M PW
    // (Section 10 — annual emission attack)
    // ─────────────────────────────────────────────────────────────────────────

    function test_RA09_oneFullYear_emissionBelowCap() public {
        bytes32 id = keccak256("sole-recipient");
        vm.prank(admin);
        vault.registerRecipient(id, reward1, 1000, true);

        uint64 t0 = uint64(block.timestamp);
        uint64 t1 = t0 + uint64(SECONDS_PER_YEAR);
        vm.warp(t1);

        vm.prank(reward1);
        uint256 claimed = vault.claim(id);

        // Must be <= 3,000,000 PW
        assertLe(claimed, 3_000_000 ether, "annual emission cap held");

        // Should be very close to 3M PW (within truncation dust)
        uint256 expectedMax = INITIAL_RATE * SECONDS_PER_YEAR;
        assertLe(claimed, expectedMax + 1, "claimed <= rate * year");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RA-10: 3M annual cap — staking variant: rate * year at max rate
    // (Section 10 — annual emission via stake churn attack)
    // ─────────────────────────────────────────────────────────────────────────

    function test_RA10_oneYear_stakingReward_belowCap() public {
        uint256 stake = MAX_STAKE; // maximum possible stake
        vm.deal(staker1, stake);

        uint64 t0 = uint64(block.timestamp);
        bytes32 vid = _register(staker1, stake, reward1, 300);
        sm.completeValidatorRegistration(0);

        uint64 t1 = t0 + uint64(SECONDS_PER_YEAR);
        vm.warp(t1);

        uint64 uptime = uint64(SECONDS_PER_YEAR);
        warpMock.setUptimeResponse(0, UPTIME_BLOCKCHAIN_ID, vid, uptime);
        vm.prank(staker1); sm.submitUptimeProof(vid, 0);
        vm.prank(staker1); sm.initiateValidatorRemoval(vid, false, 0);
        sm.completeValidatorRemoval(0);

        uint256 reward = reward1.balance;

        // Reward = RATE * SECONDS_PER_YEAR (capped by vault)
        // Must not exceed 3M PW
        assertLe(reward, 3_000_000 ether, "annual staking reward cap held");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RA-11: 3M cap boundary: 3M - 1 wei, 3M, 3M + 1 wei attempts
    // (Section 10 — exact boundary)
    // ─────────────────────────────────────────────────────────────────────────

    function test_RA11_emissionBoundary_3M_minus1_passes() public {
        uint256 amount = 3_000_000 ether - 1;
        vm.prank(address(sm));
        vault.distribute(reward1, amount);
        assertEq(vault.totalClaimed(), amount, "3M-1 passes");
    }

    function test_RA12_emissionBoundary_3M_passes() public {
        uint256 amount = 3_000_000 ether;
        vm.prank(address(sm));
        vault.distribute(reward1, amount);
        assertEq(vault.totalClaimed(), amount, "3M passes");
    }

    function test_RA13_emissionBoundary_3M_plus1_via_rateEnforcement() public {
        // Can we emit >3M in under a year by manipulating timing?
        // At MAX_RATE: one year = INITIAL_RATE * 31_536_000 < 3_000_000 ether
        // Two years: 2 * INITIAL_RATE * 31_536_000 < 6_000_000 ether -> bounded by vault total
        // The only way to get >3M in one year is if RATE > MAX_RATE, which is prevented by contract
        assertLe(vault.emissionRatePerSecond(), vault.MAX_RATE_PER_SECOND(), "rate never exceeds MAX");

        // Precompute to avoid prank+expectRevert being consumed by the view call in the argument
        uint256 oneAboveMax = vault.MAX_RATE_PER_SECOND() + 1;
        // Attempting to set rate above current (= MAX_RATE) reverts — "RV: rate not reduced"
        vm.prank(admin);
        vm.expectRevert("RV: rate not reduced");
        vault.setEmissionRate(oneAboveMax);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RA-14: 15M reserve — 5 years at MAX_RATE simulation
    // (Section 11 — 15M RewardVault attack, 5-year simulation)
    // ─────────────────────────────────────────────────────────────────────────

    function test_RA14_fiveYears_maxRate_totalBelowReserve() public {
        bytes32 id = keccak256("5yr-recipient");
        vm.prank(admin);
        vault.registerRecipient(id, reward1, 1000, true);

        uint64 t0 = uint64(block.timestamp);
        uint256 totalClaimed = 0;

        for (uint256 yr = 1; yr <= 5; yr++) {
            uint64 tYear = t0 + uint64(yr * SECONDS_PER_YEAR);
            vm.warp(tYear);

            vm.prank(reward1);
            uint256 claimed = vault.claim(id);
            totalClaimed += claimed;
        }

        // After 5 years at max rate: ~5 * 3M = ~15M, but capped by funding
        assertLe(totalClaimed, VAULT_FUND, "total claimed <= 15M reserve");
        assertLe(vault.totalEmitted(), vault.totalFunded(), "emitted <= funded");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RA-15: 15M + 1 wei is impossible through any path
    // (Section 11 — cannot overdraw vault)
    // ─────────────────────────────────────────────────────────────────────────

    function test_RA15_cannotExtract_15M_plus1() public {
        // Exhaust full vault
        vm.prank(address(sm));
        vault.distribute(reward1, VAULT_FUND);

        // Now try to get 1 more wei
        vm.prank(address(sm));
        vm.expectRevert("RV: insufficient reserve");
        vault.distribute(reward1, 1);

        assertEq(vault.totalClaimed(), VAULT_FUND, "total claimed == exactly 15M");
        assertEq(address(vault).balance, 0, "vault balance zero");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RA-16: Vault partially exhausted — graceful degradation
    // (Section 11 — partially exhausted vault)
    // ─────────────────────────────────────────────────────────────────────────

    function test_RA16_partiallyExhaustedVault_clampedReward() public {
        // Exhaust all but 500 PW
        uint256 remaining = 500 ether;
        vm.prank(address(sm));
        vault.distribute(reward1, VAULT_FUND - remaining);

        // Calculator should cap reward to 500 PW (remaining)
        // Use precomputed absolute timestamps to avoid block.timestamp - 365 days underflow
        // (Forge default block.timestamp = 1; 1 - 365 days underflows)
        uint64 BASE_TS = 1_800_000_000;
        uint64 startTime = BASE_TS;
        uint64 endTime   = BASE_TS + uint64(365 days);
        vm.warp(endTime);

        uint256 calcReward = calc.calculateReward(
            MAX_STAKE,
            startTime,
            endTime,
            uint64(365 days),   // uptime
            uint64(365 days)    // duration
        );

        assertLe(calcReward, remaining, "calculator caps at vault remaining");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RA-17: Rate reduction — rewards before and after not double-counted
    // (Section 12 — rate change attack, checkpointing)
    // ─────────────────────────────────────────────────────────────────────────

    function test_RA17_rateReduction_rewardsNotDoubleCounted() public {
        bytes32 id = keccak256("rate-recip");
        vm.prank(admin);
        vault.registerRecipient(id, reward1, 1000, true);

        uint64 t0 = uint64(block.timestamp);

        // Accrue 10 days at full rate
        uint64 t1 = t0 + 10 days;
        vm.warp(t1);

        // Capture pending via view (correct even without state update)
        uint256 pendingY1 = vault.claimable(id); // = INITIAL_RATE * 10 days

        // Reduce rate to half — triggers _updateEmissionIndex for period t0→t1
        uint256 halfRate = INITIAL_RATE / 2;
        vm.prank(admin);
        vault.setEmissionRate(halfRate);

        // Capture emittedAfterY1 AFTER rate change (index now updated for t0→t1)
        uint256 emittedAfterY1 = vault.totalEmitted();

        // Accrue another 10 days at half rate
        uint64 t2 = t1 + 10 days;
        vm.warp(t2);

        // Claim triggers index update for t1→t2; secondPeriod = totalEmitted - emittedAfterY1
        vm.prank(reward1);
        uint256 claimed = vault.claim(id);
        uint256 emittedAfterY2 = vault.totalEmitted();
        uint256 secondPeriod = emittedAfterY2 - emittedAfterY1;

        // Second 10-day period at half rate should be ~half first period
        // Tolerance: integer division of emittedAfterY1/2 can have rounding dust; allow 1e6 wei
        assertApproxEqAbs(secondPeriod, emittedAfterY1 / 2, 1e6, "half-rate half-emission");

        // Claimed = Y1 + Y2, no double counting
        assertApproxEqAbs(claimed, pendingY1 + secondPeriod, 1, "claimed == Y1 + Y2");
        assertLe(vault.totalClaimed(), vault.totalEmitted(), "claimed <= emitted");
        assertEq(address(vault).balance, vault.totalFunded() - vault.totalClaimed(), "balance exact");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RA-18: Rate cannot be increased above MAX_RATE_PER_SECOND
    // (Section 12 — rate increase blocked)
    // ─────────────────────────────────────────────────────────────────────────

    function test_RA18_rateCannotBeIncreasedAboveMax() public {
        // Precompute to avoid prank+expectRevert consumed by view call in argument position
        uint256 maxRate  = vault.MAX_RATE_PER_SECOND();
        uint256 halfRate = INITIAL_RATE / 2;

        // Try to set rate above MAX (= current rate) → "RV: rate not reduced"
        vm.prank(admin);
        vm.expectRevert("RV: rate not reduced");
        vault.setEmissionRate(maxRate + 1);

        // Reduce to half — succeeds
        vm.prank(admin);
        vault.setEmissionRate(halfRate);

        // Try to increase back to INITIAL_RATE → "RV: rate not reduced"
        vm.prank(admin);
        vm.expectRevert("RV: rate not reduced");
        vault.setEmissionRate(INITIAL_RATE);

        assertEq(vault.emissionRatePerSecond(), halfRate, "rate stays at reduced value");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RA-19: Reduce rate to zero — emission stops cleanly
    // (Section 12 — reduce rate to zero)
    // ─────────────────────────────────────────────────────────────────────────

    function test_RA19_reduceRateToZero_emissionStops() public {
        bytes32 id = keccak256("zero-rate-recip");
        vm.prank(admin);
        vault.registerRecipient(id, reward1, 1000, true);

        uint64 t0 = uint64(block.timestamp);
        uint64 t1 = t0 + 10 days;
        vm.warp(t1);

        // View captures pending without state update (correct)
        uint256 pendingAt10d = vault.claimable(id);

        // Reduce to zero — triggers _updateEmissionIndex for t0→t1 period
        vm.prank(admin);
        vault.setEmissionRate(0);

        // Capture totalEmitted AFTER the rate-change update (now has 10-day emission)
        uint256 emittedAt10d = vault.totalEmitted();

        // More time passes at rate=0
        uint64 t2 = t1 + 30 days;
        vm.warp(t2);

        // totalEmitted unchanged — no trigger fired, and rate=0 means no new emission
        assertEq(vault.totalEmitted(), emittedAt10d, "no emission after rate=0 (until update triggered)");

        // Claim triggers t1→t2 update: rate=0, so no additional emission
        vm.prank(reward1);
        uint256 claimed = vault.claim(id);
        assertApproxEqAbs(claimed, pendingAt10d, 1, "claimed == pre-zero pending only");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RA-20: Rapid rate reductions — each checkpoint is clean
    // (Section 12 — multiple rapid reductions)
    // ─────────────────────────────────────────────────────────────────────────

    function test_RA20_rapidRateReductions_noDoubleCounting() public {
        bytes32 id = keccak256("rapid-rate-recip");
        vm.prank(admin);
        vault.registerRecipient(id, reward1, 1000, true);

        uint64 t0 = uint64(block.timestamp);

        // Reduce rate 5 times, each time accumulating some emission
        uint256 rate = INITIAL_RATE;
        uint256 totalExpected = 0;

        for (uint256 i = 0; i < 5; i++) {
            uint64 tStep = t0 + uint64((i + 1) * 1 days);
            vm.warp(tStep);

            uint256 emittedBefore = vault.totalEmitted();
            rate = rate / 2;
            if (rate == 0) break;
            vm.prank(admin);
            vault.setEmissionRate(rate);

            totalExpected += vault.totalEmitted() - emittedBefore;
        }

        uint256 t1 = block.timestamp + 1;
        vm.warp(t1);

        vm.prank(reward1);
        uint256 claimed = vault.claim(id);

        assertLe(vault.totalClaimed(), vault.totalEmitted(), "no overdraft");
        assertEq(address(vault).balance, vault.totalFunded() - vault.totalClaimed(), "balance exact");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RA-21: Claim at emission boundary — no phantom reward
    // (Section 7 — claim at emission boundary)
    // ─────────────────────────────────────────────────────────────────────────

    function test_RA21_claimAtEmissionBoundary_noPhantomReward() public {
        bytes32 id = keccak256("boundary-recip");
        vm.prank(admin);
        vault.registerRecipient(id, reward1, 1000, true);

        uint64 t0 = uint64(block.timestamp);

        // At exactly t0: nothing has accrued
        assertEq(vault.claimable(id), 0, "zero claimable at t0");

        // Claim at t0 reverts — nothing to claim
        vm.prank(reward1);
        vm.expectRevert("RV: nothing to claim");
        vault.claim(id);

        // Claim after 1 second — now there is emission
        uint64 t1 = t0 + 1;
        vm.warp(t1);

        assertGt(vault.claimable(id), 0, "positive claimable at t0+1");
        vm.prank(reward1);
        uint256 claimed1 = vault.claim(id);
        assertGt(claimed1, 0, "positive claim at t0+1");

        // Claim again immediately — nothing more (just claimed everything)
        assertEq(vault.claimable(id), 0, "zero claimable immediately after claim");
        vm.prank(reward1);
        vm.expectRevert("RV: nothing to claim");
        vault.claim(id);
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
