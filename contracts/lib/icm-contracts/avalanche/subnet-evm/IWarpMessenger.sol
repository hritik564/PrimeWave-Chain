// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

struct WarpMessage {
    bytes32 sourceChainID;
    address originSenderAddress;
    bytes payload;
}

struct WarpBlockHash {
    bytes32 sourceChainID;
    bytes32 blockHash;
}

interface IWarpMessenger {
    event SendWarpMessage(address indexed sender, bytes32 indexed messageID, bytes message);

    // sendWarpMessage emits a request for the subnet to send a warp message from [msg.sender]
    // with the specified parameters.
    // This emits a SendWarpMessage log from the precompile. When the corresponding block is accepted
    // the Accept hook of the Warp precompile is invoked with all accepted logs emitted by the Warp
    // precompile.
    // Each validator then adds the UnsignedWarpMessage encoded in the log to the set of messages
    // it is willing to sign for an off-chain relayer to aggregate Warp signatures.
    function sendWarpMessage(
        bytes calldata payload
    ) external returns (bytes32 messageID);

    // getVerifiedWarpMessage parses the pre-verified warp message in the
    // predicate storage slots as a WarpMessage and returns it to the caller.
    // If the message exists and passes verification, returns the verified message
    // and true.
    // Otherwise, returns false and the empty value for the message.
    // NOTE: The actual precompile returns calldata; this local copy uses memory
    // to allow Foundry mock contracts to implement this interface in tests.
    function getVerifiedWarpMessage(
        uint32 index
    ) external view returns (WarpMessage memory message, bool valid);

    // getVerifiedWarpBlockHash parses the pre-verified WarpBlockHash message in the
    // predicate storage slots as a WarpBlockHash message and returns it to the caller.
    // If the message exists and passes verification, returns the verified message
    // and true.
    // Otherwise, returns false and the empty value for the message.
    function getVerifiedWarpBlockHash(
        uint32 index
    ) external view returns (WarpBlockHash memory warpBlockHash, bool valid);

    // getBlockchainID returns the snow.Context BlockchainID of this chain.
    // This blockchainID is the hash of the transaction that created this blockchain on the P-Chain
    // and is not related to the Ethereum ChainID.
    function getBlockchainID() external view returns (bytes32 blockchainID);
}
