/**
 * GET /identity — read-only live RPC identity check.
 *
 * The RPC endpoint remains server-side. This response contains only public
 * network identity metadata and is used to gate explorer data requests.
 */

import { Router, Request, Response } from 'express';
import { IndexerConfig } from '../../config';
import { ok } from '../validation';

interface RpcIdentity {
  chainId: number;
  genesisHash: string;
}

interface RpcPayload {
  result?: unknown;
  error?: unknown;
}

async function rpcCall(
  rpcUrl: string,
  method: string,
): Promise<unknown> {
  const response = await fetch(rpcUrl, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      jsonrpc: '2.0',
      method,
      params: method === 'eth_getBlockByNumber' ? ['0x0', false] : [],
      id: method === 'eth_chainId' ? 1 : 2,
    }),
    signal: AbortSignal.timeout(5000),
  });

  if (!response.ok) throw new Error('RPC request failed');
  const payload = await response.json() as RpcPayload;
  if (payload.error || payload.result === undefined || payload.result === null) {
    throw new Error('RPC returned an invalid identity response');
  }
  return payload.result;
}

export async function readRpcIdentity(rpcUrl: string): Promise<RpcIdentity> {
  const [chainIdResult, genesisResult] = await Promise.all([
    rpcCall(rpcUrl, 'eth_chainId'),
    rpcCall(rpcUrl, 'eth_getBlockByNumber'),
  ]);

  if (typeof chainIdResult !== 'string' || !/^0x[0-9a-f]+$/i.test(chainIdResult)) {
    throw new Error('RPC returned an invalid chain ID');
  }

  const chainId = Number.parseInt(chainIdResult, 16);
  if (!Number.isSafeInteger(chainId) || chainId < 1) {
    throw new Error('RPC returned an invalid chain ID');
  }

  if (
    typeof genesisResult !== 'object' ||
    genesisResult === null ||
    !('hash' in genesisResult) ||
    typeof genesisResult.hash !== 'string' ||
    !/^0x[0-9a-f]{64}$/i.test(genesisResult.hash)
  ) {
    throw new Error('RPC returned an invalid genesis block');
  }

  return {
    chainId,
    genesisHash: genesisResult.hash.toLowerCase(),
  };
}

export default function identityRouter(config: IndexerConfig): Router {
  const router = Router();
  let cached: { expiresAt: number; identity: RpcIdentity } | null = null;
  let pending: Promise<RpcIdentity> | null = null;
  let consecutiveFailures = 0;
  let circuitOpenUntil = 0;

  router.get('/', async (_req: Request, res: Response) => {
    if (circuitOpenUntil > Date.now()) {
      res.status(503).json({
        success: false,
        error: 'Network identity temporarily unavailable',
      });
      return;
    }

    try {
      const now = Date.now();
      let identity: RpcIdentity;
      if (cached && cached.expiresAt > now) {
        identity = cached.identity;
      } else {
        pending ??= readRpcIdentity(config.rpcUrl);
        try {
          identity = await pending;
          cached = { identity, expiresAt: Date.now() + 15_000 };
          consecutiveFailures = 0;
        } finally {
          pending = null;
        }
      }

      const expectedGenesisHash = config.expectedGenesisHash;
      const verified =
        identity.chainId === config.chainId &&
        (!expectedGenesisHash || identity.genesisHash === expectedGenesisHash);

      res.json(ok({
        chainId: identity.chainId,
        genesisHash: identity.genesisHash,
        expectedGenesisHash,
        verified,
      }));
    } catch {
      consecutiveFailures += 1;
      if (consecutiveFailures >= 3) {
        circuitOpenUntil = Date.now() + 10_000;
      }
      res.status(503).json({
        success: false,
        error: circuitOpenUntil > Date.now()
          ? 'Network identity temporarily unavailable'
          : 'Network identity unavailable',
      });
    }
  });

  return router;
}
