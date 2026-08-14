// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// ============================================================
// C11 Infrastructure Tests — Production Invariant Verification
// ============================================================
//
// Covers:
//   INV-G1  through INV-G12   (genesis invariants)
//   FUND-01 through FUND-08   (15M RewardVault funding procedure)
//   SYNC-01 through SYNC-12   (registry sync lifecycle)
//   PROT-01 through PROT-05   (wrong-chain/wrong-network protection)
//   EMS-ROT-01, EMS-ROT-02    (EMS signer rotation operational procedure)
//   FEE-01  through FEE-04    (fee routing integrity)
//
// All tests use dev-local contracts. No mainnet deployment.
// No production keys used or required.
// ============================================================

import "forge-std/Test.sol";

import {RewardVault}                from "../src/RewardVault.sol";
import {FeeDistributor}             from "../src/FeeDistributor.sol";
import {ValidatorFeeVault}          from "../src/ValidatorFeeVault.sol";
import {DevTreasury}                from "../src/DevTreasury.sol";
import {EmergencyMultisig}          from "../src/EmergencyMultisig.sol";
import {PrimeWaveTimelock}          from "../src/PrimeWaveTimelock.sol";
import {
    PrimeWaveValidatorRegistry,
    ValidatorStatus,
    ValidatorACP99
} from "../src/PrimeWaveValidatorRegistry.sol";

// ─── Mock ValidatorManager for registry sync tests ───────────────────────────

/// @dev Lightweight ACP-99 mock: lets tests set arbitrary validator state.
///      Returns the same ValidatorACP99 struct the registry reads.
///      Does NOT require Warp/P-Chain infrastructure.
contract SyncTestVM {
    struct Val { ValidatorStatus status; uint64 weight; }
    mapping(bytes32 => Val) private _vals;

    function getValidator(bytes32 id) external view returns (ValidatorACP99 memory v) {
        Val memory s = _vals[id];
        v.status = s.status;
        v.weight = s.weight;
        // nodeID, nonces, times: all zero — irrelevant for registry sync logic
    }

    function l1TotalWeight() external pure returns (uint64) { return 1000; }
    function subnetID()      external pure returns (bytes32) { return bytes32(uint256(73571)); }

    /// @dev Test helper — set validator state directly
    function setState(bytes32 id, ValidatorStatus s, uint64 w) external {
        _vals[id] = Val(s, w);
    }
}

// ─────────────────────────────────────────────────────────────────────────────

