# PW-C15 — VALIDATOR OPERATIONS

**Sprint:** PW-C15 — Testnet Battle Test + Mainnet Readiness
**Status:** OPERATIONAL RUNBOOK — PENDING EXTERNAL EXECUTION
**Environment:** TESTNET ONLY — Chain ID 77

---

## 1. VALIDATOR ARCHITECTURE

PrimeWave Testnet targets 15 independent validator nodes. If fewer are available,
report the actual count — do NOT fabricate 15.

**Phase:** PoA (PrimeWave Phase 1). ValidatorManager is the authoritative source.
Custom PoS (PrimeWaveStakingManager, C09) is deployed but Phase 2 transition is TBD.

```
Fuji P-Chain validator set
        ↓ (Warp / ICM / ACP-99)
ACP-99 ValidatorManager (EVM contract)
        ↓ (keeper sync)
PrimeWaveValidatorRegistry
        ↓
ValidatorFeeVault (weight-based fee distribution)
        +
RewardVault (reward accrual)
```

---

## 2. VALIDATOR REQUIREMENTS

Each validator must have:

| Requirement | Specification |
|---|---|
| Persistent storage | SSD ≥ 500 GB (chain data grows continuously) |
| Unique identity | Distinct NodeID + BLS key pair |
| BLS credentials | Generated securely per `generate-validator-keys.sh` |
| Network config | Static IP or DNS; firewall open on P2P port (9651) |
| Monitoring | Prometheus node_exporter + AvalancheGo metrics |
| Restart procedure | systemd with `Restart=always` |
| Backup procedure | Node config + BLS key backed up (encrypted) |

**Independence constraint:** Validators must not depend on the Replit development
process, shared storage, or a single point of failure.

---

## 3. VALIDATOR KEY GENERATION (TESTNET)

```bash
# Generate unique testnet key for each validator
bash scripts/testnet/generate-validator-keys.sh <validator-name>
```

Output:
- `<validator-name>-node-id.txt` — public NodeID (safe to share)
- `<validator-name>-staking.key` — TLS staking private key (KEEP PRIVATE)
- `<validator-name>-staking.crt` — TLS staking certificate
- `<validator-name>-bls.key` — BLS signing key (KEEP PRIVATE)
- `<validator-name>-bls.pub` — BLS public key (submit to P-Chain)

**Security:**
- Never commit keys to this repository
- Store encrypted with separate passphrase per key
- Physical or HSM storage preferred for testnet operators

---

## 4. ACTUAL VALIDATOR COUNT

| Validator | NodeID | Status | Infrastructure |
|---|---|---|---|
| V-01 | TBD | 🔵 PENDING | Cloud server TBD |
| V-02 | TBD | 🔵 PENDING | Cloud server TBD |
| V-03 | TBD | 🔵 PENDING | Cloud server TBD |
| V-04 | TBD | 🔵 PENDING | Cloud server TBD |
| V-05 | TBD | 🔵 PENDING | Cloud server TBD |
| ... | TBD | 🔵 PENDING | ... |
| Total | — | — | Target: 15 / Actual: TBD |

Update this table with actual node IDs and cloud server details after provisioning.

---

## 5. NODE CONFIGURATION

Each AvalancheGo node must use `deploy/testnet/config/node-config.json` with:

```json
{
  "network-id": "fuji",
  "http-host": "0.0.0.0",
  "http-port": 9650,
  "staking-port": 9651,
  "db-dir": "/var/lib/avalanchego/db",
  "log-level": "info",
  "bootstrap-ids": ["<BOOTSTRAP_NODE_ID>"],
  "bootstrap-ips": ["<BOOTSTRAP_NODE_IP>:9651"]
}
```

And `deploy/testnet/config/chain-config.json` for the L1 chain config:

```json
{
  "feeManagerAdminAddr": "<DEPLOYER>",
  "contractDeployerAllowListConfig": {},
  "contractNativeMinterConfig": {},
  "adminFeeRecipient": "<FEE_DISTRIBUTOR>"
}
```

---

## 6. BOOTSTRAP / PEERING

### 6.1 Initial Bootstrap Sequence

```
fresh validator node
        ↓
reads bootstrap-ids / bootstrap-ips from config
        ↓
TLS handshake with bootstrap peer
        ↓
discovers additional peers via Avalanche peer protocol
        ↓
downloads P-Chain state from Fuji
        ↓
downloads PrimeWave subnet chain state (blockchain ID)
        ↓
reaches latest block (eth_syncing returns false)
```

### 6.2 Verification

```bash
# After starting a fresh node, poll until synced
for i in $(seq 1 60); do
  SYNCING=$(curl -sf -X POST -H 'Content-Type: application/json' \
    --data '{"jsonrpc":"2.0","id":1,"method":"eth_syncing","params":[]}' \
    http://localhost:9650/ext/bc/<BLOCKCHAIN_ID>/rpc | jq '.result')
  echo "Syncing: $SYNCING"
  if [ "$SYNCING" = "false" ]; then echo "SYNCED"; break; fi
  sleep 30
done
```

### 6.3 Peering Test Results

| Test | Scenario | Expected | Actual |
|---|---|---|---|
| BST-01 | Fresh node bootstrap | Syncs to latest block within 30m | TBD |
| BST-02 | Peer discovery | ≥ 5 peers found | TBD |
| BST-03 | Block propagation | New block seen on all validators within 5s | TBD |
| BST-04 | Transaction propagation | Tx seen in mempool on all nodes within 10s | TBD |
| BST-05 | Restart sync | Node re-syncs to tip within 5m after restart | TBD |
| BST-06 | Delayed catch-up (1h offline) | Catches up to tip within 20m | TBD |
| BST-07 | Peer count stability | Peer count stable over 1h | TBD |

