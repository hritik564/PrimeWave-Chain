/**
 * PrimeWave Indexer — Configuration
 * C12: RPC + Indexing + Chain Data Layer
 *
 * All configuration is read from environment variables at startup.
 * No secrets are hardcoded.
 */

export interface IndexerConfig {
  // Chain
  rpcUrl:          string;
  wsUrl:           string | null;
  chainId:         number;

  // Database
  dbUrl:           string;
  dbPoolMin:       number;
  dbPoolMax:       number;

  // Indexer behaviour
  startBlock:      number;
  pollIntervalMs:  number;
  batchSize:       number;         // blocks fetched per round
  confirmations:   number;         // blocks behind head to consider final
  retryDelayMs:    number;
  maxRetries:      number;

  // API
  apiPort:         number;
  apiMaxLimit:     number;         // max pagination limit
  apiDefaultLimit: number;

  // Known contract addresses (lowercase)
  contracts: {
    feeDistributor:            string | null;
    validatorFeeVault:         string | null;
    devTreasury:               string | null;
    rewardVault:               string | null;
    validatorRegistry:         string | null;
    stakingManager:            string | null;
    emergencyMultisig:         string | null;
    timelock:                  string | null;
  };

  // Logging
  logLevel: 'error' | 'warn' | 'info' | 'debug';
}

function required(key: string): string {
  const v = process.env[key];
  if (!v) throw new Error(`Required env var missing: ${key}`);
  return v;
}

function optional(key: string, fallback: string): string {
  return process.env[key] ?? fallback;
}

function optionalAddr(key: string): string | null {
  const v = process.env[key];
  if (!v) return null;
  return v.toLowerCase();
}

function int(key: string, fallback: number): number {
  const v = process.env[key];
  if (!v) return fallback;
  const n = parseInt(v, 10);
  if (isNaN(n)) throw new Error(`${key} must be an integer, got "${v}"`);
  return n;
}

export function loadConfig(): IndexerConfig {
  return {
    rpcUrl:         required('INDEXER_RPC_URL'),
    wsUrl:          process.env['INDEXER_WS_URL'] ?? null,
    chainId:        int('INDEXER_CHAIN_ID', 73571),

    dbUrl:          required('INDEXER_DB_URL'),
    dbPoolMin:      int('INDEXER_DB_POOL_MIN', 2),
    dbPoolMax:      int('INDEXER_DB_POOL_MAX', 10),

    startBlock:     int('INDEXER_START_BLOCK', 0),
    pollIntervalMs: int('INDEXER_POLL_MS', 2000),
    batchSize:      int('INDEXER_BATCH_SIZE', 100),
    confirmations:  int('INDEXER_CONFIRMATIONS', 1),
    retryDelayMs:   int('INDEXER_RETRY_DELAY_MS', 3000),
    maxRetries:     int('INDEXER_MAX_RETRIES', 5),

    apiPort:         int('INDEXER_API_PORT', 4000),
    apiMaxLimit:     int('INDEXER_API_MAX_LIMIT', 500),
    apiDefaultLimit: int('INDEXER_API_DEFAULT_LIMIT', 25),

    contracts: {
      feeDistributor:   optionalAddr('ADDR_FEE_DISTRIBUTOR'),
      validatorFeeVault: optionalAddr('ADDR_VALIDATOR_FEE_VAULT'),
      devTreasury:      optionalAddr('ADDR_DEV_TREASURY'),
      rewardVault:      optionalAddr('ADDR_REWARD_VAULT'),
      validatorRegistry: optionalAddr('ADDR_VALIDATOR_REGISTRY'),
      stakingManager:   optionalAddr('ADDR_STAKING_MANAGER'),
      emergencyMultisig: optionalAddr('ADDR_EMERGENCY_MULTISIG'),
      timelock:         optionalAddr('ADDR_TIMELOCK'),
    },

    logLevel: (optional('LOG_LEVEL', 'info') as IndexerConfig['logLevel']),
  };
}

/** Config with all contracts explicitly provided — used in tests. */
export function makeTestConfig(overrides: Partial<IndexerConfig> = {}): IndexerConfig {
  return {
    rpcUrl:          'http://localhost:9650',
    wsUrl:           null,
    chainId:         73571,
    dbUrl:           'postgresql://localhost:5432/primewave_test',
    dbPoolMin:       1,
    dbPoolMax:       2,
    startBlock:      0,
    pollIntervalMs:  500,
    batchSize:       10,
    confirmations:   1,
    retryDelayMs:    10,
    maxRetries:      2,
    apiPort:         4001,
    apiMaxLimit:     100,
    apiDefaultLimit: 10,
    contracts: {
      feeDistributor:   '0x' + 'fd'.repeat(20),
      validatorFeeVault: '0x' + 'fv'.repeat(20),
      devTreasury:      '0x' + 'dt'.repeat(20),
      rewardVault:      '0x' + 'rv'.repeat(20),
      validatorRegistry: '0x' + 'vr'.repeat(20),
      stakingManager:   '0x' + 'sm'.repeat(20),
      emergencyMultisig: '0x' + 'em'.repeat(20),
      timelock:         '0x' + 'tl'.repeat(20),
    },
    logLevel:        'error',
    ...overrides,
  };
}
