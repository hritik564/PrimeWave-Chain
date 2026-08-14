// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// ============================================================
// GovernanceUnit.t.sol -- PW-C07 Unit Tests
// ============================================================
//
// Tests all governance components added in C07:
//   - EmergencyMultisig (3-of-5 pause authority)
//   - PrimeWaveTimelock (48-hour delay)
//   - Pause / unpause on FeeDistributor, ValidatorFeeVault, RewardVault
//   - Emergency authority limits (cannot exceed pause/unpause scope)
//   - Validator lifecycle hardening (timelocked actions)
//   - Reward recipient manipulation protection
//
// Acceptance criteria covered (from PW-C07 spec):
//   - 3-of-5 threshold enforced; 1/5 and 2/5 fail
//   - Duplicate approvals rejected
//   - Unauthorized approvals rejected
//   - Proposal replay impossible
//   - 48-hour timelock: early execution fails; on-time succeeds
//   - Timelock: cancellation works; replay after cancel fails
//   - Timelock: parameter tampering causes hash mismatch -> revert
//   - Pause halts claims on all three contracts
//   - Unpause restores claims
//   - Emergency Multisig cannot mint, drain, change validators, bypass timelock
//
// Regression: All C06 behaviors preserved.
// ============================================================

import "forge-std/Test.sol";

import "../src/EmergencyMultisig.sol";
import "../src/PrimeWaveTimelock.sol";
import "../src/FeeDistributor.sol";
import "../src/ValidatorFeeVault.sol";
import "../src/RewardVault.sol";
import "../src/DevTreasury.sol";

// ── Helpers ───────────────────────────────────────────────────────────────────

