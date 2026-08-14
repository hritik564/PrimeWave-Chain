// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// ============================================================
// C10FeeIsolation.t.sol  --  PW-C10
// ============================================================
//
// Fee system isolation + simultaneous reward/fee operations.
// Covers C10 brief sections 16 and 31.
//
//   Section 16: C10 must prove PoS operations cannot alter
//               FeeDistributor / ValidatorFeeVault / DevTreasury / burn.
//   Section 31: Simultaneous fee generation + staking rewards.
// ============================================================

import {Test, Vm} from "forge-std/Test.sol";
import {RewardVault} from "../src/RewardVault.sol";
import {PrimeWaveRewardCalculator} from "../src/PrimeWaveRewardCalculator.sol";
import {PrimeWaveStakingManager} from "../src/PrimeWaveStakingManager.sol";
import {FeeDistributor} from "../src/FeeDistributor.sol";
import {ValidatorFeeVault} from "../src/ValidatorFeeVault.sol";
import {DevTreasury} from "../src/DevTreasury.sol";
import {MockAvalancheValidatorManager} from "./MockAvalancheValidatorManager.sol";
import {MockWarpMessenger} from "./MockWarpMessenger.sol";
import {StakingManagerSettings} from "validator-manager/interfaces/IStakingManager.sol";
import {IRewardCalculator} from "validator-manager/interfaces/IRewardCalculator.sol";
import {IValidatorManager} from "validator-manager/interfaces/IValidatorManager.sol";
import {PChainOwner} from "validator-manager/interfaces/IACP99Manager.sol";

