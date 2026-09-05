export interface SearchResult {
  type: 'block' | 'transaction' | 'address' | 'validator' | 'not_found' | 'invalid_format';
  data: unknown;
}

export interface SearchApiResponse {
  success: boolean;
  type: SearchResult['type'];
  data: unknown;
}

const SEARCH_RESULT_TYPES = new Set<SearchResult['type']>([
  'block',
  'transaction',
  'address',
  'validator',
  'not_found',
  'invalid_format',
]);

export function isSearchQueryEnabled(query: string): boolean {
  return query.trim().length > 0;
}

export function parseSearchApiResponse(response: unknown): SearchApiResponse {
  if (
    !response ||
    typeof response !== 'object' ||
    !('success' in response) ||
    response.success !== true ||
    !('type' in response) ||
    typeof response.type !== 'string' ||
    !SEARCH_RESULT_TYPES.has(response.type as SearchResult['type']) ||
    !('data' in response)
  ) {
    throw new Error('Invalid search API response');
  }

  return {
    success: true,
    type: response.type as SearchResult['type'],
    data: response.data,
  };
}