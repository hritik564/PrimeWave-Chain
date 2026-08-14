# PrimeWave Chain — Infrastructure Specification
**Updated: PW-C12 | Status: DESIGN DOCUMENT — NOT FOR PRODUCTION**

---

## 1. Overview

This document specifies the infrastructure architecture for PrimeWave Chain. The guiding principle is:

**SECURITY + COMPLETENESS + LOW OPERATING COST**

Infrastructure decisions favor open-source, proven Avalanche tooling, managed services where cost-justified, and automation over manual operations.

---

## 2. Infrastructure Components

### 2.1 Required Components

| Component | Purpose | Phase |
|---|---|---|
| Mainnet validator nodes (15) | Block production and validation | Mainnet |
| Testnet validator nodes (3–5) | Pre-mainnet testing | Testnet |
| Public RPC nodes | JSON-RPC and WebSocket access | Both |
| Archive/indexer node | Full historical state for indexer | Both |
| Block explorer | Transaction and address lookup | Both |
| Indexer service | Event indexing for PrimeWave Dex | Both |
| Monitoring | Node health, block production, alerts | Both |
| Alerting | PagerDuty/Opsgenie for critical events | Mainnet |
| Backups | Node state and database backups | Both |
| Disaster recovery | Documented recovery procedures | Mainnet |
| Infrastructure automation | Terraform / Ansible | Both |

---

## 3. Node Architecture

### 3.1 Validator Nodes

- **Count:** 15 mainnet validators, 3–5 testnet validators
- **Software:** AvalancheGo (version locked at testnet launch) + Subnet-EVM plugin
- **Hosting:** Mix of cloud providers for resilience (AWS, GCP, Azure — no single-provider dependency)
- **Spec (preliminary — validate on testnet):**
  - CPU: 8 vCPU minimum
  - RAM: 16 GB minimum
  - Storage: 500 GB SSD NVMe (NVMe strongly preferred for Avalanche)
  - Network: 1 Gbps symmetric
  - OS: Ubuntu 22.04 LTS

- **Security:**
  - No public SSH (use bastion host or VPN-only access)
  - Validator P2P port exposed; RPC ports NOT exposed publicly from validator nodes
  - Validator keys stored offline / in HSM; loaded at node startup only
  - Firewall: allow only Avalanche P2P port (9651 default) inbound

### 3.2 Public RPC Nodes

- **Count:** Minimum 2 per region (for HA)
- **Purpose:** Handle JSON-RPC and WebSocket requests from wallets, applications, indexers
- **Spec:** Same as validator, but no staking keys present
- **Rate limiting:** Required on public endpoints (nginx/Cloudflare)
- **TLS:** Required for all public endpoints
- **Load balancer:** nginx or cloud LB in front of RPC node pool

### 3.3 Archive / Indexer Node

- **Purpose:** Full historical state access for the indexer service
- **Config:** AvalancheGo with `--state-sync-enabled=false` (full archive mode)
- **Storage:** Larger disk (1 TB+ for long-term archive)
- **Not a validator:** No signing keys

---

## 4. Block Explorer

**Recommended:** Deploy an open-source EVM explorer. Options:

| Explorer | License | Notes |
|---|---|---|
| Blockscout | GPL / AGPL | Full-featured, actively maintained, EVM-compatible |
| Otterscan | MIT | Lightweight, fast, good for smaller chains |
| Expedition | MIT | Simple, minimal dependencies |

**Recommendation: Blockscout** — most feature-complete, supports custom chain configurations, well-maintained, used by many EVM L1s.

Blockscout requires:
- PostgreSQL database
- A connected archive RPC node
- NGINX reverse proxy
- Optional: Redis for caching

---

## 5. Indexer Service

The indexer is the backend for PrimeWave Dex market data. See `PRIMEWAVE_MARKET_DATA_INTERFACE.md`.

- Connects to PrimeWave Chain archive node via WebSocket
- Subscribes to `Swap`, `Sync`, `Mint`, `Burn` events from PWSwapPair
- Stores processed data in TimescaleDB (PostgreSQL with time-series extension)
- Exposes REST + WebSocket API for PrimeWave Dex frontend
- Can replay from block 0 for resync (chain is source of truth)

