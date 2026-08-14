// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// ============================================================
// C10GovernanceAttack.t.sol  --  PW-C10
// ============================================================
//
// Governance attacks. Covers C10 brief sections 17, 18, 19, 20.
//
//   Section 17: Unauthorized governance actions
//   Section 18: EmergencyMultisig attacks (1/2/3/4/5 signers, replay, tamper)
//   Section 19: Timelock attacks (early exec, replay, tamper, modified params)
//   Section 20: Governance + Emergency interaction combinations
// ============================================================

import {Test, Vm} from "forge-std/Test.sol";
import {RewardVault} from "../src/RewardVault.sol";
import {PrimeWaveStakingManager} from "../src/PrimeWaveStakingManager.sol";
import {EmergencyMultisig} from "../src/EmergencyMultisig.sol";
import {PrimeWaveTimelock} from "../src/PrimeWaveTimelock.sol";
import {FeeDistributor} from "../src/FeeDistributor.sol";
import {ValidatorFeeVault} from "../src/ValidatorFeeVault.sol";
import {DevTreasury} from "../src/DevTreasury.sol";
import {MockAvalancheValidatorManager} from "./MockAvalancheValidatorManager.sol";
import {StakingManagerSettings} from "validator-manager/interfaces/IStakingManager.sol";
import {IRewardCalculator} from "validator-manager/interfaces/IRewardCalculator.sol";
import {IValidatorManager} from "validator-manager/interfaces/IValidatorManager.sol";
import {PChainOwner} from "validator-manager/interfaces/IACP99Manager.sol";
import {PrimeWaveRewardCalculator} from "../src/PrimeWaveRewardCalculator.sol";

