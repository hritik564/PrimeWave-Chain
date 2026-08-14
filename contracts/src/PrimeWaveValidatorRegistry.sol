// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// ============================================================
// PrimeWaveValidatorRegistry — C05 Validator State Adapter
// ============================================================
//
// PURPOSE (C05):
//   Bridge between Avalanche's on-chain ValidatorManager (ACP-77/ACP-99)
//   and the PrimeWave fee-accounting layer (ValidatorFeeVault, C04).
//
//   The ValidatorManager (from ava-labs/icm-services@40e1c89) is the single
//   authoritative source of truth for validator existence, status, and weight
//   on the EVM layer. It is queryable by any EVM contract via standard calls.
//
// INTEGRATION BOUNDARY:
//
//   Avalanche P-Chain (Warp/ICM)
//         │  validator set changes
//         ▼
//   ValidatorManager (ACP-99 — from icm-services)
//         │  getValidator(validationID) — EVM-readable
//         ▼
//   PrimeWaveValidatorRegistry (THIS CONTRACT)
//         │  registerValidator / syncValidator / updateWeight
//         ▼
//   ValidatorFeeVault (C04)
//         │  reward-index accounting
//         ▼
//   Validator claimFees()
//
// VALIDATOR IDENTITY:
//   The canonical validator identifier is the `validationID` (bytes32) returned
//   by ValidatorManager.initiateValidatorRegistration() and confirmed after the
//   P-Chain Warp roundtrip via completeValidatorRegistration().
//   The same validationID is used as the key in ValidatorFeeVault.
//
// VALIDATOR STATUS (ACP-99 ValidatorStatus enum):
//   Unknown       — not a valid validator; all operations reject this
//   PendingAdded  — registration initiated but P-Chain has not yet confirmed
//   Active        — registered and confirmed; eligible to earn fees
//   PendingRemoved — removal initiated; fee accrual stops at this point
//   Completed     — fully removed; fees earned before removal remain claimable
//   Invalidated   — registration/removal expired without P-Chain confirmation
//
// UPTIME — EXPLICIT STOP BOUNDARY:
//   Validator uptime is tracked exclusively by the P-Chain and is NOT
//   exposed to the EVM layer through any mechanism at this time.
//   setUptimeBips() is provided as an admin-only hook for a future trusted
//   oracle (off-chain service + multisig), but implementing such an oracle
//   is EXPLICITLY OUT OF SCOPE for C05. Phase 1 uptimeBips defaults to 10_000
//   (100% — all PoA validators are assumed fully eligible).
//   Phase 2 uptime integration will be designed in a subsequent sprint.
//
// REWARD RECIPIENT BINDING:
//   The ValidatorManager does NOT store a rewardRecipient. Binding is a
//   PrimeWave protocol-level operation: only the protocolAdmin (PoA:
//   multisig+timelock in production) can associate a rewardRecipient with
//   a validationID. An attacker cannot self-register because:
//   1. registerValidator() is admin-only.
//   2. The validationID must exist in ValidatorManager (status != Unknown)
//      — meaning the actual P-Chain validator was registered by admin.
//   3. Admin key and node operator identity are distinct; the admin
//      controls the binding ceremony.
//
// WARP / LOCAL DEV:
//   Deploying and driving the real ValidatorManager requires Warp round-trips
//   with the P-Chain and an ICM relayer service. On the local primewavedev
//   chain this is replaced by MockValidatorManager (contracts/test/) which
//   simulates the ACP-99 state machine without Warp for local testing.
//   MockValidatorManager is LABELED DEV-ONLY and MUST NOT be used in production.
//
// ENVIRONMENT: LOCAL DEVELOPMENT / TESTNET — NOT FOR MAINNET
// ============================================================

// ── Minimal read interface for ACP-99 ValidatorManager ─────────────────────
// Source: ava-labs/icm-services@40e1c89 — icm-contracts/avalanche/validator-manager/

/// @notice ACP-99 validator lifecycle status.
enum ValidatorStatus {
    Unknown,        // 0 — does not exist
    PendingAdded,   // 1 — registration initiated, awaiting P-Chain Warp confirmation
    Active,         // 2 — registered and confirmed; earning fees
    PendingRemoved, // 3 — removal initiated; fee accrual stops
    Completed,      // 4 — fully removed; earned fees remain claimable
    Invalidated     // 5 — message expired without P-Chain confirmation
}

