// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// ============================================================
// PrimeWaveTimelock — PW-C07 48-Hour Governance Timelock
// ============================================================
//
// PURPOSE:
//   Enforce a mandatory 48-hour delay before executing privileged
//   governance actions. Provides a public review window for the
//   community to observe and react to proposed changes.
//
// TIMELOCK POLICY (from PRIMEWAVE_GOVERNANCE_POLICY.md §3):
//
//   Actions requiring this timelock (exhaustive):
//     - Upgrading any protocol contract behind a proxy
//     - Changing the owner of any protocol contract
//     - Changing gas fee parameters
//     - Changing the FeeDistributor split percentages (70/20/10)
//     - Changing the RewardVault emission rate cap
//     - Adding or removing a validator (Phase 1 PoA)
//     - Changing validator weight (Phase 1 PoA)
//     - Changing the MONETARY_AUTHORITY_ROLE assignment
//     - Changing the Emergency Multisig address composition
//     - Changing any TimelockController parameter (INCLUDING minDelay)
//
//   Actions NOT requiring this timelock:
//     - Emergency pause/unpause by Emergency Multisig
//     - Uptime proof submission (keepers)
//     - Reward claims (validators)
//     - FeeDistributor.distribute() calls (keepers)
//
// SECURITY DESIGN:
//   - MIN_DELAY is a compile-time constant (48 hours = 172,800 seconds)
//   - The delay CANNOT be reduced by any admin action
//   - Changing the delay requires deploying a new timelock contract
//     (a governance action itself, subject to the OLD timelock)
//   - Each operation is identified by a unique hash that includes
//     target, data, salt, and predecessor
//   - Parameter tampering (altering target/data/salt after scheduling)
//     causes a hash mismatch and the execution reverts
//   - Executed operations are permanently marked; no replay
//   - Cancelled operations are permanently marked; no re-execution
//
// PROPOSER / EXECUTOR MODEL:
//   - A single proposer (Protocol Admin multisig or EOA in dev) may
//     schedule and cancel operations
//   - Any account may execute once the delay has elapsed ("open executor")
//   - In Phase 1 dev: proposer = DEV0 EOA
//   - In production: proposer = Protocol Admin multisig
//
// PREDECESSOR SUPPORT:
//   - An operation can declare a predecessor (another operation ID)
//     which must be executed before this operation can execute
//   - Pass bytes32(0) for no predecessor dependency
//
// ENVIRONMENT: LOCAL DEVELOPMENT ONLY — NOT FOR MAINNET
// ============================================================

