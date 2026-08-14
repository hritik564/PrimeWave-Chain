# PW-C15 — SOAK TEST

**Sprint:** PW-C15 — Testnet Battle Test + Mainnet Readiness
**Status:** PROCEDURE READY — PENDING EXTERNAL EXECUTION
**Environment:** TESTNET ONLY — Chain ID 77

---

## 1. OBJECTIVE

Run a continuous testnet soak to surface:
- Memory leaks in long-running services
- Database growth patterns
- Disk usage over time
- Unexpected crashes or restarts
- Performance degradation under sustained load
- Any latent conservation or data integrity issues

**Target duration:** ≥ 24 hours (infrastructure permitting)

---

## 2. SOAK TEST CONFIGURATION

```bash
# Start soak test monitoring script
cat > /tmp/soak-monitor.sh << 'EOF'
#!/bin/bash
LOG=/var/log/primewave-soak.log
START=$(date +%s)

while true; do
  NOW=$(date +%s)
  ELAPSED=$(( (NOW - START) / 3600 ))
  BLOCK=$(cast block-number --rpc-url $TESTNET_RPC 2>/dev/null || echo "RPC_ERR")
  PEERS=$(curl -sf -X POST -H 'Content-Type: application/json' \
    --data '{"jsonrpc":"2.0","id":1,"method":"info.peers","params":[]}' \
    http://localhost:9650/ext/info | jq '.result.numPeers' 2>/dev/null || echo "ERR")
  DB_BLOCK=$(psql $DATABASE_URL -t -c "SELECT MAX(number) FROM blocks;" 2>/dev/null | tr -d ' ')
  LAG=$((BLOCK - DB_BLOCK))
  DISK=$(df /var/lib/avalanchego | tail -1 | awk '{print $5}')
  MEM=$(free -m | grep Mem | awk '{print $3}')
  KEEPER_HB=$(stat -c %Y /var/lib/primewave-keeper/heartbeat 2>/dev/null || echo 0)
  KEEPER_AGE=$(( NOW - KEEPER_HB ))
  
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) H+${ELAPSED}h block=$BLOCK peers=$PEERS db_lag=${LAG}blk disk=$DISK mem=${MEM}MB keeper_age=${KEEPER_AGE}s" \
    | tee -a $LOG
  
  sleep 300  # log every 5 minutes
done
EOF
chmod +x /tmp/soak-monitor.sh
nohup /tmp/soak-monitor.sh &
```

---

## 3. SOAK TEST LOAD GENERATION

Light continuous transaction load during soak:

```bash
# Generate 1 tx per minute to keep chain active and fee accounting running
cat > /tmp/soak-txgen.sh << 'EOF'
#!/bin/bash
while true; do
  cast send $TEST_ADDR_2 \
    --value 1gwei \
    --rpc-url $TESTNET_RPC \
    --private-key $TEST_KEY_1 2>/dev/null
  sleep 60
done
EOF
nohup /tmp/soak-txgen.sh &
```

---

## 4. MONITORING CHECKLIST (EVERY 6 HOURS)

Check these items at 0h, 6h, 12h, 18h, 24h:

| Metric | 0h | 6h | 12h | 18h | 24h |
|---|---|---|---|---|---|
| Block number | TBD | TBD | TBD | TBD | TBD |
| Peers (avg across validators) | TBD | TBD | TBD | TBD | TBD |
| DB indexer lag (blocks) | TBD | TBD | TBD | TBD | TBD |
| Keeper last heartbeat age | TBD | TBD | TBD | TBD | TBD |
| Disk used % | TBD | TBD | TBD | TBD | TBD |
| Memory used (MB) | TBD | TBD | TBD | TBD | TBD |
| CPU avg % | TBD | TBD | TBD | TBD | TBD |
| Service restarts (count) | TBD | TBD | TBD | TBD | TBD |
| Fee conservation check | TBD | TBD | TBD | TBD | TBD |
| RewardVault balance | TBD | TBD | TBD | TBD | TBD |
| PWCScan responding | TBD | TBD | TBD | TBD | TBD |
| Monitoring alerts fired | TBD | TBD | TBD | TBD | TBD |

---

## 5. ACCEPTANCE CRITERIA

| Criterion | Required |
|---|---|
| Block production continuous for 24h | Yes — no halt > 30s |
| All validators remain connected | ≥ 10 of 15 (or full set) |
| Indexer lag never exceeds 100 blocks | Yes |
| Keeper heartbeat never stale > 10m | Yes |
| No unplanned service restarts | Yes (only graceful, if any) |
| No conservation violation | Yes (zero tolerance) |
| Disk growth < 10 GB / 24h | Yes (or documented if higher) |
| Memory stable (no runaway growth) | Yes (< 20% growth over 24h) |
| No new security findings | Yes |
| PWCScan always accessible | Yes (< 1m total downtime) |

---

## 6. PARTIAL SOAK DOCUMENTATION

If 24 hours cannot be completed during the current sprint:

| Field | Value |
|---|---|
| Soak start time | TBD |
| Soak end time | TBD |
| Actual soak duration | TBD |
| Reason for early termination | TBD (infrastructure limit / planned) |
| Blocks produced during soak | TBD |
| Issues found | TBD |
| Remaining soak requirement | TBD hours |
| Recommended completion | Before C16 gate |

> **Note:** Any shortfall in soak duration must be explicitly accepted by
> the C16 entry gate checklist as a DEFERRED item with a defined completion date.

---

## 7. SOAK TEST RESULTS

| Metric | Result | Pass/Fail |
|---|---|---|
| Duration achieved | TBD | 🔵 |
| Block production continuous | TBD | 🔵 |
| Validator health throughout | TBD | 🔵 |
| Indexer stability | TBD | 🔵 |
| Keeper stability | TBD | 🔵 |
| Database stability | TBD | 🔵 |
| Fee conservation | TBD | 🔵 |
| Disk growth rate | TBD | 🔵 |
| Memory stability | TBD | 🔵 |
| Service restarts | TBD | 🔵 |
| Security events | TBD | 🔵 |

---

## 8. DISK GROWTH PROJECTION

> Fill after soak — used to size mainnet infrastructure

| Service | Data Directory | Size at 0h | Size at 24h | Growth/day | Projected 1-year |
|---|---|---|---|---|---|
| AvalancheGo | `/var/lib/avalanchego` | TBD | TBD | TBD | TBD |
| PostgreSQL | `/var/lib/postgresql` | TBD | TBD | TBD | TBD |
| Logs | `/var/log` | TBD | TBD | TBD | TBD |

**Mainnet disk recommendation:** Based on testnet growth rate × expected mainnet
traffic multiplier × 2x safety margin.
