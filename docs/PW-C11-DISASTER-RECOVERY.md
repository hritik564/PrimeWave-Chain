# PW-C11: Disaster Recovery

**Sprint:** C11 — Production Infrastructure + Validator Keeper + Genesis Finalization
**Status:** COMPLETE
**Date:** 2026-08-14

---

## 1. Backup Strategy

### 1.1 What Must Be Backed Up

| Asset | Frequency | Location | Retention |
|-------|-----------|----------|-----------|
| Staking certificate + key (`staker.crt`, `staker.key`) | Once (immutable) | HSM + offline encrypted backup | Forever |
| AvalancheGo data directory | Daily snapshot | Secure offsite storage | 30 days |
| Contract deployment addresses | Once (after ceremony) | `docs/PRIMEWAVE_INFRASTRUCTURE.md` + offline | Forever |
| Keeper `keeper-state.json` | Continuous (daemon writes) | Local + nightly backup | 30 days |
| Prometheus metrics data | Continuous | TSDB + nightly backup | 90 days |
| Governance keys (EMS signers) | Per key rotation | HSM, offline | Forever |

### 1.2 Staking Key Backup

Staking keys (`staker.crt`, `staker.key`) define the validator's NodeID. If lost, the validator identity is lost permanently.

**Backup procedure:**
```bash
# On validator node — generate and immediately back up
openssl x509 -in /var/lib/avalanchego/staking/staker.crt -noout -fingerprint -sha256

# Encrypt backup with operator GPG key
tar czf staker-backup.tar.gz \
    /var/lib/avalanchego/staking/staker.crt \
    /var/lib/avalanchego/staking/staker.key
gpg --recipient $OPERATOR_GPG_KEY --encrypt staker-backup.tar.gz

# Store encrypted file in:
#   1. Hardware security module (HSM)
#   2. Offline encrypted USB drive
#   3. Secure cloud storage (encrypted at rest)
# NEVER store unencrypted staking keys in cloud storage
```

### 1.3 Chain Data Backup

```bash
# On each validator node (requires brief maintenance window or snapshot)
# AvalancheGo data directory is typically at /var/lib/avalanchego

# Stop node (brief maintenance window)
sudo systemctl stop avalanchego

# Create snapshot
tar czf /backup/avalanchego-$(date +%Y%m%d).tar.gz /var/lib/avalanchego/

# Restart node
sudo systemctl start avalanchego

# Upload to secure offsite (use your org's preferred tool)
rclone copy /backup/avalanchego-$(date +%Y%m%d).tar.gz s3://primewave-backups/
```

---

## 2. Node Failure Scenarios

### Scenario A: Single Validator Node Failure

**Impact:** Reduced but functional consensus (5-of-5 → 4-of-5)
**Response Time:** 4 hours (non-critical if ≥ 3 validators online)

**Steps:**
1. Run `./scripts/health-check.sh` to confirm failure
2. Attempt to restart: `ssh validator-X 'sudo systemctl restart avalanchego'`
3. If hardware failure: proceed to Node Replacement (`./scripts/node-replacement.sh`)
4. Monitor re-sync progress
5. Verify fee accrual resumes after re-sync

### Scenario B: Majority Validator Failure (3+ nodes)

**Impact:** Chain halted — no new blocks
**Response Time:** Immediate (P1 incident)

**Emergency Steps:**
1. Activate Emergency Response Team (EMS signers)
2. Identify root cause (hardware, network, software bug)
3. If software bug: assess if EMS emergency pause is needed
4. Bring validators back online in priority order
5. Verify chain resumes producing blocks
6. Run `./scripts/validate-production-genesis.sh` after recovery

### Scenario C: Keeper Failure

**Impact:** Validators may drift out of sync (fee vault vs. P-Chain state)
**Response Time:** 2 hours (P2 incident)

**Steps:**
1. Check keeper logs: `journalctl -u primewave-keeper -n 100`
2. Restart keeper: `systemctl restart primewave-keeper`
3. If keeper cannot restart: manually sync critical validators
   ```bash
   forge send $REGISTRY_ADDRESS "syncAll()" \
     --rpc-url $CHAIN_RPC_URL \
     --private-key $ANY_EOA_KEY
   ```
