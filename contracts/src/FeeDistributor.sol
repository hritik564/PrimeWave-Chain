// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// ============================================================
// FeeDistributor — PW-C03 Core Contract
// ============================================================
//
// PURPOSE:
//   Route ALL native PW transaction fees from the Avalanche
//   RewardManager to the locked 70/20/10 split:
//
//       70% → ValidatorFeeVault  (validator economic reward pool)
//       20% → DevTreasury        (protocol treasury)
//       10% → BURN_ADDRESS       (permanent inaccessible burn)
//
// SUPPLY INVARIANT:
//   This contract NEVER creates PW. Every wei that enters
//   via fee crediting or direct transfer exits exactly via
//   distribute(). No wei is silently retained.
//
// FEE ROUTING MECHANISM:
//   The Avalanche EVM (AvalancheGo v1.14.2) credits block fees
//   to the address configured as `rewardAddress` in the genesis
//   rewardManagerConfig. This contract's address is set as that
//   rewardAddress. Crediting is performed by AvalancheGo via
//   StateDB.AddBalance() — it does NOT call receive(); it directly
//   increments this contract's balance.
//
//   This means:
//     - receive() is called for explicit ETH sends (unit tests, etc.)
//     - Protocol fee credits increase balance WITHOUT calling receive()
//     - distribute() reads address(this).balance to capture ALL PW,
//       regardless of how it arrived.
//
// ROUNDING RULE:
//   validatorShare = floor(amount × 7000 / 10000)
//   treasuryShare  = floor(amount × 2000 / 10000)
//   burnShare      = amount − validatorShare − treasuryShare
//
//   The burn recipient always absorbs integer division remainder.
//   This guarantees: validatorShare + treasuryShare + burnShare == amount.
//   Maximum rounding dust: 2 wei to burn (one from each floor division).
//
// BURN MECHANISM:
//   burnShare is sent to BURN_ADDRESS = 0x000...dEaD.
//   This is the Ethereum ecosystem standard burn address.
//   No private key exists for it. Funds are permanently inaccessible.
//   This is "burn by inaccessibility." It does NOT trigger a protocol-
//   level supply reduction — the EVM state still counts those wei as
//   existing, but they are permanently unspendable.
//   See docs/PW-C03-FEEDISTRIBUTOR_SPEC.md §4 for full analysis.
//
// FEE LOOP ANALYSIS:
//   The gas fee for a distribute() call is credited to FeeDistributor
//   AFTER execution (by AvalancheGo at block finalization). During
//   distribute() execution, address(this).balance does NOT include
//   this TX's own fee. So distribute() empties the current balance;
//   the TX fee for distribute() itself becomes the residual processed
//   in the next distribute() call. No recursive loop can form.
//
// ACCESS CONTROL:
//   distribute() is permissionless — any address may call it.
//   No owner. No admin. No withdrawal. No destination-setter.
//   The split constants are immutable (compile-time constants).
//   The destinations are immutable (set at deployment, never changed).
//
// UPGRADEABILITY:
//   This contract is NOT upgradeable. No proxy. No admin.
//   Destination changes require a new deployment + RewardManager update
//   (which requires protocol governance + 48h timelock in production).
//
// ENVIRONMENT: LOCAL DEVELOPMENT ONLY — NOT FOR MAINNET
// ============================================================

