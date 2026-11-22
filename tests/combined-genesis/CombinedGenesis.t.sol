// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {ValidatorMessages} from "../../genesis-build/pinned-manager/icm/avalanche/validator-manager/ValidatorMessages.sol";
import {ConversionData,InitialValidator} from "../../genesis-build/pinned-manager/icm/avalanche/validator-manager/interfaces/IACP99Manager.sol";
import {IWarpMessenger,WarpMessage} from "../../genesis-build/pinned-manager/icm/avalanche/subnet-evm/IWarpMessenger.sol";
import {Test} from "forge-std/Test.sol";
import {CustodySecurityTest} from "../../contracts/test/CustodySecurity.t.sol";
import {CustodyGenesisState,IReviewSafe} from "../../contracts/script/CustodyGenesisState.s.sol";
import {PrimeWaveCustodyTimelock} from "../../contracts/src/PrimeWaveCustodyTimelock.sol";
import {TimelockOnlySafeGuard} from "../../contracts/src/TimelockOnlySafeGuard.sol";
import {PauseOnlyEmergencyMultisig} from "../../contracts/src/PauseOnlyEmergencyMultisig.sol";
import {PrimeWaveValidatorRegistry} from "../../contracts/src/PrimeWaveValidatorRegistry.sol";
import {ValidatorManager,ValidatorManagerSettings} from "../../genesis-build/pinned-manager/icm/avalanche/validator-manager/ValidatorManager.sol";
import {PoAManager} from "../../genesis-build/pinned-manager/icm/avalanche/validator-manager/PoAManager.sol";
import {IValidatorManagerExternalOwnable} from "../../genesis-build/pinned-manager/icm/avalanche/validator-manager/interfaces/IValidatorManagerExternalOwnable.sol";
import {ICMInitializable} from "../../genesis-build/pinned-manager/icm/avalanche/utilities/ICMInitializable.sol";
import {TransparentUpgradeableProxy,ITransparentUpgradeableProxy} from "../../genesis-build/pinned-manager/oz/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "../../genesis-build/pinned-manager/oz/proxy/transparent/ProxyAdmin.sol";

/// Test-only constructor authoring. No production address/input/approval path.
contract CombinedAuthor is Test {
    function install(address target,bytes memory creation) external {
        require(target.code.length==0&&target.balance==0&&vm.getNonce(target)==0,"occupied");
        vm.setNonce(target,1);vm.etch(target,creation);
        (bool ok,bytes memory runtime)=target.call("");require(ok&&runtime.length>0,"constructor");vm.etch(target,runtime);
    }
    function exportAccount(address target) external returns(string memory) {
        string memory key=string.concat("combined-",vm.toString(target));
        string memory storageKey=string.concat(key,"-storage");
        (,bytes32[] memory slots)=vm.accesses(target);string memory state="{}";
        for(uint256 i;i<slots.length;++i)state=vm.serializeString(storageKey,vm.toString(slots[i]),vm.toString(vm.load(target,slots[i])));
        vm.serializeString(key,"code",vm.toString(target.code));vm.serializeString(key,"balance",vm.toString(target.balance));
        vm.serializeString(key,"nonce",vm.toString(abi.encodePacked(vm.getNonce(target))));
        return vm.serializeString(key,"storage",state);
    }
}

