# PW-C15 — TESTNET DEPLOYMENT VARIABLE MANIFEST

**Sprint:** PW-C15 — Pre-Infrastructure Readiness Pass
**Status:** READY — fill in values as each phase completes
**Date Created:** 2026-08-15

NEVER put actual private keys, passwords, or seed phrases into this document.
This file is committed to Git. It documents only public identifiers and metadata.

---

## LEGEND

| Field | Meaning |
|---|---|
| SOURCE | Where this value is generated or obtained |
| WHEN | At which phase this value becomes available |
| WHO | Who is responsible for providing it |
| SECRET | YES = never commit; NO = safe to commit |
| STORED | Where the value is kept |
| USED BY | Which components need this value |

---

## 1. CHAIN IDENTITY

### 1.1 — Dev Chain ID
| Field | Value |
|---|---|
| Value | `73571` |
| SOURCE | C02 genesis locked |
| WHEN | Fixed — never changes |
| WHO | Protocol Lead (locked) |
| SECRET | NO |
| STORED | `config/local/genesis-template.json` |
| USED BY | Local dev scripts, forge tests |

---

### 1.2 — Testnet Chain ID (EVM)
| Field | Value |
|---|---|
| Value | `77` |
| SOURCE | C14 decision (changed from 77777) |
| WHEN | Fixed — never changes |
| WHO | Protocol Lead (locked) |
| SECRET | NO |
| STORED | `config/testnet/genesis-template.json` · all testnet scripts and env files |
| USED BY | AvalancheGo genesis, DeployTestnet.s.sol, all testnet env templates |

---

### 1.3 — Testnet Chain ID (hex)
| Field | Value |
|---|---|
| Value | `0x4d` |
| SOURCE | hex(77) |
| WHEN | Fixed |
| WHO | Auto-derived |
| SECRET | NO |
| STORED | Documented here; used in health checks |
| USED BY | testnet-health-check.sh (HC-01), explorer UI |

---

### 1.4 — Fuji Network ID
| Field | Value |
|---|---|
| Value | `5` |
| SOURCE | Avalanche protocol constant |
| WHEN | Fixed |
| WHO | Avalanche (external) |
| SECRET | NO |
| STORED | Documented |
| USED BY | AvalancheGo `--network-id=fuji` |

---

### 1.5 — Mainnet Chain ID
| Field | Value |
|---|---|
| Value | **TBD** — requires leadership approval |
| SOURCE | chainid.network verification + leadership sign-off |
| WHEN | BEFORE mainnet deployment (not before C16) |
| WHO | Protocol Lead |
| SECRET | NO |
| STORED | TBD |
| USED BY | Mainnet genesis — NOT YET |

UNLOCKED CANDIDATES (verified available 2026-08-15, must re-verify before finalization):
`149 · 209 · 229 · 235 · 241`

---

## 2. FUJI P-CHAIN IDENTIFIERS

### 2.1 — Testnet Subnet ID
| Field | Value |
|---|---|
| Value | `__FILL_AFTER_PHASE_6__` |
| SOURCE | Fuji P-Chain CreateSubnetTx output |
| WHEN | Phase 6 (Fuji P-Chain deployment) |
| WHO | Infra operator |
| SECRET | NO |
| STORED | `docs/PW-C15-TESTNET-VARIABLE-MANIFEST.md` (here) · `/etc/primewave/testnet.env` on all nodes |
| USED BY | AvalancheGo `--track-subnets`, `node-config.json` |

---

### 2.2 — Testnet Blockchain ID
| Field | Value |
|---|---|
| Value | `__FILL_AFTER_PHASE_6__` |
| SOURCE | Fuji P-Chain CreateChainTx output |
| WHEN | Phase 6 (Fuji P-Chain deployment) |
| WHO | Infra operator |
| SECRET | NO |
| STORED | `docs/PW-C15-TESTNET-VARIABLE-MANIFEST.md` (here) · all env templates after substitution |
| USED BY | RPC URL path, keeper env, indexer env, AvalancheGo chain config path |

---

## 3. GENESIS

### 3.1 — Genesis File
| Field | Value |
|---|---|
| Value | `config/testnet/genesis.json` |
| SOURCE | Generated from `config/testnet/genesis-template.json` after ceremony address fill |
| WHEN | Phase 7 (Genesis) — after key ceremony |
| WHO | Protocol Lead + Infra operator |
| SECRET | NO |
| STORED | Repository (committed after ceremony); distributed to all validators |
| USED BY | AvalancheGo initial block; Fuji CreateChainTx |

---

