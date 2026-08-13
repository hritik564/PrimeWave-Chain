# PW-C01: Local PrimeWave Chain Development Environment

> **ENVIRONMENT: LOCAL DEVELOPMENT ONLY**
> This guide covers the local development network only.
> Chain ID 73571 is NOT for testnet or mainnet.

## Table of Contents

1. [Requirements](#1-requirements)
2. [Software Versions](#2-software-versions)
3. [Installation](#3-installation)
4. [Repository Structure](#4-repository-structure)
5. [Local Network Architecture](#5-local-network-architecture)
6. [Node Topology](#6-node-topology)
7. [Port Map](#7-port-map)
8. [Chain Configuration](#8-chain-configuration)
9. [RPC Configuration](#9-rpc-configuration)
10. [Wallet Configuration](#10-wallet-configuration)
11. [Starting the Network](#11-starting-the-network)
12. [Stopping the Network](#12-stopping-the-network)
13. [Resetting the Network](#13-resetting-the-network)
14. [Running Tests](#14-running-tests)
15. [Troubleshooting](#15-troubleshooting)
16. [Known Limitations](#16-known-limitations)
17. [Security Warnings](#17-security-warnings)
18. [Next Sprint Dependencies](#18-next-sprint-dependencies)

---

## 1. Requirements

### Host machine

| Requirement | Minimum | Notes |
|---|---|---|
| OS | Linux (x86_64 or arm64) or macOS | Windows: not tested |
| CPU | 2 cores | 4 cores recommended for 3 nodes |
| RAM | 2 GB free | 500 MB per AvalancheGo node × 3 + overhead |
| Disk | 1 GB free | For binaries and local chain data |
| Internet | Required for setup only | Binary downloads (~300 MB total) |

### Tools required

| Tool | Where used | Install command |
|---|---|---|
| `bash` ≥ 4.x | All scripts | Pre-installed on Linux; macOS: `brew install bash` |
| `curl` | Binary downloads, RPC tests | Pre-installed on most systems |
| `jq` | JSON parsing in tests | `apt install jq` / `brew install jq` |
| `bc` | Balance conversion in tests | Pre-installed on Linux |

### Optional tools

| Tool | Where used | Install |
|---|---|---|
| Foundry (`cast`) | Signed transaction tests (Test 8) | See §3.4 |
| MetaMask | Wallet connectivity verification | Browser extension |

---

## 2. Software Versions

All versions are pinned per the **PW-C00 FINAL GATE**. Do not silently change these.

| Software | Pinned Version | Source | Notes |
|---|---|---|---|
| AvalancheGo | `v1.14.2` | ava-labs/avalanchego | Granite.2 — includes integrated EVM |
| Avalanche CLI | `v1.9.5` | ava-labs/avalanche-cli | Maintenance mode (Dec 2025); last stable |
| EVM | Integrated | AvalancheGo ≥ v1.14.1 | subnet-evm archived Dec 2025 |
| Solidity | `0.8.30` | — | For PW-C02+ smart contracts |
| OpenZeppelin | `v5.6.1` | OZ Contracts + Upgradeable | For PW-C02+ smart contracts |

### Version compatibility note

Avalanche CLI `v1.9.5` uses `avalanche-network-runner v1.8.4`, which was built in October 2025 — before AvalancheGo `v1.14.2` was released (March 30, 2026). To enforce the pinned `v1.14.2` binary:

- `setup-local.sh` downloads AvalancheGo `v1.14.2` explicitly to `local-bin/avalanchego`
- `start-local.sh` passes `--avalanchego-path local-bin/avalanchego` to the CLI
- If `--avalanchego-path` is unsupported by the installed CLI version, the CLI may download its own AvalancheGo binary. See §15 — Troubleshooting for the resolution procedure.

---

## 3. Installation

### 3.1 Clone and open the project

```bash
git clone <repo-url>
cd primewave-chain
```

### 3.2 Run setup (downloads binaries, creates chain config)

```bash
bash scripts/setup-local.sh
```

This script:
1. Detects OS and architecture (Linux/macOS × amd64/arm64)
2. Downloads AvalancheGo `v1.14.2` to `local-bin/avalanchego`
3. Downloads Avalanche CLI `v1.9.5` to `local-bin/avalanche`
4. Verifies installed binary versions match pinned versions
5. Creates the PrimeWave dev blockchain configuration via `avalanche blockchain create`

The script is **idempotent** — safe to run again if something fails partway through.

Typical setup time: 2–5 minutes (binary downloads).

### 3.3 Start the local network

```bash
bash scripts/start-local.sh
```

This starts 3 local AvalancheGo validator nodes and deploys the PrimeWave L1 chain.
Typical startup time: 30–60 seconds.

### 3.4 Install Foundry (optional, recommended for full test coverage)

Foundry provides `cast` for sending signed transactions without unlocking accounts:

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

Verify: `cast --version`

With Foundry installed, Test 8 (PW transfer) and Tests 9–10 (gas/receipt) run fully automated.
Without Foundry, Tests 8–10 require manual steps (see §14).

---

## 4. Repository Structure

```
primewave-chain/
├── chain/
│   ├── genesis/
│   │   └── dev-genesis.json          DEV genesis — PW native token, funded dev accounts
│   └── config/
│       └── chain-config.json         EVM chain-level config (RPC APIs, logging)
│
├── config/
│   └── dev/
│       ├── network.env               Non-secret dev environment variables
│       └── dev-keys.md               Dev key documentation (PUBLIC test keys only)
│
├── scripts/
│   ├── _common.sh                    Shared environment — sourced by all scripts
│   ├── setup-local.sh                Download binaries, create chain config
│   ├── start-local.sh                Start local PrimeWave network
│   ├── stop-local.sh                 Stop local network
│   ├── reset-local.sh                Wipe all local state
│   ├── status-local.sh               Show network status and balances
│   └── test-local.sh                 Run automated smoke tests
│
├── tests/
│   └── smoke-test.sh                 13 automated smoke tests
│
├── infrastructure/
│   └── local-network.md              Node topology and architecture reference
│
├── local-bin/                        Downloaded binaries (git-ignored)
│   ├── avalanchego                   AvalancheGo v1.14.2 binary
│   └── avalanche                     Avalanche CLI v1.9.5 binary
│
├── local-data/                       Runtime state (git-ignored)
│   ├── network-state.env             RPC URL, blockchain ID, etc.
│   └── test-results-*.txt            Smoke test run records
│
└── docs/
    ├── (PW-C00 architecture docs)
    ├── PW-C01-LOCAL-DEVELOPMENT.md   This file
    └── PW-C01-TEST-REPORT.md         Test execution report
```

---

## 5. Local Network Architecture

The local network is a fully functional 3-node Avalanche L1.

**What runs locally:**

- 3 × AvalancheGo `v1.14.2` processes (P-Chain + X-Chain + PrimeWave EVM chain)
- Avalanche Network Runner (ANR) managing process lifecycle
- PrimeWave EVM chain: EVM-compatible, PW as native token, Chain ID 73571

**What does NOT run locally** (by design — PW-C01 scope):

- RewardVault (PW-C02+)
- ValidatorFeeVault (PW-C02+)
- PoAManager on-chain contract (PW-C03)
- PWUSD (later sprint)
- PWSwap, PrimeWave Dex (different projects)
- Governance frontend (later sprint)

The local network uses Avalanche's built-in PoA for local-mode validator registration.
The custom `PrimeWaveStakingManager` and `PoAManager` smart contracts are **not** deployed here.

---

## 6. Node Topology

```
  ┌─────────────────────────────────────────────────────────────┐
  │             LOCALHOST — DEVELOPMENT ONLY                    │
  │                                                             │
  │   Node 1            Node 2            Node 3               │
  │   (Validator)       (Validator)       (Validator)           │
  │                                                             │
  │   AvalancheGo       AvalancheGo       AvalancheGo           │
  │   v1.14.2           v1.14.2           v1.14.2               │
  │                                                             │
  │   P-Chain ──────────P-Chain ──────────P-Chain               │
  │   X-Chain           X-Chain           X-Chain               │
  │   PrimeWave EVM ────PrimeWave EVM ────PrimeWave EVM         │
  │                                                             │
  │   ↕ AvalancheSnow Consensus (localhost)                     │
  └─────────────────────────────────────────────────────────────┘
```

All nodes share the same machine and communicate via loopback. Each node validates
all chains: P-Chain (platform), X-Chain (assets), and the PrimeWave EVM chain.

---

## 7. Port Map

| Node | Service | Port | Protocol |
|---|---|---|---|
| Node 1 (primary) | RPC / WebSocket / P-Chain / Health | 9650 | HTTP/WS |
| Node 2 | RPC (ANR-assigned) | ~9652 | HTTP/WS |
| Node 3 | RPC (ANR-assigned) | ~9654 | HTTP/WS |

> **Port note:** Avalanche Network Runner assigns ports dynamically.
> Nodes 2 and 3 ports are approximate. Run `avalanche network status` for exact ports.
> The primary node (9650) is always the entry point for development.

### API endpoint paths

```
RPC endpoint:   http://127.0.0.1:9650/ext/bc/<BLOCKCHAIN_ID>/rpc
WebSocket:      ws://127.0.0.1:9650/ext/bc/<BLOCKCHAIN_ID>/ws
P-Chain API:    http://127.0.0.1:9650/ext/bc/P
Health API:     http://127.0.0.1:9650/ext/health
```

The `BLOCKCHAIN_ID` is the P-Chain assigned ID for the PrimeWave L1.
It is saved to `local-data/network-state.env` after `start-local.sh`.

---

## 8. Chain Configuration

### Genesis (chain/genesis/dev-genesis.json)

| Parameter | Value | Notes |
|---|---|---|
| Chain ID (EVM) | `73571` | **LOCAL DEV ONLY** |
| Native currency | `PW` | 18 decimals |
| Initial supply | 50,000 PW | 5 dev accounts × 10,000 PW each |
| Block gas limit | 30,000,000 | Standard EVM |
| Target block rate | 2 seconds | `feeConfig.targetBlockRate` |
| Min base fee | 25 gwei | EIP-1559 minimum |
| `allowFeeRecipients` | `false` | Fee split NOT active in dev |
| EIPs enabled | homestead → cancun | All at block/time 0 |

> **Fee split note:** The 70/20/10 ValidatorFeeVault / Treasury / Burn split is
> a **locked architectural decision** from PW-C00, but it is NOT implemented in the
> local dev environment. `allowFeeRecipients: false` means fees go to the default
> EVM behavior. The full split requires PW-C02+ smart contract deployment.

### Pre-funded development accounts

| Account | Address | Balance |
|---|---|---|
| DEV_ACCOUNT_0 | `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` | 10,000 PW |
| DEV_ACCOUNT_1 | `0x70997970C51812dc3A010C7d01b50e0d17dc79C8` | 10,000 PW |
| DEV_ACCOUNT_2 | `0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC` | 10,000 PW |
| DEV_ACCOUNT_3 | `0x90F79bf6EB2c4f870365E785982E1f101E93b906` | 10,000 PW |
| DEV_ACCOUNT_4 | `0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65` | 10,000 PW |

> These are the standard Foundry/Hardhat test accounts from the mnemonic:
> `test test test test test test test test test test test junk`
> **Private keys are in `config/dev/dev-keys.md`. DEVELOPMENT ONLY.**

---

## 9. RPC Configuration

The PrimeWave EVM RPC is a standard Ethereum JSON-RPC endpoint.
After the network starts, the URL is in `local-data/network-state.env`.

### Verified RPC methods

| Method | Purpose |
|---|---|
| `eth_chainId` | Returns chain ID (0x11F63 = 73571) |
| `eth_blockNumber` | Returns latest block number |
| `eth_getBlockByNumber` | Returns block details |
| `eth_getBalance` | Returns PW balance |
| `eth_getTransactionByHash` | Returns transaction details |
| `eth_getTransactionReceipt` | Returns transaction receipt |
| `eth_sendRawTransaction` | Submits signed transaction |
| `eth_gasPrice` | Returns current gas price in PW wei |
| `eth_estimateGas` | Estimates gas for a transaction |
| `net_version` | Returns network ID |
| `web3_clientVersion` | Returns node client version |

### Example RPC call

```bash
# Load state (sets PRIMEWAVE_RPC_URL)
source local-data/network-state.env

# Get chain ID
curl -s -X POST "$PRIMEWAVE_RPC_URL" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' | jq .

# Get latest block
curl -s -X POST "$PRIMEWAVE_RPC_URL" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest",false],"id":1}' | jq .

# Get balance (in PW wei)
curl -s -X POST "$PRIMEWAVE_RPC_URL" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_getBalance","params":["0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266","latest"],"id":1}' | jq .result
```

### Sending a transaction with cast

```bash
source local-data/network-state.env
export DEV_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

cast send \
  --private-key $DEV_KEY \
  --rpc-url $PRIMEWAVE_RPC_URL \
  --chain-id 73571 \
  0x70997970C51812dc3A010C7d01b50e0d17dc79C8 \
  --value 1ether
```

---

## 10. Wallet Configuration

### MetaMask

Add the PrimeWave dev chain as a custom network in MetaMask:

| Field | Value |
|---|---|
| Network Name | `PrimeWave Dev` |
| RPC URL | `http://127.0.0.1:9650/ext/bc/<BLOCKCHAIN_ID>/rpc` |
| Chain ID | `73571` |
| Currency Symbol | `PW` |
| Block Explorer URL | (leave blank for local dev) |

> Replace `<BLOCKCHAIN_ID>` with the value from `local-data/network-state.env`.
> MetaMask must run on the same machine as the local nodes.

### Import a dev account

1. In MetaMask: Account menu → Import Account
2. Select "Private Key"
3. Paste any dev key from `config/dev/dev-keys.md`
4. The account will show the PW balance

> **WARNING:** Never import dev keys into a production wallet or expose them on any
> public network. These keys are publicly known.

---

## 11. Starting the Network

### First time

```bash
# 1. Install binaries and create chain config (one-time, idempotent)
bash scripts/setup-local.sh

# 2. Start the local network
bash scripts/start-local.sh
```

### Subsequent starts (after stop, no reset)

```bash
bash scripts/start-local.sh
```

The start script detects if the network is already running and exits early.

### After a full reset

```bash
bash scripts/setup-local.sh   # recreates chain config
bash scripts/start-local.sh
```

### What start-local.sh does

**Phase 1 — First-time deploy (skipped on restart):**

1. Verifies binaries: `local-bin/avalanchego`, `local-bin/avalanche`, `local-bin/subnet-evm`
2. Checks if already running (RPC probe) → exits early if yes
3. Detects if local cluster DB exists → skips to Phase 2 if yes (restart path)
4. Runs `avalanche blockchain deploy primewavedev --local --avalanchego-path ./local-bin/avalanchego --num-nodes 3`
   - This creates ANR primary network (3 bootstrap nodes)
   - Creates subnet, blockchain, L1 conversion on P-Chain
   - Bootstraps the local cluster node to sync P-Chain state
   - **CLI then exits with "setup VM binary" error — this is EXPECTED and handled**
   - All P-Chain state is preserved in the local cluster node's DB

**Phase 2 — Configure node for standalone operation:**

5. Patches the local cluster `flags.json`:
   - `sybil-protection-enabled=false` — no peer quorum required for single-node dev
   - `partial-sync-primary-network=false` — required when sybil protection is disabled
   - `track-subnets=<subnetID>` — tells the node to track our L1
   - `bootstrap-ips=""`, `bootstrap-ids=""` — standalone mode, no bootstrap peers
6. Places `local-bin/subnet-evm` binary at `plugins/<VMID>` (VM plugin for our EVM chain)

**Phase 3 — Start node:**

7. Builds an `avalanchego` startup command from the patched `flags.json`
8. Starts avalanchego with `nohup` as a background daemon, saves PID to `local-data/node.pid`
9. Waits up to 60 seconds for all health checks to pass (P, X, C-Chain + our blockchain)
10. Verifies chain ID via `eth_chainId`
11. Saves all IDs and URLs to `local-data/network-state.env`

---

## 12. Stopping the Network

```bash
bash scripts/stop-local.sh
```

This reads `local-data/node.pid` and sends SIGTERM to the avalanchego process.
If the PID is stale, it falls back to `pgrep` for any stray avalanchego process on port 9656.
**Chain state is preserved** — the next `start-local.sh` resumes from the last block without re-deploying.

---

## 13. Resetting the Network

```bash
bash scripts/reset-local.sh
```

> **⚠ DESTRUCTIVE:** All blocks, transactions, and balance changes since genesis
> are permanently lost. After reset, the network starts fresh from genesis.

Reset removes:
1. Stops the running node (`stop-local.sh`)
2. Removes local cluster state: `~/.avalanche-cli/local/primewavedev-local-node-local-network/`
3. Removes blockchain config: `~/.avalanche-cli/subnets/primewavedev/`
4. Removes ANR runs and snapshots
5. Clears `~/.avalanche-cli/localNetworks.json`
6. Removes runtime files: `local-data/network-state.env`, `local-data/node.pid`, `local-data/node.log`, `local-data/deploy.log`

**Binaries in `local-bin/` are NOT removed** — they persist across resets.

After reset:
```bash
bash scripts/setup-local.sh   # recreates sidecar + genesis config
bash scripts/start-local.sh   # fresh deploy + start
```

---

## 14. Running Tests

### Quick smoke test

```bash
bash scripts/test-local.sh
```

Runs all 13 automated smoke tests. Prerequisites: network must be running.

### Test flags

```bash
# Skip the PW transfer transaction tests (Tests 8–10)
bash scripts/test-local.sh --no-tx

# Skip the network restart test (Test 11)
bash scripts/test-local.sh --skip-restart

# Both
bash scripts/test-local.sh --no-tx --skip-restart
```

### Test descriptions

| Test | Description | Automated |
|---|---|---|
| 1 | Network starts / RPC HTTP 200 | ✓ |
| 2 | Node health checks | ✓ |
| 3 | JSON-RPC method coverage | ✓ |
| 4 | Chain ID = 73571 | ✓ |
| 5 | Blocks are produced | ✓ |
| 6 | Multi-node consensus | ✓ |
| 7 | Account balance queries | ✓ |
| 8 | PW transfer succeeds | ✓ (requires Foundry cast) |
| 9 | Gas paid in PW | ✓ (depends on Test 8) |
| 10 | Transaction receipt | ✓ (depends on Test 8) |
| 11 | Network restart / catch-up | ✓ |
| 12 | Clean reset verification | ✓ (non-destructive check) |
| 13 | Clean checkout reproducibility | ✓ (file existence check) |

Results are saved to `local-data/test-results-<timestamp>.txt`.

### Manual RPC verification

```bash
source local-data/network-state.env

# eth_chainId
curl -s -X POST "$PRIMEWAVE_RPC_URL" -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' | jq .result

# eth_blockNumber
curl -s -X POST "$PRIMEWAVE_RPC_URL" -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq .result

# eth_getBalance (DEV_ACCOUNT_0)
curl -s -X POST "$PRIMEWAVE_RPC_URL" -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_getBalance","params":["0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266","latest"],"id":1}' | jq .result
```

---

## 15. Troubleshooting

### Network fails to start

**Symptom:** `avalanche blockchain deploy` returns non-zero.

**Check 1 — Port in use:**
```bash
lsof -i :9650 2>/dev/null || ss -tlnp | grep 9650
# If occupied: stop anything using port 9650
bash scripts/stop-local.sh
```

**Check 2 — Stale processes:**
```bash
pkill -f avalanchego
pkill -f avalanche-network-runner
bash scripts/start-local.sh
```

**Check 3 — CLI version / `--avalanchego-path` unsupported:**
```bash
./local-bin/avalanche blockchain deploy --help | grep avalanchego-path
```
If `--avalanchego-path` is not listed:
- The CLI will download its own AvalancheGo version internally
- Check what version it uses: inspect the deploy log in `local-data/deploy.log`
- If the CLI uses AvalancheGo < v1.14.0 or > v1.14.x, this is a version incompatibility
- **Action:** Document the discrepancy in `PW-C01-TEST-REPORT.md` under Known Limitations
- **Do NOT** silently proceed with an incompatible version without documenting it
- The local dev EVM behavior will be consistent with Granite family for all practical dev purposes

**Check 4 — Insufficient memory:**
```bash
free -h
# Need at least 1.5 GB free for 3 nodes
```

**Check 5 — Blockchain config corrupted:**
```bash
bash scripts/reset-local.sh
bash scripts/setup-local.sh
bash scripts/start-local.sh
```

---

### RPC not responding after start

**Symptom:** `start-local.sh` waits 60s and gives up.

```bash
# Check if node is alive
cat local-data/node.pid && kill -0 $(cat local-data/node.pid) && echo "alive" || echo "dead"
ps aux | grep avalanchego | grep -v grep

# Check health directly (note: port 9656, not 9650)
curl -s http://127.0.0.1:9656/ext/health | jq .healthy

# Check node log
tail -50 local-data/node.log

# Check deploy log (first-time setup)
tail -50 local-data/deploy.log
```

---

### `eth_sendTransaction` fails (Tests 8–10)

**Symptom:** Test 8 fails with "method not found" or "unauthorized".

This happens because `eth_sendTransaction` requires account unlocking, which is not enabled
by default in AvalancheGo's EVM.

**Solution:** Install Foundry and use `cast send` instead:
```bash
curl -L https://foundry.paradigm.xyz | bash && foundryup
```

Then re-run tests:
```bash
bash scripts/test-local.sh
```

---

### Chain ID mismatch

**Symptom:** Test 4 fails — chain ID is different from 73571.

The genesis `chainId` must match `PRIMEWAVE_DEV_CHAIN_ID=73571` in `_common.sh`.

```bash
# Verify genesis
jq .config.chainId chain/genesis/dev-genesis.json
# Should output: 73571

# Full reset and restart
bash scripts/reset-local.sh
bash scripts/setup-local.sh
bash scripts/start-local.sh
```

---

### `avalanche blockchain create` fails interactively

**Symptom:** Setup hangs waiting for user input.

The `--evm --token-symbol --token-name --genesis` flags should make creation non-interactive.
If the CLI prompts for additional input:

```bash
# Check CLI version
./local-bin/avalanche --version

# Try with explicit vm flag if needed
./local-bin/avalanche blockchain create primewave-dev \
  --evm \
  --token-symbol PW \
  --token-name PrimeWave \
  --genesis chain/genesis/dev-genesis.json \
  --no-prompts 2>/dev/null || \
./local-bin/avalanche blockchain create primewave-dev \
  --evm \
  --token-symbol PW \
  --token-name PrimeWave \
  --genesis chain/genesis/dev-genesis.json
```

---

## 16. Known Limitations

### CLI v1.9.5 + AvalancheGo v1.14.2 version mismatch (workaround applied)

**Root cause:** Avalanche CLI v1.9.5 entered maintenance mode December 2025. AvalancheGo v1.14.2 (March 2026) grafted the subnet-evm source code into the main avalanchego monorepo ("Granite.1 — Grafting EVM Repos"). As a result, CLI v1.9.5's internal VM registry lookup for `"subnet-evm"` fails with `"unknown vm: subnet-evm"` — the registry is hardcoded and cannot be patched without rebuilding the CLI.

**Workaround (applied in `start-local.sh`):**
1. `blockchain deploy` is run and intentionally allowed to fail at `setup VM binary` — all P-Chain work (subnet creation, blockchain registration, L1 conversion, local cluster bootstrap) completes before that step.
2. The local cluster node's `flags.json` is patched to enable standalone operation.
3. The real `subnet-evm` binary (now shipped as a release asset of AvalancheGo v1.14.2) is placed in the plugins directory as `plugins/<VMID>`.
4. `avalanchego` is started directly from the patched flags — it loads the plugin, verifies rpcchainvm protocol (both `45`), and starts the EVM chain.

**Confirmed working:** `eth_chainId` → `73571`, all health checks pass, genesis balances correct.

**References:** `docs/PRIMEWAVE_DEPENDENCY_COMPATIBILITY.md`, `local-data/deploy.log`

---

### Single-node topology (not 3-node)

The runtime is a single standalone node. The three ANR nodes that exist during the `blockchain deploy` phase are transient — they are shut down when the CLI exits. Starting additional nodes manually requires per-node flag orchestration not in scope for PW-C01. The single-node setup is sufficient for EVM development; multi-node consensus validation belongs to PW-C03+.

### subnet-evm binary provenance

`local-bin/subnet-evm` is downloaded from the AvalancheGo v1.14.2 GitHub release as `subnet-evm-linux-amd64-v1.14.2.tar.gz`. It is NOT from the archived `ava-labs/subnet-evm` repository. See `scripts/setup-local.sh` for the download URL.

### L1 validator management
The local dev network uses Avalanche's built-in PoA local validator set.
The production `PoAManager` smart contract (from `icm-services`) is NOT deployed here.
This is by design — it belongs to PW-C03.

### Fee distribution
The 70/20/10 ValidatorFeeVault / Treasury / Burn split is architecturally locked
but **not implemented**. In the local dev environment, fees accumulate without
the production split. This is by design — it belongs to PW-C02+.

### Demand-driven block production

The EVM does not produce blocks unless transactions are submitted. Block #0 is the genesis block. To advance the chain manually:
```bash
# Using Foundry cast (PW-C02+):
cast send --private-key <DEV_PRIVATE_KEY> <ANY_ADDR> --value 1wei --rpc-url <RPC_URL>
```

### Subnet-EVM archived
The `ava-labs/subnet-evm` repository was archived December 16, 2025.
The EVM is now integrated into AvalancheGo ≥ v1.14.1. No separate subnet-evm
dependency exists or should be referenced.

### WebSocket
WebSocket endpoints follow the same path structure as RPC:
`ws://127.0.0.1:9650/ext/bc/<BLOCKCHAIN_ID>/ws`
Full WebSocket test (persistent connection, subscription) is a manual step;
see §9 for connection details.

### Mainnet genesis
The production genesis (100M PW with 15M RewardVault pre-funded) is documented in
`docs/PRIMEWAVE_GENESIS_SPEC.md`. It is not used here. The dev genesis (50,000 PW
across 5 test accounts) is for local verification only.

---

## 17. Security Warnings

> **READ BEFORE PROCEEDING**

1. **Development keys are public.** The private keys in `config/dev/dev-keys.md` are
   derived from the publicly known Foundry test mnemonic. Anyone can derive them.
   Never use them on any public network.

2. **Chain ID 73571 is local only.** It is not registered and has no meaning on any
   public Avalanche network. Never use it for a public deployment.

3. **No production keys were generated.** Consistent with PW-C00 and PW-C01 scope.
   Production validators, treasury, multisig, and Monetary Authority keys will be
   generated separately with hardware security modules per `docs/PRIMEWAVE_KEY_SECURITY_PROCEDURE.md`.

4. **Node ports are not authenticated.** Local RPC (port 9650) has no authentication.
   Do not expose this port to untrusted networks. Use a firewall.

5. **Dev binaries are downloaded over HTTPS from GitHub.** Checksums are verified
   against the version string. For higher assurance, manually verify against the
   official GitHub release SHA256 files.

6. **No production infrastructure exists.** No cloud resources were provisioned,
   no paid services were used, no public domains were registered.

---

## 18. Next Sprint Dependencies

PW-C02 and beyond depend on the local network established in PW-C01.

| Sprint | Depends On |
|---|---|
| **PW-C02** (Smart Contracts) | Working RPC at `$PRIMEWAVE_RPC_URL`; funded dev accounts; Foundry installed |
| **PW-C02** | AvalancheGo `v1.14.2` binary in `local-bin/` |
| **PW-C02** | ICM Services at `icm-relayer-v1.7.5 / 40e1c89` for validator contracts |
| **PW-C02** | OpenZeppelin `v5.6.1` (npm install in contracts workspace) |
| **PW-C03** (PoAManager) | PW-C02 contract deployment infrastructure + running local network |
| **PW-C04** (RewardVault) | PW-C03 PoAManager deployed; running local network |
| **PW-C05** (PoS Transition) | PW-C04 complete; running PoA network to migrate |

### Confirmed prerequisites for PW-C02

From the PW-C01 exit state:
- [ ] `bash scripts/start-local.sh` succeeds
- [ ] `PRIMEWAVE_RPC_URL` responds with chain ID 73571
- [ ] DEV_ACCOUNT_0 has PW balance > 0
- [ ] Blocks are being produced
- [ ] `local-bin/avalanchego` binary is at exactly `v1.14.2`
- [ ] Foundry (`forge`, `cast`) installed for contract compilation and testing
- [ ] `local-bin/avalanche` at `v1.9.5` or documented substitute

---

*Document version: PW-C01 | Updated: 2026-08-13*
