import assert from 'node:assert/strict';
import test from 'node:test';
import {
  isSafeIndexerUrl,
  verifyNetworkIdentity,
  type NetworkIdentity,
} from './network-identity';

const expectedHash = `0x${'ab'.repeat(32)}`;

function identity(overrides: Partial<NetworkIdentity> = {}): NetworkIdentity {
  return {
    chainId: 73571,
    genesisHash: expectedHash,
    expectedGenesisHash: expectedHash,
    verified: true,
    ...overrides,
  };
}

test('Mainnet identity requires matching Chain ID and genesis hash', () => {
  const expected = {
    id: 'mainnet',
    chainId: 73571,
    expectedGenesisHash: expectedHash,
  };

  assert.deepEqual(verifyNetworkIdentity(expected, identity()), { verified: true });
  assert.equal(
    verifyNetworkIdentity(expected, identity({ chainId: 77 })).reason,
    'chain-id',
  );
  assert.equal(
    verifyNetworkIdentity(
      expected,
      identity({ genesisHash: `0x${'cd'.repeat(32)}` }),
    ).reason,
    'genesis-hash',
  );
});

test('Mainnet does not verify without an approved genesis hash', () => {
  assert.equal(
    verifyNetworkIdentity(
      { id: 'mainnet', chainId: 73571, expectedGenesisHash: null },
      identity(),
    ).verified,
    false,
  );
});

test('Mainnet requires the indexer to report the matching configured hash', () => {
  assert.equal(
    verifyNetworkIdentity(
      { id: 'mainnet', chainId: 73571, expectedGenesisHash: expectedHash },
      identity({ expectedGenesisHash: null }),
    ).reason,
    'server-unverified',
  );
});

test('Testnet can verify its explicit Chain ID without claiming a genesis binding', () => {
  assert.deepEqual(
    verifyNetworkIdentity(
      { id: 'testnet', chainId: 77, expectedGenesisHash: null },
      identity({ chainId: 77, expectedGenesisHash: null }),
    ),
    { verified: true },
  );
});

test('Indexer URLs reject embedded credentials and credential-like query values', () => {
  assert.equal(isSafeIndexerUrl('/indexer-api'), true);
  assert.equal(isSafeIndexerUrl('/indexer-api?token=secret'), false);
  assert.equal(isSafeIndexerUrl('https://indexer.example.invalid/api'), true);
  assert.equal(isSafeIndexerUrl('https://user:pass@indexer.example.invalid/api'), false);
  assert.equal(isSafeIndexerUrl('https://indexer.example.invalid/api?api_key=secret'), false);
  assert.equal(isSafeIndexerUrl('//indexer.example.invalid/api'), false);
});
