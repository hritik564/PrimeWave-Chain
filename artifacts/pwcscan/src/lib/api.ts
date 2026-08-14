import { useQuery } from '@tanstack/react-query';

export class ApiError extends Error {
  constructor(public status: number, message: string) {
    super(message);
    this.name = 'ApiError';
  }
}

export function formatApiUrl(base: string, path: string): string {
  const normalizedBase = base.endsWith('/') ? base.slice(0, -1) : base;
  const normalizedPath = path.startsWith('/') ? path : `/${path}`;
  return `${normalizedBase}${normalizedPath}`;
}

const getApiBase = () => {
  return import.meta.env.VITE_INDEXER_API_URL ?? '';
};

export async function apiRequest<T>(path: string, params?: Record<string, string | number | boolean>): Promise<T> {
  const base = getApiBase();
  if (!base) {
    throw new ApiError(503, 'Indexer API URL is not configured. Please set VITE_INDEXER_API_URL.');
  }

  const url = new URL(formatApiUrl(base, path));
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
  return useQuery({
    queryKey: ['stats'],
    queryFn: () => apiRequest<ApiResponse<Stats>>('/stats').then(res => res.data),
    refetchInterval,
  });
}

export function useBlocks(params?: { limit?: number; cursor?: number }) {
  return useQuery({
    queryKey: ['blocks', params],
    queryFn: () => apiRequest<PaginatedApiResponse<Block>>('/blocks', params),
  });
}

export function useBlock(numberOrHash: string | number) {
  return useQuery({
    queryKey: ['block', numberOrHash],
    queryFn: () => {
      const path = typeof numberOrHash === 'string' && numberOrHash.startsWith('0x') 
        ? `/blocks/hash/${numberOrHash}` 
        : `/blocks/${numberOrHash}`;
      return apiRequest<ApiResponse<Block>>(path).then(res => res.data);
    },
    enabled: !!numberOrHash,
  });
}

export function useTransactions(params?: { limit?: number; cursor?: number }) {
  return useQuery({
    queryKey: ['transactions', params],
    queryFn: () => apiRequest<PaginatedApiResponse<Transaction>>('/transactions', params),
  });
}

export function useTransaction(hash: string) {
  return useQuery({
    queryKey: ['transaction', hash],
    queryFn: () => apiRequest<ApiResponse<Transaction>>(`/transactions/${hash}`).then(res => res.data),
    enabled: !!hash,
  });
}

export function useAddress(address: string) {
  return useQuery({
    queryKey: ['address', address],
    queryFn: () => apiRequest<ApiResponse<Address>>(`/addresses/${address}`).then(res => res.data),
    enabled: !!address,
  });
}

export function useAddressTransactions(address: string, params?: { limit?: number; cursor?: number }) {
  return useQuery({
    queryKey: ['addressTxs', address, params],
    queryFn: () => apiRequest<PaginatedApiResponse<Transaction>>(`/addresses/${address}/transactions`, params),
    enabled: !!address,
  });
}

export function useValidators(params?: { status?: number }) {
  return useQuery({
    queryKey: ['validators', params],
    queryFn: () => apiRequest<ApiResponse<Validator[]>>('/validators', params).then(res => res.data),
  });
}

export function useValidator(id: string) {
  return useQuery({
    queryKey: ['validator', id],
    queryFn: () => apiRequest<ApiResponse<Validator>>(`/validators/${id}`).then(res => res.data),
    enabled: !!id,
  });
}

export function useValidatorEvents(id: string, params?: { limit?: number; cursor?: number }) {
  return useQuery({
    queryKey: ['validatorEvents', id, params],
    queryFn: () => apiRequest<PaginatedApiResponse<ValidatorEvent>>(`/validators/${id}/events`, params),
    enabled: !!id,
  });
}

export function useStaking(params?: { limit?: number; cursor?: number }) {
  return useQuery({
    queryKey: ['staking', params],
    queryFn: () => apiRequest<PaginatedApiResponse<StakingEvent>>('/staking', params),
  });
}

export function useStakingByAddress(address: string) {
  return useQuery({
    queryKey: ['stakingAddress', address],
    queryFn: () => apiRequest<ApiResponse<StakingPosition[]>>(`/staking/${address}`).then(res => res.data),
    enabled: !!address,
  });
}

export function useRewards() {
  return useQuery({
    queryKey: ['rewards'],
    queryFn: () => apiRequest<ApiResponse<RewardsOverview>>('/rewards').then(res => res.data),
  });
}

export function useRewardsByAddress(address: string, params?: { limit?: number; cursor?: number }) {
  return useQuery({
    queryKey: ['rewardsAddress', address, params],
    queryFn: () => apiRequest<PaginatedApiResponse<RewardEvent>>(`/rewards/${address}`, params),
    enabled: !!address,
  });
}

export function useFees(params?: { limit?: number; cursor?: number }) {
  return useQuery({
    queryKey: ['fees', params],
    queryFn: () => apiRequest<ApiResponse<FeesOverview>>('/fees', params).then(res => res.data),
  });
}

export function useContracts(params?: { limit?: number; cursor?: number; known_only?: boolean }) {
  return useQuery({
    queryKey: ['contracts', params],
    queryFn: () => apiRequest<PaginatedApiResponse<Contract>>('/contracts', params),
  });
}

export function useSearch(q: string) {
  return useQuery({
    queryKey: ['search', q],
    queryFn: () => apiRequest<ApiResponse<SearchResult>>('/search', { q }).then(res => res.data),
    enabled: !!q && q.length > 2,
    retry: false,
  });
}
