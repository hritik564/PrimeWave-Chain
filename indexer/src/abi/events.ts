/**
 * PrimeWave Indexer — Known Event ABIs
 *
 * All event signatures are taken directly from the Solidity source.
 * Do NOT invent signatures. If a contract is changed, update here.
 *
 * References:
 *   contracts/src/FeeDistributor.sol            lines 139-166
 *   contracts/src/ValidatorFeeVault.sol         lines 184-220
 *   contracts/src/RewardVault.sol               lines 190-238
 *   contracts/src/PrimeWaveValidatorRegistry.sol lines 166-179
 *   contracts/src/PrimeWaveStakingManager.sol   lines 65-79
 *   contracts/src/EmergencyMultisig.sol         lines 90-114
 *   contracts/src/PrimeWaveTimelock.sol         lines 84-109
 *   contracts/src/DevTreasury.sol               line 41
 */

import { Interface, LogDescription, id as keccakId } from 'ethers';

// ── Contract event fragments ───────────────────────────────────────────────────

export const FEE_DISTRIBUTOR_EVENTS = [
  'event FeeReceived(uint256 amount, uint256 blockNumber, address indexed sender)',
  'event FeeDistributed(uint256 amount, uint256 validatorShare, uint256 treasuryShare, uint256 burnShare, uint256 indexed blockNumber)',
  'event Paused(address indexed by)',
  'event Unpaused(address indexed by)',
  'event PauseControllerUpdated(address indexed oldController, address indexed newController)',
];

export const VALIDATOR_FEE_VAULT_EVENTS = [
  'event ValidatorRegistered(bytes32 indexed validationId, address indexed rewardRecipient, uint128 baseWeight, uint16 uptimeBips)',
  'event ValidatorActivated(bytes32 indexed validationId)',
  'event ValidatorDeactivated(bytes32 indexed validationId, uint256 checkpointedReward)',
  'event ValidatorUpdated(bytes32 indexed validationId, uint128 baseWeight, uint16 uptimeBips)',
  'event FeeReceived(uint256 amount, uint256 newAccFeePerWeight, uint256 totalEffectiveWeight)',
  'event FeeAccrued(bytes32 indexed validationId, uint256 amount)',
  'event ValidatorRecipientUpdated(bytes32 indexed validationId, address indexed newRecipient)',
  'event ValidatorFeeClaimed(bytes32 indexed validationId, address indexed recipient, uint256 amount)',
  'event UnallocatedDistributed(uint256 amount)',
  'event Paused(address indexed by)',
  'event Unpaused(address indexed by)',
  'event PauseControllerUpdated(address indexed oldController, address indexed newController)',
];

export const REWARD_VAULT_EVENTS = [
  'event StakingManagerSet(address indexed stakingManager)',
  'event StakingRewardDistributed(address indexed to, uint256 amount)',
  'event Paused(address indexed by)',
  'event Unpaused(address indexed by)',
  'event PauseControllerUpdated(address indexed oldController, address indexed newController)',
  'event RewardVaultFunded(address indexed funder, uint256 amount, uint256 newTotalFunded)',
  'event GlobalUpdated(uint256 emitted, uint256 newAccRewardPerWeight, uint256 totalEligibleWeight)',
  'event RewardClaimed(bytes32 indexed recipientId, address indexed rewardAddress, uint256 amount)',
  'event EmissionRateReduced(uint256 oldRatePerSecond, uint256 newRatePerSecond)',
  'event RecipientRegistered(bytes32 indexed recipientId, address indexed rewardAddress, uint128 weight, bool startActive)',
  'event RecipientWeightUpdated(bytes32 indexed recipientId, uint128 oldWeight, uint128 newWeight)',
  'event RecipientActivated(bytes32 indexed recipientId)',
  'event RecipientDeactivated(bytes32 indexed recipientId, uint256 checkpointed)',
  'event RecipientAddressUpdated(bytes32 indexed recipientId, address indexed newRewardAddress)',
];

export const VALIDATOR_REGISTRY_EVENTS = [
  'event ValidatorRegistered(bytes32 indexed validationID, address indexed rewardRecipient, uint64 acp99Weight, uint16 uptimeBips)',
  'event ValidatorSynced(bytes32 indexed validationID, uint8 newStatus, bool nowActive)',
  'event ValidatorWeightUpdated(bytes32 indexed validationID, uint64 newWeight)',
  'event ValidatorUptimeBipsSet(bytes32 indexed validationID, uint16 newBips)',
  'event ValidatorRewardRecipientUpdated(bytes32 indexed validationID, address indexed newRecipient)',
];

export const STAKING_MANAGER_EVENTS = [
  'event StakeDeposited(bytes32 indexed validationID, address indexed staker, uint256 amount)',
  'event StakeReturned(address indexed to, uint256 amount)',
  'event PhaseTransitionInitiated(address indexed stakingManager, address indexed rewardVault)',
  'event PhaseTransitionCompleted(address indexed stakingManager, address indexed rewardVault)',
];

