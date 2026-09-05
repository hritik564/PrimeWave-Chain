---
name: Local PWCScan preview startup
description: Durable startup constraints for running the local Chain, C12 Indexer, and PWCScan preview together
---

Fresh workspace previews need the C12 Indexer's own declared dependencies installed in the `indexer` package because that directory is intentionally outside the root pnpm workspace. The local Chain startup must also parse Avalanche CLI's table-formatted `Blockchain ID` and `Subnet ID`; otherwise it persists a fallback blockchain ID and the Indexer waits on a dead RPC URL.

**Why:** The preview uses Vite's `/indexer-api` proxy to reach the local Indexer on port 4000, and the Indexer verifies the local Chain RPC before serving. Either missing package-local modules or a stale generated RPC URL prevents the explorer from loading even though the frontend workflow itself is healthy.

**How to apply:** When bringing up a fresh local preview, validate the local Chain state file points at the actually deployed blockchain ID, ensure the Indexer build output includes `dist/db/migrations`, set the web artifact's shared service environment `BASE_PATH` explicitly when Vite requires it, and verify `/indexer-api/stats` through the PWCScan server before diagnosing frontend code.