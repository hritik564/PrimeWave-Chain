// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import {DeployProduction} from "../script/DeployProduction.s.sol";

/// @dev setEnv mutates process-global state, so run guard cases sequentially.
/// Every case reverts before signing-key reads or broadcast cheatcodes.
contract ProductionDeploymentGuardsTest is Test {
    function testAllGuardFailuresBeforeKeyAccess() public {
        DeployProduction script = new DeployProduction();
        vm.setEnv("PRIMEWAVE_ENV", "production");
        vm.setEnv("PRIMEWAVE_MAINNET_CHAIN_ID", "73571");
        vm.setEnv("PRIMEWAVE_MAINNET_CHAIN_ID_APPROVED", "true");
        vm.chainId(73571);
        vm.expectRevert("DeployProduction: local/testnet/reserved Chain ID forbidden");
        script.run();

        vm.setEnv("PRIMEWAVE_MAINNET_CHAIN_ID", "73571001");
        vm.setEnv("PRIMEWAVE_MAINNET_CHAIN_ID_APPROVED", "false");
        vm.chainId(73571001);
        vm.expectRevert("DeployProduction: Chain ID approval required");
        script.run();

        vm.setEnv("PRIMEWAVE_MAINNET_CHAIN_ID_APPROVED", "true");
        vm.chainId(77);
        vm.expectRevert("DeployProduction: wrong chain ID");
        script.run();

        vm.chainId(73571001);
        vm.setEnv("POST_DEPLOY_REWARD_FUNDING_APPROVED", "false");
        vm.expectRevert("DeployProduction: explicit post-deployment RewardVault funding approval required");
        script.run();

        vm.setEnv("PRIMEWAVE_ENV", "development");
        vm.expectRevert("DeployProduction: PRIMEWAVE_ENV must be 'production' -- set env var before running");
        script.run();
    }
}
