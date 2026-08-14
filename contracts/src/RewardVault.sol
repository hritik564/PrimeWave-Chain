// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// ============================================================
// RewardVault  --  PW-C06
// ============================================================
//
// PURPOSE:
//   Distribute the 15,000,000 PW pre-funded staking/validator reward
//   reserve at a maximum rate of 3,000,000 PW/year.
//
// FUNDAMENTAL INVARIANTS:
//   1. NO MINTING. Rewards come ONLY from pre-funded PW. No NativeMinter.
//      No mint(). No inflation. Total PW supply never increases.
//   2. totalEmitted <= totalFunded  (cannot emit more than deposited)
//   3. totalClaimed <= totalEmitted (cannot claim more than accrued)
//   4. emissionRatePerSecond <= MAX_RATE_PER_SECOND at all times
//   5. balance = totalFunded - totalClaimed (exact accounting)
//
// EMISSION MODEL:
//   - Continuous per-second rate: rewards accrue based on elapsed time.
//   - MAX_RATE_PER_SECOND = 3,000,000 PW / 31,536,000 s/year (floor).
//   - Actual rate per year at max: 95,129,375,951,293,760 * 31,536,000
//     = 2,999,999,999,999,999,994,880,000,000 wei ~= 3,000,000 PW.
//     The fractional remainder (~5.12e-9 PW/year) stays in the vault.
//   - Rate can be REDUCED by admin. Never increased above MAX.
//   - Zero-weight periods: emission pauses (rewards accumulate as latent
//     vault balance; they do NOT disappear or go to unallocated).
//
// REWARD INDEX MODEL (same as ValidatorFeeVault C04):
//   - accRewardPerWeight increases each epoch: += emitted * PRECISION / totalWeight
//   - Each recipient's claimable = (accRewardPerWeight - rewardDebt) * weight / PRECISION
//     + pendingReward
//
// FORCED TRANSFERS:
//   - Only PW received via fund() / receive() is counted in totalFunded.
//   - PW arriving via selfdestruct or other forced mechanisms is NOT
//     accounted in totalFunded and therefore cannot be emitted or claimed.
//     It remains locked in the vault balance as unaccounted surplus.
//
// RECIPIENT MODEL (C06 dev-only):
//   - Admin registers recipients (bytes32 ID + rewardAddress + weight).
//   - Future PrimeWaveStakingManager will use the same interface.
//   - See §41 of C06 spec for Phase-2 integration boundary.
//
// SEPARATE FROM ValidatorFeeVault:
//   - RewardVault distributes pre-funded staking reserves.
//   - ValidatorFeeVault distributes gas fee revenue.
//   - These MUST NOT be connected.
//
// ENVIRONMENT: LOCAL DEVELOPMENT  --  NOT FOR MAINNET
// ============================================================

