// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// ============================================================
// PrimeWaveValidatorRegistryFuzz.t.sol -- C05 Fuzz + Invariant Tests
// ============================================================
//
// Covers:
//   FUZZ-1:  Random fee amounts; conservation invariant holds
//   FUZZ-2:  Random weight changes; historical fees preserved exactly
//   FUZZ-3:  Random validator removal order; earned fees not confiscated
//   FUZZ-4:  Random recipient changes; only new recipient can claim
//   FUZZ-5:  Activate/deactivate cycle; conservation across transitions
//   FUZZ-6:  Multiple validators with random weights and fees
//   FUZZ-7:  No cross-validator claim possible
//   FUZZ-8:  Uptime changes; global conservation holds
//
//   INV-A:  balance == totalReceived - totalClaimed (exact)
//   INV-B:  sum(claimable) + unallocated <= balance
//   INV-C:  totalClaimed <= totalReceived
//   INV-D:  Deactivated validator claimable never decreases
// ============================================================

import "forge-std/Test.sol";
import "../src/PrimeWaveValidatorRegistry.sol";
import "../src/ValidatorFeeVault.sol";
import "./MockValidatorManager.sol";

// ── Stateful invariant handler ────────────────────────────────────────────────

contract RegistryHandler is Test {

    MockValidatorManager       public mockVM;
    ValidatorFeeVault          public vault;
    PrimeWaveValidatorRegistry public registry;

    address constant ADMIN = address(0xA1);

    bytes32 constant SUBNET_ID = keccak256("primewavedev-subnet");

    uint256 public constant MAX_VALIDATORS = 10;
    bytes32[10] public vids;
    bytes[10]   public nodeIDs;
    address[10] public recipients;

    uint256 public registeredCount;
    mapping(bytes32 => bool)    public wasDeactivated;
    mapping(bytes32 => uint256) public claimableAtDeactivation;
    mapping(bytes32 => uint256) public claimedAfterDeactivation;

    constructor() {
        for (uint256 i = 0; i < MAX_VALIDATORS; i++) {
            vids[i]       = keccak256(abi.encodePacked("fuzz-validator-", i));
            nodeIDs[i]    = abi.encodePacked(bytes20(keccak256(abi.encodePacked("fuzz-node-", i))));
            recipients[i] = address(uint160(0x2000 + i));
        }

        mockVM = new MockValidatorManager(SUBNET_ID);

        address futureRegistry = address(uint160(uint256(keccak256(abi.encodePacked(
            address(this), vm.getNonce(address(this)) + 1
        )))));
        // Use computeCreateAddress instead
        uint256 nextNonce = vm.getNonce(address(this));
        futureRegistry = vm.computeCreateAddress(address(this), nextNonce + 1);

        vault    = new ValidatorFeeVault(futureRegistry);
        registry = new PrimeWaveValidatorRegistry(ADMIN, address(mockVM), address(vault));

        vm.deal(address(this), 1_000_000 ether);
        vm.deal(ADMIN, 1_000_000 ether);
    }

    function registerNext(uint64 weight) public {
        if (registeredCount >= MAX_VALIDATORS) return;
        weight = uint64(bound(weight, 1, 10));

        bytes32 vid = vids[registeredCount];
        mockVM.devRegisterAndActivate(vid, nodeIDs[registeredCount], weight);

        vm.prank(ADMIN);
        registry.registerValidator(vid, recipients[registeredCount], weight);
        registeredCount++;
    }

    function sendFees(uint128 amount) public {
        if (registeredCount == 0) return;
        amount = uint128(bound(amount, 1, 100 ether));
        (bool ok,) = address(vault).call{value: amount}("");
        ok; // silence unused warning
    }

    function deactivate(uint8 idx) public {
        if (registeredCount == 0) return;
        idx = uint8(bound(idx, 0, registeredCount - 1));
        bytes32 vid = vids[idx];

        ValidatorACP99 memory v = mockVM.getValidator(vid);
        if (v.status != ValidatorStatus.Active) return;

        claimableAtDeactivation[vid] = vault.claimable(vid);
        wasDeactivated[vid] = true;

        mockVM.devInitiateRemoval(vid);
        registry.syncValidator(vid);
    }

    function syncOne(uint8 idx) public {
        if (registeredCount == 0) return;
        idx = uint8(bound(idx, 0, registeredCount - 1));
        registry.syncValidator(vids[idx]);
    }

    function updateWeight(uint8 idx, uint64 newWeight) public {
        if (registeredCount == 0) return;
        idx = uint8(bound(idx, 0, registeredCount - 1));
        newWeight = uint64(bound(newWeight, 1, 20));
        bytes32 vid = vids[idx];

        ValidatorACP99 memory v = mockVM.getValidator(vid);
        if (v.status != ValidatorStatus.Active) return;

        mockVM.devSetWeight(vid, newWeight);
        registry.updateWeight(vid);
    }

    function claim(uint8 idx) public {
        if (registeredCount == 0) return;
        idx = uint8(bound(idx, 0, registeredCount - 1));
        bytes32 vid = vids[idx];

        uint256 c = vault.claimable(vid);
        if (c == 0) return;

        (address recip,,,,,,) = vault.validators(vid);
        vm.prank(recip);
        uint256 claimed = vault.claimFees(vid);
        // Track post-deactivation claims so INV-D can account for them
        if (wasDeactivated[vid]) {
            claimedAfterDeactivation[vid] += claimed;
        }
    }
}

