// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// ============================================================
// ValidatorFeeVault — PW-C04 Validator Fee Accounting
// ============================================================
//
// PURPOSE (C04):
//   Combined vault + per-validator accounting for the 70%
//   validator share of transaction-fee economics.
//
//   Architecture:
//     FeeDistributor.distribute()
//           │ 70%
//           ▼
//     ValidatorFeeVault.receive()          ← updates global index
//           │
//           ├── accFeePerWeight increases
//           │
//           └── Validators pull their share via claimFees()
//
// ACCOUNTING MODEL:
//   Reward-index algorithm (same as Synthetix / Compound):
//   - accFeePerWeight: global cumulative fee per unit of effective weight,
//     scaled by PRECISION (1e18) to preserve fixed-point precision.
//   - effectiveWeight(v) = baseWeight × uptimeBips / 10_000
//   - Claimable(v) = (accFeePerWeight − rewardDebt[v]) × ew(v) / PRECISION
//                   + pendingReward[v]
//
//   O(1) fee accrual per receive() call.
//   O(1) claim per validator.
//   No loop over all validators on any operation.
//
// ROUNDING:
//   Floor division at every step. Dust (< 1 wei per distribution
//   per unit of totalEffectiveWeight) accumulates in the vault
//   implicitly and is never lost. The conservation invariant holds:
//     balance ≥ totalClaimable + unallocated
//     balance = totalReceived − totalClaimed (exact)
//
// UPTIME:
//   Binary or fractional. Represented as uptimeBips ∈ [0, 10_000].
//   uptimeBips = 10_000  → 100% uptime, full weight eligible.
//   uptimeBips = 0       → ineligible; effectiveWeight = 0.
//   Phase 1 default: 10_000 (fully eligible PoA validators).
//
// ACCESS CONTROL:
//   protocolAdmin (dev: DEV0 EOA; prod: multisig+timelock) controls:
//     - registerValidator
//     - deactivateValidator / activateValidator
//     - setUptimeBips / setBaseWeight
//     - distributeUnallocated
//   Anyone can call claimFees(validationId), but only the registered
//   rewardRecipient receives the native PW.
//
// FUTURE PoS INTEGRATION:
//   In Phase 2, protocolAdmin will be replaced by PrimeWaveStakingManager
//   which drives weight/uptime from on-chain Warp-verified data.
//   The accounting interface (this contract) remains unchanged.
//
// WHAT C04 DOES NOT IMPLEMENT:
//   - Staking, delegation, unbonding, slashing
//   - RewardVault (15M PW staking reserve — separate mechanism)
//   - Production multisig or governance
//   - NativeMinter interaction
//
// ENVIRONMENT: LOCAL DEVELOPMENT ONLY — NOT FOR MAINNET
// ============================================================

