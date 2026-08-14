// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// ============================================================
// IntegrationC05.s.sol — PW-C05 Live Chain Integration Test
// ============================================================
//
// Tests on the running primewavedev L1 chain (Chain ID 73571):
//
//   1. Deploy MockValidatorManager (dev-only — no Warp required)
//   2. Pre-compute registry address
//   3. Deploy ValidatorFeeVault with registry as protocolAdmin
//   4. Deploy PrimeWaveValidatorRegistry
//   5. Register 15 validators via MockValidatorManager + registry
//      - Validators 1-5: PendingAdded to registered inactive
//      - Validators 6-15: Active to registered active
//   6. Activate validators 1-5 (simulate P-Chain Warp confirmation)
//   7. syncAll() to all 15 now active in feeVault
//   8. Send 15 PW directly to vault (simulating FeeDistributor.distribute())
//   9. Assert each validator has 1 PW claimable
//  10. Initiate removal of validator-1 (DEV0 is recipient for claim)
//  11. syncValidator() deactivates validator-1 in feeVault
//  12. Assert validator-1 still has 1 PW claimable (not confiscated)
//  13. Claim 1 PW as DEV0 (validator-1 recipient)
//  14. Send 14 more PW (validators 2-15 earn, validator-1 earns 0)
//  15. Assert conservation: balance == totalReceived - totalClaimed
//  16. Weight update: change validator-2 weight to 3 via MockVM
//  17. updateWeight() syncs to feeVault; historical fees preserved
//  18. Assert C04 INV-1 still holds
//  19. Mock re-registration: re-activate validator-1 (force status)
//  20. syncValidator to validator-1 active again
//  21. Assert no retro-accrual during inactive period
//
// Note: In production, steps 5-6 are driven by the real PoAManager
// + P-Chain Warp round-trips via an ICM relayer. The MockValidatorManager
// simulates this without Warp for local dev integration testing.
// ============================================================

import "forge-std/Script.sol";
import "../src/PrimeWaveValidatorRegistry.sol";
import "../src/ValidatorFeeVault.sol";
import "../test/MockValidatorManager.sol";

