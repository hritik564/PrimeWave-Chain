// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// ============================================================
// FeeDistributorUnit.t.sol — Unit Tests (PW-C03)
// ============================================================
//
// Tests:
//   1. Constructor validation
//   2. Split correctness (exact 70/20/10 for clean amounts)
//   3. Rounding: burn absorbs remainder, no dust lost
//   4. Zero-amount guard
//   5. Cumulative accounting accumulators
//   6. Access control: no withdraw/drain/setter functions
//   7. Reentrancy guard blocks reentrant distribute()
//   8. Events emitted correctly
//   9. previewDistribution() matches actual distribute()
//  10. pendingDistribution() and accountingSummary() views
// ============================================================

import "forge-std/Test.sol";
import "../src/FeeDistributor.sol";
import "../src/ValidatorFeeVault.sol";
import "../src/DevTreasury.sol";

/// @dev Attack contract that tries to reenter distribute() from receive().
contract ReentrancyAttacker {
    FeeDistributor public target;
    bool public attackAttempted;
    bool public attackSucceeded;
    uint256 public callDepth;

    constructor() {}

    function setTarget(address payable _target) external {
        target = FeeDistributor(_target);
    }

    receive() external payable {
        callDepth++;
        if (callDepth == 1) {
            attackAttempted = true;
            try target.distribute() {
                attackSucceeded = true; // Guard is broken if this runs
            } catch {
                // Expected: "FeeDistributor: reentrant call"
            }
        }
    }
}

