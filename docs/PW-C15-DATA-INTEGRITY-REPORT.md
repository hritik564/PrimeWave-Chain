# PW-C15 — DATA INTEGRITY REPORT

**Sprint:** PW-C15 — Testnet Battle Test + Mainnet Readiness
**Status:** PROCEDURE READY — PENDING EXTERNAL EXECUTION
**Environment:** TESTNET ONLY — Chain ID 77

This document covers indexer integrity, database consistency, fee conservation,
and RewardVault accounting on the live testnet.

---

## 1. INDEXER INTEGRITY

### 1.1 C12 Integrity Check Suite

All C12 Jest integrity checks must pass against the live testnet indexer:

```bash
cd indexer
INDEXER_RPC_URL=https://rpc.testnet.primewave.xyz \
INDEXER_CHAIN_ID=77 \
npx jest --testPathPattern="integrity" --no-coverage
```

| Check | Expected | Actual |
|---|---|---|
| Parent hash continuity | Every block's parentHash matches previous block hash | TBD |
| Block number continuity | No gaps in block sequence 0..tip | TBD |
| Transaction count | DB tx count matches chain tx count for each block | TBD |
| Fee accounting | DB fee total matches sum of gas * gasPrice per block | TBD |
| RewardVault accounting | DB reward total matches vault events | TBD |
| Validator event ordering | Events monotonically ordered by block | TBD |
| No duplicate blocks | One row per block number in blocks table | TBD |
| No duplicate transactions | One row per tx hash | TBD |
| Orphan detection | No blocks without a parent chain path to genesis | TBD |
| Event decoding | All known ABI events decode without error | TBD |

### 1.2 Block Continuity SQL Check

```sql
-- Find any gaps in the block sequence
SELECT a.number + 1 AS missing_block
FROM blocks a
LEFT JOIN blocks b ON a.number + 1 = b.number
WHERE b.number IS NULL
  AND a.number < (SELECT MAX(number) FROM blocks)
ORDER BY 1;
-- Must return 0 rows
```

### 1.3 Parent Hash Continuity SQL Check

```sql
-- Find any blocks with wrong parent hash
SELECT b.number, b.hash, b.parent_hash, p.hash AS expected_parent
FROM blocks b
JOIN blocks p ON p.number = b.number - 1
WHERE b.parent_hash != p.hash
LIMIT 10;
-- Must return 0 rows
```

### 1.4 Transaction Count Verification

```sql
-- Compare DB tx counts with on-chain data (sampled)
SELECT b.number, b.transaction_count AS db_count, COUNT(t.hash) AS actual_count
FROM blocks b
LEFT JOIN transactions t ON t.block_number = b.number
GROUP BY b.number, b.transaction_count
HAVING b.transaction_count != COUNT(t.hash)
LIMIT 10;
-- Must return 0 rows
```

---

## 2. INDEXER SYNC SCENARIOS

### 2.1 Fresh Sync from Genesis

```bash
# Clear database
psql $DATABASE_URL -c "TRUNCATE blocks, transactions, logs, validator_events, fee_events, reward_events CASCADE;"

# Start indexer
sudo systemctl start primewave-indexer

# Monitor progress
watch -n 5 "psql $DATABASE_URL -t -c 'SELECT MAX(number) FROM blocks;'"

# Verify it reaches chain tip
```

| Metric | Expected | Actual |
|---|---|---|
| Sync speed | ≥ 100 blocks/sec (historical) | TBD |
| Time to tip | < 30 minutes for < 100k blocks | TBD |
| No errors during sync | Zero error logs | TBD |

### 2.2 Continuous Sync

After reaching tip, indexer continues in watch mode:

```bash
# Verify new blocks appear within 10 seconds of chain time
CHAIN_TIP=$(cast block-number --rpc-url $TESTNET_RPC)
DB_TIP=$(psql $DATABASE_URL -t -c "SELECT MAX(number) FROM blocks;")
LAG=$((CHAIN_TIP - DB_TIP))
echo "Lag: $LAG blocks"
# Must be < 5 blocks in continuous mode
```

### 2.3 Restart Recovery

