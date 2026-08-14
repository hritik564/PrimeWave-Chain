// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// ============================================================
// MockValidatorManager — DEV / TEST ONLY
// ============================================================
//
// ⚠️  DO NOT DEPLOY ON MAINNET OR PRODUCTION TESTNET ⚠️
//
// This contract simulates the ACP-99 ValidatorManager interface
// (ava-labs/icm-services@40e1c89) without requiring Warp/ICM
// round-trips with the P-Chain. It allows the PrimeWave team
// to test the full validator lifecycle (registration, activation,
// removal, weight updates) on the local primewavedev chain.
//
// In production, this is replaced by the real ValidatorManager
// from ava-labs/icm-services, which requires:
//   1. An ICM relayer service running
//   2. P-Chain Warp message round-trips
//   3. BLS signatures from actual validator nodes
//
// Interface compatibility: implements IACP99ManagerReader
// (the read-only subset consumed by PrimeWaveValidatorRegistry)
// plus write functions for test state control.
//
// ENVIRONMENT: TEST / LOCAL DEV — MUST NOT BE USED IN PRODUCTION
// ============================================================

import {ValidatorStatus, ValidatorACP99} from "../src/PrimeWaveValidatorRegistry.sol";

contract MockValidatorManager {

    // ── State ────────────────────────────────────────────────────────────────

    /// @dev Maps validationID → validator state (mirrors ACP-99 ValidatorManager storage).
    mapping(bytes32 => ValidatorACP99) private _validators;

    /// @dev Maps nodeID (bytes) → validationID.
    mapping(bytes => bytes32) private _nodeToValidation;

    /// @dev The subnetID this mock is associated with.
    bytes32 public subnetID;

    /// @dev Running sum of active weight (mirrors l1TotalWeight).
    uint64 private _totalWeight;

    // ── Constructor ───────────────────────────────────────────────────────────

    constructor(bytes32 _subnetID) {
        subnetID = _subnetID;
    }

    // ── IACP99ManagerReader interface ─────────────────────────────────────────

    function getValidator(bytes32 validationID) external view returns (ValidatorACP99 memory) {
        return _validators[validationID];
    }

    function l1TotalWeight() external view returns (uint64) {
        return _totalWeight;
    }

    function getNodeValidationID(bytes calldata nodeID) external view returns (bytes32) {
        return _nodeToValidation[nodeID];
    }

    // ── Test control: validator lifecycle ─────────────────────────────────────
    // All functions below are DEV-ONLY. Production ValidatorManager requires Warp.

    /// @notice [DEV-ONLY] Register a validator in PendingAdded state.
    ///         Simulates initiateValidatorRegistration() (without Warp).
    function devRegister(bytes32 validationID, bytes calldata nodeID, uint64 weight) external {
        require(_validators[validationID].status == ValidatorStatus.Unknown, "Mock: already exists");
        require(validationID != bytes32(0), "Mock: zero validationID");
        require(weight > 0, "Mock: zero weight");

        _validators[validationID] = ValidatorACP99({
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
    }

    /// @notice [DEV-ONLY] Activate a PendingAdded validator.
    ///         Simulates completeValidatorRegistration() (without Warp).
    function devActivate(bytes32 validationID) external {
        ValidatorACP99 storage v = _validators[validationID];
        require(v.status == ValidatorStatus.PendingAdded, "Mock: not PendingAdded");
        v.status = ValidatorStatus.Active;
        _totalWeight += v.weight;
    }

    /// @notice [DEV-ONLY] Initiate validator removal (PendingRemoved state).
    ///         Simulates initiateValidatorRemoval() (without Warp).
    function devInitiateRemoval(bytes32 validationID) external {
        ValidatorACP99 storage v = _validators[validationID];
        require(v.status == ValidatorStatus.Active, "Mock: not Active");
        v.status  = ValidatorStatus.PendingRemoved;
        v.endTime = uint64(block.timestamp);
        _totalWeight -= v.weight;
    }

    /// @notice [DEV-ONLY] Complete validator removal (Completed state).
    ///         Simulates completeValidatorRemoval() (without Warp).
    function devComplete(bytes32 validationID) external {
        ValidatorACP99 storage v = _validators[validationID];
        require(v.status == ValidatorStatus.PendingRemoved, "Mock: not PendingRemoved");
        v.status = ValidatorStatus.Completed;
    }

    /// @notice [DEV-ONLY] Invalidate a validator (registration/removal message expired).
    function devInvalidate(bytes32 validationID) external {
        ValidatorACP99 storage v = _validators[validationID];
        require(
            v.status == ValidatorStatus.PendingAdded ||
            v.status == ValidatorStatus.PendingRemoved,
            "Mock: cannot invalidate"
        );
        if (v.status == ValidatorStatus.Active) {
            _totalWeight -= v.weight;
        }
        v.status = ValidatorStatus.Invalidated;
    }

    /// @notice [DEV-ONLY] Update validator weight (Active state only).
    ///         Simulates completeValidatorWeightUpdate() (without Warp).
    function devSetWeight(bytes32 validationID, uint64 newWeight) external {
        require(newWeight > 0, "Mock: zero weight");
        ValidatorACP99 storage v = _validators[validationID];
        require(v.status == ValidatorStatus.Active, "Mock: not Active");
        _totalWeight -= v.weight;
        _totalWeight += newWeight;
        v.weight      = newWeight;
        v.receivedNonce++;
    }

    /// @notice [DEV-ONLY] Re-register an Invalidated validator (for testing re-registration).
    ///         Simulates a new validator replacing an invalidated one.
    function devReregister(bytes32 validationID, uint64 weight) external {
        ValidatorACP99 storage v = _validators[validationID];
        require(v.status == ValidatorStatus.Invalidated, "Mock: not Invalidated");
        v.status  = ValidatorStatus.PendingAdded;
        v.weight  = weight;
        v.endTime = 0;
    }

    /// @notice [DEV-ONLY] Directly set any status (for edge case testing).
    function devForceStatus(bytes32 validationID, ValidatorStatus status) external {
        _validators[validationID].status = status;
    }

    /// @notice [DEV-ONLY] Helper: create and immediately activate a validator.
    function devRegisterAndActivate(bytes32 validationID, bytes calldata nodeID, uint64 weight) external {
        this.devRegister(validationID, nodeID, weight);
        this.devActivate(validationID);
    }
}
