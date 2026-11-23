import { buildMainnetNetwork } from './mainnet-config.js';
import { isGenesisHash, isSafeIndexerUrl } from './network-identity';

export type NetworkId = 'devnet' | 'testnet' | 'mainnet';
export type NetworkStatus = 'configured' | 'unconfigured';

export type ContractName =
  | 'emergencyMultisig'
  | 'timelock'
  | 'validatorFeeVault'
  | 'devTreasury'
  | 'feeDistributor'
  | 'rewardVault'
  | 'validatorRegistry';

export interface NetworkDefinition {
  id: NetworkId;
  label: string;
  shortLabel: string;
  description: string;
  status: NetworkStatus;
  chainId: number | null;
  subnetId: string | null;
  blockchainId: string | null;
  nativeCurrency: { name: string; symbol: string; decimals: number };
  rpcUrl: string | null;
  websocketUrl: string | null;
  indexerApiUrl: string | null;
  expectedGenesisHash: string | null;
  contractAddresses: Partial<Record<ContractName, string>>;
  visual: {
    color: 'devnet' | 'testnet' | 'mainnet';
    badgeClass: string;
  };
}

const TESTNET_BLOCKCHAIN_ID =
  '22iFuL8GqPYbtnPKNFrq7AzoDfv3FYwq8T93GubRi12LQVjLni';

function envValue(name: string): string | undefined {
  const value = import.meta.env[name];
  return typeof value === 'string' && value.trim() ? value.trim() : undefined;
}

function legacyValueForNetwork(network: NetworkId): string | undefined {
  const legacyLabel = envValue('VITE_NETWORK_LABEL')?.toLowerCase();
  const explicitNetwork =
    legacyLabel === 'testnet'
      ? 'testnet'
      : legacyLabel === 'devnet'
        ? 'devnet'
        : undefined;

  return explicitNetwork === network ? envValue('VITE_INDEXER_API_URL') : undefined;
}

const devnetAddresses: Partial<Record<ContractName, string>> = {
  emergencyMultisig: envValue('VITE_DEVNET_ADDR_EMERGENCY_MULTISIG') ?? '0x5FbDB2315678afecb367f032d93F642f64180aa3',
  timelock: envValue('VITE_DEVNET_ADDR_TIMELOCK') ?? '0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512',
  validatorFeeVault: envValue('VITE_DEVNET_ADDR_VALIDATOR_FEE_VAULT') ?? '0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0',
  devTreasury: envValue('VITE_DEVNET_ADDR_DEV_TREASURY') ?? '0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9',
  feeDistributor: envValue('VITE_DEVNET_ADDR_FEE_DISTRIBUTOR') ?? '0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9',
  rewardVault: envValue('VITE_DEVNET_ADDR_REWARD_VAULT') ?? '0x0165878A594ca255338adfa4d48449f69242Eb8F',
  validatorRegistry: envValue('VITE_DEVNET_ADDR_VALIDATOR_REGISTRY') ?? '0x5FC8d32690cc91D4c39d9d3abcBD16989F875707',
};

const testnetAddresses: Partial<Record<ContractName, string>> = {
  emergencyMultisig: envValue('VITE_TESTNET_ADDR_EMERGENCY_MULTISIG') ?? '0x59a419F3160fa9B4b6aE98b18C2ABA3d5aBb81Fa',
  timelock: envValue('VITE_TESTNET_ADDR_TIMELOCK') ?? '0x7D50dBEb0d38Fe2E3AcdaBF70Fa99228E3Ec6AEE',
  validatorFeeVault: envValue('VITE_TESTNET_ADDR_VALIDATOR_FEE_VAULT') ?? '0x8008e22DB31e787b98dfC891E1076747D17A3EE8',
  devTreasury: envValue('VITE_TESTNET_ADDR_DEV_TREASURY') ?? '0x7Edc50F7cD417d0ac94f3c17E5D57EE4eaa23B89',
  feeDistributor: envValue('VITE_TESTNET_ADDR_FEE_DISTRIBUTOR') ?? '0x27B15970700daC632f0814522118A1c3B200d971',
  rewardVault: envValue('VITE_TESTNET_ADDR_REWARD_VAULT') ?? '0x469B3d8B88006ea5b9eeC9c7c6aD650FB929C7e4',
  validatorRegistry: envValue('VITE_TESTNET_ADDR_VALIDATOR_REGISTRY') ?? '0x14c47a0D544684FC0189Bce13220B38523Fff9da',
};

const testnetIndexerApiUrl =
  envValue('VITE_TESTNET_INDEXER_API_URL') ??
  legacyValueForNetwork('testnet') ??
  null;
const safeTestnetIndexerApiUrl = isSafeIndexerUrl(testnetIndexerApiUrl)
  ? testnetIndexerApiUrl
  : null;

// Devnet is intentionally local-development-only. Never let a production
// build inherit the same-origin Testnet proxy as its indexer endpoint.
export const IS_PRODUCTION_BUILD = import.meta.env.PROD;
const devnetRpcUrl = IS_PRODUCTION_BUILD
  ? null
  : envValue('VITE_DEVNET_RPC_URL') ?? 'http://127.0.0.1:9656';
const devnetIndexerApiUrl = IS_PRODUCTION_BUILD
  ? null
  : envValue('VITE_DEVNET_INDEXER_API_URL') ??
    legacyValueForNetwork('devnet') ??
    '/indexer-api';
const safeDevnetIndexerApiUrl = isSafeIndexerUrl(devnetIndexerApiUrl)
  ? devnetIndexerApiUrl
  : null;

