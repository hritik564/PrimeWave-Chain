# PW-C15 — FAILURE RECOVERY REPORT

**Sprint:** PW-C15 — Testnet Battle Test + Mainnet Readiness
**Status:** PROCEDURE READY — PENDING EXTERNAL EXECUTION
**Environment:** TESTNET ONLY — Chain ID 77

This document covers the deliberate failure injection and recovery tests required
by C15 §§21–22. Every scenario follows the pattern:

```
FAILURE → DETECTION → RECOVERY → DATA VERIFICATION
```

---

## 1. FAILURE TEST MATRIX

| # | Component | Failure Mode | Detection Method | Recovery Method | Data Check |
|---|---|---|---|---|---|
| F-01 | Validator | Process kill | Peer count drops; block production slows | systemctl start | Sync to tip; no dup fees |
| F-02 | RPC | Nginx stop | HTTP 502/504 | systemctl start nginx | eth_chainId re-confirms |
| F-03 | Keeper | Process kill | No syncValidator for 10m | systemctl start | Catches up from saved block |
| F-04 | Indexer | Process kill | Indexer lag alert fires | systemctl start | Resumes; no gap |
| F-05 | PostgreSQL | Service stop | Indexer log errors; PWCScan errors | systemctl start | Data intact; indexer resyncs |
| F-06 | Bootstrap node | Shutdown | Other validators still peer and sync | systemctl start | Blockchain continues |
| F-07 | Monitoring | Prometheus stop | No alert delivery | systemctl start | Metrics resume |
| F-08 | Network connectivity | iptables block (5m) | Peer count drops to 0 | iptables -F | Reconnects; resyncs |
| F-09 | ICM relayer | Process kill | Warp messages not delivered | systemctl start | Relayer catches up queued messages |
| F-10 | DNS endpoint | Disable DNS record | RPC URL fails to resolve | Re-add DNS record | Services resume via IP fallback |
| F-11 | Disk pressure | Fill disk to 95% | DiskPressure alert fires | Remove temp files | No data corruption |
| F-12 | Keeper tx | Invalid nonce sent | Keeper retries with correct nonce | Auto-retry | No duplicate sync |

---

## 2. DETAILED FAILURE PROCEDURES

### F-01: Validator Failure

```bash
# Pre-failure state
export BLOCK_PRE=$(cast block-number --rpc-url $TESTNET_RPC)
export VALIDATOR_WEIGHT_PRE=$(cast call $VALIDATOR_REGISTRY \
  "getValidatorWeight(bytes32)(uint64)" $NODE_ID_BYTES32 --rpc-url $TESTNET_RPC)

# Inject failure
ssh validator-05 "sudo systemctl stop primewave-node"

# Detection verification (should trigger within 2m)
# Check Prometheus alert: ValidatorFailure
# Check peer counts on remaining validators drop by 1

# Verify network continues
sleep 120
export BLOCK_POST=$(cast block-number --rpc-url $TESTNET_RPC)
echo "Blocks produced during outage: $((BLOCK_POST - BLOCK_PRE))"
# Must be > 0

# Recovery
ssh validator-05 "sudo systemctl start primewave-node"

# Wait for sync
while true; do
  SYNCING=$(curl -sf -X POST -H 'Content-Type: application/json' \
    --data '{"jsonrpc":"2.0","id":1,"method":"eth_syncing","params":[]}' \
    http://validator-05:9650/ext/bc/<BLOCKCHAIN_ID>/rpc | jq -r '.result')
  [ "$SYNCING" = "false" ] && echo "SYNCED" && break
  echo "Still syncing: $SYNCING"; sleep 30
done

# Data verification
# Check no duplicate fee entries in last 50 blocks
psql $DATABASE_URL -c "SELECT COUNT(*) FROM fee_events WHERE block > $BLOCK_PRE GROUP BY block HAVING COUNT(*) > 1;"
# Must return 0 rows
```

**Results:**

