// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {CustodySecurityTest} from "../../contracts/test/CustodySecurity.t.sol";
import {ValidatorManager,ValidatorManagerSettings} from "../../genesis-build/pinned-manager/icm/avalanche/validator-manager/ValidatorManager.sol";
import {PoAManager} from "../../genesis-build/pinned-manager/icm/avalanche/validator-manager/PoAManager.sol";
import {IValidatorManagerExternalOwnable} from "../../genesis-build/pinned-manager/icm/avalanche/validator-manager/interfaces/IValidatorManagerExternalOwnable.sol";
import {ValidatorMessages} from "../../genesis-build/pinned-manager/icm/avalanche/validator-manager/ValidatorMessages.sol";
import {ConversionData,InitialValidator} from "../../genesis-build/pinned-manager/icm/avalanche/validator-manager/interfaces/IACP99Manager.sol";
import {ICMInitializable} from "../../genesis-build/pinned-manager/icm/avalanche/utilities/ICMInitializable.sol";
import {IWarpMessenger,WarpMessage} from "../../genesis-build/pinned-manager/icm/avalanche/subnet-evm/IWarpMessenger.sol";
import {TransparentUpgradeableProxy,ITransparentUpgradeableProxy} from "../../genesis-build/pinned-manager/oz/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "../../genesis-build/pinned-manager/oz/proxy/transparent/ProxyAdmin.sol";

