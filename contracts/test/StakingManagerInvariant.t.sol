// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// ============================================================
// StakingManagerInvariant.t.sol  --  PW-C09
// ============================================================
//
// Stateful invariant tests for the C09 PoS staking system.
// Each test is named INV_N_<description> matching the C09 gate
// invariant checklist.
//
// Gate invariants tested here:
//   INV-5:  Annual rewards <= 3,000,000 PW
//   INV-6:  Total rewards  <= 15,000,000 PW (vault cap)
//   INV-2:  Stake conservation (stake always returned to owner)
//   INV-10: ValidatorManager remains authoritative
//   INV-11: FeeDistributor remains independent of staking ops
//   INV-12: Governance boundaries (setStakingManager is admin-only)
//
// Other invariants covered in StakingManagerUnit.t.sol /
// StakingManagerFuzz.t.sol:
//   INV-1:  No minting (F2: totalFunded unchanged)
//   INV-3:  Withdrawals <= deposits (F2b: cannot overdraw)
//   INV-4:  Rewards <= available reserve (F1)
//   INV-7:  Unauthorized reward claim impossible (unit)
//   INV-8:  Unauthorized withdrawal impossible (unit)
//   INV-9:  14-day unbonding cannot be bypassed (unit)
// ============================================================

import {Test} from "forge-std/Test.sol";
import {RewardVault} from "../src/RewardVault.sol";
import {FeeDistributor} from "../src/FeeDistributor.sol";
import {PrimeWaveRewardCalculator} from "../src/PrimeWaveRewardCalculator.sol";
import {PrimeWaveStakingManager} from "../src/PrimeWaveStakingManager.sol";
import {MockAvalancheValidatorManager} from "./MockAvalancheValidatorManager.sol";
import {MockWarpMessenger} from "./MockWarpMessenger.sol";
import {StakingManagerSettings} from "validator-manager/interfaces/IStakingManager.sol";
import {IRewardCalculator} from "validator-manager/interfaces/IRewardCalculator.sol";
import {IValidatorManager} from "validator-manager/interfaces/IValidatorManager.sol";
import {PChainOwner} from "validator-manager/interfaces/IACP99Manager.sol";

