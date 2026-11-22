import {
  assertProductionGenesisBinding,
  assertDevelopmentDatabaseSafety,
  assertRpcEndpointAllowed,
  isAutoContractDeploymentEnabled,
  verifyRpcChainId,
  verifyRpcGenesisHash,
} from '../src/startup-safety';

const isolatedDevelopmentEnv = {
  NODE_ENV: 'development',
  INDEXER_DB_URL: 'postgresql://isolated-development',
  INDEXER_DB_ENV: 'development',
  INDEXER_DB_DISPOSABLE: 'true',
  INDEXER_DB_ISOLATED: 'true',
};

describe('development startup gates', () => {
  test('requires an explicit isolated, disposable development database', () => {
    expect(() => assertDevelopmentDatabaseSafety({
      NODE_ENV: 'development',
      INDEXER_DB_URL: 'postgresql://isolated-development',
    })).toThrow(/INDEXER_DB_ENV=development/);

    expect(() => assertDevelopmentDatabaseSafety(isolatedDevelopmentEnv)).not.toThrow();
  });

  test('rejects reusing the general DATABASE_URL as the development database', () => {
    expect(() => assertDevelopmentDatabaseSafety({
      ...isolatedDevelopmentEnv,
      DATABASE_URL: isolatedDevelopmentEnv.INDEXER_DB_URL,
    })).toThrow(/distinct from DATABASE_URL/);
  });

  test('requires development RPC to be loopback on port 9656', () => {
    expect(() =>
      assertRpcEndpointAllowed('http://127.0.0.1:9656/ext/bc/test/rpc', 'development'),
    ).not.toThrow();
    expect(() =>
      assertRpcEndpointAllowed('http://192.0.2.10:9656/rpc', 'development'),
    ).toThrow(/literal loopback IP/);
    expect(() =>
      assertRpcEndpointAllowed('http://127.0.0.1:9650/rpc', 'development'),
    ).toThrow(/port 9656/);
  });

  test('allows production RPC configuration to remain remote', () => {
    expect(() =>
      assertRpcEndpointAllowed('https://rpc.example.invalid', 'production'),
    ).not.toThrow();
  });

  test('requires a genesis binding for production networks other than Testnet 77', () => {
    expect(() => assertProductionGenesisBinding(77, null, 'production')).not.toThrow();
    expect(() => assertProductionGenesisBinding(73571, null, 'production')).toThrow(
      /INDEXER_EXPECTED_GENESIS_HASH.*before database access/,
    );
    expect(() => assertProductionGenesisBinding(
      73571,
      `0x${'ab'.repeat(32)}`,
      'production',
    )).not.toThrow();
  });

  test('rejects a wrong development chain ID before database startup', async () => {
    await expect(
      verifyRpcChainId(async () => 77, 73571, 'development'),
    ).rejects.toThrow(/expected 73571, received 77/);
  });

  test('fails closed when the RPC identity request is unavailable', async () => {
    await expect(
      verifyRpcChainId(async () => {
        throw new Error('transport details are intentionally not surfaced');
      }, 73571, 'development'),
    ).rejects.toThrow(/startup aborted before database access/);
  });

  test('requires configured genesis identity to match before database startup', async () => {
    const genesisHash = `0x${'ab'.repeat(32)}`;
    await expect(
      verifyRpcGenesisHash(async () => genesisHash, genesisHash),
    ).resolves.toBeUndefined();
    await expect(
      verifyRpcGenesisHash(async () => `0x${'cd'.repeat(32)}`, genesisHash),
    ).rejects.toThrow(/genesis hash mismatch.*before database access/i);
    await expect(
      verifyRpcGenesisHash(async () => null, genesisHash),
    ).rejects.toThrow(/genesis hash mismatch.*before database access/i);
  });

  test('disables contract deployment unless explicitly enabled', () => {
    expect(isAutoContractDeploymentEnabled({})).toBe(false);
    expect(isAutoContractDeploymentEnabled({ INDEXER_AUTO_DEPLOY: 'false' })).toBe(false);
    expect(isAutoContractDeploymentEnabled({ INDEXER_AUTO_DEPLOY: 'true' })).toBe(true);
  });
});
