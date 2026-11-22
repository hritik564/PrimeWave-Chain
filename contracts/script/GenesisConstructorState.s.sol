// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Script.sol";
import {RewardVault} from "../src/RewardVault.sol";
import {PrimeWaveTimelock} from "../src/PrimeWaveTimelock.sol";
import {EmergencyMultisig} from "../src/EmergencyMultisig.sol";
import {FeeDistributor} from "../src/FeeDistributor.sol";
import {ValidatorFeeVault} from "../src/ValidatorFeeVault.sol";
import {PrimeWaveValidatorRegistry} from "../src/PrimeWaveValidatorRegistry.sol";

contract GenesisAuthoringFunder {
    function fund(address payable vault) external {
        RewardVault(vault).fund{value: 15_000_000 ether}();
    }
}

/// @notice Offline state compiler only. No startBroadcast, key reads or RPC.
/// All target addresses come from an explicit PUBLIC manifest, never defaults.
contract GenesisConstructorState is Script {
    struct PublicConfig {
        address timelock;
        address emergency;
        address feeVault;
        address feeDistributor;
        address registry;
        address rewardVault;
        address manager;
        address treasury;
        address governance;
        address[5] signers;
        uint256 genesisTimestamp;
    }
    mapping(address => bytes32[]) private constructorSlots;

    function copyConstructor(address source, address target) internal {
        require(target != address(0) && target.code.length == 0, "genesis: occupied/zero target");
        (, bytes32[] memory writes) = vm.accesses(source);
        vm.etch(target, source.code);
        vm.setNonce(target, 1);
        for (uint256 i; i < writes.length; ++i) {
            vm.store(target, writes[i], vm.load(source, writes[i]));
            constructorSlots[target].push(writes[i]);
        }
    }

    function build(PublicConfig memory m) public {
        vm.warp(m.genesisTimestamp);
        vm.roll(0);
        vm.record();
        PrimeWaveTimelock timelock = new PrimeWaveTimelock(m.governance);
        copyConstructor(address(timelock), m.timelock);
        EmergencyMultisig emergency = new EmergencyMultisig(m.signers);
        copyConstructor(address(emergency), m.emergency);
        buildCore(m);
    }

    /// @dev Shared core export; callers must first author the selected governance
    /// and emergency state at their final public addresses.
    function buildCore(PublicConfig memory m) internal {
        ValidatorFeeVault fees = new ValidatorFeeVault(m.registry);
        copyConstructor(address(fees), m.feeVault);
        FeeDistributor distributor = new FeeDistributor(payable(m.feeVault), payable(m.treasury), m.emergency);
        copyConstructor(address(distributor), m.feeDistributor);
        PrimeWaveValidatorRegistry registry = new PrimeWaveValidatorRegistry(m.timelock, m.manager, m.feeVault);
        copyConstructor(address(registry), m.registry);
        RewardVault vault = new RewardVault(m.timelock, uint256(3_000_000 ether) / 31_536_000);
        copyConstructor(address(vault), m.rewardVault);
        // Synthetic authoring-EVM funding only. The builder/source accounts are
        // never exported: final genesis seeds the vault with exactly the C00 15M.
        GenesisAuthoringFunder authoringFunder = new GenesisAuthoringFunder();
        vm.deal(address(authoringFunder), 15_000_000 ether);
        authoringFunder.fund(payable(m.rewardVault));
        // Explicit genesis bootstrap state, approved as part of final genesis;
        // no future timelock delay is bypassed by an on-chain transaction.
        vm.prank(m.timelock);
        RewardVault(payable(m.rewardVault)).setPauseController(m.emergency);
        vm.prank(m.registry);
        ValidatorFeeVault(payable(m.feeVault)).setPauseController(m.emergency);
        require(RewardVault(payable(m.rewardVault)).totalFunded() == 15_000_000 ether, "genesis: unaccounted rewards");
        require(m.rewardVault.balance == 15_000_000 ether, "genesis: reward balance mismatch");
        require(FeeDistributor(payable(m.feeDistributor)).VALIDATOR_BPS() == 7000, "genesis: fee split");
        require(FeeDistributor(payable(m.feeDistributor)).TREASURY_BPS() == 2000, "genesis: fee split");
    }

    function accountJson(address account) public returns (string memory) {
        string memory key = string.concat("account-", vm.toString(account));
        string memory storageKey = string.concat("storage-", vm.toString(account));
        (, bytes32[] memory writes) = vm.accesses(account);
        string memory storageJson = "{}";
        for (uint256 i; i < constructorSlots[account].length; ++i) {
            bytes32 slot = constructorSlots[account][i];
            storageJson = vm.serializeString(storageKey, vm.toString(slot), vm.toString(vm.load(account, slot)));
        }
        for (uint256 i; i < writes.length; ++i) {
            storageJson = vm.serializeString(storageKey, vm.toString(writes[i]), vm.toString(vm.load(account, writes[i])));
        }
        vm.serializeString(key, "code", vm.toString(account.code));
        vm.serializeString(key, "balance", vm.toString(account.balance));
        vm.serializeString(key, "nonce", "0x1");
        return vm.serializeString(key, "storage", storageJson);
    }

    function readPublicConfig(string memory raw) internal returns(PublicConfig memory m) {
        require(vm.parseJsonBool(raw, ".publicAddressesReviewed"), "genesis: public address review required");
        m.genesisTimestamp = vm.parseJsonUint(raw, ".genesisTimestamp");
        m.timelock = vm.parseJsonAddress(raw, ".contracts.timelock");
        m.emergency = vm.parseJsonAddress(raw, ".contracts.emergency");
        m.feeVault = vm.parseJsonAddress(raw, ".contracts.feeVault");
        m.feeDistributor = vm.parseJsonAddress(raw, ".contracts.feeDistributor");
        m.registry = vm.parseJsonAddress(raw, ".contracts.registry");
        m.rewardVault = vm.parseJsonAddress(raw, ".contracts.rewardVault");
        m.manager = vm.parseJsonAddress(raw, ".managerAddress");
        m.treasury = vm.parseJsonAddress(raw, ".allocationAddresses.treasury");
        m.governance = vm.parseJsonAddress(raw, ".governanceProposer");
        for (uint256 i; i < 5; ++i) {
            m.signers[i] = vm.parseJsonAddress(raw, string.concat(".emergencySigners[", vm.toString(i), "]"));
        }
    }

    function run() external virtual {
        string memory raw = vm.readFile(vm.envString("GENESIS_PUBLIC_MANIFEST"));
        PublicConfig memory m=readPublicConfig(raw);
        build(m);
        address[6] memory targets = [m.timelock,m.emergency,m.feeVault,m.feeDistributor,m.registry,m.rewardVault];
        string memory out = "{}";
        for (uint256 i; i < targets.length; ++i) {
            out = vm.serializeString("genesis-accounts", vm.toString(targets[i]), accountJson(targets[i]));
        }
        vm.writeJson(out, vm.envString("GENESIS_STATE_OUTPUT"));
    }
}