contract PrimeWaveTimelock {

    // ── Constants ─────────────────────────────────────────────────────────────

    /// @notice Minimum delay before an operation can execute.
    ///         HARDCODED — cannot be reduced without redeployment.
    uint256 public constant MIN_DELAY = 172_800; // 48 hours

    // ── State ─────────────────────────────────────────────────────────────────

    /// @notice Address authorized to schedule and cancel operations.
    address public proposer;

    /// @notice operationId → earliest execution timestamp (0 if not scheduled).
    mapping(bytes32 => uint256) public scheduledAt;

    /// @notice operationId → has been executed.
    mapping(bytes32 => bool) public isExecuted;

    /// @notice operationId → has been cancelled.
    mapping(bytes32 => bool) public isCancelled;

    // ── Events ────────────────────────────────────────────────────────────────

    event OperationScheduled(
        bytes32 indexed operationId,
        address indexed proposer_,
        address indexed target,
        bytes   data,
        bytes32 predecessor,
        bytes32 salt,
        uint256 executeAfter
    );

    event OperationExecuted(
        bytes32 indexed operationId,
        address indexed executor,
        address indexed target,
        bytes   data
    );

    event OperationCancelled(
        bytes32 indexed operationId,
        address indexed canceller
    );

    event ProposerTransferred(
        address indexed oldProposer,
        address indexed newProposer
    );

    // ── Constructor ───────────────────────────────────────────────────────────

    /// @param _proposer  Address authorized to schedule and cancel (DEV0 in dev; multisig in prod).
    constructor(address _proposer) {
        require(_proposer != address(0), "PWTL: zero proposer");
        proposer = _proposer;
    }

    // ── Modifiers ─────────────────────────────────────────────────────────────

    modifier onlyProposer() {
        require(msg.sender == proposer, "PWTL: not proposer");
        _;
    }

    // ── Internal helpers ──────────────────────────────────────────────────────

    /// @dev Compute the operation ID from its parameters.
    function _operationId(
        address target,
        bytes memory data,
        bytes32 predecessor,
        bytes32 salt
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(target, data, predecessor, salt));
    }

    // ── Proposer: schedule ────────────────────────────────────────────────────

    /// @notice Schedule an operation. Only callable by proposer.
    ///
    ///         The operation becomes executable after MIN_DELAY seconds.
    ///         If a predecessor is specified, it must be executed first.
    ///
    ///         REPLAY PROTECTION: use a unique salt per operation. Reusing
    ///         an identical (target, data, predecessor, salt) combination
    ///         for a second scheduled call will revert ("already scheduled").
    ///
    /// @param target       Contract to call.
    /// @param data         ABI-encoded calldata.
    /// @param predecessor  Operation ID that must be executed first (or bytes32(0)).
    /// @param salt         Unique value to differentiate otherwise identical ops.
    /// @return operationId The unique identifier for this operation.
    function schedule(
        address target,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt
    ) external onlyProposer returns (bytes32 operationId) {
        require(target != address(0), "PWTL: zero target");

        operationId = _operationId(target, data, predecessor, salt);
        require(scheduledAt[operationId] == 0, "PWTL: already scheduled");

        uint256 readyAt = block.timestamp + MIN_DELAY;
        scheduledAt[operationId] = readyAt;

        emit OperationScheduled(
            operationId,
            msg.sender,
            target,
            data,
            predecessor,
            salt,
            readyAt
        );
    }

    // ── Execute ───────────────────────────────────────────────────────────────

    /// @notice Execute a scheduled operation after the delay has elapsed.
    ///         Open execution — any account may call once the delay has passed.
    ///
    ///         All parameters must match exactly what was passed to schedule().
    ///         Any alteration produces a different hash and the execution reverts.
    ///
    /// @param target       Must match schedule() call.
    /// @param data         Must match schedule() call.
    /// @param predecessor  Must match schedule() call. If non-zero, must be executed first.
    /// @param salt         Must match schedule() call.
    function execute(
        address target,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt
    ) external {
        bytes32 operationId = _operationId(target, data, predecessor, salt);

        uint256 readyAt = scheduledAt[operationId];
        require(readyAt != 0,              "PWTL: not scheduled");
        require(!isExecuted[operationId],  "PWTL: already executed");
        require(!isCancelled[operationId], "PWTL: cancelled");
        require(block.timestamp >= readyAt, "PWTL: delay not elapsed");

        // Predecessor check
        if (predecessor != bytes32(0)) {
            require(isExecuted[predecessor], "PWTL: predecessor not executed");
        }

        isExecuted[operationId] = true;

        (bool ok, bytes memory ret) = target.call(data);
        if (!ok) {
            assembly { revert(add(ret, 32), mload(ret)) }
        }

        emit OperationExecuted(operationId, msg.sender, target, data);
    }

    // ── Cancel ────────────────────────────────────────────────────────────────

    /// @notice Cancel a scheduled operation. Only callable by proposer.
    ///         Cannot cancel an already-executed operation.
    function cancel(
        address target,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt
    ) external onlyProposer {
        bytes32 operationId = _operationId(target, data, predecessor, salt);

        require(scheduledAt[operationId] != 0,  "PWTL: not scheduled");
        require(!isExecuted[operationId],        "PWTL: already executed");
        require(!isCancelled[operationId],       "PWTL: already cancelled");

        isCancelled[operationId] = true;
        emit OperationCancelled(operationId, msg.sender);
    }

    // ── Proposer rotation ─────────────────────────────────────────────────────

    /// @notice Transfer proposer role to a new address.
    ///         In production this action should itself go through a timelock,
    ///         or the current proposer should be the timelock itself (self-ref).
    ///         Only callable by current proposer.
    function transferProposer(address newProposer) external onlyProposer {
        require(newProposer != address(0), "PWTL: zero proposer");
        emit ProposerTransferred(proposer, newProposer);
        proposer = newProposer;
    }

    // ── Views ─────────────────────────────────────────────────────────────────

    /// @notice Compute the operation ID (view helper for off-chain use).
    function getOperationId(
        address target,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt
    ) external pure returns (bytes32) {
        return _operationId(target, data, predecessor, salt);
    }

    /// @notice Whether an operation is ready to execute right now.
    function isReady(bytes32 operationId) external view returns (bool) {
        uint256 readyAt = scheduledAt[operationId];
        return readyAt != 0
            && !isExecuted[operationId]
            && !isCancelled[operationId]
            && block.timestamp >= readyAt;
    }

    /// @notice Earliest timestamp at which an operation can execute (0 = not scheduled).
    function executeAfter(bytes32 operationId) external view returns (uint256) {
        return scheduledAt[operationId];
    }
}
