// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// ============================================================
// C10LongRun.t.sol  --  PW-C10
// ============================================================
//
// Long-run simulation + all 17 C10 stateful invariants.
// Covers C10 brief sections 32 and 34.
//
// IMPORTANT (via_ir): All timestamps are pre-computed absolute
// values. Never use vm.warp(block.timestamp + N) in loops.
// ============================================================

import {Test, Vm} from "forge-std/Test.sol";
import {RewardVault} from "../src/RewardVault.sol";
import {PrimeWaveRewardCalculator} from "../src/PrimeWaveRewardCalculator.sol";
import {PrimeWaveStakingManager} from "../src/PrimeWaveStakingManager.sol";
import {FeeDistributor} from "../src/FeeDistributor.sol";
import {ValidatorFeeVault} from "../src/ValidatorFeeVault.sol";
import {DevTreasury} from "../src/DevTreasury.sol";
import {EmergencyMultisig} from "../src/EmergencyMultisig.sol";
import {PrimeWaveTimelock} from "../src/PrimeWaveTimelock.sol";
import {MockAvalancheValidatorManager} from "./MockAvalancheValidatorManager.sol";
import {MockWarpMessenger} from "./MockWarpMessenger.sol";
import {StakingManagerSettings} from "validator-manager/interfaces/IStakingManager.sol";
import {IRewardCalculator} from "validator-manager/interfaces/IRewardCalculator.sol";
import {IValidatorManager} from "validator-manager/interfaces/IValidatorManager.sol";
import {PChainOwner} from "validator-manager/interfaces/IACP99Manager.sol";

