import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { after, before, test } from 'node:test';
import { createStaticServer } from './serve-static.mjs';

const temporaryRoot = mkdtempSync(path.join(os.tmpdir(), 'pwcscan-static-test-'));
const dist = path.join(temporaryRoot, 'dist');
mkdirSync(path.join(dist, 'assets'), { recursive: true });
writeFileSync(path.join(dist, 'index.html'), '<!doctype html><title>PWCScan test shell</title>');
writeFileSync(path.join(dist, 'assets', 'app-123456789abc.js'), 'window.pwcscan = true;');
writeFileSync(path.join(dist, 'favicon-32x32.png'), Buffer.from([0x89, 0x50, 0x4e, 0x47]));

const server = createStaticServer(dist);
let origin;

before(async () => {
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  origin = `http://127.0.0.1:${server.address().port}`;
});

after(async () => {
  await new Promise((resolve) => server.close(resolve));
  rmSync(temporaryRoot, { recursive: true, force: true });
});

async function request(route, options = {}) {
  const response = await fetch(`${origin}${route}`, options);
  return { response, body: await response.text() };
}

test('health check reports only static-server health', async () => {
  const { response, body } = await request('/healthz');
  assert.equal(response.status, 200);
  assert.deepEqual(JSON.parse(body), { status: 'ok', service: 'pwcscan-static' });
  assert.equal(response.headers.get('x-content-type-options'), 'nosniff');
  assert.equal(response.headers.get('referrer-policy'), 'strict-origin-when-cross-origin');
});

for (const route of [
  '/',
  '/mainnet',
  '/mainnet/blocks',
  '/mainnet/transactions',
  '/testnet/blocks',
]) {
  test(`frontend navigation route ${route} serves the SPA shell without Accept negotiation`, async () => {
    const { response, body } = await request(route);
    assert.equal(response.status, 200);
    assert.match(response.headers.get('content-type'), /^text\/html/);
    assert.match(body, /PWCScan test shell/);
    assert.equal(response.headers.get('cache-control'), 'no-store');
    assert.equal(response.headers.get('x-content-type-options'), 'nosniff');
    assert.equal(response.headers.get('referrer-policy'), 'strict-origin-when-cross-origin');
  });
}

test('missing indexer health route returns sanitized 503 without preventing the shell', async () => {
  const { response, body } = await request('/indexer-api/health');
  assert.equal(response.status, 503);
  assert.deepEqual(JSON.parse(body), {
    success: false,
    error: {
      code: 'INDEXER_UNAVAILABLE',
      message: 'Indexer service is unavailable or not ready.',
    },
  });
  const shell = await request('/', { headers: { accept: 'text/html' } });
  assert.equal(shell.response.status, 200);
});

test('static assets have correct MIME types and immutable cache only for hashed assets', async () => {
  const js = await request('/assets/app-123456789abc.js');
  assert.equal(js.response.status, 200);
  assert.match(js.response.headers.get('content-type'), /^text\/javascript/);
  assert.equal(js.response.headers.get('cache-control'), 'public, max-age=31536000, immutable');

  const png = await request('/favicon-32x32.png');
  assert.equal(png.response.status, 200);
  assert.match(png.response.headers.get('content-type'), /^image\/png/);
  assert.equal(png.response.headers.get('cache-control'), 'public, max-age=300');
});

test('unknown assets, traversal attempts and unsupported methods do not become SPA pages', async () => {
  const missing = await request('/missing.png', { headers: { accept: 'text/html' } });
  assert.equal(missing.response.status, 404);

  const missingExtensionlessAsset = await request('/images/missing-logo', {
    headers: { accept: 'text/html' },
  });
  assert.equal(missingExtensionlessAsset.response.status, 404);

  const unknownNetworkRoute = await request('/mainnet/not-a-route', {
    headers: { accept: 'text/html' },
  });
  assert.equal(unknownNetworkRoute.response.status, 404);

  const traversal = await request('/%2e%2e/package.json', { headers: { accept: 'text/html' } });
  assert.equal(traversal.response.status, 404);

  const post = await request('/', { method: 'POST' });
  assert.equal(post.response.status, 405);
  assert.equal(post.response.headers.get('allow'), 'GET, HEAD');
});
