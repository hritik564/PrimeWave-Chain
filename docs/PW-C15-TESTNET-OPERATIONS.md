# PW-C15 — TESTNET OPERATIONS

**Sprint:** PW-C15 — Testnet Battle Test + Mainnet Readiness
**Status:** OPERATIONAL RUNBOOK — PENDING EXTERNAL EXECUTION
**Environment:** TESTNET ONLY — Chain ID 77

This document is the day-to-day operational reference for PrimeWave Testnet.
It covers startup/shutdown, health monitoring, routine maintenance, and escalation.

---

## 1. SERVICE TOPOLOGY

```
┌─────────────────────────────────────────────────────┐
│                 Cloud Infrastructure                │
│                                                     │
│  ┌───────────────┐   ┌───────────────┐              │
│  │ Validator Node │   │  Validator N  │  ...15 nodes │
│  │ (AvalancheGo) │   │ (AvalancheGo) │              │
│  └───────┬───────┘   └───────────────┘              │
│          │ RPC                                      │
│  ┌───────▼───────┐                                  │
│  │  Nginx + TLS  │  rpc.testnet.primewave.xyz       │
│  └───────┬───────┘                                  │
│          │                                          │
│  ┌───────▼───────┐   ┌───────────────┐              │
│  │    Indexer    ├───►  PostgreSQL   │              │
│  └───────┬───────┘   └───────────────┘              │
│          │                                          │
│  ┌───────▼───────┐                                  │
│  │    PWCScan    │  explorer.testnet.primewave.xyz  │
│  └───────────────┘                                  │
│                                                     │
│  ┌───────────────┐   ┌───────────────┐              │
│  │    Keeper     │   │  Prometheus   │              │
│  └───────────────┘   │  + Grafana    │              │
│                       └───────────────┘              │
└─────────────────────────────────────────────────────┘
         │
         │ Warp / ICM
         ▼
    Fuji P-Chain
```

---

## 2. ENVIRONMENT VARIABLES

All services use the env templates from `deploy/testnet/env/`. Copy and fill:

```bash
cp deploy/testnet/env/testnet-indexer.env.template /etc/testnet/indexer.env
cp deploy/testnet/env/testnet-keeper.env.template /etc/testnet/keeper.env
cp deploy/testnet/env/testnet-pwcscan.env.template /etc/testnet/pwcscan.env
```

Critical variables to fill:

| Variable | Service | Value |
|---|---|---|
| `INDEXER_RPC_URL` | Indexer | `https://rpc.testnet.primewave.xyz` |
| `INDEXER_CHAIN_ID` | Indexer | `77` |
| `KEEPER_RPC_URL` | Keeper | `https://rpc.testnet.primewave.xyz` |
| `KEEPER_CHAIN_ID` | Keeper | `77` |
| `KEEPER_PRIVATE_KEY` | Keeper | Testnet keeper key (not mainnet) |
| `VITE_RPC_URL` | PWCScan | `https://rpc.testnet.primewave.xyz` |
| `VITE_CHAIN_ID` | PWCScan | `77` |
| `VITE_NETWORK_LABEL` | PWCScan | `Testnet` |
| `DATABASE_URL` | Indexer/PWCScan | PostgreSQL connection string |

---

## 3. SERVICE STARTUP SEQUENCE

Start services in this order to avoid dependency failures:

```bash
# 1. AvalancheGo (bootstrap node first, then validators)
sudo systemctl start primewave-node
sleep 30  # wait for sync

# 2. PostgreSQL (must be running before indexer)
sudo systemctl start postgresql

# 3. Indexer
sudo systemctl start primewave-indexer

# 4. Keeper (needs RPC + registry address)
sudo systemctl start primewave-keeper

# 5. PWCScan (needs indexer database)
sudo systemctl start primewave-pwcscan

# 6. Monitoring
sudo systemctl start prometheus
sudo systemctl start grafana-server

# 7. ICM Relayer
# (configured per Teleporter relayer docs)
```

---

## 4. HEALTH CHECK PROCEDURE

Run after every deployment or restart:

```bash
bash scripts/testnet/testnet-health-check.sh
```

Expected output:

```
HC-01: eth_chainId ... PASS (0x4d)
HC-02: eth_blockNumber ... PASS (increasing)
HC-03: net_version ... PASS (77)
HC-04: eth_gasPrice ... PASS
HC-05: Indexer sync ... PASS (lag < 30s)
HC-06: Keeper alive ... PASS (last heartbeat < 2m)
HC-07: PWCScan loads ... PASS
HC-08: Validator count ... PASS (N validators)
```

**STOP:** Do not open the testnet to public users if any HC check fails.

---

## 5. VALIDATOR NODE OPERATIONS

### 5.1 Starting a Validator

```bash
# Using systemd unit from C14 deploy package
sudo systemctl start primewave-node

# Verify it joined the subnet
curl -s -X POST --header 'content-type:application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"platform.getCurrentValidators","params":{"subnetID":"<SUBNET_ID>"}}' \
  https://api.avax-test.network/ext/bc/P
```

### 5.2 Stopping a Validator (graceful)

```bash
sudo systemctl stop primewave-node
# Verify peer count drops on remaining nodes
```

### 5.3 Restart Recovery

```bash
sudo systemctl restart primewave-node
# Check sync status
curl -s -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_syncing","params":[]}' \
  http://localhost:9650/ext/bc/<BLOCKCHAIN_ID>/rpc
# Should return false when fully synced
```

