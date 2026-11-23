import { createReadStream, existsSync, realpathSync, statSync } from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const MIME_TYPES = new Map([
  ['.css', 'text/css; charset=utf-8'],
  ['.gif', 'image/gif'],
  ['.html', 'text/html; charset=utf-8'],
  ['.ico', 'image/x-icon'],
  ['.jpeg', 'image/jpeg'],
  ['.jpg', 'image/jpeg'],
  ['.js', 'text/javascript; charset=utf-8'],
  ['.json', 'application/json; charset=utf-8'],
  ['.map', 'application/json; charset=utf-8'],
  ['.mjs', 'text/javascript; charset=utf-8'],
  ['.png', 'image/png'],
  ['.svg', 'image/svg+xml'],
  ['.webmanifest', 'application/manifest+json; charset=utf-8'],
  ['.woff', 'font/woff'],
  ['.woff2', 'font/woff2'],
]);

const INDEXER_UNAVAILABLE = JSON.stringify({
  success: false,
  error: {
    code: 'INDEXER_UNAVAILABLE',
    message: 'Indexer service is unavailable or not ready.',
  },
});

const NETWORK_ROUTE = String.raw`(?:devnet|testnet|mainnet)`;
const ROUTE_PARAM = String.raw`[^/.]+`;
const SPA_ROUTE_PATTERNS = [
  new RegExp(String.raw`^/${NETWORK_ROUTE}/?$`),
  new RegExp(String.raw`^/${NETWORK_ROUTE}/blocks(?:/${ROUTE_PARAM})?/?$`),
  new RegExp(String.raw`^/${NETWORK_ROUTE}/transactions/?$`),
  new RegExp(String.raw`^/${NETWORK_ROUTE}/tx/${ROUTE_PARAM}/?$`),
  new RegExp(String.raw`^/${NETWORK_ROUTE}/address/${ROUTE_PARAM}/?$`),
  new RegExp(String.raw`^/${NETWORK_ROUTE}/contract/${ROUTE_PARAM}/?$`),
  new RegExp(String.raw`^/${NETWORK_ROUTE}/contracts/?$`),
  new RegExp(String.raw`^/${NETWORK_ROUTE}/validators/?$`),
  new RegExp(String.raw`^/${NETWORK_ROUTE}/validator/${ROUTE_PARAM}/?$`),
  new RegExp(String.raw`^/${NETWORK_ROUTE}/(?:staking|rewards|fees|governance|stats|search)/?$`),
];

function isSpaRoute(pathname) {
  return SPA_ROUTE_PATTERNS.some((pattern) => pattern.test(pathname));
}

function sendText(response, status, contentType, body, extraHeaders = {}) {
  response.writeHead(status, {
    'Cache-Control': 'no-store',
    'Content-Length': Buffer.byteLength(body),
    'Content-Type': contentType,
    'X-Content-Type-Options': 'nosniff',
    'Referrer-Policy': 'strict-origin-when-cross-origin',
    ...extraHeaders,
  });
  if (response.req?.method === 'HEAD') response.end();
  else response.end(body);
}

function safeFilePath(root, pathname) {
  let decoded;
  try {
    decoded = decodeURIComponent(pathname);
  } catch {
    return null;
  }
  if (decoded.includes('\0') || decoded.includes('\\')) return null;

  const relative = decoded.replace(/^\/+/, '');
  const resolved = path.resolve(root, relative || 'index.html');
  if (resolved !== root && !resolved.startsWith(`${root}${path.sep}`)) return null;

  const segments = relative.split('/');
  if (segments.some((segment) => segment.startsWith('.'))) return null;
  return resolved;
}

function cacheControlFor(relativePath, isHtml) {
  if (isHtml) return 'no-store';
  if (/^assets\//.test(relativePath) && /-[a-z\d_-]{8,}\./i.test(relativePath)) {
    return 'public, max-age=31536000, immutable';
  }
  return 'public, max-age=300';
}

