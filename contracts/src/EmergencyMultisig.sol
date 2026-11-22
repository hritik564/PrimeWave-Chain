// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// ============================================================
// EmergencyMultisig — PW-C07 Phase-1 Emergency Authority
// ============================================================
//
// AUTHORITY:
//   3-of-5 multisig. Only authorized signers may approve proposals.
//   A proposal executes when >= THRESHOLD approvals are collected.
//
// LEGACY BASE WARNING: execute() is generic and does NOT enforce the
// intended target/selector scope below. Use the separately reviewed
// PauseOnlyEmergencyMultisig candidate for enforced production isolation.
// SCOPE (historical design intent, not enforced by this base):
//   The Emergency Multisig may ONLY call pause() and unpause() on
//   registered protocol contracts. Any other call will revert at
//   the target (target contracts restrict their pause functions to
//   their registered pauseController, which is this contract).
//
//   Per PRIMEWAVE_GOVERNANCE_POLICY.md §4.2 (locked 2026-08-13):
//   - pause(target)   — halt claims/distribution on affected contract
//   - unpause(target) — restore normal operation
//
//   The Emergency Multisig CANNOT:
//   - mint PW or alter supply
//   - transfer funds from any vault or treasury
//   - change validator set, weights, or recipients
//   - bypass the 48-hour timelock
//   - upgrade contracts
//   - change governance role memberships
//
// SECURITY PROPERTIES:
//   - No single signer can act alone (threshold = 3)
//   - Duplicate approvals from the same signer are rejected
//   - Executed proposals are permanently marked; no replay
//   - Cancelled proposals are permanently marked; no re-execution
//   - Proposal hash includes nonce, target, data — parameter tampering fails
//   - Any account may propose; only signers may approve
//   - Any account may execute once threshold is reached
//
// SIGNER MANAGEMENT:
//   Signers are set at construction and CANNOT be changed by this contract.
//   Changing the signer set requires deploying a new EmergencyMultisig and
//   rotating the pauseController on each affected contract through the
//   Protocol Admin multisig + 48-hour timelock process.
//
// DEVELOPMENT NOTE:
//   Development signers (DEV keys) are used here. Production keys require
//   the full key ceremony per PRIMEWAVE_KEY_SECURITY_PROCEDURE.md.
//   DO NOT generate production keys in this sprint.
//
// ENVIRONMENT: LOCAL DEVELOPMENT ONLY — NOT FOR MAINNET
// ============================================================

