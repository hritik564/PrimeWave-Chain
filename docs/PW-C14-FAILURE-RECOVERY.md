# PW-C14: Failure and Recovery Procedures
**Sprint:** PW-C14
**Environment:** TESTNET ONLY
**Reference:** Section 29, 30 of PW-C14 spec

---

## Overview

C14 deliberately exercises failure scenarios to verify recovery procedures. Each scenario follows the pattern:

```
FAILURE → DETECTION → RECOVERY → STATE VERIFICATION
```

---

## 1. Validator Node Restart

**Test:** Stop one validator, verify network health, restart, verify recovery.

```bash
# FAILURE: Stop validator node
systemctl stop primewave-testnet-node

# DETECTION: Check network health (remaining 4 nodes should keep consensus)
bash scripts/testnet/testnet-health-check.sh
# Expected: HC-01 to HC-05 pass (RPC node still serves chain)

# VERIFY: Block height still advancing
cast block-number --rpc-url $TESTNET_RPC_URL
sleep 10
cast block-number --rpc-url $TESTNET_RPC_URL
# Expected: block number increased

# RECOVERY: Restart node
systemctl start primewave-testnet-node
sleep 60

# VERIFY: Node synced to chain head
journalctl -fu primewave-testnet-node | grep "bootstrapped\|synced"
cast call http://127.0.0.1:9650/ext/bc/$BLOCKCHAIN_ID/rpc \
  '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

**Expected result:** Network remains healthy with 4/5 validators. Restarted node re-syncs and rejoins.

---

## 2. RPC Node Restart

**Test:** Stop RPC node, PWCScan shows offline briefly, restart, verify recovery.

```bash
# FAILURE
systemctl stop primewave-testnet-node  # On RPC node

# DETECTION: PWCScan proxy fails (503 from explorer)
curl -f https://testnet.pwcscan.example.com/indexer-api/health || echo "Indexer unavailable"

# RECOVERY
systemctl start primewave-testnet-node
sleep 30

# VERIFY
bash scripts/testnet/testnet-health-check.sh
```

---

## 3. Indexer Restart

**Test:** Stop indexer, restart, verify no data loss and sync resumes.

```bash
# FAILURE
systemctl stop primewave-testnet-indexer

# DETECTION: /health returns 503
curl -f http://localhost:4000/health || echo "Indexer down"

# Generate blocks while indexer is down
for i in $(seq 1 5); do
  cast send --private-key $TEST_KEY --rpc-url $TESTNET_RPC_URL \
    $TEST_ADDR --value 1gwei
done

# RECOVERY
systemctl start primewave-testnet-indexer
sleep 10

# VERIFY: Indexer caught up (isSynced: true)
curl -s http://localhost:4000/stats | python3 -m json.tool | grep -E "isSynced|chainHead|latestIndexed"
# Expected: latestIndexed == chainHead, isSynced: true
```

---

## 4. Keeper Restart

**Test:** Stop keeper, trigger validator sync event, restart keeper, verify it processes missed events.

```bash
# FAILURE
systemctl stop primewave-testnet-keeper

# Trigger a validator state change while keeper is down
# (simulated in testnet via admin operation)

# DETECTION
curl -f http://localhost:8080/health || echo "Keeper down"

# RECOVERY
systemctl start primewave-testnet-keeper
sleep 30

# VERIFY: Keeper processed missed events
journalctl -fu primewave-testnet-keeper | grep -E "syncValidator|processed"
```

---

## 5. PostgreSQL Restart

**Test:** Stop PostgreSQL, restart, verify indexer reconnects automatically.

```bash
# FAILURE
systemctl stop postgresql

# DETECTION: Indexer logs DB connection error
journalctl -fu primewave-testnet-indexer | grep -E "error|ECONNREFUSED"

# RECOVERY
systemctl start postgresql
sleep 5

# VERIFY: Indexer reconnects (check health)
curl -s http://localhost:4000/health
# Expected: {"success":true}
```

---

## 6. Database Backup → Destroy → Restore Test

**Test:** Create backup, drop and recreate DB, restore, verify indexer resumes.

```bash
# BACKUP
BACKUP_DIR=/backups/testnet-db \
PGDATABASE=primewave_testnet \
bash scripts/testnet/backup-testnet-db.sh

