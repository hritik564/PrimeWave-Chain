// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {EmergencyMultisig} from "./EmergencyMultisig.sol";

/// @notice Review candidate. Existing3-of-5 accounting plus a fixed target/selector
/// boundary. Custody, upgrades and role grants are never emergency powers.
/// Rotation is a separate timelock-only path, not an emergency-vote escape hatch.
contract PauseOnlyEmergencyMultisig is EmergencyMultisig {
    address public governanceTimelock;
    mapping(address=>bool) public allowedTarget;
    constructor(address[5] memory signers_,address[3] memory targets,address governance)
        EmergencyMultisig(signers_) {
        require(governance!=address(0),"emergency: zero governance");
        governanceTimelock=governance;
        for(uint256 i;i<targets.length;++i){
            require(targets[i]!=address(0)&&!allowedTarget[targets[i]],"emergency: invalid target");
            allowedTarget[targets[i]]=true;
        }
    }
    function execute(address target,bytes calldata data,uint256 nonce_) public override {
        require(allowedTarget[target],"emergency: target forbidden");
        require(data.length==4,"emergency: calldata forbidden");
        bytes4 selector=bytes4(data[:4]);
        require(selector==bytes4(keccak256("pause()"))||selector==bytes4(keccak256("unpause()")),"emergency: selector forbidden");
        super.execute(target,data,nonce_);
    }
    function rotatePauseController(address target,address next) external {
        require(msg.sender==governanceTimelock,"emergency: timelock only");
        require(allowedTarget[target]&&next.code.length>0,"emergency: invalid rotation");
        (bool ok,bytes memory reason)=target.call(abi.encodeWithSignature("setPauseController(address)",next));
        if(!ok){assembly{revert(add(reason,32),mload(reason))}}
    }
}
