import { useQuery } from '@tanstack/react-query';
import { useNetwork } from './network';
import type { NetworkDefinition } from './network-config';

export class ApiError extends Error {
  constructor(public status: number, message: string) {
    super(message);
    this.name = 'ApiError';
  }
}

export class NetworkUnavailableError extends Error {
  constructor(public network: NetworkDefinition) {
    super(`${network.label} configuration pending. No explorer data source is configured.`);
    this.name = 'NetworkUnavailableError';
  }
}

export class NetworkDataMismatchError extends Error {
  constructor(
    public network: NetworkDefinition,
    public receivedChainId: number,
  ) {
    super(
      `Network data mismatch for ${network.label}: expected Chain ID ${network.chainId}, received Chain ID ${receivedChainId}.`,
    );
    this.name = 'NetworkDataMismatchError';
  }
}

export function formatApiUrl(base: string, path: string): string {
  const normalizedBase = base.endsWith('/') ? base.slice(0, -1) : base;
  const normalizedPath = path.startsWith('/') ? path : `/${path}`;
  return `${normalizedBase}${normalizedPath}`;
}

export async function apiRequest<T>(
  network: NetworkDefinition,
  path: string,
  params?: Record<string, string | number | boolean>,
): Promise<T> {
  if (!network.indexerApiUrl || network.status !== 'configured') {
    throw new NetworkUnavailableError(network);
  }

  const base = network.indexerApiUrl;

  // Handle both absolute URLs (http://...) and relative paths (/indexer-api)
  const urlStr = formatApiUrl(base, path);
  const url = urlStr.startsWith('http')
    ? new URL(urlStr)
    : new URL(urlStr, window.location.origin);
  if (params) {
    Object.entries(params).forEach(([key, value]) => {
      if (value !== undefined && value !== null) {
        url.searchParams.append(key, value.toString());
      }
    });
  }

  try {
    const res = await fetch(url.toString());
    if (!res.ok) {
      throw new ApiError(res.status, `API request failed with status ${res.status}`);
    }
    const data = await res.json();
    if (!data.success) {
      throw new ApiError(res.status, data.error || 'Unknown API error');
    }
    return data;
  } catch (err) {
    if (err instanceof ApiError) throw err;
    throw new ApiError(500, err instanceof Error ? err.message : 'Network error');
  }
}

// ========================
// Types
// ========================

export interface ApiResponse<T> {
  success: boolean;
  data: T;
}

export interface PaginatedApiResponse<T> {
  success: boolean;
  data: T[];
  pagination: {
    limit: number;
    nextCursor: number | null;
  };
}

export interface Stats {
  network: { chainId: number; currentBlock: number; latestBlockTimestamp: number; isSynced: boolean; chainHead: number; latestIndexed: number };
  transactions: { total: string; inLatestBlock: number; tps_60s: number | null };
  gas: { gasUsedLatestBlock: string; gasLimitLatestBlock: string };
  validators: { activeCount: string };
  rewardVault: { totalFunded: string; totalEmitted: string; emissionRate: string };
  fees: { totalDistributed: string; totalToValidators: string };
}

export interface Block {
  number: number; hash: string; parent_hash: string; timestamp_unix: number;
  gas_limit: string; gas_used: string; base_fee_per_gas: string | null;
  transaction_count: number; coinbase: string | null; state_root: string | null; receipts_root: string | null;
}

export interface Log { log_index: number; contract_address: string; topic0: string; topic1: string | null; topic2: string | null; topic3: string | null; data: string | null; }
export interface DecodedEvent { event_name: string; event_signature: string; decoded_json: Record<string, unknown>; contract_address: string; tx_hash?: string; block_number?: number; }

export interface Transaction {
  hash: string; block_number: number; block_hash: string; transaction_index: number;
  from_address: string; to_address: string | null; value: string; gas_limit: string;
  gas_price: string | null; max_fee_per_gas: string | null; max_priority_fee: string | null;
  nonce: number; input: string | null; chain_id: number; tx_type: number;
  status: number; receipt_gas_used: string; effective_gas_price: string | null;
  transaction_fee: string | null; created_contract: string | null;
  logs: Log[]; decodedEvents: DecodedEvent[];
}

