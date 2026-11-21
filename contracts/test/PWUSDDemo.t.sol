// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import {PWUSDDemo} from "../src/PWUSDDemo.sol";

contract PWUSDDemoTest is Test {
    PWUSDDemo token;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        vm.chainId(73571);
        token = new PWUSDDemo(alice);
    }

    function testMetadataAndFixedSupply() public view {
        assertEq(token.name(), "PWUSD Demo (Unbacked)");
        assertEq(token.symbol(), "PWUSD");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 1_000_000 ether);
        assertEq(token.balanceOf(alice), token.totalSupply());
    }

    function testTransfer() public {
        vm.prank(alice);
        assertTrue(token.transfer(bob, 25 ether));
        assertEq(token.balanceOf(bob), 25 ether);
        assertEq(token.balanceOf(alice), 999_975 ether);
        assertEq(token.totalSupply(), 1_000_000 ether);
    }

    function testApproveAndTransferFrom() public {
        vm.prank(alice);
        token.approve(address(this), 1 ether);
        assertTrue(token.transferFrom(alice, bob, 1 ether));
        assertEq(token.allowance(alice, address(this)), 0);
    }

    function testWrongChainRejected() public {
        vm.chainId(77);
        vm.expectRevert("PWUSD: local PrimeWave only");
        new PWUSDDemo(alice);
    }

    function testZeroRecipientRejected() public {
        vm.expectRevert();
        new PWUSDDemo(address(0));
    }

    function testInsufficientBalanceRejected() public {
        vm.prank(bob);
        vm.expectRevert();
        token.transfer(alice, 1);
    }

    function testNoExternalMint() public {
        (bool success,) = address(token).call(abi.encodeWithSignature("mint(address,uint256)", bob, 1));
        assertFalse(success);
    }

    function testFuzzTransfer(uint256 amount) public {
        amount = bound(amount, 0, token.totalSupply());
        vm.prank(alice);
        token.transfer(bob, amount);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(alice) + token.balanceOf(bob), token.totalSupply());
    }
}