```bash
# Pause indexer at block N
sudo systemctl stop primewave-indexer
sleep 60  # chain advances M blocks

# Restart
sudo systemctl start primewave-indexer

# Verify it catches up from block N, not from 0
journalctl -u primewave-indexer | grep "Resuming\|Starting from"
```

### 2.4 RPC Outage Handling

```bash
# Block RPC access temporarily
sudo iptables -A OUTPUT -p tcp --dport 443 -d rpc.testnet.primewave.xyz -j DROP
sleep 120

# Verify indexer retries (does not crash)
journalctl -u primewave-indexer | grep -i "retry\|reconnect\|error"

# Restore RPC access
sudo iptables -D OUTPUT -p tcp --dport 443 -d rpc.testnet.primewave.xyz -j DROP

# Verify indexer resumes from the last indexed block
```

### 2.5 Duplicate Prevention

```bash
# Attempt to manually trigger a duplicate index (should be idempotent)
curl -X POST http://localhost:3001/reindex/100
curl -X POST http://localhost:3001/reindex/100

# Verify no duplicate rows
psql $DATABASE_URL -c "SELECT block_number, COUNT(*) FROM transactions GROUP BY block_number HAVING COUNT(*) > (SELECT COUNT(*) FROM transactions t2 WHERE t2.block_number = block_number LIMIT 1);"
```

---

## 3. FEE CONSERVATION CHECKS

### 3.1 Conservation Invariant

For every block B:
```
sum(gasUsed[i] * gasPrice[i] for tx i in B)
  == ValidatorFeeVault.totalReceived[B] (70%)
   + Treasury.totalReceived[B] (20%)
   + burned[B] (10%)
```

### 3.2 SQL Conservation Check

```sql
-- Check fee conservation across all indexed blocks
SELECT
  b.number,
  b.total_fees_collected AS on_chain_fees,
  f.validator_amount + f.treasury_amount + f.burn_amount AS split_total,
  b.total_fees_collected - (f.validator_amount + f.treasury_amount + f.burn_amount) AS discrepancy
FROM blocks b
JOIN fee_events f ON f.block_number = b.number
WHERE b.total_fees_collected != (f.validator_amount + f.treasury_amount + f.burn_amount)
LIMIT 10;
-- Must return 0 rows (zero discrepancy)
```

### 3.3 Split Ratio Check

```sql
-- Verify 70/20/10 split on a sample
SELECT
  number,
  ROUND(validator_amount * 100.0 / NULLIF(total_fee, 0), 2) AS validator_pct,
  ROUND(treasury_amount * 100.0 / NULLIF(total_fee, 0), 2) AS treasury_pct,
  ROUND(burn_amount * 100.0 / NULLIF(total_fee, 0), 2) AS burn_pct
FROM (
  SELECT b.number,
    b.total_fees_collected AS total_fee,
    f.validator_amount, f.treasury_amount, f.burn_amount
  FROM blocks b JOIN fee_events f ON f.block_number = b.number
  WHERE b.total_fees_collected > 0
  LIMIT 100
) sub;
-- validator_pct ≈ 70, treasury_pct ≈ 20, burn_pct ≈ 10 (rounding allowed)
```

### 3.4 Conservation Test Results

| Test | Blocks Checked | Conservation Violations | Status |
|---|---|---|---|
| Standard blocks | TBD | 0 expected | 🔵 |
| Zero-fee blocks | TBD | 0 expected | 🔵 |
| Large fee blocks | TBD | 0 expected | 🔵 |
| Rounding edge cases | TBD | 0 expected | 🔵 |
| Multi-validator churn | TBD | 0 expected | 🔵 |

**Acceptance:** Any conservation violation is a STOP condition.

---

## 4. REWARDVAULT ACCOUNTING

### 4.1 Vault Balance Progression

```bash
# Check vault balance at multiple points in time
cast balance $REWARD_VAULT_ADDRESS --rpc-url $TESTNET_RPC --block latest
cast balance $REWARD_VAULT_ADDRESS --rpc-url $TESTNET_RPC --block earliest
```

Expected: Balance only decreases (never increases). Vault started with 15M PW.

### 4.2 Emission Rate Check

