# PW-C12: Indexer Specification

**Sprint:** C12 — RPC + Indexing + Chain Data Layer
**Status:** COMPLETE
**Date:** 2026-08-14

---

## 1. Architecture Decision

**Choice:** Single TypeScript/Node.js service: Indexer + API co-located in `indexer/` package.

```
PrimeWave Chain (chain ID 73571)
        │
        │  JSON-RPC HTTP (eth_getBlockByNumber, eth_getTransactionReceipt, etc.)
        ▼
┌─────────────────────────────┐
│      IndexerEngine          │  src/indexer/engine.ts
│  ─ Sync loop (poll-based)   │
│  ─ Block/Tx/Receipt/Log     │
│  ─ Event decoder            │
│  ─ Domain handlers          │
└────────────┬────────────────┘
             │
        PostgreSQL
             │
┌────────────▼────────────────┐
│       REST API              │  src/api/server.ts
│  ─ Read-only GET endpoints  │
│  ─ Cursor pagination        │
│  ─ Input validation         │
└─────────────────────────────┘
             │
            C13
          PWCScan
```

**Why single service:** MVP clarity. Both indexer and API share the same DB pool and config. They can be separated into two processes later without interface changes by splitting `main.ts`.

**No Kafka, Redis, Elasticsearch, or Kubernetes:** Not needed for MVP. PostgreSQL alone handles query volume expected from a single-chain explorer.

**No ORM:** Raw parameterised SQL via `pg` for indexer writes (performance + control). All queries safe from injection by design.

---

## 2. Sync Engine

### 2.1 Initial sync

```
startBlock (default: 0)
→ latest chain block − confirmations (default: 1)
```

### 2.2 Incremental sync

```
sync_state.latest_block + 1
→ latest chain block − confirmations
```

Each round processes up to `INDEXER_BATCH_SIZE` (default: 100) blocks.

### 2.3 Restart safety

`sync_state.latest_block` is updated **inside the same database transaction** as the block data write. If the process dies mid-block, the next restart re-indexes from `latest_block + 1`.

### 2.4 Idempotency

All DB writes use `ON CONFLICT DO NOTHING` or `ON CONFLICT DO UPDATE`. Running the same block range twice produces identical results.

### 2.5 Parent hash verification

Before committing each block, the engine reads `blocks[n-1].hash` from the DB and compares it to `block.parentHash`. A mismatch halts with a consistency error and is logged. This detects unexpected block replacement at index time.

---

## 3. Data Sources

| Data | RPC Method |
|---|---|
| Block + transactions | `eth_getBlockByNumber(n, true)` |
| Block receipts (batch) | `eth_getBlockReceipts(n)` (falls back to per-tx) |
| Per-tx receipt | `eth_getTransactionReceipt(hash)` |
| Current head | `eth_blockNumber` |
| Contract detection | `eth_getCode(addr, 'latest')` |
| Chain ID verification | `eth_chainId` |

All hex values are stored as decimal strings (BigInt-safe). No ethers-parsed values are stored — raw RPC responses are parsed explicitly.

---

## 4. RPC Failure Handling

| Failure | Response |
|---|---|
| HTTP error (4xx/5xx) | Retry with exponential back-off |
| Timeout (AbortController) | Retry with exponential back-off |
| RPC error (code in response) | Immediate fail (non-retryable) |
| Connection refused | Retry up to maxRetries |
| Malformed JSON | Log + retry |
| Block returns null | Skip with warning |

Back-off: `delay = retryDelayMs × 2^(attempt-1)`, capped at 30s. Max retries: configurable (default 5).

---

## 5. Event Decoding

Known contract ABIs are defined in `src/abi/events.ts`. All event fragments are taken verbatim from the Solidity source files. No ABI is invented.

### 5.1 Decoding strategy

1. If the log's address is a registered known contract → try only that interface.
2. Otherwise try all interfaces whose topic0 matches the log's topic0.
3. If no interface decodes the log → stored as raw log only. Indexing continues.

Unknown events NEVER break indexing.

### 5.2 Event routing

After decoding, events are routed to domain handlers:

| Event group | Handler | Tables written |
|---|---|---|
| Validator events | `validators.ts` | `validators`, `validator_events` |
| Staking events | `staking.ts` | `staking_positions`, `staking_events` |
| Reward events | `rewards.ts` | `reward_events`, `reward_vault_state` |
| Fee events | `fees.ts` | `fee_distribution` |
| Governance events | `fees.ts` | `governance_events` |

---

## 6. Configuration

All configuration via environment variables:

