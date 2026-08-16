# PrimeWave Testnet — MetaMask Connection Guide

**Status:** LIVE as of 2026-08-16  
**Chain:** PrimeWave L1 on Fuji Testnet  
**Chain ID:** 77 (0x4d)  
**Token:** PW  

---

## Quick Add to MetaMask

### Step 1 — Open MetaMask → Settings → Networks → Add a network

Or use the "Add Network" button when prompted.

### Step 2 — Enter the following details

| Field | Value |
|---|---|
| **Network Name** | PrimeWave Testnet |
| **New RPC URL** | `http://159.195.47.126/ext/bc/22iFuL8GqPYbtnPKNFrq7AzoDfv3FYwq8T93GubRi12LQVjLni/rpc` |
| **Chain ID** | `77` |
| **Currency Symbol** | `PW` |
| **Block Explorer URL** | *(leave blank for now — PWCScan setup pending contract deploy)* |

### Step 3 — Save and switch to the PrimeWave Testnet network

---

## Backup RPC Endpoints

Use these if the primary is unavailable:

| Validator | RPC URL |
|---|---|
| V9 (Primary) | `http://159.195.47.126/ext/bc/22iFuL8GqPYbtnPKNFrq7AzoDfv3FYwq8T93GubRi12LQVjLni/rpc` |
| V7 (Backup 1) | `http://152.53.66.201/ext/bc/22iFuL8GqPYbtnPKNFrq7AzoDfv3FYwq8T93GubRi12LQVjLni/rpc` |
| V6 (Backup 2) | `http://152.53.66.93/ext/bc/22iFuL8GqPYbtnPKNFrq7AzoDfv3FYwq8T93GubRi12LQVjLni/rpc` |
| V8 (Backup 3) | `http://159.195.44.104/ext/bc/22iFuL8GqPYbtnPKNFrq7AzoDfv3FYwq8T93GubRi12LQVjLni/rpc` |

> **Note:** These are bare HTTP endpoints (no TLS). Use only on testnet. Do not send mainnet funds or sensitive operations.

---

## Chain Identifiers (permanent — on-chain and immutable)

| Identifier | Value |
|---|---|
| Subnet ID | `ovXTQNjfug8bipjnqnSKieZFdtHid2amTQnrbibg4kYQtrLbv` |
| Blockchain ID | `22iFuL8GqPYbtnPKNFrq7AzoDfv3FYwq8T93GubRi12LQVjLni` |
| VM ID | `rXJjKFtAVSmpN77uiTTUvHuMQtE1eAX3vJAuZj2kDdjY6apL7` |
| Chain ID | `77` |
| Network | Fuji Testnet (Avalanche network ID 5) |

---

## Verifying the Connection

After adding the network, open the MetaMask browser console or use any JSON-RPC tool:

```bash
# Verify chain ID
curl -s -X POST http://159.195.47.126/ext/bc/22iFuL8GqPYbtnPKNFrq7AzoDfv3FYwq8T93GubRi12LQVjLni/rpc \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'
# Expected: {"result":"0x4d"}  (77 decimal)

# Check latest block
curl -s -X POST http://159.195.47.126/ext/bc/22iFuL8GqPYbtnPKNFrq7AzoDfv3FYwq8T93GubRi12LQVjLni/rpc \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
# Expected: {"result":"0x..."} (a growing block number)
```

---

## Validator Node Details

| Validator | IP | Node ID |
|---|---|---|
| V6 | 152.53.66.93 | NodeID-144dTzcL2vgpbKzX943xy5pEF3M8oGyiQ |
| V7 | 152.53.66.201 | NodeID-cwX3HFmaR5QmbxuZaDJCXAueJeyewjni |
| V8 | 159.195.44.104 | NodeID-7DLuPUaMiDbyVoZ6P92RQdNRFS81cpYb5 |
| V9 | 159.195.47.126 | NodeID-9TiHzx7DZgtCjB9pqyY6db55pZgVZELvJ |

All validators run AvalancheGo v1.15.0-fuji [rpcchainvm=46] with the patched subnet-evm v1.15.0 binary.

---

## Technical Notes

### Genesis Patch Applied
The on-chain genesis has `"warpConfig":{"blockTimestamp":0}` but no `durangoTimestamp`, which causes stock subnet-evm v1.15.0 to reject the genesis with:
```
failed to verify genesis: invalid precompile upgrades: warp cannot be activated before Durango
```
The patched binary (`graft/subnet-evm/precompile/contracts/warp/config.go`, one-line fix) allows warp activation when `durangoTimestamp` is not explicitly set. The patch is applied to all 4 validators.

### Block Production
First block was produced by a manual kick transaction on 2026-08-16. Subsequent blocks are produced automatically by the consensus engine.

### Service
All validators run as `avalanche` user via `primewave-testnet-node.service` (systemd). The chain config is at:
- `/home/avalanche/.avalanchego/configs/chains/22iFuL8GqPYbtnPKNFrq7AzoDfv3FYwq8T93GubRi12LQVjLni/config.json`
- `/home/avalanche/.avalanchego/configs/chains/22iFuL8GqPYbtnPKNFrq7AzoDfv3FYwq8T93GubRi12LQVjLni/upgrade.json`