```sql
-- Check total emitted so far
SELECT
  MAX(total_emitted) AS total_emitted_pw,
  15000000 * 1e18 - MAX(total_emitted) AS remaining_reserve,
  3000000 * 1e18 AS annual_cap
FROM reward_vault_snapshots;
-- total_emitted_pw <= 15000000 * 1e18
-- Must never exceed annual_cap proportionally
```

### 4.3 No-Mint Check

```bash
# Verify no ERC-20 Transfer events from the zero address on the PW token
# (NativeMinter disabled — no mint events should ever appear)
cast logs \
  --from-block earliest \
  --to-block latest \
  --address $PW_TOKEN_ADDRESS \
  --topic0 "Transfer(address,address,uint256)" \
  --topic1 "0x0000000000000000000000000000000000000000000000000000000000000000" \
  --rpc-url $TESTNET_RPC
# Must return empty (no mint events)
```

### 4.4 Claim Integrity

```sql
-- Verify every claim matches a corresponding vault withdrawal
SELECT r.validator_id, r.claimed_amount, v.withdrawn_amount
FROM reward_claims r
LEFT JOIN vault_withdrawals v ON v.claim_id = r.id
WHERE r.claimed_amount != v.withdrawn_amount;
-- Must return 0 rows
```

---

## 5. STAKING DATA INTEGRITY

### 5.1 Stake / Unstake Accounting

```sql
-- Check that stake in == stake out + active stake
SELECT
  SUM(CASE WHEN event_type = 'stake' THEN amount ELSE 0 END) AS total_staked,
  SUM(CASE WHEN event_type = 'unstake' THEN amount ELSE 0 END) AS total_unstaked,
  (SELECT SUM(amount) FROM active_stakes) AS active,
  SUM(CASE WHEN event_type = 'stake' THEN amount ELSE 0 END) -
  SUM(CASE WHEN event_type = 'unstake' THEN amount ELSE 0 END) AS expected_active
FROM staking_events;
-- active must == expected_active
```

### 5.2 Unbonding Period

For any unbond initiated at block `B`, verify withdrawal fails before 14 days
and succeeds after:

```bash
UNBOND_BLOCK=$(psql $DATABASE_URL -t -c "SELECT block_number FROM staking_events WHERE event_type='unbond' LIMIT 1;")
UNBOND_TIME=$(cast block $UNBOND_BLOCK --rpc-url $TESTNET_RPC --json | jq .timestamp)
CURRENT_TIME=$(date +%s)
echo "Days since unbond: $(( (CURRENT_TIME - UNBOND_TIME) / 86400 ))"
```

---

## 6. PWCSCAN DATA VERIFICATION

PWCScan data is cross-validated against direct RPC/chain queries:

| Data Field | PWCScan Source | Direct Chain Query | Match? |
|---|---|---|---|
| Block hash | Indexer DB | `eth_getBlockByNumber` | TBD |
| Tx hash | Indexer DB | `eth_getTransactionByHash` | TBD |
| Tx status | Indexer DB | `eth_getTransactionReceipt` | TBD |
| Validator weight | Indexer DB | `getValidatorWeight()` call | TBD |
| Fee totals | Indexer DB | `totalCollected()` call | TBD |
| Reward totals | Indexer DB | `totalEmitted()` call | TBD |
| Supply | PWCScan stats | `eth_getBalance(rewardVault)` | TBD |

**Acceptance:** PWCScan may show no mocked or manually inserted data. Every displayed
value must match its on-chain or indexer source within one finalized block.

---

## 7. INTEGRITY RESULTS SUMMARY

| Category | Checks | Pass | Fail | Status |
|---|---|---|---|---|
| Block continuity | TBD | TBD | TBD | 🔵 |
| Transaction integrity | TBD | TBD | TBD | 🔵 |
| Fee conservation | TBD | TBD | TBD | 🔵 |
| RewardVault accounting | TBD | TBD | TBD | 🔵 |
| Staking accounting | TBD | TBD | TBD | 🔵 |
| PWCScan accuracy | TBD | TBD | TBD | 🔵 |
| No-mint invariant | TBD | TBD | TBD | 🔵 |
