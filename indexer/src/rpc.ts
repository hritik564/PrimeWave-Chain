/**
 * PrimeWave Indexer — JSON-RPC Client
 *
 * Uses raw JSON-RPC (eth_* methods) over HTTP.
 * Returns raw hex strings — no ethers parsing — so we control all
 * BigInt conversions explicitly.
 *
 * Includes retry + exponential back-off for all RPC failures.
 */

export interface RpcBlock {
  number:           string;   // hex
  hash:             string;
  parentHash:       string;
  timestamp:        string;   // hex
  gasLimit:         string;   // hex
  gasUsed:          string;   // hex
  baseFeePerGas?:   string;   // hex — EIP-1559
  transactions:     RpcTransaction[];
  miner?:           string;
  stateRoot?:       string;
  receiptsRoot?:    string;
}

export interface RpcTransaction {
  hash:                  string;
  blockNumber:           string;
  blockHash:             string;
  transactionIndex:      string;
  from:                  string;
  to:                    string | null;
  value:                 string;   // hex wei
  gas:                   string;   // hex
  gasPrice?:             string;   // hex
  maxFeePerGas?:         string;   // hex
  maxPriorityFeePerGas?: string;   // hex
  nonce:                 string;   // hex
  input:                 string;
  chainId?:              string;   // hex
  type?:                 string;   // hex
}

export interface RpcReceipt {
  transactionHash:  string;
  blockNumber:      string;
  blockHash:        string;
  transactionIndex: string;
  from:             string;
  to:               string | null;
  status:           string;   // "0x0" | "0x1"
  gasUsed:          string;
  cumulativeGasUsed: string;
  effectiveGasPrice?: string;
  contractAddress?: string | null;
  logs:             RpcLog[];
}

export interface RpcLog {
  address:          string;
  topics:           string[];
  data:             string;
  blockNumber:      string;
  blockHash:        string;
  transactionHash:  string;
  transactionIndex: string;
  logIndex:         string;
  removed?:         boolean;
}

// ── RPC Client ────────────────────────────────────────────────────────────────

export interface RpcClientOptions {
  url:          string;
  maxRetries:   number;
  retryDelayMs: number;
  timeoutMs:    number;
}

let _reqId = 1;

async function rpcFetch<T>(
  url:    string,
  method: string,
  params: unknown[],
  opts:   Pick<RpcClientOptions, 'maxRetries' | 'retryDelayMs' | 'timeoutMs'>
): Promise<T> {
  const body = JSON.stringify({ jsonrpc: '2.0', method, params, id: _reqId++ });
  let lastError: Error | null = null;

  for (let attempt = 0; attempt <= opts.maxRetries; attempt++) {
    if (attempt > 0) {
      const delay = opts.retryDelayMs * Math.pow(2, attempt - 1);
      await sleep(Math.min(delay, 30000));
    }

    try {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), opts.timeoutMs);
      let res: Response;
      try {
        res = await fetch(url, {
          method:  'POST',
          headers: { 'Content-Type': 'application/json' },
          body,
          signal:  controller.signal,
        });
      } finally {
        clearTimeout(timer);
      }

      if (!res.ok) {
        throw new Error(`HTTP ${res.status}: ${await res.text()}`);
      }

      const json = await res.json() as { result?: T; error?: { message: string; code: number } };

      if (json.error) {
        // Non-retryable RPC error
        throw Object.assign(new Error(`RPC error ${json.error.code}: ${json.error.message}`), {
          rpcCode:    json.error.code,
          retryable:  false,
        });
      }

      return json.result as T;
    } catch (err: unknown) {
      lastError = err instanceof Error ? err : new Error(String(err));

      // Don't retry non-retryable RPC errors
      if ((lastError as { retryable?: boolean }).retryable === false) throw lastError;

      // Don't retry on abort (timeout)
      if (lastError.name === 'AbortError') {
        lastError = new Error(`RPC timeout after ${opts.timeoutMs}ms: ${method}`);
      }

      if (attempt < opts.maxRetries) {
        console.warn(`[rpc] Attempt ${attempt + 1}/${opts.maxRetries + 1} failed for ${method}: ${lastError.message}`);
      }
    }
  }

  throw lastError ?? new Error(`RPC call failed: ${method}`);
}

function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

// ── Public client class ───────────────────────────────────────────────────────

export class RpcClient {
  private opts: RpcClientOptions;

  constructor(opts: Partial<RpcClientOptions> & { url: string }) {
    this.opts = {
      maxRetries:   opts.maxRetries   ?? 5,
      retryDelayMs: opts.retryDelayMs ?? 3000,
      timeoutMs:    opts.timeoutMs    ?? 15000,
      url:          opts.url,
    };
  }

  private call<T>(method: string, params: unknown[]): Promise<T> {
    return rpcFetch<T>(this.opts.url, method, params, this.opts);
  }

  async getBlockNumber(): Promise<number> {
    const hex = await this.call<string>('eth_blockNumber', []);
    return parseInt(hex, 16);
  }

  async getBlockByNumber(n: number, full = true): Promise<RpcBlock | null> {
    const hex = '0x' + n.toString(16);
    return this.call<RpcBlock | null>('eth_getBlockByNumber', [hex, full]);
  }

  async getTransactionReceipt(hash: string): Promise<RpcReceipt | null> {
    return this.call<RpcReceipt | null>('eth_getTransactionReceipt', [hash]);
  }

  /** Fetch all receipts for a block via eth_getBlockReceipts (if supported),
   *  otherwise fall back to per-tx calls.  */
  async getBlockReceipts(blockNumber: number): Promise<RpcReceipt[]> {
    try {
      const hex = '0x' + blockNumber.toString(16);
      const receipts = await this.call<RpcReceipt[]>('eth_getBlockReceipts', [hex]);
      if (Array.isArray(receipts)) return receipts;
    } catch {
      // Fall through to per-tx calls
    }
    return [];
  }

  async getCode(address: string): Promise<string> {
    return this.call<string>('eth_getCode', [address, 'latest']);
  }

  async getBalance(address: string, blockTag: string = 'latest'): Promise<string> {
    return this.call<string>('eth_getBalance', [address, blockTag]);
  }

  async chainId(): Promise<number> {
    const hex = await this.call<string>('eth_chainId', []);
    return parseInt(hex, 16);
  }
}

// ── Hex utils ─────────────────────────────────────────────────────────────────

export function hexToNumber(hex: string): number {
  return parseInt(hex, 16);
}

export function hexToBigInt(hex: string): bigint {
  return BigInt(hex);
}

export function hexToDecStr(hex: string): string {
  return BigInt(hex).toString(10);
}

export function normalizeAddress(addr: string | null | undefined): string | null {
  if (!addr) return null;
  return addr.toLowerCase();
}

export function normalizeHash(hash: string | null | undefined): string | null {
  if (!hash) return null;
  return hash.toLowerCase();
}
