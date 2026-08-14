# PW-C15 — INFRASTRUCTURE BUDGET AND TOPOLOGY

**Sprint:** PW-C15 — Pre-Infrastructure Readiness Pass
**Status:** PLANNING DOCUMENT ONLY — do not purchase anything
**Date Created:** 2026-08-15

This document provides three topology options with cost estimates.
Costs are approximate as of 2026-08-15 and should be verified before ordering.

---

## TOPOLOGY OPTIONS SUMMARY

| Topology | Validators | Total Servers | Est. Monthly Cost | Use Case |
|---|---|---|---|---|
| MINIMUM | 3 | 5 | ~€150/month | Functional testnet; proves all protocol behavior |
| RECOMMENDED | 5 | 8 | ~€280/month | Proves validator failure/recovery; better resilience |
| FULL (15-VALIDATOR) | 15 | 18 | ~€460/month | Intended production-representative topology |

---

## TOPOLOGY 1 — MINIMUM VIABLE TESTNET (3 VALIDATORS)

**Purpose:** Prove all protocol behavior with minimum resources.
**Can prove:** Multi-node consensus, RPC, keeper, indexer, PWCScan, ICM, 1 validator failure.
**Cannot prove:** 5+-node failure scenarios, production-scale churn.

### Server Layout

| # | Role | vCPU | RAM | Storage | Purpose |
|---|---|---|---|---|---|
| 1 | validator-01 | 4 | 8 GB | 200 GB SSD | AvalancheGo + subnet-evm (bootstrap node) |
| 2 | validator-02 | 4 | 8 GB | 200 GB SSD | AvalancheGo + subnet-evm |
| 3 | validator-03 | 4 | 8 GB | 200 GB SSD | AvalancheGo + subnet-evm |
| 4 | infra-01 | 4 | 16 GB | 500 GB SSD | nginx RPC + Indexer + Keeper + PWCScan + PostgreSQL |
| 5 | monitoring-01 | 2 | 4 GB | 80 GB SSD | Prometheus + Grafana |
| | **Total** | **18** | **44 GB** | **1,180 GB** | |

### Hetzner Cloud Estimate

| Server type | Count | Unit price | Subtotal |
|---|---|---|---|
| CX32 (4 vCPU / 8 GB / 80 GB SSD) | 4 | €12/mo | €48 |
| SSD Volume 200 GB (attached) | 3 (validators) | €8/mo each | €24 |
| SSD Volume 500 GB (infra) | 1 | €20/mo | €20 |
| CPX21 (3 vCPU / 4 GB / 80 GB) | 1 (monitoring) | €7/mo | €7 |
| IPv4 (reserved per server) | 5 | €3.80/mo each | €19 |
| Bandwidth | included | — | €0 |
| **Estimated monthly total** | | | **~€118/month** |

### AWS Equivalent

| Instance | Count | Type | ~USD/month |
|---|---|---|---|
| EC2 validator | 3 | t3.xlarge (4 vCPU / 16 GB) | $120 each → $360 |
| EC2 infra | 1 | m5.xlarge (4 vCPU / 16 GB) | $140 |
| EC2 monitoring | 1 | t3.medium (2 vCPU / 4 GB) | $30 |
| EBS gp3 200 GB × 3 | 3 | gp3 | $48 |
| EBS gp3 500 GB × 1 | 1 | gp3 | $40 |
| **Estimated monthly total** | | | **~$618/month** |

### Notes on Minimum Topology

- 3 validators is the absolute minimum for BFT consensus (f=1, tolerates 1 failure)
- With 3 validators, losing 1 halts finality — recovery must be fast
- This topology is **NOT production-equivalent** — DO NOT call it production readiness
- Suitable for: all C15 battle test items except large-scale churn and production-scale load

---

## TOPOLOGY 2 — RECOMMENDED TESTNET (5 VALIDATORS)

**Purpose:** More realistic fault tolerance with dedicated RPC node.
**Can prove:** Everything in MINIMUM + 2-validator failure, higher RPC throughput, dedicated public endpoint.

### Server Layout

| # | Role | vCPU | RAM | Storage | Purpose |
|---|---|---|---|---|---|
| 1 | validator-01 | 4 | 8 GB | 200 GB SSD | Bootstrap validator |
| 2 | validator-02 | 4 | 8 GB | 200 GB SSD | Validator |
| 3 | validator-03 | 4 | 8 GB | 200 GB SSD | Validator |
| 4 | validator-04 | 4 | 8 GB | 200 GB SSD | Validator |
| 5 | validator-05 | 4 | 8 GB | 200 GB SSD | Validator |
| 6 | rpc-01 | 4 | 16 GB | 500 GB SSD | Dedicated public RPC/archive node + nginx |
| 7 | infra-01 | 4 | 16 GB | 500 GB SSD | Indexer + Keeper + PWCScan + PostgreSQL |
| 8 | monitoring-01 | 2 | 4 GB | 80 GB SSD | Prometheus + Grafana + Alertmanager |
| | **Total** | **30** | **76 GB** | **2,180 GB** | |

### Hetzner Cloud Estimate