// ── Invariant test contract ────────────────────────────────────────────────────

contract PrimeWaveValidatorRegistryInvariant is Test {

    RegistryHandler handler;

    function setUp() public {
        handler = new RegistryHandler();
        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = RegistryHandler.registerNext.selector;
        selectors[1] = RegistryHandler.sendFees.selector;
        selectors[2] = RegistryHandler.deactivate.selector;
        selectors[3] = RegistryHandler.syncOne.selector;
        selectors[4] = RegistryHandler.updateWeight.selector;
        selectors[5] = RegistryHandler.claim.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// INV-A: balance == totalReceived - totalClaimed (exact conservation)
    function invariant_A_BalanceConservation() public view {
        ValidatorFeeVault vault = handler.vault();
        assertEq(
            vault.vaultBalance(),
            vault.totalReceived() - vault.totalClaimed(),
            "INV-A: balance != totalReceived - totalClaimed"
        );
    }

    /// INV-B: sum(claimable) + unallocated <= balance (no over-allocation)
    function invariant_B_NoOverAllocation() public view {
        ValidatorFeeVault vault = handler.vault();
        uint256 totalClaimable = 0;
        uint256 n = handler.registeredCount();
        for (uint256 i = 0; i < n; i++) {
            totalClaimable += vault.claimable(handler.vids(i));
        }
        assertLe(
            totalClaimable + vault.unallocated(),
            vault.vaultBalance() + 1, // +1 for rounding dust
            "INV-B: over-allocation"
        );
    }

    /// INV-C: totalClaimed <= totalReceived (no fee creation)
    function invariant_C_NoFeeCreation() public view {
        ValidatorFeeVault vault = handler.vault();
        assertLe(vault.totalClaimed(), vault.totalReceived(), "INV-C: fee creation");
    }

    /// INV-D: Deactivated validator's (claimable + claimed-after-deactivation) >= claimable-at-deactivation
    ///        i.e. earned fees are never confiscated, only legitimately claimed.
    function invariant_D_DeactivatedFeesNotConfiscated() public view {
        ValidatorFeeVault vault = handler.vault();
        uint256 n = handler.registeredCount();
        for (uint256 i = 0; i < n; i++) {
            bytes32 vid = handler.vids(i);
            if (handler.wasDeactivated(vid)) {
                uint256 atDeact  = handler.claimableAtDeactivation(vid);
                uint256 current  = vault.claimable(vid);
                uint256 claimed  = handler.claimedAfterDeactivation(vid);
                assertGe(current + claimed, atDeact,
                    "INV-D: fees confiscated on deactivation (not just claimed)");
            }
        }
    }
}

// ── Standalone fuzz tests ─────────────────────────────────────────────────────

contract PrimeWaveValidatorRegistryFuzz is Test {

    address constant ADMIN = address(0xA1);
    bytes32 constant SUBNET_ID = keccak256("primewavedev-subnet");

    MockValidatorManager       mockVM;
    ValidatorFeeVault          vault;
    PrimeWaveValidatorRegistry registry;

    bytes32[5] vids;
    bytes[5]   nodeIDs;

    function setUp() public {
        for (uint256 i = 0; i < 5; i++) {
            vids[i]    = keccak256(abi.encodePacked("fuzz-validator-", i));
            nodeIDs[i] = abi.encodePacked(bytes20(keccak256(abi.encodePacked("fuzz-node-", i))));
        }

        mockVM = new MockValidatorManager(SUBNET_ID);
        address futureRegistry = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        vault    = new ValidatorFeeVault(futureRegistry);
        registry = new PrimeWaveValidatorRegistry(ADMIN, address(mockVM), address(vault));

        vm.deal(address(this), 1_000_000 ether);
        vm.deal(ADMIN, 1_000_000 ether);
    }

    /// FUZZ-1: Random fee amounts; conservation invariant holds
    function testFuzz_F1_RandomFees_Conservation(uint128 amount1, uint128 amount2, uint128 amount3) public {
        amount1 = uint128(bound(amount1, 1, 1_000 ether));
        amount2 = uint128(bound(amount2, 1, 1_000 ether));
        amount3 = uint128(bound(amount3, 1, 1_000 ether));

        for (uint256 i = 0; i < 3; i++) {
            mockVM.devRegisterAndActivate(vids[i], nodeIDs[i], 1);
            vm.prank(ADMIN);
            registry.registerValidator(vids[i], address(uint160(0x3000 + i)), 1);
        }

        (bool ok1,) = address(vault).call{value: amount1}(""); require(ok1);
        (bool ok2,) = address(vault).call{value: amount2}(""); require(ok2);
        (bool ok3,) = address(vault).call{value: amount3}(""); require(ok3);

        assertEq(vault.vaultBalance(), vault.totalReceived() - vault.totalClaimed());
        uint256 sumC = 0;
        for (uint256 i = 0; i < 3; i++) sumC += vault.claimable(vids[i]);
        assertLe(sumC, vault.vaultBalance() + 1);
    }

    /// FUZZ-2: Random weight changes; historical fees preserved exactly
    function testFuzz_F2_WeightChange_HistoricalFeesPreserved(uint64 newWeight, uint128 feeAmount) public {
        newWeight = uint64(bound(newWeight, 1, 100));
        feeAmount = uint128(bound(feeAmount, 2, 1_000 ether));

        for (uint256 i = 0; i < 2; i++) {
            mockVM.devRegisterAndActivate(vids[i], nodeIDs[i], 1);
            vm.prank(ADMIN);
            registry.registerValidator(vids[i], address(uint160(0x3000 + i)), 1);
        }

        (bool ok,) = address(vault).call{value: feeAmount}(""); require(ok);
        uint256 earned0 = vault.claimable(vids[0]);
        uint256 earned1 = vault.claimable(vids[1]);

        mockVM.devSetWeight(vids[0], newWeight);
        registry.updateWeight(vids[0]);

        assertEq(vault.claimable(vids[0]), earned0, "FUZZ-2: v0 historical fee corrupted");
        assertEq(vault.claimable(vids[1]), earned1, "FUZZ-2: v1 historical fee corrupted");
    }

    /// FUZZ-3: Random removal order; earned fees not confiscated
    function testFuzz_F3_RemovalOrder_FeesPreserved(uint8 removeFirst, uint128 feesBefore) public {
        removeFirst = uint8(bound(removeFirst, 0, 4));
        feesBefore  = uint128(bound(feesBefore, 5, 500 ether));

        for (uint256 i = 0; i < 5; i++) {
            mockVM.devRegisterAndActivate(vids[i], nodeIDs[i], 1);
            vm.prank(ADMIN);
            registry.registerValidator(vids[i], address(uint160(0x4000 + i)), 1);
        }

        (bool ok,) = address(vault).call{value: feesBefore}(""); require(ok);
        uint256 claimableBeforeRemoval = vault.claimable(vids[removeFirst]);

        mockVM.devInitiateRemoval(vids[removeFirst]);
        registry.syncValidator(vids[removeFirst]);

        assertEq(vault.claimable(vids[removeFirst]), claimableBeforeRemoval,
            "FUZZ-3: fees confiscated on deactivation");

        assertEq(vault.vaultBalance(), vault.totalReceived() - vault.totalClaimed());
    }

    /// FUZZ-4: Random recipient changes; only new recipient can claim
    function testFuzz_F4_RecipientChange_OnlyNewCanClaim(uint128 feeAmount, address newRecipient) public {
        vm.assume(newRecipient != address(0));
        vm.assume(uint160(newRecipient) > 0x100); // avoid precompiles
        vm.assume(newRecipient != address(vault));
        vm.assume(newRecipient != address(registry));
        vm.assume(newRecipient != address(mockVM));
        // Exclude Foundry's VM contract address — it rejects native transfers
        vm.assume(newRecipient != 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        // Exclude the test contract's own address — no payable receive(), ETH transfer reverts
        vm.assume(newRecipient != address(this));
        // This property asserts successful payment to an EOA. Foundry also
        // installs the CREATE2 factory at0x4e59..., which has no payable receive.
        // Exclude all deployed contracts rather than hardcoding another address.
        vm.assume(newRecipient.code.length == 0);
        feeAmount = uint128(bound(feeAmount, 1, 100 ether));

        bytes32 vid = vids[0];
        address origRecipient = address(0x4001);
        mockVM.devRegisterAndActivate(vid, nodeIDs[0], 1);
        vm.prank(ADMIN);
        registry.registerValidator(vid, origRecipient, 1);

        (bool ok,) = address(vault).call{value: feeAmount}(""); require(ok);

        vm.prank(ADMIN);
        registry.setRewardRecipient(vid, newRecipient);

        if (origRecipient != newRecipient) {
            vm.prank(origRecipient);
            vm.expectRevert("VFV: caller is not recipient");
            vault.claimFees(vid);
        }

        vm.deal(newRecipient, 1 ether);
        vm.prank(newRecipient);
        uint256 claimed = vault.claimFees(vid);
        assertGe(claimed, feeAmount - 1);
    }

    /// FUZZ-5: Activate/deactivate cycle; conservation across all transitions
    function testFuzz_F5_ActivationCycle_Conservation(uint128 fee1, uint128 fee2, uint128 fee3) public {
        fee1 = uint128(bound(fee1, 1, 100 ether));
        fee2 = uint128(bound(fee2, 1, 100 ether));
        fee3 = uint128(bound(fee3, 1, 100 ether));

        bytes32 vid0 = vids[0];
        bytes32 vid1 = vids[1];

        for (uint256 i = 0; i < 2; i++) {
            mockVM.devRegisterAndActivate(vids[i], nodeIDs[i], 1);
            vm.prank(ADMIN);
            registry.registerValidator(vids[i], address(uint160(0x5000 + i)), 1);
        }

        (bool ok1,) = address(vault).call{value: fee1}(""); require(ok1);

        mockVM.devInitiateRemoval(vid0);
        registry.syncValidator(vid0);

        (bool ok2,) = address(vault).call{value: fee2}(""); require(ok2);

        // Re-activate vid0
        mockVM.devForceStatus(vid0, ValidatorStatus.Active);
        registry.syncValidator(vid0);

        (bool ok3,) = address(vault).call{value: fee3}(""); require(ok3);

        assertEq(vault.vaultBalance(), vault.totalReceived() - vault.totalClaimed(),
            "FUZZ-5: conservation violated");

        uint256 sumC = vault.claimable(vid0) + vault.claimable(vid1);
        assertLe(sumC + vault.unallocated(), vault.vaultBalance() + 1,
            "FUZZ-5: over-allocation");
    }

    /// FUZZ-6: Multiple validators, weight updates and fee accrual
    function testFuzz_F6_MultiValidator_WeightUpdate(
        uint64 w1, uint64 w2, uint64 w3, uint128 fees
    ) public {
        w1   = uint64(bound(w1, 1, 10));
        w2   = uint64(bound(w2, 1, 10));
        w3   = uint64(bound(w3, 1, 10));
        fees = uint128(bound(fees, 100, 100 ether));

        for (uint256 i = 0; i < 3; i++) {
            uint64 w = (i == 0) ? w1 : (i == 1) ? w2 : w3;
            mockVM.devRegisterAndActivate(vids[i], nodeIDs[i], w);
            vm.prank(ADMIN);
            registry.registerValidator(vids[i], address(uint160(0x6000 + i)), w);
        }

        (bool ok,) = address(vault).call{value: fees}(""); require(ok);

        uint256 total = vault.totalEffectiveWeight();
        assertEq(total, w1 + w2 + w3);

        for (uint256 i = 0; i < 3; i++) {
            uint64 w = (i == 0) ? w1 : (i == 1) ? w2 : w3;
            uint256 expected = (uint256(fees) * w) / total;
            assertLe(vault.claimable(vids[i]), expected + 1);
        }

        assertEq(vault.vaultBalance(), vault.totalReceived() - vault.totalClaimed());
    }

    /// FUZZ-7: No cross-validator claim possible
    function testFuzz_F7_NoCrossValidatorClaim(uint128 feeAmount) public {
        feeAmount = uint128(bound(feeAmount, 1 ether, 100 ether));

        address alice = address(0xAA11);
        address bob   = address(0xBB22);

        mockVM.devRegisterAndActivate(vids[0], nodeIDs[0], 1);
        vm.prank(ADMIN);
        registry.registerValidator(vids[0], alice, 1);

        mockVM.devRegisterAndActivate(vids[1], nodeIDs[1], 1);
        vm.prank(ADMIN);
        registry.registerValidator(vids[1], bob, 1);

        (bool ok,) = address(vault).call{value: feeAmount}(""); require(ok);

        vm.prank(alice);
        vm.expectRevert("VFV: caller is not recipient");
        vault.claimFees(vids[1]);

        vm.prank(bob);
        vm.expectRevert("VFV: caller is not recipient");
        vault.claimFees(vids[0]);

        vm.deal(alice, 1 ether);
        vm.deal(bob, 1 ether);
        vm.prank(alice);
        uint256 aliceClaimed = vault.claimFees(vids[0]);
        vm.prank(bob);
        uint256 bobClaimed   = vault.claimFees(vids[1]);

        assertGe(aliceClaimed, feeAmount / 2 - 1);
        assertGe(bobClaimed,   feeAmount / 2 - 1);
        assertLe(aliceClaimed + bobClaimed, feeAmount);
    }

    /// FUZZ-8: Uptime changes; global conservation holds
    function testFuzz_F8_UptimeChange_GlobalConsistency(uint16 newBips, uint128 fees) public {
        newBips = uint16(bound(newBips, 0, 10_000));
        fees    = uint128(bound(fees, 1, 100 ether));

        for (uint256 i = 0; i < 3; i++) {
            mockVM.devRegisterAndActivate(vids[i], nodeIDs[i], 10);
            vm.prank(ADMIN);
            registry.registerValidator(vids[i], address(uint160(0x7000 + i)), 10);
        }

        (bool ok,) = address(vault).call{value: fees}(""); require(ok);

        vm.prank(ADMIN);
        registry.setUptimeBips(vids[0], newBips);

        (bool ok2,) = address(vault).call{value: fees}(""); require(ok2);

        assertEq(vault.vaultBalance(), vault.totalReceived() - vault.totalClaimed(),
            "FUZZ-8: conservation violated after uptime change");
    }
}