const configuredNetworks: Record<Exclude<NetworkId, 'mainnet'>, NetworkDefinition> = {
  devnet: {
    id: 'devnet',
    label: 'Devnet',
    shortLabel: 'Devnet',
    description: 'Local development',
    status: safeDevnetIndexerApiUrl && devnetRpcUrl ? 'configured' : 'unconfigured',
    chainId: 73571,
    subnetId: null,
    blockchainId: null,
    nativeCurrency: { name: 'PrimeWave', symbol: 'PW', decimals: 18 },
    rpcUrl: devnetRpcUrl,
    websocketUrl: null,
    indexerApiUrl: safeDevnetIndexerApiUrl,
    expectedGenesisHash: null,
    contractAddresses: devnetAddresses,
    visual: {
      color: 'devnet',
      badgeClass: 'border-blue-500/30 bg-blue-500/10 text-blue-700 dark:text-blue-300',
    },
  },
  testnet: {
    id: 'testnet',
    label: 'Testnet',
    shortLabel: 'Testnet',
    description: testnetIndexerApiUrl
      ? 'Chain 77 test environment'
      : 'Chain 77 indexer endpoint pending',
    status: safeTestnetIndexerApiUrl ? 'configured' : 'unconfigured',
    chainId: 77,
    subnetId: null,
    blockchainId: TESTNET_BLOCKCHAIN_ID,
    nativeCurrency: { name: 'PrimeWave', symbol: 'PW', decimals: 18 },
    rpcUrl:
      envValue('VITE_TESTNET_RPC_URL') ??
      `https://rpc.testnet.primewave.xyz/ext/bc/${TESTNET_BLOCKCHAIN_ID}/rpc`,
    websocketUrl: envValue('VITE_TESTNET_WS_URL') ?? null,
    indexerApiUrl: safeTestnetIndexerApiUrl,
    expectedGenesisHash: isGenesisHash(envValue('VITE_TESTNET_GENESIS_HASH'))
      ? envValue('VITE_TESTNET_GENESIS_HASH')!.toLowerCase()
      : null,
    contractAddresses: testnetAddresses,
    visual: {
      color: 'testnet',
      badgeClass: 'border-orange-500/30 bg-orange-500/10 text-orange-700 dark:text-orange-300',
    },
  },
};

const mainnetNetwork = buildMainnetNetwork({
  VITE_MAINNET_CHAIN_ID: envValue('VITE_MAINNET_CHAIN_ID'),
  VITE_MAINNET_BLOCKCHAIN_ID: envValue('VITE_MAINNET_BLOCKCHAIN_ID'),
  VITE_MAINNET_RPC_URL: envValue('VITE_MAINNET_RPC_URL'),
  VITE_MAINNET_WS_URL: envValue('VITE_MAINNET_WS_URL'),
  VITE_MAINNET_INDEXER_API_URL: envValue('VITE_MAINNET_INDEXER_API_URL'),
});
const mainnetExpectedGenesisHashValue = envValue('VITE_MAINNET_GENESIS_HASH');
const mainnetExpectedGenesisHash = isGenesisHash(mainnetExpectedGenesisHashValue)
  ? mainnetExpectedGenesisHashValue.toLowerCase()
  : null;
const mainnetIdentityConfigured =
  mainnetNetwork.status === 'configured' && mainnetExpectedGenesisHash !== null;

export const NETWORKS: Record<NetworkId, NetworkDefinition> = {
  ...configuredNetworks,
  mainnet: {
    id: 'mainnet',
    label: 'Mainnet',
    shortLabel: 'Mainnet',
    description: mainnetIdentityConfigured
      ? 'Identity verification required'
      : 'Launch configuration pending or incomplete',
    status: mainnetIdentityConfigured ? 'configured' : 'unconfigured',
    chainId: mainnetNetwork.chainId,
    subnetId: mainnetNetwork.subnetId,
    blockchainId: mainnetNetwork.blockchainId,
    nativeCurrency: mainnetNetwork.nativeCurrency,
    rpcUrl: mainnetIdentityConfigured ? mainnetNetwork.rpcUrl : null,
    websocketUrl: mainnetIdentityConfigured ? mainnetNetwork.websocketUrl : null,
    indexerApiUrl: mainnetIdentityConfigured ? mainnetNetwork.indexerApiUrl : null,
    expectedGenesisHash: mainnetIdentityConfigured ? mainnetExpectedGenesisHash : null,
    contractAddresses: {},
    visual: {
      color: 'mainnet',
      badgeClass: 'border-emerald-500/30 bg-emerald-500/10 text-emerald-700 dark:text-emerald-300',
    },
  },
};

export const NETWORK_IDS = Object.keys(NETWORKS) as NetworkId[];
export const SAFE_DEFAULT_NETWORK: NetworkId = 'devnet';

export function isNetworkId(value: string | null | undefined): value is NetworkId {
  return Boolean(value && NETWORK_IDS.includes(value as NetworkId));
}

export function isNetworkAvailable(id: NetworkId): boolean {
  if (!IS_PRODUCTION_BUILD) return true;
  return id === 'testnet' || id === 'mainnet';
}

export function getNetwork(id: string): NetworkDefinition {
  if (!isNetworkId(id)) {
    throw new Error(`Unknown network "${id}"`);
  }
  return NETWORKS[id];
}

export function getDefaultNetwork(): NetworkId {
  const configuredDefault = envValue('VITE_DEFAULT_NETWORK');
  const candidate = isNetworkId(configuredDefault)
    ? configuredDefault
    : SAFE_DEFAULT_NETWORK;
  return isNetworkAvailable(candidate) ? candidate : 'testnet';
}

export function validateNetwork(network: NetworkDefinition): void {
  if (network.status === 'unconfigured') return;
  if (!network.indexerApiUrl || network.chainId === null) {
    throw new Error(`${network.label} network is partially configured`);
  }
}

NETWORK_IDS.forEach((id) => validateNetwork(NETWORKS[id]));