contract EmergencyMultisig {

    // ── Constants ─────────────────────────────────────────────────────────────

    /// @notice Minimum approvals required to execute a proposal.
    uint256 public constant THRESHOLD = 3;

    /// @notice Maximum number of signers this implementation supports.
    uint256 public constant MAX_SIGNERS = 5;

    // ── Immutables ────────────────────────────────────────────────────────────

    /// @notice The 5 authorized signers. Immutable after construction.
    address[MAX_SIGNERS] public signers;

    // ── Proposal tracking ─────────────────────────────────────────────────────

    /// @notice Global nonce. Incremented for each new proposal to prevent replay.
    uint256 public nonce;

    /// @notice proposalId → approval count.
    mapping(bytes32 => uint256) public approvalCount;

    /// @notice proposalId → signer → has approved.
    mapping(bytes32 => mapping(address => bool)) public hasApproved;

    /// @notice proposalId → has been executed.
    mapping(bytes32 => bool) public isExecuted;

    /// @notice proposalId → has been cancelled.
    mapping(bytes32 => bool) public isCancelled;

    /// @notice proposalId → proposer (for cancellation auth).
    mapping(bytes32 => address) public proposer;

    // ── Events ────────────────────────────────────────────────────────────────

    event ProposalCreated(
        bytes32 indexed proposalId,
        address indexed proposer,
        address indexed target,
        bytes   data,
        uint256 nonce
    );

    event ProposalApproved(
        bytes32 indexed proposalId,
        address indexed signer,
        uint256 approvalCount
    );

    event ProposalExecuted(
        bytes32 indexed proposalId,
        address indexed executor,
        address indexed target,
        bytes   data
    );

    event ProposalCancelled(
        bytes32 indexed proposalId,
        address indexed canceller
    );

    // ── Constructor ───────────────────────────────────────────────────────────

    /// @param _signers Exactly 5 authorized signer addresses. No duplicates. No zero-addresses.
    constructor(address[MAX_SIGNERS] memory _signers) {
        for (uint256 i = 0; i < MAX_SIGNERS; i++) {
            require(_signers[i] != address(0), "EMS: zero signer");
            // Check for duplicates
            for (uint256 j = 0; j < i; j++) {
                require(_signers[i] != _signers[j], "EMS: duplicate signer");
            }
            signers[i] = _signers[i];
        }
    }

    // ── Internal helpers ──────────────────────────────────────────────────────

    /// @dev Check whether `addr` is one of the 5 authorized signers.
    function _isSigner(address addr) internal view returns (bool) {
        for (uint256 i = 0; i < MAX_SIGNERS; i++) {
            if (signers[i] == addr) return true;
        }
        return false;
    }

    /// @dev Compute the proposal ID for given parameters.
    function _proposalId(
        address target,
        bytes memory data,
        uint256 _nonce
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(target, data, _nonce));
    }

    // ── Public: proposal lifecycle ────────────────────────────────────────────

    /// @notice Create a new proposal. Anyone may propose; only signers may approve.
    ///
    ///         A proposal is a call to `target` with `data`. The proposer
    ///         automatically registers the proposal with the current nonce and
    ///         increments the nonce. The proposer does NOT automatically approve.
    ///
    /// @param target  Contract to call upon execution.
    /// @param data    ABI-encoded calldata (e.g. abi.encodeCall(target.pause, ())).
    /// @return proposalId  Unique identifier for this proposal.
    function propose(
        address target,
        bytes calldata data
    ) external returns (bytes32 proposalId) {
        require(target != address(0), "EMS: zero target");

        uint256 currentNonce = nonce;
        nonce = currentNonce + 1;

        proposalId = _proposalId(target, data, currentNonce);

        // Proposals cannot collide (nonce is unique per call)
        require(proposer[proposalId] == address(0), "EMS: proposal exists");

        proposer[proposalId] = msg.sender;
        emit ProposalCreated(proposalId, msg.sender, target, data, currentNonce);
    }

    /// @notice Approve a proposal. Only authorized signers may approve.
    ///         Each signer may approve at most once per proposal.
    ///
    /// @param proposalId  The proposal identifier from propose().
    function approve(bytes32 proposalId) external {
        require(_isSigner(msg.sender),              "EMS: not a signer");
        require(proposer[proposalId] != address(0), "EMS: proposal does not exist");
        require(!isExecuted[proposalId],            "EMS: already executed");
        require(!isCancelled[proposalId],           "EMS: cancelled");
        require(!hasApproved[proposalId][msg.sender], "EMS: already approved");

        hasApproved[proposalId][msg.sender] = true;
        uint256 count = approvalCount[proposalId] + 1;
        approvalCount[proposalId] = count;

        emit ProposalApproved(proposalId, msg.sender, count);
    }

    /// @notice Execute a proposal once THRESHOLD approvals are collected.
    ///         Any account may execute (signers or otherwise).
    ///
    ///         The proposal must:
    ///           - Exist (have been proposed)
    ///           - Have >= THRESHOLD approvals
    ///           - Not have been executed or cancelled
    ///
    ///         The target call must succeed (revert propagated).
    ///
    /// @param target   Must match the original target in propose().
    /// @param data     Must match the original data in propose().
    /// @param _nonce   Must match the original nonce used in propose().
    function execute(
        address target,
        bytes calldata data,
        uint256 _nonce
    ) public virtual {
        bytes32 proposalId = _proposalId(target, data, _nonce);

        require(proposer[proposalId] != address(0), "EMS: proposal does not exist");
        require(!isExecuted[proposalId],            "EMS: already executed");
        require(!isCancelled[proposalId],           "EMS: cancelled");
        require(approvalCount[proposalId] >= THRESHOLD, "EMS: insufficient approvals");

        isExecuted[proposalId] = true;

        (bool ok, bytes memory ret) = target.call(data);
        if (!ok) {
            // Bubble up revert
            assembly { revert(add(ret, 32), mload(ret)) }
        }

        emit ProposalExecuted(proposalId, msg.sender, target, data);
    }

    /// @notice Cancel a proposal. Only the original proposer may cancel.
    ///         Cannot cancel an already-executed proposal.
    ///
    /// @param target   Must match the original target in propose().
    /// @param data     Must match the original data in propose().
    /// @param _nonce   Must match the original nonce used in propose().
    function cancel(
        address target,
        bytes calldata data,
        uint256 _nonce
    ) external {
        bytes32 proposalId = _proposalId(target, data, _nonce);

        require(proposer[proposalId] != address(0), "EMS: proposal does not exist");
        require(msg.sender == proposer[proposalId], "EMS: not proposer");
        require(!isExecuted[proposalId],            "EMS: already executed");
        require(!isCancelled[proposalId],           "EMS: already cancelled");

        isCancelled[proposalId] = true;
        emit ProposalCancelled(proposalId, msg.sender);
    }

    // ── Views ─────────────────────────────────────────────────────────────────

    /// @notice Compute the proposalId for given params (view helper).
    function getProposalId(
        address target,
        bytes calldata data,
        uint256 _nonce
    ) external pure returns (bytes32) {
        return _proposalId(target, data, _nonce);
    }

    /// @notice Whether `addr` is one of the authorized signers.
    function isSigner(address addr) external view returns (bool) {
        return _isSigner(addr);
    }

    /// @notice Whether a proposal is ready to execute (threshold met, not yet executed).
    function isReady(bytes32 proposalId) external view returns (bool) {
        return !isExecuted[proposalId]
            && !isCancelled[proposalId]
            && proposer[proposalId] != address(0)
            && approvalCount[proposalId] >= THRESHOLD;
    }
}
