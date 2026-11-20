import {
  assertIndexedBlockMatchesRpc,
  ChainResetCheckUnavailableError,
  ChainResetRequiredError,
} from '../src/indexer/chain-reset-safety';

describe('chain reset safety', () => {
  test('accepts the matching indexed block without modifying data', async () => {
    await expect(
      assertIndexedBlockMatchesRpc(12, '0xabc', async () => ({ hash: '0xAbC' })),
    ).resolves.toBeUndefined();
  });

  test('requires explicit maintenance for a missing indexed block', async () => {
    await expect(
      assertIndexedBlockMatchesRpc(12, '0xabc', async () => null),
    ).rejects.toBeInstanceOf(ChainResetRequiredError);
  });

  test('requires explicit maintenance for a block-hash mismatch', async () => {
    await expect(
      assertIndexedBlockMatchesRpc(12, '0xabc', async () => ({ hash: '0xdef' })),
    ).rejects.toBeInstanceOf(ChainResetRequiredError);
  });

  test('does not treat an RPC error as a reset or delete indexed data', async () => {
    await expect(
      assertIndexedBlockMatchesRpc(12, '0xabc', async () => {
        throw new Error('temporary transport failure');
      }),
    ).rejects.toBeInstanceOf(ChainResetCheckUnavailableError);
  });
});