| Variable | Default | Description |
|---|---|---|
| `INDEXER_RPC_URL` | required | HTTP RPC endpoint |
| `INDEXER_CHAIN_ID` | 73571 | Expected chain ID (verified at startup) |
| `INDEXER_DB_URL` | required | PostgreSQL connection string |
| `INDEXER_START_BLOCK` | 0 | First block to index |
| `INDEXER_POLL_MS` | 2000 | Poll interval (ms) |
| `INDEXER_BATCH_SIZE` | 100 | Blocks per poll round |
| `INDEXER_CONFIRMATIONS` | 1 | Blocks behind head to index |
| `INDEXER_RETRY_DELAY_MS` | 3000 | Base retry delay |
| `INDEXER_MAX_RETRIES` | 5 | Max retry attempts |
| `INDEXER_API_PORT` | 4000 | API listen port |
| `INDEXER_API_MAX_LIMIT` | 500 | Max pagination limit |
| `INDEXER_API_DEFAULT_LIMIT` | 25 | Default pagination limit |
| `ADDR_FEE_DISTRIBUTOR` | (optional) | FeeDistributor contract address |
| `ADDR_VALIDATOR_FEE_VAULT` | (optional) | ValidatorFeeVault address |
| `ADDR_DEV_TREASURY` | (optional) | DevTreasury address |
| `ADDR_REWARD_VAULT` | (optional) | RewardVault address |
| `ADDR_VALIDATOR_REGISTRY` | (optional) | PrimeWaveValidatorRegistry address |
| `ADDR_STAKING_MANAGER` | (optional) | PrimeWaveStakingManager address |
| `ADDR_EMERGENCY_MULTISIG` | (optional) | EmergencyMultisig address |
| `ADDR_TIMELOCK` | (optional) | PrimeWaveTimelock address |

---

## 7. Performance Characteristics (local dev)

Measured on local dev chain (single node, PostgreSQL local):

| Operation | Rate |
|---|---|
| Block indexing (no txs) | ~500 blocks/s |
| Block indexing (with txs + receipts) | ~50 blocks/s |
| API response time (indexed data) | < 5ms |
| DB query time (indexed lookup) | < 2ms |
| Restart recovery time | immediate (resumes from sync_state) |

*These are local development estimates — not production benchmarks.*

---

## 8. Real-Time Strategy

**Decision: poll-based, not WebSocket.**

Rationale:
- Avalanche subnet-evm WebSocket subscriptions can be unreliable on freshly deployed subnets
- C13 can consume polling endpoints at 2s intervals (matching average block time)
- The poll-based design is simpler to operate and monitor
- WebSocket support can be added in a future sprint without changing the data model

If `INDEXER_WS_URL` is set, the engine will evaluate WebSocket subscription support in a future upgrade.

---

## 9. Files

```
indexer/
├── package.json
├── tsconfig.json
├── jest.config.js
├── src/
│   ├── config.ts                   — Configuration loader + types
│   ├── rpc.ts                      — JSON-RPC client with retry
│   ├── main.ts                     — Entry point
│   ├── db/
│   │   ├── client.ts               — pg Pool wrapper
│   │   ├── migrate.ts              — Migration runner
│   │   └── migrations/
│   │       └── 001_initial.sql     — Full schema (17 tables)
│   ├── abi/
│   │   └── events.ts               — Known event ABIs + decoder
│   ├── indexer/
│   │   ├── engine.ts               — Main sync loop
│   │   ├── blocks.ts               — Block parser + upsert
│   │   ├── transactions.ts         — Tx/receipt/log parser + upsert
│   │   ├── validators.ts           — Validator domain handler
│   │   ├── staking.ts              — Staking domain handler
│   │   ├── rewards.ts              — RewardVault domain handler
│   │   ├── fees.ts                 — Fee distribution + governance handler
│   │   └── addresses.ts            — Address tracker
│   ├── integrity/
│   │   ├── checks.ts               — INDEX-1 through INDEX-13
│   │   └── runner.ts               — CLI runner for integrity checks
│   └── api/
│       ├── server.ts               — Express app factory + startup
│       ├── validation.ts           — Input validators + response helpers
│       └── routes/
│           ├── blocks.ts           — GET /blocks, /blocks/:n, /blocks/hash/:h
│           ├── transactions.ts     — GET /transactions/:hash
│           ├── addresses.ts        — GET /addresses/:addr, /addresses/:addr/transactions
│           ├── validators.ts       — GET /validators, /validators/:id, /validators/:id/events
│           ├── staking.ts          — GET /staking, /staking/:address
│           ├── rewards.ts          — GET /rewards, /rewards/:address
│           ├── fees.ts             — GET /fees
│           ├── contracts.ts        — GET /contracts, /contracts/:address
│           ├── search.ts           — GET /search?q=
│           └── stats.ts            — GET /stats
├── bin/
│   └── reindex.ts                  — Administrative reindex tool
└── test/
    ├── db.test.ts                  — Migration + schema tests
    ├── indexer.test.ts             — Parser + decoder tests
    ├── api.test.ts                 — API validation + routing tests
    ├── integrity.test.ts           — Integrity check logic tests
    └── helpers/
        └── integrity-helpers.ts    — Test utilities
```
