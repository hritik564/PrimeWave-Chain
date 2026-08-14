---
name: PrimeWave Chain C12
description: C12 RPC + Indexing + Chain Data Layer — complete, locked. Indexer package, schema, API, integrity checks, 57 tests passing.
---

# C12 — RPC + Indexing + Chain Data Layer (COMPLETE)

**Gate:** 57/57 indexer Jest tests PASS. 792/792 Forge regression confirmed clean.

## Package Location

`indexer/` — standalone `npm` package (not in pnpm workspace; same pattern as `keeper/`).

## Key Architecture Decisions

- **Raw JSON-RPC** (not ethers provider): avoids hex→JS number precision loss for uint256.
- **Raw `pg` SQL** (no ORM): ON CONFLICT DO NOTHING for idempotency.
- **Sync_state update inside block commit tx**: restart-safe; resume on crash from next block.
- **Poll-based** (not WebSocket): 2s interval matches block time; subnet-evm WebSocket unreliable.
- **Address-first decoding**: known contract → that interface only; unknown → topic0 map across all.
- **BigInt as decimal TEXT** in PostgreSQL: `COALESCE(SUM(amount::numeric))` for aggregation.

## TypeScript Pitfall (Fixed)

`ethers.Fragment` base class does not expose `topicHash`/`name` in its type. EventFragment does.
Cast: `fragment as unknown as { topicHash: string; name: string }` (double-cast via `unknown`).

**Why:** `as { topicHash }` alone fails TS2352 because Fragment and the target type don't overlap enough.

## Schema

17 tables in `src/db/migrations/001_initial.sql`. Invariants:
- `fee_distribution`: total_amount = validator_share + treasury_share + burn_share (INDEX-11)
- `reward_vault_state`: total_emitted ≤ total_funded (INDEX-12)
- Sync_state row updated atomically inside each block's write transaction.

## API

20+ read-only GET endpoints on port `INDEXER_API_PORT` (default 4000).
Entry: `src/main.ts` → migrations → chain ID verify → IndexerEngine + API server.
Reindex tool: `bin/reindex.ts --from N --to M [--verify]` (requires `PRIMEWAVE_ALLOW_REINDEX=yes`).

## Integrity Checks

13 checks (INDEX-1 through INDEX-13) in `src/integrity/checks.ts`.
CLI runner: `ts-node src/integrity/runner.ts`.
Used in reindex `--verify` mode.

## Documents Produced (C12)

- `docs/PW-C12-INDEXER-SPEC.md`
- `docs/PW-C12-DATABASE-SCHEMA.md`
- `docs/PW-C12-API-SPEC.md`
- `docs/PW-C12-PWCSCAN-DATA-CONTRACT.md`
- `docs/PW-C12-TEST-REPORT.md`
- `docs/PW-C12-FINAL-REPORT.md`

## C13 Entry Point

C13 (PWCScan) consumes only the API defined in `PW-C12-PWCSCAN-DATA-CONTRACT.md`.
C13 must NOT query blockchain RPC directly for block/tx/log/event data.
C13 must use BigInt() for all amount fields (returned as decimal strings).
