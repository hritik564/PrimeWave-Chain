# PrimeWave Chain — Architecture Specification
**Sprint PW-C00 | Status: DESIGN DOCUMENT — NOT FOR PRODUCTION**

---

## 1. Overview

PrimeWave Chain is a sovereign EVM-compatible Avalanche L1 built on the ACP-77 / ACP-99 framework. It is the foundational settlement layer for the PrimeWave ecosystem.

- **Native asset:** PW (max 100,000,000)
- **EVM compatibility:** Full (Subnet-EVM / AvalancheGo)
- **Consensus:** Snowman++ (Avalanche BFT)
- **Target block time:** ~2 seconds (to be finalized through testnet benchmarking)

PrimeWave Chain is strictly separate from the existing PrimeWave application. The application communicates with the chain only through standard EVM RPC, WebSocket, and contract interactions.

---

## 2. Avalanche L1 Architecture (ACP-77 / ACP-99)

### 2.1 What Changed with ACP-77

ACP-77 ("Reinventing Subnets"), now activated, fundamentally changed how Avalanche L1s work:

| Feature | Pre-ACP-77 (Subnets) | Post-ACP-77 (Sovereign L1s) |
|---|---|---|
| Validator set control | P-Chain only | L1 owns its validator set |
| Primary Network stake required | 2000 AVAX per validator | Eliminated |
| Staking asset | AVAX on P-Chain | L1 native token (on-chain) |
| Validator management | P-Chain transactions | ValidatorManager smart contract |
| Reward calculation | P-Chain protocol | On-chain (IRewardCalculator) |
| Reward distribution | P-Chain | On-chain (_reward() hook) |

Under ACP-77, PrimeWave Chain:
- Owns its own validator set via a `ValidatorManager` contract deployed on the L1
- Communicates with the Avalanche P-Chain via ICM (Interchain Messaging / Warp protocol)
- Does NOT require validators to stake AVAX on the Primary Network

### 2.2 ACP-99 — Validator Manager Solidity Standard

ACP-99 defines the standard Solidity interface for Validator Managers. The reference implementation lives in the `ava-labs/icm-contracts` repository (now archived as of December 2025; successor: see open questions).

Available standard implementations:
- `PoAValidatorManager` — permissioned, admin-controlled validators, **no staking rewards**
- `NativeTokenStakingManager` — PoS with native token staking, **requires minting**
- `ERC20TokenStakingManager` — PoS with ERC-20 staking, **requires mintable ERC-20**

### 2.3 Selected Architecture: Hybrid PoA → PoS

**Phase 1 (Launch):** `PoAValidatorManager` — 15 permissioned validators, no staking reward minting.

**Phase 2 (PoS Transition):** Custom staking contract with pre-funded reward vault (15M PW from genesis). See `PRIMEWAVE_VALIDATOR_SPEC.md` for full details.

### 2.4 Key Architectural Principle: Warp / ICM

The ValidatorManager on the EVM chain communicates with the Avalanche P-Chain via Avalanche Warp Messaging (AWM). Registration and deregistration of validators involves:
1. EVM contract emitting a Warp-signed message
2. P-Chain processing the validator set change
3. P-Chain sending a Warp confirmation back
4. EVM contract finalizing the registration

This round-trip is fundamental to the architecture and must be accounted for in validator lifecycle management.

---

## 3. EVM Compatibility

PrimeWave Chain runs **Subnet-EVM** — the standard Avalanche EVM implementation. This provides:

- Full Ethereum opcode compatibility (latest EIPs supported by Subnet-EVM)
- Standard Ethereum JSON-RPC and WebSocket API
- Standard MetaMask / wallet compatibility
- Standard Solidity contract deployment
- Precompile extensions (Fee Manager, Reward Manager, Native Minter, etc.)

### 3.1 Required Precompiles