export interface Address {
  address: string; first_seen_block: number; last_seen_block: number;
  tx_count: number; sent_count: number; received_count: number;
  is_contract: boolean; creation_tx: string | null; is_known_protocol: boolean; protocol_name: string | null;
}

export interface Validator {
  validation_id: string; reward_recipient: string; acp99_weight: string;
  uptime_bips: number; status: number; is_active_in_vault: boolean;
  vault_base_weight: string; total_fees_claimed: string;
  first_seen_block: number; last_updated_block: number;
}

export interface ValidatorEvent {
  id: number; tx_hash: string; block_number: number; log_index: number;
  validation_id: string | null; event_name: string; contract_address: string; event_data: Record<string, unknown>;
}

export interface StakingEvent {
  id: number; tx_hash: string; block_number: number; event_name: string;
  validation_id: string | null; address: string; amount: string;
}

export interface StakingPosition { validation_id: string; staker: string; amount: string; stake_block: number; is_returned: boolean; return_block: number | null; }

export interface RewardsOverview { latestState: RewardVaultState | null; totalClaimed: string; emissionRate: string; }
export interface RewardVaultState { block_number: number; total_funded: string; total_emitted: string; emission_rate: string; }

export interface RewardEvent { id: number; tx_hash: string; block_number: number; event_name: string; recipient_id: string | null; amount: string | null; }

export interface FeesOverview {
  summary: { total_distributed: string; total_validator: string; total_treasury: string; total_burn: string; event_count: string } | null;
  events: FeeEvent[];
}
export interface FeeEvent { id: number; tx_hash: string; block_number: number; log_index: number; total_amount: string; validator_share: string; treasury_share: string; burn_share: string; }

export interface Contract {
  address: string; creation_tx: string | null; creation_block: number | null;
  is_verified: boolean; is_known_protocol: boolean; protocol_name: string | null; tx_count: number;
  recentEvents?: DecodedEvent[];
}

export interface SearchResult { type: 'block' | 'transaction' | 'address' | 'validator' | 'not_found' | 'invalid_format'; data: unknown; }

// ========================
// React Query Hooks
// ========================

export function useStats(refetchInterval?: number) {
  const { network, isConfigured } = useNetwork();
  return useQuery({
    queryKey: ['network', network.id, 'stats'],
    queryFn: async () => {
      const response = await apiRequest<ApiResponse<Stats>>(network, '/stats');
      const receivedChainId = response.data.network.chainId;
      if (network.chainId === null || receivedChainId !== network.chainId) {
        throw new NetworkDataMismatchError(network, receivedChainId);
      }
      return response.data;
    },
    enabled: isConfigured,
    refetchInterval: refetchInterval
      ? (query) =>
          query.state.error instanceof NetworkDataMismatchError ? false : refetchInterval
      : false,
  });
}

export function useBlocks(params?: { limit?: number; cursor?: number }) {
  const { network, isConfigured } = useNetwork();
  return useQuery({
    queryKey: ['network', network.id, 'blocks', params],
    queryFn: () => apiRequest<PaginatedApiResponse<Block>>(network, '/blocks', params),
    enabled: isConfigured,
  });
}

export function useBlock(numberOrHash: string | number) {
  const { network, isConfigured } = useNetwork();
  return useQuery({
    queryKey: ['network', network.id, 'block', numberOrHash],
    queryFn: () => {
      const path = typeof numberOrHash === 'string' && numberOrHash.startsWith('0x') 
        ? `/blocks/hash/${numberOrHash}` 
        : `/blocks/${numberOrHash}`;
      return apiRequest<ApiResponse<Block>>(network, path).then(res => res.data);
    },
    enabled: isConfigured && !!numberOrHash,
  });
}

export function useTransactions(params?: { limit?: number; cursor?: number }) {
  const { network, isConfigured } = useNetwork();
  return useQuery({
    queryKey: ['network', network.id, 'transactions', params],
    queryFn: () => apiRequest<PaginatedApiResponse<Transaction>>(network, '/transactions', params),
    enabled: isConfigured,
  });
}

export function useTransaction(hash: string) {
  const { network, isConfigured } = useNetwork();
  return useQuery({
    queryKey: ['network', network.id, 'transaction', hash],
    queryFn: () => apiRequest<ApiResponse<Transaction>>(network, `/transactions/${hash}`).then(res => res.data),
    enabled: isConfigured && !!hash,
  });
}