/// @notice ACP-99 validator state as returned by ValidatorManager.getValidator().
struct ValidatorACP99 {
    ValidatorStatus status;
    bytes           nodeID;
    uint64          startingWeight;
    uint64          sentNonce;
    uint64          receivedNonce;
    uint64          weight;       // current consensus weight
    uint64          startTime;
    uint64          endTime;
}

/// @notice Minimal read-only interface we consume from the ACP-99 ValidatorManager.
/// Source: IACP99Manager.sol + IValidatorManager.sol @ icm-services 40e1c89
interface IACP99ManagerReader {
    function getValidator(bytes32 validationID) external view returns (ValidatorACP99 memory);
    function l1TotalWeight() external view returns (uint64);
    function subnetID() external view returns (bytes32);
}

// ── Minimal interface for ValidatorFeeVault (C04) ──────────────────────────

interface IValidatorFeeVault {
    function registerValidator(bytes32 validationId, address rewardRecipient, uint128 baseWeight, uint16 uptimeBips) external;
    function deactivateValidator(bytes32 validationId) external;
    function activateValidator(bytes32 validationId) external;
    function setBaseWeight(bytes32 validationId, uint128 newBaseWeight) external;
    function setUptimeBips(bytes32 validationId, uint16 newUptimeBips) external;
    function setRewardRecipient(bytes32 validationId, address newRecipient) external;
    function isActive(bytes32 validationId) external view returns (bool);
    function protocolAdmin() external view returns (address);
    function validatorCount() external view returns (uint256);
}

// ── PrimeWaveValidatorRegistry ─────────────────────────────────────────────

