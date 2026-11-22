// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import "forge-std/Test.sol";
import {CustodyGenesisState,IReviewSafe} from "../script/CustodyGenesisState.s.sol";
import {GenesisConstructorState} from "../script/GenesisConstructorState.s.sol";
import {PrimeWaveCustodyTimelock} from "../src/PrimeWaveCustodyTimelock.sol";
import {PauseOnlyEmergencyMultisig} from "../src/PauseOnlyEmergencyMultisig.sol";
import {TimelockOnlySafeGuard} from "../src/TimelockOnlySafeGuard.sol";
import {FeeDistributor} from "../src/FeeDistributor.sol";
import {RewardVault} from "../src/RewardVault.sol";

contract CustodySecurityTest is Test {
    CustodyGenesisState internal authoring;
    GenesisConstructorState.PublicConfig internal m;
    CustodyGenesisState.CustodyConfig internal c;
    PrimeWaveCustodyTimelock internal treasury;
    PrimeWaveCustodyTimelock internal protocol;
    uint256 internal beforeBuild;
    address internal outsider=address(0xF001);
    function setUp() public virtual {
        vm.chainId(73571001); // synthetic test context; no network/RPC
        authoring=new CustodyGenesisState();
        m.timelock=address(0xB001);m.emergency=address(0xB002);m.feeVault=address(0xB003);
        m.feeDistributor=address(0xB004);m.registry=address(0xB005);m.rewardVault=address(0xB006);
        m.manager=address(0xB007);m.treasury=address(0xB008);m.governance=address(0xB009);m.genesisTimestamp=1_800_000_000;
        c.safeSingleton=address(0xB010);c.protocolSafe=m.governance;c.treasurySafe=address(0xB011);c.protocolGuard=address(0xB012);c.treasuryGuard=address(0xB013);
        for(uint256 i;i<5;++i){c.protocolOwners[i]=address(uint160(0xA100+i));c.treasuryOwners[i]=address(uint160(0xA200+i));m.signers[i]=address(uint160(0xA300+i));}
        beforeBuild=vm.snapshotState();
        authoring.buildProduction(m,c);
        treasury=PrimeWaveCustodyTimelock(payable(m.treasury));protocol=PrimeWaveCustodyTimelock(payable(m.timelock));
    }
    // Uses Safe's native approved-hash signature mode with synthetic addresses.
    // No vm.sign, keys, real signatures, production owners or remote calls.
    function safeCall(bool isTreasury,address to,uint256 value,bytes memory data,uint256 approvals) public returns(bool){
        return configuredSafeCall(isTreasury,to,value,data,approvals,0,0,payable(address(0)));
    }
    function configuredSafeCall(bool isTreasury,address to,uint256 value,bytes memory data,uint256 approvals,uint8 operation,uint256 gasPrice,address payable refundReceiver) public returns(bool){
        address safe_=isTreasury?c.treasurySafe:c.protocolSafe;
        bytes32 hash=IReviewSafe(safe_).getTransactionHash(to,value,data,operation,0,0,gasPrice,address(0),refundReceiver,IReviewSafe(safe_).nonce());
        bytes memory sigs;
        for(uint256 i;i<approvals;++i){address owner=isTreasury?c.treasuryOwners[i]:c.protocolOwners[i];vm.prank(owner);IReviewSafe(safe_).approveHash(hash);sigs=abi.encodePacked(sigs,bytes32(uint256(uint160(owner))),bytes32(0),uint8(1));}
        return IReviewSafe(safe_).execTransaction(to,value,data,operation,0,0,gasPrice,address(0),refundReceiver,sigs);
    }
    function schedule(bool isTreasury,address target,uint256 value,bytes memory data,bytes32 salt) internal {
        PrimeWaveCustodyTimelock clock=isTreasury?treasury:protocol;
        require(safeCall(isTreasury,address(clock),0,abi.encodeCall(clock.schedule,(target,value,data,bytes32(0),salt,48 hours)),3));
    }
    function runReady(bool isTreasury,address target,uint256 value,bytes memory data,bytes32 salt) public returns(bool){
        PrimeWaveCustodyTimelock clock=isTreasury?treasury:protocol;
        return safeCall(isTreasury,address(clock),0,abi.encodeCall(clock.execute,(target,value,data,bytes32(0),salt)),3);
    }
    function emergencyAttempt(address target,bytes memory data) public {
        PauseOnlyEmergencyMultisig em=PauseOnlyEmergencyMultisig(m.emergency);uint256 n=em.nonce();bytes32 id=em.propose(target,data);
        for(uint256 i;i<3;++i){vm.prank(m.signers[i]);em.approve(id);}
        em.execute(target,data,n);
    }
    function testNativeInboundOutboundRequiresMultisigAndDelay() public {
        vm.deal(address(this),2 ether);(bool received,)=m.treasury.call{value:2 ether}("");assertTrue(received);
        assertEq(m.treasury.balance,15_000_002 ether);
        schedule(true,outsider,1 ether,"",bytes32("pay"));
        vm.expectRevert();this.runReady(true,outsider,1 ether,"",bytes32("pay"));
        vm.warp(block.timestamp+48 hours);assertTrue(runReady(true,outsider,1 ether,"",bytes32("pay")));
        assertEq(outsider.balance,1 ether);assertEq(m.treasury.balance,15_000_001 ether);
        vm.expectRevert();this.runReady(true,outsider,1 ether,"",bytes32("pay"));
    }
    function testFeeDistributorNativeTreasuryShareIsHeldByTimelock() public {
        vm.deal(m.feeDistributor,100 ether);
        FeeDistributor(payable(m.feeDistributor)).distribute();
        assertEq(m.treasury.balance,15_000_020 ether);
        assertEq(m.feeVault.balance,70 ether);
        assertEq(c.treasurySafe.balance,0);
    }
    function testRolesNoDeployerEOAOrEmergencyAdmin() public view {
        assertEq(IReviewSafe(c.protocolSafe).getThreshold(),3);assertEq(IReviewSafe(c.treasurySafe).getThreshold(),3);
        assertEq(IReviewSafe(c.treasurySafe).getOwners().length,5);
        assertTrue(treasury.hasRole(treasury.DEFAULT_ADMIN_ROLE(),m.treasury));
        assertTrue(treasury.hasRole(treasury.PROPOSER_ROLE(),c.treasurySafe));
        assertTrue(treasury.hasRole(treasury.EXECUTOR_ROLE(),c.treasurySafe));
        assertTrue(treasury.hasRole(treasury.CANCELLER_ROLE(),c.treasurySafe));
        assertFalse(treasury.hasRole(treasury.DEFAULT_ADMIN_ROLE(),c.treasurySafe));
        assertFalse(treasury.hasRole(treasury.DEFAULT_ADMIN_ROLE(),address(authoring)));
        assertFalse(treasury.hasRole(treasury.EXECUTOR_ROLE(),address(0)));
        assertFalse(treasury.hasRole(treasury.PROPOSER_ROLE(),c.protocolSafe));
        assertFalse(treasury.hasRole(treasury.DEFAULT_ADMIN_ROLE(),m.emergency));
    }
    function testTwoSafeOwnersCannotExecuteOrEscalate() public {
        vm.expectRevert();this.safeCall(true,outsider,1,"",2);
        vm.prank(outsider);vm.expectRevert();treasury.grantRole(bytes32(0),outsider);
        vm.prank(m.emergency);vm.expectRevert();treasury.grantRole(bytes32(0),outsider);
        vm.prank(c.treasuryOwners[0]);vm.expectRevert();treasury.schedule(outsider,1,"",bytes32(0),bytes32(0),48 hours);
        vm.prank(outsider);vm.expectRevert();treasury.execute(outsider,1,"",bytes32(0),bytes32(0));
    }
    function testCancelAndPermissionChecks() public {
        bytes32 salt=bytes32("cancel");schedule(true,outsider,1,"",salt);
        bytes32 id=treasury.hashOperation(outsider,1,"",bytes32(0),salt);
        vm.prank(outsider);vm.expectRevert();treasury.cancel(id);
        assertTrue(safeCall(true,m.treasury,0,abi.encodeCall(treasury.cancel,(id)),3));
        vm.warp(block.timestamp+48 hours);vm.expectRevert();this.runReady(true,outsider,1,"",salt);
    }
    function testTimelockFloorCannotBeReducedEvenByGovernance() public {
        bytes memory data=abi.encodeCall(treasury.updateDelay,(1));schedule(true,m.treasury,0,data,bytes32("delay"));
        vm.warp(block.timestamp+48 hours);vm.expectRevert();this.runReady(true,m.treasury,0,data,bytes32("delay"));
        assertEq(treasury.getMinDelay(),48 hours);
    }
    function testEmergencyPauseWorksButProtectedArbitraryCallsFail() public {
        emergencyAttempt(m.rewardVault,abi.encodeWithSignature("pause()"));assertTrue(RewardVault(payable(m.rewardVault)).paused());
        emergencyAttempt(m.rewardVault,abi.encodeWithSignature("unpause()"));assertFalse(RewardVault(payable(m.rewardVault)).paused());
        vm.expectRevert();this.emergencyAttempt(m.rewardVault,abi.encodeWithSignature("setEmissionRate(uint256)",1));
        vm.expectRevert();this.emergencyAttempt(m.rewardVault,abi.encodeWithSignature("setPauseController(address)",outsider));
        vm.expectRevert();this.emergencyAttempt(m.treasury,abi.encodeCall(treasury.execute,(outsider,1,"",bytes32(0),bytes32(0))));
        vm.expectRevert();this.emergencyAttempt(m.treasury,abi.encodeCall(treasury.grantRole,(bytes32(0),m.emergency)));
        vm.expectRevert();this.emergencyAttempt(c.treasurySafe,abi.encodeWithSignature("transferOwnership(address)",outsider));
        vm.expectRevert();this.emergencyAttempt(m.manager,abi.encodeWithSignature("transferOwnership(address)",outsider));
        vm.expectRevert();this.emergencyAttempt(m.manager,abi.encodeWithSignature("upgradeAndCall(address,address,bytes)",outsider,outsider,""));
    }
    function testRotationOnlyThroughProtocolTimelock() public {
        address next=address(new PauseOnlyEmergencyMultisig(m.signers,[m.feeDistributor,m.feeVault,m.rewardVault],m.timelock));
        vm.prank(m.signers[0]);vm.expectRevert();PauseOnlyEmergencyMultisig(m.emergency).rotatePauseController(m.rewardVault,next);
        bytes memory data=abi.encodeCall(PauseOnlyEmergencyMultisig.rotatePauseController,(m.rewardVault,next));
        schedule(false,m.emergency,0,data,bytes32("rotate"));vm.warp(block.timestamp+48 hours);
        assertTrue(runReady(false,m.emergency,0,data,bytes32("rotate")));
        assertEq(RewardVault(payable(m.rewardVault)).pauseController(),next);
    }
    function testExportRoundTripSelfAdminAndSafeOwnersAtExactAddresses() public {
        string memory exported=authoring.accountJson(m.treasury);
        assertEq(vm.parseJsonBytes(exported,".code"),m.treasury.code);
        assertEq(vm.parseJsonUint(exported,".balance"),15_000_000 ether);
        assertEq(exported,authoring.accountJson(m.treasury));
        assertEq(c.safeSingleton.code,vm.parseJsonBytes(vm.readFile("contracts/vendor/safe-1.4.1/Safe.json"),".deployedBytecode"));
        assertEq(c.treasurySafe.code,vm.parseJsonBytes(vm.readFile("contracts/vendor/safe-1.4.1/SafeProxy.json"),".deployedBytecode"));
    }
    function testCompleteExportRepeatabilityAndRestore() public {
        string memory first=authoring.accountsJson(m,c);
        assertTrue(vm.revertToState(beforeBuild));
        authoring.buildProduction(m,c);
        string memory second=authoring.accountsJson(m,c);
        assertEq(first,second,"constructor export nondeterministic");
        address[12] memory targets=[m.timelock,m.emergency,m.feeVault,m.feeDistributor,m.registry,m.rewardVault,m.treasury,c.safeSingleton,c.protocolSafe,c.treasurySafe,c.protocolGuard,c.treasuryGuard];
        for(uint256 i;i<targets.length;++i){
            string memory account=authoring.accountJson(targets[i]);
            bytes memory code=vm.parseJsonBytes(account,".code");
            string[] memory slots=vm.parseJsonKeys(account,".storage");
            vm.etch(targets[i],"");vm.deal(targets[i],0);
            for(uint256 j;j<slots.length;++j)vm.store(targets[i],vm.parseBytes32(slots[j]),bytes32(0));
            vm.etch(targets[i],code);vm.deal(targets[i],vm.parseJsonUint(account,".balance"));
            for(uint256 j;j<slots.length;++j)vm.store(targets[i],vm.parseBytes32(slots[j]),vm.parseJsonBytes32(account,string.concat(".storage.",slots[j])));
        }
        PrimeWaveCustodyTimelock restored=PrimeWaveCustodyTimelock(payable(m.treasury));
        assertEq(m.treasury.balance,15_000_000 ether);
        assertTrue(restored.hasRole(restored.DEFAULT_ADMIN_ROLE(),m.treasury));
        assertTrue(restored.hasRole(restored.PROPOSER_ROLE(),c.treasurySafe));
        assertFalse(restored.hasRole(restored.DEFAULT_ADMIN_ROLE(),address(authoring)));
        address[] memory treasuryOwners=IReviewSafe(c.treasurySafe).getOwners();
        address[] memory protocolOwners=IReviewSafe(c.protocolSafe).getOwners();
        for(uint256 i;i<5;++i){assertEq(treasuryOwners[i],c.treasuryOwners[i]);assertEq(protocolOwners[i],c.protocolOwners[i]);}
        (address[] memory treasuryModules,)=IReviewSafe(c.treasurySafe).getModulesPaginated(address(1),10);
        (address[] memory protocolModules,)=IReviewSafe(c.protocolSafe).getModulesPaginated(address(1),10);
        assertEq(treasuryModules.length,0);assertEq(protocolModules.length,0);
        assertEq(IReviewSafe(c.treasurySafe).getThreshold(),3);
        assertEq(uint256(vm.load(c.treasurySafe,bytes32(0))),uint256(uint160(c.safeSingleton)));
        treasury=restored;protocol=PrimeWaveCustodyTimelock(payable(m.timelock));
        schedule(true,outsider,1,"",bytes32("restored pay"));vm.warp(block.timestamp+48 hours);
        assertTrue(runReady(true,outsider,1,"",bytes32("restored pay")));assertEq(outsider.balance,1);
    }
    function testSafeConfigurationCannotBypassTimelockEvenWithQuorum() public {
        vm.expectRevert();this.safeCall(true,c.treasurySafe,0,abi.encodeWithSignature("changeThreshold(uint256)",1),3);
        vm.expectRevert();this.safeCall(true,c.treasurySafe,0,abi.encodeWithSignature("setGuard(address)",address(0)),3);
        vm.expectRevert();this.safeCall(true,c.treasurySafe,0,abi.encodeWithSignature("enableModule(address)",outsider),3);
        vm.expectRevert();this.safeCall(true,c.treasurySafe,0,abi.encodeWithSignature("swapOwner(address,address,address)",address(1),c.treasuryOwners[0],outsider),3);
        vm.expectRevert();this.safeCall(true,outsider,1,"",3);
        vm.expectRevert();this.configuredSafeCall(true,m.treasury,0,"",3,1,0,payable(address(0)));
        vm.expectRevert();this.configuredSafeCall(true,m.treasury,0,"",3,0,1,payable(outsider));
        assertEq(IReviewSafe(c.treasurySafe).getThreshold(),3);
    }
    function testSignerRotationUsesDelayedAtomicSafeRoleMigration() public {
        bytes memory creation=abi.encodePacked(authoring.artifact("SafeProxy"),abi.encode(c.safeSingleton));
        address next;assembly{next:=create(0,add(creation,32),mload(creation))}
        require(next!=address(0));address[] memory owners=new address[](5);
        for(uint256 i;i<5;++i)owners[i]=address(uint160(0xA400+i));
        IReviewSafe(next).setup(owners,3,address(0),"",address(0),address(0),0,payable(address(0)));
        TimelockOnlySafeGuard nextGuard=new TimelockOnlySafeGuard(next,m.treasury);
        vm.prank(next);IReviewSafe(next).setGuard(address(nextGuard)); // test genesis/creation setup only
        bytes32[3] memory roles=[treasury.PROPOSER_ROLE(),treasury.EXECUTOR_ROLE(),treasury.CANCELLER_ROLE()];
        address[] memory targets=new address[](6);uint256[] memory values=new uint256[](6);bytes[] memory payloads=new bytes[](6);
        for(uint256 i;i<3;++i){targets[i]=m.treasury;targets[i+3]=m.treasury;payloads[i]=abi.encodeCall(treasury.grantRole,(roles[i],next));payloads[i+3]=abi.encodeCall(treasury.revokeRole,(roles[i],c.treasurySafe));}
        bytes32 salt=bytes32("Safe migration");
        assertTrue(safeCall(true,m.treasury,0,abi.encodeCall(treasury.scheduleBatch,(targets,values,payloads,bytes32(0),salt,48 hours)),3));
        vm.warp(block.timestamp+48 hours);
        assertTrue(safeCall(true,m.treasury,0,abi.encodeCall(treasury.executeBatch,(targets,values,payloads,bytes32(0),salt)),3));
        for(uint256 i;i<3;++i){assertTrue(treasury.hasRole(roles[i],next));assertFalse(treasury.hasRole(roles[i],c.treasurySafe));}
        assertTrue(treasury.hasRole(bytes32(0),m.treasury));assertFalse(treasury.hasRole(bytes32(0),next));
        vm.expectRevert();this.safeCall(true,m.treasury,0,abi.encodeCall(treasury.schedule,(outsider,0,bytes(""),bytes32(0),bytes32(0),48 hours)),3);
    }
    function testExporterRefusesToOverwriteAnExistingReviewFile() public {
        string memory path="genesis-build/custody-test-existing-output.json";
        vm.writeFile(path,"review evidence");vm.setEnv("GENESIS_STATE_OUTPUT",path);
        vm.expectRevert("custody: output exists");authoring.run();
        assertEq(vm.readFile(path),"review evidence");
    }
    function testWriteSyntheticExportForPythonIntegration() public {
        vm.writeJson(authoring.accountsJson(m,c),"genesis-build/custody-fixture.raw.json");
    }
    function testSingletonAndSafeSetupCannotBeReinitialized() public {
        address[] memory list=new address[](5);for(uint256 i;i<5;++i)list[i]=c.protocolOwners[i];
        vm.expectRevert();IReviewSafe(c.safeSingleton).setup(list,3,address(0),"",address(0),address(0),0,payable(address(0)));
        vm.expectRevert();IReviewSafe(c.protocolSafe).setup(list,3,address(0),"",address(0),address(0),0,payable(address(0)));
    }

}