contract RewardVault {

    // ── Constants ────────────────────────────────────────────────────────────

    /// @notice Seconds in a 365-day year (non-leap).
    uint256 public constant SECONDS_PER_YEAR = 365 * 24 * 60 * 60; // 31_536_000

    /// @notice Maximum annual emission: 3,000,000 PW (in wei).
    uint256 public constant MAX_ANNUAL_EMISSION = 3_000_000 ether;

    /// @notice Maximum emission rate per second (floor division  --  dust stays in vault).
    ///         = 3,000,000e18 / 31,536,000
    ///         = 95,129,375,951,293,760 wei/second
    /// @dev    Over exactly one year: 95_129_375_951_293_760 * 31_536_000
    ///         = 2,999,999,999,999,999,994,880,000,000 wei
    ///         ~= 3,000,000 PW (off by ~5.12e-9 PW/year  --  remains in vault).
    uint256 public constant MAX_RATE_PER_SECOND = MAX_ANNUAL_EMISSION / SECONDS_PER_YEAR;

    /// @notice Fixed-point precision for reward index.
    uint256 public constant PRECISION = 1e18;

    // ── Immutables ────────────────────────────────────────────────────────────

    /// @notice Protocol admin (DEV0 in dev; multisig+timelock in production).
    address public immutable admin;

    // ── Emission state ────────────────────────────────────────────────────────

    /// @notice Current emission rate in wei/second. <= MAX_RATE_PER_SECOND.
    ///         Admin can only reduce; never increase above MAX.
    uint256 public emissionRatePerSecond;

    /// @notice Timestamp of the last global state update.
    uint256 public lastUpdateTime;

    /// @notice Global reward index: total PW emitted per unit of weight since genesis,
    ///         scaled by PRECISION. Monotonically non-decreasing.
    uint256 public accRewardPerWeight;

    /// @notice Current total eligible weight (sum of all active recipients' weights).
    uint256 public totalEligibleWeight;

    // ── Accounting ────────────────────────────────────────────────────────────

    /// @notice Total PW received via fund() (nat PW deposited). Never decreases.
    uint256 public totalFunded;

    /// @notice Total PW accrued into the reward index (including unclaimed).
    ///         totalEmitted <= totalFunded always.
    uint256 public totalEmitted;

    /// @notice Total PW actually claimed (transferred out).
    ///         totalClaimed <= totalEmitted always.
    uint256 public totalClaimed;

    // ── Recipient state ───────────────────────────────────────────────────────

    struct RecipientInfo {
        /// @dev Whether this recipient currently accrues rewards.
        bool    active;

        /// @dev Consensus/staking weight used for proportional reward distribution.
        uint128 weight;

        /// @dev Snapshot of accRewardPerWeight at the time of last checkpoint.
        uint256 rewardDebt;

        /// @dev Accrued but unclaimed rewards (wei).
        uint256 pendingReward;

        /// @dev Total rewards claimed by this recipient (for accounting).
        uint256 totalClaimed;

        /// @dev EVM address where claimed PW is sent.
        address rewardAddress;
    }

    /// @notice Per-recipient accounting state.
    mapping(bytes32 => RecipientInfo) public recipients;

    /// @notice Ordered list of registered recipient IDs (for enumeration / syncing).
    bytes32[] public recipientList;

    /// @notice Whether a recipient ID has been registered.
    mapping(bytes32 => bool) public isRegistered;

    // ── Reentrancy guard ───────────────────────────────────────────────────────

    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED     = 2;
    uint256 private _reentrancyStatus     = _NOT_ENTERED;

    modifier nonReentrant() {
        require(_reentrancyStatus == _NOT_ENTERED, "RV: reentrant call");
        _reentrancyStatus = _ENTERED;
        _;
        _reentrancyStatus = _NOT_ENTERED;
    }

    // ── Access control ────────────────────────────────────────────────────────

    modifier onlyAdmin() {
        require(msg.sender == admin, "RV: not admin");
        _;
    }

    // ── Events ────────────────────────────────────────────────────────────────

    /// @notice PW was funded into the vault.
    event RewardVaultFunded(address indexed funder, uint256 amount, uint256 newTotalFunded);

    /// @notice Global reward index was updated (rewards emitted to index).
    event GlobalUpdated(uint256 emitted, uint256 newAccRewardPerWeight, uint256 totalEligibleWeight);

    /// @notice A recipient claimed their rewards.
    event RewardClaimed(bytes32 indexed recipientId, address indexed rewardAddress, uint256 amount);

    /// @notice Emission rate was reduced.
    event EmissionRateReduced(uint256 oldRatePerSecond, uint256 newRatePerSecond);

    /// @notice A new recipient was registered.
    event RecipientRegistered(
        bytes32 indexed recipientId,
        address indexed rewardAddress,
        uint128 weight,
        bool    startActive
    );

    /// @notice A recipient's weight was updated.
    event RecipientWeightUpdated(bytes32 indexed recipientId, uint128 oldWeight, uint128 newWeight);

    /// @notice A recipient was activated (began accruing rewards).
    event RecipientActivated(bytes32 indexed recipientId);

    /// @notice A recipient was deactivated (stopped accruing rewards; earned fees preserved).
    event RecipientDeactivated(bytes32 indexed recipientId, uint256 checkpointed);

    /// @notice A recipient's reward address was changed.
    event RecipientAddressUpdated(bytes32 indexed recipientId, address indexed newRewardAddress);

    // ── Constructor ───────────────────────────────────────────────────────────

    /// @param _admin       Protocol admin (DEV0 EOA in dev; multisig+timelock in production).
    /// @param _initialRate Initial emission rate in wei/second. Must be <= MAX_RATE_PER_SECOND.
    constructor(address _admin, uint256 _initialRate) {
        require(_admin != address(0),                          "RV: zero admin");
        require(_initialRate <= MAX_RATE_PER_SECOND,           "RV: rate exceeds max");

        admin                = _admin;
        emissionRatePerSecond = _initialRate;
        lastUpdateTime       = block.timestamp;
    }

    // ── Funding ───────────────────────────────────────────────────────────────

    /// @notice Deposit native PW into the RewardVault.
    ///         Counted in totalFunded. Only funded PW can ever be emitted or claimed.
    /// @dev    Can be called by anyone (Genesis allocation, admin top-up, etc.).
    function fund() external payable {
        require(msg.value > 0, "RV: zero funding");
        totalFunded += msg.value;
        emit RewardVaultFunded(msg.sender, msg.value, totalFunded);
    }

    /// @notice Accept native PW sent directly (e.g., from genesis alloc or plain transfer).
    receive() external payable {
        if (msg.value > 0) {
            totalFunded += msg.value;
            emit RewardVaultFunded(msg.sender, msg.value, totalFunded);
        }
    }

    // ── Internal: global update ────────────────────────────────────────────────

    /// @dev Advance the global reward index for elapsed time.
    ///      RULES:
    ///      - If totalEligibleWeight == 0 or rate == 0: emission pauses (no rewards lost).
    ///      - toEmit is capped by (totalFunded - totalEmitted) to prevent insolvency.
    ///      - Integer truncation remainder stays in vault (never emitted).
    function _updateGlobal() internal {
        uint256 elapsed = block.timestamp - lastUpdateTime;
        // Always advance lastUpdateTime even if nothing is emitted
        lastUpdateTime = block.timestamp;

        if (elapsed == 0) return;
        if (totalEligibleWeight == 0) return;
        if (emissionRatePerSecond == 0) return;

        // Compute raw emission for elapsed period
        uint256 toEmit = elapsed * emissionRatePerSecond;

        // Cap by unaccrued funded balance (cannot emit more than deposited)
        uint256 maxEmittable = totalFunded - totalEmitted;
        if (toEmit > maxEmittable) toEmit = maxEmittable;

        if (toEmit == 0) return;

        // Advance global index
        accRewardPerWeight += toEmit * PRECISION / totalEligibleWeight;
        totalEmitted       += toEmit;

        emit GlobalUpdated(toEmit, accRewardPerWeight, totalEligibleWeight);
    }

    // ── Internal: recipient checkpoint ────────────────────────────────────────

    /// @dev Checkpoint a recipient: calculate pending rewards earned since last debt snapshot.
    function _checkpoint(bytes32 id) internal {
        RecipientInfo storage r = recipients[id];
        if (!r.active || r.weight == 0) {
            r.rewardDebt = accRewardPerWeight;
            return;
        }
        uint256 earned = (accRewardPerWeight - r.rewardDebt) * r.weight / PRECISION;
        if (earned > 0) {
            r.pendingReward += earned;
        }
        r.rewardDebt = accRewardPerWeight;
    }

    // ── Admin: recipient management ────────────────────────────────────────────

    /// @notice Register a new reward recipient.
    /// @param  id          Unique identifier (e.g., keccak256("dev-recipient-0")).
    /// @param  rewardAddr  EVM address that will receive claimed PW.
    /// @param  weight      Proportional weight for reward allocation.
    /// @param  startActive Whether to start accruing immediately.
    function registerRecipient(
        bytes32 id,
        address rewardAddr,
        uint128 weight,
        bool    startActive
    ) external onlyAdmin {
        require(id        != bytes32(0), "RV: zero id");
        require(rewardAddr != address(0), "RV: zero address");
        require(weight     > 0,           "RV: zero weight");
        require(!isRegistered[id],        "RV: already registered");

        // Checkpoint global state before changing weight
        _updateGlobal();

        RecipientInfo storage r = recipients[id];
        r.rewardAddress = rewardAddr;
        r.weight        = weight;
        r.rewardDebt    = accRewardPerWeight; // start from current index (no retro-accrual)
        r.active        = startActive;

        if (startActive) {
            totalEligibleWeight += weight;
        }

        isRegistered[id] = true;
        recipientList.push(id);

        emit RecipientRegistered(id, rewardAddr, weight, startActive);
    }

    /// @notice Activate a registered recipient (begin accruing rewards).
    function activateRecipient(bytes32 id) external onlyAdmin {
        require(isRegistered[id], "RV: not registered");
        RecipientInfo storage r = recipients[id];
        require(!r.active, "RV: already active");

        _updateGlobal();
        _checkpoint(id);

        r.active      = true;
        r.rewardDebt  = accRewardPerWeight; // no retro-accrual from inactive period
        totalEligibleWeight += r.weight;

        emit RecipientActivated(id);
    }

    /// @notice Deactivate a recipient (stop accruing rewards; earned fees preserved).
    function deactivateRecipient(bytes32 id) external onlyAdmin {
        require(isRegistered[id], "RV: not registered");
        RecipientInfo storage r = recipients[id];
        require(r.active, "RV: already inactive");

        _updateGlobal();
        _checkpoint(id);

        r.active            = false;
        totalEligibleWeight -= r.weight;

        emit RecipientDeactivated(id, r.pendingReward);
    }

    /// @notice Update a recipient's reward weight.
    ///         Checkpoints all accumulated rewards under the old weight first.
    function setWeight(bytes32 id, uint128 newWeight) external onlyAdmin {
        require(isRegistered[id], "RV: not registered");
        require(newWeight > 0,    "RV: zero weight");
        RecipientInfo storage r = recipients[id];

        _updateGlobal();
        _checkpoint(id);

        uint128 old = r.weight;

        if (r.active) {
            totalEligibleWeight = totalEligibleWeight - old + newWeight;
        }
        r.weight = newWeight;

        emit RecipientWeightUpdated(id, old, newWeight);
    }

    /// @notice Update the EVM address that receives a recipient's claimed PW.
    function setRewardAddress(bytes32 id, address newAddr) external onlyAdmin {
        require(isRegistered[id],    "RV: not registered");
        require(newAddr != address(0), "RV: zero address");
        recipients[id].rewardAddress = newAddr;
        emit RecipientAddressUpdated(id, newAddr);
    }

    // ── Admin: emission rate control ──────────────────────────────────────────

    /// @notice Reduce the emission rate.
    ///
    ///         GOVERNANCE RULE (LOCKED  --  C00):
    ///         The emission rate MAY be reduced by the protocol admin (multisig+timelock).
    ///         It MAY NEVER be increased above MAX_RATE_PER_SECOND through this function.
    ///         A protocol upgrade is required to increase the cap.
    ///
    ///         Rate-change checkpoints all global state first so that
    ///         historical rewards are computed at the old rate. The new rate
    ///         applies ONLY to future elapsed time.
    ///
    /// @param  newRate  New emission rate in wei/second. Must be < current rate.
    function setEmissionRate(uint256 newRate) external onlyAdmin {
        require(newRate <  emissionRatePerSecond,  "RV: rate not reduced");
        require(newRate <= MAX_RATE_PER_SECOND,    "RV: rate exceeds max");
        // newRate < currentRate <= MAX, so second require is always true but kept for clarity

        // Checkpoint at old rate before applying new rate
        _updateGlobal();

        uint256 old = emissionRatePerSecond;
        emissionRatePerSecond = newRate;

        emit EmissionRateReduced(old, newRate);
    }

    // ── Claim ─────────────────────────────────────────────────────────────────

    /// @notice Claim accrued rewards for a recipient.
    ///         CEI pattern. Caller must be the registered rewardAddress.
    /// @param  id  The recipient ID.
    /// @return amount  PW transferred to rewardAddress.
    function claim(bytes32 id) external nonReentrant returns (uint256 amount) {
        require(isRegistered[id], "RV: not registered");
        RecipientInfo storage r = recipients[id];
        require(msg.sender == r.rewardAddress, "RV: caller is not rewardAddress");

        // Update global index first, then checkpoint this recipient
        _updateGlobal();
        _checkpoint(id);

        amount = r.pendingReward;
        require(amount > 0, "RV: nothing to claim");

        // Effects before interaction (CEI)
        r.pendingReward  = 0;
        r.totalClaimed  += amount;
        totalClaimed    += amount;

        // Interaction
        (bool ok,) = r.rewardAddress.call{value: amount}("");
        require(ok, "RV: transfer failed");

        emit RewardClaimed(id, r.rewardAddress, amount);
    }

    // ── View functions ────────────────────────────────────────────────────────

    /// @notice Current claimable amount for a recipient (including unaccrued since last update).
    function claimable(bytes32 id) external view returns (uint256) {
        if (!isRegistered[id]) return 0;
        RecipientInfo storage r = recipients[id];

        uint256 pending = r.pendingReward;

        // Simulate _updateGlobal + _checkpoint without writing state
        if (r.active && r.weight > 0 && totalEligibleWeight > 0 && emissionRatePerSecond > 0) {
            uint256 elapsed = block.timestamp - lastUpdateTime;
            if (elapsed > 0) {
                uint256 toEmit = elapsed * emissionRatePerSecond;
                uint256 maxEmittable = totalFunded - totalEmitted;
                if (toEmit > maxEmittable) toEmit = maxEmittable;

                if (toEmit > 0) {
                    uint256 indexDelta = toEmit * PRECISION / totalEligibleWeight;
                    uint256 earned = (accRewardPerWeight + indexDelta - r.rewardDebt) * r.weight / PRECISION;
                    pending += earned;
                } else {
                    // No new emission; compute from existing index
                    pending += (accRewardPerWeight - r.rewardDebt) * r.weight / PRECISION;
                }
            } else {
                // Same block: only existing index delta
                pending += (accRewardPerWeight - r.rewardDebt) * r.weight / PRECISION;
            }
        } else if (r.active && r.weight > 0) {
            // Weight or rate is 0 (or zero-weight period); use stored index
            pending += (accRewardPerWeight - r.rewardDebt) * r.weight / PRECISION;
        }

        return pending;
    }

    /// @notice Native PW balance of this contract (actual, including any forced transfers).
    function vaultBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /// @notice Accounted balance: totalFunded - totalClaimed.
    ///         This is the exact amount the accounting model expects to be here.
    function accountedBalance() external view returns (uint256) {
        return totalFunded - totalClaimed;
    }

    /// @notice Total currently accrued but unclaimed rewards.
    function totalPending() external view returns (uint256) {
        return totalEmitted - totalClaimed;
    }

    /// @notice Remaining unaccrued reserve (available for future emission).
    function totalRemaining() external view returns (uint256) {
        return totalFunded - totalEmitted;
    }

    /// @notice Number of registered recipients.
    function recipientCount() external view returns (uint256) {
        return recipientList.length;
    }

    /// @notice Annual emission at the current rate (may be less than MAX_ANNUAL_EMISSION).
    function currentAnnualEmission() external view returns (uint256) {
        return emissionRatePerSecond * SECONDS_PER_YEAR;
    }

    /// @notice Whether the vault has exhausted its funded balance (no more emissions possible).
    function isExhausted() external view returns (bool) {
        return totalEmitted >= totalFunded;
    }
}
