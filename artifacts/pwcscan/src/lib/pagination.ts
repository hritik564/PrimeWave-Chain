export type PageCursor = number | string;

/** Translate the explorer's page state into the indexer's documented query names. */
export function pageQuery(params?: { limit?: number; cursor?: PageCursor }) {
  return { limit: params?.limit, after: params?.cursor };
}
