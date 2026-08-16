# PW-C15 Step 3 — Fuji L1 Deployment Report

**Date:** 2026-08-16  
**Operator:** Automated ceremony (Replit agent)  
**Status: ✅ COMPLETE — PrimeWave is a sovereign Avalanche L1 on Fuji**

---

## Summary

Step 3 of the Day-0 ceremony created the PrimeWave blockchain on Fuji's P-Chain and converted it
from a permissioned subnet to a sovereign L1 via `ConvertSubnetToL1Tx`. All three P-Chain
transactions were committed and verified. The PoA ValidatorManager predeploy address
(`0x0FEEDC0DE...`) is recorded on-chain as the manager.

---

## Chain Identifiers (Fuji Testnet)

| Field | Value |
|---|---|
| **Subnet ID** | `ovXTQNjfug8bipjnqnSKieZFdtHid2amTQnrbibg4kYQtrLbv` |
| **Blockchain ID** | `22iFuL8GqPYbtnPKNFrq7AzoDfv3FYwq8T93GubRi12LQVjLni` |
| **VM ID** | `rXJjKFtAVSmpN77uiTTUvHuMQtE1eAX3vJAuZj2kDdjY6apL7` |
| **Conversion ID** | `3wDXKHGn9AggJmMfSZXhE2TpMtrghem3ymZ6RPm48KQpiECW4` |
| **Manager Address (PoA predeploy)** | `0x0feedc0de0000000000000000000000000000000` |
| **Manager Chain ID** | `22iFuL8GqPYbtnPKNFrq7AzoDfv3FYwq8T93GubRi12LQVjLni` |
| **Blockchain name (CLI)** | `primewavetestnet` |
| **Chain ID** | `77` |
| **Token** | `PW` |

---

## P-Chain Transactions

| Tx | ID | Fee |
|---|---|---|
| `CreateSubnetTx` | `ovXTQNjfug8bipjnqnSKieZFdtHid2amTQnrbibg4kYQtrLbv` | 0.000010278 AVAX |
| `CreateChainTx` | `22iFuL8GqPYbtnPKNFrq7AzoDfv3FYwq8T93GubRi12LQVjLni` | 0.000024458 AVAX |
| `ConvertSubnetToL1Tx` | `28BAWiPbUp6HS8AEXYZcu7uFxPH1PBScN7HZZGS4fy65zjJDTH` | 0.000087512 AVAX |

**Total P-Chain fees:** 0.000122248 AVAX  
**Validator balance locked (4 × 0.37 AVAX):** 1.480000000 AVAX  
**P-Chain balance remaining:** 0.019869482 AVAX

---

## Bootstrap Validators Registered

| NodeID | Weight | Balance (nAVAX) |
|---|---|---|
| `NodeID-144dTzcL2vgpbKzX943xy5pEF3M8oGyiQ` (V6) | 100 | 370,000,000 |
| `NodeID-cwX3HFmaR5QmbxuZaDJCXAueJeyewjni` (V7) | 100 | 370,000,000 |
| `NodeID-7DLuPUaMiDbyVoZ6P92RQdNRFS81cpYb5` (V8) | 100 | 370,000,000 |
| `NodeID-9TiHzx7DZgtCjB9pqyY6db55pZgVZELvJ` (V9) | 100 | 370,000,000 |

---

## On-Chain Verification (Fuji P-Chain)

```json
{
  "isPermissioned": false,
  "controlKeys": ["P-fuji17c7fuusyh76r74zwge4sl0nc3458xdkv477adz"],
  "threshold": "1",
  "locktime": "0",
  "subnetTransformationTxID": "11111111111111111111111111111111LpoYY",
  "conversionID": "3wDXKHGn9AggJmMfSZXhE2TpMtrghem3ymZ6RPm48KQpiECW4",
  "managerChainID": "22iFuL8GqPYbtnPKNFrq7AzoDfv3FYwq8T93GubRi12LQVjLni",
  "managerAddress": "0x0feedc0de0000000000000000000000000000000"
}
```

`isPermissioned: false` ✅ — Sovereign L1, not a permissioned subnet  
`managerAddress: 0x0feedc0de...` ✅ — PoA predeploy address confirmed on-chain

---

## Deployer Balances (post-deployment)

| Chain | Address | Balance |
|---|---|---|
| C-Chain | `0xB518397E3D65a0E7475635F01C225E9426a76F11` | 0.499999999 AVAX |
| P-Chain | `P-fuji17c7fuusyh76r74zwge4sl0nc3458xdkv477adz` | 0.019869482 AVAX |
| X-Chain | — | 0 AVAX |

---

## Issues Encountered and Resolutions