### 3.2 — Genesis SHA256 Hash
| Field | Value |
|---|---|
| Value | `__FILL_AFTER_PHASE_7__` |
| SOURCE | `sha256sum config/testnet/genesis.json` |
| WHEN | Phase 7.3 |
| WHO | Protocol Lead |
| SECRET | NO |
| STORED | Here and in `docs/PW-C15-FINAL-REPORT.md` |
| USED BY | Cross-validator verification; audit log |

---

### 3.3 — Genesis Total Supply
| Field | Value |
|---|---|
| Value | `100,000,000 PW` exactly |
| SOURCE | Fixed in genesis template (verified) |
| WHEN | Fixed |
| WHO | Protocol Lead (locked) |
| SECRET | NO |
| STORED | `config/testnet/genesis-template.json` · `config/testnet/allocations.md` |
| USED BY | invariant checks (INV-G3) |

---

## 4. NETWORK ENDPOINTS

### 4.1 — Testnet Public RPC URL
| Field | Value |
|---|---|
| Value | `https://rpc.testnet.primewave.xyz/ext/bc/<BLOCKCHAIN_ID>/rpc` |
| SOURCE | Phase 13 (nginx deploy) — fill BLOCKCHAIN_ID after Phase 6 |
| WHEN | Phase 13 |
| WHO | Infra operator |
| SECRET | NO |
| STORED | `deploy/testnet/env/*.env.template` (after substitution) |
| USED BY | deploy-contracts.sh · testnet-health-check.sh · keeper · indexer · PWCScan |

---

### 4.2 — Testnet Public WebSocket URL
| Field | Value |
|---|---|
| Value | `wss://rpc.testnet.primewave.xyz/ext/bc/<BLOCKCHAIN_ID>/ws` |
| SOURCE | Phase 13 |
| WHEN | Phase 13 |
| WHO | Infra operator |
| SECRET | NO |
| STORED | `deploy/testnet/env/testnet-indexer.env.template` (after substitution) |
| USED BY | Indexer WebSocket subscription |

---

### 4.3 — Testnet Indexer API URL
| Field | Value |
|---|---|
| Value | `https://api.testnet.primewave.xyz` |
| SOURCE | Phase 15 (indexer deploy) |
| WHEN | Phase 15 |
| WHO | Infra operator |
| SECRET | NO |
| STORED | PWCScan env |
| USED BY | PWCScan frontend |

---

### 4.4 — Testnet PWCScan URL
| Field | Value |
|---|---|
| Value | `https://explorer.testnet.primewave.xyz` |
| SOURCE | Phase 16 (PWCScan deploy) |
| WHEN | Phase 16 |
| WHO | Infra operator |
| SECRET | NO |
| STORED | Public; documented |
| USED BY | Users; health checks |

---

## 5. DEPLOYER IDENTITY

### 5.1 — Testnet Deployer C-Chain Address
| Field | Value |
|---|---|
| Value | `0x2AD3152Ca630e2eF6679EBeb8da7b8311bfbFc60` |
| SOURCE | Generated 2026-08-15 via `avalanche key create testnet-deployer` |
| WHEN | Generated — available now |
| WHO | Protocol Lead |
| SECRET | NO (address is public) |
| STORED | Here; `docs/PW-C15-INFRA-PROVISIONING-GUIDE.md` |
| USED BY | Fuji faucet; DeployTestnet.s.sol deployer |

---

### 5.2 — Testnet Deployer P-Chain Address
| Field | Value |
|---|---|
| Value | `P-fuji1p25rk6kz9lwg2plwmfmvkvzxsa5qd02kla0vsw` |
| SOURCE | Generated 2026-08-15 |
| WHEN | Generated — available now |
| WHO | Protocol Lead |
| SECRET | NO (address is public) |
| STORED | Here |
| USED BY | Fuji P-Chain AVAX transfer; CreateSubnetTx |

---

### 5.3 — Testnet Deployer Private Key
| Field | Value |
|---|---|
| Value | **NEVER STORED HERE** |
| SOURCE | `~/.avalanche-cli/key/testnet-deployer.pk` (Replit) or air-gapped hardware |
| WHEN | Available now (Replit) |
| WHO | Protocol Lead only |
| SECRET | **YES — NEVER COMMIT** |
| STORED | Encrypted storage only; `~/.avalanche-cli/key/` (testnet only) |
| USED BY | `deploy-contracts.sh` as `TESTNET_DEPLOYER_KEY` env var at deploy time only |

---

## 6. CEREMONY KEYS (PUBLIC ADDRESSES ONLY)

Fill this table after Phase 2 (Key Ceremony). Do NOT include private keys.

