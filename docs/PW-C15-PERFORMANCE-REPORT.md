# PW-C15 — PERFORMANCE REPORT

**Sprint:** PW-C15 — Testnet Battle Test + Mainnet Readiness
**Status:** PROCEDURE READY — PENDING EXTERNAL EXECUTION
**Environment:** TESTNET ONLY — Chain ID 77

> **Principle:** Report observed values, test conditions, and limitations honestly.
> Do not manufacture TPS numbers. All figures are from testnet observations only.

---

## 1. METRICS MEASURED

| Metric | Instrument | Sample Rate |
|---|---|---|
| Block time | Chain RPC timestamps | Every block |
| TPS (observed) | Indexer tx count / block time | Per block |
| RPC latency | k6 percentiles | 1 req/sec baseline |
| Indexer throughput | blocks/sec during sync | Full sync |
| DB write rate | PostgreSQL `pg_stat_bgwriter` | 1-minute windows |
| Keeper latency | Log timestamps | Per sync event |
| Validator sync time | P-Chain registration → on-chain | End-to-end |
| Memory (per service) | `node_exporter` RSS | 5-minute avg |
| CPU (per service) | `node_exporter` cpu_seconds | 5-minute avg |
| Disk write rate | `node_exporter` disk_io | 5-minute avg |

---

## 2. BLOCK TIME

```bash
# Measure block time over 100 consecutive blocks
python3 - << 'EOF'
import subprocess, json, time, statistics

blocks = []
for i in range(100):
    result = subprocess.run(
        ['cast', 'block', 'latest', '--rpc-url', '$TESTNET_RPC', '--json'],
        capture_output=True, text=True
    )
    block = json.loads(result.stdout)
    blocks.append(int(block['timestamp'], 16))
    time.sleep(3)

deltas = [b - a for a, b in zip(blocks, blocks[1:])]
print(f"Block times (n={len(deltas)})")
print(f"  Mean:   {statistics.mean(deltas):.2f}s")
print(f"  Median: {statistics.median(deltas):.2f}s")
print(f"  StdDev: {statistics.stdev(deltas):.2f}s")
print(f"  Min:    {min(deltas):.2f}s")
print(f"  Max:    {max(deltas):.2f}s")
EOF
```

| Metric | Expected (subnet-evm) | Actual |
|---|---|---|
| Mean block time | ~2s | TBD |
| Median block time | ~2s | TBD |
| StdDev | < 1s | TBD |
| Min block time | ≥ 1s | TBD |
| Max block time | < 10s under load | TBD |

---

## 3. TRANSACTION THROUGHPUT (TPS)

> TPS is measured at the observed testnet load. It is not a maximum capacity claim.

```bash
# Generate a batch of test transactions
for i in $(seq 1 1000); do
  cast send $TARGET_ADDR \
    --value 1gwei \
    --rpc-url $TESTNET_RPC \
    --private-key $TEST_KEY &
done
wait

# Count txs in the next 60 seconds of blocks
START_BLOCK=$(cast block-number --rpc-url $TESTNET_RPC)
sleep 60
END_BLOCK=$(cast block-number --rpc-url $TESTNET_RPC)
psql $DATABASE_URL -c "
  SELECT COUNT(*) AS txs, COUNT(*) / GREATEST($((END_BLOCK - START_BLOCK)), 1)::float / 2 AS approx_tps
  FROM transactions
  WHERE block_number BETWEEN $START_BLOCK AND $END_BLOCK;"
```

| Metric | Value |
|---|---|
| Test transactions submitted | 1000 |
| Blocks observed | TBD |
| Total txs in those blocks | TBD |
| Approximate TPS (observed) | TBD |
| Test conditions | TBD (N validators, cloud hardware) |
| Limitations | Single load-generating client; not max capacity |

---

## 4. RPC LATENCY

Measured during steady-state (10 concurrent clients):

| Endpoint | p50 | p95 | p99 | Notes |
|---|---|---|---|---|
| `eth_blockNumber` | TBD | TBD | TBD | Hot path |
| `eth_getBlockByNumber` | TBD | TBD | TBD | With full tx objects |
| `eth_getTransactionReceipt` | TBD | TBD | TBD | |
| `eth_call` (simple view) | TBD | TBD | TBD | |
| `eth_getLogs` (100-block range) | TBD | TBD | TBD | |

