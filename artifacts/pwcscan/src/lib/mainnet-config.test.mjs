import assert from 'node:assert/strict';
import test from 'node:test';
import {
  buildMainnetNetwork,
  PRIMEWAVE_MAINNET_CHAIN_ID,
  PRIMEWAVE_MAINNET_BLOCKCHAIN_ID,
  PRIMEWAVE_MAINNET_SUBNET_ID,
} from './mainnet-config.js';

const blockchainId = PRIMEWAVE_MAINNET_BLOCKCHAIN_ID;
const configured = {
  VITE_MAINNET_BLOCKCHAIN_ID: blockchainId,
  VITE_MAINNET_RPC_URL: `https://rpc.example.invalid/ext/bc/${blockchainId}/rpc`,
  VITE_MAINNET_WS_URL: `wss://rpc.example.invalid/ext/bc/${blockchainId}/ws`,
  VITE_MAINNET_INDEXER_API_URL: '/indexer-api',
};

test('Mainnet remains unconfigured until BlockchainID and all endpoints exist', () => {
  const network = buildMainnetNetwork({});
  assert.equal(network.status, 'unconfigured');
  assert.equal(network.chainId, 735);
  assert.equal(network.subnetId, PRIMEWAVE_MAINNET_SUBNET_ID);
  assert.equal(network.blockchainId, PRIMEWAVE_MAINNET_BLOCKCHAIN_ID);
  assert.deepEqual(network.nativeCurrency, { name: 'PrimeWave', symbol: 'PW', decimals: 18 });
  assert.equal(network.rpcUrl, null);
});

test('complete Mainnet configuration binds HTTP and WebSocket paths to BlockchainID', () => {
  const network = buildMainnetNetwork(configured);
  assert.equal(network.status, 'configured');
  assert.equal(network.chainId, PRIMEWAVE_MAINNET_CHAIN_ID);
  assert.equal(network.blockchainId, blockchainId);
  assert.equal(network.rpcUrl, configured.VITE_MAINNET_RPC_URL);
  assert.equal(network.websocketUrl, configured.VITE_MAINNET_WS_URL);
  assert.equal(network.indexerApiUrl, '/indexer-api');
});

test('rejects a Chain ID override', () => {
  assert.throws(
    () => buildMainnetNetwork({ ...configured, VITE_MAINNET_CHAIN_ID: '73571001' }),
    /fixed at 735/,
  );
});

test('rejects a BlockchainID other than the accepted PrimeWave chain', () => {
  assert.throws(
    () => buildMainnetNetwork({
      ...configured,
      VITE_MAINNET_BLOCKCHAIN_ID: PRIMEWAVE_MAINNET_SUBNET_ID,
      VITE_MAINNET_RPC_URL: `https://rpc.example.invalid/ext/bc/${PRIMEWAVE_MAINNET_SUBNET_ID}/rpc`,
      VITE_MAINNET_WS_URL: `wss://rpc.example.invalid/ext/bc/${PRIMEWAVE_MAINNET_SUBNET_ID}/ws`,
    }),
    /does not match the accepted chain/,
  );
});

test('a known BlockchainID does not imply that Mainnet RPC is live', () => {
  const network = buildMainnetNetwork({ VITE_MAINNET_BLOCKCHAIN_ID: blockchainId });
  assert.equal(network.status, 'unconfigured');
  assert.equal(network.blockchainId, blockchainId);
  assert.equal(network.rpcUrl, null);
  assert.match(network.description, /Not connected/);
});

test('rejects paths not bound to the configured BlockchainID', () => {
  assert.throws(
    () => buildMainnetNetwork({
      ...configured,
      VITE_MAINNET_RPC_URL: `https://rpc.example.invalid/ext/bc/${PRIMEWAVE_MAINNET_SUBNET_ID}/rpc`,
    }),
    /must use https/,
  );
});

test('rejects credentials or query strings in public gateway URLs', () => {
  const rpcWithCredentials = new URL(configured.VITE_MAINNET_RPC_URL);
  rpcWithCredentials.username = 'review-test';
  rpcWithCredentials.password = 'not-for-use';
  assert.throws(
    () => buildMainnetNetwork({
      ...configured,
      VITE_MAINNET_RPC_URL: rpcWithCredentials.toString(),
    }),
    /no embedded credentials\/query/,
  );
  assert.throws(
    () => buildMainnetNetwork({
      ...configured,
      VITE_MAINNET_WS_URL: `wss://rpc.example.invalid/ext/bc/${blockchainId}/ws?token=secret`,
    }),
    /no embedded credentials\/query/,
  );
});