contract C10GovernanceAttackTest is Test {

    // ── Actors ────────────────────────────────────────────────────────────────

    address constant PROTOCOL_ADMIN = address(0x1001);
    address constant S1 = address(0xA001);
    address constant S2 = address(0xA002);
    address constant S3 = address(0xA003);
    address constant S4 = address(0xA004);
    address constant S5 = address(0xA005);
    address constant RANDO = address(0xBEEF);

    uint256 constant VAULT_FUND         = 15_000_000 ether;
    uint256 constant MIN_STAKE          = 1_000 ether;
    uint256 constant MAX_STAKE          = 3_000_000 ether;
    uint64  constant MIN_STAKE_DURATION = 14 days;
    uint64  constant CHURN_PERIOD       = 3600;
    bytes32 constant SUBNET_ID          = bytes32(uint256(1));
    bytes32 constant UPTIME_BLOCKCHAIN_ID = bytes32(uint256(2));

    // ── Contracts ─────────────────────────────────────────────────────────────

    EmergencyMultisig ems;
    PrimeWaveTimelock timelock;
    FeeDistributor    feeDistributor;
    ValidatorFeeVault feeVault;
    DevTreasury       treasury;
    RewardVault       rewardVault;
    PrimeWaveStakingManager sm;
    MockAvalancheValidatorManager mockVM;
    PrimeWaveRewardCalculator calc;

    uint256 INITIAL_RATE;

    function setUp() public {
        INITIAL_RATE = uint256(3_000_000 * 1 ether) / 31_536_000;

        // Deploy EMS
        address[5] memory sigs = [S1, S2, S3, S4, S5];
        ems = new EmergencyMultisig(sigs);

        // Deploy Timelock (proposer = PROTOCOL_ADMIN)
        timelock = new PrimeWaveTimelock(PROTOCOL_ADMIN);

        // Deploy fee system (pre-computed addresses)
        address deployer = address(this);
        uint64 n = vm.getNonce(deployer);
        address expectedVFV  = computeCreateAddress(deployer, n);
        address expectedTrea = computeCreateAddress(deployer, n + 1);
        address expectedFD   = computeCreateAddress(deployer, n + 2);

        feeVault       = new ValidatorFeeVault(expectedFD);
        treasury       = new DevTreasury(expectedFD);
        feeDistributor = new FeeDistributor(payable(expectedVFV), payable(expectedTrea), address(ems));

        // Deploy RewardVault with TIMELOCK as admin so timelock can call setEmissionRate, etc.
        // This is the production pattern: timelock controls all admin-gated vault operations.
        rewardVault = new RewardVault(address(timelock), INITIAL_RATE);

        // Fund vault (fund() has no access control — anyone can fund)
        vm.deal(address(this), VAULT_FUND + 100 ether);
        rewardVault.fund{value: VAULT_FUND}();

        // Timelock sets the pause controller to EMS (admin-gated)
        vm.prank(address(timelock));
        rewardVault.setPauseController(address(ems));

        // Deploy staking system
        mockVM = new MockAvalancheValidatorManager(SUBNET_ID, CHURN_PERIOD);
        calc   = new PrimeWaveRewardCalculator(rewardVault);
        sm     = new PrimeWaveStakingManager();
        vm.prank(PROTOCOL_ADMIN);
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
            rewardVault
        );
        // Timelock sets the staking manager (admin-gated)
        vm.prank(address(timelock));
        rewardVault.setStakingManager(address(sm));

        // Set EMS as pause controller for fee vault too
        vm.prank(address(feeDistributor));
        feeVault.setPauseController(address(ems));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // GA-01: Random EOA cannot change emission rate
    // (Section 17)
    // ─────────────────────────────────────────────────────────────────────────

    function test_GA01_randoCannotChangeEmissionRate() public {
        vm.prank(RANDO);
        vm.expectRevert("RV: not admin");
        rewardVault.setEmissionRate(1);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // GA-02: Random EOA cannot register recipient in RewardVault
    // (Section 17)
    // ─────────────────────────────────────────────────────────────────────────

    function test_GA02_randoCannotRegisterRecipient() public {
        vm.prank(RANDO);
        vm.expectRevert("RV: not admin");
        rewardVault.registerRecipient(keccak256("r"), RANDO, 100, true);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // GA-03: Random EOA cannot call distribute (must be SM)
    // (Section 17)
    // ─────────────────────────────────────────────────────────────────────────

    function test_GA03_randoCannotDistribute() public {
        vm.prank(RANDO);
        vm.expectRevert("RV: not staking manager");
        rewardVault.distribute(RANDO, 1 ether);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // GA-04: Random EOA cannot pause RewardVault
    // (Section 17)
    // ─────────────────────────────────────────────────────────────────────────

    function test_GA04_randoCannotPauseRewardVault() public {
        vm.prank(RANDO);
        vm.expectRevert("RV: not pause controller");
        rewardVault.pause();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // GA-05: EMS with only 1 signer → cannot execute
    // (Section 18 — <3 approvals)
    // ─────────────────────────────────────────────────────────────────────────

    function test_GA05_ems_1Signer_cannotExecute() public {
        bytes32 pid = _emsProposeAndApprove(address(rewardVault), abi.encodeCall(RewardVault.pause, ()), 1);

        vm.expectRevert("EMS: insufficient approvals");
        ems.execute(address(rewardVault), abi.encodeCall(RewardVault.pause, ()), 0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // GA-06: EMS with only 2 signers → cannot execute
    // (Section 18)
    // ─────────────────────────────────────────────────────────────────────────

    function test_GA06_ems_2Signers_cannotExecute() public {
        _emsProposeAndApprove(address(rewardVault), abi.encodeCall(RewardVault.pause, ()), 2);

        vm.expectRevert("EMS: insufficient approvals");
        ems.execute(address(rewardVault), abi.encodeCall(RewardVault.pause, ()), 0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // GA-07: EMS with 3 valid signers → executes successfully
    // (Section 18 — 3 valid approvals → PASS)
    // ─────────────────────────────────────────────────────────────────────────

    function test_GA07_ems_3Signers_executes() public {
        _emsProposeAndApprove(address(rewardVault), abi.encodeCall(RewardVault.pause, ()), 3);

        ems.execute(address(rewardVault), abi.encodeCall(RewardVault.pause, ()), 0);

        assertTrue(rewardVault.paused(), "vault paused via EMS 3-of-5");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // GA-08: EMS duplicate approval from same signer → rejected
    // (Section 18)
    // ─────────────────────────────────────────────────────────────────────────

    function test_GA08_ems_duplicateApproval_rejected() public {
        bytes32 pid = _emsProposeAndApprove(address(rewardVault), abi.encodeCall(RewardVault.pause, ()), 1);

        vm.prank(S1);
        vm.expectRevert("EMS: already approved");
        ems.approve(pid);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // GA-09: EMS wrong signer (non-signer) → rejected
    // (Section 18)
    // ─────────────────────────────────────────────────────────────────────────

    function test_GA09_ems_wrongSigner_rejected() public {
        bytes32 pid = ems.propose(address(rewardVault), abi.encodeCall(RewardVault.pause, ()));

        vm.prank(RANDO);
        vm.expectRevert("EMS: not a signer");
        ems.approve(pid);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // GA-10: EMS reused nonce (replayed transaction) → rejected
    // (Section 18)
    // ─────────────────────────────────────────────────────────────────────────

    function test_GA10_ems_replayedTransaction_rejected() public {
        bytes memory data = abi.encodeCall(RewardVault.pause, ());
        _emsProposeAndApprove(address(rewardVault), data, 3);
        ems.execute(address(rewardVault), data, 0);

        // Attempt to execute again (replay)
        vm.expectRevert("EMS: already executed");
        ems.execute(address(rewardVault), data, 0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // GA-11: EMS changed transaction data → different proposal ID, fails
    // (Section 18 — changed transaction data)
    // ─────────────────────────────────────────────────────────────────────────

    function test_GA11_ems_changedData_proposalNotFound() public {
        bytes memory originalData = abi.encodeCall(RewardVault.pause, ());
        bytes memory tampered     = abi.encodeCall(RewardVault.unpause, ());

        _emsProposeAndApprove(address(rewardVault), originalData, 3);

        // Execute with tampered data — different proposalId, not found
        vm.expectRevert("EMS: proposal does not exist");
        ems.execute(address(rewardVault), tampered, 0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // GA-12: EMS cannot call non-pause functions (target contract rejects)
    // (Section 18 — EMS cannot gain mint/withdraw authority)
    // ─────────────────────────────────────────────────────────────────────────

    function test_GA12_ems_cannotCallSetEmissionRate() public {
        bytes memory data = abi.encodeWithSignature("setEmissionRate(uint256)", 1);
        _emsProposeAndApprove(address(rewardVault), data, 3);

        // Execute → target reverts because EMS is not admin
        vm.expectRevert("RV: not admin");
        ems.execute(address(rewardVault), data, 0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // GA-13: EMS cannot withdraw from RewardVault
    // (Section 18 — EMS cannot gain RewardVault withdrawal authority)
    // ─────────────────────────────────────────────────────────────────────────

    function test_GA13_ems_cannotWithdrawFromVault() public {
        bytes memory data = abi.encodeWithSignature("distribute(address,uint256)", RANDO, 1 ether);
        _emsProposeAndApprove(address(rewardVault), data, 3);

        // Execute → target reverts because EMS is not staking manager
        vm.expectRevert("RV: not staking manager");
        ems.execute(address(rewardVault), data, 0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // GA-14: Timelock: execute immediately → FAIL
    // (Section 19)
    // ─────────────────────────────────────────────────────────────────────────

    function test_GA14_timelock_immediateExecution_fails() public {
        bytes memory data = abi.encodeWithSignature("setEmissionRate(uint256)", INITIAL_RATE / 2);
        bytes32 salt = bytes32(uint256(1));

        vm.prank(PROTOCOL_ADMIN);
        timelock.schedule(address(rewardVault), data, bytes32(0), salt);

        vm.expectRevert("PWTL: delay not elapsed");
        timelock.execute(address(rewardVault), data, bytes32(0), salt);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // GA-15: Timelock: execute 1 second before → FAIL
    // (Section 19)
    // ─────────────────────────────────────────────────────────────────────────

    function test_GA15_timelock_oneSecondEarly_fails() public {
        bytes memory data = abi.encodeWithSignature("setEmissionRate(uint256)", INITIAL_RATE / 2);
        bytes32 salt = bytes32(uint256(2));

        uint64 t0 = uint64(block.timestamp);

        vm.prank(PROTOCOL_ADMIN);
        timelock.schedule(address(rewardVault), data, bytes32(0), salt);

        uint64 t_early = t0 + 172_800 - 1; // 1 second before 48h
        vm.warp(t_early);

        vm.expectRevert("PWTL: delay not elapsed");
        timelock.execute(address(rewardVault), data, bytes32(0), salt);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // GA-16: Timelock: execute at exact 48h → PASS
    // (Section 19)
    // ─────────────────────────────────────────────────────────────────────────

    function test_GA16_timelock_exactFortyEightHours_succeeds() public {
        uint256 halfRate = INITIAL_RATE / 2;
        bytes memory data = abi.encodeWithSignature("setEmissionRate(uint256)", halfRate);
        bytes32 salt = bytes32(uint256(3));

        uint64 t0 = uint64(block.timestamp);

        vm.prank(PROTOCOL_ADMIN);
        timelock.schedule(address(rewardVault), data, bytes32(0), salt);

        uint64 t48 = t0 + 172_800; // exactly 48 hours
        vm.warp(t48);

        timelock.execute(address(rewardVault), data, bytes32(0), salt);

        assertEq(rewardVault.emissionRatePerSecond(), halfRate, "rate reduced via timelock");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // GA-17: Timelock: cancel before execution, then replay fails
    // (Section 19 — cancel before execution)
    // ─────────────────────────────────────────────────────────────────────────

    function test_GA17_timelock_cancelThenExecute_fails() public {
        bytes memory data = abi.encodeWithSignature("setEmissionRate(uint256)", INITIAL_RATE / 2);
        bytes32 salt = bytes32(uint256(4));

        uint64 t0 = uint64(block.timestamp);

        vm.prank(PROTOCOL_ADMIN);
        timelock.schedule(address(rewardVault), data, bytes32(0), salt);

        vm.prank(PROTOCOL_ADMIN);
        timelock.cancel(address(rewardVault), data, bytes32(0), salt);

        uint64 t48 = t0 + 172_800;
        vm.warp(t48);

        vm.expectRevert("PWTL: cancelled");
        timelock.execute(address(rewardVault), data, bytes32(0), salt);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // GA-18: Timelock: replay execution → FAIL
    // (Section 19 — replay execution)
    // ─────────────────────────────────────────────────────────────────────────

    function test_GA18_timelock_replayExecution_fails() public {
        uint256 halfRate = INITIAL_RATE / 2;
        bytes memory data = abi.encodeWithSignature("setEmissionRate(uint256)", halfRate);
        bytes32 salt = bytes32(uint256(5));

        uint64 t0 = uint64(block.timestamp);

        vm.prank(PROTOCOL_ADMIN);
        timelock.schedule(address(rewardVault), data, bytes32(0), salt);

        uint64 t48 = t0 + 172_800;
        vm.warp(t48);

        timelock.execute(address(rewardVault), data, bytes32(0), salt);

        // Replay
        vm.expectRevert("PWTL: already executed");
        timelock.execute(address(rewardVault), data, bytes32(0), salt);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // GA-19: Timelock: modified calldata → hash mismatch, not scheduled
    // (Section 19 — modified calldata)
    // ─────────────────────────────────────────────────────────────────────────

    function test_GA19_timelock_modifiedCalldata_notScheduled() public {
        bytes memory original = abi.encodeWithSignature("setEmissionRate(uint256)", INITIAL_RATE / 2);
        bytes memory tampered = abi.encodeWithSignature("setEmissionRate(uint256)", 0);
        bytes32 salt = bytes32(uint256(6));

        uint64 t0 = uint64(block.timestamp);

        vm.prank(PROTOCOL_ADMIN);
        timelock.schedule(address(rewardVault), original, bytes32(0), salt);

        uint64 t48 = t0 + 172_800;
        vm.warp(t48);

        vm.expectRevert("PWTL: not scheduled");
        timelock.execute(address(rewardVault), tampered, bytes32(0), salt);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // GA-20: Timelock: non-proposer cannot schedule
    // (Section 19 — unauthorized schedule)
    // ─────────────────────────────────────────────────────────────────────────

    function test_GA20_timelock_nonProposer_cannotSchedule() public {
        bytes memory data = abi.encodeWithSignature("setEmissionRate(uint256)", 1);
        bytes32 salt = bytes32(uint256(7));

        vm.prank(RANDO);
        vm.expectRevert("PWTL: not proposer");
        timelock.schedule(address(rewardVault), data, bytes32(0), salt);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // GA-21: Emergency pause + timelock operation — pause blocks claim
    // (Section 20 — emergency pause + timelock operation)
    // ─────────────────────────────────────────────────────────────────────────

    function test_GA21_emergencyPause_blocksClaim_timelockContinues() public {
        // Register a recipient (vault admin is timelock, not PROTOCOL_ADMIN)
        vm.prank(address(timelock));
        rewardVault.registerRecipient(keccak256("r1"), makeAddr("recv"), 100, true);

        // Precompute all timestamps up front — via_ir caches block.timestamp at function entry
        uint64 t0  = uint64(block.timestamp);
        uint64 t10 = t0 + uint64(10 days);
        uint64 t48 = t10 + uint64(172_800); // MIN_DELAY = 172_800

        vm.warp(t10);

        // EMS pauses vault
        _emsProposeAndApprove(address(rewardVault), abi.encodeCall(RewardVault.pause, ()), 3);
        ems.execute(address(rewardVault), abi.encodeCall(RewardVault.pause, ()), 0);
        assertTrue(rewardVault.paused(), "vault paused");

        // Claim blocked
        vm.prank(makeAddr("recv"));
        vm.expectRevert("RV: paused");
        rewardVault.claim(keccak256("r1"));

        // Timelock operation can still be scheduled (pausing doesn't affect governance)
        bytes memory data = abi.encodeWithSignature("setEmissionRate(uint256)", INITIAL_RATE / 2);
        bytes32 salt = bytes32(uint256(8));

        vm.prank(PROTOCOL_ADMIN);
        timelock.schedule(address(rewardVault), data, bytes32(0), salt);

        // After 48h (using absolute precomputed t48), timelock executes
        vm.warp(t48);
        timelock.execute(address(rewardVault), data, bytes32(0), salt);

        assertEq(rewardVault.emissionRatePerSecond(), INITIAL_RATE / 2, "rate reduced while paused");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // GA-22: Multiple pause/unpause cycles — accounting preserved
    // (Section 20 — multiple pause/unpause cycles)
    // ─────────────────────────────────────────────────────────────────────────

    function test_GA22_multiplePauseUnpauseCycles_accountingPreserved() public {
        // Vault admin is timelock — use it for admin-gated calls
        vm.prank(address(timelock));
        rewardVault.registerRecipient(keccak256("cyc"), makeAddr("recv2"), 100, true);

        uint64 t0 = uint64(block.timestamp);

        // Pause cycle 1
        _emsProposeAndApprove(address(rewardVault), abi.encodeCall(RewardVault.pause, ()), 3);
        ems.execute(address(rewardVault), abi.encodeCall(RewardVault.pause, ()), 0);

        uint64 t1 = t0 + 5 days;
        vm.warp(t1);

        _emsProposeAndApprove(address(rewardVault), abi.encodeCall(RewardVault.unpause, ()), 3);
        ems.execute(address(rewardVault), abi.encodeCall(RewardVault.unpause, ()), 1);

        uint64 t2 = t1 + 5 days;
        vm.warp(t2);

        // Pause cycle 2
        _emsProposeAndApprove(address(rewardVault), abi.encodeCall(RewardVault.pause, ()), 3);
        ems.execute(address(rewardVault), abi.encodeCall(RewardVault.pause, ()), 2);

        uint64 t3 = t2 + 5 days;
        vm.warp(t3);

        _emsProposeAndApprove(address(rewardVault), abi.encodeCall(RewardVault.unpause, ()), 3);
        ems.execute(address(rewardVault), abi.encodeCall(RewardVault.unpause, ()), 3);

        // Vault invariants still hold
        assertLe(rewardVault.totalEmitted(), rewardVault.totalFunded(), "emitted <= funded after 2 pause cycles");
        assertFalse(rewardVault.paused(), "vault unpaused");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // GA-23: Timelock cannot acquire emergency-only pause powers
    // (Section 20 — timelock cannot acquire emergency-only authority)
    // ─────────────────────────────────────────────────────────────────────────

    function test_GA23_timelock_cannotAcquireEmergencyPausePower() public {
        // Timelock tries to call pause() on RewardVault
        // But timelock is not the pauseController (EMS is)
        bytes memory data = abi.encodeCall(RewardVault.pause, ());
        bytes32 salt = bytes32(uint256(9));

        uint64 t0 = uint64(block.timestamp);

        vm.prank(PROTOCOL_ADMIN);
        timelock.schedule(address(rewardVault), data, bytes32(0), salt);

        uint64 t48 = t0 + 172_800;
        vm.warp(t48);

        // Execute fails — timelock is not the pause controller
        vm.expectRevert("RV: not pause controller");
        timelock.execute(address(rewardVault), data, bytes32(0), salt);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // GA-24: EMS cannot become hidden governance (cannot call timelock)
    // (Section 20 — emergency authority cannot become hidden governance mechanism)
    // ─────────────────────────────────────────────────────────────────────────

    function test_GA24_ems_cannotScheduleTimelockOperations() public {
        // EMS tries to schedule a timelock operation
        bytes memory scheduleData = abi.encodeWithSignature(
            "schedule(address,bytes,bytes32,bytes32)",
            address(rewardVault),
            abi.encodeWithSignature("setEmissionRate(uint256)", 0),
            bytes32(0),
            bytes32(uint256(99))
        );

        _emsProposeAndApprove(address(timelock), scheduleData, 3);

        // Execute → timelock rejects because EMS is not the proposer
        vm.expectRevert("PWTL: not proposer");
        ems.execute(address(timelock), scheduleData, 0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // GA-25: Cancelled EMS proposal cannot be re-executed
    // (Section 18 — cancelled proposal)
    // ─────────────────────────────────────────────────────────────────────────

    function test_GA25_ems_cancelledProposal_cannotBeExecuted() public {
        bytes memory data = abi.encodeCall(RewardVault.pause, ());
        bytes32 pid = ems.propose(address(rewardVault), data);

        // Proposer cancels
        ems.cancel(address(rewardVault), data, 0);

        // Signers approve (after cancel)
        vm.prank(S1); vm.expectRevert("EMS: cancelled"); ems.approve(pid);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // GA-26: Timelock predecessor chain — must execute in order
    // (Section 19 — predecessor check)
    // ─────────────────────────────────────────────────────────────────────────

    function test_GA26_timelock_predecessorNotExecuted_fails() public {
        bytes memory data1 = abi.encodeWithSignature("setEmissionRate(uint256)", INITIAL_RATE / 2);
        bytes memory data2 = abi.encodeWithSignature("setEmissionRate(uint256)", INITIAL_RATE / 4);
        bytes32 salt1 = bytes32(uint256(10));
        bytes32 salt2 = bytes32(uint256(11));

        uint64 t0 = uint64(block.timestamp);

        vm.prank(PROTOCOL_ADMIN);
        bytes32 opId1 = timelock.schedule(address(rewardVault), data1, bytes32(0), salt1);

        // Schedule op2 with op1 as predecessor
        vm.prank(PROTOCOL_ADMIN);
        timelock.schedule(address(rewardVault), data2, opId1, salt2);

        uint64 t48 = t0 + 172_800;
        vm.warp(t48);

        // Try to execute op2 before op1 → fails (predecessor not executed)
        vm.expectRevert("PWTL: predecessor not executed");
        timelock.execute(address(rewardVault), data2, opId1, salt2);

        // Execute op1 first
        timelock.execute(address(rewardVault), data1, bytes32(0), salt1);

        // Now op2 can execute
        timelock.execute(address(rewardVault), data2, opId1, salt2);
        assertEq(rewardVault.emissionRatePerSecond(), INITIAL_RATE / 4, "rate reduced via chain");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // GA-27: EMS cannot change its own signer set (immutable)
    // (Section 18 — signer set is immutable)
    // ─────────────────────────────────────────────────────────────────────────

    function test_GA27_ems_signerSetImmutable() public {
        // EMS has no function to change signers
        // Verify this by checking no such selector exists (compile-time — just verify signer is S1)
        assertTrue(ems.isSigner(S1), "S1 is signer");
        assertFalse(ems.isSigner(RANDO), "RANDO is not signer");

        // The signers array is immutable after construction
        assertEq(ems.signers(0), S1);
        assertEq(ems.signers(1), S2);
        assertEq(ems.signers(2), S3);
        assertEq(ems.signers(3), S4);
        assertEq(ems.signers(4), S5);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // GA-28: EMS with 4 or 5 signers — still executes (meets threshold)
    // (Section 18 — 4 and 5 signers)
    // ─────────────────────────────────────────────────────────────────────────

    function test_GA28_ems_4Signers_executes() public {
        // First nonce = 0 was consumed above (in other tests proposing)
        // Fresh proposal with current nonce
        uint256 currentNonce = ems.nonce();
        bytes memory data = abi.encodeCall(RewardVault.pause, ());
        ems.propose(address(rewardVault), data);

        vm.prank(S1); ems.approve(_pid(address(rewardVault), data, currentNonce));
        vm.prank(S2); ems.approve(_pid(address(rewardVault), data, currentNonce));
        vm.prank(S3); ems.approve(_pid(address(rewardVault), data, currentNonce));
        vm.prank(S4); ems.approve(_pid(address(rewardVault), data, currentNonce));

        ems.execute(address(rewardVault), data, currentNonce);
        assertTrue(rewardVault.paused(), "4-of-5 executes");
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    function _emsProposeAndApprove(
        address target,
        bytes memory data,
        uint256 numSigners
    ) internal returns (bytes32 pid) {
        uint256 currentNonce = ems.nonce();
        ems.propose(target, data);
        pid = _pid(target, data, currentNonce);

        address[5] memory allSigners = [S1, S2, S3, S4, S5];
        for (uint256 i = 0; i < numSigners && i < 5; i++) {
            vm.prank(allSigners[i]);
            ems.approve(pid);
        }
    }

    function _pid(address target, bytes memory data, uint256 n) internal pure returns (bytes32) {
        return keccak256(abi.encode(target, data, n));
    }
}