| Metric | Expected | Actual |
|---|---|---|
| Blocks during outage | > 0 (N-1 validators continue) | TBD |
| Detection time | < 2m | TBD |
| Sync time after restart | < 20m | TBD |
| Duplicate fee entries | 0 | TBD |
| Conservation violation | None | TBD |

---

### F-02: RPC Failure

```bash
# Inject
sudo systemctl stop nginx

# Detection: HTTP calls return connection refused / timeout
# Alert: RPCFailure should fire within 1m

# Recovery
sudo systemctl start nginx

# Verification
cast chain-id --rpc-url $TESTNET_RPC  # Must return 77
```

| Metric | Expected | Actual |
|---|---|---|
| Alert fires | < 1m | TBD |
| Recovery time | < 30s | TBD |
| Chain ID re-confirmed | 77 | TBD |

---

### F-03: Keeper Failure

```bash
# Record state before failure
export LAST_BLOCK=$(cat /var/lib/primewave-keeper/state.json | jq .lastProcessedBlock)

# Inject
sudo systemctl stop primewave-keeper

# Wait 10 minutes — keeper stall alert should fire

# Recovery
sudo systemctl start primewave-keeper

# Verification
journalctl -u primewave-keeper | grep "Resuming from block $LAST_BLOCK"
# Or similar — keeper must resume from persisted state, not from block 0
```

| Metric | Expected | Actual |
|---|---|---|
| KeeperStalled alert | Fires within 10m | TBD |
| Resumes from saved block | Yes (no re-scan from 0) | TBD |
| Missed syncs caught up | Yes | TBD |
| No duplicate syncs | Yes | TBD |

---

### F-04: Indexer Failure

```bash
export INDEXED_BLOCK_PRE=$(psql $DATABASE_URL -t -c "SELECT MAX(number) FROM blocks;")

# Inject
sudo systemctl stop primewave-indexer

# Wait for IndexerSyncLag alert (lag > 100 blocks)

# Recovery
sudo systemctl start primewave-indexer

# Verification
# Wait for catch-up
sleep 120
export INDEXED_BLOCK_POST=$(psql $DATABASE_URL -t -c "SELECT MAX(number) FROM blocks;")
echo "Indexed from $INDEXED_BLOCK_PRE to $INDEXED_BLOCK_POST"

# Check for gaps
psql $DATABASE_URL -c "
  SELECT a.number + 1 AS missing
  FROM blocks a
  LEFT JOIN blocks b ON a.number + 1 = b.number
  WHERE b.number IS NULL AND a.number < (SELECT MAX(number) FROM blocks)
  LIMIT 10;"
# Must return 0 rows (no gaps)
```

| Metric | Expected | Actual |
|---|---|---|
| Alert fires | Yes, IndexerSyncLag | TBD |
| Recovery: resumes from last indexed | Yes | TBD |
| No gaps in block sequence | Confirmed | TBD |
| No duplicate blocks | Confirmed | TBD |

---

### F-05: PostgreSQL Failure

```bash
# Inject
sudo systemctl stop postgresql

# Detection: Indexer and PWCScan log DB connection errors

# Recovery
sudo systemctl start postgresql
# Indexer and PWCScan reconnect automatically

# Verify data integrity
psql $DATABASE_URL -c "SELECT COUNT(*) FROM blocks;"
# Count must be consistent with pre-failure value (no data loss from DB restart)
```

---

### F-06: Bootstrap Node Failure

```bash
# Identify bootstrap node
export BOOTSTRAP_IP=$(grep bootstrap-ips /etc/avalanchego/config.json | awk -F'"' '{print $4}' | cut -d: -f1)

# Inject
ssh $BOOTSTRAP_IP "sudo systemctl stop primewave-node"

# Verify: Other validators retain peers and continue syncing
for v in V-02 V-03 V-04 V-05; do
  PEERS=$(curl -sf -X POST -H 'Content-Type: application/json' \
    --data '{"jsonrpc":"2.0","id":1,"method":"info.peers","params":[]}' \
    http://$v:9650/ext/info | jq '.result.numPeers')
  echo "$v peers: $PEERS"
done
# Each must show > 0 peers after bootstrap node failure

# Recovery
ssh $BOOTSTRAP_IP "sudo systemctl start primewave-node"
```

