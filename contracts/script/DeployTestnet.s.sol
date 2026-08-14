// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// ============================================================
// DeployTestnet.s.sol - PrimeWave Testnet Deployment Script
// ============================================================
//
// TESTNET ONLY - Chain ID 77.
// Deploys all 7 protocol contracts to the PrimeWave testnet and funds
// RewardVault with exactly 15M PW.
//
// Differences from DevDeploy.s.sol:
//   1. Enforces chain ID == 77 (refuses to run on dev or mainnet)
//   2. Refuses to run with the public dev mnemonic (account 0 = 0xf39F...)
//   3. Funds RewardVault with 15M PW (not 1000 PW as in dev)
//   4. EMS signer addresses must be set to real testnet keys before running
//   5. Writes addresses to local-data/testnet-deployed-contracts.env
//
// Usage:
//   TESTNET_RPC_URL=... TESTNET_DEPLOYER_KEY=0x... \
//   forge script contracts/script/DeployTestnet.s.sol:DeployTestnet \
//     --rpc-url $TESTNET_RPC_URL \
//     --private-key $TESTNET_DEPLOYER_KEY \
//     --broadcast --via-ir -vvv
//
// ENVIRONMENT: TESTNET ONLY - NEVER RUN ON MAINNET
// ============================================================

import "forge-std/Script.sol";

import {EmergencyMultisig}           from "../src/EmergencyMultisig.sol";
import {PrimeWaveTimelock}           from "../src/PrimeWaveTimelock.sol";
import {FeeDistributor}              from "../src/FeeDistributor.sol";
import {ValidatorFeeVault}           from "../src/ValidatorFeeVault.sol";
import {DevTreasury}                 from "../src/DevTreasury.sol";
import {RewardVault}                 from "../src/RewardVault.sol";
import {PrimeWaveValidatorRegistry}  from "../src/PrimeWaveValidatorRegistry.sol";

