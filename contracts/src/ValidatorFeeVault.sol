// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// ============================================================
// ValidatorFeeVault — PW-C03 Development Version
// ============================================================
//
// PURPOSE (C03):
//   Receive the 70% validator share of distributed transaction fees.
//   Recording-only vault; NO per-validator distribution in C03.
//
// OUT OF SCOPE FOR C03:
//   - Validator weight accounting
//   - Per-validator distribution / claims
//   - Uptime eligibility
//   - Delegation support
//   - Staking integration
//   (These belong to later validator economics sprints.)
//
// SUPPLY INVARIANT:
//   This contract only receives PW; it never creates PW.
//   No minting. No NativeMinter interaction.
//
// ENVIRONMENT: LOCAL DEVELOPMENT ONLY — NOT FOR MAINNET
// ============================================================

contract ValidatorFeeVault {
    // ── State ────────────────────────────────────────────────────────────────

    /// @notice Cumulative amount of PW received via distribute() calls.
    uint256 public totalReceived;

    /// @notice Address of the FeeDistributor that is the sole authorized sender.
    /// @dev    Set at construction. Informational — the vault accepts ETH from
    ///         any address to be safe, but only FeeDistributor should ever send.
    address public immutable feeDistributor;

    // ── Events ───────────────────────────────────────────────────────────────

    /// @notice Emitted every time the vault receives PW from the FeeDistributor.
    /// @param  amount       Wei received.
    /// @param  blockNumber  Block at which the receipt occurred.
    /// @param  sender       Address that sent the PW (should always be FeeDistributor).
    event ValidatorFeeReceived(uint256 amount, uint256 blockNumber, address indexed sender);

    // ── Constructor ──────────────────────────────────────────────────────────

    /// @param _feeDistributor  Address of the FeeDistributor contract.
    constructor(address _feeDistributor) {
        require(_feeDistributor != address(0), "ValidatorFeeVault: zero distributor");
        feeDistributor = _feeDistributor;
    }

    // ── Receive ──────────────────────────────────────────────────────────────

    /// @notice Accept native PW. Updates cumulative accounting and emits an event.
    /// @dev    Called by FeeDistributor.distribute() for each block's 70% share.
    ///         Protocol-level AddBalance() calls (direct fee crediting by AvalancheGo)
    ///         do NOT trigger this function — only explicit .call{value:...}("") transfers do.
    receive() external payable {
        totalReceived += msg.value;
        emit ValidatorFeeReceived(msg.value, block.number, msg.sender);
    }

    // ── View ─────────────────────────────────────────────────────────────────

    /// @notice Current PW balance of this vault.
    function vaultBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /// @notice Cumulative PW received (updated via explicit transfers only).
    function cumulativeReceived() external view returns (uint256) {
        return totalReceived;
    }

    // ── No withdrawal in C03 ─────────────────────────────────────────────────
    //
    // Intentionally omitted:
    //   withdraw()        — deferred to validator distribution sprint
    //   claimValidatorFee() — deferred to validator economics sprint
    //   emergencyDrain()  — no admin drain allowed per security policy
    //
    // Future: per-validator claims will use a pull model with weight × uptime
    // accounting. See docs/PW-C03-FEEDISTRIBUTOR_SPEC.md §13.
}