| Precompile | Address | Purpose | Required? |
|---|---|---|---|
| WarpMessenger | `0x0200000000000000000000000000000000000005` | P-Chain ↔ L1 validator communication | **YES** |
| RewardManager | `0x0200000000000000000000000000000000000004` | Controls where tx fees go | **YES** |
| FeeManager | `0x0200000000000000000000000000000000000003` | Dynamic fee parameter control | OPTIONAL |
| NativeMinter | `0x0200000000000000000000000000000000000001` | Mints native tokens | **NO** — MUST NOT be enabled |

> ⚠️ **CRITICAL:** The `NativeMinter` precompile MUST NOT be activated. Enabling it would create a pathway to inflate PW beyond 100,000,000. No address should be granted NativeMinter admin or minter roles.

### 3.2 Gas / Fee Architecture

The `RewardManager` precompile controls fee routing. PrimeWave's 70/20/10 model:

- **70% → Validators** (via `allowFeeRecipients: true` and fee collection by validator coinbase)
- **20% → PrimeWave Treasury** (via a FeeDistributor contract that splits collected fees)
- **10% → Burn** (sent to `0x000...dead` or burned via contract)

> ⚠️ **Architectural Note:** Subnet-EVM's Reward Manager natively supports "allow fee recipients" (validators collect) OR "send all to one address" OR "burn all" — not a three-way percentage split. Achieving 70/20/10 requires a `FeeDistributor` contract that validators call to forward and split their collected fees. See `PRIMEWAVE_TOKENOMICS.md` for the detailed gas economics design.

---

## 4. Network Topology

```
                       ┌─────────────────────────────┐
                       │      Avalanche P-Chain        │
                       │  (validator registration)     │
                       └──────────────┬────────────────┘
                                      │ Warp/ICM
                       ┌──────────────▼────────────────┐
                       │       PrimeWave Chain          │
                       │    (Subnet-EVM / ACP-77 L1)   │
                       │                                │
                       │  ┌────────────────────────┐   │
                       │  │  ValidatorManager.sol  │   │
                       │  │  RewardVault.sol       │   │
                       │  │  FeeDistributor.sol    │   │
                       │  │  PWUSD.sol             │   │
                       │  │  PWSwap.sol (future)   │   │
                       │  └────────────────────────┘   │
                       └───────────────────────────────┘
                                      │
                   ┌──────────────────┼──────────────────┐
                   │                  │                   │
         ┌─────────▼──────┐  ┌────────▼───────┐  ┌──────▼────────┐
         │   RPC Nodes     │  │  Validator     │  │  Archive/     │
         │  (public API)   │  │  Nodes (15)    │  │  Indexer Node │
         └────────────────┘  └────────────────┘  └───────────────┘
```

---

## 5. On-Chain Contract Architecture

### 5.1 Core Protocol Contracts

| Contract | Role | Deploy Timing |
|---|---|---|
| `PoAValidatorManager` | Phase 1 validator set management | Genesis / immediate post-genesis |
| `RewardVault` | Holds 15M PW, distributes staking rewards | Genesis pre-fund |
| `FeeDistributor` | Splits collected validator fees 70/20/10 | Pre-mainnet |
| `PrimeWaveTreasury` | Multisig + timelock for treasury | Pre-mainnet |
| `EmergencyMultisig` | Emergency pause/security authority | Pre-mainnet |
| `PWUSD` | PrimeWave USD stablecoin | Pre-mainnet |
| `MonetaryAuthority` | Narrowly scoped PWUSD mint/burn role | Pre-mainnet |

### 5.2 Future Contracts (Not PW-C00)

| Contract | Sprint |
|---|---|
| `PWSwap` | PW-Swap-C01+ |
| `PoSValidatorManager` (custom) | PW-C0X (after PoA → PoS design approval) |
| `LPToken` | PW-Swap-C01+ |

---

## 6. Separation of Concerns

PrimeWave Chain MUST NOT import or embed logic from the existing PrimeWave web application.

