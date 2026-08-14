// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// ============================================================
// FeeDistributorInvariant.t.sol — Invariant / Fuzz Tests (PW-C03)
// ============================================================
//
// Validates all 9 PW-C03 accounting invariants via fuzz testing:
//
//   INV-1: validatorShare + treasuryShare + burnShare == feeAmount (no dust)
//   INV-2: validatorShare == floor(feeAmount × 7000 / 10000)
//   INV-3: treasuryShare  == floor(feeAmount × 2000 / 10000)
//   INV-4: burnShare      == feeAmount − validatorShare − treasuryShare
//   INV-5: FeeDistributor empties to zero after every distribute()
//   INV-6: totalDistributed == totalValidatorShare + totalTreasuryShare + totalBurnShare
//   INV-7: No PW is silently retained (vault+treasury+burn == total deposited)
//   INV-8: No PW created (pending + distributed == total deposited)
//   INV-9: Burn is >= floor(10%) and <= floor(10%) + 2 wei per call
// ============================================================

import "forge-std/Test.sol";
import "../src/FeeDistributor.sol";
import "../src/ValidatorFeeVault.sol";
import "../src/DevTreasury.sol";

contract FeeDistributorInvariantTest is Test {
    FeeDistributor    public distributor;
    ValidatorFeeVault public vault;
    DevTreasury       public treasury;
    address constant BURN = 0x000000000000000000000000000000000000dEaD;

    function setUp() public {
        address deployer   = address(this);
        uint64  startNonce = vm.getNonce(deployer);

        address expectedVault    = computeCreateAddress(deployer, startNonce);
        address expectedTreasury = computeCreateAddress(deployer, startNonce + 1);
        address expectedDist     = computeCreateAddress(deployer, startNonce + 2);

        vault       = new ValidatorFeeVault(expectedDist);
        treasury    = new DevTreasury(expectedDist);
        distributor = new FeeDistributor(payable(expectedVault), payable(expectedTreasury));
    }

    // ── INV-1: No wei lost — sum of parts equals whole ────────────────────────

    function testFuzz_INV1_noWeiLost(uint256 amount) public {
        amount = bound(amount, 1, 1_000_000_000 ether);
        vm.deal(address(distributor), amount);
        uint256 burnBefore = BURN.balance;

        distributor.distribute();

        uint256 vGot = address(vault).balance;
        uint256 tGot = address(treasury).balance;
        uint256 bGot = BURN.balance - burnBefore;

        assertEq(vGot + tGot + bGot, amount, "INV-1: v+t+b == amount");
        assertEq(address(distributor).balance, 0, "INV-5: distributor emptied");
    }

    // ── INV-2: Validator share is exactly floor(amount × 70%) ────────────────

    function testFuzz_INV2_validatorShareFloor(uint256 amount) public {
        amount = bound(amount, 1, 1_000_000_000 ether);
        vm.deal(address(distributor), amount);
        distributor.distribute();

        uint256 expected = amount * 7000 / 10000;
        assertEq(address(vault).balance, expected, "INV-2: validator = floor(70%)");
    }

    // ── INV-3: Treasury share is exactly floor(amount × 20%) ─────────────────

    function testFuzz_INV3_treasuryShareFloor(uint256 amount) public {
        amount = bound(amount, 1, 1_000_000_000 ether);
        vm.deal(address(distributor), amount);
        distributor.distribute();

        uint256 expected = amount * 2000 / 10000;
        assertEq(address(treasury).balance, expected, "INV-3: treasury = floor(20%)");
    }

    // ── INV-4: Burn is exact remainder ───────────────────────────────────────

    function testFuzz_INV4_burnIsRemainder(uint256 amount) public {
        amount = bound(amount, 1, 1_000_000_000 ether);
        uint256 burnBefore = BURN.balance;
        vm.deal(address(distributor), amount);
        distributor.distribute();

        uint256 validatorShare = amount * 7000 / 10000;
        uint256 treasuryShare  = amount * 2000 / 10000;
        uint256 expectedBurn   = amount - validatorShare - treasuryShare;

        assertEq(BURN.balance - burnBefore, expectedBurn, "INV-4: burn = remainder");
    }

    // ── INV-5: FeeDistributor emptied after every distribute() ────────────────

    function testFuzz_INV5_distributorEmptied(uint256 amount) public {
        amount = bound(amount, 1, 1_000_000_000 ether);
        vm.deal(address(distributor), amount);
        distributor.distribute();
        assertEq(address(distributor).balance, 0, "INV-5: distributor empty");
    }

    // ── INV-6: Accounting sum identity ───────────────────────────────────────

    function testFuzz_INV6_accountingIdentity(uint256 seed) public {
        // Multiple rounds; accounting must always sum correctly
        uint256 total = 0;
        for (uint256 i = 0; i < 5; i++) {
            uint256 amount = bound(
                uint256(keccak256(abi.encode(seed, i))),
                1, 200_000_000 ether
            );
            vm.deal(address(distributor), amount);
            distributor.distribute();
            total += amount;
        }

        assertEq(distributor.totalDistributed(), total, "INV-6a: total distributed");
        assertEq(
            distributor.totalValidatorShare() +
            distributor.totalTreasuryShare()  +
            distributor.totalBurnShare(),
            total,
            "INV-6b: v+t+b == total"
        );
    }

    // ── INV-7: System conservation (no silent retention) ─────────────────────

    function testFuzz_INV7_systemConservation(uint256 seed) public {
        uint256 totalInput = 0;
        uint256 burnBefore = BURN.balance;

        for (uint256 i = 0; i < 8; i++) {
            uint256 amount = bound(
                uint256(keccak256(abi.encode(seed, i))),
                1, 100_000_000 ether
            );
            vm.deal(address(distributor), address(distributor).balance + amount);
            totalInput += amount;
            distributor.distribute();
        }

        uint256 vGot = address(vault).balance;
        uint256 tGot = address(treasury).balance;
        uint256 bGot = BURN.balance - burnBefore;

        assertEq(vGot + tGot + bGot, totalInput, "INV-7: vault+treasury+burn == total input");
        assertEq(address(distributor).balance, 0, "INV-7: distributor empty at end");
    }

    // ── INV-8: No PW created (conservation of supply) ────────────────────────

    function testFuzz_INV8_noMinting(uint256 seed) public {
        uint256 totalDeposited = 0;

        for (uint256 i = 0; i < 3; i++) {
            uint256 amount = bound(
                uint256(keccak256(abi.encode(seed, i))),
                1, 300_000_000 ether
            );
            vm.deal(address(distributor), address(distributor).balance + amount);
            totalDeposited += amount;
            distributor.distribute();
        }

        uint256 pending     = address(distributor).balance; // should be 0
        uint256 distributed = distributor.totalDistributed();

        assertEq(
            pending + distributed,
            totalDeposited,
            "INV-8: pending + distributed == deposited (no PW created)"
        );
    }

    // ── INV-9: Burn is >= floor(10%) and <= floor(10%) + 2 per call ──────────

    function testFuzz_INV9_burnBounds(uint256 amount) public {
        amount = bound(amount, 1, 1_000_000_000 ether);
        uint256 burnBefore = BURN.balance;
        vm.deal(address(distributor), amount);
        distributor.distribute();

        uint256 burnGot  = BURN.balance - burnBefore;
        uint256 floor10  = amount * 1000 / 10000;

        assertGe(burnGot, floor10,      "INV-9a: burn >= floor(10%)");
        assertLe(burnGot, floor10 + 2,  "INV-9b: burn <= floor(10%) + 2 wei");
    }

    // ── Edge cases ────────────────────────────────────────────────────────────

    function test_edge_1wei() public {
        // 1 wei: 7000/10000=0, 2000/10000=0, burn=1
        vm.deal(address(distributor), 1);
        uint256 burnBefore = BURN.balance;
        distributor.distribute();
        assertEq(address(vault).balance,    0, "vault 0");
        assertEq(address(treasury).balance, 0, "treasury 0");
        assertEq(BURN.balance - burnBefore, 1, "burn 1");
    }

    function test_edge_9wei() public {
        // 9: 6, 1, 2
        vm.deal(address(distributor), 9);
        uint256 burnBefore = BURN.balance;
        distributor.distribute();
        assertEq(address(vault).balance,    6);
        assertEq(address(treasury).balance, 1);
        assertEq(BURN.balance - burnBefore, 2);
    }

    function test_edge_maxUint128() public {
        // type(uint128).max — verifies no overflow in math
        uint256 huge = type(uint128).max;
        vm.deal(address(distributor), huge);
        uint256 burnBefore = BURN.balance;
        distributor.distribute();
        assertEq(
            address(vault).balance + address(treasury).balance + (BURN.balance - burnBefore),
            huge, "Large: no overflow"
        );
    }

    function test_distribute_revertsOnEmpty() public {
        vm.expectRevert("FeeDistributor: nothing to distribute");
        distributor.distribute();
    }

    function test_multiRound_exactAccounting() public {
        uint256[5] memory amounts = [
            uint256(1 ether), 3 ether, 100 wei, 7 ether, 1_000_000 ether
        ];
        uint256 total = 0;
        uint256 burnBefore = BURN.balance;

        for (uint256 i = 0; i < amounts.length; i++) {
            vm.deal(address(distributor), amounts[i]);
            distributor.distribute();
            total += amounts[i];
        }

        assertEq(distributor.totalDistributed(), total, "cumulative distributed");
        assertEq(
            address(vault).balance + address(treasury).balance +
            (BURN.balance - burnBefore),
            total, "cumulative conservation"
        );
    }
}