contract FeeDistributorUnitTest is Test {
    FeeDistributor    public distributor;
    ValidatorFeeVault public vault;
    DevTreasury       public treasury;

    address constant BURN  = 0x000000000000000000000000000000000000dEaD;
    address constant ALICE = address(0xA11cE);

    // ── Setup ─────────────────────────────────────────────────────────────────

    function setUp() public {
        // Pre-compute addresses for this test contract as deployer.
        // Deployment order: vault (n), treasury (n+1), distributor (n+2).
        address deployer    = address(this);
        uint64  startNonce  = vm.getNonce(deployer);

        address expectedVault    = computeCreateAddress(deployer, startNonce);
        address expectedTreasury = computeCreateAddress(deployer, startNonce + 1);
        address expectedDist     = computeCreateAddress(deployer, startNonce + 2);

        vault       = new ValidatorFeeVault(expectedDist);
        treasury    = new DevTreasury(expectedDist);
        distributor = new FeeDistributor(payable(expectedVault), payable(expectedTreasury));

        // Sanity: verify addresses matched
        assertEq(address(vault),       expectedVault,    "vault addr");
        assertEq(address(treasury),    expectedTreasury, "treasury addr");
        assertEq(address(distributor), expectedDist,     "dist addr");
    }

    // ── Constructor ───────────────────────────────────────────────────────────

    function test_constructor_setsImmutables() public view {
        assertEq(distributor.validatorFeeVault(), address(vault));
        assertEq(distributor.treasury(),          address(treasury));
        assertEq(distributor.BURN_ADDRESS(),       BURN);
        assertEq(distributor.VALIDATOR_BPS(),      7000);
        assertEq(distributor.TREASURY_BPS(),       2000);
        assertEq(distributor.BASIS_POINTS(),       10000);
    }

    function test_constructor_rejectsZeroVault() public {
        vm.expectRevert("FeeDistributor: zero vault");
        new FeeDistributor(payable(address(0)), payable(address(treasury)));
    }

    function test_constructor_rejectsZeroTreasury() public {
        vm.expectRevert("FeeDistributor: zero treasury");
        new FeeDistributor(payable(address(vault)), payable(address(0)));
    }

    // ── receive() ─────────────────────────────────────────────────────────────

    function test_receive_acceptsNativePW() public {
        uint256 amount = 1 ether;
        vm.deal(ALICE, amount);

        vm.expectEmit(true, false, false, true, address(distributor));
        emit FeeDistributor.FeeReceived(amount, block.number, ALICE);

        vm.prank(ALICE);
        (bool ok, ) = address(distributor).call{value: amount}("");
        assertTrue(ok);
        assertEq(address(distributor).balance, amount);
    }

    // ── distribute(): zero guard ───────────────────────────────────────────────

    function test_distribute_revertsOnZeroBalance() public {
        assertEq(address(distributor).balance, 0);
        vm.expectRevert("FeeDistributor: nothing to distribute");
        distributor.distribute();
    }

    // ── distribute(): exact splits ─────────────────────────────────────────────

    function test_distribute_exactly1PW() public {
        uint256 fee = 1 ether;
        vm.deal(address(distributor), fee);
        uint256 burnBefore = BURN.balance;

        distributor.distribute();

        assertEq(address(vault).balance,    0.7 ether, "vault 70%");
        assertEq(address(treasury).balance, 0.2 ether, "treasury 20%");
        assertEq(BURN.balance - burnBefore, 0.1 ether, "burn 10%");
        assertEq(address(distributor).balance, 0,       "distributor emptied");
    }

    function test_distribute_exactly10PW() public {
        uint256 fee = 10 ether;
        vm.deal(address(distributor), fee);
        uint256 burnBefore = BURN.balance;

        distributor.distribute();

        assertEq(address(vault).balance,    7 ether);
        assertEq(address(treasury).balance, 2 ether);
        assertEq(BURN.balance - burnBefore, 1 ether);
        assertEq(address(distributor).balance, 0);
    }

    function test_distribute_100wei() public {
        vm.deal(address(distributor), 100);
        uint256 burnBefore = BURN.balance;
        distributor.distribute();
        assertEq(address(vault).balance,    70);
        assertEq(address(treasury).balance, 20);
        assertEq(BURN.balance - burnBefore, 10);
    }

    // ── distribute(): rounding dust goes to burn ───────────────────────────────

    function test_distribute_1wei() public {
        // 1 * 7000/10000 = 0; 1 * 2000/10000 = 0; burn = 1
        vm.deal(address(distributor), 1);
        uint256 burnBefore = BURN.balance;
        distributor.distribute();
        assertEq(address(vault).balance,    0, "vault 0");
        assertEq(address(treasury).balance, 0, "treasury 0");
        assertEq(BURN.balance - burnBefore, 1, "burn gets 1 wei");
    }

    function test_distribute_9wei() public {
        // 9*7000/10000=6; 9*2000/10000=1; burn=9-6-1=2
        vm.deal(address(distributor), 9);
        uint256 burnBefore = BURN.balance;
        distributor.distribute();
        assertEq(address(vault).balance,    6);
        assertEq(address(treasury).balance, 1);
        assertEq(BURN.balance - burnBefore, 2);
    }

    function test_distribute_101wei() public {
        // 101*7000/10000=70; 101*2000/10000=20; burn=101-70-20=11
        vm.deal(address(distributor), 101);
        uint256 burnBefore = BURN.balance;
        distributor.distribute();
        assertEq(address(vault).balance,    70);
        assertEq(address(treasury).balance, 20);
        assertEq(BURN.balance - burnBefore, 11);
    }

    // ── Rounding invariant — fuzz ─────────────────────────────────────────────

    function testFuzz_noWeiLost(uint256 seed) public {
        uint256 amount = bound(seed, 1, 1_000_000_000 ether);
        vm.deal(address(distributor), amount);
        uint256 burnBefore = BURN.balance;

        distributor.distribute();

        uint256 total = address(vault).balance + address(treasury).balance +
                        (BURN.balance - burnBefore);
        assertEq(total, amount, "No wei lost: v+t+b == amount");
        assertEq(address(distributor).balance, 0, "Distributor emptied");
    }

    // ── Accounting accumulators ────────────────────────────────────────────────

    function test_cumulativeAccounting() public {
        vm.deal(address(distributor), 1 ether);
        distributor.distribute();
        vm.deal(address(distributor), 3 ether);
        distributor.distribute();

        uint256 total = 4 ether;
        assertEq(distributor.totalDistributed(), total);
        // sum of parts must equal total
        assertEq(
            distributor.totalValidatorShare() +
            distributor.totalTreasuryShare()  +
            distributor.totalBurnShare(),
            total
        );
    }

    // ── previewDistribution() matches actual ──────────────────────────────────

    function testFuzz_previewMatchesActual(uint256 seed) public {
        uint256 amount = bound(seed, 1, 1_000_000_000 ether);
        (uint256 pv, uint256 pt, uint256 pb) = distributor.previewDistribution(amount);
        vm.deal(address(distributor), amount);
        uint256 burnBefore = BURN.balance;
        distributor.distribute();
        assertEq(address(vault).balance,    pv, "vault matches preview");
        assertEq(address(treasury).balance, pt, "treasury matches preview");
        assertEq(BURN.balance - burnBefore, pb, "burn matches preview");
    }

    // ── Events ────────────────────────────────────────────────────────────────

    function test_emitsFeeDistributed() public {
        uint256 fee = 1 ether;
        vm.deal(address(distributor), fee);
        vm.expectEmit(false, false, false, true, address(distributor));
        emit FeeDistributor.FeeDistributed(
            fee, 0.7 ether, 0.2 ether, 0.1 ether, block.number
        );
        distributor.distribute();
    }

    function test_vaultEmitsEvent() public {
        vm.deal(address(distributor), 1 ether);
        vm.expectEmit(true, false, false, true, address(vault));
        emit ValidatorFeeVault.ValidatorFeeReceived(
            0.7 ether, block.number, address(distributor)
        );
        distributor.distribute();
    }

    function test_treasuryEmitsEvent() public {
        vm.deal(address(distributor), 1 ether);
        vm.expectEmit(true, false, false, true, address(treasury));
        emit DevTreasury.TreasuryReceived(
            0.2 ether, block.number, address(distributor)
        );
        distributor.distribute();
    }

    // ── Access control: no unauthorized withdrawal ────────────────────────────

    function test_noWithdrawFunction() public {
        bytes memory w1 = abi.encodeWithSignature("withdraw(uint256,address)", 1 ether, ALICE);
        (bool ok, ) = address(distributor).call(w1);
        assertFalse(ok, "No withdraw(uint256,address)");

        bytes memory w2 = abi.encodeWithSignature("ownerWithdraw()");
        (ok, ) = address(distributor).call(w2);
        assertFalse(ok, "No ownerWithdraw()");

        bytes memory w3 = abi.encodeWithSignature("emergencyWithdrawAll(address)");
        (ok, ) = address(distributor).call(w3);
        assertFalse(ok, "No emergencyWithdrawAll(address)");
    }

    function test_noSetDestination() public {
        bytes memory s1 = abi.encodeWithSignature("setValidatorFeeVault(address)", ALICE);
        (bool ok, ) = address(distributor).call(s1);
        assertFalse(ok, "No setValidatorFeeVault");

        bytes memory s2 = abi.encodeWithSignature("setTreasury(address)", ALICE);
        (ok, ) = address(distributor).call(s2);
        assertFalse(ok, "No setTreasury");
    }

    function test_noSetSplit() public {
        bytes memory s = abi.encodeWithSignature("setSplit(uint256,uint256,uint256)", 50, 40, 10);
        (bool ok, ) = address(distributor).call(s);
        assertFalse(ok, "No setSplit");
    }

    function test_vaultHasNoWithdraw() public {
        vm.deal(address(vault), 1 ether);
        bytes memory wd = abi.encodeWithSignature("withdraw(uint256)", 1 ether);
        (bool ok, ) = address(vault).call(wd);
        assertFalse(ok, "ValidatorFeeVault has no withdraw");
    }

    function test_treasuryHasNoWithdraw() public {
        vm.deal(address(treasury), 1 ether);
        bytes memory wd = abi.encodeWithSignature("withdraw(uint256)", 1 ether);
        (bool ok, ) = address(treasury).call(wd);
        assertFalse(ok, "DevTreasury has no withdraw");
    }

    // ── Reentrancy guard ──────────────────────────────────────────────────────

    function test_reentrancyGuardBlocks() public {
        // ReentrancyAttacker acts as the vault — will try to call distribute()
        // from its receive() when it gets the validator 70% payment.
        ReentrancyAttacker attacker = new ReentrancyAttacker();

        FeeDistributor malDist = new FeeDistributor(
            payable(address(attacker)),
            payable(address(treasury))
        );

        attacker.setTarget(payable(address(malDist)));

        vm.deal(address(malDist), 1 ether);
        malDist.distribute(); // Attacker receive() fires, tries reentry

        assertTrue(attacker.attackAttempted(),   "Reentry was attempted");
        assertFalse(attacker.attackSucceeded(),   "Reentry was blocked by guard");
        assertEq(address(malDist).balance, 0,    "Distribution completed normally");
    }

    // ── View helpers ──────────────────────────────────────────────────────────

    function test_pendingDistribution() public {
        uint256 fee = 5 ether;
        vm.deal(address(distributor), fee);
        assertEq(distributor.pendingDistribution(), fee);
        distributor.distribute();
        assertEq(distributor.pendingDistribution(), 0);
    }

    function test_accountingSummary() public {
        vm.deal(address(distributor), 10 ether);
        distributor.distribute();
        (uint256 dist, uint256 toV, uint256 toT, uint256 toB) =
            distributor.accountingSummary();
        assertEq(dist, 10 ether);
        assertEq(toV,  7 ether);
        assertEq(toT,  2 ether);
        assertEq(toB,  1 ether);
    }
}
