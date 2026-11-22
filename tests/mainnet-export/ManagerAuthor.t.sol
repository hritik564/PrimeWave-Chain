// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {Test} from "../../contracts/lib/forge-std/src/Test.sol";
import {ManagerAuthor} from "../../tools/mainnet-genesis/ManagerAuthor.s.sol";
import {ValidatorManager,ValidatorManagerSettings} from "../../genesis-build/pinned-manager/icm/avalanche/validator-manager/ValidatorManager.sol";
contract ManagerAuthorTest is Test {
    ManagerAuthor author;ManagerAuthor.Inputs i;
    string constant ARTIFACT="genesis-build/mainnet-author-test/artifacts/ValidatorMessages.sol/ValidatorMessages.json";
    function setUp() public {
        author=new ManagerAuthor();
        i.libraryAddress=address(bytes20(hex"110000000000000000000000000000000000e100"));
        i.implementation=address(bytes20(hex"110000000000000000000000000000000000e101"));
        i.poa=address(bytes20(hex"110000000000000000000000000000000000e102"));
        i.proxy=address(bytes20(hex"110000000000000000000000000000000000e103"));
        i.timelock=address(bytes20(hex"110000000000000000000000000000000000b001"));
        i.admin=vm.computeCreateAddress(i.proxy,1);i.subnet=keccak256("explicit test subnet, never production");i.period=3600;i.churn=20;
    }
    function testInputDrivenAuthorRepeatAndFreshRestore() public {
        uint256 clean=vm.snapshotState();author.build(i,ARTIFACT);string memory first=author.exportState(i);
        address[5] memory list=[i.libraryAddress,i.implementation,i.proxy,i.poa,i.admin];string[5] memory states;
        for(uint256 n;n<5;++n)states[n]=author.account(list[n]);
        assertTrue(vm.revertToState(clean));author.build(i,ARTIFACT);assertEq(first,author.exportState(i));
        assertTrue(vm.revertToState(clean));
        for(uint256 n;n<5;++n){
            assertEq(list[n].code.length,0);assertEq(vm.getNonce(list[n]),0);
            string memory raw=states[n];vm.etch(list[n],vm.parseJsonBytes(raw,".code"));vm.deal(list[n],vm.parseJsonUint(raw,".balance"));vm.setNonce(list[n],uint64(vm.parseJsonUint(raw,".nonce")));
            string[] memory slots=vm.parseJsonKeys(raw,".storage");
            for(uint256 j;j<slots.length;++j){bytes32 slot=vm.parseBytes32(slots[j]);bytes32 value=vm.parseJsonBytes32(raw,string.concat(".storage.",slots[j]));vm.store(list[n],slot,value);assertEq(vm.load(list[n],slot),value);}
        }
        author.verify(i);
        vm.expectRevert();ValidatorManager(i.proxy).initialize(ValidatorManagerSettings(address(this),i.subnet,3600,20));
        vm.expectRevert();ValidatorManager(i.implementation).initialize(ValidatorManagerSettings(address(this),i.subnet,3600,20));
    }
    function testWriteFocusedPublicStateForRuntimeChecks() public {
        author.build(i,ARTIFACT);vm.writeJson(author.exportState(i),"genesis-build/mainnet-author-test/state.json");
        string memory out="{}";vm.serializeAddress("plan","library",i.libraryAddress);vm.serializeAddress("plan","implementation",i.implementation);vm.serializeAddress("plan","proxy",i.proxy);vm.serializeAddress("plan","poa",i.poa);out=vm.serializeAddress("plan","proxyAdmin",i.admin);vm.writeJson(out,"genesis-build/mainnet-author-test/plan.json");
    }
    function testNoDefaultSubnetOrDerivedAdminFallback() public {
        i.subnet=bytes32(0);vm.expectRevert();author.build(i,ARTIFACT);
        i.subnet=keccak256("test");i.admin=address(1);vm.expectRevert();author.build(i,ARTIFACT);
    }
    function testCollisionAndExistingAccountRefused() public {
        i.poa=i.proxy;vm.expectRevert();author.build(i,ARTIFACT);
        i.poa=address(8);vm.etch(i.libraryAddress,hex"00");vm.expectRevert();author.build(i,ARTIFACT);
    }
    function testNoChurnTruncationOrImplicitValues() public {
        i.period=0;vm.expectRevert();author.build(i,ARTIFACT);
        i.period=3600;i.churn=21;vm.expectRevert();author.build(i,ARTIFACT);
    }
}
