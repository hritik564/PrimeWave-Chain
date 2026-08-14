// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// ============================================================
// MockWarpMessenger  --  PW-C09  DEV/TEST ONLY
// ============================================================
//
// Mock implementation of the Avalanche Warp precompile interface.
// Deployed to address 0x0200000000000000000000000000000000000005 in tests
// via vm.etch() to intercept WARP_MESSENGER calls from StakingManager._updateUptime().
//
// Tests configure uptime responses via setUptimeResponse() before calling
// submitUptimeProof() or initiateValidatorRemoval(includeUptimeProof=true).
//
// ENVIRONMENT: TEST / LOCAL DEV — MUST NOT BE USED IN PRODUCTION
// ============================================================

import {IWarpMessenger, WarpMessage, WarpBlockHash} from "@subnet-evm/IWarpMessenger.sol";
import {ValidatorMessages} from "validator-manager/ValidatorMessages.sol";

contract MockWarpMessenger is IWarpMessenger {

    // ── State ────────────────────────────────────────────────────────────────

    /// @dev Pre-configured Warp messages returned by getVerifiedWarpMessage(index).
    mapping(uint32 => WarpMessage) private _messages;

    /// @dev Whether the message at a given index is valid (true) or invalid (false).
    mapping(uint32 => bool) private _valid;

    /// @dev The blockchain ID returned by getBlockchainID().
    bytes32 public blockchainIDValue;

    // ── Test configuration helpers ────────────────────────────────────────────

    /// @notice Configure an uptime response for a specific Warp message index.
    ///
    /// @param messageIndex    The index passed to getVerifiedWarpMessage().
    /// @param sourceChainID   Must match PrimeWaveStakingManager._uptimeBlockchainID.
    /// @param validationID    The validator's validationID.
    /// @param uptimeSeconds   Uptime in seconds (packed into the payload).
    function setUptimeResponse(
        uint32  messageIndex,
        bytes32 sourceChainID,
        bytes32 validationID,
        uint64  uptimeSeconds
    ) external {
        bytes memory payload = ValidatorMessages.packValidationUptimeMessage(validationID, uptimeSeconds);
        _messages[messageIndex] = WarpMessage({
            sourceChainID:       sourceChainID,
            originSenderAddress: address(0), // must be 0 for valid uptime proof
            payload:             payload
        });
        _valid[messageIndex] = true;
    }

    /// @notice Configure a raw WarpMessage at a given index.
    function setRawResponse(uint32 messageIndex, WarpMessage memory msg_, bool valid) external {
        _messages[messageIndex] = msg_;
        _valid[messageIndex]    = valid;
    }

    /// @notice Set the blockchain ID returned by getBlockchainID().
    function setBlockchainID(bytes32 id) external {
        blockchainIDValue = id;
    }

    // ── IWarpMessenger ────────────────────────────────────────────────────────

    function sendWarpMessage(bytes calldata payload) external override returns (bytes32 messageID) {
        messageID = keccak256(abi.encode(block.timestamp, msg.sender, payload));
        emit SendWarpMessage(msg.sender, messageID, payload);
    }

    function getVerifiedWarpMessage(uint32 index)
        external
        view
        override
        returns (WarpMessage memory message, bool valid)
    {
        message = _messages[index];
        valid   = _valid[index];
    }

    function getVerifiedWarpBlockHash(uint32)
        external
        pure
        override
        returns (WarpBlockHash memory, bool)
    {
        // Not used by StakingManager — return empty/false
        revert("MockWarp: blockHash not mocked");
    }

    function getBlockchainID() external view override returns (bytes32) {
        return blockchainIDValue;
    }
}
