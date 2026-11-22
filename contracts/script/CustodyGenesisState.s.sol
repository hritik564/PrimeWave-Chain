// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {GenesisConstructorState} from "./GenesisConstructorState.s.sol";
import {PrimeWaveCustodyTimelock} from "../src/PrimeWaveCustodyTimelock.sol";
import {TimelockOnlySafeGuard} from "../src/TimelockOnlySafeGuard.sol";
import {PauseOnlyEmergencyMultisig} from "../src/PauseOnlyEmergencyMultisig.sol";

interface IReviewSafe {
    function setup(address[] calldata,uint256,address,bytes calldata,address,address,uint256,address payable) external;
    function getOwners() external view returns(address[] memory);
    function getThreshold() external view returns(uint256);
    function nonce() external view returns(uint256);
    function getModulesPaginated(address,uint256) external view returns(address[] memory,address);
    function approveHash(bytes32) external;
    function setGuard(address) external;
    function getTransactionHash(address,uint256,bytes calldata,uint8,uint256,uint256,uint256,address,address,uint256) external view returns(bytes32);
    function execTransaction(address,uint256,bytes calldata,uint8,uint256,uint256,uint256,address,address payable,bytes calldata) external payable returns(bool);
}

/// @notice Offline authoring EVM only. Constructors run at EXACT final addresses,
/// never copied from another self-administered timelock/proxy instance. No RPC,
/// signing or broadcast. All addresses/signers are explicit public inputs.
contract CustodyGenesisState is GenesisConstructorState {
    struct CustodyConfig {
        address safeSingleton;
        address protocolSafe;
        address treasurySafe;
        address protocolGuard;
        address treasuryGuard;
        address[5] protocolOwners;
        address[5] treasuryOwners;
    }
    function artifact(string memory name) public view returns(bytes memory) {
        return vm.getCode(string.concat("contracts/vendor/safe-1.4.1/",name,".json"));
    }
    function author(address target,bytes memory creation) internal {
        require(target!=address(0)&&target.code.length==0&&target.balance==0,"custody: occupied target");
        vm.setNonce(target,1);
        vm.etch(target,creation);
        (bool ok,bytes memory runtime)=target.call("");
        require(ok&&runtime.length>0,"custody: constructor failed");
        vm.etch(target,runtime);
    }
    function safe(address target,address singleton,address[5] memory owners) internal {
        author(target,abi.encodePacked(artifact("SafeProxy"),abi.encode(singleton)));
        address[] memory list=new address[](5);
        for(uint256 i;i<5;++i)list[i]=owners[i];
        IReviewSafe(target).setup(list,3,address(0),"",address(0),address(0),0,payable(address(0)));
        require(IReviewSafe(target).getThreshold()==3&&IReviewSafe(target).nonce()==0,"custody: Safe setup");
    }
    function buildProduction(PublicConfig memory m,CustodyConfig memory c) public {
        require(m.genesisTimestamp>0,"custody: explicit timestamp");
        require(m.governance==c.protocolSafe&&m.treasury!=c.treasurySafe,"custody: role mismatch");
        require(c.protocolSafe!=c.treasurySafe,"custody: overlapping Safe");
        for(uint256 i;i<5;++i)for(uint256 j;j<5;++j){
            require(c.protocolOwners[i]!=c.treasuryOwners[j]&&c.protocolOwners[i]!=m.signers[j]&&c.treasuryOwners[i]!=m.signers[j],"custody: signer role overlap");
        }
        vm.warp(m.genesisTimestamp);vm.roll(0);vm.record();
        author(c.safeSingleton,artifact("Safe"));
        safe(c.protocolSafe,c.safeSingleton,c.protocolOwners);
        safe(c.treasurySafe,c.safeSingleton,c.treasuryOwners);
        author(m.timelock,abi.encodePacked(type(PrimeWaveCustodyTimelock).creationCode,abi.encode(c.protocolSafe)));
        author(m.treasury,abi.encodePacked(type(PrimeWaveCustodyTimelock).creationCode,abi.encode(c.treasurySafe)));
        author(c.protocolGuard,abi.encodePacked(type(TimelockOnlySafeGuard).creationCode,abi.encode(c.protocolSafe,m.timelock)));
        author(c.treasuryGuard,abi.encodePacked(type(TimelockOnlySafeGuard).creationCode,abi.encode(c.treasurySafe,m.treasury)));
        // Offline genesis initialization only; no preapproved Safe transaction
        // hashes/nonces/signatures are seeded. Constructor state owner-reviewed later.
        vm.prank(c.protocolSafe);IReviewSafe(c.protocolSafe).setGuard(c.protocolGuard);
        vm.prank(c.treasurySafe);IReviewSafe(c.treasurySafe).setGuard(c.treasuryGuard);
        require(m.timelock.codehash==keccak256(type(PrimeWaveCustodyTimelock).runtimeCode)&&m.treasury.codehash==m.timelock.codehash,"custody: runtime differs");
        author(m.emergency,abi.encodePacked(type(PauseOnlyEmergencyMultisig).creationCode,abi.encode(m.signers,[m.feeDistributor,m.feeVault,m.rewardVault],m.timelock)));
        buildCore(m);
        // Authoring-EVM only: exactly the existing C00 treasury allocation.
        vm.deal(m.treasury,15_000_000 ether);
        require(PrimeWaveCustodyTimelock(payable(m.treasury)).hasRole(bytes32(0),m.treasury),"custody: self admin mismatch");
        require(!PrimeWaveCustodyTimelock(payable(m.treasury)).hasRole(bytes32(0),address(this)),"custody: author admin leak");
    }
    function run() external override {
        string memory output=vm.envString("GENESIS_STATE_OUTPUT");
        require(!vm.exists(output),"custody: output exists");
        string memory raw=vm.readFile(vm.envString("GENESIS_PUBLIC_MANIFEST"));
        require(keccak256(bytes(vm.parseJsonString(raw,".custody.mode")))==keccak256("safe-1.4.1-oz-5.6.1"),"custody: explicit mode");
        PublicConfig memory m=readPublicConfig(raw);CustodyConfig memory c;
        c.safeSingleton=vm.parseJsonAddress(raw,".custody.safeSingleton");
        c.protocolSafe=vm.parseJsonAddress(raw,".custody.protocolSafe");
        c.treasurySafe=vm.parseJsonAddress(raw,".custody.treasurySafe");
        c.protocolGuard=vm.parseJsonAddress(raw,".custody.protocolGuard");
        c.treasuryGuard=vm.parseJsonAddress(raw,".custody.treasuryGuard");
        for(uint256 i;i<5;++i){
            c.protocolOwners[i]=vm.parseJsonAddress(raw,string.concat(".custody.protocolOwners[",vm.toString(i),"]"));
            c.treasuryOwners[i]=vm.parseJsonAddress(raw,string.concat(".custody.treasuryOwners[",vm.toString(i),"]"));
        }
        buildProduction(m,c);
        vm.writeJson(accountsJson(m,c),output);
    }

    function accountsJson(PublicConfig memory m,CustodyConfig memory c) public returns(string memory){
        address[12] memory targets=[m.timelock,m.emergency,m.feeVault,m.feeDistributor,m.registry,m.rewardVault,m.treasury,c.safeSingleton,c.protocolSafe,c.treasurySafe,c.protocolGuard,c.treasuryGuard];
        string memory out="{}";
        for(uint256 i;i<targets.length;++i)out=vm.serializeString("custody-genesis-accounts",vm.toString(targets[i]),accountJson(targets[i]));
        return out;
    }

}
