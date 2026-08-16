---
name: PrimeWave Chain PW-C15
description: Testnet pre-launch sprint; arch docs + key ceremony + blocker fixes + STEP 3 COMPLETE — PrimeWave is a live sovereign L1 on Fuji
---

# PW-C15 — Testnet Pre-Launch Sprint

## State
STEP 3 COMPLETE (2026-08-16). PrimeWave is a sovereign L1 on Fuji. Remaining steps: validator node setup (Steps 7–10).

## Fuji L1 Identifiers (PERMANENT — record everywhere)

| Field | Value |
|---|---|
| Subnet ID | `ovXTQNjfug8bipjnqnSKieZFdtHid2amTQnrbibg4kYQtrLbv` |
| Blockchain ID | `22iFuL8GqPYbtnPKNFrq7AzoDfv3FYwq8T93GubRi12LQVjLni` |
| VM ID | `rXJjKFtAVSmpN77uiTTUvHuMQtE1eAX3vJAuZj2kDdjY6apL7` |
| Conversion ID | `3wDXKHGn9AggJmMfSZXhE2TpMtrghem3ymZ6RPm48KQpiECW4` |
| ConvertSubnetToL1Tx ID | `28BAWiPbUp6HS8AEXYZcu7uFxPH1PBScN7HZZGS4fy65zjJDTH` |
| Manager Address | `0x0feedc0de0000000000000000000000000000000` |
| Chain ID | 77 |
| Token | PW |

On-chain confirmation: `isPermissioned: false`, `managerAddress: 0x0feedc0de...`

## CLI Blockchain Name
`primewavetestnet` (no hyphen — Avalanche CLI rejects hyphens in blockchain names)

## Deployer (new key, 2026-08-16 replacement)
- C-Chain: `0xB518397E3D65a0E7475635F01C225E9426a76F11`
- P-Chain: `P-fuji17c7fuusyh76r74zwge4sl0nc3458xdkv477adz`
- CLI key: `~/.avalanche-cli/key/testnet-deployer.pk` (EPHEMERAL — back up before container restart)
- P-Chain balance remaining: 0.019869482 AVAX
- C-Chain balance: 0.499999999 AVAX (for contract deployment in Step 8)

## Step 3 Blockers Encountered and How Resolved
1. **Blockchain name** — hyphens rejected by CLI → used `primewavetestnet`
2. **Interactive ICM prompt** in `blockchain create` → manually constructed sidecar.json + genesis, bypassed `blockchain create` entirely
3. **`--num-bootstrap-validators` + `--bootstrap-filepath` mutually exclusive** → removed `--num-bootstrap-validators`
4. **`Balance` field format** — bootstrap-validators.json had `0.375` float (AVAX); CLI expects uint64 nAVAX → changed to `370000000`
5. **ConvertSubnetToL1Tx interactive prompt** — `^D` EOF in non-TTY → used Python `pty` module + `blockchain convert --verify-input=false`

## Step 3 Deploy Sequence (for reference)
```bash
# 1. Manually create sidecar + copy genesis to ~/.avalanche-cli/subnets/primewavetestnet/
# 2. blockchain deploy (CreateSubnetTx + CreateChainTx only; ConvertSubnetToL1Tx needs PTY)
# 3. blockchain convert via Python pty with --verify-input=false --convert-only
```

## Critical Findings (architectural, persist forever)

### PoAManager predeploy address
`0x0Feedc0de0000000000000000000000000000000` — Avalanche CLI standard predeploy for ALL L1 chains.
Confirmed from `~/.avalanche-cli/subnets/primewavedev/sidecar.json`.
EIP-55 checksum form (required by Solidity): `0x0Feedc0de0000000000000000000000000000000`

### PWVR.validatorManager is IMMUTABLE
`PrimeWaveValidatorRegistry.validatorManager` is `public immutable` — no setter exists.
Must receive `0x0Feedc0de0000000000000000000000000000000` at constructor time.

### --convert-only flag behavior
Skips CLI's built-in PoA manager EVM contract setup (we use our own `DeployTestnet.s.sol` in Step 8).
Does NOT skip ConvertSubnetToL1Tx itself. This is correct for our flow.

### DeployTestnet.s.sol must run AFTER L1 is live
The script references `POA_MANAGER_ADDR` — live as genesis alloc from block 0.
Cannot run before the L1 chain exists (chainid 77 guard will fail anyway).

### cast wallet new --json outputs an ARRAY
Format: `[{"address":"0x...","private_key":"0x..."}]` — use `d[0]['address']`, not `d['address']`.

### FeeDistributor address (new deployer, nonce=4)
`0x27B15970700daC632f0814522118A1c3B200d971`

## V6–V9 Validators
- V6 (152.53.66.93):   NodeID-144dTzcL2vgpbKzX943xy5pEF3M8oGyiQ
- V7 (152.53.66.201):  NodeID-cwX3HFmaR5QmbxuZaDJCXAueJeyewjni
- V8 (159.195.44.104): NodeID-7DLuPUaMiDbyVoZ6P92RQdNRFS81cpYb5
- V9 (159.195.47.126): NodeID-9TiHzx7DZgtCjB9pqyY6db55pZgVZELvJ
AvalancheGo v1.15.0 (rpcchainvm=46). Plugins dir: /opt/avalanchego/plugins/ (EMPTY — subnet-evm not yet installed).

## CRITICAL BLOCKER FOR STEP 7: subnet-evm rpcchainvm=46
Public subnet-evm releases cap at rpcchainvm=44 (v0.8.0-fuji for AvalancheGo v1.14.0).
Validators need rpcchainvm=46 binary. Source: custom/internal build — NOT from ava-labs/subnet-evm GitHub releases.
VMID for our chain: `rXJjKFtAVSmpN77uiTTUvHuMQtE1eAX3vJAuZj2kDdjY6apL7`
The binary filename in /opt/avalanchego/plugins/ must match this VMID exactly.

## Remaining Steps (Day-0 Checklist)
- Step 7: Install rpcchainvm=46 subnet-evm on V6–V9 + configure track-subnets + restart AvalancheGo
- Step 8: Deploy contracts via DeployTestnet.s.sol (needs TESTNET_DEPLOYER_KEY env var from CLI key file)
- Step 9: Initialize PoA ValidatorManager (`avalanche contract initValidatorManager primewavetestnet`)
- Step 10: Register validators in PoA manager

## Files Updated in Step 3
- `config/testnet/bootstrap-validators.json` — Balance changed to 370000000 nAVAX
- `config/testnet/node-config.json` — SubnetID placeholder filled
- `local-data/testnet-key-addresses.env` — SubnetID, BlockchainID, VM_ID, Conversion_ID added
- `docs/PW-C15-STEP-3-DEPLOYMENT-REPORT.md` — full deployment report

## Deployer Replacement (2026-08-16)
ORIGINAL deployer 0x44A37aF5... — key permanently lost (ephemeral ~/.primewave-keys/). 2.0 AVAX stranded.
Report: docs/PW-C15-DEPLOYER-REPLACEMENT-REPORT.md