### 6.4 Observed Peer Counts

| Validator | Peer Count | Block Height | Block Time | Status |
|---|---|---|---|---|
| V-01 | TBD | TBD | TBD | 🔵 PENDING |
| V-02 | TBD | TBD | TBD | 🔵 PENDING |
| ... | | | | |

---

## 7. ACP-99 VALIDATOR LIFECYCLE

### 7.1 Real Registration Flow

```bash
# Step 1: P-Chain registration (via Avalanche CLI)
avalanche validator add --subnet-id <SUBNET_ID> \
  --node-id <NODE_ID> \
  --bls-public-key <BLS_PUB_KEY> \
  --stake-amount 2000  # in nAVAX
  --start-time <UNIX_TS>
  --end-time <UNIX_TS>

# Fuji P-Chain emits a Warp message to the ValidatorManager
# ICM relayer delivers the message to the EVM ValidatorManager

# Step 2: ValidatorManager completes registration on-chain
# (automatic via ICM relayer — no manual call needed if relayer is running)

# Step 3: Verify on-chain
cast call $VALIDATOR_MANAGER "getValidator(bytes32)(uint8,uint64,bytes)" \
  $NODE_ID_BYTES32 --rpc-url $TESTNET_RPC
```

### 7.2 Lifecycle State Machine

```
P-Chain: registered
    → Warp → ICM relayer → ValidatorManager.completeValidatorRegistration()
        → PrimeWaveValidatorRegistry.syncValidator() (keeper)
            → ValidatorFeeVault weight set
                → Validator eligible for fees and rewards
                    → (on removal) PrimeWaveStakingManager.forceInitiateValidatorRemoval()
```

Do NOT bypass any step with devActivate or test shortcuts.

---

## 8. VALIDATOR FAILURE TEST

### 8.1 Procedure

```bash
# 1. Identify target validator
export TARGET_VALIDATOR="V-05"

# 2. Record current block height on all nodes
for v in V-01 V-02 V-03 V-04 V-06; do
  echo "$v: $(cast block-number --rpc-url http://$v:9650/ext/bc/<BLOCKCHAIN_ID>/rpc)"
done

# 3. Stop target validator
ssh $TARGET_VALIDATOR "sudo systemctl stop primewave-node"

# 4. Verify remaining network continues
sleep 120
for v in V-01 V-02 V-03 V-04 V-06; do
  echo "$v: $(cast block-number --rpc-url http://$v:9650/ext/bc/<BLOCKCHAIN_ID>/rpc)"
done
# Block heights must continue to increase

# 5. Verify keeper detects weight change (if applicable)
journalctl -u primewave-keeper | tail -50

# 6. Check fee accounting integrity
cast call $FEE_DISTRIBUTOR "totalCollected()(uint256)" --rpc-url $TESTNET_RPC

# 7. Restore validator
ssh $TARGET_VALIDATOR "sudo systemctl start primewave-node"

# 8. Verify sync
# Wait for validator to reach tip
```

### 8.2 Expected Results

| Check | Expected | Actual |
|---|---|---|
| Network continues | Block height increases with N-1 validators | TBD |
| Block production | New blocks produced without the offline validator | TBD |
| Keeper detects | Weight updated within keeper polling interval | TBD |
| Fee accounting | No conservation violation during outage | TBD |
| Sync on return | Validator reaches tip within 20m | TBD |
| No duplicate rewards | totalEmitted unchanged during outage | TBD |
| No duplicate fees | No double-counting in FeeDistributor | TBD |

---

## 9. MULTI-NODE CONSISTENCY

### 9.1 Check Procedure

```bash
#!/bin/bash
# Compare state across all validators
VALIDATORS=(V-01-RPC V-02-RPC V-03-RPC V-04-RPC V-05-RPC)
BLOCK=$(cast block-number --rpc-url ${VALIDATORS[0]})

echo "Checking block $BLOCK across all validators..."
for v in "${VALIDATORS[@]}"; do
  HASH=$(cast block $BLOCK --rpc-url $v --json | jq -r .hash)
  ROOT=$(cast block $BLOCK --rpc-url $v --json | jq -r .stateRoot)
  echo "$v: hash=$HASH stateRoot=$ROOT"
done
```

### 9.2 Acceptance Criteria

| Metric | Criteria | Actual |
|---|---|---|
| Block height | All validators within 1 block | TBD |
| Block hash | Identical for confirmed blocks | TBD |
| State root | Identical for confirmed blocks | TBD |
| Transaction receipts | Same outcome on all nodes | TBD |
| Contract state | `getValidator()` returns same on all nodes | TBD |

**STOP CONDITION:** Persistent divergence (> 3 blocks or state root mismatch) halts the testnet.

---

## 10. VALIDATOR MONITORING DASHBOARD

Prometheus targets for each validator (expose AvalancheGo metrics):

```yaml
# In deploy/testnet/prometheus/prometheus.yml
scrape_configs:
  - job_name: 'avalanchego-validators'
    static_configs:
      - targets:
          - 'validator-01:9090'
          - 'validator-02:9090'
          # ... all 15 validators
    metrics_path: /ext/metrics
```

Key metrics to watch:

| Metric | Alert Threshold | Description |
|---|---|---|
| `avalanche_network_peers` | < 3 | Isolated validator |
| `avalanche_chain_handler_pending_get_count` | > 1000 | Handler backup |
| `avalanche_chain_vm_block_build_success_count` | stagnant | Block production stopped |
| `process_resident_memory_bytes` | > 8GB | Memory pressure |
| `node_disk_io_time_seconds_total` | rate > 0.8 | Disk saturation |
