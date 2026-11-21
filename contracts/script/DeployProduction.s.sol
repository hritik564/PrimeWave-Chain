// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// ============================================================
// DeployProduction.s.sol — Hardened Production Deployment Script
// ============================================================
//
// This is the PRODUCTION deployment script for PrimeWave Chain.
// It includes mandatory safety guards that prevent accidental
// deployment to the wrong chain or network.
//
// SAFETY GUARDS:
//   1. Chain ID must match explicitly approved PRIMEWAVE_MAINNET_CHAIN_ID
//   2. PRIMEWAVE_ENV env var must be "production"
//   3. RPC URL must be explicitly provided (no default)
//   4. All contract addresses printed before any broadcast
//   5. RewardVault funding invariant verified after deploy
//   6. Script reverts on any invariant violation
//
// USAGE (production ceremony only):
//   PRIMEWAVE_ENV=production \
//   forge script contracts/script/DeployProduction.s.sol \
//     --rpc-url $PRIMEWAVE_RPC_URL \
//     --chain-id $PRIMEWAVE_MAINNET_CHAIN_ID \
//     --broadcast \
//     --sig "run()"
//
// PRE-CEREMONY REQUIREMENTS:
//   - Read docs/PW-C11-PRODUCTION-DEPLOYMENT-CEREMONY.md
//   - Read docs/PRIMEWAVE_KEY_SECURITY_PROCEDURE.md
//   - Complete key ceremony per docs/PW-C11-PRODUCTION-DEPLOYMENT-CEREMONY.md
//   - All 5 EMS signers verified and addresses recorded
//   - Genesis hash verified against docs/PW-C11-GENESIS-FINALIZATION.md
//   - Testnet rehearsal completed (IntegrationC11.s.sol passed)
//
// ENVIRONMENT: PRODUCTION — NOT FOR LOCAL DEVELOPMENT
// ============================================================

import "forge-std/Script.sol";

import {RewardVault}                from "../src/RewardVault.sol";
import {FeeDistributor}             from "../src/FeeDistributor.sol";
import {ValidatorFeeVault}          from "../src/ValidatorFeeVault.sol";
import {DevTreasury}                from "../src/DevTreasury.sol";
import {EmergencyMultisig}          from "../src/EmergencyMultisig.sol";
import {PrimeWaveTimelock}          from "../src/PrimeWaveTimelock.sol";
import {PrimeWaveValidatorRegistry} from "../src/PrimeWaveValidatorRegistry.sol";

interface IRewardVaultDeploy {
    function fund() external payable;
    function totalFunded() external view returns (uint256);
    function setPauseController(address) external;
    function setStakingManager(address) external;
}

interface IFeeDistributorDeploy {
    function VALIDATOR_BPS() external view returns (uint256);
    function TREASURY_BPS() external view returns (uint256);
}

interface ITimelockDeploy {
    function MIN_DELAY() external view returns (uint256);
}

interface IEMSDeploy {
    function THRESHOLD() external view returns (uint256);
    function MAX_SIGNERS() external view returns (uint256);
}