| Server type | Count | Unit price | Subtotal |
|---|---|---|---|
| CX32 (4 vCPU / 8 GB) | 5 (validators) | €12/mo | €60 |
| SSD Volume 200 GB (validators) | 5 | €8/mo each | €40 |
| CX42 (8 vCPU / 16 GB / 240 GB) | 2 (rpc + infra) | €25/mo each | €50 |
| SSD Volume 500 GB (rpc, infra) | 2 | €20/mo each | €40 |
| CPX21 (monitoring) | 1 | €7/mo | €7 |
| IPv4 (reserved) | 8 | €3.80/mo each | €30 |
| **Estimated monthly total** | | | **~€227/month** |

---

## TOPOLOGY 3 — FULL 15-VALIDATOR TESTNET

**Purpose:** Production-representative topology for launch readiness.
**Can prove:** All C15 items, large-scale churn, HA failover, realistic soak tests.
**Note:** This is NOT equivalent to mainnet — mainnet will have many more independent validators from different operators globally.

### Server Layout

| # | Role | vCPU | RAM | Storage | Count | Purpose |
|---|---|---|---|---|---|---|
| 1–15 | validator-01..15 | 4 | 8 GB | 300 GB SSD | 15 | AvalancheGo validators |
| 16 | rpc-01 | 8 | 16 GB | 1 TB SSD | 1 | Public RPC + nginx (HA candidate) |
| 17 | infra-01 | 8 | 16 GB | 500 GB SSD | 1 | Indexer + Keeper + PWCScan + PostgreSQL |
| 18 | monitoring-01 | 4 | 8 GB | 200 GB SSD | 1 | Prometheus + Grafana + Alertmanager |
| | **Total** | **84** | **168 GB** | **6.2 TB** | **18** | |

### Hetzner Cloud Estimate

| Server type | Count | Unit price | Subtotal |
|---|---|---|---|
| CX32 (4 vCPU / 8 GB) | 15 (validators) | €12/mo | €180 |
| SSD Volume 300 GB (validators) | 15 | €12/mo each | €180 |
| CX52 (16 vCPU / 32 GB) | 2 (rpc + infra) | €42/mo each | €84 |
| SSD Volume 1 TB (rpc) | 1 | €40/mo | €40 |
| SSD Volume 500 GB (infra) | 1 | €20/mo | €20 |
| CPX31 (4 vCPU / 8 GB) | 1 (monitoring) | €17/mo | €17 |
| IPv4 reserved | 18 | €3.80/mo each | €68 |
| **Estimated monthly total** | | | **~€589/month** |

### AWS Equivalent (Full Topology)

| Component | Instance | Count | ~USD/month |
|---|---|---|---|
| Validators | t3.xlarge | 15 | $1,800 |
| RPC node | m5.2xlarge | 1 | $280 |
| Infra | m5.xlarge | 1 | $140 |
| Monitoring | t3.large | 1 | $60 |
| EBS gp3 volumes | Various | 18 | $600 |
| Data transfer | — | — | ~$100 |
| **Estimated monthly total** | | | **~$2,980/month** |

---

## RECOMMENDATION

### Recommended Path

**START WITH TOPOLOGY 1 (MINIMUM VIABLE — 3 VALIDATORS)**

Rationale:
- All C15 protocol behavior can be proven with 3 validators
- Costs ~€118/month vs €589/month for full topology
- Allows full C15 gate completion without committing to large infra budget
- Leadership can make C16 decision based on protocol correctness, not infra cost
- Scaling to 5 or 15 validators is an additive operation — do not rebuild

**Scale to TOPOLOGY 2 (RECOMMENDED) after C16 is open:**
- Add validator-04 and validator-05 (2 new servers)
- Add rpc-01 (move nginx from infra-01 to dedicated node)
- Total incremental cost: ~+€109/month

**Scale to TOPOLOGY 3 (FULL) approaching mainnet launch:**
- Add validator-06..15 (10 new servers)
- Upsize rpc-01 and infra-01
- Total incremental cost: ~+€362/month

---

## WHAT MINIMUM TOPOLOGY CAN PROVE

| C15 Category | Provable with 3V? | Notes |
|---|---|---|
| Multi-node consensus | ✅ YES | 3 nodes required for BFT |
| Validator failure | ✅ YES | Kill validator-01; verify finality continues |
| RPC separation | ✅ YES | infra-01 acts as RPC proxy |
| Keeper | ✅ YES | Runs on infra-01 |
| Indexer | ✅ YES | Runs on infra-01 |
| PWCScan | ✅ YES | Runs on infra-01 |
| ICM/Warp | ✅ YES | Cross-chain messages work with 3 validators |
| Fee distribution (70/20/10) | ✅ YES | Protocol-level, validator count-independent |
| RewardVault (15M cap) | ✅ YES | Protocol-level |
| Governance (EMS + Timelock) | ✅ YES | Protocol-level |
| 2+ validator failures simultaneously | ❌ NO | Need 5+ validators |
| Production-scale load (>100 TPS) | ⚠️ LIMITED | Network throughput limited with 3 nodes |
| 14-day unbond (real-time) | ❌ NO | Topology-independent; calendar time required |

---

## DO NOT CALL MINIMUM TOPOLOGY EQUIVALENT TO 15-VALIDATOR PRODUCTION

The 3-validator minimum topology is explicitly NOT production-equivalent.
Its purpose is to prove all C15 gate items to the minimum bar required to open C16.
Mainnet launch requires 15+ independently operated validators from multiple organizations.
