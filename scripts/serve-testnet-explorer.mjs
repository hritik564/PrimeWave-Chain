import { createServer, request as httpRequest } from "node:http";
import { createReadStream, existsSync, statSync } from "node:fs";
import { extname, join, relative, resolve, sep } from "node:path";
import { spawn } from "node:child_process";

const repositoryRoot = resolve(import.meta.dirname, "..");
const publicDirectory = resolve(repositoryRoot, "artifacts/pwcscan/dist/public");
const indexerEntryPoint = resolve(repositoryRoot, "indexer/dist/main.js");

function required(name) {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`[testnet-explorer] ${name} is required`);
  }
  return value;
}

function positivePort(name, fallback) {
  const value = Number.parseInt(process.env[name] ?? fallback, 10);
  if (!Number.isInteger(value) || value < 1 || value > 65535) {
    throw new Error(`[testnet-explorer] ${name} must be a valid TCP port`);
  }
  return value;
}

if (process.env.NODE_ENV !== "production") {
  throw new Error(
    "[testnet-explorer] Refusing to start outside NODE_ENV=production",
  );
}

if (process.env.INDEXER_CHAIN_ID !== "77") {
  throw new Error(
    "[testnet-explorer] Refusing to start unless INDEXER_CHAIN_ID=77",
  );
}

if (!existsSync(indexerEntryPoint)) {
  throw new Error(
    `[testnet-explorer] Missing ${relative(repositoryRoot, indexerEntryPoint)}; run the production build first`,
  );
}

if (!existsSync(join(publicDirectory, "index.html"))) {
  throw new Error(
    `[testnet-explorer] Missing ${relative(repositoryRoot, join(publicDirectory, "index.html"))}; run the production build first`,
  );
}

const port = positivePort("PORT", "19951");
const indexerPort = positivePort("INDEXER_API_PORT", "4000");
const rpcUrl = required("INDEXER_RPC_URL");
const databaseUrl = process.env.INDEXER_DB_URL?.trim() ||
  process.env.DATABASE_URL?.trim();

if (!databaseUrl) {
  throw new Error(
    "[testnet-explorer] INDEXER_DB_URL or Replit DATABASE_URL is required",
  );
}

const indexerEnvironment = {
  ...process.env,
  INDEXER_RPC_URL: rpcUrl,
  INDEXER_CHAIN_ID: "77",
  INDEXER_API_PORT: String(indexerPort),
  INDEXER_DB_URL: databaseUrl,
};

const indexer = spawn(process.execPath, [indexerEntryPoint], {
  cwd: repositoryRoot,
  env: indexerEnvironment,
  stdio: "inherit",
});

let shuttingDown = false;

function stopIndexer(signal = "SIGTERM") {
  if (!indexer.killed) {
    indexer.kill(signal);
  }
}

const mimeTypes = {
  ".css": "text/css; charset=utf-8",
  ".gif": "image/gif",
  ".html": "text/html; charset=utf-8",
  ".ico": "image/x-icon",
  ".jpeg": "image/jpeg",
  ".jpg": "image/jpeg",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".png": "image/png",
  ".svg": "image/svg+xml",
  ".txt": "text/plain; charset=utf-8",
  ".webp": "image/webp",
  ".woff": "font/woff",
  ".woff2": "font/woff2",
};

function serveStatic(request, response, pathname) {
  let decodedPath;
  try {
    decodedPath = decodeURIComponent(pathname);
  } catch {
    response.writeHead(400, { "content-type": "text/plain; charset=utf-8" });
    response.end("Bad request");
    return;
  }

  const requestedPath = decodedPath === "/"
    ? "index.html"
    : decodedPath.replace(/^\/+/, "");
  const candidate = resolve(publicDirectory, requestedPath);
  const publicPrefix = `${publicDirectory}${sep}`;

  if (candidate !== publicDirectory && !candidate.startsWith(publicPrefix)) {
    response.writeHead(403, { "content-type": "text/plain; charset=utf-8" });
    response.end("Forbidden");
    return;
  }

  const filePath = existsSync(candidate) && statSync(candidate).isFile()
    ? candidate
    : join(publicDirectory, "index.html");

  response.writeHead(200, {
    "cache-control": filePath.endsWith("index.html")
      ? "no-cache"
      : "public, max-age=31536000, immutable",
    "content-type": mimeTypes[extname(filePath).toLowerCase()] ??
      "application/octet-stream",
  });

  if (request.method === "HEAD") {
    response.end();
    return;
  }

  createReadStream(filePath).on("error", () => {
    if (!response.headersSent) {
      response.writeHead(500, {
        "content-type": "text/plain; charset=utf-8",
      });
    }
    response.end("Unable to read asset");
  }).pipe(response);
}

function proxyIndexer(request, response, requestUrl) {
  const indexerPath = requestUrl.pathname.slice("/indexer-api".length) || "/";
  const targetPath = `${indexerPath}${requestUrl.search}`;
  const proxyRequest = httpRequest({
    hostname: "127.0.0.1",
    port: indexerPort,
    path: targetPath,
    method: request.method,
    headers: {
      ...request.headers,
      host: `127.0.0.1:${indexerPort}`,
    },
  }, (proxyResponse) => {
    response.writeHead(proxyResponse.statusCode ?? 502, proxyResponse.headers);
    proxyResponse.pipe(response);
  });

  proxyRequest.on("error", () => {
    if (!response.headersSent) {
      response.writeHead(502, {
        "content-type": "application/json; charset=utf-8",
      });
    }
    response.end(JSON.stringify({
      success: false,
      error: "Indexer API unavailable",
    }));
  });

  request.pipe(proxyRequest);
}

const server = createServer((request, response) => {
  const requestUrl = new URL(
    request.url ?? "/",
    `http://${request.headers.host ?? "localhost"}`,
  );

  if (
    requestUrl.pathname === "/indexer-api" ||
    requestUrl.pathname.startsWith("/indexer-api/")
  ) {
    proxyIndexer(request, response, requestUrl);
    return;
  }

  serveStatic(request, response, requestUrl.pathname);
});

server.listen(port, "0.0.0.0", () => {
  console.log(`[testnet-explorer] PWCScan listening on :${port}`);
  console.log(`[testnet-explorer] Indexer API private on 127.0.0.1:${indexerPort}`);
});

indexer.on("error", (error) => {
  console.error("[testnet-explorer] Indexer process error:", error);
  if (!shuttingDown) {
    server.close();
    process.exitCode = 1;
  }
});

indexer.on("exit", (code, signal) => {
  if (shuttingDown) return;
  console.error(
    `[testnet-explorer] Indexer exited unexpectedly (code=${code ?? "null"}, signal=${signal ?? "none"})`,
  );
  server.close();
  process.exitCode = 1;
});

function shutdown(signal) {
  if (shuttingDown) return;
  shuttingDown = true;
  console.log(`[testnet-explorer] Received ${signal}; stopping services`);
  stopIndexer("SIGTERM");
  server.close(() => process.exit(0));
  setTimeout(() => {
    stopIndexer("SIGKILL");
    process.exit(1);
  }, 10_000).unref();
}

process.on("SIGINT", () => shutdown("SIGINT"));
process.on("SIGTERM", () => shutdown("SIGTERM"));