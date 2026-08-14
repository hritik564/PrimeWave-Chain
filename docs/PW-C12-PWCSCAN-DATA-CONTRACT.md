# PW-C12: PWCScan Data Contract

**Sprint:** C12 — RPC + Indexing + Chain Data Layer
**Consumer:** C13 PWCScan frontend
**Status:** COMPLETE — do not modify without versioning the API

---

## Purpose

This document defines exactly what C13 can consume from the C12 indexer API.
C13 must NOT inspect blockchain internals directly to render normal explorer pages.
All chain data flows through the API defined here.

---

## Base URL

```
http://<INDEXER_HOST>:<INDEXER_API_PORT>
```

Default development URL: `http://localhost:4000`

---

## 1. Explorer Landing Page

**Endpoint:** `GET /stats`

Provides: current block, TPS, active validators, RewardVault balance, sync status.

**Derived fields:**
- `tps_60s` = `SUM(tx_count for last 60s of blocks) / 60`
- `isSynced` = `latestIndexed >= chainHead - 1`

**Update frequency:** Every poll cycle (~2s)

---

## 2. Block List

**Endpoint:** `GET /blocks?limit=25&after=<cursor>`

Returns newest blocks first. C13 renders a paginated block table.

**Required fields per block:**
- `number` — block height
- `hash` — for detail link
- `timestamp_unix` — for relative time display
- `transaction_count` — tx badge
- `gas_used` + `gas_limit` — for gas utilisation bar
- `base_fee_per_gas` — EIP-1559 base fee

---

## 3. Block Detail

**Endpoint:** `GET /blocks/<number>` or `GET /blocks/hash/<hash>`

Returns all block fields. C13 links to individual transactions via `hash` field.

---

## 4. Transaction List (for a block)

**Endpoint:** `GET /addresses/<address>/transactions?limit=25`

Note: For block-level tx list, C13 should query `/blocks/<n>` to get the block, then display `transaction_count`. For individual tx links, use `GET /transactions/<hash>`.

(A future endpoint `GET /blocks/<n>/transactions` may be added in a later sprint.)

---

## 5. Transaction Detail

**Endpoint:** `GET /transactions/<hash>`

**Required fields:**
- `hash`, `block_number`, `from_address`, `to_address`
- `value` — in wei (C13 converts to PW display: value / 10^18)
- `gas_limit`, `receipt_gas_used`, `effective_gas_price`, `transaction_fee`
- `status` — 0=fail, 1=success
- `created_contract` — non-null for contract creation
- `logs` — raw logs array
- `decodedEvents` — decoded PrimeWave events

**Authoritative source:** transaction_receipts + decoded_events

---

## 6. Address Page

**Endpoint:** `GET /addresses/<address>`

**Required fields:**
- `is_contract` — display contract badge
- `tx_count`, `sent_count`, `received_count`
- `first_seen_block`, `last_seen_block`
- `is_known_protocol`, `protocol_name` — for known contract badge

**Balance:** NOT provided by the indexer. C13 should call `eth_getBalance` on the RPC directly for current native PW balance, or the indexer can be extended in a future sprint.

---

## 7. Address Transactions

**Endpoint:** `GET /addresses/<address>/transactions?limit=25&after=<cursor>`

Paginated. Returns both sent and received transactions.

---

## 8. Validators Page

**Endpoint:** `GET /validators?limit=25&status=2` (status=2 for Active)

**Required fields:**
- `validation_id` — unique validator ID (bytes32)
- `status` — ValidatorStatus enum integer
- `reward_recipient` — fee/reward destination
- `acp99_weight` — P-Chain registered weight
- `is_active_in_vault` — whether accruing fees
- `total_fees_claimed` — cumulative fees claimed

---

## 9. Validator Detail

**Endpoint:** `GET /validators/<validationID>`

**Endpoint (events):** `GET /validators/<validationID>/events?limit=25`

---

## 10. Staking Page

**Endpoint:** `GET /staking?limit=25`

Shows recent staking activity across all validators.

**Endpoint (by address):** `GET /staking/<address>`

Shows positions and events for a specific staker.

---

## 11. RewardVault Page

**Endpoint:** `GET /rewards`

Shows: totalFunded, totalEmitted, emissionRate.

**Derived display values:**
- Remaining reserve = `totalFunded - totalEmitted` (C13 computes as BigInt strings)
- Annual emission = `emissionRate × 31536000` (rate is wei/second)

**Endpoint (by address):** `GET /rewards/<address>`

Shows: per-address total claimed + event history.

---

## 12. Fee Distribution Page

**Endpoint:** `GET /fees`

Shows: totalDistributed, totalToValidators, totalToTreasury, totalBurned.

**Split display:** 70%/20%/10% confirmed by on-chain events. Do NOT derive from gas fees alone.

---

## 13. Search

**Endpoint:** `GET /search?q=<query>`

C13 wires the search box to this endpoint. No client-side format detection needed — the server classifies and routes.

---

## 14. Contracts

**Endpoint:** `GET /contracts?known=true` — known protocol contracts
**Endpoint:** `GET /contracts/<address>` — contract detail + recent events

---

## 15. What C13 Must NOT Do

- Query blockchain RPC directly for block/tx/log data
- Implement its own event decoding
- Depend on contract addresses being hardcoded in the frontend
- Assume BigInt values are JavaScript `number` — all amounts are decimal strings

---

## 16. BigInt Handling Convention

All token amounts (value, fee, shares, rewards) are returned as **decimal strings**.

```
"1000000000000000000"   = 1 PW
"15000000000000000000000000"  = 15,000,000 PW
```

C13 should use `BigInt()` in JavaScript to parse, or a BigNumber library.

---

## 17. Error Handling

All API errors have `{ "success": false, "error": "<message>" }`.

C13 should:
- On 404 → show "Not found" page
- On 400 → show "Invalid input" message
- On 500 → show "Service unavailable, try again"
- On network error → retry with exponential backoff

---

## 18. Versioning

This contract is v1. Changes that break C13 require a new `/v2/` prefix or a C14 migration sprint.
