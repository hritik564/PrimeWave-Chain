// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import "forge-std/Test.sol";
import {GenesisConstructorState} from "../script/GenesisConstructorState.s.sol";
import {RewardVault} from "../src/RewardVault.sol";
import {FeeDistributor} from "../src/FeeDistributor.sol";
import {PrimeWaveValidatorRegistry} from "../src/PrimeWaveValidatorRegistry.sol";

contract GenesisConstructorStateTest is Test {
    function testConstructorFundedGenesisStateAndCustody() public {
        GenesisConstructorState builder = new GenesisConstructorState();
        GenesisConstructorState.PublicConfig memory m;
        m.timelock=address(0xB001);m.emergency=address(0xB002);m.feeVault=address(0xB003);
        m.feeDistributor=address(0xB004);m.registry=address(0xB005);m.rewardVault=address(0xB006);
        m.manager=address(0xB007);m.treasury=address(0xB008);m.governance=address(0xB009);
        m.signers=[address(0xC001),address(0xC002),address(0xC003),address(0xC004),address(0xC005)];
        builder.build(m);
        RewardVault vault=RewardVault(payable(m.rewardVault));
        assertEq(vault.admin(),m.timelock);
        assertEq(vault.totalFunded(),15_000_000 ether);
        assertEq(vault.totalEmitted(),0);
        assertEq(vault.totalClaimed(),0);
        assertEq(vault.pauseController(),m.emergency);
        assertEq(m.rewardVault.balance,15_000_000 ether);
        assertEq(FeeDistributor(payable(m.feeDistributor)).treasury(),m.treasury);
        assertEq(PrimeWaveValidatorRegistry(m.registry).protocolAdmin(),m.timelock);
        vm.expectRevert("RV: not admin");vault.setEmissionRate(1);
        string memory exported=builder.accountJson(m.rewardVault);
        assertEq(vm.parseJsonUint(exported,".balance"),15_000_000 ether);
        assertGt(vm.parseJsonKeys(exported,".storage").length,0);
        address restored=address(0xD001);
        vm.etch(restored,vm.parseJsonBytes(exported,".code"));
        string[] memory slots=vm.parseJsonKeys(exported,".storage");
        for(uint256 i;i<slots.length;++i){
            vm.store(restored,vm.parseBytes32(slots[i]),vm.parseJsonBytes32(exported,string.concat(".storage.",slots[i])));
        }
        vm.deal(restored,15_000_000 ether);
        assertEq(RewardVault(payable(restored)).admin(),m.timelock);
        assertEq(RewardVault(payable(restored)).totalFunded(),15_000_000 ether);
        assertEq(RewardVault(payable(restored)).pauseController(),m.emergency);
        assertEq(RewardVault(payable(restored)).emissionRatePerSecond(),vault.emissionRatePerSecond());
    }
}
