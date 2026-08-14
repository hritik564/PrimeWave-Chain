---
name: PrimeWave Chain PW-C14
description: C14 Public Testnet + Deployment Rehearsal — all deliverables, constraints, and pitfalls
---

## Status
C14 COMPLETE (infrastructure preparation phase).
External testnet activation pending: cloud servers, Fuji AVAX, DNS, TLS, key ceremony.

## Testnet Identity
- Chain ID: **77777** (verify uniqueness on chainlist.org before final launch)
- Dev Chain ID: 73571 (never reuse for testnet)
- Blockchain ID: generated at Fuji P-Chain subnet creation (TBD)
- AvalancheGo: v1.14.2 (pinned)

## Hex Allocations (100M PW total, all verified)
| Recipient        | Amount  | Hex                        |
|------------------|---------|----------------------------|
| Deployer         | 16M PW  | 0xd3c21bcecceda10000000     |
| Treasury         | 25M PW  | 0x14adf4b7320334b9000000    |
| Team             | 20M PW  | 0x108b2a2c28029094000000    |
| Community        | 20M PW  | 0x108b2a2c28029094000000    |
| Ecosystem        | 10M PW  | 0x84595161401484a000000     |
| Reserve          | 9M PW   | 0x771d2fa45345aa9000000     |
| **Total**        | **100M**| 0x52b7d2dcc80cd2e4000000    |

## Key Deliverables
- `config/testnet/genesis-template.json` — genesis with Chain ID 77777, NativeMinter disabled
- `config/testnet/chain-config.json`, `node-config.json`, `allocations.md`
- `scripts/testnet/` — 7 operational scripts (deploy-contracts, generate-validator-keys, validate-testnet-genesis, testnet-health-check, setup-testnet-node, backup-testnet-db, restore-testnet-db)
- `deploy/testnet/systemd/` — 4 systemd service files
- `deploy/testnet/nginx/` — rpc.conf, explorer.conf
- `deploy/testnet/prometheus/` — prometheus.yml, alert-rules.yml
- `deploy/testnet/env/` — env templates for indexer and keeper
- `contracts/script/DeployTestnet.s.sol` — chain-ID-verified testnet deployment script
- 10 required docs in `docs/PW-C14-*.md`
- PWCScan: `VITE_NETWORK_LABEL` env var → shows orange "🧪 Testnet" badge in header + home page

## Pitfalls
- DeployTestnet.s.sol: All Solidity string literals must use ASCII only (no Unicode em dashes — use `-` not `—`)
- Fuzz test fix: `testFuzz_F4_RecipientChange_OnlyNewCanClaim` needed `vm.assume(newRecipient != address(this))` — the test contract's own address (0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496) has no payable receive(), so ETH transfer to it reverts with "VFV: transfer failed"
- DeployTestnet.s.sol constructor signatures differ from the naive guess — use DevDeploy.s.sol as the reference (same address-prediction pattern, same constructor arities)
- ValidatorFeeVault: `constructor(address _protocolAdmin)` takes 1 arg (predicted registry address)
- PrimeWaveValidatorRegistry: `constructor(address _protocolAdmin, address _validatorManager, address _feeVault)` — 3 args
- RewardVault: `constructor(address _admin, uint256 _initialRate)` — 2 args
- PrimeWaveTimelock: `constructor(address _proposer)` — 1 arg
- DevTreasury: `constructor(address _feeDistributor)` — 1 arg

## Regression Baseline (C14 COMPLETE)
- Forge: 792/792 ✅
- Indexer Jest: 57/57 ✅
- Keeper Jest: 20/20 ✅

## Critical Constraints
- NativeMinter DISABLED in genesis template (enforced)
- Chain ID 77777 enforced in DeployTestnet.s.sol (refuses wrong chain)
- VITE_NETWORK_LABEL must be "Testnet" for testnet builds (never "Mainnet")
- DO NOT start C15 automatically after C14
