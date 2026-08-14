// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// ============================================================
// ValidatorFeeVaultUnit.t.sol — PW-C04 Unit Tests
// ============================================================
//
// Covers:
//   Scenario A: 15 equal-weight, 100% eligibility
//   Scenario B: 14 eligible, 1 ineligible (uptimeBips=0)
//   Scenario C: fractional uptime factors
//   Scenario D: validator deactivated after earning fees
//   Scenario E: validator reactivated, no retro-accrual
//   Weighted distribution (V1=1, V2=2, V3=3)
//   Non-divisible amounts (rounding / dust)
//   Access control (all unauthorised paths fail)
//   Claim model (pull, only recipient, no double-claim)
//   Zero-weight / no-validator unallocated handling
//   Conservation invariant per scenario
// ============================================================

import "forge-std/Test.sol";
import "../src/ValidatorFeeVault.sol";

contract ValidatorFeeVaultUnit is Test {

    // ── Test doubles ──────────────────────────────────────────────────────────

    ValidatorFeeVault internal vault;

    address internal constant ADMIN    = address(0xA001);
    address internal constant ATTACKER = address(0xBAD1);

    // Dev validator addresses (rewardRecipients)
    address[15] internal recipients;

    // Dev validationIds (deterministic)
    bytes32[15] internal ids;

    // ── Setup ─────────────────────────────────────────────────────────────────

    function setUp() public {
        vault = new ValidatorFeeVault(ADMIN);

        for (uint256 i = 0; i < 15; i++) {
            recipients[i] = address(uint160(0x1001 + i));
            ids[i] = keccak256(abi.encodePacked("primewavedev-validator-", i + 1));
        }
    }

    // ── Helper ────────────────────────────────────────────────────────────────

    function _register15(uint16 uptimeBips) internal {
        vm.startPrank(ADMIN);
        for (uint256 i = 0; i < 15; i++) {
            vault.registerValidator(ids[i], recipients[i], 1, uptimeBips);
        }
        vm.stopPrank();
    }

    function _fund(uint256 amount) internal {
        vm.deal(address(this), amount);
        (bool ok, ) = address(vault).call{value: amount}("");
        require(ok, "fund failed");
    }

    function _sumClaimable() internal view returns (uint256 total) {
        for (uint256 i = 0; i < 15; i++) {
            total += vault.claimable(ids[i]);
        }
    }

    // ── Constructor & admin ───────────────────────────────────────────────────

    function test_ConstructorSetsAdmin() public view {
        assertEq(vault.protocolAdmin(), ADMIN);
    }

    function test_ConstructorConstants() public view {
        assertEq(vault.PRECISION(), 1e18);
        assertEq(vault.MAX_UPTIME_BIPS(), 10_000);
    }

    function test_ConstructorZeroAdminReverts() public {
        vm.expectRevert("VFV: zero admin");
        new ValidatorFeeVault(address(0));
    }

    // ── Registration ──────────────────────────────────────────────────────────

    function test_RegisterValidator_Basic() public {
        vm.prank(ADMIN);
        vault.registerValidator(ids[0], recipients[0], 1, 10_000);

        (
            address r, uint128 bw, uint16 ub, bool active,
            uint256 debt, uint256 pending, uint256 claimed
        ) = vault.validators(ids[0]);

        assertEq(r, recipients[0]);
        assertEq(bw, 1);
        assertEq(ub, 10_000);
        assertTrue(active);
        assertEq(debt, 0);
        assertEq(pending, 0);
        assertEq(claimed, 0);
        assertEq(vault.totalEffectiveWeight(), 1);
        assertEq(vault.validatorCount(), 1);
    }

    function test_RegisterValidator_NonAdminReverts() public {
        vm.prank(ATTACKER);
        vm.expectRevert("VFV: not admin");
        vault.registerValidator(ids[0], recipients[0], 1, 10_000);
    }

    function test_RegisterValidator_ZeroIdReverts() public {
        vm.prank(ADMIN);
        vm.expectRevert("VFV: zero validationId");
        vault.registerValidator(bytes32(0), recipients[0], 1, 10_000);
    }

    function test_RegisterValidator_ZeroRecipientReverts() public {
        vm.prank(ADMIN);
        vm.expectRevert("VFV: zero recipient");
        vault.registerValidator(ids[0], address(0), 1, 10_000);
    }

    function test_RegisterValidator_ZeroWeightReverts() public {
        vm.prank(ADMIN);
        vm.expectRevert("VFV: zero baseWeight");
        vault.registerValidator(ids[0], recipients[0], 0, 10_000);
    }

    function test_RegisterValidator_InvalidUptimeReverts() public {
        vm.prank(ADMIN);
        vm.expectRevert("VFV: uptimeBips > 10_000");
        vault.registerValidator(ids[0], recipients[0], 1, 10_001);
    }

    function test_RegisterValidator_DuplicateReverts() public {
        vm.startPrank(ADMIN);
        vault.registerValidator(ids[0], recipients[0], 1, 10_000);
        vm.expectRevert("VFV: already registered");
        vault.registerValidator(ids[0], recipients[0], 1, 10_000);
        vm.stopPrank();
    }

    function test_RegisterValidator_EffectiveWeightZeroUptime() public {
        vm.prank(ADMIN);
        vault.registerValidator(ids[0], recipients[0], 1, 0);
        // effectiveWeight = 1 * 0 / 10_000 = 0
        assertEq(vault.totalEffectiveWeight(), 0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SCENARIO A: 15 equal-weight, 100% eligibility, divisible amount
    // ─────────────────────────────────────────────────────────────────────────

    function test_ScenarioA_150PW_EqualSplit() public {
        _register15(10_000);
        // totalEffectiveWeight = 15

        uint256 amount = 150 ether; // 150 PW
        _fund(amount);

        // Each validator should earn 10 PW
        for (uint256 i = 0; i < 15; i++) {
            assertEq(vault.claimable(ids[i]), 10 ether, "each should earn 10 PW");
        }

        // Conservation: sum of claimable == amount (exact, no dust here)
        assertEq(_sumClaimable(), amount);

        // Vault balance equals total received
        assertEq(vault.vaultBalance(), amount);
        assertEq(vault.totalReceived(), amount);
        assertEq(vault.totalClaimed(), 0);
    }

    function test_ScenarioA_ClaimAll_BalanceZero() public {
        _register15(10_000);
        uint256 amount = 150 ether;
        _fund(amount);

        // Each recipient claims their 10 PW
        for (uint256 i = 0; i < 15; i++) {
            vm.deal(recipients[i], 0);
            vm.prank(recipients[i]);
            vault.claimFees(ids[i]);
            assertEq(recipients[i].balance, 10 ether);
        }

        assertEq(vault.totalClaimed(), 150 ether);
        // Remaining balance = rounding dust (0 here) + unallocated (0)
        assertLe(vault.vaultBalance(), 1); // at most 1 wei dust
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SCENARIO A: Non-divisible amount — rounding dust
    // ─────────────────────────────────────────────────────────────────────────

    function test_ScenarioA_151PW_RoundingDust() public {
        _register15(10_000);
        uint256 amount = 151 ether; // not divisible by 15
        _fund(amount);

        // Floor(151e18 * 1e18 / 15) * 15 / 1e18 = floor(151/15)*15 approximately
        // Each earns: floor(delta/1e18) where delta = 151e18*1e18/15
        // = floor(151e36/15) / 1e18 = approximately 10.0666...
        // In wei: 10066666666666666666 per validator (calculated)
        uint256 perValidator = vault.claimable(ids[0]);
        assertTrue(perValidator >= 10 ether, "at least 10 PW each");
        assertTrue(perValidator <= 10.1 ether, "at most 10.1 PW each");

        uint256 sumC = _sumClaimable();
        uint256 dust = amount - sumC;

        // Dust must be non-negative and tiny (< totalEffectiveWeight = 15 wei)
        assertLe(dust, 15, "dust <= totalEffectiveWeight in wei");
        assertTrue(amount >= sumC, "no over-allocation");

        // Conservation: balance = sumClaimable + dust
        assertEq(vault.vaultBalance(), sumC + dust);
    }

    function test_ScenarioA_1Wei_AllDust() public {
        _register15(10_000);
        _fund(1); // 1 wei — less than can be divided among 15

        // delta = 1 * 1e18 / 15 = 0 (floor)
        // accFeePerWeight += 0 → no one earns anything
        for (uint256 i = 0; i < 15; i++) {
            assertEq(vault.claimable(ids[i]), 0);
        }

        // The 1 wei is "dust" — stays in vault
        assertEq(vault.vaultBalance(), 1);
        assertEq(vault.roundingDust(), 1);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SCENARIO B: 14 eligible, 1 ineligible (uptimeBips=0)
    // ─────────────────────────────────────────────────────────────────────────

    function test_ScenarioB_OneIneligible() public {
        // Register 14 with full uptime, 1 with 0 uptime
        vm.startPrank(ADMIN);
        for (uint256 i = 0; i < 14; i++) {
            vault.registerValidator(ids[i], recipients[i], 1, 10_000);
        }
        vault.registerValidator(ids[14], recipients[14], 1, 0); // ineligible
        vm.stopPrank();

        assertEq(vault.totalEffectiveWeight(), 14); // only 14 earn

        uint256 amount = 140 ether;
        _fund(amount);

        // Each of 14 eligible validators earns 10 PW
        for (uint256 i = 0; i < 14; i++) {
            assertEq(vault.claimable(ids[i]), 10 ether, "eligible validator earns 10 PW");
        }
        // Ineligible earns 0
        assertEq(vault.claimable(ids[14]), 0, "ineligible earns 0");

        // Conservation: sumClaimable = 14 * 10 = 140 PW
        assertEq(_sumClaimable(), 140 ether);
    }

    function test_ScenarioB_IneligibleCannotClaim() public {
        vm.startPrank(ADMIN);
        vault.registerValidator(ids[0], recipients[0], 1, 0);
        vm.stopPrank();
        _fund(1 ether);

        vm.prank(recipients[0]);
        vm.expectRevert("VFV: nothing to claim");
        vault.claimFees(ids[0]);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SCENARIO C: Fractional uptime factors
    // ─────────────────────────────────────────────────────────────────────────

    function test_ScenarioC_FractionalUptime() public {
        // V1: weight=1, uptime=10_000 (100%) → ew=1
        // V2: weight=1, uptime=5_000  ( 50%) → ew=0 (1*5000/10000=0... wait)
        // Actually: 1 * 5000 / 10000 = 0 with integer division!
        // Need baseWeight >= 2 or use larger weights for fractional uptime.
        // Use baseWeight=10 to test fractional uptime meaningfully.

        vm.startPrank(ADMIN);
        vault.registerValidator(ids[0], recipients[0], 10, 10_000); // ew=10
        vault.registerValidator(ids[1], recipients[1], 10, 5_000);  // ew=5
        vault.registerValidator(ids[2], recipients[2], 10, 0);      // ew=0
        vm.stopPrank();

        // totalEffectiveWeight = 10 + 5 + 0 = 15
        assertEq(vault.totalEffectiveWeight(), 15);

        uint256 amount = 150 ether;
        _fund(amount);

        // delta = 150e18 * 1e18 / 15 = 10e18
        // V1 claimable = 10e18 * 10 / 1e18 = 100 PW
        // V2 claimable = 10e18 * 5  / 1e18 = 50 PW
        // V3 claimable = 0
        assertEq(vault.claimable(ids[0]), 100 ether, "100% uptime gets 100 PW");
        assertEq(vault.claimable(ids[1]), 50 ether,  "50% uptime gets 50 PW");
        assertEq(vault.claimable(ids[2]), 0,         "0% uptime gets 0");

        assertEq(_sumClaimable(), 150 ether); // exact, no dust
    }

    function test_ScenarioC_UptimeChange_CheckpointBeforeChange() public {
        vm.prank(ADMIN);
        vault.registerValidator(ids[0], recipients[0], 10, 10_000); // ew=10

        _fund(100 ether);
        // Validator earns 100 PW (only one active, gets everything)
        assertEq(vault.claimable(ids[0]), 100 ether);

        // Admin reduces uptime to 50%
        vm.prank(ADMIN);
        vault.setUptimeBips(ids[0], 5_000); // ew becomes 5

        // The 100 PW already earned is checkpointed into pendingReward
        assertEq(vault.claimable(ids[0]), 100 ether, "pending reward preserved");

        // Send more fees
        _fund(100 ether);
        // totalEffectiveWeight is now 5
        // delta = 100e18 * 1e18 / 5 = 20e18
        // new earned = 20e18 * 5 / 1e18 = 100 PW
        assertEq(vault.claimable(ids[0]), 200 ether, "total = old + new");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SCENARIO D: Validator deactivated after earning
    // ─────────────────────────────────────────────────────────────────────────

    function test_ScenarioD_DeactivatedAfterEarning() public {
        vm.startPrank(ADMIN);
        vault.registerValidator(ids[0], recipients[0], 1, 10_000);
        vault.registerValidator(ids[1], recipients[1], 1, 10_000);
        vm.stopPrank();

        _fund(20 ether); // each earns 10 PW

        // Deactivate V1 (checkpoints 10 PW into pendingReward)
        vm.prank(ADMIN);
        vault.deactivateValidator(ids[0]);

        // V1 is inactive but still has 10 PW claimable
        assertEq(vault.claimable(ids[0]), 10 ether, "inactive V1 keeps earned fees");
        (,,,bool active0,,, ) = vault.validators(ids[0]);
        assertFalse(active0);

        // More fees arrive — V1 does NOT earn (only V2 does)
        _fund(20 ether); // V2 earns 20 PW more (total weight = 1)
        assertEq(vault.claimable(ids[0]), 10 ether, "V1 does not earn while inactive");
        assertEq(vault.claimable(ids[1]), 30 ether, "V2 earns all new fees");

        // V1 can still claim their pre-deactivation fees
        vm.prank(recipients[0]);
        uint256 claimed = vault.claimFees(ids[0]);
        assertEq(claimed, 10 ether);
        assertEq(recipients[0].balance, 10 ether);
    }

    function test_ScenarioD_DeactivateInactiveReverts() public {
        vm.prank(ADMIN);
        vault.registerValidator(ids[0], recipients[0], 1, 10_000);
        vm.prank(ADMIN);
        vault.deactivateValidator(ids[0]);

        vm.prank(ADMIN);
        vm.expectRevert("VFV: already inactive");
        vault.deactivateValidator(ids[0]);
    }

    function test_ScenarioD_DeactivateUnregisteredReverts() public {
        vm.prank(ADMIN);
        vm.expectRevert("VFV: not registered");
        vault.deactivateValidator(ids[0]);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SCENARIO E: Validator reactivated — no retro-accrual
    // ─────────────────────────────────────────────────────────────────────────

    function test_ScenarioE_ReactivatedNoRetroAccrual() public {
        vm.startPrank(ADMIN);
        vault.registerValidator(ids[0], recipients[0], 1, 10_000);
        vault.registerValidator(ids[1], recipients[1], 1, 10_000);
        vm.stopPrank();

        _fund(20 ether); // each earns 10 PW

        vm.prank(ADMIN);
        vault.deactivateValidator(ids[0]); // checkpoints 10 PW

        _fund(20 ether); // V2 earns 20 PW (totalWeight = 1 → all goes to V2)

        // Reactivate V1 — should NOT earn the 20 PW from inactive period
        vm.prank(ADMIN);
        vault.activateValidator(ids[0]);

        // Check: V1 pendingReward = 10 PW (from before deactivation)
        // V1 rewardDebt = current accFeePerWeight (does not earn from inactive period)
        assertEq(vault.claimable(ids[0]), 10 ether, "V1 retains pre-deactivation fees");
        assertEq(vault.claimable(ids[1]), 30 ether, "V2 earned 10+20=30 PW");

        // New fees: now both V1 and V2 earn again
        _fund(20 ether); // totalWeight=2, each earns 10 PW
        assertEq(vault.claimable(ids[0]), 20 ether, "V1 earned 10 (pre) + 10 (post-reactivation)");
        assertEq(vault.claimable(ids[1]), 40 ether, "V2 earned 10+20+10=40 PW");
    }

    function test_ScenarioE_ActivateActiveReverts() public {
        vm.prank(ADMIN);
        vault.registerValidator(ids[0], recipients[0], 1, 10_000);

        vm.prank(ADMIN);
        vm.expectRevert("VFV: already active");
        vault.activateValidator(ids[0]);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // WEIGHTED DISTRIBUTION (V1=1, V2=2, V3=3, total=6)
    // ─────────────────────────────────────────────────────────────────────────

    function test_WeightedDistribution_ExactMath() public {
        vm.startPrank(ADMIN);
        vault.registerValidator(ids[0], recipients[0], 1, 10_000); // ew=1
        vault.registerValidator(ids[1], recipients[1], 2, 10_000); // ew=2
        vault.registerValidator(ids[2], recipients[2], 3, 10_000); // ew=3
        vm.stopPrank();

        assertEq(vault.totalEffectiveWeight(), 6);

        uint256 amount = 60 ether;
        _fund(amount); // divisible by 6

        // delta = 60e18 * 1e18 / 6 = 10e18
        // V1 (ew=1): 10e18 * 1 / 1e18 = 10 PW
        // V2 (ew=2): 10e18 * 2 / 1e18 = 20 PW
        // V3 (ew=3): 10e18 * 3 / 1e18 = 30 PW
        assertEq(vault.claimable(ids[0]), 10 ether);
        assertEq(vault.claimable(ids[1]), 20 ether);
        assertEq(vault.claimable(ids[2]), 30 ether);
        assertEq(vault.claimable(ids[0]) + vault.claimable(ids[1]) + vault.claimable(ids[2]), amount);
    }

    function test_WeightedDistribution_NonDivisible() public {
        vm.startPrank(ADMIN);
        vault.registerValidator(ids[0], recipients[0], 1, 10_000); // ew=1
        vault.registerValidator(ids[1], recipients[1], 2, 10_000); // ew=2
        vault.registerValidator(ids[2], recipients[2], 3, 10_000); // ew=3
        vm.stopPrank();

        uint256 amount = 61 ether; // not divisible by 6
        _fund(amount);

        uint256 total = vault.claimable(ids[0]) + vault.claimable(ids[1]) + vault.claimable(ids[2]);

        // Must not over-allocate
        assertLe(total, amount, "no over-allocation");

        // Dust must be tiny (< 6 wei)
        uint256 dust = amount - total;
        assertLe(dust, 6, "dust < totalEffectiveWeight");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // UPTIME-WEIGHTED TEST (spec §22)
    // ─────────────────────────────────────────────────────────────────────────

    function test_UptimeWeighted_ThreeValidators() public {
        // A: weight=1, uptime=10_000 (100%) → ew=1*10000/10000=1
        // B: weight=2, uptime=5_000  ( 50%) → ew=2*5000/10000=1
        // C: weight=1, uptime=0      (  0%) → ew=0
        vm.startPrank(ADMIN);
        vault.registerValidator(ids[0], recipients[0], 1, 10_000);
        vault.registerValidator(ids[1], recipients[1], 2, 5_000);
        vault.registerValidator(ids[2], recipients[2], 1, 0);
        vm.stopPrank();

        // totalEffectiveWeight = 1 + 1 + 0 = 2
        assertEq(vault.totalEffectiveWeight(), 2);

        uint256 amount = 20 ether;
        _fund(amount);

        // delta = 20e18 * 1e18 / 2 = 10e18
        // A (ew=1): 10e18 * 1 / 1e18 = 10 PW
        // B (ew=1): 10e18 * 1 / 1e18 = 10 PW
        // C (ew=0): 0
        assertEq(vault.claimable(ids[0]), 10 ether, "A: 100% uptime");
        assertEq(vault.claimable(ids[1]), 10 ether, "B: 50% uptime but weight=2");
        assertEq(vault.claimable(ids[2]), 0,         "C: 0% uptime earns 0");

        assertEq(vault.claimable(ids[0]) + vault.claimable(ids[1]) + vault.claimable(ids[2]), amount);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ZERO-WEIGHT / NO-VALIDATOR CASE
    // ─────────────────────────────────────────────────────────────────────────

    function test_ZeroWeight_FeesGoToUnallocated() public {
        // No validators registered → totalEffectiveWeight = 0
        _fund(100 ether);
        assertEq(vault.unallocated(), 100 ether);
        assertEq(vault.totalReceived(), 100 ether);
        assertEq(vault.accFeePerWeight(), 0);
    }

    function test_ZeroWeight_DistributeUnallocated() public {
        _fund(100 ether); // goes to unallocated

        vm.prank(ADMIN);
        vault.registerValidator(ids[0], recipients[0], 1, 10_000);

        // unallocated still 100 PW (registration doesn't auto-distribute)
        assertEq(vault.unallocated(), 100 ether);
        assertEq(vault.claimable(ids[0]), 0);

        // Admin distributes the unallocated
        vault.distributeUnallocated();

        assertEq(vault.unallocated(), 0);
        // Now the validator can claim the 100 PW
        assertEq(vault.claimable(ids[0]), 100 ether);
    }

    function test_ZeroWeight_DistributeUnallocated_NoWeight_Reverts() public {
        _fund(100 ether);
        vm.expectRevert("VFV: no active weight");
        vault.distributeUnallocated();
    }

    function test_ZeroWeight_DistributeUnallocated_NothingReverts() public {
        vm.prank(ADMIN);
        vault.registerValidator(ids[0], recipients[0], 1, 10_000);

        vm.expectRevert("VFV: nothing unallocated");
        vault.distributeUnallocated();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // CLAIM MODEL
    // ─────────────────────────────────────────────────────────────────────────

    function test_Claim_OnlyRecipientCanClaim() public {
        vm.prank(ADMIN);
        vault.registerValidator(ids[0], recipients[0], 1, 10_000);
        _fund(10 ether);

        // Attacker cannot claim
        vm.prank(ATTACKER);
        vm.expectRevert("VFV: caller is not recipient");
        vault.claimFees(ids[0]);

        // Another validator's recipient cannot claim
        vm.prank(recipients[1]);
        vm.expectRevert("VFV: caller is not recipient");
        vault.claimFees(ids[0]);
    }

    function test_Claim_NothingToClaimReverts() public {
        vm.prank(ADMIN);
        vault.registerValidator(ids[0], recipients[0], 1, 10_000);

        vm.prank(recipients[0]);
        vm.expectRevert("VFV: nothing to claim");
        vault.claimFees(ids[0]);
    }

    function test_Claim_DoubleClaim_Reverts() public {
        vm.prank(ADMIN);
        vault.registerValidator(ids[0], recipients[0], 1, 10_000);
        _fund(10 ether);

        vm.startPrank(recipients[0]);
        vault.claimFees(ids[0]);
        vm.expectRevert("VFV: nothing to claim");
        vault.claimFees(ids[0]);
        vm.stopPrank();
    }

    function test_Claim_UnregisteredReverts() public {
        vm.prank(recipients[0]);
        vm.expectRevert("VFV: not registered");
        vault.claimFees(ids[0]);
    }

    function test_Claim_TransfersFunds() public {
        vm.prank(ADMIN);
        vault.registerValidator(ids[0], recipients[0], 1, 10_000);
        _fund(50 ether);

        uint256 balBefore = recipients[0].balance;
        vm.prank(recipients[0]);
        uint256 claimed = vault.claimFees(ids[0]);

        assertEq(claimed, 50 ether);
        assertEq(recipients[0].balance - balBefore, 50 ether);
        assertEq(vault.totalClaimed(), 50 ether);
        assertEq(vault.vaultBalance(), 0);
    }

    function test_Claim_MultipleFundRounds() public {
        vm.startPrank(ADMIN);
        vault.registerValidator(ids[0], recipients[0], 1, 10_000);
        vault.registerValidator(ids[1], recipients[1], 1, 10_000);
        vm.stopPrank();

        _fund(20 ether); // each earns 10
        _fund(20 ether); // each earns 10 more → 20 total

        assertEq(vault.claimable(ids[0]), 20 ether);
        assertEq(vault.claimable(ids[1]), 20 ether);

        vm.prank(recipients[0]);
        vault.claimFees(ids[0]);
        assertEq(vault.vaultBalance(), 20 ether); // V1 claimed, V2 still pending
    }

    function test_Claim_InactiveCanStillClaim() public {
        vm.startPrank(ADMIN);
        vault.registerValidator(ids[0], recipients[0], 1, 10_000);
        vm.stopPrank();
        _fund(30 ether);

        vm.prank(ADMIN);
        vault.deactivateValidator(ids[0]);

        vm.prank(recipients[0]);
        uint256 claimed = vault.claimFees(ids[0]);
        assertEq(claimed, 30 ether);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ACCESS CONTROL — ALL UNAUTHORIZED PATHS
    // ─────────────────────────────────────────────────────────────────────────

    function test_AccessControl_RegisterNonAdmin() public {
        vm.prank(ATTACKER);
        vm.expectRevert("VFV: not admin");
        vault.registerValidator(ids[0], recipients[0], 1, 10_000);
    }

    function test_AccessControl_DeactivateNonAdmin() public {
        vm.prank(ADMIN);
        vault.registerValidator(ids[0], recipients[0], 1, 10_000);

        vm.prank(ATTACKER);
        vm.expectRevert("VFV: not admin");
        vault.deactivateValidator(ids[0]);
    }

    function test_AccessControl_ActivateNonAdmin() public {
        vm.startPrank(ADMIN);
        vault.registerValidator(ids[0], recipients[0], 1, 10_000);
        vault.deactivateValidator(ids[0]);
        vm.stopPrank();

        vm.prank(ATTACKER);
        vm.expectRevert("VFV: not admin");
        vault.activateValidator(ids[0]);
    }

    function test_AccessControl_SetUptimeNonAdmin() public {
        vm.prank(ADMIN);
        vault.registerValidator(ids[0], recipients[0], 1, 10_000);

        vm.prank(ATTACKER);
        vm.expectRevert("VFV: not admin");
        vault.setUptimeBips(ids[0], 5_000);
    }

    function test_AccessControl_SetWeightNonAdmin() public {
        vm.prank(ADMIN);
        vault.registerValidator(ids[0], recipients[0], 1, 10_000);

        vm.prank(ATTACKER);
        vm.expectRevert("VFV: not admin");
        vault.setBaseWeight(ids[0], 2);
    }

    function test_AccessControl_ClaimWrongRecipient() public {
        vm.prank(ADMIN);
        vault.registerValidator(ids[0], recipients[0], 1, 10_000);
        _fund(10 ether);

        vm.prank(ATTACKER);
        vm.expectRevert("VFV: caller is not recipient");
        vault.claimFees(ids[0]);
    }

    function test_AccessControl_ValidatorCannotModifyOwnWeight() public {
        vm.prank(ADMIN);
        vault.registerValidator(ids[0], recipients[0], 1, 10_000);

        vm.prank(recipients[0]);
        vm.expectRevert("VFV: not admin");
        vault.setBaseWeight(ids[0], 1000);
    }

    function test_AccessControl_ValidatorCannotModifyOwnUptime() public {
        vm.prank(ADMIN);
        vault.registerValidator(ids[0], recipients[0], 1, 10_000);

        vm.prank(recipients[0]);
        vm.expectRevert("VFV: not admin");
        vault.setUptimeBips(ids[0], 10_000);
    }

    function test_AccessControl_ValidatorCannotRegisterOthers() public {
        vm.prank(recipients[0]);
        vm.expectRevert("VFV: not admin");
        vault.registerValidator(ids[0], recipients[0], 1, 10_000);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SET UPTIME / SET WEIGHT — detailed
    // ─────────────────────────────────────────────────────────────────────────

    function test_SetUptimeBips_InvalidReverts() public {
        vm.prank(ADMIN);
        vault.registerValidator(ids[0], recipients[0], 1, 10_000);

        vm.prank(ADMIN);
        vm.expectRevert("VFV: uptimeBips > 10_000");
        vault.setUptimeBips(ids[0], 10_001);
    }

    function test_SetUptimeBips_UnregisteredReverts() public {
        vm.prank(ADMIN);
        vm.expectRevert("VFV: not registered");
        vault.setUptimeBips(ids[0], 5_000);
    }

    function test_SetBaseWeight_ZeroReverts() public {
        vm.prank(ADMIN);
        vault.registerValidator(ids[0], recipients[0], 1, 10_000);

        vm.prank(ADMIN);
        vm.expectRevert("VFV: zero baseWeight");
        vault.setBaseWeight(ids[0], 0);
    }

    function test_SetBaseWeight_UpdatesWeight() public {
        vm.startPrank(ADMIN);
        vault.registerValidator(ids[0], recipients[0], 1, 10_000);
        vault.registerValidator(ids[1], recipients[1], 1, 10_000);
        vm.stopPrank();

        _fund(20 ether); // each earns 10

        vm.prank(ADMIN);
        vault.setBaseWeight(ids[0], 2); // ew goes from 1 to 2

        // totalEffectiveWeight = 2 + 1 = 3
        assertEq(vault.totalEffectiveWeight(), 3);

        // Pending from before weight change is checkpointed
        assertEq(vault.claimable(ids[0]), 10 ether);

        _fund(30 ether); // totalWeight=3, delta=10e18
        // V0 (ew=2): +20 PW; V1 (ew=1): +10 PW
        assertEq(vault.claimable(ids[0]), 30 ether);
        assertEq(vault.claimable(ids[1]), 20 ether);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 15-VALIDATOR FULL FLOW (spec §20)
    // ─────────────────────────────────────────────────────────────────────────

    function test_15Validator_FullFlow() public {
        _register15(10_000);
        assertEq(vault.totalEffectiveWeight(), 15);

        // Round 1: 150 PW (exact)
        _fund(150 ether);
        assertEq(vault.claimable(ids[0]), 10 ether);

        // Round 2: 150 PW more → each has 20 PW
        _fund(150 ether);
        assertEq(vault.claimable(ids[7]), 20 ether);

        // All 15 claim
        for (uint256 i = 0; i < 15; i++) {
            vm.prank(recipients[i]);
            vault.claimFees(ids[i]);
        }

        assertEq(vault.totalClaimed(), 300 ether);
        assertLe(vault.vaultBalance(), 1); // at most 1 wei dust
    }

    // ─────────────────────────────────────────────────────────────────────────
    // CONSERVATION INVARIANT across all scenarios
    // ─────────────────────────────────────────────────────────────────────────

    function test_Conservation_AfterDepositsAndClaims() public {
        _register15(10_000);

        _fund(151 ether);
        _fund(75 ether);
        _fund(13.5 ether);

        // Partial claims
        vm.prank(recipients[0]);
        vault.claimFees(ids[0]);
        vm.prank(recipients[1]);
        vault.claimFees(ids[1]);

        // Conservation: balance = totalReceived - totalClaimed
        assertEq(vault.vaultBalance(), vault.totalReceived() - vault.totalClaimed());

        // balance >= sum(claimable) + unallocated
        uint256 sumC = _sumClaimable();
        assertGe(vault.vaultBalance(), sumC + vault.unallocated());
    }

    // ─────────────────────────────────────────────────────────────────────────
    // VIEW FUNCTIONS
    // ─────────────────────────────────────────────────────────────────────────

    function test_ViewFunctions_EmptyVault() public view {
        assertEq(vault.vaultBalance(), 0);
        assertEq(vault.totalReceived(), 0);
        assertEq(vault.totalClaimed(), 0);
        assertEq(vault.totalEffectiveWeight(), 0);
        assertEq(vault.accFeePerWeight(), 0);
        assertEq(vault.unallocated(), 0);
        assertEq(vault.validatorCount(), 0);
        assertEq(vault.totalClaimableView(), 0);
        assertEq(vault.netReceived(), 0);
    }

    function test_ViewFunctions_ValidatorZeroUptime() public {
        vm.prank(ADMIN);
        vault.registerValidator(ids[0], recipients[0], 1, 0);
        assertEq(vault.claimable(ids[0]), 0);
    }

    function test_ViewFunctions_ClaimableZeroForUnregistered() public view {
        assertEq(vault.claimable(bytes32(uint256(999))), 0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // EVENTS
    // ─────────────────────────────────────────────────────────────────────────

    function test_Event_ValidatorRegistered() public {
        vm.prank(ADMIN);
        vm.expectEmit(true, true, false, true);
        emit ValidatorFeeVault.ValidatorRegistered(ids[0], recipients[0], 1, 10_000);
        vault.registerValidator(ids[0], recipients[0], 1, 10_000);
    }

    function test_Event_ValidatorDeactivated() public {
        vm.prank(ADMIN);
        vault.registerValidator(ids[0], recipients[0], 1, 10_000);
        _fund(10 ether);

        vm.prank(ADMIN);
        vm.expectEmit(true, false, false, true);
        emit ValidatorFeeVault.ValidatorDeactivated(ids[0], 10 ether);
        vault.deactivateValidator(ids[0]);
    }

    function test_Event_ValidatorFeeClaimed() public {
        vm.prank(ADMIN);
        vault.registerValidator(ids[0], recipients[0], 1, 10_000);
        _fund(10 ether);

        vm.prank(recipients[0]);
        vm.expectEmit(true, true, false, true);
        emit ValidatorFeeVault.ValidatorFeeClaimed(ids[0], recipients[0], 10 ether);
        vault.claimFees(ids[0]);
    }

    function test_Event_FeeReceived() public {
        vm.prank(ADMIN);
        vault.registerValidator(ids[0], recipients[0], 1, 10_000);

        vm.deal(address(this), 10 ether);
        vm.expectEmit(false, false, false, false); // just check it emits
        emit ValidatorFeeVault.FeeReceived(10 ether, 0, 0);
        (bool ok, ) = address(vault).call{value: 10 ether}("");
        assertTrue(ok);
    }
}
