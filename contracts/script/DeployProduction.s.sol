// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Legacy production deployment entry point is deliberately disabled.
// C00 seeds RewardVault at genesis using reviewed constructor-executed state;
// post-deployment15M funding would contradict or double-count that allocation.
// GenesisConstructorState.s.sol is an OFFLINE candidate compiler, not a launcher.
// Existing environment/chain guards remain before the unconditional refusal.
// No signing material is read and this entry point cannot broadcast.

import "forge-std/Script.sol";

contract DeployProduction is Script {

    function run() external {
        // ── GUARD 1: Environment flag ────────────────────────────────────────
        string memory env = vm.envOr("PRIMEWAVE_ENV", string(""));
        require(
            keccak256(bytes(env)) == keccak256(bytes("production")),
            "DeployProduction: PRIMEWAVE_ENV must be 'production' -- set env var before running"
        );

        // Reject local/testnet IDs before accessing any signing material.
        uint256 expectedChainId = vm.envUint("PRIMEWAVE_MAINNET_CHAIN_ID");
        require(vm.envBool("PRIMEWAVE_MAINNET_CHAIN_ID_APPROVED"), "DeployProduction: Chain ID approval required");
        require(expectedChainId >= 1000 && expectedChainId <= 9007199254740991
            && expectedChainId != 73571 && expectedChainId != 43113 && expectedChainId != 43114
            && expectedChainId != 31337 && expectedChainId != 1337,
            "DeployProduction: local/testnet/reserved Chain ID forbidden");
        require(block.chainid == expectedChainId, "DeployProduction: wrong chain ID");

        // C00 requires the vault's15M to exist at genesis. Never fund a second
        // vault, read signer keys or broadcast after constructor predeployment.
        revert("DeployProduction: legacy post-deploy funding disabled; review C00 genesis predeploy");
    }
}
