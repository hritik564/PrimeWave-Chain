# PW-C12: API Specification

**Sprint:** C12 — RPC + Indexing + Chain Data Layer
**Base URL:** `http://<host>:<INDEXER_API_PORT>` (default port 4000)
**Protocol:** HTTP/1.1 REST — read-only GET endpoints only
**Content-Type:** `application/json`

---

## 1. Response Envelope

All endpoints return:

```json
{ "success": true, "data": <payload> }
{ "success": false, "error": "<message>" }
```

With pagination:
```json
{ "success": true, "data": [...], "pagination": { "limit": 25, "nextCursor": 99 } }
```

`nextCursor` is null when no more pages exist.

---

## 2. Pagination

Cursor-based. Use `nextCursor` from the previous response as the `after` parameter.

| Parameter | Type | Default | Max | Description |
|---|---|---|---|---|
| `limit` | integer | 25 | 500 | Items per page |
| `after` | integer | — | — | Cursor (block number or row ID) |

**Example:**
```
GET /blocks?limit=10
GET /blocks?limit=10&after=90    ← next page using cursor from prev response
```

---

## 3. Error Codes

| HTTP Status | Meaning |
|---|---|
| 200 | Success |
| 400 | Invalid parameter (hash format, block number, limit range) |
| 404 | Resource not found |
| 500 | Internal server error |

---

## 4. Endpoints

### GET /health

Liveness check.

```json
{ "success": true, "data": { "status": "ok", "service": "primewave-indexer" } }
```

---

### GET /stats

Network statistics summary.

```json
{
  "success": true,
  "data": {
    "network": {
      "chainId": 73571,
      "currentBlock": 1000,
      "latestBlockTimestamp": 1700000000,
      "isSynced": true,
      "chainHead": 1000,
      "latestIndexed": 1000
    },
    "transactions": {
      "total": "5423",
      "inLatestBlock": 3,
      "tps_60s": 0.05
    },
    "gas": {
      "gasUsedLatestBlock": "63000",
      "gasLimitLatestBlock": "8000000"
    },
    "validators": { "activeCount": "15" },
    "rewardVault": {
      "totalFunded": "15000000000000000000000000",
      "totalEmitted": "250000000000000000000",
      "emissionRate": "95129375951"
    },
    "fees": {
      "totalDistributed": "1234567890",
      "totalToValidators": "864197523"
    }
  }
}
```

> Note: `tps_60s` is computed over the last 60 seconds of indexed block timestamps. Documented formula: `SUM(transaction_count for blocks in window) / 60`.

---

### GET /blocks

Paginated block list, descending by block number.

**Parameters:** `limit`, `after` (block number cursor)

**Response fields per block:**
```json
{
  "number": 100,
  "hash": "0x...",
  "parent_hash": "0x...",
  "timestamp_unix": 1700000000,
  "gas_limit": "8000000",
  "gas_used": "63000",
  "base_fee_per_gas": "1000000000",
  "transaction_count": 3,
  "coinbase": "0x...",
  "state_root": "0x...",
  "receipts_root": "0x..."
}
```

---

### GET /blocks/:number

Block by number. `number` must be a non-negative integer.

**404** if not indexed.

---

### GET /blocks/hash/:hash

Block by hash. `hash` must be a 0x-prefixed 32-byte hex string.

---

### GET /transactions/:hash

Transaction + receipt + logs + decoded events.

```json
{
  "hash": "0x...",
  "block_number": 100,
  "from_address": "0x...",
  "to_address": "0x...",
  "value": "1000000000000000000",
  "gas_limit": "21000",
  "tx_type": 0,
  "status": 1,
  "receipt_gas_used": "21000",
  "effective_gas_price": "1000000000",
  "transaction_fee": "21000000000000",
  "created_contract": null,
  "logs": [...],
  "decodedEvents": [...]
}
```

---

### GET /addresses/:address

Address summary. `address` must be a 0x-prefixed 20-byte hex string.

```json
{
  "address": "0x...",
  "first_seen_block": 1,
  "last_seen_block": 100,
  "tx_count": 42,
  "sent_count": 20,
  "received_count": 22,
  "is_contract": false,
  "creation_tx": null,
  "is_known_protocol": false,
  "protocol_name": null
}
```

---

### GET /addresses/:address/transactions

Paginated transaction history for an address (sender or recipient).

**Parameters:** `limit`, `after` (block number cursor)

---

### GET /addresses/:address/logs

Paginated log history where the address is the emitter.

**Parameters:** `limit`, `after` (log ID cursor)

---

### GET /validators

Paginated validator list.

**Parameters:** `limit`, `after` (first_seen_block cursor), `status` (integer filter)

**Response fields per validator:**
```json
{
  "validation_id": "0x0101...",
  "reward_recipient": "0x...",
  "acp99_weight": "1000",
  "uptime_bips": "9000",
  "status": 2,
  "is_active_in_vault": true,
  "vault_base_weight": "1000",
  "total_fees_claimed": "0",
  "first_seen_block": 5,
  "last_updated_block": 99
}
```

ValidatorStatus values: 0=Unknown, 1=PendingAdded, 2=Active, 3=PendingRemoved, 4=Completed, 5=Invalidated

---

### GET /validators/:id

Validator by validationID (0x-prefixed 32-byte hex).

---

### GET /validators/:id/events

Paginated validator event history.

**Parameters:** `limit`, `after` (row ID cursor)

---

### GET /staking

Recent staking events (paginated).

**Parameters:** `limit`, `after` (row ID cursor)

---

### GET /staking/:address

Staking positions and recent events for an address.

```json
{
  "positions": [...],
  "recentEvents": [...]
}
```

---

### GET /rewards

RewardVault summary.

```json
{
  "latestState": { "total_funded": "...", "total_emitted": "...", "emission_rate": "..." },
  "totalClaimed": "0",
  "emissionRate": "95129375951"
}
```

---

### GET /rewards/:address

Reward claims for an address (paginated).

---

### GET /fees

Fee distribution summary + recent FeeDistributed events.

```json
{
  "summary": {
    "total_distributed": "...",
    "total_validator": "...",
    "total_treasury": "...",
    "total_burn": "...",
    "event_count": "42"
  },
  "events": [...]
}
```

---

### GET /contracts

Paginated contract list.

**Parameters:** `limit`, `after` (creation_block cursor), `known=true` (filter to known protocol contracts only)

---

### GET /contracts/:address

Contract details + 20 most recent decoded events.

---

### GET /search?q=\<query\>

Global lookup. Resolves to one of:

| Input format | Result type |
|---|---|
| `0x` + 40 hex chars | address |
| `0x` + 64 hex chars | transaction / block / validator |
| Decimal integer | block |
| Other | 400 invalid_format |

```json
{ "success": true,  "type": "block",       "data": { ... } }
{ "success": false, "type": "address",      "error": "Not found" }
{ "success": false, "type": "invalid_format", "error": "Query does not match..." }
```

---

## 5. Security

- All endpoints are GET (no mutation)
- All path params and query params are validated before DB access
- All DB queries use parameterised SQL (`$1`, `$2`, ...)
- Pagination limits enforced: 1 ≤ limit ≤ maxLimit (default 500)
- No raw SQL user input ever reaches the query planner

---

## 6. Update Frequency

Data is updated every `INDEXER_POLL_MS` milliseconds (default: 2000ms). PWCScan should tolerate up to ~1 block of lag (typically < 2s).