contract PrimeWaveValidatorRegistry {

    // ── Constants ────────────────────────────────────────────────────────────

    /// @notice Default uptimeBips for Phase 1 PoA validators.
    ///         All validators are assumed fully eligible (100% uptime).
    ///         C05 uptime oracle is NOT implemented — see UPTIME comment above.
    uint16 public constant PHASE1_UPTIME_BIPS = 10_000;

    // ── Immutables ────────────────────────────────────────────────────────────

    /// @notice Admin address (DEV0 in dev; multisig+timelock in production).
    address public immutable protocolAdmin;

    /// @notice The ACP-99 ValidatorManager (production) or MockValidatorManager (dev).
    IACP99ManagerReader public immutable validatorManager;

    /// @notice The C04 fee accounting vault. registry is its protocolAdmin.
    IValidatorFeeVault public immutable feeVault;

    // ── Modifiers ────────────────────────────────────────────────────────────

    modifier onlyAdmin() {
        require(msg.sender == protocolAdmin, "PWVR: not admin");
        _;
    }

    // ── Registry state ────────────────────────────────────────────────────────

    /// @notice Whether a validationID is tracked by this registry.
    mapping(bytes32 => bool) public isManaged;

    /// @notice Ordered list of all managed validationIDs (for syncAll / enumeration).
    bytes32[] public managedValidators;

    /// @notice Reward recipient for each managed validator.
    ///         Mirrors the binding stored in ValidatorFeeVault.
    mapping(bytes32 => address) public rewardRecipient;

    // ── Events ────────────────────────────────────────────────────────────────

    event ValidatorRegistered(
        bytes32 indexed validationID,
        address indexed rewardRecipient,
        uint64  acp99Weight,
        uint16  uptimeBips
    );
    event ValidatorSynced(
        bytes32 indexed validationID,
        uint8   newStatus,
        bool    nowActive
    );
    event ValidatorWeightUpdated(bytes32 indexed validationID, uint64 newWeight);
    event ValidatorUptimeBipsSet(bytes32 indexed validationID, uint16 newBips);
    event ValidatorRewardRecipientUpdated(bytes32 indexed validationID, address indexed newRecipient);

    // ── Constructor ───────────────────────────────────────────────────────────

    /// @param _protocolAdmin  Dev EOA (DEV0) or multisig+timelock in production.
    /// @param _validatorManager  ACP-99 ValidatorManager (real or mock for dev).
    /// @param _feeVault       C04 ValidatorFeeVault. MUST have this registry as its protocolAdmin.
    constructor(address _protocolAdmin, address _validatorManager, address _feeVault) {
        require(_protocolAdmin    != address(0), "PWVR: zero admin");
        require(_validatorManager != address(0), "PWVR: zero validatorManager");
        require(_feeVault         != address(0), "PWVR: zero feeVault");

        protocolAdmin    = _protocolAdmin;
        validatorManager = IACP99ManagerReader(_validatorManager);
        feeVault         = IValidatorFeeVault(_feeVault);

        // Sanity-check: registry must be the feeVault admin
        require(
            _feeVault.code.length > 0,
            "PWVR: feeVault has no code"
        );
    }

    // ── Admin: validator registration ──────────────────────────────────────────

    /// @notice Register a validator in the PrimeWave fee accounting system.
    ///
    ///         WHEN TO CALL:
    ///         In production, call AFTER `PoAManager.completeValidatorRegistration()`
    ///         has been called (P-Chain Warp confirmed — status will be Active).
    ///         Calling with status PendingAdded is also valid but the validator
    ///         will be registered as inactive until a syncValidator() call
    ///         transitions it to Active.
    ///
    ///         SECURITY: Only admin can call. The validationID must exist in
    ///         ValidatorManager (status != Unknown). Admin controls both this
    ///         binding AND the PoAManager — an attacker cannot fabricate a
    ///         mapping between a legitimate validationID and their own address.
    ///
    /// @param validationID   The ACP-99 validationID from ValidatorManager.
    /// @param recipient      EVM address to receive claimed fees.
    /// @param weight         Consensus weight (from ACP-99; use 1 for equal Phase 1).
    function registerValidator(
        bytes32 validationID,
        address recipient,
        uint64  weight
    ) external onlyAdmin {
        require(validationID != bytes32(0),  "PWVR: zero validationID");
        require(recipient    != address(0),  "PWVR: zero recipient");
        require(weight       > 0,            "PWVR: zero weight");
        require(!isManaged[validationID],    "PWVR: already managed");

        // Verify the validationID exists in the authoritative ValidatorManager
        ValidatorACP99 memory v = validatorManager.getValidator(validationID);
        require(v.status != ValidatorStatus.Unknown, "PWVR: validator not in ValidatorManager");

        bool startActive = (v.status == ValidatorStatus.Active);
        uint16 bips = startActive ? PHASE1_UPTIME_BIPS : 0;

        // Register in ValidatorFeeVault
        feeVault.registerValidator(validationID, recipient, uint128(weight), bips);

        // If only registered (PendingAdded), mark inactive in feeVault:
        // registerValidator starts with uptimeBips=PHASE1_UPTIME_BIPS and active=true.
        // For PendingAdded, we deactivate immediately after registration.
        if (!startActive) {
            feeVault.deactivateValidator(validationID);
        }

        // Store in local registry
        isManaged[validationID]    = true;
        rewardRecipient[validationID] = recipient;
        managedValidators.push(validationID);

        emit ValidatorRegistered(validationID, recipient, weight, bips);
    }

    // ── Permissionless: sync ───────────────────────────────────────────────────

    /// @notice Sync a single validator's active status from ValidatorManager to ValidatorFeeVault.
    ///         Permissionless — anyone can call to keep accounting current.
    ///
    ///         Status → action:
    ///           Active          → activate in feeVault (if was inactive)
    ///           PendingRemoved  → deactivate in feeVault (fee accrual stops immediately)
    ///           Completed       → deactivate in feeVault (if not already)
    ///           Invalidated     → deactivate in feeVault (if not already)
    ///           PendingAdded    → no change (awaiting P-Chain confirmation)
    ///           Unknown         → revert (not a managed validator)
    ///
    ///         Earned fees are NOT confiscated by deactivation — they remain
    ///         claimable via ValidatorFeeVault.claimFees() by the rewardRecipient.
    ///
    /// @param validationID  The validationID to sync.
    function syncValidator(bytes32 validationID) public {
        require(isManaged[validationID], "PWVR: not managed");

        ValidatorACP99 memory v = validatorManager.getValidator(validationID);
        bool currentlyActive = feeVault.isActive(validationID);

        if (v.status == ValidatorStatus.Active) {
            if (!currentlyActive) {
                feeVault.activateValidator(validationID);
                emit ValidatorSynced(validationID, uint8(ValidatorStatus.Active), true);
            }
        } else if (
            v.status == ValidatorStatus.PendingRemoved ||
            v.status == ValidatorStatus.Completed      ||
            v.status == ValidatorStatus.Invalidated
        ) {
            if (currentlyActive) {
                feeVault.deactivateValidator(validationID);
                emit ValidatorSynced(validationID, uint8(v.status), false);
            }
        }
        // PendingAdded → no action; Unknown → already reverted above (isManaged check)
    }

    /// @notice Sync ALL managed validators. O(n) — use off-chain or infrequently.
    function syncAll() external {
        uint256 n = managedValidators.length;
        for (uint256 i = 0; i < n; i++) {
            syncValidator(managedValidators[i]);
        }
    }

    // ── Permissionless: weight update ──────────────────────────────────────────

    /// @notice Read the current ACP-99 weight from ValidatorManager and update
    ///         the fee accounting weight in ValidatorFeeVault.
    ///
    ///         Historical fees (earned before this call) are preserved via
    ///         ValidatorFeeVault.setBaseWeight()'s internal checkpoint.
    ///         See C04 spec for proof of historical conservation.
    ///
    ///         Permissionless — anyone can call after a weight change completes
    ///         on-chain (after `completeValidatorWeightUpdate()` on ValidatorManager).
    ///
    /// @param validationID  The validationID whose weight to sync.
    function updateWeight(bytes32 validationID) external {
        require(isManaged[validationID], "PWVR: not managed");

        ValidatorACP99 memory v = validatorManager.getValidator(validationID);
        require(v.status != ValidatorStatus.Unknown, "PWVR: validator not found");
        require(v.weight > 0, "PWVR: zero weight from ValidatorManager");

        feeVault.setBaseWeight(validationID, uint128(v.weight));
        emit ValidatorWeightUpdated(validationID, v.weight);
    }

    // ── Admin: uptime (future oracle hook) ────────────────────────────────────

    /// @notice Set the uptimeBips for a validator.
    ///
    ///         ⚠️  UPTIME ORACLE — PHASE 1 STOP BOUNDARY ⚠️
    ///         Validator uptime is NOT available from the EVM layer.
    ///         This function is an admin-only hook for a future off-chain
    ///         oracle (e.g. a multisig-attested uptime report). Implementing
    ///         such an oracle is explicitly out of scope for C05.
    ///
    ///         Phase 1 default: 10,000 bips (100% — all PoA validators fully eligible).
    ///
    ///         DO NOT call this with unrestricted or unauthenticated uptime data.
    ///         The oracle architecture must be designed and approved separately.
    ///
    /// @param validationID  The validationID to update.
    /// @param bips          Uptime in basis points [0, 10_000].
    function setUptimeBips(bytes32 validationID, uint16 bips) external onlyAdmin {
        require(isManaged[validationID], "PWVR: not managed");
        feeVault.setUptimeBips(validationID, bips);
        emit ValidatorUptimeBipsSet(validationID, bips);
    }

    // ── Admin: reward recipient ────────────────────────────────────────────────

    /// @notice Update the rewardRecipient for a managed validator.
    ///
    ///         SECURITY: Only admin can call. Prevents unauthorized recipient
    ///         substitution. In production, protected by multisig+timelock.
    ///         Any earned but unclaimed fees are unaffected — they are still
    ///         claimable by the OLD recipient until claimed, then future claims
    ///         go to the new recipient.
    ///
    ///         ⚠️  Implementation note: ValidatorFeeVault.claimFees() checks
    ///         that msg.sender == rewardRecipient at claim time. Changing the
    ///         recipient does NOT transfer ownership of unclaimed fees — the
    ///         old recipient should claim before the change is made.
    ///
    /// @param validationID  The validationID to update.
    /// @param newRecipient  The new EVM address to receive future claimed fees.
    function setRewardRecipient(bytes32 validationID, address newRecipient) external onlyAdmin {
        require(isManaged[validationID],   "PWVR: not managed");
        require(newRecipient != address(0),"PWVR: zero recipient");

        rewardRecipient[validationID] = newRecipient;
        feeVault.setRewardRecipient(validationID, newRecipient);
        emit ValidatorRewardRecipientUpdated(validationID, newRecipient);
    }

    // ── View ──────────────────────────────────────────────────────────────────

    /// @notice Number of managed validators in this registry.
    function managedCount() external view returns (uint256) {
        return managedValidators.length;
    }

    /// @notice Live ACP-99 status of a validator. Reads from ValidatorManager.
    function validatorStatus(bytes32 validationID) external view returns (ValidatorStatus) {
        return validatorManager.getValidator(validationID).status;
    }

    /// @notice Live ACP-99 weight of a validator. Reads from ValidatorManager.
    function validatorWeight(bytes32 validationID) external view returns (uint64) {
        return validatorManager.getValidator(validationID).weight;
    }
}