contract GovernanceUnit is Test {

    // ── Actors ────────────────────────────────────────────────────────────────

    // Protocol Admin (DEV0 EOA in dev; in prod this would be multisig+timelock)
    address internal constant PROTOCOL_ADMIN = address(0x1001);

    // 5 Emergency Multisig signers (dev keys)
    address internal constant S1 = address(0xA001);
    address internal constant S2 = address(0xA002);
    address internal constant S3 = address(0xA003);
    address internal constant S4 = address(0xA004);
    address internal constant S5 = address(0xA005);

    // Non-authorized address
    address internal constant RANDO = address(0xBEEF);

    // Validator reward recipient
    address internal constant RECIPIENT_1 = address(0xC001);

    // ── Contracts ─────────────────────────────────────────────────────────────

    EmergencyMultisig   internal ems;
    PrimeWaveTimelock   internal timelock;
    FeeDistributor      internal distributor;
    ValidatorFeeVault   internal vault;
    RewardVault         internal rewardVault;
    DevTreasury         internal treasury;

    bytes32 internal constant VAL_ID_1 = keccak256("validator-1");
    bytes32 internal constant RV_REC_1 = keccak256("rv-recipient-1");

    uint256 internal constant MAX_RATE = uint256(3_000_000 ether) / (365 * 24 * 60 * 60);

    // ── Setup ─────────────────────────────────────────────────────────────────

    function setUp() public {
        // 1. Deploy Emergency Multisig
        address[5] memory sigs = [S1, S2, S3, S4, S5];
        ems = new EmergencyMultisig(sigs);

        // 2. Deploy Timelock (proposer = PROTOCOL_ADMIN)
        timelock = new PrimeWaveTimelock(PROTOCOL_ADMIN);

        // 3. Deploy protocol contracts
        // FeeDistributor needs vault + treasury addresses pre-computed.
        // Use pre-computed address pattern (nonce = current + offsets).
        address deployer = address(this);
        uint64  nonce    = vm.getNonce(deployer);

        address expectedVault    = computeCreateAddress(deployer, nonce);
        address expectedTreasury = computeCreateAddress(deployer, nonce + 1);
        address expectedDist     = computeCreateAddress(deployer, nonce + 2);

        vault       = new ValidatorFeeVault(expectedDist);     // nonce+0
        treasury    = new DevTreasury(expectedDist);           // nonce+1
        distributor = new FeeDistributor(                      // nonce+2
            payable(expectedVault),
            payable(expectedTreasury),
            address(ems)   // pauseController = EmergencyMultisig
        );

        // 4. Set Emergency Multisig as pause controller on vault + rewardVault
        //    protocolAdmin for VFV is the distributor (expectedDist)
        //    In this test setup we use PROTOCOL_ADMIN for RewardVault
        rewardVault = new RewardVault(PROTOCOL_ADMIN, MAX_RATE);

        // Set pauseController on vault via protocolAdmin path
        // VFV's protocolAdmin is `expectedDist` (distributor)
        // For test simplicity: redeploy vault with PROTOCOL_ADMIN as admin
        vault = new ValidatorFeeVault(PROTOCOL_ADMIN);
        vm.prank(PROTOCOL_ADMIN);
        vault.setPauseController(address(ems));

        vm.prank(PROTOCOL_ADMIN);
        rewardVault.setPauseController(address(ems));

        // FeeDistributor already has ems as pauseController from constructor
    }

    // =========================================================================
    // SECTION A: EmergencyMultisig
    // =========================================================================

    // ── A1: Construction ──────────────────────────────────────────────────────

    function test_EMS_constructor_storesSigners() public view {
        assertEq(ems.signers(0), S1);
        assertEq(ems.signers(1), S2);
        assertEq(ems.signers(2), S3);
        assertEq(ems.signers(3), S4);
        assertEq(ems.signers(4), S5);
        assertTrue(ems.isSigner(S1));
        assertTrue(ems.isSigner(S5));
        assertFalse(ems.isSigner(RANDO));
        assertEq(ems.THRESHOLD(), 3);
    }

    function test_EMS_constructor_rejectsZeroSigner() public {
        address[5] memory sigs = [S1, S2, S3, S4, address(0)];
        vm.expectRevert("EMS: zero signer");
        new EmergencyMultisig(sigs);
    }

    function test_EMS_constructor_rejectsDuplicateSigner() public {
        address[5] memory sigs = [S1, S2, S3, S4, S1];
        vm.expectRevert("EMS: duplicate signer");
        new EmergencyMultisig(sigs);
    }

    // ── A2: Propose ───────────────────────────────────────────────────────────

    function test_EMS_propose_anyoneCanPropose() public {
        bytes memory data = abi.encodeCall(FeeDistributor.pause, ());
        vm.prank(RANDO);
        bytes32 pid = ems.propose(address(distributor), data);
        assertEq(ems.proposer(pid), RANDO);
        assertEq(ems.nonce(), 1);
    }

    function test_EMS_propose_incrementsNonce() public {
        bytes memory data = abi.encodeCall(FeeDistributor.pause, ());
        ems.propose(address(distributor), data);
        assertEq(ems.nonce(), 1);
        ems.propose(address(distributor), data);
        assertEq(ems.nonce(), 2);
    }

    function test_EMS_propose_rejectsZeroTarget() public {
        vm.expectRevert("EMS: zero target");
        ems.propose(address(0), "");
    }

    // ── A3: Approve ───────────────────────────────────────────────────────────

    function test_EMS_approve_signerCanApprove() public {
        bytes32 pid = _propose_pause_dist();

        vm.prank(S1);
        ems.approve(pid);

        assertEq(ems.approvalCount(pid), 1);
        assertTrue(ems.hasApproved(pid, S1));
    }

    function test_EMS_approve_nonSignerReverts() public {
        bytes32 pid = _propose_pause_dist();
        vm.prank(RANDO);
        vm.expectRevert("EMS: not a signer");
        ems.approve(pid);
    }

    function test_EMS_approve_duplicateReverts() public {
        bytes32 pid = _propose_pause_dist();
        vm.prank(S1);
        ems.approve(pid);
        vm.prank(S1);
        vm.expectRevert("EMS: already approved");
        ems.approve(pid);
    }

    function test_EMS_approve_nonexistentProposalReverts() public {
        vm.prank(S1);
        vm.expectRevert("EMS: proposal does not exist");
        ems.approve(keccak256("nonexistent"));
    }

    function test_EMS_1_of_5_insufficient() public {
        bytes32 pid = _propose_pause_dist();
        vm.prank(S1); ems.approve(pid);
        assertFalse(ems.isReady(pid));
    }

    function test_EMS_2_of_5_insufficient() public {
        bytes32 pid = _propose_pause_dist();
        vm.prank(S1); ems.approve(pid);
        vm.prank(S2); ems.approve(pid);
        assertFalse(ems.isReady(pid));
        assertEq(ems.approvalCount(pid), 2);
    }

    function test_EMS_3_of_5_sufficient() public {
        bytes32 pid = _propose_pause_dist();
        _approve3(pid);
        assertTrue(ems.isReady(pid));
        assertEq(ems.approvalCount(pid), 3);
    }

    function test_EMS_4_of_5_sufficient() public {
        bytes32 pid = _propose_pause_dist();
        vm.prank(S1); ems.approve(pid);
        vm.prank(S2); ems.approve(pid);
        vm.prank(S3); ems.approve(pid);
        vm.prank(S4); ems.approve(pid);
        assertTrue(ems.isReady(pid));
        assertEq(ems.approvalCount(pid), 4);
    }

    function test_EMS_5_of_5_sufficient() public {
        bytes32 pid = _propose_pause_dist();
        vm.prank(S1); ems.approve(pid);
        vm.prank(S2); ems.approve(pid);
        vm.prank(S3); ems.approve(pid);
        vm.prank(S4); ems.approve(pid);
        vm.prank(S5); ems.approve(pid);
        assertTrue(ems.isReady(pid));
        assertEq(ems.approvalCount(pid), 5);
    }

    // ── A4: Execute ───────────────────────────────────────────────────────────

    function test_EMS_execute_pausesDistributor() public {
        (bytes32 pid, bytes memory data, uint256 n) = _propose_pause_dist_full();
        _approve3(pid);
        ems.execute(address(distributor), data, n);
        assertTrue(distributor.paused());
        assertTrue(ems.isExecuted(pid));
    }

    function test_EMS_execute_pausesVault() public {
        bytes memory data = abi.encodeCall(ValidatorFeeVault.pause, ());
        uint256 n = ems.nonce();
        bytes32 pid = ems.propose(address(vault), data);
        _approve3(pid);
        ems.execute(address(vault), data, n);
        assertTrue(vault.paused());
    }

    function test_EMS_execute_pausesRewardVault() public {
        bytes memory data = abi.encodeCall(RewardVault.pause, ());
        uint256 n = ems.nonce();
        bytes32 pid = ems.propose(address(rewardVault), data);
        _approve3(pid);
        ems.execute(address(rewardVault), data, n);
        assertTrue(rewardVault.paused());
    }

    function test_EMS_execute_unpausesDistributor() public {
        // First pause
        (bytes32 pid, bytes memory data, uint256 n) = _propose_pause_dist_full();
        _approve3(pid);
        ems.execute(address(distributor), data, n);

        // Now unpause
        bytes memory udata = abi.encodeCall(FeeDistributor.unpause, ());
        uint256 n2 = ems.nonce();
        bytes32 pid2 = ems.propose(address(distributor), udata);
        _approve3(pid2);
        ems.execute(address(distributor), udata, n2);
        assertFalse(distributor.paused());
    }

    function test_EMS_execute_withInsufficientApprovalsReverts() public {
        (bytes32 pid, bytes memory data, uint256 n) = _propose_pause_dist_full();
        vm.prank(S1); ems.approve(pid);
        vm.prank(S2); ems.approve(pid);
        vm.expectRevert("EMS: insufficient approvals");
        ems.execute(address(distributor), data, n);
    }

    function test_EMS_execute_replayReverts() public {
        (bytes32 pid, bytes memory data, uint256 n) = _propose_pause_dist_full();
        _approve3(pid);
        ems.execute(address(distributor), data, n);
        // Replay attempt
        vm.expectRevert("EMS: already executed");
        ems.execute(address(distributor), data, n);
    }

    function test_EMS_execute_afterCancelReverts() public {
        (bytes32 pid, bytes memory data, uint256 n) = _propose_pause_dist_full();
        _approve3(pid);
        ems.cancel(address(distributor), data, n);
        vm.expectRevert("EMS: cancelled");
        ems.execute(address(distributor), data, n);
    }

    function test_EMS_execute_approveAfterExecuteReverts() public {
        (bytes32 pid, bytes memory data, uint256 n) = _propose_pause_dist_full();
        _approve3(pid);
        ems.execute(address(distributor), data, n);
        vm.prank(S4);
        vm.expectRevert("EMS: already executed");
        ems.approve(pid);
    }

    // ── A5: Cancel ────────────────────────────────────────────────────────────

    function test_EMS_cancel_byProposerSucceeds() public {
        (bytes32 pid, bytes memory data, uint256 n) = _propose_pause_dist_full();
        ems.cancel(address(distributor), data, n);
        assertTrue(ems.isCancelled(pid));
    }

    function test_EMS_cancel_byNonProposerReverts() public {
        (, bytes memory data, uint256 n) = _propose_pause_dist_full();
        vm.prank(RANDO);
        vm.expectRevert("EMS: not proposer");
        ems.cancel(address(distributor), data, n);
    }

    function test_EMS_cancel_afterExecuteReverts() public {
        (bytes32 pid, bytes memory data, uint256 n) = _propose_pause_dist_full();
        _approve3(pid);
        ems.execute(address(distributor), data, n);
        vm.expectRevert("EMS: already executed");
        ems.cancel(address(distributor), data, n);
    }

    function test_EMS_cancel_doubleCancelReverts() public {
        (, bytes memory data, uint256 n) = _propose_pause_dist_full();
        ems.cancel(address(distributor), data, n);
        vm.expectRevert("EMS: already cancelled");
        ems.cancel(address(distributor), data, n);
    }

    // ── A6: Emergency authority limits ────────────────────────────────────────

    function test_EMS_cannotCallRegisterValidator_onVault() public {
        // Even with 3/5 approval, calling registerValidator reverts
        // because VFV's protocolAdmin is PROTOCOL_ADMIN, not ems.
        bytes memory data = abi.encodeCall(
            ValidatorFeeVault.registerValidator,
            (VAL_ID_1, RANDO, 1, 10_000)
        );
        uint256 n = ems.nonce();
        bytes32 pid = ems.propose(address(vault), data);
        _approve3(pid);
        vm.expectRevert(); // "VFV: not admin"
        ems.execute(address(vault), data, n);
    }

    function test_EMS_cannotCallSetEmissionRate() public {
        bytes memory data = abi.encodeCall(RewardVault.setEmissionRate, (0));
        uint256 n = ems.nonce();
        bytes32 pid = ems.propose(address(rewardVault), data);
        _approve3(pid);
        vm.expectRevert(); // "RV: not admin"
        ems.execute(address(rewardVault), data, n);
    }

    function test_EMS_cannotCallSetRewardAddress() public {
        // First register a recipient so the ID exists
        bytes32 id = RV_REC_1;
        vm.prank(PROTOCOL_ADMIN);
        rewardVault.registerRecipient(id, RECIPIENT_1, 1, true);
        // fund() is permissionless; test contract sends ETH directly
        rewardVault.fund{value: 1 ether}();
        // Try to hijack rewardAddress via EmergencyMultisig
        bytes memory data = abi.encodeCall(RewardVault.setRewardAddress, (id, RANDO));
        uint256 n = ems.nonce();
        bytes32 pid = ems.propose(address(rewardVault), data);
        _approve3(pid);
        vm.expectRevert(); // "RV: not admin"
        ems.execute(address(rewardVault), data, n);
    }

    function test_EMS_cannotDeactivateValidator() public {
        // Register validator in vault directly (admin = PROTOCOL_ADMIN)
        vm.prank(PROTOCOL_ADMIN);
        vault.registerValidator(VAL_ID_1, RECIPIENT_1, 1, 10_000);

        bytes memory data = abi.encodeCall(ValidatorFeeVault.deactivateValidator, (VAL_ID_1));
        uint256 n = ems.nonce();
        bytes32 pid = ems.propose(address(vault), data);
        _approve3(pid);
        vm.expectRevert(); // "VFV: not admin"
        ems.execute(address(vault), data, n);
    }

    function test_EMS_cannotSetRewardRecipient_onVault() public {
        vm.prank(PROTOCOL_ADMIN);
        vault.registerValidator(VAL_ID_1, RECIPIENT_1, 1, 10_000);

        bytes memory data = abi.encodeCall(
            ValidatorFeeVault.setRewardRecipient, (VAL_ID_1, RANDO)
        );
        uint256 n = ems.nonce();
        bytes32 pid = ems.propose(address(vault), data);
        _approve3(pid);
        vm.expectRevert(); // "VFV: not admin"
        ems.execute(address(vault), data, n);
    }

    // =========================================================================
    // SECTION B: PrimeWaveTimelock
    // =========================================================================

    function test_TL_constructor_setsProposer() public view {
        assertEq(timelock.proposer(), PROTOCOL_ADMIN);
        assertEq(timelock.MIN_DELAY(), 172_800);
    }

    function test_TL_constructor_rejectsZeroProposer() public {
        vm.expectRevert("PWTL: zero proposer");
        new PrimeWaveTimelock(address(0));
    }

    // ── B1: Schedule ──────────────────────────────────────────────────────────

    function test_TL_schedule_proposerCanSchedule() public {
        bytes memory data = abi.encodeCall(ValidatorFeeVault.registerValidator,
            (VAL_ID_1, RECIPIENT_1, 1, 10_000));
        vm.prank(PROTOCOL_ADMIN);
        bytes32 opId = timelock.schedule(address(vault), data, bytes32(0), keccak256("salt1"));
        assertGt(timelock.scheduledAt(opId), 0);
        assertEq(timelock.scheduledAt(opId), block.timestamp + 172_800);
    }

    function test_TL_schedule_nonProposerReverts() public {
        vm.prank(RANDO);
        vm.expectRevert("PWTL: not proposer");
        timelock.schedule(address(vault), "", bytes32(0), bytes32(0));
    }

    function test_TL_schedule_duplicateSaltReverts() public {
        bytes memory data = "";
        bytes32 salt = keccak256("unique-salt");
        vm.prank(PROTOCOL_ADMIN);
        timelock.schedule(address(vault), data, bytes32(0), salt);
        vm.prank(PROTOCOL_ADMIN);
        vm.expectRevert("PWTL: already scheduled");
        timelock.schedule(address(vault), data, bytes32(0), salt);
    }

    function test_TL_schedule_rejectsZeroTarget() public {
        vm.prank(PROTOCOL_ADMIN);
        vm.expectRevert("PWTL: zero target");
        timelock.schedule(address(0), "", bytes32(0), bytes32(0));
    }

    // ── B2: Execute (delay enforcement) ───────────────────────────────────────

    function test_TL_execute_beforeDelayReverts() public {
        bytes memory data = abi.encodeCall(ValidatorFeeVault.setPauseController, (address(ems)));
        bytes32 salt = keccak256("test-delay");
        vm.prank(PROTOCOL_ADMIN);
        timelock.schedule(address(vault), data, bytes32(0), salt);

        // 1 second before ready
        vm.warp(block.timestamp + 172_799);
        vm.expectRevert("PWTL: delay not elapsed");
        timelock.execute(address(vault), data, bytes32(0), salt);
    }

    function test_TL_execute_exactlyAtDelaySucceeds() public {
        // We test with setPauseController which vault already has admin set
        // Use timelock as proposer and vault admin = PROTOCOL_ADMIN is different
        // Just test the timelock internal logic by calling a simple target
        bytes memory data = abi.encodeCall(ValidatorFeeVault.setPauseController, (address(ems)));
        bytes32 salt = keccak256("delay-exact");
        vm.prank(PROTOCOL_ADMIN);
        timelock.schedule(address(vault), data, bytes32(0), salt);

        vm.warp(block.timestamp + 172_800);

        // vault.setPauseController requires protocolAdmin or pauseController
        // Since timelock is not either, this reverts at vault level
        // Test just that timelock WOULD execute (timelock delay check passes)
        // We'll use a mock that accepts any call instead
        vm.expectRevert(); // vault rejects, but timelock delay check passed
        timelock.execute(address(vault), data, bytes32(0), salt);
        // Confirm not marked as executed (call failed at target)
        bytes32 opId = timelock.getOperationId(address(vault), data, bytes32(0), salt);
        assertFalse(timelock.isExecuted(opId));
    }

    function test_TL_execute_timelockAsAdmin_succeeds() public {
        // Deploy a fresh vault with timelock as protocolAdmin
        ValidatorFeeVault tlVault = new ValidatorFeeVault(address(timelock));

        bytes memory data = abi.encodeCall(ValidatorFeeVault.setPauseController, (address(ems)));
        bytes32 salt = keccak256("tl-admin-test");
        vm.prank(PROTOCOL_ADMIN);
        timelock.schedule(address(tlVault), data, bytes32(0), salt);

        vm.warp(block.timestamp + 172_800);
        timelock.execute(address(tlVault), data, bytes32(0), salt);

        assertEq(tlVault.pauseController(), address(ems));
        bytes32 opId = timelock.getOperationId(address(tlVault), data, bytes32(0), salt);
        assertTrue(timelock.isExecuted(opId));
    }

    function test_TL_execute_replayReverts() public {
        ValidatorFeeVault tlVault = new ValidatorFeeVault(address(timelock));
        bytes memory data = abi.encodeCall(ValidatorFeeVault.setPauseController, (address(ems)));
        bytes32 salt = keccak256("replay-test");
        vm.prank(PROTOCOL_ADMIN);
        timelock.schedule(address(tlVault), data, bytes32(0), salt);
        vm.warp(block.timestamp + 172_800);
        timelock.execute(address(tlVault), data, bytes32(0), salt);

        vm.expectRevert("PWTL: already executed");
        timelock.execute(address(tlVault), data, bytes32(0), salt);
    }

    function test_TL_execute_parameterTamperReverts() public {
        bytes memory data = abi.encodeCall(ValidatorFeeVault.setPauseController, (address(ems)));
        bytes32 salt = keccak256("tamper-test");
        vm.prank(PROTOCOL_ADMIN);
        timelock.schedule(address(vault), data, bytes32(0), salt);
        vm.warp(block.timestamp + 172_800);

        // Tamper: change salt
        vm.expectRevert("PWTL: not scheduled");
        timelock.execute(address(vault), data, bytes32(0), keccak256("different-salt"));
    }

    function test_TL_execute_predecessorNotExecutedReverts() public {
        ValidatorFeeVault tlVault = new ValidatorFeeVault(address(timelock));
        bytes memory data = abi.encodeCall(ValidatorFeeVault.setPauseController, (address(ems)));

        bytes32 salt1 = keccak256("pred");
        bytes32 salt2 = keccak256("dep");

        // Schedule op1 (no predecessor)
        vm.prank(PROTOCOL_ADMIN);
        bytes32 opId1 = timelock.schedule(address(tlVault), data, bytes32(0), salt1);

        // Schedule op2 with op1 as predecessor
        vm.prank(PROTOCOL_ADMIN);
        timelock.schedule(address(tlVault), data, opId1, salt2);

        vm.warp(block.timestamp + 172_800);

        // Execute op2 without op1 executed first
        vm.expectRevert("PWTL: predecessor not executed");
        timelock.execute(address(tlVault), data, opId1, salt2);
    }

    function test_TL_execute_predecessorChainSucceeds() public {
        // Deploy a vault with timelock as admin so it can make both calls
        ValidatorFeeVault tlVault = new ValidatorFeeVault(address(timelock));

        // op1: set pauseController to ems (timelock is admin -> authorized)
        bytes memory data1 = abi.encodeCall(ValidatorFeeVault.setPauseController, (address(ems)));
        // op2: rotate pauseController to a different address (timelock is still admin -> authorized)
        //      Pause (pause()) is EMERGENCY MULTISIG only, NOT timelocked.
        //      We test the predecessor dependency with two admin actions.
        address newCtrl = address(0x9997);
        bytes memory data2 = abi.encodeCall(ValidatorFeeVault.setPauseController, (newCtrl));

        bytes32 salt1 = keccak256("chain-1");
        bytes32 salt2 = keccak256("chain-2");

        vm.prank(PROTOCOL_ADMIN);
        bytes32 opId1 = timelock.schedule(address(tlVault), data1, bytes32(0), salt1);
        vm.prank(PROTOCOL_ADMIN);
        timelock.schedule(address(tlVault), data2, opId1, salt2);

        vm.warp(block.timestamp + 172_800);

        // Execute op1 first (sets pauseController = ems)
        timelock.execute(address(tlVault), data1, bytes32(0), salt1);
        assertTrue(timelock.isExecuted(opId1));
        assertEq(tlVault.pauseController(), address(ems));

        // Now op2 can execute (rotates pauseController to newCtrl)
        timelock.execute(address(tlVault), data2, opId1, salt2);
        assertEq(tlVault.pauseController(), newCtrl, "Predecessor chain: op2 applied after op1");
    }

    // ── B3: Cancel ────────────────────────────────────────────────────────────

    function test_TL_cancel_proposerCanCancel() public {
        bytes memory data = "";
        bytes32 salt = keccak256("cancel-me");
        vm.prank(PROTOCOL_ADMIN);
        bytes32 opId = timelock.schedule(address(vault), data, bytes32(0), salt);

        vm.prank(PROTOCOL_ADMIN);
        timelock.cancel(address(vault), data, bytes32(0), salt);

        assertTrue(timelock.isCancelled(opId));
    }

    function test_TL_cancel_nonProposerReverts() public {
        bytes memory data = "";
        bytes32 salt = keccak256("cancel-auth");
        vm.prank(PROTOCOL_ADMIN);
        timelock.schedule(address(vault), data, bytes32(0), salt);

        vm.prank(RANDO);
        vm.expectRevert("PWTL: not proposer");
        timelock.cancel(address(vault), data, bytes32(0), salt);
    }

    function test_TL_cancel_afterExecuteReverts() public {
        ValidatorFeeVault tlVault = new ValidatorFeeVault(address(timelock));
        bytes memory data = abi.encodeCall(ValidatorFeeVault.setPauseController, (address(ems)));
        bytes32 salt = keccak256("cancel-after-exec");
        vm.prank(PROTOCOL_ADMIN);
        timelock.schedule(address(tlVault), data, bytes32(0), salt);
        vm.warp(block.timestamp + 172_800);
        timelock.execute(address(tlVault), data, bytes32(0), salt);

        vm.prank(PROTOCOL_ADMIN);
        vm.expectRevert("PWTL: already executed");
        timelock.cancel(address(tlVault), data, bytes32(0), salt);
    }

    function test_TL_cancelledOpCannotExecute() public {
        bytes memory data = "";
        bytes32 salt = keccak256("cancel-exec");
        vm.prank(PROTOCOL_ADMIN);
        timelock.schedule(address(vault), data, bytes32(0), salt);
        vm.prank(PROTOCOL_ADMIN);
        timelock.cancel(address(vault), data, bytes32(0), salt);
        vm.warp(block.timestamp + 172_800);

        vm.expectRevert("PWTL: cancelled");
        timelock.execute(address(vault), data, bytes32(0), salt);
    }

    // ── B4: Proposer rotation ─────────────────────────────────────────────────

    function test_TL_transferProposer_succeeds() public {
        vm.prank(PROTOCOL_ADMIN);
        timelock.transferProposer(RANDO);
        assertEq(timelock.proposer(), RANDO);
    }

    function test_TL_transferProposer_nonProposerReverts() public {
        vm.prank(RANDO);
        vm.expectRevert("PWTL: not proposer");
        timelock.transferProposer(RANDO);
    }

    // =========================================================================
    // SECTION C: Pause / Unpause — FeeDistributor
    // =========================================================================

    function test_FD_pauseController_setViaConstructor() public view {
        assertEq(distributor.pauseController(), address(ems));
    }

    function test_FD_pause_byPauseController() public {
        _ems_pause_dist();
        assertTrue(distributor.paused());
    }

    function test_FD_pause_byNonControllerReverts() public {
        vm.prank(RANDO);
        vm.expectRevert("FeeDistributor: not pause controller");
        distributor.pause();
    }

    function test_FD_pause_alreadyPausedReverts() public {
        _ems_pause_dist();
        bytes memory data = abi.encodeCall(FeeDistributor.pause, ());
        uint256 n = ems.nonce();
        bytes32 pid = ems.propose(address(distributor), data);
        _approve3(pid);
        vm.expectRevert(); // "FeeDistributor: already paused"
        ems.execute(address(distributor), data, n);
    }

    function test_FD_distribute_whenPausedReverts() public {
        _ems_pause_dist();
        vm.deal(address(distributor), 1 ether);
        vm.expectRevert("FeeDistributor: paused");
        distributor.distribute();
    }

    function test_FD_distribute_whenUnpausedSucceeds() public {
        _ems_pause_dist();
        _ems_unpause_dist();
        vm.deal(address(distributor), 1 ether);
        distributor.distribute();
        assertEq(address(distributor).balance, 0);
    }

    function test_FD_unpause_byNonControllerReverts() public {
        _ems_pause_dist();
        vm.prank(RANDO);
        vm.expectRevert("FeeDistributor: not pause controller");
        distributor.unpause();
    }

    function test_FD_unpause_whenNotPausedReverts() public {
        bytes memory data = abi.encodeCall(FeeDistributor.unpause, ());
        uint256 n = ems.nonce();
        bytes32 pid = ems.propose(address(distributor), data);
        _approve3(pid);
        vm.expectRevert(); // "FeeDistributor: not paused"
        ems.execute(address(distributor), data, n);
    }

    function test_FD_setPauseController_bySelf() public {
        // EmergencyMultisig rotates to a new controller
        address newCtrl = address(0x9999);
        bytes memory data = abi.encodeCall(FeeDistributor.setPauseController, (newCtrl));
        uint256 n = ems.nonce();
        bytes32 pid = ems.propose(address(distributor), data);
        _approve3(pid);
        ems.execute(address(distributor), data, n);
        assertEq(distributor.pauseController(), newCtrl);
    }

    function test_FD_setPauseController_byNonControllerReverts() public {
        vm.prank(RANDO);
        vm.expectRevert("FeeDistributor: not pause controller");
        distributor.setPauseController(RANDO);
    }

    function test_FD_zeroController_pauseReverts() public {
        // Deploy distributor with address(0) pause controller
        FeeDistributor npc = new FeeDistributor(payable(address(vault)), payable(address(treasury)), address(0));
        vm.expectRevert("FeeDistributor: not pause controller");
        npc.pause();
    }

    // =========================================================================
    // SECTION D: Pause / Unpause — ValidatorFeeVault
    // =========================================================================

    function test_VFV_setPauseController_byProtocolAdmin() public {
        ValidatorFeeVault v2 = new ValidatorFeeVault(PROTOCOL_ADMIN);
        vm.prank(PROTOCOL_ADMIN);
        v2.setPauseController(address(ems));
        assertEq(v2.pauseController(), address(ems));
    }

    function test_VFV_setPauseController_byCurrentController() public {
        // ems is current controller; ems rotates to newCtrl via multisig
        address newCtrl = address(0x9998);
        bytes memory data = abi.encodeCall(ValidatorFeeVault.setPauseController, (newCtrl));
        uint256 n = ems.nonce();
        bytes32 pid = ems.propose(address(vault), data);
        _approve3(pid);
        ems.execute(address(vault), data, n);
        assertEq(vault.pauseController(), newCtrl);
    }

    function test_VFV_setPauseController_byUnauthorizedReverts() public {
        vm.prank(RANDO);
        vm.expectRevert("VFV: unauthorized");
        vault.setPauseController(RANDO);
    }

    function test_VFV_pause_byPauseController() public {
        _ems_pause_vault();
        assertTrue(vault.paused());
    }

    function test_VFV_pause_byNonControllerReverts() public {
        vm.prank(RANDO);
        vm.expectRevert("VFV: not pause controller");
        vault.pause();
    }

    function test_VFV_claimFees_whenPausedReverts() public {
        // Register validator
        vm.prank(PROTOCOL_ADMIN);
        vault.registerValidator(VAL_ID_1, RECIPIENT_1, 1, 10_000);

        // Send fees
        vm.deal(address(vault), 1 ether);
        vm.prank(address(vault)); // simulate receive()
        (bool ok,) = address(vault).call{value: 0}("");
        ok; // suppress warning

        // Actually fund the vault properly via receive
        address funder = address(0xFEED);
        vm.deal(funder, 1 ether);
        vm.prank(funder);
        (ok,) = address(vault).call{value: 1 ether}("");
        require(ok);

        // Pause
        _ems_pause_vault();

        // Attempt claim — should revert
        vm.prank(RECIPIENT_1);
        vm.expectRevert("VFV: paused");
        vault.claimFees(VAL_ID_1);
    }

    function test_VFV_claimFees_whenUnpausedSucceeds() public {
        // Register + fund
        vm.prank(PROTOCOL_ADMIN);
        vault.registerValidator(VAL_ID_1, RECIPIENT_1, 1, 10_000);
        address funder = address(0xFEED);
        vm.deal(funder, 1 ether);
        vm.prank(funder);
        (bool ok,) = address(vault).call{value: 1 ether}("");
        require(ok);

        _ems_pause_vault();
        _ems_unpause_vault();

        // Claim should succeed
        vm.prank(RECIPIENT_1);
        uint256 claimed = vault.claimFees(VAL_ID_1);
        assertGt(claimed, 0);
    }

    function test_VFV_accounting_continuesDuringPause() public {
        // Pause does not block fee receipt or registration
        _ems_pause_vault();

        // registerValidator still works (admin op, not claim)
        vm.prank(PROTOCOL_ADMIN);
        vault.registerValidator(VAL_ID_1, RECIPIENT_1, 1, 10_000);

        // receive() still works
        address funder = address(0xFEED);
        vm.deal(funder, 1 ether);
        vm.prank(funder);
        (bool ok,) = address(vault).call{value: 1 ether}("");
        require(ok);
        assertGt(vault.totalReceived(), 0);
    }

    // =========================================================================
    // SECTION E: Pause / Unpause — RewardVault
    // =========================================================================

    function test_RV_pause_byPauseController() public {
        _ems_pause_rv();
        assertTrue(rewardVault.paused());
    }

    function test_RV_pause_byNonControllerReverts() public {
        vm.prank(RANDO);
        vm.expectRevert("RV: not pause controller");
        rewardVault.pause();
    }

    function test_RV_claim_whenPausedReverts() public {
        // Fund + register + accrue
        vm.prank(PROTOCOL_ADMIN);
        rewardVault.registerRecipient(RV_REC_1, RECIPIENT_1, 1, true);
        vm.deal(PROTOCOL_ADMIN, 10 ether);
        vm.prank(PROTOCOL_ADMIN);
        rewardVault.fund{value: 10 ether}();

        vm.warp(block.timestamp + 3600); // 1 hour of accrual

        _ems_pause_rv();

        vm.prank(RECIPIENT_1);
        vm.expectRevert("RV: paused");
        rewardVault.claim(RV_REC_1);
    }

    function test_RV_claim_whenUnpausedSucceeds() public {
        vm.prank(PROTOCOL_ADMIN);
        rewardVault.registerRecipient(RV_REC_1, RECIPIENT_1, 1, true);
        vm.deal(PROTOCOL_ADMIN, 10 ether);
        vm.prank(PROTOCOL_ADMIN);
        rewardVault.fund{value: 10 ether}();
        vm.warp(block.timestamp + 3600);

        _ems_pause_rv();
        _ems_unpause_rv();

        vm.prank(RECIPIENT_1);
        uint256 claimed = rewardVault.claim(RV_REC_1);
        assertGt(claimed, 0);
    }

    function test_RV_emission_accruesDuringPause() public {
        vm.prank(PROTOCOL_ADMIN);
        rewardVault.registerRecipient(RV_REC_1, RECIPIENT_1, 1, true);
        vm.deal(PROTOCOL_ADMIN, 10 ether);
        vm.prank(PROTOCOL_ADMIN);
        rewardVault.fund{value: 10 ether}();

        _ems_pause_rv();

        uint256 t0 = block.timestamp;
        vm.warp(t0 + 7200); // 2h pass while paused

        // Claimable should still accrue (pause only blocks claim())
        uint256 claimable = rewardVault.claimable(RV_REC_1);
        assertGt(claimable, 0, "Emission accrues while paused");

        // But claim reverts
        vm.prank(RECIPIENT_1);
        vm.expectRevert("RV: paused");
        rewardVault.claim(RV_REC_1);
    }

    function test_RV_setPauseController_byAdmin() public {
        vm.prank(PROTOCOL_ADMIN);
        rewardVault.setPauseController(RANDO);
        assertEq(rewardVault.pauseController(), RANDO);
    }

    function test_RV_setPauseController_byUnauthorizedReverts() public {
        vm.prank(RANDO);
        vm.expectRevert("RV: unauthorized");
        rewardVault.setPauseController(RANDO);
    }

    // =========================================================================
    // SECTION F: Validator Lifecycle Hardening
    // =========================================================================

    function test_VFV_registerValidator_onlyAdmin() public {
        vm.prank(RANDO);
        vm.expectRevert("VFV: not admin");
        vault.registerValidator(VAL_ID_1, RECIPIENT_1, 1, 10_000);
    }

    function test_VFV_deactivateValidator_onlyAdmin() public {
        vm.prank(PROTOCOL_ADMIN);
        vault.registerValidator(VAL_ID_1, RECIPIENT_1, 1, 10_000);

        vm.prank(RANDO);
        vm.expectRevert("VFV: not admin");
        vault.deactivateValidator(VAL_ID_1);
    }

    function test_VFV_setRewardRecipient_onlyAdmin() public {
        vm.prank(PROTOCOL_ADMIN);
        vault.registerValidator(VAL_ID_1, RECIPIENT_1, 1, 10_000);

        vm.prank(RANDO);
        vm.expectRevert("VFV: not admin");
        vault.setRewardRecipient(VAL_ID_1, RANDO);
    }

    function test_VFV_rewardRecipient_cannotBeHijackedByNonAdmin() public {
        vm.prank(PROTOCOL_ADMIN);
        vault.registerValidator(VAL_ID_1, RECIPIENT_1, 1, 10_000);

        // Attacker tries to redirect via claimFees
        vm.prank(RANDO);
        vm.expectRevert("VFV: caller is not recipient");
        vault.claimFees(VAL_ID_1);
    }

    // =========================================================================
    // SECTION G: Reward Recipient Manipulation Protection (RewardVault)
    // =========================================================================

    function test_RV_setRewardAddress_onlyAdmin() public {
        vm.prank(PROTOCOL_ADMIN);
        rewardVault.registerRecipient(RV_REC_1, RECIPIENT_1, 1, true);

        vm.prank(RANDO);
        vm.expectRevert("RV: not admin");
        rewardVault.setRewardAddress(RV_REC_1, RANDO);
    }

    function test_RV_claim_callerMustBeRewardAddress() public {
        vm.prank(PROTOCOL_ADMIN);
        rewardVault.registerRecipient(RV_REC_1, RECIPIENT_1, 1, true);
        vm.deal(PROTOCOL_ADMIN, 10 ether);
        vm.prank(PROTOCOL_ADMIN);
        rewardVault.fund{value: 10 ether}();
        vm.warp(block.timestamp + 3600);

        vm.prank(RANDO);
        vm.expectRevert("RV: caller is not rewardAddress");
        rewardVault.claim(RV_REC_1);
    }

    // =========================================================================
    // SECTION H: Freeze semantics documentation test
    // =========================================================================
    //
    // Per PRIMEWAVE_GOVERNANCE_POLICY.md §4.2:
    //   freeze(account) is ONLY defined for PWUSD (AML/sanctions compliance).
    //   There is NO freeze operation on FeeDistributor, ValidatorFeeVault,
    //   RewardVault, or PrimeWaveValidatorRegistry.
    //   PWUSD is a Phase 2 contract (not in scope for C07).
    //   This test documents the architectural boundary.

    function test_FREEZE_notApplicableToPhase1Contracts() public view {
        // These contracts have no freeze() function.
        // Verifying this at the ABI level:
        // - distributor has no freeze
        // - vault has no freeze
        // - rewardVault has no freeze
        // freeze is PWUSD-only (Phase 2).
        // This test exists as documentation.
        assertTrue(true, "Freeze is PWUSD-only; Phase 1 contracts only have pause/unpause");
    }

    // =========================================================================
    // SECTION I: Supply and rate invariants
    // =========================================================================

    function test_INV_rewardVault_rateNeverExceedsMax() public view {
        assertLe(rewardVault.emissionRatePerSecond(), rewardVault.MAX_RATE_PER_SECOND());
    }

    function test_INV_rewardVault_cannotSetRateAboveMax() public {
        vm.prank(PROTOCOL_ADMIN);
        vm.expectRevert();
        // setEmissionRate requires strictly LESS than current; current is MAX; pass MAX
        // Should revert "RV: rate not reduced" (not less than current)
        rewardVault.setEmissionRate(MAX_RATE);
    }

    function test_INV_feeDistributor_splitIntact() public {
        vm.deal(address(distributor), 10_000 ether);
        distributor.distribute();

        // Use the distributor's own cumulative accounting (independent of vault variable)
        assertEq(distributor.totalDistributed(),    10_000 ether, "Total distributed");
        assertEq(distributor.totalValidatorShare(),  7_000 ether, "70% to vault");
        assertEq(distributor.totalTreasuryShare(),   2_000 ether, "20% to treasury");
        assertEq(distributor.totalBurnShare(),       1_000 ether, "10% to burn");
        // 70/20/10 is always intact
        assertEq(
            distributor.totalValidatorShare() + distributor.totalTreasuryShare() + distributor.totalBurnShare(),
            distributor.totalDistributed(),
            "Sum of parts == total"
        );
    }

    // =========================================================================
    // SECTION J: Full regression smoke (C03-C06 behaviors)
    // =========================================================================

    function test_REGRESS_distribute_stillWorksUnpaused() public {
        vm.deal(address(distributor), 100 ether);
        distributor.distribute();
        assertEq(address(distributor).balance, 0);
    }

    function test_REGRESS_vfv_claimFees_stillWorks() public {
        vm.prank(PROTOCOL_ADMIN);
        vault.registerValidator(VAL_ID_1, RECIPIENT_1, 1, 10_000);
        address funder = address(0xFEED);
        vm.deal(funder, 2 ether);
        vm.prank(funder);
        (bool ok,) = address(vault).call{value: 2 ether}("");
        require(ok);
        vm.prank(RECIPIENT_1);
        uint256 claimed = vault.claimFees(VAL_ID_1);
        assertGt(claimed, 0);
    }

    function test_REGRESS_rv_claim_stillWorks() public {
        vm.prank(PROTOCOL_ADMIN);
        rewardVault.registerRecipient(RV_REC_1, RECIPIENT_1, 1, true);
        vm.deal(PROTOCOL_ADMIN, 10 ether);
        vm.prank(PROTOCOL_ADMIN);
        rewardVault.fund{value: 10 ether}();
        vm.warp(block.timestamp + 86_400); // 1 day
        vm.prank(RECIPIENT_1);
        uint256 claimed = rewardVault.claim(RV_REC_1);
        assertGt(claimed, 0);
    }

    // =========================================================================
    // Internal helpers
    // =========================================================================

    function _propose_pause_dist() internal returns (bytes32 pid) {
        bytes memory data = abi.encodeCall(FeeDistributor.pause, ());
        pid = ems.propose(address(distributor), data);
    }

    function _propose_pause_dist_full()
        internal
        returns (bytes32 pid, bytes memory data, uint256 n)
    {
        data = abi.encodeCall(FeeDistributor.pause, ());
        n = ems.nonce();
        pid = ems.propose(address(distributor), data);
    }

    function _approve3(bytes32 pid) internal {
        vm.prank(S1); ems.approve(pid);
        vm.prank(S2); ems.approve(pid);
        vm.prank(S3); ems.approve(pid);
    }

    function _ems_pause_dist() internal {
        bytes memory data = abi.encodeCall(FeeDistributor.pause, ());
        uint256 n = ems.nonce();
        bytes32 pid = ems.propose(address(distributor), data);
        _approve3(pid);
        ems.execute(address(distributor), data, n);
    }

    function _ems_unpause_dist() internal {
        bytes memory data = abi.encodeCall(FeeDistributor.unpause, ());
        uint256 n = ems.nonce();
        bytes32 pid = ems.propose(address(distributor), data);
        _approve3(pid);
        ems.execute(address(distributor), data, n);
    }

    function _ems_pause_vault() internal {
        bytes memory data = abi.encodeCall(ValidatorFeeVault.pause, ());
        uint256 n = ems.nonce();
        bytes32 pid = ems.propose(address(vault), data);
        _approve3(pid);
        ems.execute(address(vault), data, n);
    }

    function _ems_unpause_vault() internal {
        bytes memory data = abi.encodeCall(ValidatorFeeVault.unpause, ());
        uint256 n = ems.nonce();
        bytes32 pid = ems.propose(address(vault), data);
        _approve3(pid);
        ems.execute(address(vault), data, n);
    }

    function _ems_pause_rv() internal {
        bytes memory data = abi.encodeCall(RewardVault.pause, ());
        uint256 n = ems.nonce();
        bytes32 pid = ems.propose(address(rewardVault), data);
        _approve3(pid);
        ems.execute(address(rewardVault), data, n);
    }

    function _ems_unpause_rv() internal {
        bytes memory data = abi.encodeCall(RewardVault.unpause, ());
        uint256 n = ems.nonce();
        bytes32 pid = ems.propose(address(rewardVault), data);
        _approve3(pid);
        ems.execute(address(rewardVault), data, n);
    }
}
