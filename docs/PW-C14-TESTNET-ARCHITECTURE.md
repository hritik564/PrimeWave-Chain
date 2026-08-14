# PW-C14: Testnet Architecture
**Sprint:** PW-C14 — Public Testnet + Deployment Rehearsal
**Status:** IN PROGRESS
**Environment:** TESTNET ONLY — Chain ID 77777

---

## 1. Overview

PW-C14 moves PrimeWave Chain from local development validation to a real public testnet rehearsal. The testnet proves the deployment and operational model before mainnet. Every component is labeled **TESTNET**.

---

## 2. Testnet Chain Identity

| Parameter | Value | Notes |
|---|---|---|
| Chain Name | PrimeWave Testnet | |
| Chain ID (EVM) | **77777** | Verify on chainlist.org before launch |
| Blockchain ID | TBD — generated at subnet creation | Fuji P-Chain transaction |
| Subnet ID | TBD — generated at subnet creation | Fuji P-Chain transaction |
| Network | Avalanche Fuji (testnet) | |
| Native Token | PW (TESTNET) | |
| Total Supply | 100,000,000 PW (fixed) | No inflation |
| AvalancheGo | v1.14.2 (pinned) | |
| Subnet-EVM | v1.14.2 (pinned) | |
| ICM Relayer | icm-relayer-v1.7.5 (commit 40e1c89) | |

**Why 77777:** The genesis spec document explicitly suggests 77777 as a candidate testnet ID ("e.g., 77777 or similar"). The number is clearly distinct from the dev ID (73571) and the mainnet ID (TBD). **Verify uniqueness on chainlist.org before finalizing the genesis.**

---

## 3. Node Topology

```
Internet
    │  HTTPS/443
    ▼
[Cloudflare / Load Balancer]
    │
    ├── rpc.primewave-testnet.example.com  (JSON-RPC + WebSocket)
    │       ↓
    │   [RPC Node 1]  [RPC Node 2]        ← DMZ / public subnet
    │       │              │
    │       └──────┬───────┘
    │              │ P2P/9651
    │              ▼
    │   [Private Subnet]
    │   [Validator 1] [Validator 2] [Validator 3]
    │   [Validator 4] [Validator 5]
    │
    ├── testnet.pwcscan.example.com        (PWCScan Explorer)
    │       ↓
    │   [Explorer Host]
    │       ├── PWCScan (nginx + static Vite build)
    │       └── C12 Indexer (port 4000, internal)
    │
    └── [Sentinel / Monitoring Node]
            ├── Keeper service
            ├── Prometheus
            ├── Grafana
            └── Alertmanager
```

### 3.1 Node Roles

| Role | Count | Public IP | Staking Keys | Purpose |
|---|---|---|---|---|
| Validator | 5 | No (private) | Yes | Block production, consensus |
| RPC Node | 1–2 | Yes (load-balanced) | No | Public JSON-RPC / WebSocket |
| Explorer Host | 1 | Yes (HTTPS only) | No | PWCScan + Indexer |
| Sentinel | 1 | No (internal) | No | Keeper + monitoring |

> **Testnet constraint:** The C14 rehearsal targets 5 validators (vs 15 at mainnet). If independent machines are unavailable, the spec requires documenting the actual topology and limiting to what infrastructure allows — never simulating validators that don't exist.

---

## 4. Testnet Infrastructure Stack

| Component | Version | Location | Port(s) |
|---|---|---|---|
| AvalancheGo | v1.14.2 | All nodes | 9650 (API, private), 9651 (P2P) |
| Subnet-EVM plugin | v1.14.2 | All nodes | — |
| ICM Relayer | icm-relayer-v1.7.5 | Sentinel | Internal |
| C12 Indexer | C12 (from this repo) | Explorer Host | 4000 (private) |
| C13 PWCScan | C13 (from this repo) | Explorer Host | 443 (via nginx) |
| C11 Keeper | C11 (from this repo) | Sentinel | 8080 (health, internal) |
| PostgreSQL | 16.x | Explorer Host | 5432 (private only) |
| Prometheus | 2.x | Sentinel | 9090 (internal) |
| Grafana | 10.x | Sentinel | 3000 (internal) |
| Alertmanager | 0.26.x | Sentinel | 9093 (internal) |
| nginx | 1.24.x | RPC Node, Explorer | 80, 443 |