export function useAddress(address: string) {
  const { network, isConfigured } = useNetwork();
  return useQuery({
    queryKey: ['network', network.id, 'address', address],
    queryFn: () => apiRequest<ApiResponse<Address>>(network, `/addresses/${address}`).then(res => res.data),
    enabled: isConfigured && !!address,
  });
}

export function useAddressTransactions(address: string, params?: { limit?: number; cursor?: number }) {
  const { network, isConfigured } = useNetwork();
  return useQuery({
    queryKey: ['network', network.id, 'addressTxs', address, params],
    queryFn: () => apiRequest<PaginatedApiResponse<Transaction>>(network, `/addresses/${address}/transactions`, params),
    enabled: isConfigured && !!address,
  });
}

export function useValidators(params?: { status?: number }) {
  const { network, isConfigured } = useNetwork();
  return useQuery({
    queryKey: ['network', network.id, 'validators', params],
    queryFn: () => apiRequest<ApiResponse<Validator[]>>(network, '/validators', params).then(res => res.data),
    enabled: isConfigured,
  });
}

export function useValidator(id: string) {
  const { network, isConfigured } = useNetwork();
  return useQuery({
    queryKey: ['network', network.id, 'validator', id],
    queryFn: () => apiRequest<ApiResponse<Validator>>(network, `/validators/${id}`).then(res => res.data),
    enabled: isConfigured && !!id,
  });
}

export function useValidatorEvents(id: string, params?: { limit?: number; cursor?: number }) {
  const { network, isConfigured } = useNetwork();
  return useQuery({
    queryKey: ['network', network.id, 'validatorEvents', id, params],
    queryFn: () => apiRequest<PaginatedApiResponse<ValidatorEvent>>(network, `/validators/${id}/events`, params),
    enabled: isConfigured && !!id,
  });
}

export function useStaking(params?: { limit?: number; cursor?: number }) {
  const { network, isConfigured } = useNetwork();
  return useQuery({
    queryKey: ['network', network.id, 'staking', params],
    queryFn: () => apiRequest<PaginatedApiResponse<StakingEvent>>(network, '/staking', params),
    enabled: isConfigured,
  });
}

export function useStakingByAddress(address: string) {
  const { network, isConfigured } = useNetwork();
  return useQuery({
    queryKey: ['network', network.id, 'stakingAddress', address],
    queryFn: () => apiRequest<ApiResponse<StakingPosition[]>>(network, `/staking/${address}`).then(res => res.data),
    enabled: isConfigured && !!address,
  });
}

export function useRewards() {
  const { network, isConfigured } = useNetwork();
  return useQuery({
    queryKey: ['network', network.id, 'rewards'],
    queryFn: () => apiRequest<ApiResponse<RewardsOverview>>(network, '/rewards').then(res => res.data),
    enabled: isConfigured,
  });
}

export function useRewardsByAddress(address: string, params?: { limit?: number; cursor?: number }) {
  const { network, isConfigured } = useNetwork();
  return useQuery({
    queryKey: ['network', network.id, 'rewardsAddress', address, params],
    queryFn: () => apiRequest<PaginatedApiResponse<RewardEvent>>(network, `/rewards/${address}`, params),
    enabled: isConfigured && !!address,
  });
}

export function useFees(params?: { limit?: number; cursor?: number }) {
  const { network, isConfigured } = useNetwork();
  return useQuery({
    queryKey: ['network', network.id, 'fees', params],
    queryFn: () => apiRequest<ApiResponse<FeesOverview>>(network, '/fees', params).then(res => res.data),
    enabled: isConfigured,
  });
}

export function useContracts(params?: { limit?: number; cursor?: number; known_only?: boolean }) {
  const { network, isConfigured } = useNetwork();
  return useQuery({
    queryKey: ['network', network.id, 'contracts', params],
    queryFn: () => apiRequest<PaginatedApiResponse<Contract>>(network, '/contracts', params),
    enabled: isConfigured,
  });
}

export function useSearch(q: string) {
  const { network, isConfigured } = useNetwork();
  return useQuery({
    queryKey: ['network', network.id, 'search', q],
    queryFn: () => apiRequest<ApiResponse<SearchResult>>(network, '/search', { q }).then(res => res.data),
    enabled: isConfigured && !!q && q.length > 2,
    retry: false,
  });
}