4. Fix root cause before re-enabling keeper

### Scenario D: Complete Node Replacement

See `./scripts/node-replacement.sh` for the full automated procedure.

**Critical precondition:** Old node MUST be stopped before starting new node. NEVER run two instances with the same `staker.key` — this can cause equivocation (slashable behavior).

---

## 3. Rebuild-from-Genesis Procedure

If all chain data is lost (catastrophic failure), the chain can be rebuilt from genesis. This is an extreme scenario — use only if all backup snapshots are also lost.

**Important:** Rebuild-from-genesis means re-syncing from block 0. This is slow (hours to days depending on chain length).

### Step 1: Prepare Genesis File

```bash
# Retrieve genesis from PRIMEWAVE_GENESIS_SPEC.md and genesis.json backup
# Verify chain ID and allocations match locked values
./scripts/validate-production-genesis.sh
```

### Step 2: Bootstrap First Validator

```bash
# Initialize with genesis
avalanchego \
  --network-id=primewavedev \
  --genesis-file=/etc/avalanchego/genesis.json \
  --staking-tls-cert-file=/var/lib/avalanchego/staking/staker.crt \
  --staking-tls-key-file=/var/lib/avalanchego/staking/staker.key
```

### Step 3: Bootstrap Remaining Validators

```bash
# Use bootstrap node as anchor
avalanchego \
  --network-id=primewavedev \
  --bootstrap-ids=$BOOTSTRAP_NODE_ID \
  --bootstrap-ips=$BOOTSTRAP_NODE_IP:9651 \
  --staking-tls-cert-file=./staker.crt \
  --staking-tls-key-file=./staker.key
```

### Step 4: Verify Chain State

After sync completes:
```bash
# Verify all contracts at expected addresses
./scripts/validate-production-genesis.sh

# Verify keeper is syncing
curl http://sentinel:8080/health
```

---

## 4. Emergency Governance Procedures

### EMS Pause (Emergency Multisig)

If a critical contract vulnerability is found:

```bash
# 3 of 5 EMS signers must submit and confirm the pause transaction
# Via Gnosis Safe or direct signature aggregation

# On PrimeWaveFeeDistributor:
cast send $FEE_DISTRIBUTOR_ADDRESS "pause()" \
  --private-key $EMS_SIGNER_1_KEY --rpc-url $CHAIN_RPC_URL

# Repeat with signer 2 and 3 until threshold (3) is met
# The EMS contract accumulates signatures and executes when threshold reached
```

### EMS Signer Rotation

See `docs/PRIMEWAVE_KEY_SECURITY_PROCEDURE.md` for the full procedure.

Summary:
1. Deploy `EmergencyMultisig` with new signer set
2. Via timelock (48h delay): call `setPauseController(newEms)` on each contract
3. After timelock delay expires: new EMS takes effect

---

## 5. Key Recovery Checklist

After any incident requiring key recovery:

- [ ] Incident documented with timeline
- [ ] Root cause identified
- [ ] Affected validators re-verified on-chain
- [ ] Keeper re-enabled and health confirmed
- [ ] Monitoring dashboards show recovery
- [ ] Fee accrual verified for all active validators
- [ ] EMS signers notified and confirmed availability
- [ ] Backup freshness verified (< 24h old)
- [ ] Post-mortem scheduled within 48h

---

## 6. Contact Tree

| Role | Responsibility | Response |
|------|---------------|----------|
| On-Call Ops | First responder | 15 min (P1), 2h (P2) |
| Protocol Admin | Governance actions | 1h (business hours) |
| EMS Signers (3-of-5) | Emergency pause/governance | 30 min (P1) |
| Infrastructure | Hardware/network | 30 min (P1) |

**Note:** Production contact details are stored offline in the emergency response binder, not in this repository.

---

## 7. References

- `scripts/node-replacement.sh` — Automated node replacement
- `scripts/health-check.sh` — Node health check
- `scripts/validate-production-genesis.sh` — Genesis validation
- `docs/PW-C11-MONITORING-AND-ALERTING.md` — Alert thresholds
- `docs/PW-C11-VALIDATOR-OPERATIONS.md` — Validator lifecycle
- `docs/PRIMEWAVE_KEY_SECURITY_PROCEDURE.md` — Key management
