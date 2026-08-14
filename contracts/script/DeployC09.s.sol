// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// ============================================================
// DeployC09.s.sol  --  PW-C09 Deployment Script
// ============================================================
//
// Deploys the Phase-2 PoS staking system on the PrimeWave local devnet.
// Assumes the following contracts are already deployed (from C03–C07):
//   - RewardVault          (from genesis / C06)
//   - MockAvalancheValidatorManager OR real ValidatorManager
//
// Deployment sequence:
//   1. Deploy PrimeWaveRewardCalculator (references RewardVault)
//   2. Deploy PrimeWaveStakingManager (references MockAvalancheValidatorManager)
//   3. Initialize PrimeWaveStakingManager with settings
//   4. Register PrimeWaveStakingManager with RewardVault via setStakingManager()
//
// Usage (local devnet):
//   export REWARD_VAULT=<deployed RewardVault address>
//   export VALIDATOR_MANAGER=<deployed ValidatorManager address>
//   export ADMIN_KEY=<private key of RewardVault admin>
//   forge script contracts/script/DeployC09.s.sol \
//     --rpc-url primewavedev \
//     --broadcast \
//     -vvv
//
// ENVIRONMENT: LOCAL DEVELOPMENT ONLY
// ============================================================

import {Script, console2} from "forge-std/Script.sol";
import {RewardVault} from "../src/RewardVault.sol";
import {PrimeWaveRewardCalculator} from "../src/PrimeWaveRewardCalculator.sol";
import {PrimeWaveStakingManager} from "../src/PrimeWaveStakingManager.sol";
import {MockAvalancheValidatorManager} from "../test/MockAvalancheValidatorManager.sol";
import {StakingManagerSettings} from "validator-manager/interfaces/IStakingManager.sol";
import {IRewardCalculator} from "validator-manager/interfaces/IRewardCalculator.sol";
import {IValidatorManager} from "validator-manager/interfaces/IValidatorManager.sol";
import {PChainOwner} from "validator-manager/interfaces/IACP99Manager.sol";

contract DeployC09 is Script {

    // ── Configuration ─────────────────────────────────────────────────────────

    /// @dev Avalanche devnet blockchain ID for PrimeWave Chain.
    ///      In production, decode the base58 blockchain ID to bytes32.
    ///      For devnet/tests, using a non-zero placeholder is sufficient.
    bytes32 constant PRIMEWAVE_BLOCKCHAIN_ID = bytes32(uint256(1)); // placeholder for devnet

    /// @dev Minimum stake duration: 14 days (1,209,600 seconds).
    uint64 constant MIN_STAKE_DURATION = 14 days;

    /// @dev Maximum stake multiplier = 1 → delegation disabled (Phase 2a).
    uint8 constant MAX_STAKE_MULTIPLIER = 1;

    /// @dev Minimum delegation fee in bips (1% = 100 bips). Informational only when delegation disabled.
    uint16 constant MIN_DELEGATION_FEE_BIPS = 100;

    /// @dev 1 PW = 1e18 wei weight unit (1:1 weight-to-value).
    uint256 constant WEIGHT_TO_VALUE_FACTOR = 1 ether;

    /// @dev Minimum stake: 1,000 PW.
    uint256 constant MIN_STAKE = 1_000 ether;

    /// @dev Maximum stake: 3,000,000 PW (equals full reserve).
    uint256 constant MAX_STAKE = 3_000_000 ether;

    // ── Entry point ───────────────────────────────────────────────────────────

    function run() external {
        // Load environment
        address rewardVaultAddr    = vm.envAddress("REWARD_VAULT");
        address validatorMgrAddr   = vm.envOr("VALIDATOR_MANAGER", address(0));
        uint256 deployerKey        = vm.envUint("PRIVATE_KEY");
        address deployer           = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        // ── Step 0: Deploy MockAvalancheValidatorManager if not provided ──────
        if (validatorMgrAddr == address(0)) {
            console2.log("Deploying MockAvalancheValidatorManager...");
            MockAvalancheValidatorManager mockVM = new MockAvalancheValidatorManager(
                bytes32(uint256(42)), // devnet subnetID placeholder
                3600                  // churn period: 1 hour
            );
            validatorMgrAddr = address(mockVM);
            console2.log("  MockAvalancheValidatorManager:", validatorMgrAddr);
        } else {
            console2.log("Using existing ValidatorManager:", validatorMgrAddr);
        }

        // ── Step 1: Deploy PrimeWaveRewardCalculator ──────────────────────────
        console2.log("Deploying PrimeWaveRewardCalculator...");
        PrimeWaveRewardCalculator calc = new PrimeWaveRewardCalculator(
            RewardVault(payable(rewardVaultAddr))
        );
        console2.log("  PrimeWaveRewardCalculator:", address(calc));

        // ── Step 2: Deploy PrimeWaveStakingManager ────────────────────────────
        console2.log("Deploying PrimeWaveStakingManager...");
        PrimeWaveStakingManager sm = new PrimeWaveStakingManager();
        console2.log("  PrimeWaveStakingManager:", address(sm));

        // ── Step 3: Initialize PrimeWaveStakingManager ────────────────────────
        console2.log("Initializing PrimeWaveStakingManager...");
        sm.initialize(
            StakingManagerSettings({
                manager:                  IValidatorManager(validatorMgrAddr),
                minimumStakeAmount:       MIN_STAKE,
                maximumStakeAmount:       MAX_STAKE,
                minimumStakeDuration:     MIN_STAKE_DURATION,
                minimumDelegationFeeBips: MIN_DELEGATION_FEE_BIPS,
                maximumStakeMultiplier:   MAX_STAKE_MULTIPLIER,
                weightToValueFactor:      WEIGHT_TO_VALUE_FACTOR,
                rewardCalculator:         IRewardCalculator(address(calc)),
                uptimeBlockchainID:       PRIMEWAVE_BLOCKCHAIN_ID
            }),
            RewardVault(payable(rewardVaultAddr))
        );
        console2.log("  initialized with:");
        console2.log("    minimumStakeDuration (days):", uint256(MIN_STAKE_DURATION) / 1 days);
        console2.log("    maximumStakeMultiplier:", MAX_STAKE_MULTIPLIER, "(delegation disabled)");
        console2.log("    uptimeBlockchainID:", uint256(PRIMEWAVE_BLOCKCHAIN_ID));

        // ── Step 4: Register staking manager with RewardVault ─────────────────
        console2.log("Registering PrimeWaveStakingManager with RewardVault...");
        RewardVault(payable(rewardVaultAddr)).setStakingManager(address(sm));
        console2.log("  setStakingManager() done");

        vm.stopBroadcast();

        // ── Summary ───────────────────────────────────────────────────────────
        console2.log("");
        console2.log("===== C09 DEPLOYMENT COMPLETE =====");
        console2.log("RewardVault:                   ", rewardVaultAddr);
        console2.log("ValidatorManager:              ", validatorMgrAddr);
        console2.log("PrimeWaveRewardCalculator:     ", address(calc));
        console2.log("PrimeWaveStakingManager:       ", address(sm));
        console2.log("Deployer:                      ", deployer);
        console2.log("====================================");
    }
}