/// @notice Actual pinned manager/library/OZ5.0.2 code; Warp verification is MOCKED
/// in this in-process unit EVM. No P-Chain, keys or node execution.
contract PinnedManagerCustodyTest is CustodySecurityTest {
    ValidatorManager internal manager;
    ValidatorManager internal implementation;
    PoAManager internal poa;
    ProxyAdmin internal proxyAdmin;
    address constant WARP=0x0200000000000000000000000000000000000005;
    bytes32 constant SUBNET=bytes32(uint256(123));
    bytes32 constant CHAIN=bytes32(uint256(456));
    function setUp() public override {
        super.setUp();
        implementation=new ValidatorManager(ICMInitializable.Disallowed);
        manager=ValidatorManager(address(new TransparentUpgradeableProxy(address(implementation),m.timelock,
            abi.encodeCall(ValidatorManager.initialize,(ValidatorManagerSettings(address(this),SUBNET,3600,20))))));
        poa=new PoAManager(m.timelock,IValidatorManagerExternalOwnable(address(manager)));
        manager.transferOwnership(address(poa)); // synthetic final-state setup, not production transaction
        proxyAdmin=ProxyAdmin(address(uint160(uint256(vm.load(address(manager),0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103)))));
        vm.mockCall(WARP,abi.encodeCall(IWarpMessenger.getBlockchainID,()),abi.encode(CHAIN));
        vm.mockCall(WARP,abi.encodeWithSelector(IWarpMessenger.sendWarpMessage.selector),abi.encode(bytes32(uint256(789))));
    }
    function conversion(uint64 weight) internal view returns(ConversionData memory data){
        InitialValidator[] memory validators=new InitialValidator[](2);
        validators[0]=InitialValidator(abi.encodePacked(bytes20(uint160(100))),new bytes(48),weight);
        validators[1]=InitialValidator(abi.encodePacked(bytes20(uint160(101))),new bytes(48),weight);
        return ConversionData(SUBNET,CHAIN,address(manager),validators);
    }
    function mockConversion(ConversionData memory data) internal {
        bytes memory payload=ValidatorMessages.packSubnetToL1ConversionMessage(sha256(ValidatorMessages.packConversionData(data)));
        vm.mockCall(WARP,abi.encodeCall(IWarpMessenger.getVerifiedWarpMessage,(0)),abi.encode(WarpMessage(bytes32(0),address(0),payload),true));
    }
    function testActualPinnedInitializationAndWeightMinimum() public {
        ConversionData memory bad=conversion(1);mockConversion(bad);vm.expectRevert();manager.initializeValidatorSet(bad,0);
        ConversionData memory valid=conversion(1000);mockConversion(valid);manager.initializeValidatorSet(valid,0);
        assertTrue(manager.isValidatorSetInitialized());assertEq(manager.subnetID(),SUBNET);
        vm.expectRevert();manager.initializeValidatorSet(valid,0);
        vm.expectRevert();manager.initialize(ValidatorManagerSettings(outsider,SUBNET,3600,20));
        vm.expectRevert();implementation.initialize(ValidatorManagerSettings(outsider,SUBNET,3600,20));
    }
    function testActualChurnPreventsSingleStepReplacement() public {
        ConversionData memory data=conversion(1000);mockConversion(data);manager.initializeValidatorSet(data,0);
        bytes32 id=sha256(abi.encodePacked(SUBNET,uint32(0)));
        vm.prank(m.timelock);vm.expectRevert();poa.initiateValidatorRemoval(id);
        vm.prank(m.timelock);poa.initiateValidatorWeightUpdate(id,600); //400 of2000 maximum
        vm.prank(m.timelock);vm.expectRevert();poa.initiateValidatorWeightUpdate(id,599); // cumulative401 fails
        vm.warp(block.timestamp+3600);vm.prank(m.timelock);poa.initiateValidatorWeightUpdate(id,280); //320 of1600
        vm.prank(m.timelock);vm.expectRevert();poa.initiateValidatorRemoval(id); //needs280; only320 aggregate budget minus320
    }
    function testActualOwnersAndEmergencyCannotUpgradeOrTransferManager() public {
        assertEq(manager.owner(),address(poa));assertEq(poa.owner(),m.timelock);assertEq(proxyAdmin.owner(),m.timelock);
        vm.prank(outsider);vm.expectRevert();poa.transferValidatorManagerOwnership(outsider);
        vm.prank(m.emergency);vm.expectRevert();poa.transferValidatorManagerOwnership(outsider);
        vm.prank(m.emergency);vm.expectRevert();proxyAdmin.transferOwnership(outsider);
        vm.prank(m.emergency);vm.expectRevert();proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(manager)),address(implementation),"");
        vm.expectRevert();this.emergencyAttempt(address(proxyAdmin),abi.encodeCall(proxyAdmin.transferOwnership,(outsider)));
        vm.expectRevert();this.emergencyAttempt(address(poa),abi.encodeCall(poa.transferValidatorManagerOwnership,(outsider)));
        vm.expectRevert();this.emergencyAttempt(address(proxyAdmin),abi.encodeCall(proxyAdmin.upgradeAndCall,(ITransparentUpgradeableProxy(address(manager)),address(implementation),bytes(""))));
        bytes memory data=abi.encodeCall(proxyAdmin.upgradeAndCall,(ITransparentUpgradeableProxy(address(manager)),address(implementation),bytes("")));
        schedule(false,address(proxyAdmin),0,data,bytes32("upgrade"));
        vm.expectRevert();this.runReady(false,address(proxyAdmin),0,data,bytes32("upgrade"));
        vm.warp(block.timestamp+48 hours);assertTrue(runReady(false,address(proxyAdmin),0,data,bytes32("upgrade")));
    }
    function testActualPoAControlRequiresSafeAndProtocolDelay() public {
        bytes memory data=abi.encodeCall(poa.transferValidatorManagerOwnership,(m.timelock));
        vm.prank(c.protocolOwners[0]);vm.expectRevert();poa.transferValidatorManagerOwnership(m.timelock);
        vm.expectRevert();this.safeCall(false,address(poa),0,data,3); //Safe cannot bypass timelock
        schedule(false,address(poa),0,data,bytes32("poa-owner"));
        vm.warp(block.timestamp+48 hours);assertTrue(runReady(false,address(poa),0,data,bytes32("poa-owner")));
        assertEq(manager.owner(),m.timelock);
    }

}