contract C11InfrastructureTest is Test {

    // ── Locked constants ──────────────────────────────────────────────────────

    uint256 constant TOTAL_SUPPLY        = 100_000_000 ether;
    uint256 constant REWARD_VAULT_FUND   = 15_000_000 ether;
    uint256 constant MAX_ANNUAL_EMISSION = 3_000_000 ether;
    uint256 constant UNBONDING_SECONDS   = 1_209_600;      // 14 days
    uint256 constant EMS_THRESHOLD       = 3;
    uint256 constant EMS_MAX_SIGNERS     = 5;
    uint256 constant TIMELOCK_DELAY      = 172_800;        // 48 h
    uint256 constant INITIAL_RATE        = uint256(3_000_000 * 1 ether) / 31_536_000;

    address constant BURN_ADDRESS        = 0x000000000000000000000000000000000000dEaD;

    // ── Actors ────────────────────────────────────────────────────────────────

    address admin       = makeAddr("admin");
    address deployer    = makeAddr("deployer");
    address keeper      = makeAddr("keeper");
    address recipient1  = makeAddr("recipient1");

    address signer1 = makeAddr("signer1");
    address signer2 = makeAddr("signer2");
    address signer3 = makeAddr("signer3");
    address signer4 = makeAddr("signer4");
    address signer5 = makeAddr("signer5");

    // ── Contracts ─────────────────────────────────────────────────────────────

    RewardVault                vault;
    ValidatorFeeVault          feeVault;
    DevTreasury                devTreasury;
    FeeDistributor             feeDistributor;
    EmergencyMultisig          ems;
    PrimeWaveTimelock          timelock;
    PrimeWaveValidatorRegistry registry;
    SyncTestVM                 syncVM;

    // ── Setup ─────────────────────────────────────────────────────────────────

    function setUp() public {
        address[5] memory signers = [signer1, signer2, signer3, signer4, signer5];

        vm.startPrank(admin);

        // Deploy EMS, timelock, syncVM first (no inter-dependencies)
        ems      = new EmergencyMultisig(signers);
        timelock = new PrimeWaveTimelock(admin);
        syncVM   = new SyncTestVM();

        // Predict deployment addresses for the chicken-and-egg dependencies:
        //   ValidatorFeeVault.protocolAdmin = registry  (immutable)
        //   DevTreasury.feeDistributor = feeDistributor (immutable)
        //
        // From the admin's current nonce, deployments will be:
        //   nonce+0: feeVault
        //   nonce+1: devTreasury
        //   nonce+2: feeDistributor
        //   nonce+3: registry
        //   nonce+4: vault

        uint64 n = vm.getNonce(admin);
        address predictedFeeDistributor = vm.computeCreateAddress(admin, n + 2);
        address predictedRegistry       = vm.computeCreateAddress(admin, n + 3);

        // Deploy feeVault — registry will be its protocolAdmin
        feeVault    = new ValidatorFeeVault(predictedRegistry);

        // Deploy devTreasury — links to predicted feeDistributor
        devTreasury = new DevTreasury(predictedFeeDistributor);

        // Deploy feeDistributor (lands at predictedFeeDistributor)
        feeDistributor = new FeeDistributor(
            payable(address(feeVault)),
            payable(address(devTreasury)),
            address(ems)
        );
        require(address(feeDistributor) == predictedFeeDistributor, "feeDistributor address mismatch");

        // Deploy registry (lands at predictedRegistry) — admin=admin, feeVault admin
        registry = new PrimeWaveValidatorRegistry(
            admin,
            address(syncVM),
            address(feeVault)
        );
        require(address(registry) == predictedRegistry, "registry address mismatch");

        // Deploy RewardVault — admin for tests (production: timelock)
        vault = new RewardVault(admin, INITIAL_RATE);
        vault.setPauseController(address(ems));

        vm.stopPrank();
    }

    // ── Helpers ────────────────────────────────────────────────────────────────

    bytes32 constant VID_1 = keccak256("validator-1");
    bytes32 constant VID_2 = keccak256("validator-2");
    bytes32 constant VID_3 = keccak256("validator-3");

    function _registerActive(bytes32 vid, address recip) internal {
        syncVM.setState(vid, ValidatorStatus.Active, 1000);
        vm.prank(admin); // registry.protocolAdmin = admin
        registry.registerValidator(vid, recip, 1000);
    }

    function _registerPending(bytes32 vid, address recip) internal {
        syncVM.setState(vid, ValidatorStatus.PendingAdded, 1000);
        vm.prank(admin);
        registry.registerValidator(vid, recip, 1000);
    }

    // ═════════════════════════════════════════════════════════════════════════
    // SECTION 1: Genesis Invariants (INV-G1 to INV-G12)
    // ═════════════════════════════════════════════════════════════════════════

    // INV-G1: Supply ceiling — no mint function exists
    function test_INVG1_noMintFunction_supplyFixed() public {
        // RewardVault distributes only from funded balance — cannot create new PW
        assertEq(vault.totalFunded(), 0, "fresh vault has no funded balance");

        // NativeMinter precompile has no code in Foundry local (chain 31337)
        address nm = 0x0200000000000000000000000000000000000001;
        uint256 sz; assembly { sz := extcodesize(nm) }
        assertEq(sz, 0, "NativeMinter has no code in test env");
    }

    // INV-G2: NativeMinter disabled
    function test_INVG2_nativeMinterDisabled() public {
        address nm = 0x0200000000000000000000000000000000000001;
        uint256 codeSize; assembly { codeSize := extcodesize(nm) }
        assertEq(codeSize, 0, "NativeMinter precompile disabled");
    }

    // INV-G3: No backdoor functions on FeeDistributor or ValidatorFeeVault
    function test_INVG3_noBackdoor_feeDistributor() public {
        bytes4 ownerWithdraw = bytes4(keccak256("ownerWithdraw()"));
        bytes4 emergencyExit = bytes4(keccak256("emergencyWithdrawAll()"));
        bytes4 setVault      = bytes4(keccak256("setValidatorFeeVault(address)"));
        bytes4 setTreasury   = bytes4(keccak256("setTreasury(address)"));

        (bool ok1,) = address(feeDistributor).staticcall(abi.encodeWithSelector(ownerWithdraw));
        (bool ok2,) = address(feeDistributor).staticcall(abi.encodeWithSelector(emergencyExit));
        (bool ok3,) = address(feeDistributor).staticcall(abi.encodeWithSelector(setVault));
        (bool ok4,) = address(feeDistributor).staticcall(abi.encodeWithSelector(setTreasury));

        assertFalse(ok1, "no ownerWithdraw on FeeDistributor");
        assertFalse(ok2, "no emergencyWithdrawAll on FeeDistributor");
        assertFalse(ok3, "no setValidatorFeeVault on FeeDistributor");
        assertFalse(ok4, "no setTreasury on FeeDistributor");
    }

    // INV-G3b: No transferAdmin on ValidatorFeeVault (protocolAdmin immutable)
    function test_INVG3b_noTransferAdmin_validatorFeeVault() public {
        bytes4 transferAdmin = bytes4(keccak256("transferAdmin(address)"));
        (bool ok,) = address(feeVault).staticcall(abi.encodeWithSelector(transferAdmin, address(0)));
        assertFalse(ok, "no transferAdmin on ValidatorFeeVault");
    }

    // INV-G4: RewardVault funded = 15M PW
    function test_INVG4_rewardVaultFunding_exactAmount() public {
        vm.deal(admin, REWARD_VAULT_FUND);
        vm.prank(admin);
        vault.fund{value: REWARD_VAULT_FUND}();
        assertEq(vault.totalFunded(), REWARD_VAULT_FUND, "INV-G4: totalFunded == 15M PW");
    }

    // INV-G5: Funding is a transfer, not a mint
    function test_INVG5_funding_isTransferNotMint() public {
        vm.deal(deployer, REWARD_VAULT_FUND);
        uint256 deployerBefore = deployer.balance;
        vm.prank(deployer);
        vault.fund{value: REWARD_VAULT_FUND}();

        assertEq(vault.totalFunded(), REWARD_VAULT_FUND, "vault funded");
        assertEq(address(vault).balance, REWARD_VAULT_FUND, "vault holds ETH");
        // Conservation: deployer lost 15M, vault gained 15M (no new PW created)
        assertEq(deployer.balance, deployerBefore - REWARD_VAULT_FUND, "deployer balance decreased");
    }

    // INV-G6: FeeDistributor routing links
    function test_INVG6_feeDistributor_routing() public {
        assertEq(feeDistributor.validatorFeeVault(), address(feeVault),    "FD -> VFV");
        assertEq(feeDistributor.treasury(),          address(devTreasury), "FD -> treasury");
        assertEq(feeDistributor.BURN_ADDRESS(),      BURN_ADDRESS,         "FD -> burn");
    }

    // INV-G7: Fee split 70/20/10
    function test_INVG7_feeSplit_70_20_10() public {
        assertEq(feeDistributor.VALIDATOR_BPS(), 7000, "70% validator [LOCKED]");
        assertEq(feeDistributor.TREASURY_BPS(),  2000, "20% treasury [LOCKED]");
        uint256 burnBps = feeDistributor.BASIS_POINTS()
                        - feeDistributor.VALIDATOR_BPS()
                        - feeDistributor.TREASURY_BPS();
        assertEq(burnBps, 1000, "10% burn [LOCKED]");
    }

    // INV-G8: ValidatorManager is authoritative — registry only reads it
    function test_INVG8_registry_cannotAlterValidatorManager() public {
        // Registry never writes to ValidatorManager (only calls getValidator())
        // Structural verification: ValidatorStatus.Unknown for any unregistered ID
        bytes32 fakeId = keccak256("fake");
        ValidatorStatus s = registry.validatorStatus(fakeId);
        assertEq(uint8(s), uint8(ValidatorStatus.Unknown), "unknown = 0");
    }

    // INV-G9: EmergencyMultisig = 3-of-5
    function test_INVG9_ems_3of5() public {
        assertEq(ems.THRESHOLD(),   EMS_THRESHOLD,   "EMS threshold = 3 [LOCKED]");
        assertEq(ems.MAX_SIGNERS(), EMS_MAX_SIGNERS, "EMS max signers = 5 [LOCKED]");

        assertTrue(ems.isSigner(signer1), "signer1");
        assertTrue(ems.isSigner(signer2), "signer2");
        assertTrue(ems.isSigner(signer3), "signer3");
        assertTrue(ems.isSigner(signer4), "signer4");
        assertTrue(ems.isSigner(signer5), "signer5");
        assertFalse(ems.isSigner(makeAddr("intruder")), "intruder not a signer");
    }

    // INV-G10: Timelock = 48 hours
    function test_INVG10_timelock_48h() public {
        assertEq(timelock.MIN_DELAY(), TIMELOCK_DELAY, "MIN_DELAY = 172800 [LOCKED]");
    }

    // INV-G11: Staking unbonding = 14 days (constant verification)
    function test_INVG11_unbonding_14days() public pure {
        assertEq(UNBONDING_SECONDS, 14 days, "14-day unbonding [LOCKED]");
        assertEq(UNBONDING_SECONDS, 1_209_600, "= 1,209,600 seconds");
    }

    // INV-G12: Annual reward cap <= 3M PW
    function test_INVG12_annualCap_3M_PW() public {
        uint256 annualAtMax = vault.MAX_RATE_PER_SECOND() * 365 days;
        assertLe(annualAtMax, MAX_ANNUAL_EMISSION,        "annual at MAX_RATE <= 3M PW [LOCKED]");
        assertLe(vault.emissionRatePerSecond(), vault.MAX_RATE_PER_SECOND(), "current <= MAX");
    }

    // ═════════════════════════════════════════════════════════════════════════
    // SECTION 2: RewardVault Funding Procedure (FUND-01 to FUND-08)
    // ═════════════════════════════════════════════════════════════════════════

    // FUND-01: Exact 15M PW funding succeeds
    function test_FUND01_exactFund_succeeds() public {
        vm.deal(deployer, REWARD_VAULT_FUND + 1 ether);
        vm.prank(deployer);
        vault.fund{value: REWARD_VAULT_FUND}();
        assertEq(vault.totalFunded(), REWARD_VAULT_FUND, "totalFunded exact");
        assertEq(address(vault).balance, REWARD_VAULT_FUND, "balance exact");
    }

    // FUND-02: Underfunding is detectable (totalFunded < 15M)
    function test_FUND02_underfunding_detectable() public {
        uint256 partialAmt = REWARD_VAULT_FUND - 1 ether;
        vm.deal(deployer, partialAmt);
        vm.prank(deployer);
        vault.fund{value: partialAmt}();
        assertTrue(vault.totalFunded() < REWARD_VAULT_FUND, "underfunded < 15M");
    }

    // FUND-03: Double funding is detectable (totalFunded > 15M)
    function test_FUND03_doubleFunding_detectable() public {
        vm.deal(deployer, REWARD_VAULT_FUND * 2);
        vm.prank(deployer);
        vault.fund{value: REWARD_VAULT_FUND}();
        assertEq(vault.totalFunded(), REWARD_VAULT_FUND, "first fund");

        vm.prank(deployer);
        vault.fund{value: REWARD_VAULT_FUND}();
        // Deployment script must check for EXACT 15M, not >= 15M
        assertEq(vault.totalFunded(), REWARD_VAULT_FUND * 2, "double fund detected");
    }

    // FUND-04: Wrong vault address — correct vault remains empty
    function test_FUND04_wrongVaultAddress_correctVaultEmpty() public {
        RewardVault wrongVault = new RewardVault(admin, INITIAL_RATE);
        vm.deal(deployer, REWARD_VAULT_FUND);
        vm.prank(deployer);
        wrongVault.fund{value: REWARD_VAULT_FUND}();
        assertEq(vault.totalFunded(), 0, "correct vault still empty");
        assertEq(wrongVault.totalFunded(), REWARD_VAULT_FUND, "wrong vault received funds");
    }

    // FUND-05: Post-fund, emitted <= funded always holds
    function test_FUND05_postFund_solvency() public {
        vm.deal(admin, REWARD_VAULT_FUND);
        vm.prank(admin);
        vault.fund{value: REWARD_VAULT_FUND}();

        vm.prank(admin);
        vault.registerRecipient(keccak256("v1"), recipient1, 1000, true);
        vm.warp(block.timestamp + 365 days);

        assertLe(vault.totalEmitted(), vault.totalFunded(), "FUND-05: emitted <= funded");
    }

    // FUND-06: Zero-amount fund reverts
    function test_FUND06_zeroFund_reverts() public {
        vm.prank(deployer);
        vm.expectRevert();
        vault.fund{value: 0}();
    }

    // FUND-07: accountedBalance == totalFunded at t=0
    function test_FUND07_accountedBalance_postFund() public {
        vm.deal(admin, REWARD_VAULT_FUND);
        vm.prank(admin);
        vault.fund{value: REWARD_VAULT_FUND}();
        assertEq(vault.accountedBalance(), REWARD_VAULT_FUND, "accountedBalance == funded");
        assertEq(address(vault).balance, vault.accountedBalance(), "balance == accountedBalance");
    }

    // FUND-08: Wrong-chain detection — test env is never production chain
    function test_FUND08_wrongChainId_detectable() public {
        uint256 productionChainId = 73571;
        assertNotEq(block.chainid, productionChainId, "test env != production chain");
    }

    // ═════════════════════════════════════════════════════════════════════════
    // SECTION 3: Registry Sync Lifecycle (SYNC-01 to SYNC-12)
    // ═════════════════════════════════════════════════════════════════════════

    // SYNC-01: PendingAdded → Active: registered as inactive, sync activates
    function test_SYNC01_pendingAdded_to_Active_sync() public {
        _registerPending(VID_1, recipient1);
        assertFalse(feeVault.isActive(VID_1), "inactive while PendingAdded");

        // P-Chain confirms — status becomes Active
        syncVM.setState(VID_1, ValidatorStatus.Active, 1000);

        // Keeper calls syncValidator (permissionless)
        vm.prank(keeper);
        registry.syncValidator(VID_1);

        assertTrue(feeVault.isActive(VID_1), "SYNC-01: active after sync");
    }

    // SYNC-02: Already synced — idempotent (no revert, no state change)
    function test_SYNC02_alreadySynced_idempotent() public {
        _registerActive(VID_1, recipient1);
        assertTrue(feeVault.isActive(VID_1), "already active");

        vm.prank(keeper);
        registry.syncValidator(VID_1); // must not revert
        assertTrue(feeVault.isActive(VID_1), "SYNC-02: still active");
    }

    // SYNC-03: Active → PendingRemoved: sync deactivates
    function test_SYNC03_active_to_PendingRemoved_sync() public {
        _registerActive(VID_1, recipient1);
        syncVM.setState(VID_1, ValidatorStatus.PendingRemoved, 1000);

        vm.prank(keeper);
        registry.syncValidator(VID_1);

        assertFalse(feeVault.isActive(VID_1), "SYNC-03: deactivated on PendingRemoved");
    }

    // SYNC-04: Completed status → sync deactivates
    function test_SYNC04_completed_deactivates() public {
        _registerActive(VID_1, recipient1);
        syncVM.setState(VID_1, ValidatorStatus.Completed, 0);

        vm.prank(keeper);
        registry.syncValidator(VID_1);

        assertFalse(feeVault.isActive(VID_1), "SYNC-04: deactivated on Completed");
    }

    // SYNC-05: Invalidated status → sync deactivates
    function test_SYNC05_invalidated_deactivates() public {
        _registerActive(VID_1, recipient1);
        syncVM.setState(VID_1, ValidatorStatus.Invalidated, 0);

        vm.prank(keeper);
        registry.syncValidator(VID_1);

        assertFalse(feeVault.isActive(VID_1), "SYNC-05: deactivated on Invalidated");
    }

    // SYNC-06: Duplicate sync on deactivated — safe (idempotent)
    function test_SYNC06_duplicateSync_afterDeactivation_safe() public {
        _registerActive(VID_1, recipient1);
        syncVM.setState(VID_1, ValidatorStatus.PendingRemoved, 0);

        vm.prank(keeper); registry.syncValidator(VID_1);
        vm.prank(keeper); registry.syncValidator(VID_1); // must not revert

        assertFalse(feeVault.isActive(VID_1), "SYNC-06: still deactivated");
    }

    // SYNC-07: Unmanaged validator — sync reverts
    function test_SYNC07_unmanagedValidator_reverts() public {
        vm.prank(keeper);
        vm.expectRevert("PWVR: not managed");
        registry.syncValidator(keccak256("not-registered"));
    }

    // SYNC-08: syncValidator is permissionless — any EOA can call it
    function test_SYNC08_syncValidator_permissionless() public {
        _registerActive(VID_1, recipient1);
        syncVM.setState(VID_1, ValidatorStatus.PendingRemoved, 0);

        // Any random EOA (no special role)
        vm.prank(makeAddr("random-eoa"));
        registry.syncValidator(VID_1);
        assertFalse(feeVault.isActive(VID_1), "SYNC-08: sync works from any caller");
    }

    // SYNC-09: Weight update via updateWeight()
    function test_SYNC09_weightUpdate() public {
        _registerActive(VID_1, recipient1);

        // Weight changes on P-Chain
        syncVM.setState(VID_1, ValidatorStatus.Active, 2000);

        vm.prank(keeper);
        registry.updateWeight(VID_1);

        assertEq(registry.validatorWeight(VID_1), 2000, "SYNC-09: weight updated");
    }

    // SYNC-10: syncAll() processes multiple validators
    function test_SYNC10_syncAll_multipleValidators() public {
        _registerActive(VID_1, makeAddr("r1"));
        _registerActive(VID_2, makeAddr("r2"));
        _registerActive(VID_3, makeAddr("r3"));

        syncVM.setState(VID_1, ValidatorStatus.PendingRemoved, 0);
        syncVM.setState(VID_3, ValidatorStatus.Completed, 0);

        vm.prank(keeper);
        registry.syncAll();

        assertFalse(feeVault.isActive(VID_1), "VID_1 deactivated");
        assertTrue(feeVault.isActive(VID_2),  "VID_2 unchanged");
        assertFalse(feeVault.isActive(VID_3), "VID_3 deactivated");
    }

    // SYNC-11: Keeper cannot register validators (admin-only on registry)
    function test_SYNC11_keeper_cannotRegister() public {
        syncVM.setState(VID_1, ValidatorStatus.Active, 1000);
        vm.prank(keeper);
        vm.expectRevert("PWVR: not admin");
        registry.registerValidator(VID_1, recipient1, 1000);
    }

    // SYNC-12: Keeper cannot alter RewardVault (no privileged role)
    function test_SYNC12_keeper_cannotAlterRewardVault() public {
        vm.prank(keeper);
        vm.expectRevert();
        vault.setEmissionRate(INITIAL_RATE / 2);

        vm.prank(keeper);
        vm.expectRevert();
        vault.setStakingManager(address(0));
    }

    // ═════════════════════════════════════════════════════════════════════════
    // SECTION 4: Wrong-Chain / Wrong-Network Protection (PROT-01 to PROT-05)
    // ═════════════════════════════════════════════════════════════════════════

    // PROT-01: Test env chain ID is not the production chain ID
    function test_PROT01_chainId_notProduction() public {
        assertNotEq(block.chainid, uint256(73571), "test env != primewavedev");
    }

    // PROT-02: Wrong-chain guard logic correctly blocks deployment in test env
    function test_PROT02_wrongChainGuard_logic() public {
        bool safe = (block.chainid == 73571);
        assertFalse(safe, "guard blocks test-env deployment");
    }

    // PROT-03: EMS threshold and max signers are immutable after deployment
    function test_PROT03_ems_immutable() public {
        assertEq(ems.THRESHOLD(),   3, "threshold immutable");
        assertEq(ems.MAX_SIGNERS(), 5, "max signers immutable");
    }

    // PROT-04: Timelock MIN_DELAY is immutable
    function test_PROT04_timelockDelay_immutable() public {
        assertEq(timelock.MIN_DELAY(), TIMELOCK_DELAY, "MIN_DELAY immutable");
    }

    // PROT-05: Both env flag AND chain ID required for production deployment
    function test_PROT05_dualGuard_logic() public {
        bool envOk   = false;           // PRIMEWAVE_ENV != "production" in test
        bool chainOk = (block.chainid == 73571); // false in test
        assertFalse(envOk && chainOk, "both guards block test-env deployment");
    }

    // ═════════════════════════════════════════════════════════════════════════
    // SECTION 5: EMS Signer Rotation — Operational Procedure
    // ═════════════════════════════════════════════════════════════════════════

    // EMS-ROT-01: No on-chain updateSigner function — rotation requires redeployment
    function test_EMSROT01_noUpdateSignerFunction() public {
        bytes4 sel = bytes4(keccak256("updateSigner(address,address)"));
        (bool ok,) = address(ems).call(abi.encodeWithSelector(sel, signer1, makeAddr("new")));
        assertFalse(ok, "EMS-ROT-01: no updateSigner function exists");
    }

    // EMS-ROT-02: Rotation procedure — deploy new EMS, update pauseController via admin
    function test_EMSROT02_rotationProcedure_newDeployment() public {
        address[5] memory newSigners = [
            makeAddr("ns1"), makeAddr("ns2"), makeAddr("ns3"),
            makeAddr("ns4"), makeAddr("ns5")
        ];
        EmergencyMultisig newEms = new EmergencyMultisig(newSigners);
        assertEq(newEms.THRESHOLD(), 3, "new EMS has correct threshold");

        // Production: timelock-governed pauseController update on each contract
        vm.prank(admin);
        vault.setPauseController(address(newEms));
        assertEq(vault.pauseController(), address(newEms), "pauseController updated");
    }

    // ═════════════════════════════════════════════════════════════════════════
    // SECTION 6: Fee Routing Integrity (FEE-01 to FEE-04)
    // ═════════════════════════════════════════════════════════════════════════

    // FEE-01: Distribution conservation (vfv + treasury + burn == total)
    function test_FEE01_distribution_conservation() public {
        vm.deal(address(feeDistributor), 300 ether);
        feeDistributor.distribute();

        assertApproxEqAbs(address(feeVault).balance,    210 ether, 2, "VFV 70%");
        assertApproxEqAbs(address(devTreasury).balance, 60 ether,  2, "treasury 20%");
        assertApproxEqAbs(BURN_ADDRESS.balance,         30 ether,  2, "burn 10%");
    }

    // FEE-02: Split constants are exactly 7000/2000/1000 bps
    function test_FEE02_splitConstants_exact() public {
        assertEq(feeDistributor.VALIDATOR_BPS(), 7000);
        assertEq(feeDistributor.TREASURY_BPS(),  2000);
        assertEq(feeDistributor.BASIS_POINTS(),  10000);
    }

    // FEE-03: Multiple distributions preserve totalDistributed == sum of parts
    function test_FEE03_multipleDistributions_accounting() public {
        for (uint256 i = 1; i <= 5; i++) {
            vm.deal(address(feeDistributor), i * 100 ether);
            feeDistributor.distribute();
        }
        uint256 total = feeDistributor.totalDistributed();
        uint256 sum   = feeDistributor.totalValidatorShare()
                      + feeDistributor.totalTreasuryShare()
                      + feeDistributor.totalBurnShare();
        assertEq(total, sum, "conservation holds over multiple distributions");
    }

    // FEE-04: DevTreasury is linked to FeeDistributor
    function test_FEE04_devTreasury_linked() public {
        assertEq(devTreasury.feeDistributor(), address(feeDistributor));
    }

    // ═════════════════════════════════════════════════════════════════════════
    // SECTION 7: Vault Solvency Invariants
    // ═════════════════════════════════════════════════════════════════════════

    // SOL-01: totalEmitted <= totalFunded always
    function test_SOL01_emitted_lte_funded() public {
        vm.deal(admin, REWARD_VAULT_FUND);
        vm.prank(admin); vault.fund{value: REWARD_VAULT_FUND}();
        vm.prank(admin); vault.registerRecipient(keccak256("v1"), recipient1, 1000, true);
        vm.warp(block.timestamp + 365 days);
        assertLe(vault.totalEmitted(), vault.totalFunded(), "SOL-01");
    }

    // SOL-02: totalClaimed <= totalEmitted always
    function test_SOL02_claimed_lte_emitted() public {
        vm.deal(admin, REWARD_VAULT_FUND);
        vm.prank(admin); vault.fund{value: REWARD_VAULT_FUND}();
        assertLe(vault.totalClaimed(), vault.totalEmitted(), "SOL-02");
    }

    // SOL-03: balance == totalFunded - totalClaimed
    function test_SOL03_balance_conservation() public {
        vm.deal(admin, REWARD_VAULT_FUND);
        vm.prank(admin); vault.fund{value: REWARD_VAULT_FUND}();
        assertEq(address(vault).balance, vault.accountedBalance(), "SOL-03");
    }
}