---

## 5. INDEXER THROUGHPUT

### 5.1 Historical Sync Rate

```bash
START_TIME=$(date +%s)
# Start fresh sync
psql $DATABASE_URL -c "TRUNCATE blocks CASCADE;"
sudo systemctl restart primewave-indexer
sleep 600  # 10 minutes

# Measure rate
END_TIME=$(date +%s)
INDEXED=$(psql $DATABASE_URL -t -c "SELECT COUNT(*) FROM blocks;")
ELAPSED=$((END_TIME - START_TIME))
echo "Rate: $((INDEXED / ELAPSED)) blocks/sec"
```

| Metric | Expected | Actual |
|---|---|---|
| Historical sync rate | ≥ 50 blocks/sec | TBD |
| DB write rate during sync | TBD | TBD |
| CPU during sync | TBD | TBD |
| Memory during sync | TBD | TBD |

### 5.2 Continuous Sync Lag

At steady state with active chain:

| Metric | Target | Actual |
|---|---|---|
| Block lag | < 5 blocks | TBD |
| Lag in seconds | < 15s | TBD |
| Events processed per block | avg | TBD |

---

## 6. DATABASE WRITE RATE

```sql
-- PostgreSQL write metrics
SELECT
  buffers_clean + buffers_backend AS total_writes,
  pg_size_pretty(pg_database_size(current_database())) AS db_size
FROM pg_stat_bgwriter;
```

| Metric | 1-min avg | 5-min avg | 30-min avg |
|---|---|---|---|
| Writes/sec | TBD | TBD | TBD |
| DB size growth/hour | TBD | TBD | TBD |
| Disk IO utilization | TBD | TBD | TBD |

---

## 7. KEEPER LATENCY

```bash
# Measure time from P-Chain event to registry update
# Requires log correlation between P-Chain submission and keeper sync tx
journalctl -u primewave-keeper | grep "syncValidator\|detected" | head -20
```

| Metric | Expected | Actual |
|---|---|---|
| Detection latency (P-Chain → keeper) | < keeper poll interval | TBD |
| Sync TX submission latency | < 30s | TBD |
| End-to-end (P-Chain → registry updated) | < 2 minutes | TBD |

---

## 8. VALIDATOR SYNCHRONIZATION TIME

| Metric | Observed |
|---|---|
| P-Chain registration → Warp delivery | TBD |
| Warp delivery → ValidatorManager complete | TBD |
| ValidatorManager → keeper syncValidator | TBD |
| Total P-Chain → registry eligible | TBD |

---

## 9. RESOURCE UTILIZATION

At steady state (continuous testnet operation):

| Service | CPU % | RAM (MB) | Disk Read MB/s | Disk Write MB/s |
|---|---|---|---|---|
| AvalancheGo | TBD | TBD | TBD | TBD |
| Indexer | TBD | TBD | TBD | TBD |
| PostgreSQL | TBD | TBD | TBD | TBD |
| Keeper | TBD | TBD | TBD | TBD |
| PWCScan | TBD | TBD | TBD | TBD |
| Prometheus | TBD | TBD | TBD | TBD |

---

## 10. PERFORMANCE SUMMARY

| Metric | Observed | Conditions | Adequate for Mainnet? |
|---|---|---|---|
| Block time | TBD | N validators | TBD |
| Observed TPS | TBD | 1 load client | TBD |
| RPC p95 latency | TBD | 10 clients | TBD |
| Indexer sync rate | TBD | Cloud hardware | TBD |
| Keeper latency | TBD | Normal load | TBD |

**Limitations of this measurement:**
- Testnet has limited validator count vs. mainnet target
- Load was generated from a single controlled client
- Results represent testnet hardware, not mainnet infrastructure
- These are observed values, not theoretical maximums

**Mainnet projection:** Performance characteristics may differ on mainnet based on
validator count, geographic distribution, and actual user load.
