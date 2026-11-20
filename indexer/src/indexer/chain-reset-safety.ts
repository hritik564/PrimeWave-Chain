export interface RpcBlockIdentity {
  hash: string;
}

export class ChainResetRequiredError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ChainResetRequiredError';
  }
}

export class ChainResetCheckUnavailableError extends Error {
  constructor() {
    super(
      'Could not verify indexed chain state because RPC is unavailable. No indexed data was deleted; retry after RPC recovers.',
    );
    this.name = 'ChainResetCheckUnavailableError';
  }
}

export async function assertIndexedBlockMatchesRpc(
  blockNumber: number,
  indexedHash: string | null,
  getBlock: (number: number) => Promise<RpcBlockIdentity | null>,
): Promise<void> {
  let rpcBlock: RpcBlockIdentity | null;
  try {
    rpcBlock = await getBlock(blockNumber);
  } catch {
    throw new ChainResetCheckUnavailableError();
  }

  if (!rpcBlock) {
    throw new ChainResetRequiredError(
      `Indexed block ${blockNumber} is absent from the configured RPC. No indexed data was deleted; an explicit maintenance reindex is required.`,
    );
  }

  if (
    indexedHash &&
    rpcBlock.hash.toLowerCase() !== indexedHash.toLowerCase()
  ) {
    throw new ChainResetRequiredError(
      `Indexed block ${blockNumber} does not match the configured RPC. No indexed data was deleted; an explicit maintenance reindex is required.`,
    );
  }
}
