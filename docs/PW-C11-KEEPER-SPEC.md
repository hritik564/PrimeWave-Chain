# PW-C11: Validator Sync Keeper Specification

**Sprint:** C11 — Production Infrastructure + Validator Keeper + Genesis Finalization
**Status:** COMPLETE
**Date:** 2026-08-14

---

## 1. Overview

The **PrimeWave Validator Sync Keeper** is a TypeScript service that maintains the consistency of `PrimeWaveValidatorRegistry` with the authoritative `ValidatorManager` state.

### Why a Keeper is Needed

`PrimeWaveValidatorRegistry` tracks validator fee-accounting state in `ValidatorFeeVault`. When the P-Chain changes a validator's status (Active/Removed/Completed), the EVM registry must be updated. Since P-Chain events do not trigger EVM callbacks, an off-chain keeper polls and calls the permissionless `syncValidator()` function.

### Security Model

The keeper is **purely operational** — it cannot compromise system security:

| What the keeper CAN do | What the keeper CANNOT do |
|------------------------|--------------------------|
| Call `syncValidator(bytes32)` | Register new validators |
| Call `updateWeight(bytes32)` | Set emission rates |
| Call `syncAll()` | Withdraw funds |
| Read contract state | Change fee splits |
| Emit structured logs | Alter governance |

`syncValidator()` and `updateWeight()` are **permissionless** — any EOA can call them. The keeper account requires no privileged role and holds no governance tokens.

---

## 2. Liveness Targets

| Metric | Target | Alert Threshold |
|--------|--------|-----------------|
| Poll interval | 30 seconds | > 60 seconds |
| Max sync latency (Active transition) | < 2 minutes | > 5 minutes |
| Max sync latency (Removal) | < 2 minutes | > 5 minutes |
| Consecutive RPC failures before alert | 3 | ≥ 3 |
| Max retry attempts per validator | 5 | Exhausted |
| Keeper uptime target | 99.5% | < 99% (7-day rolling) |

---