| Role | Address | Node ID | Notes |
|---|---|---|---|
| testnet-keeper-signer | `__FILL_AFTER_PHASE_2__` | N/A | EOA; keeper signer |
| testnet-ems-signer-1 | `__FILL_AFTER_PHASE_2__` | N/A | EMS 3-of-5 |
| testnet-ems-signer-2 | `__FILL_AFTER_PHASE_2__` | N/A | EMS 3-of-5 |
| testnet-ems-signer-3 | `__FILL_AFTER_PHASE_2__` | N/A | EMS 3-of-5 |
| testnet-ems-signer-4 | `__FILL_AFTER_PHASE_2__` | N/A | EMS 3-of-5 |
| testnet-ems-signer-5 | `__FILL_AFTER_PHASE_2__` | N/A | EMS 3-of-5 |
| validator-01 NodeID | `__FILL_AFTER_PHASE_9__` | required | From node logs |
| validator-02 NodeID | `__FILL_AFTER_PHASE_9__` | required | From node logs |
| validator-03 NodeID | `__FILL_AFTER_PHASE_9__` | required | From node logs |
| validator-01 BLS pubkey | `__FILL_AFTER_PHASE_9__` | required | ACP-99 registration |
| validator-02 BLS pubkey | `__FILL_AFTER_PHASE_9__` | required | ACP-99 registration |
| validator-03 BLS pubkey | `__FILL_AFTER_PHASE_9__` | required | ACP-99 registration |

---

## 7. GOVERNANCE ADDRESSES

| Role | Address | Notes |
|---|---|---|
| EmergencyMultisig | `__FILL_AFTER_PHASE_8__` | 3-of-5 EMS contract |
| PrimeWaveTimelock | `__FILL_AFTER_PHASE_8__` | 48h delay |
| Protocol Lead multisig | `__FILL_AFTER_KEY_CEREMONY__` | External multisig |

---

## 8. CONTRACT ADDRESSES

Fill after Phase 8.3. All addresses from `local-data/testnet-deployed-contracts.env`.

| Contract | Address | Chain ID |
|---|---|---|
| EmergencyMultisig | `__FILL_AFTER_PHASE_8__` | 77 |
| PrimeWaveTimelock | `__FILL_AFTER_PHASE_8__` | 77 |
| ValidatorFeeVault | `__FILL_AFTER_PHASE_8__` | 77 |
| DevTreasury | `__FILL_AFTER_PHASE_8__` | 77 |
| FeeDistributor | `__FILL_AFTER_PHASE_8__` | 77 |
| RewardVault | `__FILL_AFTER_PHASE_8__` | 77 |
| ValidatorRegistry | `__FILL_AFTER_PHASE_8__` | 77 |

---

## 9. ICM / WARP

| Variable | Value | Notes |
|---|---|---|
| ICM Teleporter Address | `__FILL_AFTER_PHASE_11__` | Deployed on PrimeWave testnet |
| Fuji Warp API endpoint | `https://api.avax-test.network/ext/bc/P` | Public — available now |
| Relayer signer address | `__FILL_AFTER_PHASE_11__` | |
| Relayer signer key | **NEVER STORE HERE** | Secret |

---

## 10. BOOTSTRAP NODES

| Node | Endpoint | IP | Status |
|---|---|---|---|
| bootstrap-01 | `NodeID-xxx@<IP>:9651` | `__FILL_AFTER_PHASE_9__` | |
| bootstrap-02 | `NodeID-xxx@<IP>:9651` | `__FILL_AFTER_PHASE_9__` | |

---

## 11. DATABASE

| Variable | Value | SECRET |
|---|---|---|
| PGHOST | `localhost` (on infra-01) or Replit `helium` (dev) | NO |
| PGPORT | `5432` | NO |
| PGDATABASE | `primewave_testnet` | NO |
| PGUSER | `indexer` | NO |
| PGPASSWORD | **NEVER HERE** | YES |
| DATABASE_URL | `postgresql://indexer:__SECRET__@localhost:5432/primewave_testnet` | YES (contains secret) |
| Keeper DB | `postgresql://keeper:__SECRET__@localhost:5432/primewave_testnet_keeper` | YES |

---

## 12. INFRASTRUCTURE SERVERS

| Server | Role | IP | SSH User | Notes |
|---|---|---|---|---|
| validator-01 | AvalancheGo validator | `__FILL_AFTER_PHASE_3__` | ubuntu | Port 9651 open |
| validator-02 | AvalancheGo validator | `__FILL_AFTER_PHASE_3__` | ubuntu | Port 9651 open |
| validator-03 | AvalancheGo validator | `__FILL_AFTER_PHASE_3__` | ubuntu | Port 9651 open |
| infra-01 | RPC/nginx + Indexer + Keeper + PWCScan + PostgreSQL | `__FILL_AFTER_PHASE_3__` | ubuntu | Ports 80/443 open |
| monitoring-01 | Prometheus + Grafana | `__FILL_AFTER_PHASE_3__` | ubuntu | Internal only |
