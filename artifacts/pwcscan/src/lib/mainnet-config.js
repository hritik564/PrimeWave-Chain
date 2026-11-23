export const PRIMEWAVE_MAINNET_CHAIN_ID = 735;
export const PRIMEWAVE_MAINNET_SUBNET_ID =
  '24Bvo25NiZTeC95Q7kMwW116kp5su7yj43QyKagrZZULhrmYkF';
export const PRIMEWAVE_MAINNET_BLOCKCHAIN_ID =
  '6YLeDTNiHRJefJQQTRms3EkWn4D2Rhcwv5PC547vg6KbLc3jF';

const BASE58_ID = /^[1-9A-HJ-NP-Za-km-z]{40,60}$/;

function requireEndpoint(value, protocol, expectedPath, label) {
  if (!value) throw new Error(`Mainnet ${label} endpoint is required.`);
  let url;
  try {
    url = new URL(value);
  } catch {
    throw new Error(`Mainnet ${label} endpoint must be an absolute ${protocol} URL.`);
  }
  if (
    url.protocol !== protocol ||
    url.username ||
    url.password ||
    url.search ||
    url.hash ||
    url.pathname.replace(/\/$/, '') !== expectedPath
  ) {
    throw new Error(
      `Mainnet ${label} endpoint must use ${protocol}, contain no embedded credentials/query, and end at ${expectedPath}.`,
    );
  }
  return url.toString();
}

function requireIndexerUrl(value) {
  if (!value) throw new Error('Mainnet indexer API endpoint is required.');
  if (value.startsWith('/')) {
    if (value.startsWith('//') || value.includes('..') || value.includes('?')) {
      throw new Error('Mainnet indexer API relative path is invalid.');
    }
    return value.replace(/\/$/, '');
  }
  let url;
  try {
    url = new URL(value);
  } catch {
    throw new Error('Mainnet indexer API must be a same-origin path or HTTPS URL.');
  }
  if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash) {
    throw new Error('Mainnet indexer API URL must use HTTPS and contain no embedded credentials/query.');
  }
  return url.toString().replace(/\/$/, '');
}

export function buildMainnetNetwork(env) {
  if (env.VITE_MAINNET_CHAIN_ID && Number(env.VITE_MAINNET_CHAIN_ID) !== PRIMEWAVE_MAINNET_CHAIN_ID) {
    throw new Error(`PrimeWave Mainnet Chain ID is fixed at ${PRIMEWAVE_MAINNET_CHAIN_ID}.`);
  }

  const configuredBlockchainId = env.VITE_MAINNET_BLOCKCHAIN_ID?.trim() || undefined;
  if (configuredBlockchainId && configuredBlockchainId !== PRIMEWAVE_MAINNET_BLOCKCHAIN_ID) {
    throw new Error('PrimeWave Mainnet BlockchainID does not match the accepted chain.');
  }
  const blockchainId = PRIMEWAVE_MAINNET_BLOCKCHAIN_ID;
  const rpc = env.VITE_MAINNET_RPC_URL?.trim() || undefined;
  const ws = env.VITE_MAINNET_WS_URL?.trim() || undefined;
  const indexer = env.VITE_MAINNET_INDEXER_API_URL?.trim() || undefined;
  // The accepted BlockchainID is pinned even while the RPC gateways are not
  // provisioned; only endpoint/chain overrides indicate partial configuration.
  const hasAny = Boolean(rpc || ws || indexer || env.VITE_MAINNET_CHAIN_ID);

  const base = {
    chainId: PRIMEWAVE_MAINNET_CHAIN_ID,
    subnetId: PRIMEWAVE_MAINNET_SUBNET_ID,
    blockchainId,
    nativeCurrency: { name: 'PrimeWave', symbol: 'PW', decimals: 18 },
    rpcUrl: null,
    websocketUrl: null,
    indexerApiUrl: null,
    status: 'unconfigured',
    description: 'Not connected: verified RPC and indexer gateway configuration required',
  };
  if (!hasAny) return base;

  if (!blockchainId || !rpc || !ws || !indexer) {
    throw new Error(
      'Mainnet requires BlockchainID, HTTP RPC, WebSocket RPC and indexer API configuration together.',
    );
  }
  if (!BASE58_ID.test(blockchainId)) {
    throw new Error('Mainnet BlockchainID must be the accepted Avalanche BlockchainID (CB58 form).');
  }
  const rpcPath = `/ext/bc/${blockchainId}/rpc`;
  const wsPath = `/ext/bc/${blockchainId}/ws`;
  return {
    ...base,
    blockchainId,
    rpcUrl: requireEndpoint(rpc, 'https:', rpcPath, 'HTTP RPC'),
    websocketUrl: requireEndpoint(ws, 'wss:', wsPath, 'WebSocket RPC'),
    indexerApiUrl: requireIndexerUrl(indexer),
    status: 'configured',
    description: 'PrimeWave Mainnet',
  };
}