contract CombinedGenesisTest is CustodySecurityTest {
    address constant LIBRARY=address(0xE100);
    address constant IMPLEMENTATION=address(0xE101);
    address constant POA=address(0xE102);
    bytes32 constant SUBNET=bytes32(uint256(123)); // synthetic only; no real SubnetID
    bytes32 constant ADMIN_SLOT=0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
    bytes32 constant IMPLEMENTATION_SLOT=0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    CombinedAuthor builder;
    address admin;
    uint256 clean;
    function setUp() public override {
        super.setUp();
        // Preserve locked custody runtimes: manager remappings alter Solidity metadata.
        string memory fixture=vm.readFile("genesis-build/combined-synthetic-build/fixture.input.json");
        address[12] memory custody=[m.timelock,m.emergency,m.feeVault,m.feeDistributor,m.registry,m.rewardVault,m.treasury,c.safeSingleton,c.protocolSafe,c.treasurySafe,c.protocolGuard,c.treasuryGuard];
        for(uint256 i;i<12;++i)vm.etch(custody[i],vm.parseJsonBytes(fixture,string.concat(".accounts.",vm.toLowercase(vm.toString(custody[i])),".code")));
        builder=new CombinedAuthor();
        clean=vm.snapshotState();
        installManager();
    }
    function installManager() internal {
        builder.install(LIBRARY,vm.getCode("genesis-build/combined-synthetic-build/artifacts/ValidatorMessages.sol/ValidatorMessages.json"));
        builder.install(IMPLEMENTATION,abi.encodePacked(type(ValidatorManager).creationCode,abi.encode(ICMInitializable.Disallowed)));
        admin=vm.computeCreateAddress(m.manager,1);
        require(admin!=LIBRARY&&admin!=IMPLEMENTATION&&admin!=POA&&admin!=c.safeSingleton,"address collision");
        builder.install(m.manager,abi.encodePacked(type(TransparentUpgradeableProxy).creationCode,abi.encode(IMPLEMENTATION,m.timelock,
            abi.encodeCall(ValidatorManager.initialize,(ValidatorManagerSettings(POA,SUBNET,3600,20))))));
        builder.install(POA,abi.encodePacked(type(PoAManager).creationCode,abi.encode(m.timelock,IValidatorManagerExternalOwnable(m.manager))));
    }
    function accounts() internal view returns(address[17] memory){
        return [m.timelock,m.emergency,m.feeVault,m.feeDistributor,m.registry,m.rewardVault,m.treasury,c.safeSingleton,c.protocolSafe,c.treasurySafe,c.protocolGuard,c.treasuryGuard,LIBRARY,IMPLEMENTATION,m.manager,POA,admin];
    }
    function exportFor(uint256 index,address target) internal returns(string memory){
        return index<12?authoring.accountJson(target):builder.exportAccount(target);
    }
    function exported() internal returns(string memory out){
        out="{}";address[17] memory list=accounts();
        for(uint256 i;i<list.length;++i)out=vm.serializeString("combined-export",vm.toString(list[i]),exportFor(i,list[i]));
    }
    function verifyBindings() internal view {
        assertEq(ValidatorManager(m.manager).owner(),POA);
        assertEq(ValidatorManager(m.manager).subnetID(),SUBNET);
        assertFalse(ValidatorManager(m.manager).isValidatorSetInitialized()); // conversion proof still required
        assertEq(PoAManager(POA).owner(),m.timelock);
        assertEq(ProxyAdmin(admin).owner(),m.timelock);
        assertEq(address(uint160(uint256(vm.load(m.manager,ADMIN_SLOT)))),admin);
        assertEq(address(uint160(uint256(vm.load(m.manager,IMPLEMENTATION_SLOT)))),IMPLEMENTATION);
        assertEq(vm.getNonce(m.manager),2);assertEq(vm.getNonce(admin),1);
        assertEq(address(PrimeWaveValidatorRegistry(m.registry).validatorManager()),m.manager);
        assertEq(IReviewSafe(c.protocolSafe).getThreshold(),3);assertEq(IReviewSafe(c.treasurySafe).getThreshold(),3);
        assertEq(TimelockOnlySafeGuard(c.protocolGuard).safe(),c.protocolSafe);
        assertEq(TimelockOnlySafeGuard(c.protocolGuard).timelock(),m.timelock);
        assertEq(TimelockOnlySafeGuard(c.treasuryGuard).safe(),c.treasurySafe);
        assertEq(TimelockOnlySafeGuard(c.treasuryGuard).timelock(),m.treasury);
        assertTrue(protocol.hasRole(bytes32(0),m.timelock));assertTrue(treasury.hasRole(bytes32(0),m.treasury));
        assertTrue(protocol.hasRole(protocol.PROPOSER_ROLE(),c.protocolSafe));assertTrue(treasury.hasRole(treasury.EXECUTOR_ROLE(),c.treasurySafe));
        assertEq(m.treasury.balance,15_000_000 ether);assertEq(m.rewardVault.balance,15_000_000 ether);
        assertTrue(PauseOnlyEmergencyMultisig(m.emergency).allowedTarget(m.feeVault));
        address[17] memory list=accounts();
        for(uint256 i;i<list.length;++i){assertGt(list[i].code.length,0);for(uint256 j;j<i;++j)assertTrue(list[i]!=list[j]);}
    }
    function testCombinedBindingsAndProtectedInitializers() public {
        verifyBindings();
        vm.expectRevert();ValidatorManager(m.manager).initialize(ValidatorManagerSettings(outsider,SUBNET,3600,20));
        vm.expectRevert();ValidatorManager(IMPLEMENTATION).initialize(ValidatorManagerSettings(outsider,SUBNET,3600,20));
        vm.prank(outsider);vm.expectRevert();ProxyAdmin(admin).upgradeAndCall(ITransparentUpgradeableProxy(m.manager),IMPLEMENTATION,"");
        // Calls actual proxy fallback, linked library, and PoA immutable manager.
        vm.prank(m.timelock);vm.expectRevert();PoAManager(POA).initiateValidatorRemoval(bytes32(uint256(1)));
    }
    function testCombinedExportRepeatabilityFreshRestorationAndRuntime() public {
        string memory first=exported();
        address[17] memory list=accounts();bytes32[17] memory hashes;string[17] memory raws;
        for(uint256 i;i<17;++i){hashes[i]=list[i].codehash;raws[i]=exportFor(i,list[i]);}
        assertTrue(vm.revertToState(clean));installManager();assertEq(first,exported());
        // Revert to before even custody constructors, then restore every exported account
        // into that fresh snapshot (builder itself need not exist for vm JSON parsing).
        address savedAdmin=admin;
        assertTrue(vm.revertToState(beforeBuild));
        admin=savedAdmin;protocol=PrimeWaveCustodyTimelock(payable(m.timelock));treasury=PrimeWaveCustodyTimelock(payable(m.treasury));
        for(uint256 i;i<17;++i){
            assertEq(list[i].code.length,0);assertEq(vm.getNonce(list[i]),0);
            string memory raw=raws[i];
            vm.etch(list[i],vm.parseJsonBytes(raw,".code"));vm.deal(list[i],vm.parseJsonUint(raw,".balance"));
            vm.setNonce(list[i],uint64(vm.parseJsonUint(raw,".nonce")));
            string[] memory slots=vm.parseJsonKeys(raw,".storage");
            for(uint256 j;j<slots.length;++j)vm.store(list[i],vm.parseBytes32(slots[j]),vm.parseJsonBytes32(raw,string.concat(".storage.",slots[j])));
            assertEq(list[i].codehash,hashes[i]);
            for(uint256 j;j<slots.length;++j)assertEq(vm.load(list[i],vm.parseBytes32(slots[j])),vm.parseJsonBytes32(raw,string.concat(".storage.",slots[j])));
        }
        verifyBindings();
        schedule(true,outsider,1,"",bytes32("combined restore"));vm.warp(block.timestamp+48 hours);
        assertTrue(runReady(true,outsider,1,"",bytes32("combined restore")));
        bytes memory data=abi.encodeCall(ProxyAdmin.upgradeAndCall,(ITransparentUpgradeableProxy(m.manager),IMPLEMENTATION,bytes("")));
        schedule(false,admin,0,data,bytes32("proxy immutable"));vm.warp(block.timestamp+48 hours);
        assertTrue(runReady(false,admin,0,data,bytes32("proxy immutable"))); // proves runtime admin binding after restore
        data=abi.encodeCall(PoAManager.transferValidatorManagerOwnership,(m.timelock));
        schedule(false,POA,0,data,bytes32("poa immutable"));vm.warp(block.timestamp+48 hours);
        assertTrue(runReady(false,POA,0,data,bytes32("poa immutable")));assertEq(ValidatorManager(m.manager).owner(),m.timelock);
    }
    function testLinkedLibraryAndMockedConversion() public {
        IWarpMessenger warp=IWarpMessenger(address(0x0200000000000000000000000000000000000005));
        bytes32 chain=bytes32(uint256(456));
        InitialValidator[] memory validators=new InitialValidator[](2);
        validators[0]=InitialValidator(abi.encodePacked(bytes20(uint160(100))),new bytes(48),1000);
        validators[1]=InitialValidator(abi.encodePacked(bytes20(uint160(101))),new bytes(48),1000);
        ConversionData memory data=ConversionData(SUBNET,chain,m.manager,validators);
        bytes memory payload=ValidatorMessages.packSubnetToL1ConversionMessage(sha256(ValidatorMessages.packConversionData(data)));
        vm.mockCall(address(warp),abi.encodeCall(warp.getBlockchainID,()),abi.encode(chain));
        vm.mockCall(address(warp),abi.encodeCall(warp.getVerifiedWarpMessage,(0)),abi.encode(WarpMessage(bytes32(0),address(0),payload),true));
        ValidatorManager(m.manager).initializeValidatorSet(data,0);
        assertTrue(ValidatorManager(m.manager).isValidatorSetInitialized());
        assertEq(ValidatorManager(m.manager).l1TotalWeight(),2000);
    }
    function testWriteCombinedSyntheticExport() public {
        verifyBindings();vm.writeJson(exported(),"genesis-build/combined-synthetic.raw.json");
        vm.writeJson(string.concat('{"proxyAdmin":"',vm.toString(admin),'"}'),"genesis-build/combined-synthetic.admin.json");
    }
}
