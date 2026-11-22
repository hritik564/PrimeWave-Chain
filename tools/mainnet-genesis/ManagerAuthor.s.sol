// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {Script} from "../../contracts/lib/forge-std/src/Script.sol";
import {ValidatorManager,ValidatorManagerSettings} from "../../genesis-build/pinned-manager/icm/avalanche/validator-manager/ValidatorManager.sol";
import {PoAManager} from "../../genesis-build/pinned-manager/icm/avalanche/validator-manager/PoAManager.sol";
import {IValidatorManagerExternalOwnable} from "../../genesis-build/pinned-manager/icm/avalanche/validator-manager/interfaces/IValidatorManagerExternalOwnable.sol";
import {ICMInitializable} from "../../genesis-build/pinned-manager/icm/avalanche/utilities/ICMInitializable.sol";
import {TransparentUpgradeableProxy} from "../../genesis-build/pinned-manager/oz/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "../../genesis-build/pinned-manager/oz/proxy/transparent/ProxyAdmin.sol";

/// Offline state author ONLY. Explicit validated public input; no synthetic defaults.
contract ManagerAuthor is Script {
    struct Inputs {address libraryAddress;address implementation;address proxy;address poa;address admin;address timelock;bytes32 subnet;uint64 period;uint8 churn;}
    function install(address target,bytes memory creation) internal {
        require(target!=address(0)&&target.code.length==0&&target.balance==0&&vm.getNonce(target)==0,"occupied target");
        vm.setNonce(target,1);vm.etch(target,creation);
        (bool ok,bytes memory runtime)=target.call("");require(ok&&runtime.length>0,"constructor failed");vm.etch(target,runtime);
    }
    function build(Inputs memory i,string memory libraryArtifact) public {
        require(i.subnet!=0&&i.period>0&&i.period<=86400&&i.churn>0&&i.churn<=20,"explicit settings");
        require(vm.computeCreateAddress(i.proxy,1)==i.admin,"derived ProxyAdmin mismatch");
        address[5] memory addresses=[i.libraryAddress,i.implementation,i.proxy,i.poa,i.admin];
        for(uint256 n;n<5;++n){require(addresses[n]!=address(0)&&addresses[n]!=i.timelock,"collision");for(uint256 j;j<n;++j)require(addresses[n]!=addresses[j],"collision");}
        vm.record();
        install(i.libraryAddress,vm.getCode(libraryArtifact));
        install(i.implementation,abi.encodePacked(type(ValidatorManager).creationCode,abi.encode(ICMInitializable.Disallowed)));
        install(i.proxy,abi.encodePacked(type(TransparentUpgradeableProxy).creationCode,abi.encode(i.implementation,i.timelock,
            abi.encodeCall(ValidatorManager.initialize,(ValidatorManagerSettings(i.poa,i.subnet,i.period,i.churn))))));
        install(i.poa,abi.encodePacked(type(PoAManager).creationCode,abi.encode(i.timelock,IValidatorManagerExternalOwnable(i.proxy))));
        verify(i);
    }
    function verify(Inputs memory i) public view {
        require(ValidatorManager(i.proxy).owner()==i.poa&&ValidatorManager(i.proxy).subnetID()==i.subnet,"manager binding");
        require(!ValidatorManager(i.proxy).isValidatorSetInitialized(),"premature conversion");
        (uint64 period,uint8 churn,)=ValidatorManager(i.proxy).getChurnTracker();require(period==i.period&&churn==i.churn,"churn mismatch");
        require(PoAManager(i.poa).owner()==i.timelock&&ProxyAdmin(i.admin).owner()==i.timelock,"owner mismatch");
        require(vm.getNonce(i.proxy)==2&&vm.getNonce(i.admin)==1,"nonce mismatch");
    }
    function account(address target) public returns(string memory) {
        string memory key=vm.toString(target);string memory sk=string.concat(key,"-slots");
        (,bytes32[] memory slots)=vm.accesses(target);string memory state="{}";
        for(uint256 n;n<slots.length;++n)state=vm.serializeString(sk,vm.toString(slots[n]),vm.toString(vm.load(target,slots[n])));
        vm.serializeString(key,"code",vm.toString(target.code));vm.serializeString(key,"balance",vm.toString(target.balance));
        vm.serializeString(key,"nonce",vm.toString(abi.encodePacked(vm.getNonce(target))));return vm.serializeString(key,"storage",state);
    }
    function exportState(Inputs memory i) public returns(string memory out){
        out="{}";address[5] memory list=[i.libraryAddress,i.implementation,i.proxy,i.poa,i.admin];
        for(uint256 n;n<5;++n)out=vm.serializeString("manager-state",vm.toString(list[n]),account(list[n]));
    }
    function run() external {
        string memory raw=vm.readFile(vm.envString("MAINNET_AUTHOR_INPUT"));Inputs memory i;
        i.libraryAddress=vm.parseJsonAddress(raw,".manager.library");i.implementation=vm.parseJsonAddress(raw,".manager.implementation");
        i.proxy=vm.parseJsonAddress(raw,".manager.proxy");i.poa=vm.parseJsonAddress(raw,".manager.poa");i.admin=vm.parseJsonAddress(raw,".manager.proxyAdmin");
        i.timelock=vm.parseJsonAddress(raw,".contracts.timelock");i.subnet=vm.parseJsonBytes32(raw,".manager.subnetBytes32");
        uint256 period=vm.parseJsonUint(raw,".manager.churnPeriodSeconds");uint256 churn=vm.parseJsonUint(raw,".manager.maximumChurnPercentage");
        require(period>0&&period<=86400&&churn>0&&churn<=20,"settings overflow");i.period=uint64(period);i.churn=uint8(churn);
        string memory output=vm.envString("MAINNET_MANAGER_OUTPUT");require(!vm.exists(output),"output exists");
        uint256 clean=vm.snapshotState();build(i,vm.envString("MAINNET_LIBRARY_ARTIFACT"));string memory first=exportState(i);
        require(vm.revertToState(clean),"snapshot");build(i,vm.envString("MAINNET_LIBRARY_ARTIFACT"));require(keccak256(bytes(first))==keccak256(bytes(exportState(i))),"nondeterministic");
        vm.writeJson(first,output);
    }
}