---

## 6. Monitoring and Alerting

### 6.1 Metrics Collection

| Tool | Role |
|---|---|
| Prometheus | Metrics scraping from AvalancheGo nodes |
| Grafana | Dashboards for chain health, validator performance |
| Node Exporter | System-level metrics (CPU, RAM, disk, network) |

AvalancheGo exposes Prometheus metrics on port 9090 (default). Key metrics to monitor:

| Metric | Alert Threshold |
|---|---|
| Block production rate | < 0.4 blocks/sec for >60 seconds |
| Validator uptime | < 80% over 24h rolling window |
| Peer count (per node) | < 5 peers |
| Mempool size | > 10,000 pending transactions |
| Disk usage | > 80% |
| RPC response time | > 2 seconds p99 |

### 6.2 Alerting

- **Tool:** PagerDuty or Opsgenie (managed, low maintenance)
- **Channels:** PagerDuty → on-call engineer; Slack for non-critical alerts
- **Critical alerts (immediate response):**
  - Chain halt (no blocks for >30 seconds)
  - Validator offline
  - RPC node failure
  - Disk > 90% full
  - Unusual PWUSD mint event (large amount)
  - Credential rotation due alert

---

## 7. Backups and Disaster Recovery

### 7.1 Node State Backups

- AvalancheGo node data backed up daily to object storage (AWS S3 or equivalent)
- Retention: 30 days minimum
- Backup verified monthly (restore test)

### 7.2 Database Backups

- Blockscout PostgreSQL: daily automated backup
- Indexer TimescaleDB: daily automated backup
- Backups encrypted at rest
- Offsite backup copy (different cloud provider)

### 7.3 Disaster Recovery

| Scenario | Recovery Target | Procedure |
|---|---|---|
| Single validator node failure | < 1 hour | Restart node; re-sync from peers |
| Data center outage (single region) | < 4 hours | Failover to nodes in other regions |
| Full indexer database loss | < 24 hours | Restore from backup OR full resync from chain |
| Blockscout database corruption | < 4 hours | Restore from backup |

DR procedures must be documented and tested on testnet before mainnet launch.

---

## 8. Infrastructure Automation

### 8.1 Recommended Tooling

| Tool | Purpose |
|---|---|
| Terraform | Cloud infrastructure provisioning (VMs, networking, DNS) |
| Ansible | Node configuration management (AvalancheGo setup, Subnet-EVM plugin) |
| GitHub Actions | CI/CD for contract deployments and infrastructure updates |
| Docker | Container deployment for indexer, explorer services |
| Docker Compose / Kubernetes | Container orchestration (Compose for small scale; K8s if needed later) |

### 8.2 Infrastructure as Code

All infrastructure MUST be codified in Terraform:
- No manual cloud console provisioning for production
- Testnet infrastructure mirrors mainnet in architecture (different scale)
- Mainnet provisioned from the same Terraform codebase as testnet, with environment variables

---

## 9. Cost Estimation (Preliminary)

> These are rough estimates. Actual costs depend on cloud provider, region, and negotiated pricing.

| Component | Est. Monthly Cost |
|---|---|
| 15 validator nodes (8 vCPU, 16GB, 500GB SSD) | ~$2,000–4,000 |
| 4 RPC nodes | ~$400–800 |
| 1 Archive/indexer node | ~$200–400 |
| Load balancers + networking | ~$100–200 |
| Blockscout (DB + server) | ~$100–200 |
| Monitoring (Grafana Cloud) | ~$50–100 |
| Alerting (PagerDuty) | ~$50–100 |
| Backups / object storage | ~$50–100 |
| **Estimated Total** | **~$3,000–6,000/month** |

Cost optimization strategies:
- Negotiate reserved instances (1–3 year) for validator nodes (30–60% discount)
- Use Hetzner or OVH for some nodes (significantly cheaper than AWS/GCP)
- Consolidate indexer and explorer on shared infrastructure where possible
- Use managed PostgreSQL (e.g., Supabase, Neon) instead of self-hosted for non-critical databases