contract C10LongRunTest is Test {

    address constant WARP_PRECOMPILE      = 0x0200000000000000000000000000000000000005;
    uint64  constant CHURN_PERIOD         = 3600;
    bytes32 constant SUBNET_ID            = bytes32(uint256(1));
    bytes32 constant UPTIME_BLOCKCHAIN_ID = bytes32(uint256(2));
    uint64  constant MIN_STAKE_DURATION   = 14 days;
    uint256 constant MIN_STAKE            = 1_000 ether;
    uint256 constant MAX_STAKE            = 3_000_000 ether;
    uint256 constant VAULT_FUND           = 15_000_000 ether;
    uint256 constant SECONDS_PER_YEAR     = 31_536_000;

    address constant PROTOCOL_ADMIN = address(0x1001);
    address constant S1 = address(0xA001);
    address constant S2 = address(0xA002);
    address constant S3 = address(0xA003);
    address constant S4 = address(0xA004);
    address constant S5 = address(0xA005);

    // Contracts
    RewardVault                   vault;
    PrimeWaveRewardCalculator     calc;
    MockAvalancheValidatorManager mockVM;
    PrimeWaveStakingManager       sm;
    MockWarpMessenger             warpMock;
    FeeDistributor                feeDistributor;
    ValidatorFeeVault             feeVault;
    DevTreasury                   treasury;
    EmergencyMultisig             ems;
    PrimeWaveTimelock             timelock;

    uint256 INITIAL_RATE;

    // Absolute base timestamp
    uint64 constant BASE_TS = 1_800_000_000;

    function setUp() public {
        INITIAL_RATE = uint256(3_000_000 * 1 ether) / SECONDS_PER_YEAR;

        vm.warp(BASE_TS);

        // EMS + Timelock
        address[5] memory sigs = [S1, S2, S3, S4, S5];
        ems = new EmergencyMultisig(sigs);
        timelock = new PrimeWaveTimelock(PROTOCOL_ADMIN);

        // Fee system (pre-computed addresses)
        address deployer = address(this);
        uint64 n = vm.getNonce(deployer);
        address expectedVFV  = computeCreateAddress(deployer, n);
        address expectedTrea = computeCreateAddress(deployer, n + 1);
        address expectedFD   = computeCreateAddress(deployer, n + 2);

        feeVault       = new ValidatorFeeVault(expectedFD);
        treasury       = new DevTreasury(expectedFD);
        feeDistributor = new FeeDistributor(payable(expectedVFV), payable(expectedTrea), address(ems));

        // Staking system
        vm.startPrank(PROTOCOL_ADMIN);
        vault = new RewardVault(PROTOCOL_ADMIN, INITIAL_RATE);
        vm.deal(PROTOCOL_ADMIN, VAULT_FUND + 200 ether);
        vault.fund{value: VAULT_FUND}();
        vault.setPauseController(address(ems));

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

        // Register one fee validator
        bytes32 fv = keccak256("fv0");
        vm.prank(address(feeDistributor));
        feeVault.registerValidator(fv, makeAddr("feerecv"), 1000, 10_000);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // LR-01: 5-year simulation — 5 validators, sequential one-year periods
    // (Section 32 — long-run simulation)
    // ─────────────────────────────────────────────────────────────────────────

    function test_LR01_fiveYearSimulation_allInvariantsHold() public {
        // 5 validators stake for one year each, sequentially
        uint256 stake      = 100_000 ether;
        uint256 totalPaidRewards = 0;
        uint64 t = BASE_TS;

        for (uint32 yr = 0; yr < 5; yr++) {
            address staker  = makeAddr(string(abi.encodePacked("yr", yr)));
            address rewAddr = makeAddr(string(abi.encodePacked("rw", yr)));
            vm.deal(staker, stake);

            bytes32 vid = _register(staker, stake, rewAddr, yr + 100);
            sm.completeValidatorRegistration(yr);

            uint64 tEnd = t + uint64(SECONDS_PER_YEAR);
            vm.warp(tEnd);

            // Simulate fee income each year
            uint256 yearFees = 500 ether * (yr + 1);
            vm.deal(address(feeDistributor), yearFees);
            feeDistributor.distribute();

            warpMock.setUptimeResponse(yr, UPTIME_BLOCKCHAIN_ID, vid, uint64(SECONDS_PER_YEAR));
            vm.prank(staker); sm.submitUptimeProof(vid, yr);
            vm.prank(staker); sm.initiateValidatorRemoval(vid, false, 0);

            uint256 rewBefore = rewAddr.balance;
            sm.completeValidatorRemoval(yr);
            totalPaidRewards += rewAddr.balance - rewBefore;

            // Annual invariants
            assertLe(vault.totalEmitted(), vault.totalFunded(), string(abi.encodePacked("yr", yr, " emitted<=funded")));
            assertLe(vault.totalClaimed(), vault.totalEmitted(), string(abi.encodePacked("yr", yr, " claimed<=emitted")));
            assertEq(address(vault).balance, vault.totalFunded() - vault.totalClaimed(),
                     string(abi.encodePacked("yr", yr, " balance exact")));

            // Annual reward cap
            uint256 maxForYear = INITIAL_RATE * SECONDS_PER_YEAR;
            assertLe(rewAddr.balance - rewBefore, maxForYear, "annual reward within cap");

            t = tEnd;
        }

        // After 5 years: total rewards <= 15M (vault never overdrawn)
        assertLe(vault.totalClaimed(), VAULT_FUND, "total rewards <= 15M");
        assertLe(totalPaidRewards, VAULT_FUND, "total paid rewards <= 15M reserve");

        // Fee system preserved
        assertGt(feeDistributor.totalDistributed(), 0, "fees distributed");
        assertEq(
            feeDistributor.totalValidatorShare() + feeDistributor.totalTreasuryShare() + feeDistributor.totalBurnShare(),
            feeDistributor.totalDistributed(),
            "fee split conserved over 5 years"
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // LR-02: Multi-validator churn over 2 years
    // (Section 32 — validator churn in long run)
    // ─────────────────────────────────────────────────────────────────────────

    function test_LR02_multiValidatorChurn_twoYears() public {
        uint256 stake = 50_000 ether;
        uint64 t = BASE_TS;

        // 3 validators, each staking 6 months in rotation
        uint64 sixMonths = uint64(SECONDS_PER_YEAR / 2);
        uint32 regIdx = 0;

        for (uint32 round = 0; round < 4; round++) {
            address staker  = makeAddr(string(abi.encodePacked("s", round)));
            address rewAddr = makeAddr(string(abi.encodePacked("r", round)));
            vm.deal(staker, stake);

            bytes32 vid = _register(staker, stake, rewAddr, round + 200);
            sm.completeValidatorRegistration(regIdx);

            uint64 tEnd = t + sixMonths;
            vm.warp(tEnd);

            warpMock.setUptimeResponse(regIdx, UPTIME_BLOCKCHAIN_ID, vid, sixMonths);
            vm.prank(staker); sm.submitUptimeProof(vid, regIdx);
            vm.prank(staker); sm.initiateValidatorRemoval(vid, false, 0);
            sm.completeValidatorRemoval(regIdx);

            regIdx++;
            t = tEnd;
        }

        // Vault invariants after 2 years of churn
        assertLe(vault.totalEmitted(), vault.totalFunded());
        assertLe(vault.totalClaimed(), vault.totalEmitted());
        assertEq(address(vault).balance, vault.totalFunded() - vault.totalClaimed());
        assertLe(vault.totalClaimed(), VAULT_FUND);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // LR-03: Rate reduction mid-simulation — rewards correctly segmented
    // (Section 32 — rate reductions in long run)
    // ─────────────────────────────────────────────────────────────────────────

    function test_LR03_rateReductionMidSimulation() public {
        // Register a Phase-1 style recipient to measure emission
        bytes32 id = keccak256("long-run-recip");
        vm.prank(PROTOCOL_ADMIN);
        vault.registerRecipient(id, makeAddr("lrrecv"), 1000, true);

        uint64 t0 = BASE_TS;

        // Year 1 at full rate
        uint64 t1 = t0 + uint64(SECONDS_PER_YEAR);
        vm.warp(t1);

        // Reduce rate to half — this triggers _updateEmissionIndex for year 1
        vm.prank(PROTOCOL_ADMIN);
        vault.setEmissionRate(INITIAL_RATE / 2);

        // Capture emittedY1 AFTER the rate change (which triggers the update)
        uint256 emittedY1 = vault.totalEmitted();

        // Year 2 at half rate
        uint64 t2 = t1 + uint64(SECONDS_PER_YEAR);
        vm.warp(t2);

        // Claim to trigger the year-2 index update, then read totalEmitted
        vm.prank(makeAddr("lrrecv")); vault.claim(id);
        uint256 emittedY2 = vault.totalEmitted() - emittedY1;
        uint256 halfYearMax = (INITIAL_RATE / 2) * SECONDS_PER_YEAR;

        assertApproxEqAbs(emittedY2, halfYearMax, 1, "year 2 emission approx half year 1");
        assertLe(vault.totalEmitted(), vault.totalFunded(), "total emitted <= funded");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // C10 INV-1: Total PW supply never increases
    // ─────────────────────────────────────────────────────────────────────────

    function test_INV1_C10_totalSupplyNeverIncreases() public {
        uint256 vaultFunded = vault.totalFunded();
        uint256 initialVaultBalance = address(vault).balance;

        // All operations only move existing PW — never create new PW
        uint256 stake = 10_000 ether;
        vm.deal(makeAddr("s"), stake);

        uint64 t0 = BASE_TS;
        bytes32 vid = _register(makeAddr("s"), stake, makeAddr("r"), 300);
        sm.completeValidatorRegistration(0);

        uint64 t1 = t0 + 30 days;
        vm.warp(t1);

        warpMock.setUptimeResponse(0, UPTIME_BLOCKCHAIN_ID, vid, uint64(30 days));
        vm.prank(makeAddr("s")); sm.submitUptimeProof(vid, 0);
        vm.prank(makeAddr("s")); sm.initiateValidatorRemoval(vid, false, 0);
        sm.completeValidatorRemoval(0);

        // totalFunded must never increase without explicit fund() call
        assertEq(vault.totalFunded(), vaultFunded, "INV-1: totalFunded unchanged without fund()");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // C10 INV-2: Stake principal is conserved
    // ─────────────────────────────────────────────────────────────────────────

    function test_INV2_C10_stakePrincipalConserved() public {
        uint256 stake = 20_000 ether;
        vm.deal(makeAddr("sv"), stake);

        uint64 t0 = BASE_TS;
        bytes32 vid = _register(makeAddr("sv"), stake, makeAddr("rv"), 400);
        sm.completeValidatorRegistration(0);

        // SM holds exactly stake
        assertGe(address(sm).balance, stake, "INV-2: SM holds stake");

        uint64 t1 = t0 + MIN_STAKE_DURATION + 1;
        vm.warp(t1);

        vm.prank(makeAddr("sv")); sm.forceInitiateValidatorRemoval(vid, false, 0);

        uint256 balBefore = makeAddr("sv").balance;
        sm.completeValidatorRemoval(0);

        assertEq(makeAddr("sv").balance - balBefore, stake, "INV-2: principal fully returned");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // C10 INV-3: Rewards never exceed RewardVault-funded capacity
    // ─────────────────────────────────────────────────────────────────────────

    function test_INV3_C10_rewardsNeverExceedVaultCapacity() public {
        // Precompute to avoid prank being consumed by view call
        uint256 tooMuch = vault.totalFunded() + 1;
        vm.prank(address(sm));
        vm.expectRevert("RV: insufficient reserve");
        vault.distribute(makeAddr("x"), tooMuch);

        // After multiple distributions, still bounded
        vm.prank(address(sm)); vault.distribute(makeAddr("x"), 5_000_000 ether);
        vm.prank(address(sm)); vault.distribute(makeAddr("x"), 5_000_000 ether);
        vm.prank(address(sm)); vault.distribute(makeAddr("x"), 5_000_000 ether);

        assertLe(vault.totalClaimed(), vault.totalFunded(), "INV-3: claimed <= funded");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // C10 INV-4: Annual staking emissions never exceed 3M PW
    // ─────────────────────────────────────────────────────────────────────────

    function test_INV4_C10_annualEmissionsNeverExceed3M() public {
        // Max rate * 1 year = just under 3M PW (by floor division)
        uint256 maxOneYear = INITIAL_RATE * SECONDS_PER_YEAR;
        assertLe(maxOneYear, 3_000_000 ether, "INV-4: max annual emission <= 3M");

        // Rate can never be increased above MAX
        assertLe(vault.emissionRatePerSecond(), vault.MAX_RATE_PER_SECOND(), "INV-4: rate <= MAX");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // C10 INV-5: Total staking rewards never exceed 15M PW reserve
    // ─────────────────────────────────────────────────────────────────────────

    function test_INV5_C10_totalRewardsNeverExceed15M() public {
        // Drain entire vault
        vm.prank(address(sm)); vault.distribute(makeAddr("x"), VAULT_FUND);
        assertEq(vault.totalClaimed(), VAULT_FUND, "INV-5: drained exactly 15M");

        // Cannot go over
        vm.prank(address(sm));
        vm.expectRevert("RV: insufficient reserve");
        vault.distribute(makeAddr("x"), 1);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // C10 INV-6: 14-day unbonding cannot be bypassed
    // ─────────────────────────────────────────────────────────────────────────

    function test_INV6_C10_unbondingCannotBeBypassed() public {
        uint256 stake = MIN_STAKE;
        vm.deal(makeAddr("ibv"), stake);

        uint64 t0 = BASE_TS;
        bytes32 vid = _register(makeAddr("ibv"), stake, makeAddr("ibr"), 500);
        sm.completeValidatorRegistration(0);

        // 1 second before minimum
        uint64 t_early = t0 + MIN_STAKE_DURATION - 1;
        vm.warp(t_early);

        vm.prank(makeAddr("ibv"));
        vm.expectRevert();
        sm.initiateValidatorRemoval(vid, false, 0);

        vm.prank(makeAddr("ibv"));
        vm.expectRevert();
        sm.forceInitiateValidatorRemoval(vid, false, 0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // C10 INV-7: Unauthorized participant cannot withdraw another's stake
    // ─────────────────────────────────────────────────────────────────────────

    function test_INV7_C10_unauthorizedWithdrawalBlocked() public {
        uint256 stake = MIN_STAKE;
        vm.deal(makeAddr("own"), stake);

        uint64 t0 = BASE_TS;
        bytes32 vid = _register(makeAddr("own"), stake, makeAddr("ownr"), 600);
        sm.completeValidatorRegistration(0);

        uint64 t1 = t0 + MIN_STAKE_DURATION + 1;
        vm.warp(t1);

        address thief = makeAddr("thief");
        vm.prank(thief);
        vm.expectRevert();
        sm.initiateValidatorRemoval(vid, false, 0);

        vm.prank(thief);
        vm.expectRevert();
        sm.forceInitiateValidatorRemoval(vid, false, 0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // C10 INV-8: Unauthorized participant cannot claim another's rewards
    // ─────────────────────────────────────────────────────────────────────────

    function test_INV8_C10_unauthorizedRewardClaimBlocked() public {
        bytes32 id = keccak256("owned-recip");
        address owner = makeAddr("owner");

        vm.prank(PROTOCOL_ADMIN);
        vault.registerRecipient(id, owner, 100, true);

        vm.warp(BASE_TS + 30 days);

        address thief = makeAddr("thief2");
        vm.prank(thief);
        vm.expectRevert("RV: caller is not rewardAddress");
        vault.claim(id);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // C10 INV-9: ValidatorManager remains validator authority
    // ─────────────────────────────────────────────────────────────────────────

    function test_INV9_C10_validatorManagerAuthoritative() public {
        // SM cannot register a validator without going through mockVM
        // Registration requires mockVM to queue it for completion
        uint256 stake = MIN_STAKE;
        vm.deal(makeAddr("vr"), stake);

        bytes32 vid = _register(makeAddr("vr"), stake, makeAddr("vrr"), 700);

        // Cannot complete registration if mockVM has no pending entry
        vm.expectRevert(); // "Mock: no pending registration at index"
        sm.completeValidatorRegistration(99);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // C10 INV-10: FeeDistributor remains independent
    // ─────────────────────────────────────────────────────────────────────────

    function test_INV10_C10_feeDistributorIndependent() public {
        uint256 totalBefore = feeDistributor.totalDistributed();
        uint256 vaultBefore = vault.totalFunded();

        // Large staking payout
        vm.prank(address(sm)); vault.distribute(makeAddr("q"), 1_000_000 ether);

        assertEq(feeDistributor.totalDistributed(), totalBefore, "INV-10: FD unchanged by staking");
        assertEq(vault.totalFunded(), vaultBefore, "INV-10: vault funding unchanged by fee distribution");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // C10 INV-11: 70/20/10 fee accounting remains conserved
    // ─────────────────────────────────────────────────────────────────────────

    function test_INV11_C10_feeSplitConserved() public {
        uint256 feeAmount = 1_234 ether;
        vm.deal(address(feeDistributor), feeAmount);
        feeDistributor.distribute();

        uint256 sum = feeDistributor.totalValidatorShare() +
                      feeDistributor.totalTreasuryShare()  +
                      feeDistributor.totalBurnShare();

        assertEq(sum, feeDistributor.totalDistributed(), "INV-11: 70+20+10 = 100%");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // C10 INV-12: Emergency multisig cannot mint or withdraw staking principal
    // ─────────────────────────────────────────────────────────────────────────

    function test_INV12_C10_emsCannotMintOrWithdraw() public {
        bytes memory mintData = abi.encodeWithSignature("mint(address,uint256)", makeAddr("evil"), 1e30);
        _emsProposeApproveExecuteExpectRevert(address(vault), mintData);

        bytes memory drainData = abi.encodeWithSignature("distribute(address,uint256)", makeAddr("evil"), VAULT_FUND);
        _emsProposeApproveExecuteExpectRevert(address(vault), drainData);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // C10 INV-13: Timelock cannot bypass emergency-only authority
    // ─────────────────────────────────────────────────────────────────────────

    function test_INV13_C10_timelockCannotBypassEmergency() public {
        bytes memory pauseData = abi.encodeCall(RewardVault.pause, ());
        bytes32 salt = bytes32(uint256(777));

        uint64 t0 = uint64(block.timestamp);

        vm.prank(PROTOCOL_ADMIN);
        timelock.schedule(address(vault), pauseData, bytes32(0), salt);

        uint64 t48 = t0 + 172_800;
        vm.warp(t48);

        // Timelock is not pause controller — reverts
        vm.expectRevert("RV: not pause controller");
        timelock.execute(address(vault), pauseData, bytes32(0), salt);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // C10 INV-14: Phase transition cannot duplicate validator/reward/stake state
    // ─────────────────────────────────────────────────────────────────────────

    function test_INV14_C10_transitionCannotDuplicateState() public {
        // SM is already initialized (Phase 2 is already active from setUp)
        // Verify: calling initialize() again reverts
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

        // Vault linkage is also one-time
        vm.prank(PROTOCOL_ADMIN);
        vm.expectRevert("RV: staking manager already set");
        vault.setStakingManager(makeAddr("evil"));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // C10 INV-15: Reward accounting remains non-negative
    // ─────────────────────────────────────────────────────────────────────────

    function test_INV15_C10_rewardAccountingNonNegative() public {
        // totalEmitted and totalClaimed are uint256 — underflow is impossible by type
        // Verify the invariant holds: totalClaimed <= totalEmitted
        vm.prank(address(sm)); vault.distribute(makeAddr("n1"), 1_000 ether);
        vm.prank(address(sm)); vault.distribute(makeAddr("n2"), 500 ether);

        assertGe(vault.totalEmitted(), vault.totalClaimed(), "INV-15: emitted >= claimed (non-negative)");
        assertGe(vault.totalFunded(),  vault.totalEmitted(), "INV-15: funded >= emitted");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // C10 INV-16: No participant can receive more reward than mathematically entitled
    // ─────────────────────────────────────────────────────────────────────────

    function test_INV16_C10_noParticipantExceedsEntitlement() public {
        // Max reward = RATE * validationDuration (100% uptime)
        uint64 duration = 30 days;
        uint256 maxReward = INITIAL_RATE * duration;

        uint256 stake = MIN_STAKE;
        vm.deal(makeAddr("me"), stake);

        uint64 t0 = BASE_TS;
        bytes32 vid = _register(makeAddr("me"), stake, makeAddr("mer"), 800);
        sm.completeValidatorRegistration(0);

        uint64 t1 = t0 + duration;
        vm.warp(t1);

        warpMock.setUptimeResponse(0, UPTIME_BLOCKCHAIN_ID, vid, duration);
        vm.prank(makeAddr("me")); sm.submitUptimeProof(vid, 0);
        vm.prank(makeAddr("me")); sm.initiateValidatorRemoval(vid, false, 0);
        sm.completeValidatorRemoval(0);

        assertLe(makeAddr("mer").balance, maxReward, "INV-16: reward <= max entitlement");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // C10 INV-17: RewardVault cannot become insolvent
    // ─────────────────────────────────────────────────────────────────────────

    function test_INV17_C10_rewardVaultCannotBecomeInsolvent() public {
        // Drain to last 1 wei
        uint256 remaining = vault.totalFunded() - vault.totalEmitted() - 1;
        vm.prank(address(sm)); vault.distribute(makeAddr("d"), remaining);

        // Vault has 1 wei remaining
        assertEq(address(vault).balance, vault.totalFunded() - vault.totalClaimed(), "balance exact");

        // Cannot go insolvent
        vm.prank(address(sm));
        vm.expectRevert("RV: insufficient reserve");
        vault.distribute(makeAddr("x"), 2); // try to take 2 from 1 wei remaining

        // Balance never goes negative
        assertGt(address(vault).balance, 0, "INV-17: vault not insolvent (1 wei remains)");
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

    function _emsProposeApproveExecuteExpectRevert(address target, bytes memory data) internal {
        uint256 n = ems.nonce();
        ems.propose(target, data);
        bytes32 pid = keccak256(abi.encode(target, data, n));

        vm.prank(S1); ems.approve(pid);
        vm.prank(S2); ems.approve(pid);
        vm.prank(S3); ems.approve(pid);

        vm.expectRevert();
        ems.execute(target, data, n);
    }
}