| Layer | Interaction Method |
|---|---|
| PrimeWave App → Chain | Standard EVM JSON-RPC / WebSocket |
| PrimeWave App → PWSwap | ABI-encoded contract calls |
| PrimeWave App → PWUSD | ERC-20 transfer / approval |
| PrimeWave Dex → Chain | Event indexing / RPC |
| PrimeWave Dex → PWSwap | Event indexing (Swap, Sync events) |

---

## 7. Avalanche Version Targeting and Dependency Registry

PrimeWave Chain uses the following confirmed official dependencies (OQ-001 resolved):

| Dependency | Repository | Version / Notes |
|---|---|---|
| **Validator Manager contracts** | `ava-labs/icm-services` tag `icm-relayer-v1.7.5` commit `40e1c89` | Replaces archived `ava-labs/icm-contracts`. Solidity 0.8.30, EVM: shanghai. Released Jan 26, 2026. Compatible with AvalancheGo v1.14.0–v1.14.2. |
| **AvalancheGo node** | `ava-labs/avalanchego` | Current: v1.14.2. Lock exact version at testnet initiation. |
| **Subnet-EVM** | ⛔ **ARCHIVED Dec 16, 2025** — EVM merged into AvalancheGo v1.14.1 | Not a separate dependency. AvalancheGo v1.14.2 includes the EVM plugin. Do NOT reference `ava-labs/subnet-evm`. |
| **Avalanche CLI** | `ava-labs/avalanche-cli` | Used for L1 creation / conversion. Lock at testnet initiation. |
| **OpenZeppelin Contracts** | `OpenZeppelin/openzeppelin-contracts` **v5.6.1** | ERC-20, AccessControl, TimelockController. Latest stable (npm `latest`, Feb 27, 2026). MIT. |
| **OpenZeppelin Upgradeable** | `OpenZeppelin/openzeppelin-contracts-upgradeable` **v5.6.1** | Proxy/upgradeable pattern. Synchronized with OZ Contracts v5.6.1. MIT. |
| **Foundry** | `foundry-rs/foundry` | Build, test, deploy tooling. Pin commit in CI. |
| **ACP-77** | Activated on Avalanche mainnet | Standard used. |
| **ACP-99** | Activated on Avalanche mainnet | Standard used. |

### Key Dependency Notes

- `ava-labs/icm-services` is **not** an NPM package; it is a Go/Solidity monorepo. PrimeWave will use the Solidity contracts from the `icm-contracts/` subdirectory, compiled with Foundry.
- Pin to a **specific release tag** of `icm-services`, not the `main` branch, for production stability. See OQ-018.
- `ava-labs/icm-contracts` (archived Dec 3, 2025) must **not** be used as a dependency — use `ava-labs/icm-services` exclusively.

### License Notes

| Repository | License |
|---|---|
| `ava-labs/icm-services` | LicenseRef-Ecosystem (Ava Labs proprietary for commercial use — verify terms for PrimeWave's use case) |
| `ava-labs/avalanchego` | BSD-3-Clause |
| `ava-labs/subnet-evm` | ⛔ ARCHIVED — not a dependency |
| `OpenZeppelin/*` | MIT |
| `foundry-rs/foundry` | MIT |

> ⚠️ **License Action Required:** The `LicenseRef-Ecosystem` license on `icm-services` contracts should be reviewed by PrimeWave's legal counsel before production deployment. Clarify whether deploying these contracts on PrimeWave Chain requires a commercial license from Ava Labs.

---

## 8. Testnet Architecture

- Dedicated PrimeWave Testnet L1 (separate from mainnet)
- Minimum 3–5 validator nodes for testnet
- Faucet contract for test PW distribution
- Full testnet RPC and explorer
- Testnet PWUSD and mock contracts
- All parameters finalized through testnet benchmarking before mainnet

---

*This document is a PW-C00 design specification. No production deployment has occurred.*
