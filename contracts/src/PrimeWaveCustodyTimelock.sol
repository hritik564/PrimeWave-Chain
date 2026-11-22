// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @notice Review candidate: OZ5.6.1 custody/roles/value execution unchanged.
/// The only policy extension prevents governance reducing C00's48h minimum.
/// No external admin; the supplied multisig is proposer/canceller/executor.
/// Not externally audited or approved for production.
contract PrimeWaveCustodyTimelock is TimelockController {
    uint256 public constant DELAY_FLOOR = 48 hours;
    constructor(address multisig) TimelockController(DELAY_FLOOR, _one(multisig), _one(multisig), address(0)) {}
    function _one(address who) private pure returns(address[] memory list) {
        require(who != address(0), "custody: zero multisig");
        list=new address[](1);list[0]=who;
    }
    function updateDelay(uint256 delay) public override {
        require(delay>=DELAY_FLOOR,"custody: below48h");
        super.updateDelay(delay);
    }
}