export function createStaticServer(distDirectory) {
  const root = path.resolve(distDirectory);
  const indexFile = path.join(root, 'index.html');
  if (!existsSync(indexFile) || !statSync(indexFile).isFile()) {
    throw new Error(`PWCScan build is missing: ${indexFile}`);
  }
  const realRoot = realpathSync(root);

  return http.createServer((request, response) => {
    const method = request.method ?? 'GET';
    if (method !== 'GET' && method !== 'HEAD') {
      sendText(response, 405, 'text/plain; charset=utf-8', 'Method Not Allowed', {
        Allow: 'GET, HEAD',
      });
      return;
    }

    let url;
    try {
      url = new URL(request.url ?? '/', 'http://localhost');
    } catch {
      sendText(response, 400, 'text/plain; charset=utf-8', 'Bad Request');
      return;
    }

    if (url.pathname === '/healthz') {
      sendText(response, 200, 'application/json; charset=utf-8', '{"status":"ok","service":"pwcscan-static"}');
      return;
    }

    if (url.pathname === '/indexer-api' || url.pathname.startsWith('/indexer-api/')) {
      sendText(response, 503, 'application/json; charset=utf-8', INDEXER_UNAVAILABLE);
      return;
    }

    const requestedFile = safeFilePath(root, url.pathname);
    if (!requestedFile) {
      sendText(response, 400, 'text/plain; charset=utf-8', 'Bad Request');
      return;
    }

    let filePath = requestedFile;
    let isHtml = false;
    try {
      const fileStat = statSync(filePath);
      if (!fileStat.isFile()) {
        if (isSpaRoute(url.pathname)) {
          filePath = indexFile;
          isHtml = true;
        } else {
          sendText(response, 404, 'text/plain; charset=utf-8', 'Not Found');
          return;
        }
      }
    } catch {
      if (isSpaRoute(url.pathname)) {
        filePath = indexFile;
        isHtml = true;
      } else {
        sendText(response, 404, 'text/plain; charset=utf-8', 'Not Found');
        return;
      }
    }

    try {
      const realFilePath = realpathSync(filePath);
      if (realFilePath !== realRoot && !realFilePath.startsWith(`${realRoot}${path.sep}`)) {
        sendText(response, 404, 'text/plain; charset=utf-8', 'Not Found');
        return;
      }
      filePath = realFilePath;
      const fileStat = statSync(filePath);
      const relativePath = path.relative(realRoot, filePath).split(path.sep).join('/');
      const contentType = MIME_TYPES.get(path.extname(filePath).toLowerCase()) ?? 'application/octet-stream';
      response.writeHead(200, {
        'Cache-Control': cacheControlFor(relativePath, isHtml || path.basename(filePath) === 'index.html'),
        'Content-Length': fileStat.size,
        'Content-Type': contentType,
        'Last-Modified': fileStat.mtime.toUTCString(),
        'X-Content-Type-Options': 'nosniff',
        'Referrer-Policy': 'strict-origin-when-cross-origin',
      });
      if (method === 'HEAD') {
        response.end();
        return;
      }
      createReadStream(filePath).pipe(response);
    } catch {
      sendText(response, 500, 'text/plain; charset=utf-8', 'Static file unavailable');
    }
  });
}

function parsePort(value) {
  if (!value || !/^\d+$/.test(value)) {
    throw new Error('PORT must be set to a valid TCP port.');
  }
  const port = Number(value);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error('PORT must be between 1 and 65535.');
  }
  return port;
}

const currentFile = fileURLToPath(import.meta.url);
if (process.argv[1] && path.resolve(process.argv[1]) === currentFile) {
  const port = parsePort(process.env.PORT);
  const distDirectory = path.resolve(path.dirname(currentFile), '../dist/public');
  const server = createStaticServer(distDirectory);

  server.listen(port, '0.0.0.0', () => {
    process.stdout.write(`PWCScan static server listening on 0.0.0.0:${port}\n`);
  });

  for (const signal of ['SIGINT', 'SIGTERM']) {
    process.on(signal, () => server.close(() => process.exit(0)));
  }
}
