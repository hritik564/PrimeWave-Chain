# PrimeWave Chain — Dependency Map
**Sprint PW-C00 | Status: DESIGN DOCUMENT — NOT FOR PRODUCTION**

---

## 1. Ecosystem Overview

The PrimeWave ecosystem consists of four distinct projects:

```
┌──────────────────────────────────────────────────────────────────┐
│                   PrimeWave Ecosystem                            │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │               PROJECT 1: PrimeWave Chain                 │   │
│  │  (Foundational protocol — everything depends on this)    │   │
│  └────────────────────────┬─────────────────────────────────┘   │
│                           │                                      │
│         ┌─────────────────┼─────────────────┐                   │
│         │                 │                 │                    │
│  ┌──────▼──────┐  ┌───────▼──────┐  ┌──────▼──────────────┐   │
│  │ PROJECT 2   │  │  PROJECT 3   │  │     PROJECT 4        │   │
│  │ PrimeWave   │  │  PrimeWave   │  │  PrimeWave           │   │
│  │ Swap        │  │  Dex         │  │  Application         │   │
│  │ (DEX/AMM)   │  │  (Analytics) │  │  (Existing MLM app)  │   │
│  └─────────────┘  └──────────────┘  └──────────────────────┘   │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

**Hard rule:** These four projects MUST remain in separate codebases. No project imports code directly from another. They communicate only through published APIs, contract ABIs, and standard RPC.

---

## 2. Project Dependency Matrix

| Project | Depends On | Communication Method |
|---|---|---|
| PrimeWave Chain | None (foundational) | — |
| PrimeWave Swap | PrimeWave Chain | Contract deployment on chain; PW + PWUSD contract ABIs |
| PrimeWave Dex | PrimeWave Chain + PrimeWave Swap | Event indexing via RPC; PWSwapPair ABI |
| PrimeWave App | PrimeWave Chain | EVM JSON-RPC; PWUSD ERC-20 ABI |

---

## 3. Detailed Dependency Graph

### 3.1 PrimeWave Swap → PrimeWave Chain

**Dependencies:**
- PrimeWave Chain must be running (testnet/mainnet)
- PW (native token) exists and is transferable
- PWUSD ERC-20 contract is deployed and has standard ERC-20 interface
- Sufficient block gas limit for AMM operations
- EVM JSON-RPC endpoint available for deployment

**Contract ABIs used:**
- PWUSD ERC-20 ABI (transfer, approve, transferFrom, balanceOf)
- NativeToken (PW) — native ETH-equivalent calls

**NOT dependent on:**
- PrimeWave Dex
- PrimeWave App
- Any off-chain service from other projects

### 3.2 PrimeWave Dex → PrimeWave Chain + PrimeWave Swap

**Dependencies:**
- PrimeWave Chain running with WebSocket RPC
- PWSwapPair contract deployed and emitting events
- Archive node for historical data access
- Indexer must be able to read from block 0

**Contract ABIs/Events used:**
- `PWSwapPair`: Swap, Sync, Mint, Burn events
- `PWSwapPair`: getReserves(), price0CumulativeLast(), price1CumulativeLast()
- `PWSwapFactory`: getPair()

**NOT dependent on:**
- PrimeWave App
- Any internal PrimeWave Swap service (only the on-chain contract events)

### 3.3 PrimeWave App → PrimeWave Chain

**Dependencies:**
- PrimeWave Chain running with JSON-RPC endpoint
- PWUSD ERC-20 contract deployed
- PrimeWave App's wallet integration (MetaMask-compatible)

**Interaction methods:**
- Standard EVM JSON-RPC (eth_call, eth_sendTransaction)
- WebSocket for event subscriptions
- PWUSD ERC-20 standard interface

**NOT dependent on:**
- PrimeWave Swap internals (may read swap state via chain, not via Swap service)
- PrimeWave Dex internals

---

## 4. Interface Contracts (Published ABIs)

The following ABIs are the published interfaces between projects:

| ABI | Produced By | Consumed By |
|---|---|---|
| PWUSD ERC-20 ABI | PrimeWave Chain | PrimeWave Swap, PrimeWave App |
| PWSwapPair ABI (events + view fns) | PrimeWave Swap | PrimeWave Dex (indexer) |
| PWSwapRouter ABI | PrimeWave Swap | PrimeWave App, PrimeWave Dex |
| PrimeWave Chain RPC endpoint | PrimeWave Chain | All projects |

ABIs must be versioned and published in a shared repository (e.g., a dedicated `primewave-abis` package or GitHub release).

---

## 5. Startup / Deployment Order

To bring the entire ecosystem online, the following order MUST be followed:

```
Step 1: PrimeWave Chain testnet/mainnet running
         → Validator nodes active
         → RPC endpoints online

Step 2: PrimeWave Chain core contracts deployed
         → PWUSD deployed
         → PoAValidatorManager initialized
         → RewardVault funded (15M PW from genesis)
         → FeeDistributor configured

Step 3: PrimeWave Swap deployed
         → PWSwap contracts deployed and verified
         → Initial liquidity added (40M PW + 2M PWUSD)
         → Liquidity locked for 36 months

Step 4: PrimeWave Dex indexer activated
         → Syncs from block 0
         → Market data API online
         → Frontend live

Step 5: PrimeWave App integration
         → App connects to PrimeWave Chain RPC
         → PWUSD distribution integrated
```

No step can start before its dependencies are complete.

---

## 6. No Shared Codebase Policy

| What is PROHIBITED | Why |
|---|---|
| PrimeWave App code imported into PrimeWave Chain repo | Business logic belongs in the app, not the protocol |
| PWSwap contracts in the Chain repo | Separate project, separate audit scope |
| PrimeWave Dex indexer in the Chain repo | Separate operational concerns |
| Any project depending on internal implementation details of another | Only public ABI/RPC interfaces are stable contracts |

Each project must be deployable and testable independently of the others.

---

*This document is a PW-C00 design specification. No production deployment has occurred.*
