# PW-C14: Testnet Deployment Manifest
**Sprint:** PW-C14
**Environment:** TESTNET ONLY — Chain ID **77** (Previous testnet Chain ID: 77777)
**Status:** TEMPLATE — Fill in after testnet deployment ceremony

---

> This manifest is the authoritative record of the PrimeWave testnet deployment.
> Update all placeholder values during and after the deployment ceremony.
> DO NOT include private keys, seed phrases, or secrets in this document.

---

## 1. Network Identity

| Field | Value |
|---|---|
| Network Name | PrimeWave Testnet |
| Environment | TESTNET |
| Chain ID (EVM) | **77** |
| Previous Testnet Chain ID | 77777 | Changed post-C14; genesis regenerated |
| Blockchain ID | TBD — Fuji P-Chain ceremony |
| Subnet ID | TBD — Fuji P-Chain ceremony |
| VM ID | rXJjKFtAVSmpKwhMhw7ZMV6opKcsmhk5AuVxWNAzFG221wmM8 |
| Fuji Network ID | 5 |
| Genesis SHA-256 | TBD — record after genesis construction |
| Genesis File Path | `config/testnet/genesis.json` |
| Launch Date | TBD |

---

## 2. Version Lock

| Dependency | Version | Pin Reason |
|---|---|---|
| AvalancheGo | v1.14.2 | ICM compatibility; pinned C11 |
| Subnet-EVM | v0.6.2 (compatible with AvalancheGo v1.14.2) | Pinned C11 |
| ICM Relayer | icm-relayer-v1.7.5 (commit 40e1c89) | Warp relay; pinned C11 |
| Solidity | 0.8.30 | Protocol contracts |
| OpenZeppelin | 5.6.1 (project), 5.1.0 (StakingManager dep) | Pinned C00 |
| Foundry | v1.7.1 | Test and deploy toolchain |
| Node.js | 22 LTS | Keeper, indexer, PWCScan |
| ethers.js | 6.x | Keeper chain interface |
| PostgreSQL | 16.x | Indexer database |

---

## 3. Contract Addresses (Testnet)

> Filled in by `scripts/testnet/deploy-contracts.sh` → `local-data/testnet-deployed-contracts.env`

| Contract | Address | Block Deployed |
|---|---|---|
| EmergencyMultisig | TBD — ceremony | TBD |
| PrimeWaveTimelock | TBD — ceremony | TBD |
| FeeDistributor | TBD — ceremony | TBD |
| ValidatorFeeVault | TBD — ceremony | TBD |
| DevTreasury | TBD — ceremony | TBD |
| RewardVault | TBD — ceremony | TBD |
| PrimeWaveValidatorRegistry | TBD — ceremony | TBD |

---

## 4. Testnet Validator Set

> Filled in by validators during onboarding (see `docs/PW-C14-VALIDATOR-ONBOARDING.md`)

| # | NodeID | BLS Public Key | Operator | Status |
|---|---|---|---|---|
| 1 | TBD | TBD | PrimeWave | ☐ |
| 2 | TBD | TBD | PrimeWave | ☐ |
| 3 | TBD | TBD | PrimeWave | ☐ |
| 4 | TBD | TBD | External Op A | ☐ |
| 5 | TBD | TBD | External Op B | ☐ |

---

## 5. Public Endpoints

| Service | URL | TLS | Notes |
|---|---|---|---|
| Public RPC (HTTPS) | `https://rpc.primewave-testnet.example.com/ext/bc/<BLOCKCHAIN_ID>/rpc` | ✅ Let's Encrypt | ETH JSON-RPC |
| Public WebSocket | `wss://rpc.primewave-testnet.example.com/ext/bc/<BLOCKCHAIN_ID>/ws` | ✅ | EVM events |
| PWCScan Explorer | `https://testnet.pwcscan.example.com` | ✅ | TESTNET labeled |
| Indexer API | `https://testnet.pwcscan.example.com/indexer-api/` | ✅ | Via nginx proxy |

---

## 6. Key Inventory (Public Addresses Only)

> No private keys are documented here. All private keys are in encrypted files.

| Role | Public Address | Notes |
|---|---|---|
| Testnet Deployer | TBD — ceremony | Used for contract deployment only; no ongoing role |
| Testnet Treasury Multisig | TBD — ceremony | 3-of-5 testnet signers |
| EmergencyMultisig Signer 1 | TBD — ceremony | Testnet only |
| EmergencyMultisig Signer 2 | TBD — ceremony | Testnet only |
| EmergencyMultisig Signer 3 | TBD — ceremony | Testnet only |
| EmergencyMultisig Signer 4 | TBD — ceremony | Testnet only |
| EmergencyMultisig Signer 5 | TBD — ceremony | Testnet only |
| Testnet Keeper Signer | TBD — ceremony | Keeper service EOA |

---

## 7. Infrastructure

| Role | Provider | Region | Spec | Hostname |
|---|---|---|---|---|
| Validator 1 | TBD | TBD | 4 vCPU / 16GB / 250GB NVMe | validator-1.primewave-testnet.internal |
| Validator 2 | TBD | TBD | 4 vCPU / 16GB / 250GB NVMe | validator-2.primewave-testnet.internal |
| Validator 3 | TBD | TBD | 4 vCPU / 16GB / 250GB NVMe | validator-3.primewave-testnet.internal |
| Validator 4 | TBD | TBD | 4 vCPU / 16GB / 250GB NVMe | validator-4.primewave-testnet.internal |
| Validator 5 | TBD | TBD | 4 vCPU / 16GB / 250GB NVMe | validator-5.primewave-testnet.internal |
| RPC Node 1 | TBD | TBD | 8 vCPU / 32GB / 1TB NVMe | rpc-1.primewave-testnet.internal |
| Explorer Host | TBD | TBD | 4 vCPU / 16GB / 500GB SSD | explorer.primewave-testnet.internal |
| Sentinel | TBD | TBD | 2 vCPU / 8GB / 100GB SSD | sentinel.primewave-testnet.internal |

---

## 8. Deployment Artifacts Hashes

> Record SHA-256 of key artifacts at deployment time.

| Artifact | SHA-256 |
|---|---|
| `config/testnet/genesis.json` | TBD |
| AvalancheGo binary | TBD |
| Subnet-EVM plugin | TBD |
| ICM Relayer binary | TBD |
| Indexer `dist/` tarball | TBD |
| Keeper `dist/` tarball | TBD |

---

## 9. Testnet Allocation Summary

| Recipient | Amount (PW) | Address |
|---|---|---|
| Testnet Deployer | 16,000,000 | TBD |
| Testnet Treasury | 25,000,000 | TBD |
| Testnet Team | 20,000,000 | TBD |
| Testnet Community | 20,000,000 | TBD |
| Testnet Ecosystem | 10,000,000 | TBD |
| Testnet Reserve | 9,000,000 | TBD |
| **Total** | **100,000,000** | Supply invariant ✅ |

---

## 10. Post-Deployment Verification

| Check | Result | Date |
|---|---|---|
| INV-G1: Chain ID 77 | TBD | |
| INV-G2: NativeMinter disabled | TBD | |
| INV-G3: Supply 100M PW | TBD | |
| INV-G4: RewardVault 15M PW | TBD | |
| NET-01 to NET-30 full matrix | TBD | |
| Security checklist | TBD | |
| Regression tests | 792/792 + 57/57 + 20/20 ✅ | 2026-08-14 |

---

*Updated: 2026-08-14 (C14 template created — pending testnet ceremony)*