---

## 5. Security Architecture

### 5.1 Network Separation

- Validator API (port 9650) bound to `127.0.0.1` only — never public
- Validator P2P (port 9651) whitelisted to known peer IPs only
- PostgreSQL bound to `127.0.0.1` — never public
- Keeper runs on sentinel (internal network only)
- Only nginx (ports 80/443) and AvalancheGo P2P (9651) are internet-facing

### 5.2 TLS

All public endpoints use Let's Encrypt certificates with auto-renewal via certbot.

### 5.3 Keys

| Key Type | Generation | Storage | Notes |
|---|---|---|---|
| Validator NodeID + BLS | avalanchego (at startup) | Node-local, encrypted | Auto-generated |
| Testnet deployer | `cast wallet new` | Encrypted file, not in Git | Testnet only |
| Testnet EMS signers (5) | `cast wallet new` | Encrypted files | Testnet only |
| Testnet keeper signer | `cast wallet new` | Encrypted file, keeper env | Testnet only |
| Mainnet governance keys | HARDWARE WALLET ONLY | Not generated in C14 | Future ceremony |

---

## 6. Software Configuration Files

| File | Purpose |
|---|---|
| `config/testnet/genesis-template.json` | Testnet genesis template with hex allocation values |
| `config/testnet/chain-config.json` | Subnet-EVM chain configuration |
| `config/testnet/node-config.json` | AvalancheGo node configuration template |
| `config/testnet/allocations.md` | Testnet allocation documentation |
| `deploy/testnet/systemd/` | Systemd service files for all components |
| `deploy/testnet/nginx/` | nginx configs for RPC and explorer |
| `deploy/testnet/prometheus/` | Prometheus + alert rules |
| `deploy/testnet/env/*.env.template` | Environment variable templates |
| `scripts/testnet/` | Operational scripts |

---

## 7. Protocol Contract Addresses (Testnet)

Addresses are generated during testnet deployment via `DeployTestnet.s.sol`. They are saved to `local-data/testnet-deployed-contracts.env`. The testnet genesis specifies `rewardManagerConfig.rewardAddress` = FeeDistributor address, which requires a two-step deployment (deploy contracts first using computed addresses, then finalize genesis).

Alternatively: Pre-compute contract addresses using `CREATE2` or nonce-based derivation, embed in genesis, then deploy to match.

> **Addresses will be recorded in `docs/PW-C14-TESTNET-DEPLOYMENT-MANIFEST.md` after deployment.**

---

## 8. Infrastructure as Code

All node configuration is reproducible from this repository:

```bash
# On a fresh Ubuntu 22.04 server:
NODE_ROLE=validator \
TESTNET_SUBNET_ID=<subnet-id> \
TESTNET_BLOCKCHAIN_ID=<blockchain-id> \
bash scripts/testnet/setup-testnet-node.sh
```

Full deployment procedure: `docs/PW-C14-DEPLOYMENT-RUNBOOK.md`.

---

## 9. Infrastructure Constraint (Replit Development Environment)

PW-C14 architecture is designed for real external cloud infrastructure. The Replit workspace provides:
- Local development validation (dev chain ID 73571)
- Complete infrastructure configurations, scripts, and documentation
- Genesis template ready for deployment
- All software components (indexer, keeper, PWCScan) ready for testnet deployment

Real testnet activation requires:
1. Cloud servers provisioned (Ubuntu 22.04, specs in this doc)
2. Real Fuji P-Chain AVAX for subnet/chain creation
3. DNS records configured
4. TLS certificates issued
5. Testnet key ceremony executed

**These steps are documented in `docs/PW-C14-DEPLOYMENT-RUNBOOK.md` and ready to execute when external infrastructure is available.**
