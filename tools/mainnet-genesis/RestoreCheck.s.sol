// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {Script} from "../../contracts/lib/forge-std/src/Script.sol";
/// Full recorded-state restoration in a blank authoring EVM; no node/key/tx.
contract RestoreCheck is Script {
    function run() external {
        string memory raw=vm.readFile(vm.envString("MAINNET_EXACT_GENESIS"));
        string memory expected=vm.readFile(vm.envString("MAINNET_EXACT_EXPECTATIONS"));
        require(sha256(bytes(raw))==vm.parseBytes32(string.concat("0x",vm.parseJsonString(expected,".genesisFileSha256"))),"genesis bytes changed");
        string[] memory accounts=vm.parseJsonKeys(raw,".alloc");uint256 supply;
        for(uint256 i;i<accounts.length;++i){
            address target=vm.parseAddress(accounts[i]);require(target.code.length==0&&vm.getNonce(target)==0&&target.balance==0,"nonempty target");
            string memory root=string.concat(".alloc.",accounts[i]);uint256 balance=vm.parseJsonUint(raw,string.concat(root,".balance"));supply+=balance;vm.deal(target,balance);
            if(vm.keyExistsJson(raw,string.concat(root,".code")))vm.etch(target,vm.parseJsonBytes(raw,string.concat(root,".code")));
            if(vm.keyExistsJson(raw,string.concat(root,".nonce"))){uint256 nonce=vm.parseJsonUint(raw,string.concat(root,".nonce"));require(nonce<=type(uint64).max,"nonce overflow");vm.setNonce(target,uint64(nonce));}
            if(vm.keyExistsJson(raw,string.concat(root,".storage"))){string[] memory slots=vm.parseJsonKeys(raw,string.concat(root,".storage"));for(uint256 j;j<slots.length;++j){bytes32 slot=vm.parseBytes32(slots[j]);bytes32 value=vm.parseJsonBytes32(raw,string.concat(root,".storage.",slots[j]));vm.store(target,slot,value);require(vm.load(target,slot)==value,"storage restore");}}
        }
        require(supply==100_000_000 ether,"supply changed");
        uint256 count=vm.parseJsonUint(expected,".callCount");
        for(uint256 i;i<count;++i){string memory root=string.concat(".calls[",vm.toString(i),"]");address to=vm.parseJsonAddress(expected,string.concat(root,".to"));(bool ok,bytes memory result)=to.staticcall(vm.parseJsonBytes(expected,string.concat(root,".data")));require(ok&&keccak256(result)==keccak256(vm.parseJsonBytes(expected,string.concat(root,".expected"))),"ownership/state mismatch");}
    }
}