---

### F-08: Network Connectivity

```bash
# Inject: block all external traffic for 5 minutes
sudo iptables -I INPUT -j DROP
sudo iptables -I OUTPUT -j DROP
sleep 300

# Restore
sudo iptables -F

# Verify reconnection
# Node should re-discover peers and resync automatically
```

---

### F-11: Disk Pressure

```bash
# Create a large temp file to fill disk to 95%
AVAILABLE=$(df /var/lib/avalanchego | tail -1 | awk '{print $4}')
FILL_TO=$((AVAILABLE * 90 / 100))  # fill 90% of remaining
dd if=/dev/zero of=/tmp/fill-disk bs=1M count=$FILL_TO

# Verify DiskPressure alert fires in Prometheus

# Recovery
rm /tmp/fill-disk

# Verify: No database corruption, node still operational
```

---

## 3. DATABASE DISASTER RECOVERY (§16)

### 3.1 Procedure

```bash
# Step 1: Take backup
bash scripts/testnet/backup-testnet-db.sh
BACKUP_FILE=$(ls -t /backups/testnet/*.sql.gz | head -1)
echo "Backup: $BACKUP_FILE"

# Step 2: Record block height before destroy
BLOCK_COUNT=$(psql $DATABASE_URL -t -c "SELECT MAX(number) FROM blocks;")

# Step 3: Destroy database
sudo systemctl stop primewave-indexer primewave-pwcscan
psql $DATABASE_URL -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"

# Verify destruction
psql $DATABASE_URL -c "SELECT COUNT(*) FROM blocks;" 2>&1
# Must fail (relation does not exist)

# Step 4: Restore
bash scripts/testnet/restore-testnet-db.sh $BACKUP_FILE

# Step 5: Restart indexer
sudo systemctl start primewave-indexer primewave-pwcscan

# Step 6: Catch up
sleep 120
BLOCK_COUNT_AFTER=$(psql $DATABASE_URL -t -c "SELECT MAX(number) FROM blocks;")
echo "Pre-destroy: $BLOCK_COUNT, After restore+catchup: $BLOCK_COUNT_AFTER"
# After must be >= pre (caught up to tip)
```

### 3.2 RPO / RTO Results

| Metric | Target | Actual |
|---|---|---|
| Recovery Point Objective (data loss) | ≤ 1 hour | TBD |
| Recovery Time Objective | ≤ 30 minutes | TBD |
| Data integrity after restore | No corruption | TBD |
| Indexer catch-up time | < 10 minutes | TBD |
| PWCScan resumes correctly | Yes | TBD |

---

## 4. RECOVERY TIME SUMMARY

> Fill after execution

| Failure | Detection Time | Recovery Time | Data Loss | Status |
|---|---|---|---|---|
| F-01 Validator | TBD | TBD | None expected | 🔵 |
| F-02 RPC | TBD | TBD | None | 🔵 |
| F-03 Keeper | TBD | TBD | None | 🔵 |
| F-04 Indexer | TBD | TBD | None (resyncs) | 🔵 |
| F-05 PostgreSQL | TBD | TBD | None (restarts) | 🔵 |
| F-06 Bootstrap | TBD | TBD | None | 🔵 |
| F-07 Monitoring | TBD | TBD | Metric gap | 🔵 |
| F-08 Network | TBD | TBD | None | 🔵 |
| F-09 ICM Relayer | TBD | TBD | Messages queued | 🔵 |
| F-10 DNS | TBD | TBD | None | 🔵 |
| F-11 Disk pressure | TBD | TBD | None | 🔵 |
| F-12 Invalid keeper tx | TBD | TBD | None | 🔵 |
| DB Disaster Recovery | N/A | TBD | ≤ backup RPO | 🔵 |

**Acceptance criterion:** Every failure scenario results in detection + recovery with no permanent data loss and no conservation violation.
