# PW-C11: Production Infrastructure

**Sprint:** C11 — Production Infrastructure + Validator Keeper + Genesis Finalization
**Status:** COMPLETE (gate report: PW-C11-FINAL-REPORT.md)
**Date:** 2026-08-14

---

## 1. Network Topology

### 1.1 Node Roles

PrimeWave Chain operates with three distinct node roles in production:

| Role | Count | Public IP | Purpose |
|------|-------|-----------|---------|
| **Validator Node** | 5 (initial) | No (private) | Block production, consensus |
| **RPC Node** | 2+ | Yes (load-balanced) | External API, dApps, explorer |
| **Sentinel Node** | 1 | No (private) | Monitoring, alerting, keeper |

### 1.2 Network Separation

```
Internet
   │
   │  HTTPS/443
   ▼
[Load Balancer] ── TLS termination
   │
   │  HTTP/8545, WebSocket/8546
   ▼
[RPC Node 1] [RPC Node 2]         ← DMZ / public subnet
   │                │
   └──────┬─────────┘
          │  P2P/9651
          ▼
   [Private Subnet]
   [Validator Node 1 … 5]          ← validators: API port NOT exposed
   [Sentinel Node]
```

**Critical network rules:**
- Validator API port (9650) is bound to `127.0.0.1` only — never exposed publicly
- Validator P2P port (9651) is exposed to known peers only (allowlist by IP)
- RPC nodes do NOT hold staking keys
- Sentinel node runs the keeper service and monitoring stack

### 1.3 Hardware Specifications

**Validator Node (production minimum):**

| Component | Specification |
|-----------|--------------|
| CPU | 8 vCPU (Intel/AMD x86-64) |
| RAM | 32 GB ECC |
| Storage | 2 TB NVMe SSD (primary) + 1 TB backup |
| Network | 1 Gbps, dedicated |
| OS | Ubuntu 22.04 LTS |

**RPC Node (production minimum):**

| Component | Specification |
|-----------|--------------|
| CPU | 16 vCPU |
| RAM | 64 GB |
| Storage | 4 TB NVMe SSD (full archive) |
| Network | 10 Gbps |

**Sentinel Node:**

| Component | Specification |
|-----------|--------------|
| CPU | 4 vCPU |
| RAM | 8 GB |
| Storage | 500 GB SSD |
| Network | 1 Gbps |

---

## 2. Node Configuration

### 2.1 AvalancheGo Version

```
AvalancheGo: v1.14.2  [LOCKED — do not upgrade without full testnet rehearsal]
```

### 2.2 Chain Configuration

Each validator and RPC node requires a chain config at:
`$CHAIN_CONFIG_DIR/$BLOCKCHAIN_ID/config.json`

```json
{
  "pruning-enabled": false,
  "state-sync-enabled": false,
  "eth-apis": ["eth", "eth-filter", "net", "web3", "internal-eth"],
  "log-level": "info",
  "fee-cap": "1000000000",
  "allow-unprotected-txs": false
}
```

**Validators:** `eth-apis` should exclude `personal` and `admin`.
**RPC nodes:** May include `debug` for archive access.

### 2.3 Subnet Configuration

```json
{
  "validatorOnly": false,
  "allowedNodes": []
}
```

### 2.4 AvalancheGo Flags (Validators)

```bash
avalanchego \
  --network-id=primewavedev \
  --http-host=127.0.0.1 \
  --http-port=9650 \
  --staking-port=9651 \
  --api-keystore-enabled=false \
  --api-admin-enabled=false \
  --track-subnets=$PRIMEWAVE_SUBNET_ID
```

---

## 3. Dependency Version Lock

| Dependency | Version | Lock Reason |
|-----------|---------|-------------|
| AvalancheGo | v1.14.2 | ICM compatibility; tested and audited |
| ICM Relayer | icm-relayer-v1.7.5 (commit 40e1c89) | Warp message relay |
| OpenZeppelin | 5.6.1 | C00 contract compilation |
| Foundry | v1.7.1 | Test and deploy toolchain |
| Node.js (keeper) | 22 LTS | Keeper service runtime |
| ethers.js (keeper) | 6.x | Keeper chain interface |

---

## 4. Keeper Service

The validator sync keeper is a TypeScript service that:
1. Polls `PrimeWaveValidatorRegistry.managedCount()` every 30 seconds
2. For each managed validator, reads status from `ValidatorManager`
3. Calls `syncValidator(bytes32)` when status has changed (permissionless)
4. Calls `updateWeight(bytes32)` when weight has changed
5. Persists state to `keeper-state.json` for restart safety
6. Exposes `/health` endpoint at `:8080`
7. Exports Prometheus metrics at `:8080/metrics`

**Security:** The keeper account holds NO privileged role. `syncValidator()` and `updateWeight()` are permissionless on the contract. The keeper CANNOT alter validator truth — the ValidatorManager (P-Chain) is the sole authority.

### Keeper Deployment (Sentinel Node)

```bash
cd keeper/
cp .env.example .env
# Fill in all required env vars (see keeper/README.md)
pnpm install
pnpm build
pnpm start
```

**Required env vars:**
```
KEEPER_RPC_URL=http://127.0.0.1:9656/ext/bc/$BLOCKCHAIN_ID/rpc
KEEPER_CHAIN_ID=73571
KEEPER_REGISTRY_ADDRESS=0x...
KEEPER_VALIDATOR_MANAGER_ADDRESS=0x...
KEEPER_PRIVATE_KEY=0x...    # Low-value EOA, no special roles
KEEPER_POLL_INTERVAL_MS=30000
KEEPER_HEALTH_PORT=8080
```

---

## 5. Firewall Rules Summary

| Rule | Source | Destination | Port | Action |
|------|--------|-------------|------|--------|
| External RPC | Internet | RPC Node | 443 (HTTPS) | ALLOW |
| P2P (validators) | Known peers | Validator | 9651 | ALLOW |
| P2P (validators) | Validator | Known peers | 9651 | ALLOW |
| API (validators) | 127.0.0.1 only | Validator | 9650 | ALLOW |
| Keeper health | Sentinel | — | 8080 | ALLOW (internal) |
| All other inbound | Internet | Validator | Any | DENY |

---

## 6. Monitoring Stack

See `PW-C11-MONITORING-AND-ALERTING.md` for full Prometheus/Grafana design.

**Key metrics:**
- `primewave_keeper_pending_syncs` — syncs needing attention
- `primewave_keeper_sync_failures_total` — failed sync attempts
- `primewave_keeper_last_poll_timestamp_seconds` — staleness detection
- AvalancheGo built-in metrics via `/ext/metrics`

---

## 7. Scripts

| Script | Purpose |
|--------|---------|
| `scripts/start-validator.sh` | Start a validator node with correct flags |
| `scripts/health-check.sh` | Node + RPC + keeper liveness check |
| `scripts/validate-production-genesis.sh` | Verify genesis invariants on live chain |
| `scripts/node-replacement.sh` | Safe node replacement procedure |

---

## 8. References

- `docs/PW-C11-VALIDATOR-OPERATIONS.md` — Full validator lifecycle
- `docs/PW-C11-DISASTER-RECOVERY.md` — Backup and recovery
- `docs/PW-C11-MONITORING-AND-ALERTING.md` — Prometheus/Grafana
- `docs/PRIMEWAVE_KEY_SECURITY_PROCEDURE.md` — Key management
- `contracts/script/DeployProduction.s.sol` — Production deployment
- `keeper/` — Keeper service source
