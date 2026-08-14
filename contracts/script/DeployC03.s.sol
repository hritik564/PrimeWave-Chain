// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// ============================================================
// DeployC03.s.sol — PW-C03 Local Deployment Script
// ============================================================
//
// Deploys the PW-C03 fee routing contracts in deterministic order:
//
//   Nonce 0: ValidatorFeeVault  → 0x5FbDB2315678afecb367f032d93F642f64180aa3
//   Nonce 1: DevTreasury        → 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
//   Nonce 2: FeeDistributor     → 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0
//
// The genesis rewardManagerConfig.initialRewardConfig.rewardAddress
// MUST equal the FeeDistributor address BEFORE this script runs.
//
// ENVIRONMENT: LOCAL DEVELOPMENT ONLY
// Deployer: DEV_ACCOUNT_0 = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
// Chain ID: 73571 (primewavedev)
// ============================================================

import "forge-std/Script.sol";
import "../src/FeeDistributor.sol";
import "../src/ValidatorFeeVault.sol";
import "../src/DevTreasury.sol";

contract DeployC03 is Script {
    // ── Expected addresses (pre-computed from DEV_ACCOUNT_0 nonces 0, 1, 2) ──
    address constant EXPECTED_VAULT    = 0x5FbDB2315678afecb367f032d93F642f64180aa3;
    address constant EXPECTED_TREASURY = 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512;
    address constant EXPECTED_DIST     = 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0;

    address constant DEV0_DEPLOYER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address constant BURN_ADDRESS  = 0x000000000000000000000000000000000000dEaD;

    function run() external {
        uint256 deployerKey = vm.envUint("DEV_PRIVATE_KEY_0");

        vm.startBroadcast(deployerKey);

        // Verify nonce before deploying
        uint64 nonce = vm.getNonce(DEV0_DEPLOYER);
        require(nonce == 0, string(abi.encodePacked(
            "DeployC03: expected nonce=0, got ",
            vm.toString(nonce),
            ". Reset the chain first: bash scripts/reset-local.sh && bash scripts/start-local.sh"
        )));

        // ── Deployment order: vault, treasury, distributor ────────────────────

        // Nonce 0: ValidatorFeeVault
        // Constructor arg: FeeDistributor address (pre-computed at nonce 2)
        ValidatorFeeVault vault = new ValidatorFeeVault(EXPECTED_DIST);
        require(address(vault) == EXPECTED_VAULT,
            "DeployC03: ValidatorFeeVault address mismatch");
        console.log("ValidatorFeeVault deployed at:", address(vault));

        // Nonce 1: DevTreasury
        DevTreasury treasury = new DevTreasury(EXPECTED_DIST);
        require(address(treasury) == EXPECTED_TREASURY,
            "DeployC03: DevTreasury address mismatch");
        console.log("DevTreasury deployed at:", address(treasury));

        // Nonce 2: FeeDistributor
        FeeDistributor distributor = new FeeDistributor(
            payable(EXPECTED_VAULT),
            payable(EXPECTED_TREASURY),
            address(0) // pauseController: set via governance after deployment
        );
        require(address(distributor) == EXPECTED_DIST,
            "DeployC03: FeeDistributor address mismatch");
        console.log("FeeDistributor deployed at:", address(distributor));

        vm.stopBroadcast();

        // ── Verification ──────────────────────────────────────────────────────

        console.log("\n=== PW-C03 DEPLOYMENT COMPLETE ===");
        console.log("ValidatorFeeVault:", address(vault));
        console.log("DevTreasury:      ", address(treasury));
        console.log("FeeDistributor:   ", address(distributor));
        console.log("Burn address:     ", BURN_ADDRESS);
        console.log("");
        console.log("FeeDistributor.validatorFeeVault:", distributor.validatorFeeVault());
        console.log("FeeDistributor.treasury:         ", distributor.treasury());
        console.log("FeeDistributor.BURN_ADDRESS:     ", distributor.BURN_ADDRESS());
        console.log("FeeDistributor.VALIDATOR_BPS:    ", distributor.VALIDATOR_BPS());
        console.log("FeeDistributor.TREASURY_BPS:     ", distributor.TREASURY_BPS());
        console.log("");
        console.log("Pending distribution:", distributor.pendingDistribution(), "wei");
        console.log("(If > 0, fees accumulated before contract deployment)");
    }
}