contract IntegrationC05 is Script {

    uint256 constant VALIDATOR_COUNT = 15;
    address constant DEV0 = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    bytes32 constant SUBNET_ID = keccak256("primewavedev-subnet");

    function run() external {
        uint256 privKey = vm.envUint("DEV_PRIVATE_KEY_0");
        address deployer = vm.addr(privKey);
        require(deployer == DEV0, "wrong deployer");

        console.log("=== PW-C05 Integration Test ===");
        console.log("Chain:   primewavedev (ID 73571)");
        console.log("Deployer:", deployer);
        console.log("Block:   ", block.number);

        uint64 startNonce = vm.getNonce(deployer);
        console.log("Deployer nonce:", startNonce);

        // Pre-compute: nonce+0 = MockVM, nonce+1 = Vault, nonce+2 = Registry
        address futureVault    = vm.computeCreateAddress(deployer, startNonce + 1);
        address futureRegistry = vm.computeCreateAddress(deployer, startNonce + 2);

        vm.startBroadcast(privKey);

        // ── Step 1: Deploy contracts ───────────────────────────────────────────
        MockValidatorManager mockVM = new MockValidatorManager(SUBNET_ID);
        ValidatorFeeVault vault = new ValidatorFeeVault(futureRegistry);
        PrimeWaveValidatorRegistry registry = new PrimeWaveValidatorRegistry(
            DEV0, address(mockVM), address(vault)
        );

        require(address(vault)    == futureVault,    "vault addr mismatch");
        require(address(registry) == futureRegistry, "registry addr mismatch");
        require(vault.protocolAdmin() == address(registry), "vault admin not registry");

        console.log("MockValidatorManager:", address(mockVM));
        console.log("ValidatorFeeVault:   ", address(vault));
        console.log("Registry:            ", address(registry));
        console.log("[PASS] Step 1: Contracts deployed; addresses match pre-computation");

        // ── Step 2: Set up validator IDs ──────────────────────────────────────
        bytes32[15] memory vids;
        for (uint256 i = 0; i < 15; i++) {
            vids[i] = keccak256(abi.encodePacked("primewavedev-validator-", i + 1));
        }

        // ── Step 3: Register validators 1-5 as PendingAdded ───────────────────
        for (uint256 i = 0; i < 5; i++) {
            bytes memory nodeID = abi.encodePacked(bytes20(keccak256(abi.encodePacked("nodeID-", i))));
            mockVM.devRegister(vids[i], nodeID, 1);
        }
        // Validator-1 recipient = DEV0 (so claim tx can be sent)
        registry.registerValidator(vids[0], DEV0, 1);
        for (uint256 i = 1; i < 5; i++) {
            registry.registerValidator(vids[i], address(uint160(0x1001 + i)), 1);
        }
        // Validators 1-5 should be inactive (PendingAdded)
        for (uint256 i = 0; i < 5; i++) {
            require(!vault.isActive(vids[i]), "PendingAdded should be inactive");
        }
        console.log("[PASS] Step 3: Validators 1-5 registered as PendingAdded (inactive)");

        // ── Step 4: Register validators 6-15 as Active ────────────────────────
        for (uint256 i = 5; i < 15; i++) {
            bytes memory nodeID = abi.encodePacked(bytes20(keccak256(abi.encodePacked("nodeID-", i))));
            mockVM.devRegisterAndActivate(vids[i], nodeID, 1);
            registry.registerValidator(vids[i], address(uint160(0x1001 + i)), 1);
        }
        // Validators 6-15 should be active
        for (uint256 i = 5; i < 15; i++) {
            require(vault.isActive(vids[i]), "Active should be active");
        }
        require(vault.totalEffectiveWeight() == 10, "expected 10 active validators");
        console.log("[PASS] Step 4: Validators 6-15 registered as Active (10 active)");

        // ── Step 5: Activate validators 1-5 (P-Chain Warp confirmation) ───────
        for (uint256 i = 0; i < 5; i++) {
            mockVM.devActivate(vids[i]);
        }
        // Sync — all 15 should now be active
        registry.syncAll();
        require(vault.totalEffectiveWeight() == 15, "expected 15 active after syncAll");
        for (uint256 i = 0; i < 15; i++) {
            require(vault.isActive(vids[i]), "validator not active after sync");
        }
        console.log("[PASS] Step 5: Validators 1-5 activated; syncAll() synced all 15 to active");

        // ── Step 6: Send 15 PW to vault ───────────────────────────────────────
        (bool ok,) = address(vault).call{value: 15 ether}("");
        require(ok, "vault send failed");
        require(vault.totalReceived() == 15 ether, "totalReceived wrong");
        for (uint256 i = 0; i < 15; i++) {
            require(vault.claimable(vids[i]) == 1 ether, "claimable != 1 PW");
        }
        console.log("[PASS] Step 6: 15 PW received; all 15 validators have 1 PW claimable");

        // ── Step 7: Initiate removal of validator-1 ───────────────────────────
        mockVM.devInitiateRemoval(vids[0]);
        // Before sync: vault still shows active
        require(vault.isActive(vids[0]), "should still be active before sync");

        // syncValidator — should deactivate validator-1
        registry.syncValidator(vids[0]);
        require(!vault.isActive(vids[0]), "validator-1 not deactivated after sync");
        require(vault.totalEffectiveWeight() == 14, "expected 14 after deactivation");
        // Earned fees NOT confiscated
        require(vault.claimable(vids[0]) == 1 ether, "earned fees confiscated on deactivation");
        console.log("[PASS] Step 7: Validator-1 deactivation synced; 1 PW claimable preserved");

        // ── Step 8: Claim as DEV0 (validator-1 recipient) ─────────────────────
        uint256 dev0Before = DEV0.balance;
        uint256 claimed = vault.claimFees(vids[0]);
        require(claimed == 1 ether, "claimed != 1 PW");
        require(vault.totalClaimed() == 1 ether, "totalClaimed wrong");
        require(vault.claimable(vids[0]) == 0, "still claimable after claim");
        console.log("[PASS] Step 8: claimFees(validator-1) returned 1 PW to DEV0");

        // ── Step 9: Conservation after claim ──────────────────────────────────
        require(vault.vaultBalance() == vault.totalReceived() - vault.totalClaimed(),
            "INV-1 violated after claim");
        console.log("[PASS] Step 9: INV-1 holds: balance == totalReceived - totalClaimed");
        console.log("       balance:       ", vault.vaultBalance());
        console.log("       totalReceived: ", vault.totalReceived());
        console.log("       totalClaimed:  ", vault.totalClaimed());

        // ── Step 10: Send 14 more PW (14 active validators, 1 PW each) ────────
        (bool ok2,) = address(vault).call{value: 14 ether}("");
        require(ok2, "vault send 2 failed");

        // Validators 2-15 each earned 1 more PW
        for (uint256 i = 1; i < 15; i++) {
            require(vault.claimable(vids[i]) == 2 ether, "validator claimable wrong after R2");
        }
        // Validator-1 (deactivated) has 0 claimable (all earned was claimed)
        require(vault.claimable(vids[0]) == 0, "deactivated validator earned after removal");
        console.log("[PASS] Step 10: 14 PW sent; validators 2-15 have 2 PW each; validator-1 has 0");

        // ── Step 11: Weight update ─────────────────────────────────────────────
        // Change validator-2's weight to 3
        mockVM.devSetWeight(vids[1], 3);
        uint256 v2_before = vault.claimable(vids[1]); // 2 PW before weight change
        assertEq(v2_before, 2 ether);

        registry.updateWeight(vids[1]);
        // Historical fees (2 PW) must be preserved
        require(vault.claimable(vids[1]) == 2 ether, "weight update corrupted historical fees");
        // totalEffectiveWeight: 14 validators × 1 + 1 validator × 2 (was 1, now 3, so +2) = 14-1+3 = 16
        require(vault.totalEffectiveWeight() == 16, "totalEffectiveWeight wrong after weight update");
        console.log("[PASS] Step 11: Weight update to 3; historical 2 PW preserved; totalEW = 16");

        // ── Step 12: Send 16 PW to test new weight distribution ───────────────
        (bool ok3,) = address(vault).call{value: 16 ether}("");
        require(ok3);
        // validator-2 (weight 3): earns 16 * 3 / 16 = 3 PW more to total 2 + 3 = 5 PW
        require(vault.claimable(vids[1]) == 5 ether, "validator-2 new weight wrong");
        // Validators 3-15 (weight 1 each): earn 16 * 1 / 16 = 1 PW more to total 2 + 1 = 3 PW
        for (uint256 i = 2; i < 15; i++) {
            require(vault.claimable(vids[i]) == 3 ether, "validator claimable wrong after R3");
        }
        console.log("[PASS] Step 12: Weight-3 distribution correct; validator-2 has 5 PW");

        // ── Step 13: Re-activation (simulate re-registration) ─────────────────
        // Force validator-1 back to Active in MockVM (simulates new registration)
        mockVM.devForceStatus(vids[0], ValidatorStatus.Active);
        registry.syncValidator(vids[0]); // activates in feeVault

        require(vault.isActive(vids[0]), "validator-1 not re-activated");
        // No retro-accrual: claimable should still be 0 (no earnings during inactive period)
        require(vault.claimable(vids[0]) == 0, "retro-accrual on re-activation");
        console.log("[PASS] Step 13: Validator-1 re-activated; no retro-accrual (claimable == 0)");

        // ── Step 14: Final conservation check ────────────────────────────────
        require(vault.vaultBalance() == vault.totalReceived() - vault.totalClaimed(), "final INV-1");
        console.log("[PASS] Step 14: Final INV-1 verified");

        vm.stopBroadcast();

        console.log("");
        console.log("=== PW-C05 Integration Test: ALL CHECKS PASSED ===");
        console.log("  MockValidatorManager + ValidatorFeeVault + PrimeWaveValidatorRegistry");
        console.log("  deployed on primewavedev chain (Chain ID 73571)");
        console.log("  Pre-computed address matching: PASS");
        console.log("  ValidatorFeeVault admin == PrimeWaveValidatorRegistry: PASS");
        console.log("  Validators 1-5 registered PendingAdded (inactive): PASS");
        console.log("  Validators 6-15 registered Active (active): PASS");
        console.log("  syncAll() activated all 15 after P-Chain confirmation: PASS");
        console.log("  15 PW: 1 PW per validator (equal weight): PASS");
        console.log("  Validator-1 removal synced; fees NOT confiscated: PASS");
        console.log("  claimFees(validator-1) to 1 PW to DEV0: PASS");
        console.log("  INV-1 conservation after claim: PASS");
        console.log("  Deactivated validator earns 0 after removal: PASS");
        console.log("  Weight update (1to3): historical fees preserved: PASS");
        console.log("  New weight distribution correct: PASS");
        console.log("  Re-activation: no retro-accrual: PASS");
        console.log("  Final INV-1 conservation: PASS");
    }

    function assertEq(uint256 a, uint256 b) internal pure {
        require(a == b, "assertion failed: a != b");
    }
}
