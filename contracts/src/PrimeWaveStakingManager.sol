// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// ============================================================
// PrimeWaveStakingManager  --  PW-C09
// ============================================================
//
// PURPOSE:
//   Phase-2 PoS validator staking contract for PrimeWave Chain.
//   Extends Avalanche's StakingManager with PrimeWave-specific reward
//   delivery (from RewardVault instead of NativeMinter) and native-PW
//   stake custody.
//
// ARCHITECTURE (see docs/PW-C09-AVALANCHE-STAKING-COMPATIBILITY.md):
//   - Extends StakingManager (ava-labs/icm-services icm-relayer-v1.7.5)
//   - _reward()  → RewardVault.distribute(account, amount)
//   - _lock()    → holds msg.value in contract (native PW custody)
//   - _unlock()  → returns native PW to validator on removal
//
// SUPPLY INVARIANT PRESERVATION:
//   - No NativeMinter path. No mint(). No inflation.
//   - All rewards come from the pre-funded 15M PW reserve in RewardVault.
//   - distribute() enforces amount ≤ (totalFunded - totalEmitted).
//   - Maximum annual payout ≤ 3,000,000 PW (governed by RewardVault.emissionRatePerSecond).
//
// DELEGATION:
//   - maximumStakeMultiplier = 1 in initial settings to disable delegation.
//   - Delegation code is inherited from StakingManager and cannot be removed,
//     but any delegation attempt reverts with MaxWeightExceeded.
//
// UNBONDING:
//   - minimumStakeDuration = 1,209,600 seconds (14 days) — enforced by StakingManager.
//   - After 14 days, validator calls initiateValidatorRemoval(), then completes
//     the Warp round-trip, then completeValidatorRemoval() returns stake + rewards.
//
// UPGRADES:
//   - Uses Initializable (ERC-7201 storage pattern from StakingManager).
//   - Production: deploy behind UUPS proxy + multisig + timelock.
//   - C09 dev/test: deploy directly (no proxy) and call initialize().
//
// ENVIRONMENT: LOCAL DEVELOPMENT  --  NOT FOR MAINNET
// ============================================================

import {StakingManager} from "validator-manager/StakingManager.sol";
import {StakingManagerSettings} from "validator-manager/interfaces/IStakingManager.sol";
import {PChainOwner} from "validator-manager/interfaces/IACP99Manager.sol";
import {RewardVault} from "./RewardVault.sol";

contract PrimeWaveStakingManager is StakingManager {

    // ── Errors ────────────────────────────────────────────────────────────────

    error ZeroVaultAddress();
    error StakeTransferFailed(address to, uint256 amount);

    // ── State ────────────────────────────────────────────────────────────────

    /// @notice The RewardVault that funds staking rewards.
    ///         Set during initialize(); immutable after that.
    RewardVault public rewardVault;

    // ── Events ────────────────────────────────────────────────────────────────

    /// @notice Emitted when a validator initiates registration via this contract.
    event StakeDeposited(bytes32 indexed validationID, address indexed staker, uint256 amount);

    /// @notice Emitted when a validator's stake is returned on removal.
    event StakeReturned(address indexed to, uint256 amount);

    // ── Initializer ───────────────────────────────────────────────────────────

    /// @notice Initialize the PrimeWaveStakingManager.
    ///
    /// @param settings  StakingManager settings. Recommended values for PW-C09:
    ///   - minimumStakeDuration = 1_209_600   (14 days — enforces unbonding period)
    ///   - maximumStakeMultiplier = 1          (disables delegation for Phase 2a)
    ///   - rewardCalculator = PrimeWaveRewardCalculator
    ///   - uptimeBlockchainID = PrimeWave Chain blockchain ID (non-zero)
    /// @param _rewardVault  The funded RewardVault. Must have distribute() caller set.
    function initialize(
        StakingManagerSettings calldata settings,
        RewardVault _rewardVault
    ) external initializer {
        if (address(_rewardVault) == address(0)) revert ZeroVaultAddress();
        __StakingManager_init(settings);
        rewardVault = _rewardVault;
    }

    // ── Public entry points ───────────────────────────────────────────────────

    /// @notice Initiate validator registration by staking native PW.
    ///
    ///         The caller sends PW as msg.value. If msg.value is within
    ///         [minimumStakeAmount, maximumStakeAmount], the stake is locked in this
    ///         contract and a registration message is sent to the ValidatorManager.
    ///
    /// @param  nodeID                20-byte NodeID of the validator node.
    /// @param  blsPublicKey          48-byte BLS public key.
    /// @param  remainingBalanceOwner P-Chain owner of remaining balance on removal.
    /// @param  disableOwner         P-Chain owner authorized to disable the validator.
    /// @param  delegationFeeBips    Fee charged to delegators (100-10000 bips).
    ///                              With maximumStakeMultiplier=1, delegation is disabled
    ///                              and this value is informational only.
    /// @param  minStakeDuration     Minimum seconds before removal can be initiated.
    ///                              Must be >= minimumStakeDuration from settings.
    /// @param  rewardRecipient      EVM address that receives staking rewards on removal.
    /// @return validationID         Unique ID of this validation period.
    function initiateValidatorRegistration(
        bytes  memory nodeID,
        bytes  memory blsPublicKey,
        PChainOwner memory remainingBalanceOwner,
        PChainOwner memory disableOwner,
        uint16 delegationFeeBips,
        uint64 minStakeDuration,
        address rewardRecipient
    ) external payable returns (bytes32 validationID) {
        validationID = _initiateValidatorRegistration(
            nodeID,
            blsPublicKey,
            remainingBalanceOwner,
            disableOwner,
            delegationFeeBips,
            minStakeDuration,
            msg.value,
            rewardRecipient
        );
        emit StakeDeposited(validationID, msg.sender, msg.value);
    }

    // ── StakingManager overrides ──────────────────────────────────────────────

    /// @notice Deliver a staking reward by calling RewardVault.distribute().
    ///         Called by StakingManager at completeValidatorRemoval() and
    ///         completeDelegatorRemoval() / claimDelegationFees().
    ///
    ///         If amount == 0 (validator had no uptime proof), no vault call is made.
    function _reward(address account, uint256 amount) internal override {
        if (amount == 0) return;
        rewardVault.distribute(account, amount);
    }

    /// @notice Lock staked PW in this contract.
    ///         msg.value is already held in the contract by the time _lock() is called.
    ///         Returns the locked value unchanged (1:1 PW stake).
    function _lock(uint256 value) internal override returns (uint256) {
        return value;
    }

    /// @notice Return staked PW to the validator on removal.
    function _unlock(address to, uint256 value) internal override {
        (bool ok,) = to.call{value: value}("");
        if (!ok) revert StakeTransferFailed(to, value);
        emit StakeReturned(to, value);
    }

    // ── Receive ───────────────────────────────────────────────────────────────

    /// @dev Accept native PW. Required for stake deposits via initiateValidatorRegistration.
    receive() external payable {}
}