BACKUP_FILE=$(ls -1t /backups/testnet-db/*.dump | head -1)
echo "Backup: $BACKUP_FILE"

# Stop indexer before restore
systemctl stop primewave-testnet-indexer

# RESTORE
BACKUP_FILE="$BACKUP_FILE" \
PGDATABASE=primewave_testnet \
bash scripts/testnet/restore-testnet-db.sh

# VERIFY: Data integrity
psql primewave_testnet -c "SELECT COUNT(*) FROM blocks;"
psql primewave_testnet -c "SELECT COUNT(*) FROM transactions;"
psql primewave_testnet -c "SELECT MAX(number) FROM blocks;"

# Resume indexer
systemctl start primewave-testnet-indexer
sleep 10
curl -s http://localhost:4000/stats
# Expected: isSynced:true, latestIndexed near chain head
```

---

## 7. Bootstrap Node Restart

**Test:** Restart one bootstrap node, verify new nodes can still join network.

```bash
# FAILURE: Stop bootstrap node (if separate from validator)
# (Bootstrap nodes in the testnet topology serve as entry points for new nodes)

# DETECTION: New nodes may temporarily fail to join
# Existing nodes unaffected

# RECOVERY: Restart bootstrap
systemctl restart primewave-testnet-node

# VERIFY: Start a fresh node and confirm it syncs
# (Requires a spare VM — test with new AvalancheGo instance)
```

---

## 8. Validator Failure (Take One Offline)

**Test:** Take validator 5 offline, verify network health, bring it back.

```bash
# FAILURE: Stop validator 5
ssh validator-5 'systemctl stop primewave-testnet-node'

# DETECTION
bash scripts/testnet/testnet-health-check.sh
# Expected: 4/5 validators → consensus continues (BFT tolerates f<N/3 failures, 1/5 < 1/3)

# Verify fee accounting: validator 5 stops earning fees
BLOCK_BEFORE=$(cast block-number --rpc-url $TESTNET_RPC_URL)
sleep 30
BLOCK_AFTER=$(cast block-number --rpc-url $TESTNET_RPC_URL)
echo "Blocks produced with validator 5 down: $((BLOCK_AFTER - BLOCK_BEFORE))"

# Keeper should detect validator 5 status change
journalctl -u primewave-testnet-keeper | grep "validator"

# RECOVERY: Restart validator 5
ssh validator-5 'systemctl start primewave-testnet-node'
sleep 120  # Allow sync

# VERIFY: Validator 5 synced and rejoined
ssh validator-5 'curl -s http://localhost:9650/ext/health | python3 -m json.tool | grep healthy'
```

---

## 9. Invalid Keeper Transaction

**Test:** Keeper sends transaction that reverts, verify keeper handles error and retries.

```bash
# Simulate: Send invalid syncValidator call with wrong validator ID
# Expected: Keeper logs the revert, retries after delay, does not halt

# Check keeper logs for proper error handling
journalctl -u primewave-testnet-keeper | grep -E "revert|retry|error"
# Expected: no silent failure — error is logged, retry scheduled
```

---

## 10. RPC Timeout Test

**Test:** Simulate slow/unresponsive RPC, verify indexer and keeper handle gracefully.

```bash
# Add 5s delay to RPC responses (requires traffic control or nginx config)
# iptables -A OUTPUT -d <rpc-host> -m statistic --mode random --probability 0.5 -j DROP

# Check indexer behavior: should log timeout, retry, not crash
journalctl -fu primewave-testnet-indexer | grep -E "timeout|retry|error"

# Check keeper: should log timeout, retry
journalctl -fu primewave-testnet-keeper | grep -E "timeout|retry"

# Remove traffic control
# iptables -D OUTPUT -d <rpc-host> ...
```

---

## 11. Reindex Test

**Test:** Truncate indexed data and verify full reindex produces identical results.

```bash
# Record state before
BLOCKS_BEFORE=$(psql primewave_testnet -tAc "SELECT COUNT(*) FROM blocks")
TXS_BEFORE=$(psql primewave_testnet -tAc "SELECT COUNT(*) FROM transactions")

# Stop indexer
systemctl stop primewave-testnet-indexer

# Truncate (reindex tool requires PRIMEWAVE_ALLOW_REINDEX=yes)
PRIMEWAVE_ALLOW_REINDEX=yes \
INDEXER_DB_URL=$INDEXER_DB_URL \
node indexer/dist/bin/reindex.js --from 0 --to $(cast block-number --rpc-url $TESTNET_RPC_URL) --verify

# Restart indexer
systemctl start primewave-testnet-indexer

# VERIFY: Same counts
BLOCKS_AFTER=$(psql primewave_testnet -tAc "SELECT COUNT(*) FROM blocks")
TXS_AFTER=$(psql primewave_testnet -tAc "SELECT COUNT(*) FROM transactions")
echo "Blocks: before=$BLOCKS_BEFORE after=$BLOCKS_AFTER (must match)"
echo "Txs:    before=$TXS_BEFORE after=$TXS_AFTER (must match)"
```

---

## Summary: Failure Recovery Matrix

| Scenario | Network Impact | Data Loss | Auto-Recovery | Manual Steps |
|---|---|---|---|---|
| 1 validator restart | None (4/5 BFT) | None | Yes | Verify sync |
| RPC node restart | Temporary 503 | None | Yes | None |
| Indexer restart | None | None | Yes (resume from latest_block) | None |
| Keeper restart | Delayed syncs | None | Yes (reprocesses) | None |
| PostgreSQL restart | Brief indexer error | None | Yes (reconnect) | None |
| DB backup → restore | Brief downtime | None | Yes (after restore) | restore-testnet-db.sh |
| 1 validator failure | None (4/5 BFT) | None | Manual | restart validator |
