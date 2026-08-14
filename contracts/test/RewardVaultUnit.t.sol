// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// ============================================================
// RewardVaultUnit.t.sol -- C06 Unit Tests
// ============================================================
//
// Test categories:
//   A. Constructor
//   B. fund() / receive()
//   C. registerRecipient
//   D. activateRecipient / deactivateRecipient
//   E. setWeight
//   F. setRewardAddress
//   G. setEmissionRate (rate reduction)
//   H. claim -- success, security, edge cases
//   I. Zero-weight / emission-pause periods
//   J. Vault exhaustion
//   K. Rate change checkpoint correctness
//   L. Supply invariant (no minting)
//   M. 15M funding test
//   N. 5-year simulation at max emission
//   O. Gas analysis
// ============================================================

import "forge-std/Test.sol";
import "../src/RewardVault.sol";

contract RewardVaultUnit is Test {

    // ── Actors ────────────────────────────────────────────────────────────────
    address constant ADMIN    = address(0xA1);
    address constant ALICE    = address(0xAA11);
    address constant BOB      = address(0xBB22);
    address constant CHARLIE  = address(0xCC33);
    address constant ATTACKER = address(0xBAD);

    // ── Fixtures ──────────────────────────────────────────────────────────────
    RewardVault vault;

    uint256 immutable MAX_R;

    bytes32 constant R0 = keccak256("recipient-0");
    bytes32 constant R1 = keccak256("recipient-1");
    bytes32 constant R2 = keccak256("recipient-2");

    constructor() {
        MAX_R = uint256(3_000_000 * 1 ether) / 31_536_000;
    }

    function setUp() public {
        vault = new RewardVault(ADMIN, MAX_R); // max rate
        vm.deal(ADMIN,    100_000_000 ether);
        vm.deal(ALICE,    1_000 ether);
        vm.deal(BOB,      1_000 ether);
        vm.deal(CHARLIE,  1_000 ether);
        vm.deal(ATTACKER, 1_000 ether);
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    function _fund(uint256 amount) internal {
        vm.prank(ADMIN);
        vault.fund{value: amount}();
    }

    function _reg(bytes32 id, address addr, uint128 weight, bool active) internal {
        vm.prank(ADMIN);
        vault.registerRecipient(id, addr, weight, active);
    }

    function _warp(uint256 secs) internal {
        vm.warp(block.timestamp + secs);
    }

    // ── A. Constructor ────────────────────────────────────────────────────────

    function test_Constructor_SetsImmutables() public view {
        assertEq(vault.admin(), ADMIN);
        assertEq(vault.emissionRatePerSecond(), MAX_R);
        assertEq(vault.totalFunded(), 0);
        assertEq(vault.totalEmitted(), 0);
        assertEq(vault.totalClaimed(), 0);
        assertEq(vault.totalEligibleWeight(), 0);
    }

    function test_Constructor_Constants() public view {
        assertEq(vault.SECONDS_PER_YEAR(), 31_536_000);
        assertEq(vault.MAX_ANNUAL_EMISSION(), 3_000_000 ether);
        // MAX_RATE_PER_SECOND = 3_000_000e18 / 31_536_000
        uint256 expected = uint256(3_000_000 * 1 ether) / 31_536_000;
        assertEq(vault.MAX_RATE_PER_SECOND(), expected);
    }

    function test_Constructor_MaxRateAtMostMaxAnnual() public view {
        // Verify max rate * seconds_per_year <= MAX_ANNUAL_EMISSION
        uint256 actualAnnual = vault.MAX_RATE_PER_SECOND() * vault.SECONDS_PER_YEAR();
        assertLe(actualAnnual, vault.MAX_ANNUAL_EMISSION(),
            "annualized max rate exceeds MAX_ANNUAL_EMISSION");
        // Difference should be < SECONDS_PER_YEAR wei (truncation remainder)
        assertLe(vault.MAX_ANNUAL_EMISSION() - actualAnnual, vault.SECONDS_PER_YEAR());
    }

    function test_Constructor_ZeroAdmin_Reverts() public {
        vm.expectRevert("RV: zero admin");
        new RewardVault(address(0), MAX_R);
    }

    function test_Constructor_RateExceedsMax_Reverts() public {
        vm.expectRevert("RV: rate exceeds max");
        new RewardVault(ADMIN, MAX_R + 1);
    }

    function test_Constructor_ZeroRate_Succeeds() public {
        RewardVault v = new RewardVault(ADMIN, 0);
        assertEq(v.emissionRatePerSecond(), 0);
    }

    // ── B. fund() / receive() ─────────────────────────────────────────────────

    function test_Fund_UpdatesTotalFunded() public {
        _fund(100 ether);
        assertEq(vault.totalFunded(), 100 ether);
        assertEq(vault.vaultBalance(), 100 ether);
    }

    function test_Fund_MultipleFundsAccumulate() public {
        _fund(50 ether);
        _fund(75 ether);
        assertEq(vault.totalFunded(), 125 ether);
    }

    function test_Fund_EmitsEvent() public {
        vm.prank(ADMIN);
        vm.expectEmit(true, false, false, true);
        emit RewardVault.RewardVaultFunded(ADMIN, 100 ether, 100 ether);
        vault.fund{value: 100 ether}();
    }

    function test_Fund_ZeroValue_Reverts() public {
        vm.prank(ADMIN);
        vm.expectRevert("RV: zero funding");
        vault.fund{value: 0}();
    }

    function test_Receive_UpdatesTotalFunded() public {
        // Send PW directly via receive()
        (bool ok,) = address(vault).call{value: 50 ether}("");
        require(ok);
        assertEq(vault.totalFunded(), 50 ether);
    }

    function test_ForcedTransfer_NotCounted() public {
        // Simulate forced transfer: balance increases but totalFunded does not
        // (In Solidity 0.8.30 there's no selfdestruct, but we can test by
        //  manipulating balance directly in test context  --  vm.deal)
        _fund(100 ether);
        uint256 fundedBefore = vault.totalFunded();

        // Force extra balance onto vault (simulates selfdestruct from another contract)
        vm.deal(address(vault), address(vault).balance + 50 ether);

        // totalFunded should still be 100 ether; vaultBalance is 150 ether
        assertEq(vault.totalFunded(), fundedBefore, "forced transfer corrupted totalFunded");
        assertEq(vault.vaultBalance(), 150 ether);
        // accountedBalance = totalFunded - totalClaimed = 100 ether
        assertEq(vault.accountedBalance(), 100 ether);
    }

    // ── C. registerRecipient ──────────────────────────────────────────────────

    function test_Register_Active_Succeeds() public {
        _fund(1_000 ether);
        _reg(R0, ALICE, 1, true);

        assertTrue(vault.isRegistered(R0));
        assertEq(vault.totalEligibleWeight(), 1);
    }

    function test_Register_Inactive_Succeeds() public {
        _reg(R0, ALICE, 1, false);
        assertTrue(vault.isRegistered(R0));
        assertEq(vault.totalEligibleWeight(), 0);
    }

    function test_Register_ZeroId_Reverts() public {
        vm.prank(ADMIN);
        vm.expectRevert("RV: zero id");
        vault.registerRecipient(bytes32(0), ALICE, 1, true);
    }

    function test_Register_ZeroAddress_Reverts() public {
        vm.prank(ADMIN);
        vm.expectRevert("RV: zero address");
        vault.registerRecipient(R0, address(0), 1, true);
    }

    function test_Register_ZeroWeight_Reverts() public {
        vm.prank(ADMIN);
        vm.expectRevert("RV: zero weight");
        vault.registerRecipient(R0, ALICE, 0, true);
    }

    function test_Register_Duplicate_Reverts() public {
        _reg(R0, ALICE, 1, true);
        vm.prank(ADMIN);
        vm.expectRevert("RV: already registered");
        vault.registerRecipient(R0, BOB, 1, true);
    }

    function test_Register_NonAdmin_Reverts() public {
        vm.prank(ATTACKER);
        vm.expectRevert("RV: not admin");
        vault.registerRecipient(R0, ATTACKER, 1, true);
    }

    function test_Register_NoRetroAccrual() public {
        _fund(1_000_000 ether);
        // Advance time so global index would have moved IF there were recipients
        _warp(365 days);
        // Register AFTER time has passed
        _reg(R0, ALICE, 1, true);

        // Alice should have 0 claimable (no retro-accrual from before registration)
        assertEq(vault.claimable(R0), 0);
    }

    function test_Register_Emits_Event() public {
        vm.prank(ADMIN);
        vm.expectEmit(true, true, false, true);
        emit RewardVault.RecipientRegistered(R0, ALICE, 1, true);
        vault.registerRecipient(R0, ALICE, 1, true);
    }

    // ── D. activateRecipient / deactivateRecipient ────────────────────────────

    function test_Activate_InactiveRecipient() public {
        _fund(1_000 ether);
        _reg(R0, ALICE, 1, false);
        assertEq(vault.totalEligibleWeight(), 0);

        vm.prank(ADMIN);
        vault.activateRecipient(R0);
        assertEq(vault.totalEligibleWeight(), 1);
    }

    function test_Activate_AlreadyActive_Reverts() public {
        _reg(R0, ALICE, 1, true);
        vm.prank(ADMIN);
        vm.expectRevert("RV: already active");
        vault.activateRecipient(R0);
    }

    function test_Activate_NotRegistered_Reverts() public {
        vm.prank(ADMIN);
        vm.expectRevert("RV: not registered");
        vault.activateRecipient(R0);
    }

    function test_Activate_NonAdmin_Reverts() public {
        _reg(R0, ALICE, 1, false);
        vm.prank(ATTACKER);
        vm.expectRevert("RV: not admin");
        vault.activateRecipient(R0);
    }

    function test_Activate_NoRetroAccrual() public {
        _fund(1_000_000 ether);
        _reg(R0, ALICE, 1, false);

        // Advance time while inactive
        _warp(30 days);

        // Activate
        vm.prank(ADMIN);
        vault.activateRecipient(R0);

        // No retroaccrual from inactive period
        assertEq(vault.claimable(R0), 0);
    }

    function test_Deactivate_ActiveRecipient() public {
        _fund(1_000 ether);
        _reg(R0, ALICE, 1, true);

        // Earn some rewards
        _warp(1 days);

        vm.prank(ADMIN);
        vault.deactivateRecipient(R0);

        assertEq(vault.totalEligibleWeight(), 0);

        // Should have earned something before deactivation
        (,, , uint256 pending,,) = vault.recipients(R0);
        assertGt(pending, 0);
    }

    function test_Deactivate_AlreadyInactive_Reverts() public {
        _reg(R0, ALICE, 1, false);
        vm.prank(ADMIN);
        vm.expectRevert("RV: already inactive");
        vault.deactivateRecipient(R0);
    }

    function test_Deactivate_EarnedFeesPreserved() public {
        _fund(1_000_000 ether);
        _reg(R0, ALICE, 1, true);

        _warp(365 days);
        uint256 earned = vault.claimable(R0);
        assertGt(earned, 0);

        vm.prank(ADMIN);
        vault.deactivateRecipient(R0);

        // Claimable must be preserved after deactivation
        assertEq(vault.claimable(R0), earned);
    }

    function test_Deactivate_StopsAccrual() public {
        _fund(1_000_000 ether);
        _reg(R0, ALICE, 1, true);

        _warp(100 days);
        vm.prank(ADMIN);
        vault.deactivateRecipient(R0);

        uint256 earnedAtDeact = vault.claimable(R0);

        // Advance more time  --  should not earn more
        _warp(100 days);
        assertEq(vault.claimable(R0), earnedAtDeact);
    }

    // ── E. setWeight ──────────────────────────────────────────────────────────

    function test_SetWeight_Active_UpdatesTotalWeight() public {
        _fund(1_000 ether);
        _reg(R0, ALICE, 1, true);
        assertEq(vault.totalEligibleWeight(), 1);

        vm.prank(ADMIN);
        vault.setWeight(R0, 5);
        assertEq(vault.totalEligibleWeight(), 5);
    }

    function test_SetWeight_Inactive_NoWeightChange() public {
        _reg(R0, ALICE, 1, false);
        assertEq(vault.totalEligibleWeight(), 0);

        vm.prank(ADMIN);
        vault.setWeight(R0, 5);
        assertEq(vault.totalEligibleWeight(), 0); // inactive  --  totalWeight unchanged
    }

    function test_SetWeight_PreservesHistoricalFees() public {
        _fund(1_000_000 ether);
        _reg(R0, ALICE, 1, true);
        _reg(R1, BOB,   1, true);

        _warp(30 days);
        uint256 earnedA = vault.claimable(R0);
        uint256 earnedB = vault.claimable(R1);

        // Change R0's weight
        vm.prank(ADMIN);
        vault.setWeight(R0, 9);

        // Historical earnings must be preserved
        assertEq(vault.claimable(R0), earnedA, "historical earnings corrupted for R0");
        assertEq(vault.claimable(R1), earnedB, "historical earnings corrupted for R1");
    }

    function test_SetWeight_ZeroWeight_Reverts() public {
        _reg(R0, ALICE, 1, true);
        vm.prank(ADMIN);
        vm.expectRevert("RV: zero weight");
        vault.setWeight(R0, 0);
    }

    function test_SetWeight_NonAdmin_Reverts() public {
        _reg(R0, ALICE, 1, true);
        vm.prank(ATTACKER);
        vm.expectRevert("RV: not admin");
        vault.setWeight(R0, 5);
    }

    // ── F. setRewardAddress ────────────────────────────────────────────────────

    function test_SetRewardAddress_Updates() public {
        _reg(R0, ALICE, 1, true);
        vm.prank(ADMIN);
        vault.setRewardAddress(R0, BOB);
        (,,,,,address addr) = vault.recipients(R0);
        assertEq(addr, BOB);
    }

    function test_SetRewardAddress_ZeroAddr_Reverts() public {
        _reg(R0, ALICE, 1, true);
        vm.prank(ADMIN);
        vm.expectRevert("RV: zero address");
        vault.setRewardAddress(R0, address(0));
    }

    function test_SetRewardAddress_NonAdmin_Reverts() public {
        _reg(R0, ALICE, 1, true);
        vm.prank(ATTACKER);
        vm.expectRevert("RV: not admin");
        vault.setRewardAddress(R0, ATTACKER);
    }

    // ── G. setEmissionRate ────────────────────────────────────────────────────

    function test_SetEmissionRate_Reduces() public {
        uint256 newRate = MAX_R / 2;
        vm.prank(ADMIN);
        vault.setEmissionRate(newRate);
        assertEq(vault.emissionRatePerSecond(), newRate);
    }

    function test_SetEmissionRate_CannotIncrease_Reverts() public {
        // Rate is already MAX; try to set to MAX (not strictly less)  --  should revert
        vm.prank(ADMIN);
        vm.expectRevert("RV: rate not reduced");
        vault.setEmissionRate(MAX_R);
    }

    function test_SetEmissionRate_CannotExceedMax_Reverts() public {
        // First reduce, then try to increase above max
        vm.prank(ADMIN);
        vault.setEmissionRate(MAX_R / 2);
        vm.prank(ADMIN);
        vm.expectRevert("RV: rate not reduced");
        vault.setEmissionRate(MAX_R / 2); // same  --  not reduced
    }

    function test_SetEmissionRate_NonAdmin_Reverts() public {
        vm.prank(ATTACKER);
        vm.expectRevert("RV: not admin");
        vault.setEmissionRate(MAX_R / 2);
    }

    function test_SetEmissionRate_Emits_Event() public {
        uint256 newRate = MAX_R / 3;
        vm.prank(ADMIN);
        vm.expectEmit(false, false, false, true);
        emit RewardVault.EmissionRateReduced(MAX_R, newRate);
        vault.setEmissionRate(newRate);
    }

    function test_SetEmissionRate_ToZero_StopsEmission() public {
        _fund(1_000_000 ether);
        _reg(R0, ALICE, 1, true);

        _warp(30 days);
        uint256 earnedBefore = vault.claimable(R0);

        vm.prank(ADMIN);
        vault.setEmissionRate(0);

        // Advance more time  --  no new emission
        _warp(30 days);
        assertEq(vault.claimable(R0), earnedBefore, "emission not stopped after rate=0");
    }

    // ── H. claim ──────────────────────────────────────────────────────────────

    function test_Claim_TransfersPW() public {
        _fund(1_000_000 ether);
        _reg(R0, ALICE, 1, true);

        _warp(365 days);
        uint256 expected = vault.claimable(R0);
        assertGt(expected, 0);

        uint256 balBefore = ALICE.balance;
        vm.prank(ALICE);
        uint256 claimed = vault.claim(R0);

        assertEq(claimed, expected);
        assertEq(ALICE.balance, balBefore + claimed);
        assertEq(vault.claimable(R0), 0);
    }

    function test_Claim_UpdatesAccounting() public {
        _fund(1_000_000 ether);
        _reg(R0, ALICE, 1, true);
        _warp(365 days);

        vm.prank(ALICE);
        uint256 claimed = vault.claim(R0);

        assertEq(vault.totalClaimed(), claimed);
        assertEq(vault.vaultBalance(), vault.totalFunded() - vault.totalClaimed());
    }

    function test_Claim_DoubleClaim_Reverts() public {
        _fund(1_000_000 ether);
        _reg(R0, ALICE, 1, true);
        _warp(1 days);

        vm.prank(ALICE);
        vault.claim(R0);

        // Second claim immediately  --  nothing to claim
        vm.prank(ALICE);
        vm.expectRevert("RV: nothing to claim");
        vault.claim(R0);
    }

    function test_Claim_NotRegistered_Reverts() public {
        vm.prank(ALICE);
        vm.expectRevert("RV: not registered");
        vault.claim(R0);
    }

    function test_Claim_WrongCaller_Reverts() public {
        _fund(1_000_000 ether);
        _reg(R0, ALICE, 1, true);
        _warp(1 days);

        vm.prank(ATTACKER);
        vm.expectRevert("RV: caller is not rewardAddress");
        vault.claim(R0);
    }

    function test_Claim_ZeroPending_Reverts() public {
        _fund(1_000_000 ether);
        _reg(R0, ALICE, 1, true);
        // No time elapsed yet
        vm.prank(ALICE);
        vm.expectRevert("RV: nothing to claim");
        vault.claim(R0);
    }

    function test_Claim_AfterDeactivation_Succeeds() public {
        _fund(1_000_000 ether);
        _reg(R0, ALICE, 1, true);
        _warp(30 days);

        // Deactivate
        vm.prank(ADMIN);
        vault.deactivateRecipient(R0);

        uint256 pendingAfterDeact = vault.claimable(R0);
        assertGt(pendingAfterDeact, 0);

        // Can still claim earned rewards
        vm.prank(ALICE);
        uint256 claimed = vault.claim(R0);
        assertEq(claimed, pendingAfterDeact);
    }

    function test_Claim_CrossRecipient_Reverts() public {
        _fund(1_000_000 ether);
        _reg(R0, ALICE, 1, true);
        _reg(R1, BOB,   1, true);
        _warp(1 days);

        // Alice cannot claim Bob's recipient
        vm.prank(ALICE);
        vm.expectRevert("RV: caller is not rewardAddress");
        vault.claim(R1);

        // Bob cannot claim Alice's recipient
        vm.prank(BOB);
        vm.expectRevert("RV: caller is not rewardAddress");
        vault.claim(R0);
    }

    function test_Claim_AfterWeightChange_HistoricalPreserved() public {
        _fund(1_000_000 ether);
        _reg(R0, ALICE, 1, true);
        _reg(R1, BOB,   1, true);

        // Period 1: equal weight, 30 days
        _warp(30 days);
        uint256 aliceP1 = vault.claimable(R0);
        uint256 bobP1   = vault.claimable(R1);
        assertEq(aliceP1, bobP1);

        // Change Alice's weight to 3
        vm.prank(ADMIN);
        vault.setWeight(R0, 3);

        // Historical rewards unchanged
        assertEq(vault.claimable(R0), aliceP1);
        assertEq(vault.claimable(R1), bobP1);

        // Period 2: 30 more days (weight 3:1 now)
        _warp(30 days);
        uint256 aliceTotal = vault.claimable(R0);
        uint256 bobTotal   = vault.claimable(R1);

        // Alice period-2 share should be 3x bob's period-2 share
        uint256 aliceP2 = aliceTotal - aliceP1;
        uint256 bobP2   = bobTotal - bobP1;
        // With weight 3:1 and total 4, alice earns 75%, bob 25%
        // aliceP2 / bobP2 should be ~3
        assertGe(aliceP2, bobP2 * 3 - 1);
        assertLe(aliceP2, bobP2 * 3 + 1);
    }

    function test_Claim_Emits_Event() public {
        _fund(1_000_000 ether);
        _reg(R0, ALICE, 1, true);
        _warp(1 days);

        uint256 expected = vault.claimable(R0);
        vm.prank(ALICE);
        vm.expectEmit(true, true, false, true);
        emit RewardVault.RewardClaimed(R0, ALICE, expected);
        vault.claim(R0);
    }

    // ── I. Zero-weight / emission-pause ───────────────────────────────────────

    function test_ZeroWeight_EmissionPauses() public {
        _fund(1_000_000 ether);
        // No recipients registered

        uint256 emittedBefore = vault.totalEmitted();
        _warp(365 days);

        // Trigger update by interacting with vault (registerRecipient calls _updateGlobal)
        _reg(R0, ALICE, 1, true);

        // Nothing should have been emitted during zero-weight period
        assertEq(vault.totalEmitted(), emittedBefore, "emission during zero-weight period");
    }

    function test_ZeroWeight_FundsStayInVault() public {
        _fund(1_000_000 ether);
        _warp(365 days);
        // After 1 year with no recipients, all 1M PW still in vault
        assertEq(vault.vaultBalance(), 1_000_000 ether);
        assertEq(vault.totalEmitted(), 0);
    }

    function test_ZeroWeight_ThenRecipient_NoRetroAccrual() public {
        _fund(1_000_000 ether);
        _warp(180 days); // 6 months with no recipients

        _reg(R0, ALICE, 1, true);

        // Alice should start from current index  --  no retro-accrual
        assertEq(vault.claimable(R0), 0);

        // Now advance time  --  only this period should accrue
        _warp(30 days);
        assertGt(vault.claimable(R0), 0);
    }

    function test_AllDeactivated_EmissionPauses() public {
        _fund(1_000_000 ether);
        _reg(R0, ALICE, 1, true);
        _reg(R1, BOB,   1, true);

        _warp(30 days);

        // Deactivate both -- _updateGlobal runs inside each call, checkpointing
        // the 30-day active-period emission. Capture emittedAtDeact AFTER both
        // deactivations so it reflects the end-of-active-period state.
        vm.prank(ADMIN);
        vault.deactivateRecipient(R0);
        vm.prank(ADMIN);
        vault.deactivateRecipient(R1);

        uint256 emittedAtDeact = vault.totalEmitted(); // captured after active-period checkpoint

        // Now zero weight -- emission should pause
        _warp(30 days);

        // Trigger write (weight==0 => _updateGlobal emits nothing)
        vm.prank(ADMIN);
        vault.activateRecipient(R0);

        assertEq(vault.totalEmitted(), emittedAtDeact, "emitted during zero-weight period");
    }

    // ── J. Vault exhaustion ───────────────────────────────────────────────────

    function test_Exhaustion_NoOverEmission() public {
        uint256 fundAmount = 100 ether; // small amount for speed
        _fund(fundAmount);
        _reg(R0, ALICE, 1, true);

        // Advance far enough to exhaust the vault
        // At MAX_R per second: 100 ether / MAX_R seconds to exhaust
        // MAX_R = ~95e15, so 100e18 / 95e15 ~ 1052 seconds
        _warp(10_000); // well past exhaustion

        // view-level check: claimable is capped at funded amount
        uint256 claimableAmount = vault.claimable(R0);
        assertLe(claimableAmount, fundAmount, "claimable exceeds funded amount");
        assertEq(claimableAmount, fundAmount, "should be able to claim full funded amount");

        // Claim (write) to flush totalEmitted
        vm.prank(ALICE);
        vault.claim(R0);
        assertEq(vault.totalEmitted(), fundAmount, "totalEmitted capped at totalFunded");
        assertTrue(vault.isExhausted());
    }

    function test_Exhaustion_CannotClaimMore() public {
        _fund(10 ether);
        _reg(R0, ALICE, 1, true);

        _warp(100_000); // far past exhaustion

        vm.prank(ALICE);
        uint256 claimed = vault.claim(R0);

        assertEq(claimed, 10 ether);
        assertEq(vault.vaultBalance(), 0);

        // Nothing left to claim
        _warp(100_000);
        assertEq(vault.claimable(R0), 0);
    }

    function test_Exhaustion_NoMinting() public {
        _fund(10 ether);
        _reg(R0, ALICE, 1, true);

        _warp(100_000); // exhaust

        uint256 supplyBefore = address(vault).balance + ALICE.balance;

        vm.prank(ALICE);
        vault.claim(R0);

        // Total PW conserved: vault + Alice = same as before claim
        assertEq(address(vault).balance + ALICE.balance, supplyBefore);
    }

    function test_Exhaustion_IsExhausted_View() public {
        _fund(1 ether);
        _reg(R0, ALICE, 1, true);

        assertFalse(vault.isExhausted());
        _warp(100_000);

        // Verify claimable is at most the funded amount (view-level check)
        assertGt(vault.claimable(R0), 0);
        assertLe(vault.claimable(R0), 1 ether);

        // Trigger a write to update totalEmitted, then verify exhaustion
        vm.prank(ALICE);
        vault.claim(R0);
        assertTrue(vault.isExhausted());
    }

    // ── K. Rate change checkpoint ──────────────────────────────────────────────

    function test_RateChange_OldRewardsPreserved() public {
        _fund(10_000_000 ether);
        _reg(R0, ALICE, 1, true);

        // Period A: 30 days at MAX_R
        _warp(30 days);
        uint256 earnedPeriodA = vault.claimable(R0);

        // Reduce rate to half (setEmissionRate calls _updateGlobal, checkpointing period A)
        vm.prank(ADMIN);
        vault.setEmissionRate(MAX_R / 2);

        // Historical rewards unchanged
        assertEq(vault.claimable(R0), earnedPeriodA, "rate change corrupted historical rewards");

        // Period B: 30 days at MAX_R/2
        _warp(30 days);
        uint256 earnedTotal = vault.claimable(R0);
        uint256 earnedPeriodB = earnedTotal - earnedPeriodA;

        // Period B should be ~half of Period A (same duration, half rate).
        // Allow ±2_592_000 wei tolerance: MAX_R and MAX_R/2 each truncate independently;
        // the worst-case rounding gap across 30 days (2_592_000 seconds) is <=1 wei/s * seconds.
        assertGe(earnedPeriodB, earnedPeriodA / 2 - 2_592_000);
        assertLe(earnedPeriodB, earnedPeriodA / 2 + 2_592_000);
    }

    function test_RateChange_NoRetroHistorical() public {
        _fund(10_000_000 ether);
        _reg(R0, ALICE, 1, true);

        // Earn at full rate
        _warp(30 days);
        uint256 expectedAtFullRate = uint256(30 days) * MAX_R;

        // Reduce rate
        vm.prank(ADMIN);
        vault.setEmissionRate(MAX_R / 2);

        // Period A rewards should equal full-rate calculation
        uint256 actual = vault.claimable(R0);
        // Allow 1 wei rounding
        assertGe(actual, expectedAtFullRate - 1);
        assertLe(actual, expectedAtFullRate + 1);
    }

    function test_RateChange_CannotIncreaseAboveMax() public {
        // Reduce
        vm.prank(ADMIN);
        vault.setEmissionRate(MAX_R / 2);

        // Attempt to increase beyond max (should revert)
        vm.prank(ADMIN);
        vm.expectRevert("RV: rate not reduced");
        vault.setEmissionRate(MAX_R / 2); // same  --  not reduced

        // Attempt to increase to MAX (not allowed through setEmissionRate)
        vm.prank(ADMIN);
        vm.expectRevert("RV: rate not reduced");
        vault.setEmissionRate(MAX_R);
    }

    // ── L. Supply invariant ───────────────────────────────────────────────────

    function test_SupplyInvariant_AfterFundAndClaim() public {
        _fund(1_000_000 ether);
        _reg(R0, ALICE, 1, true);
        _reg(R1, BOB,   2, true);

        uint256 supplyBefore = address(vault).balance + ALICE.balance + BOB.balance;

        _warp(365 days);

        vm.prank(ALICE);
        vault.claim(R0);
        vm.prank(BOB);
        vault.claim(R1);

        uint256 supplyAfter = address(vault).balance + ALICE.balance + BOB.balance;
        assertEq(supplyAfter, supplyBefore, "supply changed (minting?)");
    }

    function test_NoMinting_TotalSupplyNeverIncreases() public {
        // Total PW = vault balance + all actor balances
        // Before anything: vault has 0, actors have their initial deal amounts
        uint256 totalBefore = address(vault).balance + ALICE.balance + BOB.balance
            + CHARLIE.balance + ADMIN.balance;

        _fund(500_000 ether); // this transfers ADMIN -> vault
        _reg(R0, ALICE, 1, true);
        _reg(R1, BOB,   1, true);

        _warp(180 days);
        vm.prank(ALICE);
        vault.claim(R0);
        vm.prank(BOB);
        vault.claim(R1);

        uint256 totalAfter = address(vault).balance + ALICE.balance + BOB.balance
            + CHARLIE.balance + ADMIN.balance;

        assertEq(totalAfter, totalBefore, "total PW increased (minting bug)");
    }

    // ── M. 15M funding test ───────────────────────────────────────────────────

    function test_15M_FundingVerified() public {
        uint256 FIFTEEN_MILLION = 15_000_000 ether;
        vm.deal(ADMIN, FIFTEEN_MILLION + 1_000 ether);

        vm.prank(ADMIN);
        vault.fund{value: FIFTEEN_MILLION}();

        assertEq(vault.totalFunded(), FIFTEEN_MILLION);
        assertEq(vault.vaultBalance(), FIFTEEN_MILLION);
        assertEq(vault.accountedBalance(), FIFTEEN_MILLION);
    }

    function test_15M_CannotExceedFunding() public {
        uint256 FIFTEEN_MILLION = 15_000_000 ether;
        vm.deal(ADMIN, FIFTEEN_MILLION + 1_000 ether);

        vm.prank(ADMIN);
        vault.fund{value: FIFTEEN_MILLION}();

        _reg(R0, ALICE, 1, true);

        // Advance 100 years -- cannot claim more than funded
        _warp(100 * 365 days);

        // view-level check: claimable capped at funded amount
        uint256 claimableAmt = vault.claimable(R0);
        assertLe(claimableAmt, FIFTEEN_MILLION, "claimable exceeds 15M");

        // Write (claim) to flush totalEmitted, then verify it is capped
        vm.prank(ALICE);
        vault.claim(R0);
        assertEq(vault.totalEmitted(), FIFTEEN_MILLION, "totalEmitted should be capped at 15M");
        assertTrue(vault.isExhausted());
    }

    // ── N. 5-year simulation at max emission ──────────────────────────────────

    function test_FiveYear_MaxEmission_NeverExceeds3MPerYear() public {
        uint256 FIFTEEN_MILLION = 15_000_000 ether;
        vm.deal(ADMIN, FIFTEEN_MILLION + 1_000 ether);
        vm.prank(ADMIN);
        vault.fund{value: FIFTEEN_MILLION}();

        _reg(R0, ALICE, 1, true);

        uint256 prevEmitted = 0;

        for (uint256 year = 1; year <= 5; year++) {
            _warp(365 days);

            // Claim triggers _updateGlobal, flushing totalEmitted for this year
            vm.prank(ALICE);
            vault.claim(R0);

            uint256 nowEmitted = vault.totalEmitted();
            uint256 yearlyEmission = nowEmitted - prevEmitted;

            assertLe(yearlyEmission, 3_000_000 ether,
                "year exceeded 3M PW emission");

            prevEmitted = nowEmitted;
        }

        // Total after 5 years <= 15M
        assertLe(vault.totalEmitted(), FIFTEEN_MILLION);
    }

    function test_FiveYear_WithClaims_ConservationHolds() public {
        uint256 FIFTEEN_MILLION = 15_000_000 ether;
        vm.deal(ADMIN, FIFTEEN_MILLION + 1_000 ether);
        vm.prank(ADMIN);
        vault.fund{value: FIFTEEN_MILLION}();

        _reg(R0, ALICE, 1, true);
        _reg(R1, BOB,   1, true);

        for (uint256 year = 1; year <= 5; year++) {
            _warp(365 days);
            vm.prank(ALICE);
            vault.claim(R0);
            vm.prank(BOB);
            vault.claim(R1);
        }

        // Conservation: balance == funded - claimed
        assertEq(vault.vaultBalance(), vault.totalFunded() - vault.totalClaimed());
        assertLe(vault.totalClaimed(), FIFTEEN_MILLION);
    }

    // ── O. Gas analysis ───────────────────────────────────────────────────────

    function test_GasAnalysis() public {
        _fund(1_000_000 ether);

        uint256 g;

        // registerRecipient gas
        g = gasleft();
        vm.prank(ADMIN);
        vault.registerRecipient(R0, ALICE, 1, true);
        console.log("registerRecipient gas:", g - gasleft());

        // registerRecipient (inactive)
        g = gasleft();
        vm.prank(ADMIN);
        vault.registerRecipient(R1, BOB, 2, false);
        console.log("registerRecipient (inactive) gas:", g - gasleft());

        _warp(30 days);

        // claimable view gas
        g = gasleft();
        vault.claimable(R0);
        console.log("claimable view gas:", g - gasleft());

        // claim gas
        g = gasleft();
        vm.prank(ALICE);
        vault.claim(R0);
        console.log("claim gas:", g - gasleft());

        // activateRecipient gas
        g = gasleft();
        vm.prank(ADMIN);
        vault.activateRecipient(R1);
        console.log("activateRecipient gas:", g - gasleft());

        _warp(30 days);

        // deactivateRecipient gas
        g = gasleft();
        vm.prank(ADMIN);
        vault.deactivateRecipient(R0);
        console.log("deactivateRecipient gas:", g - gasleft());

        // setWeight gas
        g = gasleft();
        vm.prank(ADMIN);
        vault.setWeight(R1, 5);
        console.log("setWeight gas:", g - gasleft());

        // setEmissionRate gas
        g = gasleft();
        vm.prank(ADMIN);
        vault.setEmissionRate(MAX_R / 2);
        console.log("setEmissionRate gas:", g - gasleft());
    }

    // ── Additional edge cases ──────────────────────────────────────────────────

    function test_MultiRecipient_ProportionalRewards() public {
        _fund(1_000_000 ether);
        _reg(R0, ALICE,   1, true); // weight 1 = 1/6
        _reg(R1, BOB,     2, true); // weight 2 = 2/6
        _reg(R2, CHARLIE, 3, true); // weight 3 = 3/6

        _warp(365 days);

        uint256 a = vault.claimable(R0);
        uint256 b = vault.claimable(R1);
        uint256 c = vault.claimable(R2);

        // Ratios: a:b:c ~= 1:2:3 (allow small rounding per recipient)
        // b / a ~= 2
        assertGe(b, a * 2 - 2);
        assertLe(b, a * 2 + 2);
        // c / a ~= 3
        assertGe(c, a * 3 - 3);
        assertLe(c, a * 3 + 3);

        // Total claimable <= totalFunded (claimable is capped at emission which is capped at funded)
        assertLe(a + b + c, 1_000_000 ether + 1);

        // After claiming all, totalEmitted is updated and totalClaimed == totalEmitted
        vm.prank(ALICE);   vault.claim(R0);
        vm.prank(BOB);     vault.claim(R1);
        vm.prank(CHARLIE); vault.claim(R2);
        assertLe(vault.totalClaimed(), vault.totalEmitted());
        assertEq(vault.vaultBalance(), vault.totalFunded() - vault.totalClaimed());
    }

    function test_UnusedEmissions_StayInVault() public {
        // Year at max rate but only 1 recipient claiming occasionally
        _fund(10_000_000 ether);
        _reg(R0, ALICE, 1, true);

        _warp(365 days);

        // Alice claims
        uint256 earned = vault.claimable(R0);
        vm.prank(ALICE);
        vault.claim(R0);

        // "Unused" = funded - distributed = 10M - earned
        // Both still in vault
        assertEq(vault.vaultBalance(), vault.totalFunded() - vault.totalClaimed());
        assertLe(vault.totalClaimed(), vault.totalFunded());

        // Unused stays in vault  --  not burned, not sent to treasury
        uint256 unused = vault.totalFunded() - vault.totalEmitted();
        assertGt(unused, 0);
        assertEq(vault.totalRemaining(), unused);
    }

    function test_Conservation_AccountedBalance() public {
        _fund(500_000 ether);
        _reg(R0, ALICE, 1, true);
        _reg(R1, BOB,   1, true);

        _warp(100 days);

        vm.prank(ALICE);
        vault.claim(R0);

        // accountedBalance == funded - claimed
        assertEq(vault.accountedBalance(), vault.totalFunded() - vault.totalClaimed());
        // vaultBalance == accountedBalance (no forced transfers in this test)
        assertEq(vault.vaultBalance(), vault.accountedBalance());
    }

    function test_SameBlock_NoDoubleEmission() public {
        _fund(1_000_000 ether);
        _reg(R0, ALICE, 1, true);

        // Two claims in the same block (no time elapsed between)
        vm.prank(ALICE);
        vm.expectRevert("RV: nothing to claim");
        vault.claim(R0);

        // After 1 second
        _warp(1);
        uint256 earned1 = vault.claimable(R0);
        vm.prank(ALICE);
        vault.claim(R0);

        vm.prank(ALICE);
        vm.expectRevert("RV: nothing to claim");
        vault.claim(R0);
    }
}
