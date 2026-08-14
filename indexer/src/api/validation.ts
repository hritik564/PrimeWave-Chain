/**
 * PrimeWave Indexer API — Input Validation
 *
 * All user-supplied query params and path params must be validated before use.
 * No raw user input is ever interpolated into SQL strings.
 */

export class ValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ValidationError';
  }
}

// ── Regex patterns ────────────────────────────────────────────────────────────

const HEX_ADDR   = /^0x[0-9a-fA-F]{40}$/;
const HEX_HASH   = /^0x[0-9a-fA-F]{64}$/;
const HEX_BYTES32 = /^0x[0-9a-fA-F]{64}$/;

// ── Validators ────────────────────────────────────────────────────────────────

export function validateAddress(value: string, field = 'address'): string {
  if (!HEX_ADDR.test(value)) {
    throw new ValidationError(`${field}: must be a 0x-prefixed 20-byte hex string`);
  }
  return value.toLowerCase();
}

export function validateHash(value: string, field = 'hash'): string {
  if (!HEX_HASH.test(value)) {
    throw new ValidationError(`${field}: must be a 0x-prefixed 32-byte hex string`);
  }
  return value.toLowerCase();
}

export function validateValidatorId(value: string, field = 'validatorId'): string {
  if (!HEX_BYTES32.test(value)) {
    throw new ValidationError(`${field}: must be a 0x-prefixed 32-byte hex string`);
  }
  return value.toLowerCase();
}

export function validateBlockNumber(value: string, field = 'blockNumber'): number {
  const n = parseInt(value, 10);
  if (isNaN(n) || n < 0 || String(n) !== value) {
    throw new ValidationError(`${field}: must be a non-negative integer`);
  }
  return n;
}

export function validatePagination(
  limitStr: string | undefined,
  afterStr: string | undefined,
  maxLimit: number,
  defaultLimit: number
): { limit: number; after: number | null } {
  let limit = defaultLimit;
  if (limitStr !== undefined) {
    const n = parseInt(limitStr, 10);
    if (isNaN(n) || n < 1 || n > maxLimit) {
      throw new ValidationError(`limit: must be 1–${maxLimit}`);
    }
    limit = n;
  }

  let after: number | null = null;
  if (afterStr !== undefined) {
    const n = parseInt(afterStr, 10);
    if (isNaN(n) || n < 0) {
      throw new ValidationError('after: must be a non-negative integer cursor');
    }
    after = n;
  }

  return { limit, after };
}

/** Standard API response wrapper. */
export function ok<T>(data: T, meta?: Record<string, unknown>): Record<string, unknown> {
  return meta ? { success: true, data, ...meta } : { success: true, data };
}

export function err(message: string, status = 400): { status: number; body: Record<string, unknown> } {
  return { status, body: { success: false, error: message } };
}
