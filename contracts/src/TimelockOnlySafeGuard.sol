// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
interface ITimelockOnlySafeGuard {
    function checkTransaction(address,uint256,bytes calldata,uint8,uint256,uint256,uint256,address,address payable,bytes calldata,address) external view;
    function checkAfterExecution(bytes32,bool) external view;
}
/// @notice Unaudited review candidate. Safe remains the signature/custody engine.
/// Locks Safe configuration: no self-call to change owners/threshold/guard/modules.
/// A quorum can call only its paired timelock (including funding it), never
/// delegatecall. Replace the Safe via delayed timelock role migration to rotate
/// signers. No admin, setters, delegatecalls, fund transfer or upgrade path here.
contract TimelockOnlySafeGuard is ITimelockOnlySafeGuard {
    address public safe;
    address public timelock;
    constructor(address safe_,address timelock_){
        require(safe_!=address(0)&&timelock_!=address(0),"guard: zero binding");
        safe=safe_;timelock=timelock_;
    }
    function supportsInterface(bytes4 id) external pure returns(bool){
        return id==type(ITimelockOnlySafeGuard).interfaceId||id==0x01ffc9a7;
    }
    function checkTransaction(address to,uint256,bytes calldata,uint8 operation,uint256,uint256,uint256 gasPrice,address gasToken,address payable refundReceiver,bytes calldata,address) external view {
        require(gasPrice==0&&gasToken==address(0)&&refundReceiver==address(0),"guard: Safe refunds disabled");
        require(msg.sender==safe&&to==timelock&&operation==0,"guard: timelock CALL only");
    }
    function checkAfterExecution(bytes32,bool) external view {require(msg.sender==safe,"guard: Safe only");}
}
