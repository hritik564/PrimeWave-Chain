---
name: PrimeWave Chain PW-C13
description: PWCScan explorer (C13) — live data connection post-gate fix; known pitfalls and fixes
---

## C13 COMPLETE (Post-Gate Integration)

PWCScan is connected to the C12 indexer and showing live blockchain data.

### Startup sequence (each Replit session)
1. **PrimeWave Chain** workflow starts `bash scripts/start-chain.sh` — kills stale processes, starts avalanchego
2. **PrimeWave Indexer** workflow starts `bash scripts/start-indexer.sh` — waits for RPC, deploys contracts (if needed), runs migrations, starts indexer on port 4000
3. **artifacts/pwcscan: web** workflow — Vite dev server, proxy `/indexer-api/*` → `http://127.0.0.1:4000`

### Critical: Correct blockchain ID
- Blockchain ID deployed by Avalanche CLI: `2F3BHmNJWP4DNaBbMFQog3TvfcF6GRY7PX99r7Xzae4cRwAv6a`
- `local-data/network-ids.env` and `local-data/network-state.env` must reflect this
- The chain stores state in `~/.avalanche-cli/local/` — blockchain ID does NOT change on restart unless genesis changes

### Known pitfalls fixed in post-gate
1. **Unicode em dash in Solidity string literal** — `DevDeploy.s.sol` had `—` (em dash) which solc 0.8.30 rejects; use ASCII `-` only
2. **SQL migrations not copied by tsc** — `indexer/package.json` build must be `tsc && cp -r src/db/migrations dist/db/`
3. **Missing `GET /transactions` list endpoint** — original router only had `GET /transactions/:hash`; added list endpoint with cursor pagination
4. **Wrong column name in list query** — transactions table has `gas_limit` not `gas`; TX_COLS must not reference `t.gas`
5. **Stale avalanchego process** — if chain workflow fails to start, kill all `avalanchego` processes (`pkill -9 -x avalanchego`) and remove `local-data/node.pid`

**Why:** Browser accesses indexer via Vite proxy path `/indexer-api/*` → port 4000; direct `localhost:4000` is unreachable from browser in Replit (resolves to user's machine).

### Chain reset detection (post-gate fix)
- **Problem:** When the dev chain restarts, `sync_state.latest_block` holds a stale value from the old chain run. The old DB blocks have wrong hashes → `isSynced` reported `true` incorrectly.
- **Fix:** `IndexerEngine.detectAndHandleChainReset()` runs on every `start()`. Fetches the block at `lastIndexed` from RPC. If RPC returns error (`"cannot query unfinalized data"` = block does not exist on current chain) OR hash differs from DB → TRUNCATE all chain tables, reset sync_state, re-index from genesis.
- **AvalancheGo note:** `eth_getBlockByNumber` for a non-existent block returns JSON-RPC error -32000 `"cannot query unfinalized data"`, NOT null. RpcClient throws on this. The catch block must treat ANY thrown error as "block not found" (not skip-purge conservatively).
- **File:** `indexer/src/indexer/engine.ts` — `detectAndHandleChainReset()` private method, called before `registerKnownContracts()` in `start()`.

### Regression baseline
- Forge: 792/792
- Indexer Jest: 57/57
- Keeper Jest: 20/20