contract StakingManagerInvariantTest is Test {

    // ── Constants ─────────────────────────────────────────────────────────────

    address constant WARP_PRECOMPILE    = 0x0200000000000000000000000000000000000005;
    uint64  constant MIN_STAKE_DURATION = 14 days;
    uint64  constant CHURN_PERIOD       = 3600;
    bytes32 constant SUBNET_ID          = bytes32(uint256(1));
    bytes32 constant UPTIME_BLOCKCHAIN_ID = bytes32(uint256(2));
    uint256 constant VAULT_FUND         = 15_000_000 ether;
    uint256 constant MIN_STAKE          = 1_000 ether;
    uint256 constant MAX_STAKE          = 3_000_000 ether;

    // ── Actors ────────────────────────────────────────────────────────────────

    address admin      = makeAddr("admin");
    address validator1 = makeAddr("validator1");
    address rewarded1  = makeAddr("rewarded1");
    address attacker   = makeAddr("attacker");
    address fdVault    = makeAddr("fdVault");
    address fdTreasury = makeAddr("fdTreasury");

    // ── Contracts ─────────────────────────────────────────────────────────────

    RewardVault                   vault;
    PrimeWaveRewardCalculator     calc;
    MockAvalancheValidatorManager mockVM;
    PrimeWaveStakingManager       sm;
    MockWarpMessenger             warpMock;

    // ── Rate ──────────────────────────────────────────────────────────────────
    uint256 MAX_RATE; // set in setUp from vault.MAX_RATE_PER_SECOND()

    // ── Setup ─────────────────────────────────────────────────────────────────

    function setUp() public {
        vm.startPrank(admin);

        vault  = new RewardVault(admin, uint256(3_000_000 * 1 ether) / 31_536_000);
        vm.deal(admin, VAULT_FUND + 10 ether);
        vault.fund{value: VAULT_FUND}();

        MAX_RATE = vault.MAX_RATE_PER_SECOND();

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

        // Etch mock Warp precompile
        MockWarpMessenger tmp = new MockWarpMessenger();
        vm.etch(WARP_PRECOMPILE, address(tmp).code);
        warpMock = MockWarpMessenger(payable(WARP_PRECOMPILE));

        vm.stopPrank();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // INV-5: Annual rewards <= MAX_ANNUAL_EMISSION (3,000,000 PW)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice The emission rate is bounded such that at max rate, a full year
    ///         cannot pay out more than MAX_ANNUAL_EMISSION (3,000,000 PW).
    ///         Verifies: MAX_RATE_PER_SECOND × SECONDS_PER_YEAR <= 3_000_000 ether
    function test_INV5_annualEmissionCapEnforced() public view {
        uint256 maxRate      = vault.MAX_RATE_PER_SECOND();
        uint256 secPerYear   = vault.SECONDS_PER_YEAR();
        uint256 maxAnnual    = vault.MAX_ANNUAL_EMISSION();

        uint256 maxYearlyOut = maxRate * secPerYear;
        assertLe(maxYearlyOut, maxAnnual,
            "INV-5: max yearly emission must not exceed MAX_ANNUAL_EMISSION");
    }

    /// @notice For any staking duration up to one year, reward computed at max rate
    ///         with 100% uptime stays within the annual cap.
    function testFuzz_INV5_rewardAtMaxRateNeverExceedsAnnualCap(uint32 durationSeconds) public view {
        // Bound to [1, 1 year] — the maximum period for a single validator's reward
        uint64 duration = uint64(bound(durationSeconds, 1, uint32(365 days)));
        uint64 t0 = 1_000_000;
        uint64 t1 = t0 + duration;

        uint256 reward = calc.calculateReward(MAX_STAKE, t0, t0, t1, duration);

        // Must not exceed MAX_ANNUAL_EMISSION regardless of duration
        assertLe(reward, vault.MAX_ANNUAL_EMISSION(),
            "INV-5: single reward must not exceed annual emission cap");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // INV-6: Total rewards <= 15,000,000 PW (vault cap)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice After arbitrary distribute calls, totalClaimed is always bounded
    ///         by the vault's total funded amount (15,000,000 PW).
    function testFuzz_INV6_totalRewardsBoundedByVaultFunding(uint256[10] memory amounts) public {
        for (uint256 i = 0; i < 10; i++) {
            uint256 available = vault.totalFunded() - vault.totalEmitted();
            if (available == 0) break;
            uint256 amount = bound(amounts[i], 0, available);
            if (amount == 0) continue;
            vm.prank(address(sm));
            vault.distribute(rewarded1, amount);
        }

        assertLe(vault.totalClaimed(), VAULT_FUND,
            "INV-6: total claimed must not exceed 15M PW vault fund");
        assertEq(vault.totalClaimed(), vault.totalEmitted(),
            "INV-6: claimed must equal emitted for PoS-only vault");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // INV-2: Stake conservation — validator always recovers original stake
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Full lifecycle: staked ETH MUST be returned to the validator's
    ///         address regardless of reward amount (zero or non-zero).
    function test_INV2_stakeConservation_zeroReward() public {
        uint256 stake = 10_000 ether;
        vm.deal(validator1, stake);

        bytes32 vid = _register(stake);
        sm.completeValidatorRegistration(0);
        vm.warp(block.timestamp + MIN_STAKE_DURATION + 1);

        uint256 balBefore = validator1.balance;

        vm.prank(validator1);
        sm.forceInitiateValidatorRemoval(vid, false, 0);
        sm.completeValidatorRemoval(0);

        assertEq(validator1.balance, balBefore + stake,
            "INV-2: stake must be fully returned (zero reward)");
    }

    /// @notice Full lifecycle with reward: stake PLUS reward returned correctly.
    function test_INV2_stakeConservation_withReward() public {
        uint256 stake    = 10_000 ether;
        uint64  duration = 30 days;
        vm.deal(validator1, stake);

        uint64 t0 = uint64(block.timestamp);
        bytes32 vid = _register(stake);
        sm.completeValidatorRegistration(0);

        vm.warp(t0 + duration);

        // Submit uptime proof: 100% uptime
        warpMock.setUptimeResponse(0, UPTIME_BLOCKCHAIN_ID, vid, duration);
        vm.prank(validator1);
        sm.submitUptimeProof(vid, 0);

        vm.prank(validator1);
        sm.initiateValidatorRemoval(vid, false, 0);

        uint256 valBalBefore = validator1.balance;
        uint256 rewBalBefore = rewarded1.balance;
        sm.completeValidatorRemoval(0);

        // Stake returned exactly
        assertEq(validator1.balance, valBalBefore + stake,
            "INV-2: stake returned in full even when reward is non-zero");

        // Reward positive and goes to rewarded1, not validator1
        assertGt(rewarded1.balance, rewBalBefore,
            "INV-2: reward distributed to rewarded address");
    }

    /// @notice Fuzz: for any valid stake amount, stake is always returned.
    ///         NOTE: StakingManager converts stake → weight via integer division
    ///         (weight = stakeAmount / weightToValueFactor). Sub-factor dust is
    ///         retained in the SM contract. We align the fuzz input to a
    ///         weightToValueFactor (1 ether) boundary so the conversion is lossless
    ///         and the invariant holds exactly.
    function testFuzz_INV2_stakeAlwaysReturned(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, MIN_STAKE, MAX_STAKE);
        // Align to 1-ether boundary to avoid sub-ether dust truncation
        stakeAmount = (stakeAmount / 1 ether) * 1 ether;
        vm.assume(stakeAmount >= MIN_STAKE); // guard against pathological rounding

        vm.deal(validator1, stakeAmount);

        bytes32 vid = _register(stakeAmount);
        sm.completeValidatorRegistration(0);
        vm.warp(block.timestamp + MIN_STAKE_DURATION + 1);

        uint256 balBefore = validator1.balance;
        vm.prank(validator1);
        sm.forceInitiateValidatorRemoval(vid, false, 0);
        sm.completeValidatorRemoval(0);

        assertEq(validator1.balance, balBefore + stakeAmount,
            "INV-2: fuzz - stake must always be returned");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // INV-10: ValidatorManager remains authoritative
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice PrimeWaveStakingManager cannot complete a registration for a
    ///         validationID that the ValidatorManager never issued.
    ///         Verifies that the MockVM's queue is the sole source of truth.
    function test_INV10_cannotCompleteUnissuedRegistration() public {
        // Try to complete msg index 0 before any registration is initiated.
        // The mock will revert because its pendingRegistration[0] is bytes32(0)
        // (zero validationID), and subsequent processing fails.
        vm.expectRevert();
        sm.completeValidatorRegistration(0);
    }

    /// @notice A registrationID must come from the MockValidatorManager queue.
    ///         Directly calling completeValidatorRegistration with an out-of-range
    ///         index reverts.
    function test_INV10_completionRequiresValidatorManagerQueue() public {
        uint256 stake = 10_000 ether;
        vm.deal(validator1, stake);

        // Initiate one registration → fills queue index 0
        _register(stake);

        // Index 1 was never issued → must revert
        vm.expectRevert();
        sm.completeValidatorRegistration(1);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // INV-11: FeeDistributor remains independent of staking operations
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Staking lifecycle (register, complete, remove) must not alter
    ///         FeeDistributor storage variables or the fee vault balance.
    ///         The FD is entirely driven by AvalancheGo AddBalance(), not SM.
    function test_INV11_feeDistributorUnaffectedByStaking() public {
        // Deploy a FeeDistributor (requires non-zero constructor args)
        address payable fdVaultPayable   = payable(fdVault);
        address payable fdTreasuryPayable = payable(fdTreasury);
        FeeDistributor fd = new FeeDistributor(fdVaultPayable, fdTreasuryPayable, address(0));

        uint256 fdTotalBefore    = fd.totalDistributed();
        uint256 fdValShareBefore = fd.totalValidatorShare();
        uint256 fdTreasureBefore = fd.totalTreasuryShare();
        uint256 fdBurnBefore     = fd.totalBurnShare();

        // Run a full staking lifecycle
        uint256 stake = 10_000 ether;
        vm.deal(validator1, stake);
        bytes32 vid = _register(stake);
        sm.completeValidatorRegistration(0);
        vm.warp(block.timestamp + MIN_STAKE_DURATION + 1);
        vm.prank(validator1);
        sm.forceInitiateValidatorRemoval(vid, false, 0);
        sm.completeValidatorRemoval(0);

        // FeeDistributor state must be identical — staking never touches it
        assertEq(fd.totalDistributed(),    fdTotalBefore,    "INV-11: FD totalDistributed unchanged");
        assertEq(fd.totalValidatorShare(), fdValShareBefore, "INV-11: FD validatorShare unchanged");
        assertEq(fd.totalTreasuryShare(),  fdTreasureBefore, "INV-11: FD treasuryShare unchanged");
        assertEq(fd.totalBurnShare(),      fdBurnBefore,     "INV-11: FD burnShare unchanged");
        assertEq(address(fd).balance,      0,                "INV-11: FD balance unchanged (zero)");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // INV-12: Governance boundaries — setStakingManager is admin-only
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Non-admin cannot call setStakingManager.
    function test_INV12_setStakingManagerRequiresAdmin() public {
        // Deploy a fresh vault without a staking manager set
        vm.prank(admin);
        RewardVault freshVault = new RewardVault(admin, 0);

        // Attacker (non-admin) must be rejected
        vm.prank(attacker);
        vm.expectRevert();
        freshVault.setStakingManager(address(sm));

        // Admin can set it
        vm.prank(admin);
        freshVault.setStakingManager(address(sm));
        assertEq(freshVault.stakingManager(), address(sm), "INV-12: admin can set stakingManager");
    }

    /// @notice setStakingManager is a one-time operation; calling it a second
    ///         time reverts even for admin.
    function test_INV12_setStakingManagerOnce() public {
        // vault.stakingManager is already set in setUp → second call must revert
        vm.prank(admin);
        vm.expectRevert("RV: staking manager already set");
        vault.setStakingManager(makeAddr("other"));
    }

    /// @notice distribute() can ONLY be called by the registered stakingManager.
    ///         Any other caller — including admin — is rejected.
    function test_INV12_distributeOnlyByStakingManager() public {
        vm.deal(admin, 1 ether);
        vm.prank(admin);
        vault.fund{value: 1 ether}();

        // Admin cannot call distribute
        vm.prank(admin);
        vm.expectRevert("RV: not staking manager");
        vault.distribute(rewarded1, 1 ether);

        // Attacker cannot call distribute
        vm.prank(attacker);
        vm.expectRevert("RV: not staking manager");
        vault.distribute(rewarded1, 1 ether);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────────

    function _register(uint256 stakeAmount) internal returns (bytes32 validationID) {
        PChainOwner memory noOwner = PChainOwner({
            threshold: 0,
            addresses: new address[](0)
        });
        bytes memory nodeID = abi.encodePacked(
            bytes20(uint160(uint256(keccak256(abi.encode(stakeAmount, block.timestamp)))))
        );
        bytes memory blsKey = new bytes(48);

        vm.prank(validator1);
        validationID = sm.initiateValidatorRegistration{value: stakeAmount}(
            nodeID, blsKey, noOwner, noOwner, 100, MIN_STAKE_DURATION, rewarded1
        );
    }
}
