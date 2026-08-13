# PrimeWave Chain — Local Network Topology

> **ENVIRONMENT: LOCAL DEVELOPMENT ONLY**
> This document describes the local development network only.
> Not for testnet or mainnet.

## Overview

The local PrimeWave development network runs 3 Avalanche L1 validator/nodes on a single machine.
All nodes communicate via localhost. Each node exposes its own RPC and WebSocket endpoints.

The network is managed by **Avalanche Network Runner (ANR)**, which is invoked through the
**Avalanche CLI**. ANR handles process lifecycle, port assignment, and inter-node networking.

## Node Topology

```
  ┌─────────────────────────────────────────────────────────────┐
  │             LOCAL MACHINE (development only)                │
  │                                                             │
  │  ┌────────────────┐   ┌────────────────┐  ┌─────────────┐  │
  │  │   NODE 1       │   │   NODE 2       │  │   NODE 3    │  │
  │  │  Validator     │   │  Validator     │  │  Validator  │  │
  │  │                │   │                │  │             │  │
  │  │  AvalancheGo   │   │  AvalancheGo   │  │ AvalancheGo │  │
  │  │  v1.14.2       │   │  v1.14.2       │  │ v1.14.2     │  │
  │  │                │───│                │──│             │  │
  │  │  P-Chain       │   │  P-Chain       │  │  P-Chain    │  │
  │  │  X-Chain       │   │  X-Chain       │  │  X-Chain    │  │
  │  │  PrimeWave EVM │   │  PrimeWave EVM │  │ PrimeWave   │  │
  │  └────────────────┘   └────────────────┘  └─────────────┘  │
  │        ↕                     ↕                   ↕         │
  │  ┌─────────────────────────────────────────────────────┐   │
  │  │         AvalancheSnow Consensus (local)             │   │
  │  └─────────────────────────────────────────────────────┘   │
  │                                                             │
  └─────────────────────────────────────────────────────────────┘
```

## Port Assignment

Ports are allocated by Avalanche Network Runner (ANR) at deployment time.
The primary node is accessible at:

| Service              | Host       | Port | Protocol |
|---|---|---|---|
| Primary RPC          | 127.0.0.1  | 9650 | HTTP/JSON-RPC |
| Primary WebSocket    | 127.0.0.1  | 9650 | WS |
| Primary P-Chain API  | 127.0.0.1  | 9650 | HTTP |
| Primary Health API   | 127.0.0.1  | 9650 | HTTP |
| Node 2 RPC (approx) | 127.0.0.1  | 9652 | HTTP |
| Node 3 RPC (approx) | 127.0.0.1  | 9654 | HTTP |

> **Note:** ANR assigns ports dynamically. Nodes 2 and 3 may use different ports.
> Use `avalanche network status` after deployment to see all node ports.

## API Endpoint Paths

```
Base:             http://127.0.0.1:9650
P-Chain API:      http://127.0.0.1:9650/ext/bc/P
X-Chain API:      http://127.0.0.1:9650/ext/bc/X
C-Chain (ref):    http://127.0.0.1:9650/ext/bc/C/rpc
PrimeWave RPC:    http://127.0.0.1:9650/ext/bc/<BLOCKCHAIN_ID>/rpc
PrimeWave WS:     ws://127.0.0.1:9650/ext/bc/<BLOCKCHAIN_ID>/ws
Health:           http://127.0.0.1:9650/ext/health
```

> The `<BLOCKCHAIN_ID>` is assigned when the L1 is deployed and saved to
> `local-data/network-state.env` by `start-local.sh`.

## Chain Identity

| Parameter | Value | Notes |
|---|---|---|
| Chain Name | `primewavedev` | CLI name only, not on-chain (letters only — CLI restriction) |
| Chain ID (EVM) | `73571` | **DEV ONLY — not for testnet/mainnet** |
| Native Currency | `PW` | 18 decimals |
| Block Time | ~2 seconds | configured in genesis `feeConfig` |
| Gas Limit | 30,000,000 | per block |
| Min Base Fee | 25 gwei | EIP-1559 base |
| P-Chain Blockchain ID | (dynamic) | assigned at L1 creation |

## AvalancheGo Version

```
AvalancheGo:       v1.14.2  (pinned, from PW-C00 FINAL GATE)
EVM Integration:   Bundled in AvalancheGo ≥ v1.14.1 (subnet-evm archived Dec 2025)
Solidity version:  0.8.30
```

## Data Directories

| Path | Purpose |
|---|---|
| `local-bin/` | Downloaded AvalancheGo and Avalanche CLI binaries |
| `local-data/` | Runtime state (blockchain ID, RPC URL, test results) |
| `~/.avalanche-cli/` | Avalanche CLI configuration and blockchain specs |
| `~/.avalanche-cli/subnets/primewavedev/` | PrimeWave dev chain config |
| `/tmp/` (or ANR default) | ANR temporary node data (cleaned on reset) |

## Node Communication

Nodes communicate using the Avalanche P2P protocol (Snowman consensus).
In local mode, all nodes use `--network-id=local` and connect to each other
via hardcoded bootstrap IPs managed by ANR.

Each node validates:
- P-Chain (platform chain — staking, subnets)
- X-Chain (asset exchange chain)
- PrimeWave Chain EVM (our L1)

## Startup Sequence

Managed by `start-local.sh` → `avalanche blockchain deploy primewavedev --local`:

1. ANR starts AvalancheGo node processes
2. Each node bootstraps P-Chain and X-Chain
3. Primary validator issues `CreateSubnetTx` on P-Chain
4. `ConvertSubnetToL1Tx` converts subnet to L1 (ACP-77 flow)
5. `CreateBlockchainTx` initializes the EVM chain with dev genesis
6. Validators register on the L1 via `RegisterL1ValidatorTx`
7. PrimeWave EVM chain starts producing blocks
8. RPC becomes available at primary node port

Estimated startup time: 30–60 seconds.

## Shutdown Sequence

Managed by `stop-local.sh` → `avalanche network stop`:

1. ANR sends SIGTERM to all node processes
2. Nodes save state and exit
3. Chain data is preserved (network can be restarted from last block)

## Reset Sequence

Managed by `reset-local.sh` → `avalanche network clean`:

1. All node processes are stopped and killed
2. ANR temporary data is removed
3. CLI subnet configuration is removed
4. `local-data/` state files are removed
5. A fresh setup is required before the next start

## Security Notes (Local Dev)

- All dev keys are **publicly known** (Foundry test mnemonic)
- Chain ID 73571 is **local development only**
- No production keys exist in this environment
- No production endpoints are configured
- Do not expose node ports (9650+) to external networks
- Local nodes have no authentication — local network only

## Connection to MetaMask

```
Network Name:    PrimeWave Dev
RPC URL:         http://127.0.0.1:9650/ext/bc/<BLOCKCHAIN_ID>/rpc
Chain ID:        73571
Currency Symbol: PW
Block Explorer:  (none for local dev)
```

> MetaMask must be running on the same machine as the nodes.
> MetaMask cannot connect to `127.0.0.1` from a different device.

## Later Sprint Dependencies

This local topology documents dependencies for future sprints:

| Sprint | Dependency on PW-C01 Network |
|---|---|
| PW-C02 (Smart Contracts) | PrimeWave EVM RPC + funded dev accounts |
| PW-C03 (PoAManager) | P-Chain + local validator infrastructure |
| PW-C04 (RewardVault) | Deployed PrimeWave EVM + gas accounting |
| PW-C05 (PoS Transition) | Existing PoA network to migrate |
| Testnet | Separate network — not based on local topology |