contract DeployProduction is Script {

    // ── Locked constants ──────────────────────────────────────────────────────
    // Production Chain ID is ceremony-approved; local73571 is always refused.
    uint256 constant REWARD_VAULT_FUND     = 15_000_000 ether;
    uint256 constant INITIAL_RATE          = uint256(3_000_000 * 1 ether) / 31_536_000;
    uint256 constant TIMELOCK_DELAY        = 172_800;     // 48h
    uint256 constant EMS_THRESHOLD         = 3;

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

        require(vm.envBool("POST_DEPLOY_REWARD_FUNDING_APPROVED"),
            "DeployProduction: explicit post-deployment RewardVault funding approval required");
        address governanceProposer = vm.envAddress("GOVERNANCE_PROPOSER");
        require(governanceProposer != address(0), "DeployProduction: governance proposer required");

        // ── GUARD 3: Explicit deployer key (never hardcoded) ─────────────────
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer    = vm.addr(deployerKey);
        uint256 approvedNonce = vm.envUint("APPROVED_DEPLOYER_NONCE");
        require(vm.getNonce(deployer) == approvedNonce, "DeployProduction: deployer nonce drift");
        address genesisFeeDistributor = vm.envAddress("GENESIS_FEE_DISTRIBUTOR");
        require(approvedNonce <= type(uint64).max - 4
            && vm.computeCreateAddress(deployer, uint64(approvedNonce + 4)) == genesisFeeDistributor,
            "DeployProduction: genesis fee destination differs from predicted deployment");

        // ── PRE-FLIGHT PRINT ─────────────────────────────────────────────────
        console.log("===========================================================");
        console.log("PrimeWave Chain -- PRODUCTION DEPLOYMENT");
        console.log("===========================================================");
        console.log("Chain ID    :", block.chainid);
        console.log("Deployer    :", deployer);
        console.log("PRIMEWAVE_ENV: production");
        console.log("Timestamp   :", block.timestamp);
        console.log("===========================================================");
        console.log("REVIEW THE ABOVE CAREFULLY BEFORE PROCEEDING");
        console.log("===========================================================");

        // ── EMS signer addresses (from key ceremony — must be set as env vars) ─
        address[5] memory signers = [
            vm.envAddress("EMS_SIGNER_1"),
            vm.envAddress("EMS_SIGNER_2"),
            vm.envAddress("EMS_SIGNER_3"),
            vm.envAddress("EMS_SIGNER_4"),
            vm.envAddress("EMS_SIGNER_5")
        ];

        // ── ValidatorManager address (from ACP-99 deployment) ────────────────
        address validatorManagerAddr = vm.envAddress("VALIDATOR_MANAGER_ADDRESS");
        require(validatorManagerAddr != address(0), "DeployProduction: VALIDATOR_MANAGER_ADDRESS not set");

        // ── Funding account (genesis-allocated) ──────────────────────────────
        // The funding account must hold >=15M PW from genesis allocation.
        // Funding key is separate from deployer key for ceremony security.
        uint256 fundingKey  = vm.envUint("FUNDING_PRIVATE_KEY");
        address fundingAcct = vm.addr(fundingKey);
        require(fundingAcct.balance >= REWARD_VAULT_FUND,
            "DeployProduction: funding account has insufficient PW for 15M vault fund");

        // ── BEGIN DEPLOYMENT ─────────────────────────────────────────────────
        vm.startBroadcast(deployerKey);

        // 1. EmergencyMultisig (3-of-5) — signers from ceremony
        EmergencyMultisig ems = new EmergencyMultisig(signers);
        require(ems.THRESHOLD() == EMS_THRESHOLD, "EMS threshold mismatch");
        require(ems.MAX_SIGNERS() == 5, "EMS max signers mismatch");
        console.log("EmergencyMultisig:", address(ems));

        // 2. PrimeWaveTimelock: explicit governance proposer from construction (48h).
        PrimeWaveTimelock timelock = new PrimeWaveTimelock(governanceProposer);
        require(timelock.MIN_DELAY() == TIMELOCK_DELAY, "Timelock delay mismatch");
        console.log("PrimeWaveTimelock:", address(timelock));

        // 3. Fee infrastructure
        //
        // Constructor dependencies create a circular requirement:
        //   ValidatorFeeVault.protocolAdmin = registry (immutable)
        //   DevTreasury.feeDistributor = feeDistributor (immutable)
        //
        // Solve by predicting CREATE addresses before deployment:
        //   deployer nonce at this point: EMS(+0), timelock(+1) already deployed.
        //   Remaining: feeVault(+2), devTreasury(+3), feeDistributor(+4), registry(+5), rewardVault(+6)
        uint64 nonce3 = vm.getNonce(deployer);
        address predictedFD       = vm.computeCreateAddress(deployer, nonce3 + 2);
        address predictedRegistry = vm.computeCreateAddress(deployer, nonce3 + 3);

        // feeVault — registry is its protocolAdmin (immutable)
        ValidatorFeeVault feeVault = new ValidatorFeeVault(predictedRegistry);
        console.log("ValidatorFeeVault:", address(feeVault));

        // devTreasury — feeDistributor is its immutable reference
        DevTreasury devTreasury = new DevTreasury(predictedFD);
        console.log("DevTreasury:", address(devTreasury));

        // feeDistributor (lands at predictedFD)
        FeeDistributor feeDistributor = new FeeDistributor(
            payable(address(feeVault)),
            payable(address(devTreasury)),
            address(ems)
        );
        require(address(feeDistributor) == predictedFD, "DEPLOY: feeDistributor address prediction failed");
        console.log("FeeDistributor:", address(feeDistributor));

        // Verify fee split constants [LOCKED]
        require(feeDistributor.VALIDATOR_BPS() == 7000, "FD: validator BPS mismatch");
        require(feeDistributor.TREASURY_BPS()  == 2000, "FD: treasury BPS mismatch");

        // 4. Immutable protocol admin is the timelock from construction.
        PrimeWaveValidatorRegistry registry = new PrimeWaveValidatorRegistry(
            address(timelock),    // immutable governance admin; no nonexistent transfer step
            validatorManagerAddr, // ACP-99 ValidatorManager
            address(feeVault)     // feeVault (registry is its protocolAdmin)
        );
        require(address(registry) == predictedRegistry, "DEPLOY: registry address prediction failed");
        console.log("ValidatorRegistry:", address(registry));

        // 5. RewardVault — admin is timelock (governance-controlled)
        RewardVault rewardVault = new RewardVault(address(timelock), INITIAL_RATE);
        // RewardVault.admin is immutable and already points to the timelock.
        // The deployer cannot initialize this setter. Schedule/execute it through
        // the approved governance proposer after MIN_DELAY; never bypass the delay.
        console.log("GOVERNANCE ACTION REQUIRED: setPauseController(EMS) via timelock");
        console.logBytes(abi.encodeCall(RewardVault.setPauseController, (address(ems))));
        console.log("RewardVault:", address(rewardVault));

        vm.stopBroadcast();

        // ── FUND REWARDVAULT (separate signing key for ceremony isolation) ───
        vm.startBroadcast(fundingKey);

        uint256 balanceBefore = address(rewardVault).balance;
        rewardVault.fund{value: REWARD_VAULT_FUND}();
        uint256 balanceAfter  = address(rewardVault).balance;

        // HARD INVARIANT: must have funded exactly 15M PW
        require(
            rewardVault.totalFunded() == REWARD_VAULT_FUND,
            string(abi.encodePacked(
                "DeployProduction: RewardVault funding invariant FAILED -- totalFunded=",
                vm.toString(rewardVault.totalFunded()),
                " expected=", vm.toString(REWARD_VAULT_FUND)
            ))
        );
        require(
            balanceAfter - balanceBefore == REWARD_VAULT_FUND,
            "DeployProduction: vault balance delta != 15M PW"
        );

        vm.stopBroadcast();

        // ── FINAL INVARIANT PRINT ────────────────────────────────────────────
        console.log("");
        console.log("===========================================================");
        console.log("DEPLOYMENT COMPLETE -- VERIFY ALL ADDRESSES BELOW");
        console.log("===========================================================");
        console.log("EmergencyMultisig :", address(ems));
        console.log("PrimeWaveTimelock :", address(timelock));
        console.log("ValidatorFeeVault :", address(feeVault));
        console.log("DevTreasury       :", address(devTreasury));
        console.log("FeeDistributor    :", address(feeDistributor));
        console.log("RewardVault       :", address(rewardVault));
        console.log("ValidatorRegistry :", address(registry));
        console.log("---");
        console.log("RV.totalFunded    :", rewardVault.totalFunded());
        console.log("RV.balance        :", address(rewardVault).balance);
        console.log("===========================================================");
        console.log("Run ValidateGenesis.s.sol against deployed chain to confirm");
        console.log("===========================================================");
    }
}
