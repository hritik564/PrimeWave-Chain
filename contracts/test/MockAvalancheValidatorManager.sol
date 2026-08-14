// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// ============================================================
// MockAvalancheValidatorManager  --  PW-C09  DEV/TEST ONLY
// ============================================================
//
// Implements the full IValidatorManager interface (ava-labs/icm-services
// icm-relayer-v1.7.5) WITHOUT Warp round-trips. Allows
// PrimeWaveStakingManager to be tested in Foundry without a live
// P-Chain or ICM relayer.
//
// NOTE: This is DIFFERENT from the existing MockValidatorManager
// (which implements PrimeWave's own IACP99ManagerReader interface
// used by PrimeWaveValidatorRegistry). This mock implements the
// upstream Avalanche IValidatorManager interface consumed by
// the StakingManager base contract.
//
// ENVIRONMENT: TEST / LOCAL DEV — MUST NOT BE USED IN PRODUCTION
// ============================================================

import {IValidatorManager} from "validator-manager/interfaces/IValidatorManager.sol";
import {
    Validator,
    ValidatorStatus,
    PChainOwner,
    ConversionData
} from "validator-manager/interfaces/IACP99Manager.sol";

contract MockAvalancheValidatorManager is IValidatorManager {

    // ── Configuration ─────────────────────────────────────────────────────────

    bytes32 public override subnetID;
    uint64  public churnPeriodSeconds = 3600; // 1 hour — well under 14-day min stake duration

    // ── Validator state ───────────────────────────────────────────────────────

    mapping(bytes32 => Validator) private _validators;
    mapping(bytes  => bytes32)    private _nodeToValidation;
    uint64 private _totalWeight;

    // ── Registration queue ────────────────────────────────────────────────────
    // Maps messageIndex → validationID for completeValidatorRegistration()

    mapping(uint32 => bytes32) private _pendingRegistration;
    uint32 private _nextRegMsgIndex;

    // ── Removal queue ─────────────────────────────────────────────────────────
    // Maps messageIndex → validationID for completeValidatorRemoval()

    mapping(uint32 => bytes32) private _pendingRemoval;
    uint32 private _nextRemMsgIndex;

    // ── Weight update queue ───────────────────────────────────────────────────

    mapping(uint32 => bytes32) private _pendingWeightUpdate;
    uint32 private _nextWeightMsgIndex;
    mapping(bytes32 => uint64) private _pendingWeight;
    mapping(bytes32 => uint64) private _pendingNonce;
    uint64 private _nonceCounter;

    // ── Constructor ───────────────────────────────────────────────────────────

    constructor(bytes32 _subnetID, uint64 _churnPeriodSeconds) {
        subnetID = _subnetID;
        if (_churnPeriodSeconds > 0) churnPeriodSeconds = _churnPeriodSeconds;
    }

    // ── IValidatorManager / IACP99Manager ─────────────────────────────────────

    function getValidator(bytes32 validationID) external view override returns (Validator memory) {
        return _validators[validationID];
    }

    function l1TotalWeight() external view override returns (uint64) {
        return _totalWeight;
    }

    function getNodeValidationID(bytes calldata nodeID) external view override returns (bytes32) {
        return _nodeToValidation[nodeID];
    }

    function getChurnPeriodSeconds() external view override returns (uint64) {
        return churnPeriodSeconds;
    }

    /// @notice Registers a validator (mock: no Warp, assigns deterministic ID).
    ///         Returns the validationID and queues it for completeValidatorRegistration().
    function initiateValidatorRegistration(
        bytes  memory nodeID,
        bytes  memory blsPublicKey,
        PChainOwner memory, /* remainingBalanceOwner — ignored in mock */
        PChainOwner memory, /* disableOwner — ignored in mock */
        uint64 weight
    ) external override returns (bytes32 validationID) {
        // Deterministic validationID: keccak of nodeID + weight + counter
        validationID = keccak256(abi.encode(nodeID, blsPublicKey, weight, _nextRegMsgIndex));

        require(_validators[validationID].status == ValidatorStatus.Unknown, "Mock: already exists");
        require(weight > 0, "Mock: zero weight");

        _validators[validationID] = Validator({
            status:         ValidatorStatus.PendingAdded,
            nodeID:         nodeID,
            startingWeight: weight,
            sentNonce:      0,
            receivedNonce:  0,
            weight:         weight,
            startTime:      uint64(block.timestamp),
            endTime:        0
        });
        _nodeToValidation[nodeID] = validationID;

        // Queue for completion
        _pendingRegistration[_nextRegMsgIndex] = validationID;
        _nextRegMsgIndex++;

        return validationID;
    }

    /// @notice Activates the validator queued at messageIndex.
    function completeValidatorRegistration(uint32 messageIndex) external override returns (bytes32 validationID) {
        validationID = _pendingRegistration[messageIndex];
        require(validationID != bytes32(0), "Mock: no pending registration at index");

        Validator storage v = _validators[validationID];
        require(v.status == ValidatorStatus.PendingAdded, "Mock: not PendingAdded");

        v.status = ValidatorStatus.Active;
        _totalWeight += v.weight;

        delete _pendingRegistration[messageIndex];
        return validationID;
    }

    /// @notice Initiates removal (sets PendingRemoved, queues for completeValidatorRemoval).
    function initiateValidatorRemoval(bytes32 validationID) external override {
        Validator storage v = _validators[validationID];
        require(v.status == ValidatorStatus.Active, "Mock: not Active");

        v.status  = ValidatorStatus.PendingRemoved;
        v.endTime = uint64(block.timestamp);
        _totalWeight = _totalWeight >= v.weight ? _totalWeight - v.weight : 0;

        _pendingRemoval[_nextRemMsgIndex] = validationID;
        _nextRemMsgIndex++;
    }

    /// @notice Completes removal for the validator queued at messageIndex.
    function completeValidatorRemoval(uint32 messageIndex) external override returns (bytes32 validationID) {
        validationID = _pendingRemoval[messageIndex];
        require(validationID != bytes32(0), "Mock: no pending removal at index");

        Validator storage v = _validators[validationID];
        require(v.status == ValidatorStatus.PendingRemoved, "Mock: not PendingRemoved");

        v.status = ValidatorStatus.Completed;

        delete _pendingRemoval[messageIndex];
        return validationID;
    }

    function initiateValidatorWeightUpdate(
        bytes32 validationID,
        uint64  newWeight
    ) external override returns (uint64 nonce, bytes32 messageID) {
        Validator storage v = _validators[validationID];
        require(v.status == ValidatorStatus.Active, "Mock: not Active");

        _nonceCounter++;
        nonce = _nonceCounter;
        messageID = keccak256(abi.encode(validationID, nonce));

        v.sentNonce = nonce;
        _pendingWeight[validationID]  = newWeight;
        _pendingNonce[validationID]   = nonce;

        _pendingWeightUpdate[_nextWeightMsgIndex] = validationID;
        _nextWeightMsgIndex++;

        return (nonce, messageID);
    }

    function completeValidatorWeightUpdate(
        uint32 messageIndex
    ) external override returns (bytes32 validationID, uint64 nonce) {
        validationID = _pendingWeightUpdate[messageIndex];
        require(validationID != bytes32(0), "Mock: no pending weight update at index");

        Validator storage v = _validators[validationID];
        uint64 oldWeight = v.weight;
        uint64 newWeight = _pendingWeight[validationID];
        nonce = _pendingNonce[validationID];

        _totalWeight = _totalWeight >= oldWeight ? _totalWeight - oldWeight : 0;
        _totalWeight += newWeight;
        v.weight         = newWeight;
        v.receivedNonce  = nonce;

        delete _pendingWeightUpdate[messageIndex];
        delete _pendingWeight[validationID];
        delete _pendingNonce[validationID];

        return (validationID, nonce);
    }

    // ── No-op stubs for required interface functions ───────────────────────────

    function initializeValidatorSet(
        ConversionData calldata, /* conversionData — ignored in mock */
        uint32                  /* messageIndex — ignored in mock */
    ) external override { /* no-op: Phase-1 → Phase-2 transition handled externally */ }

    function migrateFromV1(bytes32, uint32) external override { /* no-op */ }

    function resendRegisterValidatorMessage(bytes32) external override { /* no-op */ }

    function resendValidatorRemovalMessage(bytes32) external override { /* no-op */ }

    // ── Dev helpers ───────────────────────────────────────────────────────────

    /// @dev Returns the messageIndex that will be used for the NEXT completeValidatorRegistration().
    function nextRegistrationMsgIndex() external view returns (uint32) {
        return _nextRegMsgIndex > 0 ? _nextRegMsgIndex - 1 : 0;
    }

    /// @dev Returns the messageIndex that will be used for the NEXT completeValidatorRemoval().
    function nextRemovalMsgIndex() external view returns (uint32) {
        return _nextRemMsgIndex > 0 ? _nextRemMsgIndex - 1 : 0;
    }

    /// @dev Returns the messageIndex that will be used for the NEXT completeValidatorWeightUpdate().
    function nextWeightMsgIndex() external view returns (uint32) {
        return _nextWeightMsgIndex > 0 ? _nextWeightMsgIndex - 1 : 0;
    }

    /// @dev Directly force a validator to Invalidated status (for edge case tests).
    function devInvalidate(bytes32 validationID) external {
        Validator storage v = _validators[validationID];
        if (v.status == ValidatorStatus.Active) {
            _totalWeight = _totalWeight >= v.weight ? _totalWeight - v.weight : 0;
        }
        v.status = ValidatorStatus.Invalidated;
    }

    /// @dev Directly force a validator to a given status (for attack / invariant tests).
    function devForceStatus(bytes32 validationID, ValidatorStatus status) external {
        _validators[validationID].status = status;
    }
}
