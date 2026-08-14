// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// ============================================================
// DevTreasury — PW-C03 Development Version
// ============================================================
//
// PURPOSE (C03):
//   Receive the 20% treasury share of distributed transaction fees.
//   Development destination only; proves treasury routing is functional.
//
// OUT OF SCOPE FOR C03:
//   - Production governance
//   - Multisig control
//   - Treasury spending decisions
//   - Timelock
//   - Treasury disbursement
//   (Production Treasury architecture will be implemented in a later sprint.)
//
// SUPPLY INVARIANT:
//   This contract only receives PW; it never creates PW.
//
// ENVIRONMENT: LOCAL DEVELOPMENT ONLY — NOT FOR MAINNET
// ============================================================

contract DevTreasury {
    // ── State ────────────────────────────────────────────────────────────────

    /// @notice Cumulative amount of PW received via distribute() calls.
    uint256 public totalReceived;

    /// @notice Address of the FeeDistributor that is the authorized sender.
    address public immutable feeDistributor;

    // ── Events ───────────────────────────────────────────────────────────────

    /// @notice Emitted every time the treasury receives its PW share.
    /// @param  amount       Wei received.
    /// @param  blockNumber  Block at which the receipt occurred.
    /// @param  sender       Address that sent the PW (should always be FeeDistributor).
    event TreasuryReceived(uint256 amount, uint256 blockNumber, address indexed sender);

    // ── Constructor ──────────────────────────────────────────────────────────

    /// @param _feeDistributor  Address of the FeeDistributor contract.
    constructor(address _feeDistributor) {
        require(_feeDistributor != address(0), "DevTreasury: zero distributor");
        feeDistributor = _feeDistributor;
    }

    // ── Receive ──────────────────────────────────────────────────────────────

    /// @notice Accept native PW. Updates cumulative accounting and emits an event.
    receive() external payable {
        totalReceived += msg.value;
        emit TreasuryReceived(msg.value, block.number, msg.sender);
    }

    // ── View ─────────────────────────────────────────────────────────────────

    /// @notice Current PW balance held by this treasury.
    function treasuryBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /// @notice Cumulative PW received (via explicit transfers only).
    function cumulativeReceived() external view returns (uint256) {
        return totalReceived;
    }

    // ── No governance in C03 ─────────────────────────────────────────────────
    //
    // Intentionally omitted:
    //   disburse()              — deferred to production governance sprint
    //   ownerWithdraw()         — not allowed; no admin drain
    //   setMultisig()           — production multisig setup deferred
    //   setTimelock()           — 48h timelock deferred to governance sprint
}