contract C10FeeIsolationTest is Test {

    address constant WARP_PRECOMPILE      = 0x0200000000000000000000000000000000000005;
    uint64  constant CHURN_PERIOD         = 3600;
    bytes32 constant SUBNET_ID            = bytes32(uint256(1));
    bytes32 constant UPTIME_BLOCKCHAIN_ID = bytes32(uint256(2));
    uint64  constant MIN_STAKE_DURATION   = 14 days;
    uint256 constant MIN_STAKE            = 1_000 ether;
    uint256 constant MAX_STAKE            = 3_000_000 ether;
    uint256 constant VAULT_FUND           = 15_000_000 ether;

    address admin   = makeAddr("admin");
    address staker1 = makeAddr("staker1");
    address reward1 = makeAddr("reward1");
    address feeRecv = makeAddr("feeRecv");

    // Fee system
    FeeDistributor feeDistributor;
    ValidatorFeeVault feeVault;
    DevTreasury treasury;

    // Staking system
    RewardVault vault;
    PrimeWaveRewardCalculator calc;
    MockAvalancheValidatorManager mockVM;
    PrimeWaveStakingManager sm;
    MockWarpMessenger warpMock;

    uint256 INITIAL_RATE;

    function setUp() public {
        INITIAL_RATE = uint256(3_000_000 * 1 ether) / 31_536_000;

        vm.startPrank(admin);

        // Deploy fee system (pre-computed address pattern)
        address deployer = admin;
        uint64 nonce = vm.getNonce(deployer);
        address expectedVFV  = computeCreateAddress(deployer, nonce);
        address expectedTrea = computeCreateAddress(deployer, nonce + 1);
        address expectedFD   = computeCreateAddress(deployer, nonce + 2);

        feeVault       = new ValidatorFeeVault(expectedFD);
        treasury       = new DevTreasury(expectedFD);
        feeDistributor = new FeeDistributor(payable(expectedVFV), payable(expectedTrea), admin);

        vm.stopPrank();

        // Register a validator in fee vault (must be called by feeDistributor)
        bytes32 feeValId = keccak256("fee-validator");
        vm.prank(address(feeDistributor));
        feeVault.registerValidator(feeValId, feeRecv, 1000, 10_000);

        vm.startPrank(admin);

        // Deploy staking system
        vault = new RewardVault(admin, INITIAL_RATE);
        vm.deal(admin, VAULT_FUND + 100 ether);
        vault.fund{value: VAULT_FUND}();

        mockVM = new MockAvalancheValidatorManager(SUBNET_ID, CHURN_PERIOD);
        calc   = new PrimeWaveRewardCalculator(vault);
        sm     = new PrimeWaveStakingManager();
        sm.initialize(
            StakingManagerSettings({
                manager:                  IValidatorManager(address(mockVM)),
                minimumStakeAmount:       MIN_STAKE,
                maximumStakeAmount:       MAX_STAKE,
                minimumStakeDuration:     MIN_STAKE_DURATION,
                minimumDelegationFeeBips: 100,
                maximumStakeMultiplier:   1,
                weightToValueFactor:      1 ether,
                rewardCalculator:         IRewardCalculator(address(calc)),
                uptimeBlockchainID:       UPTIME_BLOCKCHAIN_ID
            }),
            vault
        );
        vault.setStakingManager(address(sm));

        vm.stopPrank();

        warpMock = new MockWarpMessenger();
        vm.etch(WARP_PRECOMPILE, address(warpMock).code);
        warpMock = MockWarpMessenger(payable(WARP_PRECOMPILE));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // FI-01: FeeDistributor 70/20/10 is preserved during staking operations
    // (Section 16)
    // ─────────────────────────────────────────────────────────────────────────

    function test_FI01_feeSplitPreservedDuringStaking() public {
        // Staking operation in progress
        uint256 stake = 10_000 ether;
        vm.deal(staker1, stake);

        uint64 t0 = uint64(block.timestamp);
        bytes32 vid = _register(staker1, stake, reward1, 1);
        sm.completeValidatorRegistration(0);

        // Simulate fee income while staking is active
        uint256 feeAmount = 100 ether;
        vm.deal(address(feeDistributor), feeAmount);
        feeDistributor.distribute();

        // Verify 70/20/10 split
        uint256 validatorShare = feeAmount * 7000 / 10000;
        uint256 treasuryShare  = feeAmount * 2000 / 10000;
        uint256 burnShare      = feeAmount - validatorShare - treasuryShare;

        assertEq(feeDistributor.totalValidatorShare(), validatorShare, "70% to VFV");
        assertEq(feeDistributor.totalTreasuryShare(),  treasuryShare,  "20% to treasury");
        assertEq(feeDistributor.totalBurnShare(),      burnShare,      "10% to burn");
        assertEq(feeDistributor.totalDistributed(),    feeAmount,      "total distributed");

        // Vault balance unaffected by fee distribution
        assertEq(address(vault).balance, vault.totalFunded() - vault.totalClaimed(), "vault unchanged");

        // Complete staking
        uint64 t1 = t0 + 20 days;
        vm.warp(t1);

        warpMock.setUptimeResponse(0, UPTIME_BLOCKCHAIN_ID, vid, uint64(20 days));
        vm.prank(staker1); sm.submitUptimeProof(vid, 0);
        vm.prank(staker1); sm.initiateValidatorRemoval(vid, false, 0);
        sm.completeValidatorRemoval(0);

        // Fee accounting still exact
        assertEq(feeDistributor.totalValidatorShare(), validatorShare, "VFV share unchanged by staking reward");
        assertEq(feeDistributor.totalTreasuryShare(),  treasuryShare,  "treasury unchanged by staking reward");
        assertEq(feeDistributor.totalBurnShare(),      burnShare,      "burn unchanged by staking reward");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // FI-02: Staking rewards CANNOT consume validator transaction fees
    // (Section 16 — critical isolation invariant)
    // ─────────────────────────────────────────────────────────────────────────

    function test_FI02_stakingRewardsCannotConsumeFeeFunds() public {
        // Send fees to FeeDistributor, distribute
        uint256 feeAmount = 50 ether;
        vm.deal(address(feeDistributor), feeAmount);
        feeDistributor.distribute();

        uint256 feeVaultBalBefore = address(feeVault).balance;

        // Do staking with rewards
        uint256 stake = 5_000 ether;
        vm.deal(staker1, stake);

        uint64 t0 = uint64(block.timestamp);
        bytes32 vid = _register(staker1, stake, reward1, 2);
        sm.completeValidatorRegistration(0);

        uint64 t1 = t0 + 30 days;
        vm.warp(t1);

        warpMock.setUptimeResponse(0, UPTIME_BLOCKCHAIN_ID, vid, uint64(30 days));
        vm.prank(staker1); sm.submitUptimeProof(vid, 0);
        vm.prank(staker1); sm.initiateValidatorRemoval(vid, false, 0);
        sm.completeValidatorRemoval(0);

        // Fee vault balance MUST be unchanged by staking reward payout
        assertEq(address(feeVault).balance, feeVaultBalBefore, "fee vault balance unchanged by staking");

        // Staking reward came from RewardVault, not fee vault
        assertGt(reward1.balance, 0, "staking reward paid");
        assertEq(address(feeVault).balance, feeVaultBalBefore, "fee funds not consumed");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // FI-03: Validator transaction fees CANNOT become staking rewards
    // (Section 16 — cross-contamination prevention)
    // ─────────────────────────────────────────────────────────────────────────

    function test_FI03_feesCantBecomeStakingRewards() public {
        uint256 vaultBalBefore = address(vault).balance;
        uint256 fundedBefore   = vault.totalFunded();

        // Large fee distribution
        uint256 feeAmount = 1_000 ether;
        vm.deal(address(feeDistributor), feeAmount);
        feeDistributor.distribute();

        // RewardVault balance and funding MUST be unchanged
        assertEq(address(vault).balance, vaultBalBefore, "reward vault balance unchanged by fee distribution");
        assertEq(vault.totalFunded(), fundedBefore, "vault totalFunded unchanged");

        // Fee vault received its share
        assertGe(address(feeVault).balance, feeAmount * 7000 / 10000, "fee vault received its share");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // FI-04: Simultaneous staking + fee generation — both systems balance
    // (Section 31 — reward/fee simultaneously)
    // ─────────────────────────────────────────────────────────────────────────

    function test_FI04_simultaneousStakingAndFees_bothBalance() public {
        uint256 stake = 20_000 ether;
        vm.deal(staker1, stake);

        uint64 t0 = uint64(block.timestamp);
        bytes32 vid = _register(staker1, stake, reward1, 3);
        sm.completeValidatorRegistration(0);

        // Interleave fee distributions with staking time progression
        uint256 totalFees = 0;
        uint64 t1 = t0 + 10 days;
        vm.warp(t1);

        uint256 fee1 = 30 ether;
        vm.deal(address(feeDistributor), fee1);
        feeDistributor.distribute();
        totalFees += fee1;

        uint64 t2 = t1 + 10 days;
        vm.warp(t2);

        uint256 fee2 = 50 ether;
        vm.deal(address(feeDistributor), fee2);
        feeDistributor.distribute();
        totalFees += fee2;

        uint64 t3 = t2 + 10 days;
        vm.warp(t3);

        // Complete staking removal
        warpMock.setUptimeResponse(0, UPTIME_BLOCKCHAIN_ID, vid, uint64(30 days));
        vm.prank(staker1); sm.submitUptimeProof(vid, 0);
        vm.prank(staker1); sm.initiateValidatorRemoval(vid, false, 0);
        sm.completeValidatorRemoval(0);

        // Fee system invariants
        assertEq(feeDistributor.totalDistributed(), totalFees, "total fees distributed");
        assertEq(
            feeDistributor.totalValidatorShare() + feeDistributor.totalTreasuryShare() + feeDistributor.totalBurnShare(),
            totalFees,
            "fee split sums to total"
        );

        // Staking system invariants
        assertLe(vault.totalEmitted(), vault.totalFunded(), "vault emitted <= funded");
        assertEq(address(vault).balance, vault.totalFunded() - vault.totalClaimed(), "vault balance exact");

        // Staking reward came from vault, not fees
        assertGt(reward1.balance, 0, "staking reward paid");
        assertEq(address(vault).balance, vault.totalFunded() - vault.totalClaimed(), "vault exact");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // FI-05: Staking claim does not alter 70/20/10 accounting
    // ─────────────────────────────────────────────────────────────────────────

    function test_FI05_stakingClaimDoesNotAlterFeeAccounting() public {
        // Distribute some fees first
        uint256 feeAmount = 200 ether;
        vm.deal(address(feeDistributor), feeAmount);
        feeDistributor.distribute();

        uint256 fdTotalBefore = feeDistributor.totalDistributed();
        uint256 fdValBefore   = feeDistributor.totalValidatorShare();
        uint256 fdTreaBefore  = feeDistributor.totalTreasuryShare();
        uint256 fdBurnBefore  = feeDistributor.totalBurnShare();

        // Staking claim
        vm.prank(address(sm));
        vault.distribute(reward1, 500 ether);

        // Fee accounting unchanged
        assertEq(feeDistributor.totalDistributed(),    fdTotalBefore, "FD totalDistributed unchanged");
        assertEq(feeDistributor.totalValidatorShare(), fdValBefore,   "FD validatorShare unchanged");
        assertEq(feeDistributor.totalTreasuryShare(),  fdTreaBefore,  "FD treasuryShare unchanged");
        assertEq(feeDistributor.totalBurnShare(),      fdBurnBefore,  "FD burnShare unchanged");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // FI-06: Unbonding during fee generation — fee system unaffected
    // ─────────────────────────────────────────────────────────────────────────

    function test_FI06_unbondingDuringFeeGeneration_feeUnaffected() public {
        uint256 stake = 8_000 ether;
        vm.deal(staker1, stake);

        uint64 t0 = uint64(block.timestamp);
        bytes32 vid = _register(staker1, stake, reward1, 4);
        sm.completeValidatorRegistration(0);

        uint64 t1 = t0 + MIN_STAKE_DURATION + 1;
        vm.warp(t1);

        // Start unbonding
        vm.prank(staker1);
        sm.forceInitiateValidatorRemoval(vid, false, 0);

        // Fee distribution DURING unbonding period
        uint256 feeAmount = 75 ether;
        vm.deal(address(feeDistributor), feeAmount);
        feeDistributor.distribute();

        uint256 fdTotal = feeDistributor.totalDistributed();

        // Complete unbonding
        sm.completeValidatorRemoval(0);

        // Fee accounting unchanged by unbonding completion
        assertEq(feeDistributor.totalDistributed(), fdTotal, "FD unchanged by unbonding completion");
        assertEq(staker1.balance, stake, "stake returned");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // FI-07: Fee validator weight change during staking — no cross-impact
    // ─────────────────────────────────────────────────────────────────────────

    function test_FI07_feeValidatorWeightChange_noStakingImpact() public {
        uint256 vaultFundedBefore = vault.totalFunded();
        uint256 vaultRateBefore   = vault.emissionRatePerSecond();

        // Change fee vault validator weight (admin action in fee system)
        bytes32 feeValId = keccak256("fee-validator");
        vm.prank(address(feeDistributor));
        feeVault.setBaseWeight(feeValId, 500);

        // Staking system completely unaffected
        assertEq(vault.totalFunded(), vaultFundedBefore, "vault funding unchanged");
        assertEq(vault.emissionRatePerSecond(), vaultRateBefore, "vault rate unchanged");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // FI-08: Validator claims fee while simultaneously staking — no interference
    // ─────────────────────────────────────────────────────────────────────────

    function test_FI08_validatorClaimsFeeWhileStaking_noInterference() public {
        // Register validator in fee vault
        bytes32 feeValId = keccak256("fee-validator");

        // Send fees
        uint256 feeAmount = 100 ether;
        vm.deal(address(feeDistributor), feeAmount);
        feeDistributor.distribute();

        uint256 feeVaultBalBefore = address(feeVault).balance;

        // Staker registers in staking SM simultaneously
        uint256 stake = 5_000 ether;
        vm.deal(staker1, stake);
        bytes32 vid = _register(staker1, stake, reward1, 5);
        sm.completeValidatorRegistration(0);

        // Validator claims fee (must call as the registered rewardAddress)
        uint256 claimable = feeVault.claimable(feeValId);
        if (claimable > 0) {
            vm.prank(feeRecv);
            feeVault.claimFees(feeValId);
        }

        // Staking system not affected by fee claim
        assertEq(address(vault).balance, vault.totalFunded() - vault.totalClaimed(), "vault exact");
        assertEq(address(sm).balance, stake, "SM holds stake");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // FI-09: DevTreasury balance is independent of staking
    // ─────────────────────────────────────────────────────────────────────────

    function test_FI09_devTreasury_independentOfStaking() public {
        uint256 treasuryBalBefore = address(treasury).balance;

        // Large staking reward distribution
        vm.prank(address(sm));
        vault.distribute(reward1, 1_000_000 ether);

        // Treasury balance completely unchanged
        assertEq(address(treasury).balance, treasuryBalBefore, "treasury unchanged by staking");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // FI-10: Burn address balance independent of staking
    // ─────────────────────────────────────────────────────────────────────────

    function test_FI10_burnAddress_independentOfStaking() public {
        address burnAddr = feeDistributor.BURN_ADDRESS();
        uint256 burnBalBefore = burnAddr.balance;

        // Staking reward (from RewardVault, not FeeDistributor)
        vm.prank(address(sm));
        vault.distribute(reward1, 500 ether);

        // Burn balance unchanged by staking rewards
        assertEq(burnAddr.balance, burnBalBefore, "burn address unchanged by staking");

        // Fee distribution DOES affect burn
        uint256 feeAmount = 100 ether;
        vm.deal(address(feeDistributor), feeAmount);
        feeDistributor.distribute();

        uint256 expectedBurn = feeAmount * 1000 / 10000; // ~10%
        assertGe(burnAddr.balance, burnBalBefore + expectedBurn - 2, "burn received fee share");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // FI-11: FeeDistributor.totalDistributed == vfv + treasury + burn
    // (Section 16 — 70/20/10 remains conserved)
    // ─────────────────────────────────────────────────────────────────────────

    function test_FI11_feeSplitConservation_multipleDistributions() public {
        uint256[] memory amounts = new uint256[](5);
        amounts[0] = 1 ether;
        amounts[1] = 7 ether;
        amounts[2] = 99 ether;
        amounts[3] = 1000 ether;
        amounts[4] = 3 wei;

        for (uint256 i = 0; i < amounts.length; i++) {
            vm.deal(address(feeDistributor), amounts[i]);
            feeDistributor.distribute();
        }

        // Conservation invariant
        assertEq(
            feeDistributor.totalValidatorShare() +
            feeDistributor.totalTreasuryShare()  +
            feeDistributor.totalBurnShare(),
            feeDistributor.totalDistributed(),
            "fee split sums to total distributed"
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // FI-12: FeeVault balance == totalReceived - totalClaimed (exact)
    // ─────────────────────────────────────────────────────────────────────────

    function test_FI12_feeVaultBalanceConservation() public {
        // Multiple fee distributions
        uint256 fee1 = 100 ether;
        uint256 fee2 = 200 ether;
        vm.deal(address(feeDistributor), fee1); feeDistributor.distribute();
        vm.deal(address(feeDistributor), fee2); feeDistributor.distribute();

        // Claim fees for the registered validator (must prank as rewardAddress)
        bytes32 feeValId = keccak256("fee-validator");
        vm.prank(feeRecv);
        feeVault.claimFees(feeValId);

        // Balance conservation
        assertEq(
            address(feeVault).balance,
            feeVault.totalReceived() - feeVault.totalClaimed(),
            "fee vault balance == totalReceived - totalClaimed"
        );
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    function _register(
        address who,
        uint256 amount,
        address rewardRecipient,
        uint256 seed
    ) internal returns (bytes32) {
        bytes memory nodeID = abi.encodePacked(bytes20(uint160(uint256(keccak256(abi.encode(seed))))));
        bytes memory blsKey = new bytes(48);
        PChainOwner memory noOwner = PChainOwner({threshold: 0, addresses: new address[](0)});
        vm.prank(who);
        return sm.initiateValidatorRegistration{value: amount}(
            nodeID, blsKey, noOwner, noOwner, 100, MIN_STAKE_DURATION, rewardRecipient
        );
    }
}
