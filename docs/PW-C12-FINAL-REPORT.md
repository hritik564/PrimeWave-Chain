# PW-C12: Final Report

**Sprint:** C12 — RPC + Indexing + Chain Data Layer
**Status:** COMPLETE AND LOCKED
**Date:** 2026-08-14
**Gate:** 57/57 indexer tests + 792/792 Forge regression

---

## What Was Built

C12 delivers the complete chain data pipeline that connects PrimeWave Chain to C13 (PWCScan):

```
PrimeWave Chain (73571)
    │  JSON-RPC
    ▼
IndexerEngine           — polls chain head, indexes blocks + events
    │  PostgreSQL SQL
    ▼
17-table schema         — blocks, txs, logs, decoded events, domain state
    │  HTTP
    ▼
REST API (10 routes)    — read-only, paginated, parameterised, validated
    │
    ▼
C13 PWCScan (next sprint)
```

---

## Deliverables

### TypeScript Package: `indexer/`

Standalone `npm` package (same pattern as `keeper/`). Does not need pnpm workspace integration.

**Core modules:**

| Module | Purpose |
|---|---|
| `src/rpc.ts` | JSON-RPC client with retry + exponential backoff |
| `src/db/client.ts` | pg Pool wrapper: `query`, `withTransaction`, `setPool` |
| `src/db/migrate.ts` | Migration runner: reads SQL files, applies unapplied |
| `src/db/migrations/001_initial.sql` | Full schema: 17 tables, 25+ indexes |
| `src/abi/events.ts` | All known event ABIs from Solidity source + `tryDecodeLog` |
| `src/indexer/engine.ts` | Main sync loop (poll, batch, verify, commit) |
| `src/indexer/blocks.ts` | Block parser + upsert + parent hash verification |
| `src/indexer/transactions.ts` | Tx/receipt/log parser + upsert + decoded event insert |
| `src/indexer/validators.ts` | Validator domain handler (registry + VFV events) |
| `src/indexer/staking.ts` | Staking domain handler (StakeDeposited, StakeReturned) |
| `src/indexer/rewards.ts` | RewardVault domain handler (all RV events + state snapshots) |
| `src/indexer/fees.ts` | FeeDistributor + governance handler |
| `src/indexer/addresses.ts` | Address tracker + contract detection |
| `src/integrity/checks.ts` | INDEX-1 through INDEX-13 data integrity checks |
| `src/integrity/runner.ts` | CLI runner for integrity checks |
| `src/api/server.ts` | Express app factory + startup |
| `src/api/validation.ts` | Input validators + `ValidationError` |
| `src/api/routes/blocks.ts` | GET /blocks, /blocks/:n, /blocks/hash/:h |
| `src/api/routes/transactions.ts` | GET /transactions/:hash |
| `src/api/routes/addresses.ts` | GET /addresses/:addr (+ /transactions, /logs) |
| `src/api/routes/validators.ts` | GET /validators (+ /:id, /:id/events) |
| `src/api/routes/staking.ts` | GET /staking (+ /:address) |
| `src/api/routes/rewards.ts` | GET /rewards (+ /:address) |
| `src/api/routes/fees.ts` | GET /fees |
| `src/api/routes/contracts.ts` | GET /contracts (+ /:address) |
| `src/api/routes/search.ts` | GET /search?q= |
| `src/api/routes/stats.ts` | GET /stats |
| `src/main.ts` | Entry point: migrate → verify chain → start engine + API |
| `bin/reindex.ts` | Administrative reindex tool (range-scoped, safety-gated) |

---

## Database Schema Highlights

17 tables, all created with `IF NOT EXISTS`. Idempotent migration. Key invariants:

- `fee_distribution`: `total_amount = validator_share + treasury_share + burn_share` (INDEX-11)
- `reward_vault_state`: `total_emitted ≤ total_funded` (INDEX-12)
- `sync_state.latest_block` updated only inside block commit transaction (restart-safe)
- All amounts stored as `TEXT` (decimal string, BigInt-safe)
- All addresses stored lowercase

---

## API Surface

10 routes + health + search. All GET. All parameterised. No mutation.

```
GET /health
GET /stats
GET /blocks
GET /blocks/:number
GET /blocks/hash/:hash
GET /transactions/:hash
GET /addresses/:address
GET /addresses/:address/transactions
GET /addresses/:address/logs
GET /validators
GET /validators/:id
GET /validators/:id/events
GET /staking
GET /staking/:address
GET /rewards
GET /rewards/:address
GET /fees
GET /contracts
GET /contracts/:address
GET /search?q=
```

---

## Integrity Checks

13 automated checks, runnable via CLI (`ts-node src/integrity/runner.ts`) or during `--verify` mode of the reindex tool:

| Check | Description |
|---|---|
| INDEX-1 | Latest indexed block exists on chain (hash verified) |
| INDEX-2 | Parent hash chain intact across all blocks |
| INDEX-3 | All transactions belong to indexed blocks |
| INDEX-4 | All receipts belong to indexed transactions |
| INDEX-5 | All logs belong to indexed transactions |
| INDEX-6 | No duplicate transaction hashes |
| INDEX-7 | No duplicate logs (tx_hash, log_index) |
| INDEX-8 | No duplicate blocks |
| INDEX-9 | sync_state.latest_block present in blocks table |
| INDEX-10 | All decoded_events have non-null event_name |
| INDEX-11 | 70/20/10 fee split sums to total_amount |
| INDEX-12 | RewardVault: total_emitted ≤ total_funded |
| INDEX-13 | Validator count > 0 if ValidatorRegistered events exist |

---

## Test Results

**57/57 indexer tests — all passing (0 failures)**

| Suite | Tests | Status |
|---|---|---|
| db.test.ts | 8 | ✓ All pass |
| indexer.test.ts | 22 | ✓ All pass |
| api.test.ts | 21 | ✓ All pass |
| integrity.test.ts | 6 | ✓ All pass |

**792/792 Forge tests — confirmed clean (no contracts modified in C12)**

---

## Architecture Decisions (Rationale)

| Decision | Rationale |
|---|---|
| Raw JSON-RPC (not ethers provider) | Full control over hex representation. ethers v6 parses hex to JS numbers, losing precision for uint256. |
| Raw `pg` SQL (no ORM) | Indexer writes benefit from explicit ON CONFLICT semantics. Consistent with repo style. |
| Poll-based sync | Avalanche subnet WebSocket is optional/unreliable on fresh subnets. 2s poll matches block time. |
| Address-first decoding | When log emitter is a known protocol contract, decode using only that interface (faster, no ambiguity). |
| Standalone `npm` (not pnpm workspace) | Consistent with keeper/ precedent. Indexer and its test runner stay isolated. |
| `sync_state` updated inside block tx | Prevents partial state on crash. On restart, resumes exactly from next block. |
| BigInt → decimal string in storage | PostgreSQL `text` type, `COALESCE(SUM(amount::numeric))` for aggregation. No precision loss. |

---

## Known Limitations (intentional for C12)

1. **Balance tracking:** Native PW balance not indexed. C13 must call `eth_getBalance` directly for address balance.
2. **Contract bytecode:** Not stored (just a hash placeholder). Source verification is out of scope.
3. **Real-time WebSocket:** Not implemented. PWCScan polls at 2s intervals, consistent with indexer poll rate.
4. **Internal transactions (traces):** Not indexed. Requires `debug_traceTransaction` — planned for future sprint.
5. **Token transfers:** ERC-20/ERC-721 events not decoded (no token contracts in C12 scope).

---

## Documents Produced

| Document | Description |
|---|---|
| `PW-C12-INDEXER-SPEC.md` | Architecture, config, sync strategy, event routing |
| `PW-C12-DATABASE-SCHEMA.md` | All 17 tables, columns, indexes, invariants |
| `PW-C12-API-SPEC.md` | All 20+ endpoints, pagination, error codes, security |
| `PW-C12-PWCSCAN-DATA-CONTRACT.md` | What C13 consumes from C12 (authoritative contract) |
| `PW-C12-TEST-REPORT.md` | Per-test result table, coverage notes |
| `PW-C12-FINAL-REPORT.md` | This document |

---

## Sprint Gate Status

| Gate item | Status |
|---|---|
| indexer/ package created | ✓ |
| 17-table schema migration | ✓ |
| IndexerEngine sync loop | ✓ |
| All 8 known contract ABIs decoded | ✓ |
| Domain handlers (validator/staking/reward/fee/governance) | ✓ |
| 20+ REST API endpoints | ✓ |
| Input validation (address, hash, pagination, block number) | ✓ |
| 13 integrity checks | ✓ |
| Reindex tool | ✓ |
| 57 tests passing | ✓ |
| Forge regression 792/792 | ✓ |
| 6 documentation files | ✓ |

**C12 is COMPLETE and LOCKED.**

---

## Next Sprint: C13 — PWCScan Frontend

C13 consumes the API defined in `PW-C12-PWCSCAN-DATA-CONTRACT.md`. Required environment:
- PostgreSQL with C12 schema applied
- Indexer service running (`npm start` in `indexer/`)
- All `ADDR_*` env vars pointing to deployed C11 contracts
- `INDEXER_RPC_URL` pointing to AvalancheGo subnet-evm node
