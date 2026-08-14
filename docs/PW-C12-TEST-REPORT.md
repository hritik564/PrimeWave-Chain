# PW-C12: Test Report

**Sprint:** C12 — RPC + Indexing + Chain Data Layer
**Date:** 2026-08-14
**Status:** COMPLETE — All tests passing

---

## Summary

| Category | Total | Passed | Failed |
|---|---|---|---|
| DB tests | 8 | 8 | 0 |
| Indexer/Parser tests | 22 | 22 | 0 |
| API tests | 21 | 21 | 0 |
| Integrity check tests | 6 | 6 | 0 |
| **Total** | **57** | **57** | **0** |

**Forge regression (C00–C11 contracts):** 792/792 ✓

---

## Test Suite: `test/db.test.ts`

| ID | Test | Result |
|---|---|---|
| DB-01 | migrations directory exists | ✓ PASS |
| DB-02 | at least one migration file exists | ✓ PASS |
| DB-03 | migration files are numbered and sorted ascending | ✓ PASS |
| DB-04 | migration 001 contains all required tables | ✓ PASS |
| DB-05 | migration 001 contains required indexes | ✓ PASS |
| DB-06 | migration uses ON CONFLICT DO NOTHING for version insert | ✓ PASS |
| DB-07 | migration uses IF NOT EXISTS for all tables | ✓ PASS |
| DB-08 | runMigrations applies unapplied migrations only | ✓ PASS |

**Coverage (migrate.ts):** 52.94% statements (limited by mock-only approach; integration coverage requires real PG)

---

## Test Suite: `test/indexer.test.ts`

### Hex Utilities

| ID | Test | Result |
|---|---|---|
| IDX-01 | hexToNumber converts correctly | ✓ PASS |
| IDX-02 | hexToBigInt handles large values (1 PW = 10^18 wei) | ✓ PASS |
| IDX-03 | hexToDecStr returns decimal string | ✓ PASS |

### Block Parser

| ID | Test | Result |
|---|---|---|
| IDX-04 | parseBlock extracts all fields | ✓ PASS |
| IDX-05 | parseBlock normalises hash to lowercase | ✓ PASS |
| IDX-06 | parseBlock handles missing optional fields (no baseFee, coinbase, etc.) | ✓ PASS |

### Transaction Parser

| ID | Test | Result |
|---|---|---|
| IDX-07 | parseTx extracts all fields | ✓ PASS |
| IDX-08 | parseTx handles null to (contract creation) | ✓ PASS |
| IDX-09 | parseTx sets input to null for empty calldata | ✓ PASS |
| IDX-10 | parseTx preserves non-empty input | ✓ PASS |

### Receipt Parser

| ID | Test | Result |
|---|---|---|
| IDX-11 | parseReceipt computes transaction fee | ✓ PASS |
| IDX-12 | parseReceipt maps status correctly | ✓ PASS |
| IDX-13 | parseReceipt handles missing effectiveGasPrice | ✓ PASS |

### Log Parser

| ID | Test | Result |
|---|---|---|
| IDX-14 | parseLog extracts all topic slots | ✓ PASS |
| IDX-15 | parseLog fills missing topics with null | ✓ PASS |
| IDX-16 | parseLog sets data to null for empty calldata | ✓ PASS |

### Event Decoder

| ID | Test | Result |
|---|---|---|
| IDX-17 | unknown topic returns null without throwing | ✓ PASS |
| IDX-18 | empty topics returns null | ✓ PASS |
| IDX-19 | FeeDistributed decodes correctly (amount, validatorShare, treasuryShare, burnShare) | ✓ PASS |
| IDX-20 | ValidatorRegistered (registry) decodes correctly | ✓ PASS |
| IDX-21 | bigint args are serialised to strings | ✓ PASS |

### Config

| ID | Test | Result |
|---|---|---|
| IDX-22 | makeTestConfig returns valid config (chainId=73571) | ✓ PASS |

---

## Test Suite: `test/api.test.ts`

### Input Validation

| ID | Test | Result |
|---|---|---|
| API-01 | validateAddress accepts valid 0x address | ✓ PASS |
| API-02 | validateAddress rejects invalid address | ✓ PASS |
| API-03 | validateHash accepts valid 32-byte hex | ✓ PASS |
| API-04 | validateHash rejects short hash | ✓ PASS |
| API-05 | validateBlockNumber accepts non-negative integer | ✓ PASS |
| API-06 | validateBlockNumber rejects negative and non-integer | ✓ PASS |
| API-07 | validatePagination defaults applied | ✓ PASS |
| API-08 | validatePagination rejects limit > max | ✓ PASS |
| API-09 | validatePagination rejects negative after | ✓ PASS |
| API-10 | validateValidatorId accepts 32-byte hex | ✓ PASS |

### Search Router

| ID | Test | Result |
|---|---|---|
| API-11 | /search without q returns 400 | ✓ PASS |
| API-12 | address query hits addresses table | ✓ PASS |
| API-13 | tx hash query hits transactions table first | ✓ PASS |
| API-14 | block number query hits blocks table | ✓ PASS |
| API-15 | not found returns 404 | ✓ PASS |
| API-16 | invalid format returns 400 | ✓ PASS |

### Blocks Router

| ID | Test | Result |
|---|---|---|
| API-17 | GET /blocks returns paginated list | ✓ PASS |
| API-18 | GET /blocks/:number returns 404 for unknown block | ✓ PASS |
| API-19 | GET /blocks/hash/:hash validates hash format | ✓ PASS |
| API-20 | limit > maxLimit returns 400 | ✓ PASS |

### Health

| ID | Test | Result |
|---|---|---|
| API-21 | GET /health returns 200 | ✓ PASS |

---

## Test Suite: `test/integrity.test.ts`

| ID | Test | Result |
|---|---|---|
| INT-01 | runAllChecks returns 13 results | ✓ PASS |
| INT-02 | all results have required fields (id, name, passed, details) | ✓ PASS |
| INT-03 | INDEX-11 fails when fee split does not sum to total | ✓ PASS |
| INT-04 | INDEX-12 fails when emitted > funded | ✓ PASS |
| INT-05 | INDEX-2 passes when no parent hash violations | ✓ PASS |
| INT-06 | checks handle DB error gracefully (returns ERROR rows, no throw) | ✓ PASS |

---

## Coverage Notes

The uncovered lines (engine.ts, most route handlers, DB client) require either:
- A running PostgreSQL instance (integration tests, C13 test environment)
- A live Avalanche subnet-evm node

These are intentionally out of scope for the C12 unit test run. The mock-based approach covers all parsing logic, validation, routing, and check logic.

Coverage targets for C12 unit tests:
- Hex utilities: 100%
- Block/Tx/Receipt/Log parsers: 100%
- Event decoder (tryDecodeLog): 87%
- Input validators: 95%
- Integrity check logic: 93%
- Migration schema: 100%
- Search router: 88%

---

## TypeScript Errors Fixed

One issue encountered during test run:
- `src/abi/events.ts:124`: `Fragment` → `unknown as { topicHash; name }` cast — ethers v6 `Fragment` base class does not expose `topicHash` in its type definition even though it exists at runtime on `EventFragment`. Fixed with `as unknown as` double cast.

---

## Forge Regression

No Solidity contracts were modified in C12. C00–C11 suite (792 tests) confirmed clean.
