import { isIP } from 'node:net';

export const LOCAL_DEV_CHAIN_ID = 73571;
export const LOCAL_DEV_RPC_PORT = '9656';

type Environment = Record<string, string | undefined>;

export function assertDevelopmentDatabaseSafety(
  env: Environment = process.env,
): void {
  if (env.NODE_ENV === 'production') return;

  const dbUrl = env.INDEXER_DB_URL?.trim();
  if (!dbUrl) {
    throw new Error('INDEXER_DB_URL must explicitly identify the development database.');
  }

  if (
    env.INDEXER_DB_ENV !== 'development' ||
    env.INDEXER_DB_DISPOSABLE !== 'true' ||
    env.INDEXER_DB_ISOLATED !== 'true'
  ) {
    throw new Error(
      'Development startup requires INDEXER_DB_ENV=development, INDEXER_DB_DISPOSABLE=true, and INDEXER_DB_ISOLATED=true.',
    );
  }

  if (env.DATABASE_URL?.trim() === dbUrl) {
    throw new Error(
      'INDEXER_DB_URL must be distinct from DATABASE_URL for isolated development startup.',
    );
  }
}

export function assertRpcEndpointAllowed(
  rpcUrl: string,
  nodeEnv: string | undefined = process.env.NODE_ENV,
): void {
  if (nodeEnv === 'production') return;

  let parsed: URL;
  try {
    parsed = new URL(rpcUrl);
  } catch {
    throw new Error('Development RPC URL is invalid; expected a loopback URL on port 9656.');
  }

  const hostname = parsed.hostname.replace(/^\[|\]$/g, '').toLowerCase();
  const ipVersion = isIP(hostname);
  const isIpv4Loopback =
    ipVersion === 4 && Number(hostname.split('.')[0]) === 127;
  const isIpv6Loopback = ipVersion === 6 && hostname === '::1';

  if (
    parsed.protocol !== 'http:' ||
    parsed.username !== '' ||
    parsed.password !== '' ||
    parsed.port !== LOCAL_DEV_RPC_PORT ||
    (!isIpv4Loopback && !isIpv6Loopback)
  ) {
    throw new Error(
      'Development RPC must use a literal loopback IP, HTTP, and port 9656.',
    );
  }
}

export async function verifyRpcChainId(
  getChainId: () => Promise<number>,
  expectedChainId: number,
  nodeEnv: string | undefined = process.env.NODE_ENV,
): Promise<void> {
  if (nodeEnv !== 'production' && expectedChainId !== LOCAL_DEV_CHAIN_ID) {
    throw new Error(`Development indexer must be configured for Chain ID ${LOCAL_DEV_CHAIN_ID}.`);
  }

  let actualChainId: number;
  try {
    actualChainId = await getChainId();
  } catch {
    throw new Error(
      'Unable to verify RPC Chain ID; startup aborted before database access.',
    );
  }

  if (!Number.isInteger(actualChainId) || actualChainId !== expectedChainId) {
    throw new Error(
      `RPC Chain ID mismatch: expected ${expectedChainId}, received ${actualChainId}. Startup aborted before database access.`,
    );
  }
}

export function isAutoContractDeploymentEnabled(
  env: Environment = process.env,
): boolean {
  return env.INDEXER_AUTO_DEPLOY === 'true';
}

async function fetchRpcChainId(rpcUrl: string): Promise<number> {
  const response = await fetch(rpcUrl, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      jsonrpc: '2.0',
      method: 'eth_chainId',
      params: [],
      id: 1,
    }),
    signal: AbortSignal.timeout(5000),
  });
  if (!response.ok) throw new Error('RPC request failed');

  const payload = await response.json() as {
    result?: unknown;
    error?: unknown;
  };
  if (
    payload.error ||
    typeof payload.result !== 'string' ||
    !/^0x[0-9a-f]+$/i.test(payload.result)
  ) {
    throw new Error('RPC returned an invalid chain ID response');
  }

  return Number.parseInt(payload.result, 16);
}

async function runCommandLine(): Promise<void> {
  const command = process.argv[2];
  if (command === '--auto-deploy-enabled') {
    process.exitCode = isAutoContractDeploymentEnabled() ? 0 : 1;
    return;
  }
  if (command !== '--preflight') {
    throw new Error('Expected --preflight or --auto-deploy-enabled.');
  }

  assertDevelopmentDatabaseSafety();
  const rpcUrl = process.env.INDEXER_RPC_URL ?? '';
  assertRpcEndpointAllowed(rpcUrl);
  await verifyRpcChainId(
    () => fetchRpcChainId(rpcUrl),
    LOCAL_DEV_CHAIN_ID,
    process.env.NODE_ENV,
  );
  console.log('Development database gate and local RPC identity verified.');
}

if (require.main === module) {
  runCommandLine().catch((error: unknown) => {
    console.error(`[startup-safety] ${(error as Error).message}`);
    process.exitCode = 1;
  });
}