contract ValidatorFeeVault {

    // ── Reentrancy guard (inline — no OZ dependency) ─────────────────────────

    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED     = 2;
    uint256 private _reentrancyStatus = _NOT_ENTERED;

    modifier nonReentrant() {
        require(_reentrancyStatus == _NOT_ENTERED, "VFV: reentrant call");
        _reentrancyStatus = _ENTERED;
        _;
        _reentrancyStatus = _NOT_ENTERED;
    }

    // ── Constants ────────────────────────────────────────────────────────────

    /// @notice Fixed-point precision for the reward index.
    uint256 public constant PRECISION = 1e18;

    /// @notice Maximum uptime/eligibility in basis points (100% = 10_000).
    uint16 public constant MAX_UPTIME_BIPS = 10_000;

    // ── Access control ────────────────────────────────────────────────────────

    /// @notice Development-phase admin (DEV0 EOA → Phase 2: multisig+timelock).
    address public immutable protocolAdmin;

    modifier onlyAdmin() {
        require(msg.sender == protocolAdmin, "VFV: not admin");
        _;
    }

    // ── Pause state (C07 Emergency Governance) ────────────────────────────────

    /// @notice Whether fee claims are currently paused.
    ///         When true: claimFees() reverts. Accounting (receive, register, etc.) unaffected.
    bool public paused;

    /// @notice Address authorized to call pause() and unpause().
    ///         Set via setPauseController() by protocolAdmin or current pauseController.
    ///         address(0) = no pause controller; pause() and unpause() always revert.
    address public pauseController;

    modifier onlyPauseController() {
        require(
            msg.sender == pauseController && pauseController != address(0),
            "VFV: not pause controller"
        );
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "VFV: paused");
        _;
    }

    // ── Events (C07 additions) ────────────────────────────────────────────────

    /// @notice Emitted when fee claims are paused.
    event Paused(address indexed by);

    /// @notice Emitted when fee claims are unpaused.
    event Unpaused(address indexed by);

    /// @notice Emitted when the pauseController is updated.
    event PauseControllerUpdated(address indexed oldController, address indexed newController);

    // ── Validator registry ─────────────────────────────────────────────────────

    /// @notice Per-validator accounting record.
    struct ValidatorInfo {
        /// @dev EVM address to which claimed PW is transferred.
        address rewardRecipient;
        /// @dev Raw consensus/economic weight. Equal for all Phase 1 validators.
        uint128 baseWeight;
        /// @dev Eligibility factor in bips [0, 10_000]. effectiveWeight = base × bips / 10_000.
        uint16  uptimeBips;
        /// @dev True when validator is actively accruing fees.
        bool    active;
        /// @dev Global accFeePerWeight snapshot at last checkpoint. Scaled by PRECISION.
        uint256 rewardDebt;
        /// @dev Checkpointed but not yet claimed PW (wei).
        uint256 pendingReward;
        /// @dev Cumulative PW claimed by this validator (wei).
        uint256 totalClaimed;
    }

    /// @notice validationId → ValidatorInfo. validationId == 0 means unregistered.
    mapping(bytes32 => ValidatorInfo) public validators;

    /// @notice Ordered list of all registered validationIds (for enumeration / tests).
    bytes32[] public validationIds;

    // ── Global accounting state ────────────────────────────────────────────────

    /// @notice Global fee-per-unit-weight index, scaled by PRECISION.
    ///         Monotonically non-decreasing.
    uint256 public accFeePerWeight;

    /// @notice Sum of effectiveWeight for all currently active validators.
    ///         effectiveWeight(v) = baseWeight × uptimeBips / MAX_UPTIME_BIPS.
    uint256 public totalEffectiveWeight;

    /// @notice Cumulative PW received by this vault (wei).
    uint256 public totalReceived;

    /// @notice Cumulative PW paid out via claimFees() (wei).
    uint256 public totalClaimed;

    /// @notice PW accumulated during periods when totalEffectiveWeight == 0.
    ///         Distributed via distributeUnallocated() once validators are active.
    uint256 public unallocated;

    // ── Events ────────────────────────────────────────────────────────────────

    /// @notice A new validator was registered and is immediately active.
    event ValidatorRegistered(
        bytes32 indexed validationId,
        address indexed rewardRecipient,
        uint128 baseWeight,
        uint16  uptimeBips
    );

    /// @notice A deactivated validator was re-activated.
    event ValidatorActivated(bytes32 indexed validationId);

    /// @notice A validator was deactivated. Its pending fees remain claimable.
    event ValidatorDeactivated(bytes32 indexed validationId, uint256 checkpointedReward);

    /// @notice A validator's weight or uptime was updated.
    event ValidatorUpdated(bytes32 indexed validationId, uint128 baseWeight, uint16 uptimeBips);

    /// @notice PW received from FeeDistributor; global index updated.
    event FeeReceived(uint256 amount, uint256 newAccFeePerWeight, uint256 totalEffectiveWeight);

    /// @notice New fees checkpointed into a validator's pendingReward.
    event FeeAccrued(bytes32 indexed validationId, uint256 amount);

    /// @notice A validator's reward recipient was updated by admin.
    event ValidatorRecipientUpdated(bytes32 indexed validationId, address indexed newRecipient);

    /// @notice A validator's accumulated fees were claimed.
    event ValidatorFeeClaimed(
        bytes32 indexed validationId,
        address indexed recipient,
        uint256 amount
    );

    /// @notice Previously unallocated fees were distributed into the global index.
    event UnallocatedDistributed(uint256 amount);

    // ── Constructor ───────────────────────────────────────────────────────────

    /// @param _protocolAdmin Dev EOA (DEV0) or future multisig+timelock.
    constructor(address _protocolAdmin) {
        require(_protocolAdmin != address(0), "VFV: zero admin");
        protocolAdmin = _protocolAdmin;
    }

    // ── Receive ───────────────────────────────────────────────────────────────

    /// @notice Accept PW from FeeDistributor. Updates the global reward index.
    /// @dev    Called by FeeDistributor.distribute() via .call{value:...}("").
    ///         AvalancheGo AddBalance() does NOT trigger receive() — that path
    ///         only applies to the FeeDistributor itself.
    receive() external payable {
        totalReceived += msg.value;
        _accrueGlobal(msg.value);
        emit FeeReceived(msg.value, accFeePerWeight, totalEffectiveWeight);
    }

    // ── Internal: accounting ──────────────────────────────────────────────────

    /// @dev Compute effective weight for a validator (0 if inactive or uptimeBips==0).
    function _effectiveWeight(bytes32 id) internal view returns (uint256) {
        ValidatorInfo storage v = validators[id];
        if (!v.active) return 0;
        return uint256(v.baseWeight) * uint256(v.uptimeBips) / MAX_UPTIME_BIPS;
    }

    /// @dev Update global accFeePerWeight for `amount` new PW.
    ///      If no active weight, accumulate in `unallocated`.
    function _accrueGlobal(uint256 amount) internal {
        if (totalEffectiveWeight == 0) {
            unallocated += amount;
            return;
        }
        // Scale by PRECISION to keep sub-unit precision.
        // Integer division floors: dust stays in vault implicitly.
        accFeePerWeight += amount * PRECISION / totalEffectiveWeight;
    }

    /// @dev Checkpoint a validator's earned fees into pendingReward.
    ///      Safe to call even if effectiveWeight == 0 (will update rewardDebt).
    function _checkpoint(bytes32 id) internal {
        ValidatorInfo storage v = validators[id];
        uint256 ew = _effectiveWeight(id);
        if (ew > 0) {
            uint256 earned = (accFeePerWeight - v.rewardDebt) * ew / PRECISION;
            if (earned > 0) {
                v.pendingReward += earned;
                emit FeeAccrued(id, earned);
            }
        }
        v.rewardDebt = accFeePerWeight;
    }

    // ── Pause functions (C07) ─────────────────────────────────────────────────

    /// @notice Authorize a new pause controller.
    ///         Callable by protocolAdmin (to initialize) OR by current pauseController
    ///         (to rotate). Setting to address(0) disables pause capability.
    function setPauseController(address newController) external {
        require(
            msg.sender == protocolAdmin ||
            (pauseController != address(0) && msg.sender == pauseController),
            "VFV: unauthorized"
        );
        address old = pauseController;
        pauseController = newController;
        emit PauseControllerUpdated(old, newController);
    }

    /// @notice Pause fee claims. Only callable by pauseController.
    ///         Accounting (receive, register, sync, weight updates) is NOT affected.
    function pause() external onlyPauseController {
        require(!paused, "VFV: already paused");
        paused = true;
        emit Paused(msg.sender);
    }

    /// @notice Resume fee claims. Only callable by pauseController.
    function unpause() external onlyPauseController {
        require(paused, "VFV: not paused");
        paused = false;
        emit Unpaused(msg.sender);
    }

    // ── Admin: validator lifecycle ─────────────────────────────────────────────

    /// @notice Register a new validator. Immediately active from current index.
    /// @param  validationId    Unique identifier (e.g. keccak256 of Avalanche NodeID+BLS).
    /// @param  rewardRecipient EVM address that will receive claimed PW.
    /// @param  baseWeight      Consensus/economic weight (use 1 for equal-weight Phase 1).
    /// @param  uptimeBips      Initial eligibility [0, 10_000]. Phase 1: 10_000.
    function registerValidator(
        bytes32 validationId,
        address rewardRecipient,
        uint128 baseWeight,
        uint16  uptimeBips
    ) external onlyAdmin {
        require(validationId != bytes32(0),                         "VFV: zero validationId");
        require(rewardRecipient != address(0),                      "VFV: zero recipient");
        require(validators[validationId].rewardRecipient == address(0), "VFV: already registered");
        require(uptimeBips <= MAX_UPTIME_BIPS,                     "VFV: uptimeBips > 10_000");
        require(baseWeight > 0,                                     "VFV: zero baseWeight");

        uint256 ew = uint256(baseWeight) * uint256(uptimeBips) / MAX_UPTIME_BIPS;

        validators[validationId] = ValidatorInfo({
            rewardRecipient: rewardRecipient,
            baseWeight:      baseWeight,
            uptimeBips:      uptimeBips,
            active:          true,
            rewardDebt:      accFeePerWeight, // only earns from fees arriving after registration
            pendingReward:   0,
            totalClaimed:    0
        });
        validationIds.push(validationId);
        totalEffectiveWeight += ew;

        emit ValidatorRegistered(validationId, rewardRecipient, baseWeight, uptimeBips);
    }

    /// @notice Deactivate a validator. Checkpoints earned fees; stops future accrual.
    ///         Previously earned pendingReward remains claimable.
    function deactivateValidator(bytes32 validationId) external onlyAdmin {
        ValidatorInfo storage v = validators[validationId];
        require(v.rewardRecipient != address(0), "VFV: not registered");
        require(v.active,                        "VFV: already inactive");

        // Checkpoint BEFORE updating active/weight (effectiveWeight uses v.active)
        _checkpoint(validationId);

        // Remove from totalEffectiveWeight (must happen after checkpoint)
        uint256 ew = uint256(v.baseWeight) * uint256(v.uptimeBips) / MAX_UPTIME_BIPS;
        totalEffectiveWeight -= ew;
        v.active = false;

        emit ValidatorDeactivated(validationId, v.pendingReward);
    }

    /// @notice Re-activate a deactivated validator. Starts accruing from current index.
    ///         Does NOT retroactively earn fees from the inactive period.
    function activateValidator(bytes32 validationId) external onlyAdmin {
        ValidatorInfo storage v = validators[validationId];
        require(v.rewardRecipient != address(0), "VFV: not registered");
        require(!v.active,                       "VFV: already active");

        v.active = true;
        uint256 ew = uint256(v.baseWeight) * uint256(v.uptimeBips) / MAX_UPTIME_BIPS;
        totalEffectiveWeight += ew;
        v.rewardDebt = accFeePerWeight; // no retro-accrual for inactive period

        emit ValidatorActivated(validationId);
    }

    /// @notice Update a validator's uptime/eligibility factor.
    ///         Checkpoints current earnings before changing the weight.
    function setUptimeBips(bytes32 validationId, uint16 newUptimeBips) external onlyAdmin {
        require(newUptimeBips <= MAX_UPTIME_BIPS, "VFV: uptimeBips > 10_000");
        ValidatorInfo storage v = validators[validationId];
        require(v.rewardRecipient != address(0),  "VFV: not registered");

        if (v.active) {
            _checkpoint(validationId);
            // Remove old effective weight
            uint256 oldEw = uint256(v.baseWeight) * uint256(v.uptimeBips) / MAX_UPTIME_BIPS;
            totalEffectiveWeight -= oldEw;
            v.uptimeBips = newUptimeBips;
            // Add new effective weight
            uint256 newEw = uint256(v.baseWeight) * uint256(newUptimeBips) / MAX_UPTIME_BIPS;
            totalEffectiveWeight += newEw;
        } else {
            v.uptimeBips = newUptimeBips;
        }

        emit ValidatorUpdated(validationId, v.baseWeight, newUptimeBips);
    }

    /// @notice Update a validator's base economic weight.
    ///         Checkpoints current earnings before changing the weight.
    function setBaseWeight(bytes32 validationId, uint128 newBaseWeight) external onlyAdmin {
        require(newBaseWeight > 0,                 "VFV: zero baseWeight");
        ValidatorInfo storage v = validators[validationId];
        require(v.rewardRecipient != address(0),   "VFV: not registered");

        if (v.active) {
            _checkpoint(validationId);
            uint256 oldEw = uint256(v.baseWeight) * uint256(v.uptimeBips) / MAX_UPTIME_BIPS;
            totalEffectiveWeight -= oldEw;
            v.baseWeight = newBaseWeight;
            uint256 newEw = uint256(newBaseWeight) * uint256(v.uptimeBips) / MAX_UPTIME_BIPS;
            totalEffectiveWeight += newEw;
        } else {
            v.baseWeight = newBaseWeight;
        }

        emit ValidatorUpdated(validationId, newBaseWeight, v.uptimeBips);
    }

    /// @notice Distribute previously unallocated fees (received when no validators were active).
    ///         Any account may call this; requires at least one active validator.
    function distributeUnallocated() external {
        require(totalEffectiveWeight > 0, "VFV: no active weight");
        require(unallocated > 0,          "VFV: nothing unallocated");
        uint256 amount = unallocated;
        unallocated = 0;
        _accrueGlobal(amount);
        emit UnallocatedDistributed(amount);
    }

    // ── Claim ─────────────────────────────────────────────────────────────────

    /// @notice Pull-claim earned fees for a validator.
    ///         Only callable by the validator's registered rewardRecipient.
    /// @param  validationId The validator to claim for.
    /// @return amount       Native PW transferred (wei).
    function claimFees(bytes32 validationId)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 amount)
    {
        ValidatorInfo storage v = validators[validationId];
        require(v.rewardRecipient != address(0), "VFV: not registered");
        require(msg.sender == v.rewardRecipient, "VFV: caller is not recipient");

        _checkpoint(validationId);
        amount = v.pendingReward;
        require(amount > 0, "VFV: nothing to claim");

        // CEI: zero before transfer
        v.pendingReward  = 0;
        v.totalClaimed  += amount;
        totalClaimed    += amount;

        (bool ok, ) = v.rewardRecipient.call{value: amount}("");
        require(ok, "VFV: transfer failed");

        emit ValidatorFeeClaimed(validationId, v.rewardRecipient, amount);
    }

    // ── View functions ─────────────────────────────────────────────────────────

    /// @notice Current claimable amount for a validator (live, no storage write).
    function claimable(bytes32 validationId) external view returns (uint256) {
        ValidatorInfo storage v = validators[validationId];
        if (v.rewardRecipient == address(0)) return 0;
        uint256 pending = v.pendingReward;
        if (v.active) {
            uint256 ew = _effectiveWeight(validationId);
            if (ew > 0) {
                pending += (accFeePerWeight - v.rewardDebt) * ew / PRECISION;
            }
        }
        return pending;
    }

    /// @notice Sum of claimable() across all registered validators.
    ///         O(n) — use off-chain or in tests only.
    function totalClaimableView() external view returns (uint256 total) {
        for (uint256 i = 0; i < validationIds.length; i++) {
            total += this.claimable(validationIds[i]);
        }
    }

    /// @notice Total number of registered validators.
    function validatorCount() external view returns (uint256) {
        return validationIds.length;
    }

    /// @notice Current native PW balance of this vault.
    function vaultBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /// @notice Cumulative fees received minus claimed. Equals balance exactly.
    function netReceived() external view returns (uint256) {
        return totalReceived - totalClaimed;
    }

    /// @notice Update the reward recipient for a registered validator.
    ///         Admin-only. Old recipient should claim any earned fees first.
    ///         Future fee claims will be sent to newRecipient.
    /// @dev    Added in C05 for PrimeWaveValidatorRegistry recipient-rotation support.
    function setRewardRecipient(bytes32 validationId, address newRecipient) external onlyAdmin {
        require(newRecipient != address(0), "VFV: zero recipient");
        ValidatorInfo storage v = validators[validationId];
        require(v.rewardRecipient != address(0), "VFV: not registered");
        v.rewardRecipient = newRecipient;
        emit ValidatorRecipientUpdated(validationId, newRecipient);
    }

    /// @notice Whether a validator is currently active (accruing fees).
    ///         Convenience view for PrimeWaveValidatorRegistry.syncValidator().
    /// @dev    Added in C05 to avoid cross-contract struct decoding.
    function isActive(bytes32 validationId) external view returns (bool) {
        return validators[validationId].active;
    }

    /// @notice Conservation check: balance − claimable − unallocated ≥ 0 (rounding dust).
    function roundingDust() external view returns (uint256) {
        uint256 bal = address(this).balance;
        uint256 tc  = this.totalClaimableView();
        uint256 u   = unallocated;
        if (bal >= tc + u) return bal - tc - u;
        return 0; // should never underflow; returns 0 on pathological input
    }
}