---

## 9B. Confirmed Dependency Registry (OQ-001 Resolved)

The following table documents the current official Avalanche dependencies confirmed for PrimeWave Chain:

| Component | Official Repository | Status | Notes |
|---|---|---|---|
| Validator Manager Contracts (PoAManager, StakingManager, etc.) | `ava-labs/icm-services` tag `icm-relayer-v1.7.5` / commit `40e1c89` | ✅ **Pinned** | Successor to archived `icm-contracts`. Released Jan 26, 2026. Contracts in `icm-contracts/` subdir. Solidity 0.8.30. Compatible with AvalancheGo v1.14.0–v1.14.2. |
| AvalancheGo | `ava-labs/avalanchego` | ✅ Active | v1.14.2 current. Pin at testnet. |
| Subnet-EVM | ⛔ **ARCHIVED Dec 16, 2025** — merged into AvalancheGo v1.14.1 | ✅ N/A | Not a separate dependency. EVM included in AvalancheGo ≥ v1.14.1. DO NOT reference `ava-labs/subnet-evm`. |
| Avalanche CLI | `ava-labs/avalanche-cli` | ✅ Active | Used for L1 create/convert. Pin at testnet. |
| OpenZeppelin Contracts | `OpenZeppelin/openzeppelin-contracts` **v5.6.1** | ✅ **Pinned** | MIT. Latest stable (npm `latest`, Feb 27, 2026). Pin in Foundry config. |
| OpenZeppelin Upgradeable | `OpenZeppelin/openzeppelin-contracts-upgradeable` **v5.6.1** | ✅ **Pinned** | MIT. Synchronized with OZ Contracts v5.6.1. npm `latest`. |
| Foundry | `foundry-rs/foundry` | ✅ Active | Pin commit hash in CI. |

**Archive warnings:**
- `ava-labs/icm-contracts` (archived Dec 3, 2025) must NOT be used. Use `ava-labs/icm-services` exclusively.
- `ava-labs/subnet-evm` (archived Dec 16, 2025) must NOT be used. EVM is now part of AvalancheGo ≥ v1.14.1.

**License review required:** The `LicenseRef-Ecosystem` license on `icm-services` contracts may require a commercial arrangement with Ava Labs. Legal review needed before mainnet deployment.

---

## 10. Testnet Requirements

Before mainnet launch, testnet MUST validate:

- [ ] AvalancheGo + Subnet-EVM deployment and configuration
- [ ] ValidatorManager contract deployment and validator registration
- [ ] Genesis file correctness (all allocations sum to 100M PW)
- [ ] NativeMinter NOT accessible
- [ ] RewardVault deployment and distribution function
- [ ] FeeDistributor 70/20/10 split (verify with test transactions)
- [ ] PWUSD contract deployment and mint/burn
- [ ] Block time ~2 seconds achieved
- [ ] Gas parameters calibrated for target usage
- [ ] RPC endpoints operational
- [ ] Blockscout explorer operational
- [ ] Monitoring and alerting operational
- [ ] Backup and restore procedure tested

---

## 11. Mainnet Prerequisites

Mainnet launch REQUIRES:

- [ ] All testnet acceptance criteria met
- [ ] Smart contracts audited by reputable firm
- [ ] Genesis file triple-reviewed by independent parties
- [ ] Validator key generation completed offline (≥3 witnesses)
- [ ] Genesis hash documented and published
- [ ] Runbooks and DR procedures documented and tested
- [ ] Emergency multisig established and tested
- [ ] Treasury multisig established and tested
- [ ] Monitoring and alerting live and tested
- [ ] Public-facing RPC and explorer operational

---

*This document is a PW-C00 design specification. No production deployment has occurred.*

---

## 10. Validator Keeper Service (C11)

### 10.1 Purpose

The Validator Keeper is a TypeScript off-chain service that monitors the `PrimeWaveValidatorRegistry` and issues `syncValidator()` / `updateWeight()` transactions whenever validator state on-chain requires synchronization.

The keeper requires **no privileged role** — `syncValidator()` and `updateWeight()` are permissionless functions on the registry.

