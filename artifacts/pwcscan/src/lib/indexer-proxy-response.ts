export interface ProxyErrorResponse {
  headersSent: boolean;
  writeHead(statusCode: number, headers: Record<string, string>): unknown;
  end(body: string): unknown;
}

/** Send a stable public dependency error without reflecting proxy internals. */
export function sendIndexerUnavailable(response: ProxyErrorResponse): void {
  if (response.headersSent) return;
  response.writeHead(503, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
  });
  response.end(JSON.stringify({
    success: false,
    error: {
      code: 'INDEXER_UNAVAILABLE',
      message: 'Indexer service is unavailable or not ready.',
    },
  }));
}