### 1. Blockchain name rejected — hyphens not allowed
**Issue:** `avalanche blockchain deploy primewave-testnet` failed: "illegal name character: only letters allowed."  
**Resolution:** Used `primewavetestnet` (no hyphen) as the CLI local identifier. The on-chain blockchain
name recorded on Fuji is also `primewavetestnet`. The Day-0 checklist had `primewave-testnet` — this
was the original intent, but the CLI constraint required the change. Functionally identical.

### 2. Interactive `blockchain create` prompt (ICM question)
**Issue:** `avalanche blockchain create` presented an interactive arrow-key menu asking about
ICM/interoperability — non-drivable from a non-TTY shell.  
**Resolution:** Bypassed `blockchain create` entirely by manually constructing the CLI sidecar
(`~/.avalanche-cli/subnets/primewavetestnet/sidecar.json`) and copying the genesis file.
All fields match what the CLI would have created.

### 3. `--num-bootstrap-validators` and `--bootstrap-filepath` are mutually exclusive
**Issue:** The Day-0 checklist used both flags together; the CLI rejects them in combination.  
**Resolution:** Removed `--num-bootstrap-validators 4` — the number is implied by the 4-entry
bootstrap-validators.json file.

### 4. `Balance` field format: AVAX float vs nAVAX uint64
**Issue:** `bootstrap-validators.json` had `"Balance": 0.375` (AVAX, float). The CLI's
`SubnetValidator.Balance` field is `uint64` (nAVAX). Unmarshal error.  
**Resolution:** Changed to `370000000` (nAVAX = 0.37 AVAX) — slightly less than 0.375 to leave
~0.02 AVAX buffer for ConvertSubnetToL1Tx fees. Actual fee was 0.000087512 AVAX.

### 5. `ConvertSubnetToL1Tx` EOF prompt on `blockchain deploy --convert-only`
**Issue:** `blockchain deploy` succeeded for CreateSubnetTx + CreateChainTx but then prompted
interactively for the conversion step. Non-TTY shell got EOF (`^D`).  
**Resolution:** Used the dedicated `avalanche blockchain convert primewavetestnet` command with
`--verify-input=false` and ran it via Python's `pty` module to emulate a TTY. Conversion
completed successfully.

---

## Files Updated in This Step

| File | Change |
|---|---|
| `config/testnet/bootstrap-validators.json` | `Balance` changed from `0.375` float → `370000000` uint64 (nAVAX) |
| `config/testnet/node-config.json` | `__REPLACE_TESTNET_SUBNET_ID__` → `ovXTQNjfug8bipjnqnSKieZFdtHid2amTQnrbibg4kYQtrLbv` |
| `local-data/testnet-key-addresses.env` | Added `TESTNET_SUBNET_ID`, `TESTNET_BLOCKCHAIN_ID`, `TESTNET_VM_ID`, `TESTNET_CONVERSION_ID` |
| `~/.avalanche-cli/subnets/primewavetestnet/` | CLI sidecar + genesis (ephemeral — in CLI home dir) |

---

## Expected Fuji RPC Endpoint (once validators track the chain)

```
https://api.avax-test.network/ext/bc/22iFuL8GqPYbtnPKNFrq7AzoDfv3FYwq8T93GubRi12LQVjLni/rpc
```

---

## What Is NOT Done Yet (Separate Steps)

These were intentionally not executed in this step per the Day-0 protocol:

| Step | Description |
|---|---|
| Step 7 | Install subnet-evm plugin on V6–V9 (rpcchainvm=46 compatible binary needed) |
| Step 7 | Configure `track-subnets` on all 4 validator nodes, restart AvalancheGo |
| Step 8 | Deploy Solidity contracts (`DeployTestnet.s.sol`) via `TESTNET_DEPLOYER_KEY` env var |
| Step 9 | Initialize PoA ValidatorManager via `initValidatorManager` |
| Step 10 | Register validators in PoA manager |

### Critical Pre-Step-7 Blocker: subnet-evm rpcchainvm=46

The validators run AvalancheGo v1.15.0 (rpcchainvm=46). The public subnet-evm releases
cap at rpcchainvm=44 (v0.8.0-fuji for AvalancheGo v1.14.0). A custom or internal subnet-evm
build with rpcchainvm=46 must be obtained and installed in `/opt/avalanchego/plugins/` on
all four validators before they can run the PrimeWave chain.

---

## Verification Commands for Operator

```bash
# Confirm L1 state on Fuji P-Chain
curl -s -X POST https://api.avax-test.network/ext/bc/P \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"platform.getSubnet","params":{"subnetID":"ovXTQNjfug8bipjnqnSKieZFdtHid2amTQnrbibg4kYQtrLbv"}}' | python3 -m json.tool

# Confirm blockchain on Fuji P-Chain
# SubnetID ovXTQ... should appear in getBlockchains results with name primewavetestnet

# Deployer key on Fuji
./local-bin/avalanche key list --fuji --keys testnet-deployer
```
