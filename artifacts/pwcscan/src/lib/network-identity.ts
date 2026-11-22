export interface NetworkIdentity {
  chainId: number;
  genesisHash: string;
  expectedGenesisHash: string | null;
  verified: boolean;
}

export interface NetworkIdentityExpectation {
  id: string;
  chainId: number | null;
  expectedGenesisHash: string | null;
}

export function isGenesisHash(value: string | null | undefined): value is string {
  return typeof value === 'string' && /^0x[0-9a-f]{64}$/i.test(value);
}

export function isSafeIndexerUrl(value: string | null | undefined): value is string {
  if (!value?.trim()) return false;
  const normalized = value.trim();
  const isRelative = normalized.startsWith('/') && !normalized.startsWith('//');
  if (!isRelative && normalized.startsWith('/')) return false;

  try {
    const url = isRelative
      ? new URL(normalized, 'https://pwcscan.invalid')
      : new URL(normalized);
    if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password) {
      return false;
    }
    if (url.search || url.hash) return false;
    return true;
  } catch {
    return false;
  }
}

export function verifyNetworkIdentity(
  expected: NetworkIdentityExpectation,
  identity: NetworkIdentity,
): { verified: boolean; reason?: 'chain-id' | 'genesis-hash' | 'server-unverified' } {
  if (expected.chainId === null || identity.chainId !== expected.chainId) {
    return { verified: false, reason: 'chain-id' };
  }

  if (expected.id === 'mainnet' && !isGenesisHash(expected.expectedGenesisHash)) {
    return { verified: false, reason: 'genesis-hash' };
  }

  if (
    expected.expectedGenesisHash &&
    (!isGenesisHash(identity.genesisHash) ||
      identity.genesisHash.toLowerCase() !== expected.expectedGenesisHash.toLowerCase())
  ) {
    return { verified: false, reason: 'genesis-hash' };
  }

  if (
    expected.id === 'mainnet' &&
    (!identity.verified ||
      !identity.expectedGenesisHash ||
      identity.expectedGenesisHash.toLowerCase() !== expected.expectedGenesisHash?.toLowerCase())
  ) {
    return { verified: false, reason: 'server-unverified' };
  }

  if (expected.id !== 'mainnet' && !identity.verified) {
    return { verified: false, reason: 'server-unverified' };
  }

  return { verified: true };
}
