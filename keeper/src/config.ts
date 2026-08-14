/**
 * PrimeWave Chain Keeper — Configuration
 * C11 Production Infrastructure
 *
 * All configuration is read from environment variables.
 * No defaults for production-sensitive values (RPC, keys).
 */

export interface KeeperConfig {
  // Chain / RPC
  rpcUrl: string;
  chainId: number;

  // Contract addresses
  registryAddress: string;
  validatorManagerAddress: string;

  // Keeper operational account (for tx submission — no admin role needed)
  keeperPrivateKey: string;

  // Polling
  pollIntervalMs: number;         // Default: 30_000 (30s)
  confirmationBlocks: number;     // Default: 1

  // Retry
  maxRetries: number;             // Default: 5
  retryDelayMs: number;           // Default: 5_000 (5s)
  retryBackoffMultiplier: number; // Default: 2

  // Health server
  healthPort: number;             // Default: 8080

  // State persistence
  stateFilePath: string;          // Default: ./keeper-state.json

  // Alerting
  alertOnConsecutiveFailures: number; // Default: 3
  logLevel: 'debug' | 'info' | 'warn' | 'error';
}

export function loadConfig(): KeeperConfig {
  const required = (key: string): string => {
    const v = process.env[key];
    if (!v) throw new Error(`Keeper: required env var ${key} is not set`);
    return v;
  };

  const optional = (key: string, def: string): string =>
    process.env[key] ?? def;

  return {
    rpcUrl:                  required('KEEPER_RPC_URL'),
    chainId:                 parseInt(required('KEEPER_CHAIN_ID'), 10),
    registryAddress:         required('KEEPER_REGISTRY_ADDRESS'),
    validatorManagerAddress: required('KEEPER_VALIDATOR_MANAGER_ADDRESS'),
    keeperPrivateKey:        required('KEEPER_PRIVATE_KEY'),

    pollIntervalMs:          parseInt(optional('KEEPER_POLL_INTERVAL_MS', '30000'), 10),
    confirmationBlocks:      parseInt(optional('KEEPER_CONFIRMATION_BLOCKS', '1'), 10),

    maxRetries:              parseInt(optional('KEEPER_MAX_RETRIES', '5'), 10),
    retryDelayMs:            parseInt(optional('KEEPER_RETRY_DELAY_MS', '5000'), 10),
    retryBackoffMultiplier:  parseFloat(optional('KEEPER_RETRY_BACKOFF', '2')),

    healthPort:              parseInt(optional('KEEPER_HEALTH_PORT', '8080'), 10),
    stateFilePath:           optional('KEEPER_STATE_FILE', './keeper-state.json'),

    alertOnConsecutiveFailures: parseInt(optional('KEEPER_ALERT_THRESHOLD', '3'), 10),
    logLevel:               (optional('KEEPER_LOG_LEVEL', 'info') as KeeperConfig['logLevel']),
  };
}

// ABI fragments — only the functions the keeper calls
export const REGISTRY_ABI = [
  // Read
  'function managedCount() external view returns (uint256)',
  'function managedValidators(uint256 index) external view returns (bytes32)',
  'function isManaged(bytes32 validationID) external view returns (bool)',
  'function validatorStatus(bytes32 validationID) external view returns (uint8)',

  // Write (permissionless)
  'function syncValidator(bytes32 validationID) external',
  'function updateWeight(bytes32 validationID) external',
  'function syncAll() external',

  // Events
  'event ValidatorRegistered(bytes32 indexed validationID, address indexed recipient, uint64 weight, uint16 uptimeBips)',
  'event ValidatorSynced(bytes32 indexed validationID, uint8 indexed toStatus, bool active)',
  'event ValidatorWeightUpdated(bytes32 indexed validationID, uint64 newWeight)',
] as const;

export const VALIDATOR_MANAGER_ABI = [
  'function getValidator(bytes32 validationID) external view returns (tuple(uint8 status, bytes nodeID, uint64 startingWeight, uint64 sentNonce, uint64 receivedNonce, uint64 weight, uint64 startTime, uint64 endTime))',
  'function l1TotalWeight() external view returns (uint64)',

  // Events to watch for state changes
  'event ValidationPeriodRegistered(bytes32 indexed validationID, bytes32 indexed nodeID, uint256 registrationExpiry)',
  'event ValidationPeriodEnded(bytes32 indexed validationID, uint8 indexed status)',
  'event ValidatorWeightUpdate(bytes32 indexed validationID, uint64 nonce, uint64 totalWeight, uint64 weight)',
] as const;

// Validator status enum — mirrors PrimeWaveValidatorRegistry.sol
export enum ValidatorStatus {
  Unknown        = 0,
  PendingAdded   = 1,
  Active         = 2,
  PendingRemoved = 3,
  Completed      = 4,
  Invalidated    = 5,
}
