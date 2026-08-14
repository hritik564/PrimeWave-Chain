// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// ============================================================
// DeployC04.s.sol — PW-C04 Deployment Script
// ============================================================
//
// Deployment order (deterministic CREATE addresses — sender=DEV0):
//   nonce 0 → ValidatorFeeVault   0x5FbDB2315678afecb367f032d93F642f64180aa3
//   nonce 1 → DevTreasury         0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
//   nonce 2 → FeeDistributor      0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0
//
// DevTreasury constructor requires the FeeDistributor address, which
// is deployed at nonce 2. We pre-compute it via vm.computeCreateAddress.
//
// Then (same broadcast):
//   - Register 15 PoA validators in ValidatorFeeVault
//   - Each: baseWeight=1, uptimeBips=10_000, recipient=0x1000+N
//
// Usage:
//   export DEV_PRIVATE_KEY_0="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
//   forge script contracts/script/DeployC04.s.sol \
//     --broadcast \
//     --rpc-url http://127.0.0.1:9656/ext/bc/<BLOCKCHAIN_ID>/rpc
// ============================================================

import "forge-std/Script.sol";
import "../src/ValidatorFeeVault.sol";
import "../src/DevTreasury.sol";
import "../src/FeeDistributor.sol";

contract DeployC04 is Script {

    // ── Dev validator parameters ───────────────────────────────────────────

    uint256 public constant VALIDATOR_COUNT = 15;
    uint128 public constant BASE_WEIGHT     = 1;
    uint16  public constant UPTIME_BIPS     = 10_000;

    // ── Expected deterministic addresses ──────────────────────────────────

    address constant EXPECTED_VAULT       = 0x5FbDB2315678afecb367f032d93F642f64180aa3;
    address constant EXPECTED_TREASURY    = 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512;
    address constant EXPECTED_DISTRIBUTOR = 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0;

    // ── Deploy ────────────────────────────────────────────────────────────

    function run() external {
        uint256 privKey = vm.envUint("DEV_PRIVATE_KEY_0");
        address deployer = vm.addr(privKey);

        console.log("=== PW-C04 Deployment ===");
        console.log("Deployer (DEV0):", deployer);

        // Pre-compute FeeDistributor address (nonce 2) before broadcasting.
        // DevTreasury (nonce 1) needs this address in its constructor.
        address futureDistributor = vm.computeCreateAddress(deployer, 2);
        console.log("Pre-computed FeeDistributor (nonce 2):", futureDistributor);

        vm.startBroadcast(privKey);

        // ── Nonce 0: ValidatorFeeVault ────────────────────────────────────
        ValidatorFeeVault vault = new ValidatorFeeVault(deployer);
        console.log("ValidatorFeeVault deployed:", address(vault));

        // ── Nonce 1: DevTreasury ──────────────────────────────────────────
        // Constructor requires the FeeDistributor address (pre-computed above).
        DevTreasury treasury = new DevTreasury(futureDistributor);
        console.log("DevTreasury deployed:      ", address(treasury));

        // ── Nonce 2: FeeDistributor ───────────────────────────────────────
        FeeDistributor distributor = new FeeDistributor(
            payable(address(vault)),
            payable(address(treasury))
        );
        console.log("FeeDistributor deployed:   ", address(distributor));

        // Sanity: pre-computed address must match actual address
        require(
            address(distributor) == futureDistributor,
            "DeployC04: distributor address pre-computation mismatch"
        );

        // ── Register 15 PoA validators ────────────────────────────────────
        console.log("Registering", VALIDATOR_COUNT, "dev validators...");
        for (uint256 i = 1; i <= VALIDATOR_COUNT; i++) {
            bytes32 validationId = keccak256(
                abi.encodePacked("primewavedev-validator-", i)
            );
            address recipient = address(uint160(0x1000 + i));
            vault.registerValidator(validationId, recipient, BASE_WEIGHT, UPTIME_BIPS);
            console.log("  Validator", i, "recipient:", recipient);
        }

        vm.stopBroadcast();

        // ── Verification ──────────────────────────────────────────────────
        console.log("\n=== Post-Deploy Verification ===");
        console.log("vault.protocolAdmin():         ", vault.protocolAdmin());
        console.log("vault.validatorCount():        ", vault.validatorCount());
        console.log("vault.totalEffectiveWeight():  ", vault.totalEffectiveWeight());
        console.log("distributor.validatorFeeVault():", distributor.validatorFeeVault());
        console.log("distributor.treasury():        ", distributor.treasury());

        // Address assertions (deterministic)
        require(address(vault)       == EXPECTED_VAULT,       "DeployC04: vault address mismatch");
        require(address(treasury)    == EXPECTED_TREASURY,    "DeployC04: treasury address mismatch");
        require(address(distributor) == EXPECTED_DISTRIBUTOR, "DeployC04: distributor address mismatch");
        require(vault.validatorCount()         == VALIDATOR_COUNT, "DeployC04: validator count mismatch");
        require(vault.totalEffectiveWeight()   == VALIDATOR_COUNT, "DeployC04: totalEffectiveWeight mismatch");

        console.log("\n=== C04 Deployment COMPLETE ===");
        console.log("All addresses match expected deterministic values.");
        console.log("All", VALIDATOR_COUNT, "validators registered.");
    }
}