### 10.2 Deployment

**Runtime:** Node.js 22+, single process per chain  
**Location:** `keeper/` directory (compiled TypeScript → CommonJS)  
**State:** JSON file at `$STATE_FILE_PATH` (atomic write with tmp+rename)  
**Health:** HTTP `GET /health` at `$HEALTH_PORT` (default 8080)  
**Metrics:** Prometheus `GET /metrics` at `$HEALTH_PORT/metrics`

```bash
cd keeper
npm install
npm run build
KEEPER_RPC_URL=http://localhost:9650/ext/bc/<chain-id>/rpc \
KEEPER_CHAIN_ID=73571 \
KEEPER_REGISTRY_ADDRESS=<registry-address> \
KEEPER_VALIDATOR_MANAGER=<vm-address> \
KEEPER_PRIVATE_KEY=<keeper-eoa-key> \
npm start
```

See `docs/PW-C11-KEEPER-SPEC.md` for the full configuration reference, retry policy, and operational runbook.

### 10.3 Network Topology Update (C11)

| Node Role | Count | Purpose |
|---|---|---|
| Validator nodes | 15 | Block production (private network) |
| Public RPC nodes | 3+ | External access (round-robin LB) |
| Keeper host | 1 | Validator sync service (internal) |
| Monitoring host | 1 | Prometheus + Grafana + Alertmanager |
| Archive node | 1 | Historical queries + indexer |

Keeper is deployed on a **separate host from validators** with internal network access to the RPC port of one validator or the public RPC nodes.

---

---

## 11. Indexer Service (C12)

The Indexer is a TypeScript/Node.js service that indexes PrimeWave Chain into PostgreSQL and exposes a read-only REST API for PWCScan (C13) and other consumers.

### 11.1 Architecture

```
PrimeWave Chain (JSON-RPC)
    │
    ▼
IndexerEngine (poll-based, 2s interval)
    │  Writes blocks, txs, receipts, logs, decoded events, domain state
    ▼
PostgreSQL (17-table schema)
    │
    ▼
REST API (read-only, 20+ GET endpoints, port INDEXER_API_PORT)
    │
    ▼
C13 PWCScan
```

### 11.2 Deployment

**Runtime:** Node.js 22+, single process  
**Location:** `indexer/` directory (standalone npm package)  
**Database:** PostgreSQL (separate instance recommended)  
**Health:** `GET /health` on `INDEXER_API_PORT` (default 4000)

```bash
cd indexer
npm install
INDEXER_RPC_URL=http://localhost:9650/ext/bc/<chain-id>/rpc \
INDEXER_CHAIN_ID=73571 \
INDEXER_DB_URL=postgresql://... \
ADDR_FEE_DISTRIBUTOR=<address> \
ADDR_REWARD_VAULT=<address> \
# ... remaining ADDR_* vars
npm start
```

### 11.3 Key Properties

- **Idempotent:** Running the same block range twice produces identical results (ON CONFLICT DO NOTHING)
- **Restart-safe:** `sync_state.latest_block` updated atomically inside each block's DB transaction
- **No precision loss:** All amounts stored as decimal strings; BigInt-safe
- **13 integrity checks:** Run via `ts-node src/integrity/runner.ts`
- **Reindex tool:** `bin/reindex.ts --from N --to M [--verify]` (requires `PRIMEWAVE_ALLOW_REINDEX=yes`)

### 11.4 Network Topology Update (C12)

| Node Role | Count | Purpose |
|---|---|---|
| Validator nodes | 15 | Block production (private network) |
| Public RPC nodes | 3+ | External access (round-robin LB) |
| Keeper host | 1 | Validator sync service (internal) |
| Indexer host | 1 | Indexer + API (internal network, archive node access) |
| Monitoring host | 1 | Prometheus + Grafana + Alertmanager |
| Archive node | 1 | Full historical state — indexer connects here |

See `docs/PW-C12-INDEXER-SPEC.md` for the full configuration reference and `docs/PW-C12-API-SPEC.md` for the complete API reference.

---

*Updated C12: Indexer service topology and deployment section added.*