export const EMERGENCY_MULTISIG_EVENTS = [
  'event ProposalCreated(bytes32 indexed proposalId, address indexed proposer, address indexed target, bytes data, uint256 nonce)',
  'event ProposalApproved(bytes32 indexed proposalId, address indexed signer, uint256 approvalCount)',
  'event ProposalExecuted(bytes32 indexed proposalId, address indexed executor, address indexed target, bytes data)',
  'event ProposalCancelled(bytes32 indexed proposalId, address indexed canceller)',
];

export const TIMELOCK_EVENTS = [
  'event OperationScheduled(bytes32 indexed operationId, address indexed proposer_, address indexed target, bytes data, bytes32 predecessor, bytes32 salt, uint256 executeAfter)',
  'event OperationExecuted(bytes32 indexed operationId, address indexed executor, address indexed target, bytes data)',
  'event OperationCancelled(bytes32 indexed operationId, address indexed canceller)',
  'event ProposerTransferred(address indexed oldProposer, address indexed newProposer)',
];

export const DEV_TREASURY_EVENTS = [
  'event TreasuryReceived(uint256 amount, uint256 blockNumber, address indexed sender)',
];

// ── Interfaces ────────────────────────────────────────────────────────────────

export const ifaces = {
  feeDistributor:   new Interface(FEE_DISTRIBUTOR_EVENTS),
  validatorFeeVault: new Interface(VALIDATOR_FEE_VAULT_EVENTS),
  rewardVault:      new Interface(REWARD_VAULT_EVENTS),
  validatorRegistry: new Interface(VALIDATOR_REGISTRY_EVENTS),
  stakingManager:   new Interface(STAKING_MANAGER_EVENTS),
  emergencyMultisig: new Interface(EMERGENCY_MULTISIG_EVENTS),
  timelock:         new Interface(TIMELOCK_EVENTS),
  devTreasury:      new Interface(DEV_TREASURY_EVENTS),
};

// ── Topic0 lookup: topic0 hex → { contractKey, iface } ───────────────────────

export type ContractKey = keyof typeof ifaces;

interface KnownEvent {
  contractKey: ContractKey;
  iface:       Interface;
  name:        string;
}

const _topic0Map = new Map<string, KnownEvent[]>();

function _buildTopic0Map() {
  for (const [key, iface] of Object.entries(ifaces) as [ContractKey, Interface][]) {
    for (const fragment of iface.fragments) {
      if (fragment.type !== 'event') continue;
      const evFrag = fragment as unknown as { type: string; topicHash: string; name: string };
      const topic0 = evFrag.topicHash.toLowerCase();
      const existing = _topic0Map.get(topic0) ?? [];
      existing.push({ contractKey: key, iface, name: evFrag.name });
      _topic0Map.set(topic0, existing);
    }
  }
}

_buildTopic0Map();

// ── Known contract address → Interface mapping (populated at runtime) ─────────

const _addressToIface = new Map<string, Interface>();

/**
 * Register a known contract address so the decoder can match logs by address
 * first, then fall back to topic0 matching across all interfaces.
 */
export function registerContractAddress(address: string, key: ContractKey): void {
  _addressToIface.set(address.toLowerCase(), ifaces[key]);
}

// ── Decoded log type ──────────────────────────────────────────────────────────

export interface DecodedLog {
  eventName:      string;
  eventSignature: string;
  args:           Record<string, unknown>;
}

/**
 * Try to decode a raw log against known PrimeWave ABIs.
 *
 * Strategy:
 *   1. If the log's address is registered → try only that interface.
 *   2. Otherwise, try all interfaces whose topic0 matches.
 *
 * Returns null if the log is unknown or decoding fails.
 * NEVER throws — unknown events must not break indexing.
 */
export function tryDecodeLog(
  address: string,
  topics:  string[],
  data:    string
): DecodedLog | null {
  if (!topics || topics.length === 0) return null;
  const topic0 = topics[0]!.toLowerCase();
  const addr   = address.toLowerCase();

  const candidates: Interface[] = [];

  // Prefer address-matched interface
  const addrIface = _addressToIface.get(addr);
  if (addrIface) {
    candidates.push(addrIface);
  } else {
    // Fall back to topic0 map (any matching interface)
    const byTopic = _topic0Map.get(topic0);
    if (byTopic) candidates.push(...byTopic.map(e => e.iface));
  }

  for (const iface of candidates) {
    try {
      const desc: LogDescription | null = iface.parseLog({ topics, data });
      if (!desc) continue;

      // Serialise args to a plain Record (BigInt → string)
      const args: Record<string, unknown> = {};
      for (const [i, input] of desc.fragment.inputs.entries()) {
        const raw = desc.args[i];
        args[input.name] = serializeArg(raw);
      }

      return {
        eventName:      desc.name,
        eventSignature: desc.signature,
        args,
      };
    } catch {
      // Decoding failed against this interface — try next
    }
  }

  return null;
}

function serializeArg(value: unknown): unknown {
  if (typeof value === 'bigint') return value.toString();
  if (Array.isArray(value)) return value.map(serializeArg);
  if (value !== null && typeof value === 'object') {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
      out[k] = serializeArg(v);
    }
    return out;
  }
  return value;
}

/** Compute keccak256 of an event signature string (for reference). */
export function eventTopic0(signature: string): string {
  return keccakId(signature);
}
