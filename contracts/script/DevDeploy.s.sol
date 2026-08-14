// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// ============================================================
// DevDeploy.s.sol — Local Development Deployment Script
// ============================================================
//
// Deploys all PrimeWave protocol contracts to the LOCAL devnet (chain ID 73571).
// NOT FOR PRODUCTION. Uses dev private key as admin for all contracts.
//
// Differences from DeployProduction.s.sol:
//   - Runs on chain ID 73571 (production script refuses this chain)
//   - Deployer acts as all admin roles (no hardware wallets)
//   - EMS signers are standard Foundry test accounts 1-5
//   - RewardVault funded with 1,000 PW (not 15M — dev accounts only have 10,000 PW)
//   - Placeholder ValidatorManager (no real ACP-99 required for indexer demo)
//   - Contract addresses written to local-data/deployed-contracts.env for indexer startup
//
// Usage (called automatically by scripts/start-indexer.sh):
//   export DEV_PRIVATE_KEY_0=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
//   forge script contracts/script/DevDeploy.s.sol \
//     --rpc-url http://127.0.0.1:9656/ext/bc/<BLOCKCHAIN_ID>/rpc \
//     --broadcast
//
// ENVIRONMENT: LOCAL DEVELOPMENT ONLY — NOT FOR TESTNET OR MAINNET
// ============================================================

import "forge-std/Script.sol";

import {EmergencyMultisig}          from "../src/EmergencyMultisig.sol";
import {PrimeWaveTimelock}          from "../src/PrimeWaveTimelock.sol";
import {ValidatorFeeVault}          from "../src/ValidatorFeeVault.sol";
import {DevTreasury}                from "../src/DevTreasury.sol";
import {FeeDistributor}             from "../src/FeeDistributor.sol";
import {RewardVault}                from "../src/RewardVault.sol";
import {PrimeWaveValidatorRegistry} from "../src/PrimeWaveValidatorRegistry.sol";

contract DevDeploy is Script {

    // ── Constants ─────────────────────────────────────────────────────────────

    /// @dev Fund 1,000 PW — well within the 10,000 PW genesis allocation.
    uint256 constant DEV_REWARD_VAULT_FUND = 1_000 ether;

    /// @dev 3,000,000 PW/year → per-second rate.
    uint256 constant INITIAL_RATE = uint256(3_000_000 * 1 ether) / 31_536_000;

    function run() external {
        uint256 deployerKey = vm.envUint("DEV_PRIVATE_KEY_0");
        address deployer    = vm.addr(deployerKey);

        console.log("==== PrimeWave DevDeploy ====");
        console.log("Chain ID  :", block.chainid);
        console.log("Deployer  :", deployer);
        console.log("Balance   :", deployer.balance / 1 ether, "PW");

        // ── 5 EMS signers — standard Foundry test keys 1-5 (all distinct) ────
        // Key 0 = deployer; keys 1-5 are other pre-funded dev accounts.
        address[5] memory signers = [
            vm.addr(0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d),
            vm.addr(0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a),
            vm.addr(0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6),
            vm.addr(0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926b),
            vm.addr(0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba)
        ];

        vm.startBroadcast(deployerKey);

        // ── 1. EmergencyMultisig (3-of-5, dev signers) ───────────────────────
        EmergencyMultisig ems = new EmergencyMultisig(signers);

        // ── 2. PrimeWaveTimelock (deployer as proposer for dev) ───────────────
        PrimeWaveTimelock timelock = new PrimeWaveTimelock(deployer);

        // ── 3. Fee infrastructure ─────────────────────────────────────────────
        //
        // Constructor circular dependency:
        //   ValidatorFeeVault.protocolAdmin = registry (immutable)
        //   DevTreasury.feeDistributor = feeDistributor (immutable)
        //
        // Solved by pre-computing CREATE addresses before deployment.
        // At this point: EMS(nonce0) + Timelock(nonce1) already deployed → nonce=2.
        // Remaining: feeVault(+0), devTreasury(+1), feeDistributor(+2), registry(+3), rewardVault(+4)
        uint64 nonce3 = vm.getNonce(deployer);
        address predictedFD       = vm.computeCreateAddress(deployer, nonce3 + 2);
        address predictedRegistry = vm.computeCreateAddress(deployer, nonce3 + 3);

        ValidatorFeeVault feeVault = new ValidatorFeeVault(predictedRegistry);
        DevTreasury devTreasury    = new DevTreasury(predictedFD);
        FeeDistributor feeDist     = new FeeDistributor(
            payable(address(feeVault)),
            payable(address(devTreasury)),
            address(ems)
        );
        require(address(feeDist) == predictedFD, "DevDeploy: feeDistributor address prediction mismatch");

        // ── 4. ValidatorRegistry ─────────────────────────────────────────────
        //   protocolAdmin = deployer (for dev — production uses timelock)
        //   validatorManager = deployer address as placeholder (no real ACP-99 on local devnet)
        //   feeVault = the deployed feeVault (registry is its protocolAdmin per address prediction)
        PrimeWaveValidatorRegistry registry = new PrimeWaveValidatorRegistry(
            deployer,
            deployer,          // placeholder ValidatorManager (no real staking on local devnet)
            address(feeVault)
        );
        require(address(registry) == predictedRegistry, "DevDeploy: registry address prediction mismatch");

        // ── 5. RewardVault (deployer as admin; EMS as pause controller) ───────
        RewardVault rewardVault = new RewardVault(deployer, INITIAL_RATE);
        rewardVault.setPauseController(address(ems));
        rewardVault.fund{value: DEV_REWARD_VAULT_FUND}();

        vm.stopBroadcast();

        // ── Print deployment summary ──────────────────────────────────────────
        console.log("===========================================================");
        console.log("DevDeploy COMPLETE");
        console.log("===========================================================");
        console.log("EmergencyMultisig :", address(ems));
        console.log("PrimeWaveTimelock :", address(timelock));
        console.log("ValidatorFeeVault :", address(feeVault));
        console.log("DevTreasury       :", address(devTreasury));
        console.log("FeeDistributor    :", address(feeDist));
        console.log("RewardVault       :", address(rewardVault));
        console.log("ValidatorRegistry :", address(registry));
        console.log("===========================================================");

        // ── Write env file for indexer startup ────────────────────────────────
        string memory envContent = string.concat(
            "# Auto-generated by contracts/script/DevDeploy.s.sol\n",
            "# Do NOT edit manually - delete and re-run DevDeploy to regenerate.\n",
            "# Generated for chain ID: ", vm.toString(block.chainid), "\n\n",
            "ADDR_EMERGENCY_MULTISIG=",  vm.toString(address(ems)),        "\n",
            "ADDR_TIMELOCK=",            vm.toString(address(timelock)),    "\n",
            "ADDR_VALIDATOR_FEE_VAULT=", vm.toString(address(feeVault)),   "\n",
            "ADDR_DEV_TREASURY=",        vm.toString(address(devTreasury)), "\n",
            "ADDR_FEE_DISTRIBUTOR=",     vm.toString(address(feeDist)),     "\n",
            "ADDR_REWARD_VAULT=",        vm.toString(address(rewardVault)), "\n",
            "ADDR_VALIDATOR_REGISTRY=",  vm.toString(address(registry)),    "\n"
        );
        vm.writeFile("local-data/deployed-contracts.env", envContent);
        console.log("Addresses written to local-data/deployed-contracts.env");
    }
}