## 3. Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      PrimewaveKeeper                             │
│                                                                   │
│  ┌──────────────┐   ┌───────────────┐   ┌────────────────────┐  │
│  │   Poll Loop  │──▶│  Sync Engine  │──▶│   StateStore       │  │
│  │  (30s cycle) │   │  (retry logic)│   │  (keeper-state.json│  │
│  └──────────────┘   └───────────────┘   └────────────────────┘  │
│         │                   │                                     │
│         ▼                   ▼                                     │
│  ┌──────────────┐   ┌───────────────┐                           │
│  │ Registry     │   │  ethers.js    │                           │
│  │ Contract     │   │  Wallet+Signer│                           │
│  └──────────────┘   └───────────────┘                           │
│                                                                   │
│  ┌──────────────┐   ┌───────────────┐                           │
│  │ /health HTTP │   │ /metrics Prom │                           │
│  │ (port 8080)  │   │ (port 8080)   │                           │
│  └──────────────┘   └───────────────┘                           │
└─────────────────────────────────────────────────────────────────┘
```

### 3.1 Poll Loop

1. Get current block number (liveness probe)
2. Call `managedCount()` → N
3. For each validator i: read `managedValidators(i)` and `validatorStatus(i)`
4. Compare to last-known status in StateStore
5. Enqueue changed validators for sync
6. Process sync queue with retry
7. Update `keeper-state.json`
8. Sleep `KEEPER_POLL_INTERVAL_MS`

### 3.2 Sync Engine

For each validator needing sync:
1. Call `syncValidator(validationID)` — submits tx
2. Wait for 1 confirmation (`tx.wait(1)`)
3. On success: update StateStore, reset failure counter
4. On failure: increment failure counter, retry with exponential backoff
5. After `MAX_RETRIES` exhausted: mark pending, log alert, continue
6. On restart: pending syncs are retried immediately from StateStore

### 3.3 Retry Policy

```
Attempt 1: immediate
Attempt 2: after 5s
Attempt 3: after 10s
Attempt 4: after 20s
Attempt 5: after 40s
→ Exhausted: marked pending in StateStore; retried on next restart
```

Configurable via `KEEPER_RETRY_DELAY_MS` (initial) and `KEEPER_RETRY_BACKOFF` (multiplier).

### 3.4 Idempotency

`syncValidator()` and `updateWeight()` are safe to call multiple times:
- If already synced: contract is a no-op (does not revert, consumes minimal gas)
- Keeper may call twice due to restart; this is harmless

---

## 4. State Persistence

`keeper-state.json` stores:

```json
{
  "schemaVersion": 1,
  "chainId": 73571,
  "registryAddress": "0x...",
  "lastPollAt": 1723634400000,
  "lastBlockProcessed": 12345,
  "validators": {
    "0xabc...": {
      "validationId":         "0xabc...",
      "lastKnownStatus":      2,
      "syncPending":          false,
      "consecutiveFailures":  0,
      "lastSuccessfulSyncAt": 1723634400000,
      "lastTxHash":           "0xdef..."
    }
  },
  "totalSyncsAttempted": 42,
  "totalSyncsSucceeded": 41,
  "totalSyncsFailed":    1
}
```

**Safety:** State is written atomically (write to `.tmp`, then rename) to prevent corruption on crash.

**Chain/registry mismatch protection:** On load, chain ID and registry address are verified against config. Mismatch → hard error (prevents applying state to wrong network).

---

## 5. Health Endpoint

`GET :8080/health`

```json
{
  "status": "healthy",          // "healthy" | "degraded" | "unhealthy"
  "lastPollBlock": 12345,
  "lastPollAt": 1723634400000,
  "consecutiveRpcFailures": 0,
  "pendingSyncs": 0,
  "uptime": 3600.5
}
```

HTTP status codes:
- `200` — healthy or degraded
- `503` — unhealthy (> `ALERT_THRESHOLD` consecutive RPC failures)

---

## 6. Prometheus Metrics

All metrics are exported at `GET :8080/metrics`.

| Metric | Type | Description |
|--------|------|-------------|
| `primewave_keeper_sync_attempts_total` | Counter | Total `syncValidator()` attempts |
| `primewave_keeper_sync_successes_total` | Counter | Successful syncs |
| `primewave_keeper_sync_failures_total` | Counter | Failed syncs |
| `primewave_keeper_pending_syncs` | Gauge | Validators pending sync |
| `primewave_keeper_managed_validators` | Gauge | Total managed validators |
| `primewave_keeper_last_poll_timestamp_seconds` | Gauge | Last poll Unix timestamp |
| Default Node.js metrics (GC, heap, etc.) | Various | Auto-collected by prom-client |

---

## 7. Configuration Reference

All configuration is via environment variables. No production values are hardcoded.

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `KEEPER_RPC_URL` | Yes | — | JSON-RPC endpoint |
| `KEEPER_CHAIN_ID` | Yes | — | Chain ID (73571 for primewavedev) |
| `KEEPER_REGISTRY_ADDRESS` | Yes | — | PrimeWaveValidatorRegistry address |
| `KEEPER_VALIDATOR_MANAGER_ADDRESS` | Yes | — | ValidatorManager address |
| `KEEPER_PRIVATE_KEY` | Yes | — | Keeper EOA private key (no admin role) |
| `KEEPER_POLL_INTERVAL_MS` | No | 30000 | Poll interval in ms |
| `KEEPER_CONFIRMATION_BLOCKS` | No | 1 | Blocks to wait for tx confirmation |
| `KEEPER_MAX_RETRIES` | No | 5 | Max sync retry attempts |
| `KEEPER_RETRY_DELAY_MS` | No | 5000 | Initial retry delay in ms |
| `KEEPER_RETRY_BACKOFF` | No | 2 | Backoff multiplier |
| `KEEPER_HEALTH_PORT` | No | 8080 | HTTP health/metrics port |
| `KEEPER_STATE_FILE` | No | ./keeper-state.json | State persistence file |
| `KEEPER_ALERT_THRESHOLD` | No | 3 | Consecutive failures before alert |
| `KEEPER_LOG_LEVEL` | No | info | Log level (debug/info/warn/error) |
| `PRIMEWAVE_ENV` | No | development | Set to "production" in prod |

---

## 8. Deployment

### 8.1 Setup

```bash
cd keeper/
pnpm install
pnpm build
```

### 8.2 Systemd Service

```ini
[Unit]
Description=PrimeWave Chain Validator Sync Keeper
After=network.target

[Service]
Type=simple
User=primewave
WorkingDirectory=/opt/primewave/keeper
EnvironmentFile=/etc/primewave/keeper.env
ExecStart=/usr/bin/node dist/keeper.js
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

### 8.3 Key Security

The keeper private key must:
- Belong to a **dedicated EOA** (not shared with any admin key)
- Hold only enough native PW for gas fees (top up as needed)
- Be stored in `/etc/primewave/keeper.env` with mode `0600`
- Never be the same as the protocol admin, EMS signer, or validator staker key

---

## 9. Test Coverage

`keeper/test/keeper.test.ts` covers 17 scenarios:
- KP-01 through KP-08: Normal lifecycle (detection, sync, idempotency, transitions)
- KP-09 through KP-14: Error handling (RPC failure, tx failure, nonce conflict, restart)
- KP-15 through KP-17: Batch scenarios (multiple validators, churn, simultaneous changes)
- StateStore tests: schema mismatch, chain ID mismatch, atomic write

Run: `cd keeper && pnpm test`

---

## 10. Operational Runbook

### Keeper Is Down

1. Check `systemctl status primewave-keeper`
2. Read logs: `journalctl -u primewave-keeper -n 100`
3. Check `keeper-state.json` for last poll time
4. Restart: `systemctl start primewave-keeper`
5. On restart, pending syncs are retried immediately
6. If still failing: check RPC endpoint, check keeper account gas balance

### Manual Sync (Keeper Offline)

```bash
# Anyone can call syncValidator — permissionless
forge send $REGISTRY_ADDRESS \
  "syncAll()" \
  --rpc-url $CHAIN_RPC_URL \
  --private-key $ANY_KEY
```

### Keeper Alerts Consecutively

If `consecutiveRpcFailures >= ALERT_THRESHOLD`:
1. Check RPC node health: `./scripts/health-check.sh`
2. If RPC is down: failover to backup RPC endpoint
3. Update `KEEPER_RPC_URL` and restart keeper