### 5.4 Validator State Monitor

```bash
# Check validator is eligible and has non-zero weight
cast call $VALIDATOR_REGISTRY "getValidator(bytes32)" $NODE_ID \
  --rpc-url $TESTNET_RPC
```

---

## 6. INDEXER OPERATIONS

### 6.1 Fresh Sync

```bash
# Start indexer with empty database — it will sync from block 0
sudo systemctl start primewave-indexer
# Watch sync progress
journalctl -u primewave-indexer -f | grep "block\|sync\|error"
```

### 6.2 Continuous Sync

Indexer polls RPC at 3-second intervals. Verify:

```bash
# Check indexer lag
curl -s http://localhost:3001/health | jq .
# Expected: {"status":"ok","lag":{"blocks":0,"seconds":<30}}
```

### 6.3 Reindex from Block 0

```bash
sudo systemctl stop primewave-indexer
psql $DATABASE_URL -c "TRUNCATE blocks, transactions, logs, validator_events, fee_events, reward_events CASCADE;"
sudo systemctl start primewave-indexer
```

### 6.4 Integrity Checks

```bash
# Run C12 integrity checks
cd indexer && npx jest --testPathPattern="integrity" --no-coverage
```

---

## 7. KEEPER OPERATIONS

### 7.1 Normal Operation

```bash
# Monitor keeper sync calls
journalctl -u primewave-keeper -f | grep "syncValidator\|weight\|retry\|error"
```

### 7.2 Keeper Restart

```bash
sudo systemctl restart primewave-keeper
# Verify it resumes from persisted state
cat /var/lib/primewave-keeper/state.json | jq .lastProcessedBlock
```

### 7.3 Keeper Authority Constraint

The keeper is a bridge — NOT a validator authority:
- ValidatorManager remains the authoritative source of validator truth
- Keeper reads ValidatorManager state, bridges to PrimeWaveValidatorRegistry
- If keeper is stopped: no registry updates; fees still collected by FeeDistributor
- On keeper restart: it catches up from last processed block

---

## 8. DATABASE OPERATIONS

### 8.1 Backup

```bash
bash scripts/testnet/backup-testnet-db.sh
# Backup stored at /backups/testnet/primewave-$(date +%Y%m%d%H%M%S).sql.gz
```

### 8.2 Restore

```bash
bash scripts/testnet/restore-testnet-db.sh /backups/testnet/primewave-20260815-XXXXXX.sql.gz
sudo systemctl restart primewave-indexer
# Verify indexer catches up
```

### 8.3 RPO / RTO Targets

| Metric | Target | Actual (to be measured) |
|---|---|---|
| RPO (data loss window) | ≤ 1 hour | TBD |
| RTO (recovery time) | ≤ 30 minutes | TBD |
| Backup schedule | Every 6 hours | Configure via cron |
| Retention | 7 days | TBD |

---

## 9. PWCScan OPERATIONS

### 9.1 Verify Testnet Label

PWCScan MUST display the orange "🧪 Testnet" badge. Verify:

```bash
curl -s https://explorer.testnet.primewave.xyz | grep "Testnet"
# Must return match
```

### 9.2 Chain ID Displayed

PWCScan stats page must show Chain ID: 77. Verify in browser header and stats.

### 9.3 No Mocked Data

All data in PWCScan derives from:
1. Real Ethereum RPC calls (blocks, transactions, addresses, contracts)
2. Real Indexer database (validators, staking, rewards, fees)

No manually inserted rows. Verify with:

```bash
psql $DATABASE_URL -c "SELECT COUNT(*) FROM blocks;"
# Block count must match eth_blockNumber
```

---

## 10. MONITORING

### 10.1 Alert Conditions

| Alert | Condition | Severity |
|---|---|---|
| NodeDown | Node unreachable for > 2m | Critical |
| KeeperStalled | No syncValidator call in > 10m | High |
| IndexerSyncLag | Block lag > 100 | High |
| DiskPressure | Disk > 80% | Warning |
| RPCFailure | RPC error rate > 5% | High |
| ValidatorFailure | Active validators < threshold | Critical |

### 10.2 Controlled Alert Test

```bash
# Stop indexer, verify alert fires within 5 minutes
sudo systemctl stop primewave-indexer
# Wait for alert
# Check Prometheus alerting, Grafana dashboard
# Restart indexer
sudo systemctl start primewave-indexer
# Verify alert clears
```

---

## 11. ESCALATION PROCEDURE

| Situation | Action |
|---|---|
| Chain stops producing blocks | Emergency halt; investigate validator consensus |
| Chain divergence detected | STOP condition; do not accept transactions |
| Conservation violation detected | Emergency pause via multisig; investigate |
| Private key suspected compromised | Immediate rotation; pause if needed |
| Critical/High security finding | Emergency pause; report per security policy |

---

## 12. SHUTDOWN PROCEDURE

For planned maintenance:

```bash
# Announce maintenance window to users
# Stop services in reverse order
sudo systemctl stop primewave-pwcscan
sudo systemctl stop primewave-keeper
sudo systemctl stop primewave-indexer
# Take DB backup before stopping
bash scripts/testnet/backup-testnet-db.sh
sudo systemctl stop postgresql
# Stop validators last
sudo systemctl stop primewave-node
```
