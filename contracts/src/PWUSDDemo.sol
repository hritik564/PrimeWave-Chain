// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Demonstration token only. No USD backing or redemption rights.
/// @dev Fixed supply, no admin, no external mint, local PrimeWave chain only.
contract PWUSDDemo is ERC20 {
    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 10 ** 18;

    constructor(address recipient) ERC20("PWUSD Demo (Unbacked)", "PWUSD") {
        require(block.chainid == 73571, "PWUSD: local PrimeWave only");
        _mint(recipient, INITIAL_SUPPLY);
    }
}
