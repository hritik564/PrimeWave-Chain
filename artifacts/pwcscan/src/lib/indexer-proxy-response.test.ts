import assert from 'node:assert/strict';
import test from 'node:test';
import { sendIndexerUnavailable } from './indexer-proxy-response';

test('missing indexer returns sanitized 503 JSON without internal proxy details', () => {
  let statusCode = 0;
  let headers: Record<string, string> = {};
  let body = '';
  sendIndexerUnavailable({
    headersSent: false,
    writeHead(status, responseHeaders) { statusCode = status; headers = responseHeaders; },
    end(value) { body = value; },
  });

  assert.equal(statusCode, 503);
  assert.equal(headers['Cache-Control'], 'no-store');
  assert.deepEqual(JSON.parse(body), {
    success: false,
    error: {
      code: 'INDEXER_UNAVAILABLE',
      message: 'Indexer service is unavailable or not ready.',
    },
  });
  assert.doesNotMatch(body, /ECONNREFUSED|127\.0\.0\.1|stack/i);
});

test('does not write a second response after headers were sent', () => {
  let writes = 0;
  sendIndexerUnavailable({
    headersSent: true,
    writeHead() { writes += 1; },
    end() { writes += 1; },
  });
  assert.equal(writes, 0);
});