contract FeeDistributor {

    // ── Locked split constants (compile-time immutable) ───────────────────────

    /// @notice Validator share: 7000 / 10000 = 70.00%.
    uint256 public constant VALIDATOR_BPS = 7000;

    /// @notice Treasury share: 2000 / 10000 = 20.00%.
    uint256 public constant TREASURY_BPS  = 2000;

    /// @notice Divisor for basis-point calculations.
    uint256 public constant BASIS_POINTS  = 10000;

    // BURN_BPS is implied: 10000 - 7000 - 2000 = 1000 (10.00%).
    // burnShare is computed as the remainder to guarantee zero dust.

    // ── Burn address ─────────────────────────────────────────────────────────

    /// @notice The burn destination: the Ethereum "dead" address.
    ///         No private key. Permanently inaccessible. Standard burn convention.
    address payable public constant BURN_ADDRESS =
        payable(0x000000000000000000000000000000000000dEaD);

    // ── Immutable destinations ────────────────────────────────────────────────

    /// @notice ValidatorFeeVault — receives 70% of every distribution.
    address payable public immutable validatorFeeVault;

    /// @notice DevTreasury — receives 20% of every distribution.
    address payable public immutable treasury;

    // ── Cumulative accounting ─────────────────────────────────────────────────

    /// @notice Total PW distributed via distribute() (all-time).
    uint256 public totalDistributed;

    /// @notice Total PW routed to ValidatorFeeVault (all-time).
    uint256 public totalValidatorShare;

    /// @notice Total PW routed to DevTreasury (all-time).
    uint256 public totalTreasuryShare;

    /// @notice Total PW sent to BURN_ADDRESS (all-time).
    uint256 public totalBurnShare;

    // ── Pause state ──────────────────────────────────────────────────────────

    /// @notice Whether distribution is currently paused (Emergency Multisig only).
    bool public paused;

    /// @notice Address authorized to call pause() and unpause().
    ///         Set at construction. Use address(0) to disable pause entirely.
    ///         Only changeable by current pauseController (self-transfer).
    address public pauseController;

    // ── Reentrancy guard ──────────────────────────────────────────────────────

    /// @dev Set to true during distribute() execution to prevent reentrant calls.
    bool private _distributing;

    // ── Events ────────────────────────────────────────────────────────────────

    /// @notice Emitted when native PW arrives via an explicit send (not protocol credit).
    /// @dev    Protocol-level AddBalance() fee credits do NOT trigger this event.
    event FeeReceived(
        uint256 amount,
        uint256 blockNumber,
        address indexed sender
    );

    /// @notice Emitted when distribution is paused by the pauseController.
    event Paused(address indexed by);

    /// @notice Emitted when distribution is resumed by the pauseController.
    event Unpaused(address indexed by);

    /// @notice Emitted when the pauseController address is updated.
    event PauseControllerUpdated(address indexed oldController, address indexed newController);

    /// @notice Emitted once per distribute() call. Primary event for indexing.
    /// @param  amount          Total PW distributed in this call.
    /// @param  validatorShare  PW routed to ValidatorFeeVault (70% floor).
    /// @param  treasuryShare   PW routed to DevTreasury (20% floor).
    /// @param  burnShare       PW sent to BURN_ADDRESS (remainder).
    /// @param  blockNumber     Block in which distribute() was called.
    event FeeDistributed(
        uint256 amount,
        uint256 validatorShare,
        uint256 treasuryShare,
        uint256 burnShare,
        uint256 indexed blockNumber
    );

    // ── Constructor ───────────────────────────────────────────────────────────

    /// @param _validatorFeeVault  Address of the ValidatorFeeVault contract.
    /// @param _treasury           Address of the DevTreasury contract.
    /// @param _pauseController    Address authorized to pause/unpause (address(0) = no pause).
    constructor(
        address payable _validatorFeeVault,
        address payable _treasury,
        address _pauseController
    ) {
        require(
            _validatorFeeVault != address(0),
            "FeeDistributor: zero vault"
        );
        require(
            _treasury != address(0),
            "FeeDistributor: zero treasury"
        );
        validatorFeeVault = _validatorFeeVault;
        treasury          = _treasury;
        pauseController   = _pauseController;
    }

    // ── Pause control (Emergency Multisig only) ───────────────────────────────

    modifier onlyPauseController() {
        require(
            msg.sender == pauseController && pauseController != address(0),
            "FeeDistributor: not pause controller"
        );
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "FeeDistributor: paused");
        _;
    }

    /// @notice Transfer the pauseController role to a new address.
    ///         Only callable by the current pauseController.
    function setPauseController(address newController) external onlyPauseController {
        address old = pauseController;
        pauseController = newController;
        emit PauseControllerUpdated(old, newController);
    }

    /// @notice Pause fee distribution. Only callable by pauseController.
    ///         While paused: distribute() reverts; fees accumulate in contract.
    ///         All other state (accounting, balances) is unchanged.
    function pause() external onlyPauseController {
        require(!paused, "FeeDistributor: already paused");
        paused = true;
        emit Paused(msg.sender);
    }

    /// @notice Resume fee distribution. Only callable by pauseController.
    function unpause() external onlyPauseController {
        require(paused, "FeeDistributor: not paused");
        paused = false;
        emit Unpaused(msg.sender);
    }

    // ── Receive ───────────────────────────────────────────────────────────────

    /// @notice Accept explicit native PW transfers (e.g., unit tests, direct sends).
    /// @dev    Protocol-level block-fee credits from AvalancheGo use AddBalance()
    ///         and do NOT call this function.
    receive() external payable {
        emit FeeReceived(msg.value, block.number, msg.sender);
    }

    // ── Core: distribute ──────────────────────────────────────────────────────

    /// @notice Distribute the entire current balance according to the 70/20/10 split.
    ///
    /// @dev    Permissionless — any address may call this function.
    ///
    /// @dev    REENTRANCY: Protected by the _distributing flag.
    ///         State (totalDistributed, etc.) is updated BEFORE any external
    ///         .call(), following the checks-effects-interactions pattern.
    ///
    /// @dev    ROUNDING: validatorShare and treasuryShare use floor division.
    ///         burnShare absorbs the remainder (≤ 2 wei above exact 10%).
    function distribute() external whenNotPaused {
        // ── Reentrancy guard ──────────────────────────────────────────────────
        require(!_distributing, "FeeDistributor: reentrant call");
        _distributing = true;

        // ── Checks ────────────────────────────────────────────────────────────
        uint256 amount = address(this).balance;
        require(amount > 0, "FeeDistributor: nothing to distribute");

        // ── Math: 70/20/10 with remainder to burn ─────────────────────────────
        uint256 validatorShare = (amount * VALIDATOR_BPS) / BASIS_POINTS;
        uint256 treasuryShare  = (amount * TREASURY_BPS)  / BASIS_POINTS;
        uint256 burnShare      = amount - validatorShare - treasuryShare;

        // Internal invariant: must always hold
        assert(validatorShare + treasuryShare + burnShare == amount);

        // ── Effects: update accounting before any transfer ────────────────────
        totalDistributed    += amount;
        totalValidatorShare += validatorShare;
        totalTreasuryShare  += treasuryShare;
        totalBurnShare      += burnShare;

        emit FeeDistributed(
            amount,
            validatorShare,
            treasuryShare,
            burnShare,
            block.number
        );

        // ── Interactions: send PW to destinations ─────────────────────────────
        (bool okV, ) = validatorFeeVault.call{value: validatorShare}("");
        require(okV, "FeeDistributor: vault transfer failed");

        (bool okT, ) = treasury.call{value: treasuryShare}("");
        require(okT, "FeeDistributor: treasury transfer failed");

        (bool okB, ) = BURN_ADDRESS.call{value: burnShare}("");
        require(okB, "FeeDistributor: burn transfer failed");

        // ── Clear reentrancy guard ────────────────────────────────────────────
        _distributing = false;
    }

    // ── View helpers ─────────────────────────────────────────────────────────

    /// @notice Amount of PW currently pending distribution.
    function pendingDistribution() external view returns (uint256) {
        return address(this).balance;
    }

    /// @notice Preview the split for a given amount (does not transfer anything).
    function previewDistribution(uint256 amount)
        external
        pure
        returns (
            uint256 validatorShare_,
            uint256 treasuryShare_,
            uint256 burnShare_
        )
    {
        validatorShare_ = (amount * VALIDATOR_BPS) / BASIS_POINTS;
        treasuryShare_  = (amount * TREASURY_BPS)  / BASIS_POINTS;
        burnShare_      = amount - validatorShare_ - treasuryShare_;
    }

    /// @notice Accounting snapshot: total processed by destination.
    function accountingSummary()
        external
        view
        returns (
            uint256 distributed,
            uint256 toValidators,
            uint256 toTreasury,
            uint256 toBurn
        )
    {
        return (
            totalDistributed,
            totalValidatorShare,
            totalTreasuryShare,
            totalBurnShare
        );
    }

    // ── Security surface ─────────────────────────────────────────────────────
    //
    //   NO ownerWithdraw()           — no admin drain
    //   NO emergencyWithdrawAll()    — no emergency exit
    //   NO setValidatorFeeVault()    — destinations are immutable
    //   NO setTreasury()             — destinations are immutable
    //   NO setSplit()                — split constants are compile-time immutable
    //   NO ownerWithdraw()           — no admin drain (pause does NOT add this)
    //   NO upgrade proxy             — not upgradeable
    //   NO owner                     — no owner (pauseController != owner)
}