contract DeployTestnet is Script {
    // ── Constants ─────────────────────────────────────────────────────────────

    uint256 constant TESTNET_CHAIN_ID  = 77;
    uint256 constant REWARD_VAULT_FUND = 15_000_000 ether; // 15M PW

    // 3,000,000 PW/year expressed as wei/second (matches dev rate)
    uint256 constant INITIAL_RATE = uint256(3_000_000 * 1 ether) / 31_536_000;

    // Dev mnemonic account 0 - refuse to deploy if this is the deployer
    address constant DEV_KEY_ADDR = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    // ── EMS Testnet Signers (REPLACE before running) ─────────────────────────
    // Generate with: scripts/testnet/generate-validator-keys.sh
    // These are placeholder zero addresses - MUST be replaced before deployment.
    address constant EMS_SIGNER_1 = address(0); // REPLACE with testnet-ems-signer-1 address
    address constant EMS_SIGNER_2 = address(0); // REPLACE with testnet-ems-signer-2 address
    address constant EMS_SIGNER_3 = address(0); // REPLACE with testnet-ems-signer-3 address
    address constant EMS_SIGNER_4 = address(0); // REPLACE with testnet-ems-signer-4 address
    address constant EMS_SIGNER_5 = address(0); // REPLACE with testnet-ems-signer-5 address

    // ── Run ───────────────────────────────────────────────────────────────────

    function run() external {
        // Hard guard: refuse to run on wrong network
        require(
            block.chainid == TESTNET_CHAIN_ID,
            "DeployTestnet: WRONG CHAIN ID - expected 77 (testnet)"
        );

        address deployer = msg.sender;

        // Hard guard: refuse dev key
        require(
            deployer != DEV_KEY_ADDR,
            "DeployTestnet: REFUSED - dev mnemonic key detected. Use a testnet key."
        );

        // Validate EMS signers are set (will be caught below by EMS constructor)
        require(
            EMS_SIGNER_1 != address(0) &&
            EMS_SIGNER_2 != address(0) &&
            EMS_SIGNER_3 != address(0) &&
            EMS_SIGNER_4 != address(0) &&
            EMS_SIGNER_5 != address(0),
            "DeployTestnet: EMS signer addresses are zero - fill in before deployment"
        );

        uint256 balance = deployer.balance;

        console2.log("==== PrimeWave Testnet Deployment ====");
        console2.log("TESTNET ONLY");
        console2.log("Chain ID  :", block.chainid);
        console2.log("Deployer  :", deployer);
        console2.log("Balance   :", balance / 1 ether, "PW");

        require(balance >= REWARD_VAULT_FUND + 1 ether, "DeployTestnet: Insufficient balance (need >= 15,001 PW)");

        vm.startBroadcast();

        // ── 1. EmergencyMultisig (3-of-5, testnet ceremony signers) ──────────
        address[5] memory emsSigners = [EMS_SIGNER_1, EMS_SIGNER_2, EMS_SIGNER_3, EMS_SIGNER_4, EMS_SIGNER_5];
        EmergencyMultisig ems = new EmergencyMultisig(emsSigners);
        console2.log("EmergencyMultisig :", address(ems));

        // ── 2. PrimeWaveTimelock (deployer as proposer for initial testnet setup) ──
        PrimeWaveTimelock timelock = new PrimeWaveTimelock(deployer);
        console2.log("PrimeWaveTimelock :", address(timelock));

        // ── 3. Fee infrastructure (same address-prediction pattern as DevDeploy) ──
        // Remaining after EMS(nonce0) + Timelock(nonce1) deployed:
        // feeVault(+0), devTreasury(+1), feeDistributor(+2), registry(+3), rewardVault(+4)
        uint64 nonce3 = vm.getNonce(deployer);
        address predictedFD       = vm.computeCreateAddress(deployer, nonce3 + 2);
        address predictedRegistry = vm.computeCreateAddress(deployer, nonce3 + 3);

        ValidatorFeeVault feeVault = new ValidatorFeeVault(predictedRegistry);
        console2.log("ValidatorFeeVault :", address(feeVault));

        DevTreasury devTreasury = new DevTreasury(predictedFD);
        console2.log("DevTreasury       :", address(devTreasury));

        FeeDistributor feeDist = new FeeDistributor(
            payable(address(feeVault)),
            payable(address(devTreasury)),
            address(ems)
        );
        require(address(feeDist) == predictedFD, "DeployTestnet: FeeDistributor address prediction mismatch");
        console2.log("FeeDistributor    :", address(feeDist));

        // ── 4. ValidatorRegistry ─────────────────────────────────────────────
        //   protocolAdmin    = deployer (transferred to timelock post-setup)
        //   validatorManager = deployer placeholder (PoAManager not deployed here;
        //                      see PoAManager deployment for production ACP-99 setup)
        //   feeVault         = deployed feeVault (registry is feeVault's protocolAdmin)
        PrimeWaveValidatorRegistry registry = new PrimeWaveValidatorRegistry(
            deployer,
            deployer,          // placeholder ValidatorManager; replaced after PoAManager deploy
            address(feeVault)
        );
        require(address(registry) == predictedRegistry, "DeployTestnet: registry address prediction mismatch");
        console2.log("ValidatorRegistry :", address(registry));

        // ── 5. RewardVault (deployer as admin, EMS as pause controller) ───────
        RewardVault rewardVault = new RewardVault(deployer, INITIAL_RATE);
        rewardVault.setPauseController(address(ems));
        console2.log("RewardVault       :", address(rewardVault));

        // ── 6. Fund RewardVault with exactly 15M PW ──────────────────────────
        rewardVault.fund{value: REWARD_VAULT_FUND}();
        require(
            rewardVault.totalFunded() == REWARD_VAULT_FUND,
            "DeployTestnet: CRITICAL - RewardVault funding invariant FAILED"
        );
        console2.log("RewardVault funded:", REWARD_VAULT_FUND / 1 ether, "PW");

        vm.stopBroadcast();

        // ── Write addresses to env file ───────────────────────────────────────
        string memory envContent = string.concat(
            "# Auto-generated by contracts/script/DeployTestnet.s.sol\n",
            "# TESTNET ONLY - Chain ID: ", vm.toString(block.chainid), "\n\n",
            "ADDR_EMERGENCY_MULTISIG=",  vm.toString(address(ems)),         "\n",
            "ADDR_TIMELOCK=",            vm.toString(address(timelock)),     "\n",
            "ADDR_VALIDATOR_FEE_VAULT=", vm.toString(address(feeVault)),    "\n",
            "ADDR_DEV_TREASURY=",        vm.toString(address(devTreasury)), "\n",
            "ADDR_FEE_DISTRIBUTOR=",     vm.toString(address(feeDist)),      "\n",
            "ADDR_REWARD_VAULT=",        vm.toString(address(rewardVault)), "\n",
            "ADDR_VALIDATOR_REGISTRY=",  vm.toString(address(registry)),     "\n"
        );
        vm.writeFile("local-data/testnet-deployed-contracts.env", envContent);

        console2.log("===================================================");
        console2.log("DeployTestnet COMPLETE");
        console2.log("===================================================");
        console2.log("Addresses written to: local-data/testnet-deployed-contracts.env");
        console2.log("NEXT: Run scripts/testnet/validate-testnet-genesis.sh");
    }
}
