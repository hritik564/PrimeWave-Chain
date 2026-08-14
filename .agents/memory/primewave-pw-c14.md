---
name: PrimeWave Chain PW-C14
description: C14 Public Testnet + Deployment Rehearsal — all deliverables, constraints, and pitfalls
---

## Status
C14 COMPLETE (infrastructure preparation phase) + post-C14 chain ID update applied.
External testnet activation pending: cloud servers, Fuji AVAX, DNS, TLS, key ceremony.

## Testnet Identity
- Chain ID: **77** (CURRENT — changed from 77777 post-C14)
- Previous Testnet Chain ID: **77777** (historical; genesis regenerated)
- Dev Chain ID: 73571 (never reuse for testnet)
- Blockchain ID: generated at Fuji P-Chain subnet creation (TBD — will differ from dev 2F3BHmNJWP4DNaBbMFQog3TvfcF6GRY7PX99r7Xzae4cRwAv6a)
- AvalancheGo: v1.14.2 (pinned)
- 77 in hex: 0x4d

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
- `config/testnet/genesis-template.json` — genesis with Chain ID **77**, NativeMinter disabled
- `config/testnet/chain-config.json`, `node-config.json`, `allocations.md`
- `scripts/testnet/` — 7 operational scripts (deploy-contracts, generate-validator-keys, validate-testnet-genesis, testnet-health-check, setup-testnet-node, backup-testnet-db, restore-testnet-db)
- `deploy/testnet/systemd/` — 4 systemd service files
- `deploy/testnet/nginx/` — rpc.conf, explorer.conf
- `deploy/testnet/prometheus/` — prometheus.yml, alert-rules.yml
- `deploy/testnet/env/` — env templates for indexer, keeper, and pwcscan (chain ID 77 in all)
- `contracts/script/DeployTestnet.s.sol` — enforces chain ID == 77
- 10 required docs in `docs/PW-C14-*.md` (all updated to Chain ID 77, history preserved)
- PWCScan: `VITE_NETWORK_LABEL` env var → shows orange "🧪 Testnet" badge; `VITE_CHAIN_ID=77`

## Pitfalls
- DeployTestnet.s.sol: All Solidity string literals must use ASCII only (no Unicode em dashes — use `-` not `—`)
- Fuzz test fix: `testFuzz_F4_RecipientChange_OnlyNewCanClaim` needed `vm.assume(newRecipient != address(this))` — the test contract's own address (0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496) has no payable receive(), so ETH transfer to it reverts with "VFV: transfer failed"
- DeployTestnet.s.sol constructor signatures differ from the naive guess — use DevDeploy.s.sol as the reference (same address-prediction pattern, same constructor arities)
- ValidatorFeeVault: `constructor(address _protocolAdmin)` takes 1 arg (predicted registry address)
- PrimeWaveValidatorRegistry: `constructor(address _protocolAdmin, address _validatorManager, address _feeVault)` — 3 args
- RewardVault: `constructor(address _admin, uint256 _initialRate)` — 2 args
- PrimeWaveTimelock: `constructor(address _proposer)` — 1 arg
- DevTreasury: `constructor(address _feeDistributor)` — 1 arg
- Genesis alloc validation: alloc entries have `_label` sub-keys; validate with `if 'balance' in v`, not by filtering key names
- Chain ID change (77777→77): changing genesis regenerates blockchain identity — old dev blockchain ID 2F3BHmNJWP4DNaBbMFQog3TvfcF6GRY7PX99r7Xzae4cRwAv6a must NOT be reused for testnet

## Health Check Expected Values (Chain ID 77)
- `eth_chainId` → `0x4d`
- `net_version` → `77`
- Health check FAILS if it sees 73571 or any other chain

## Regression Baseline (post chain ID update)
- Forge: 792/792 ✅
- Indexer Jest: 57/57 ✅
- Keeper Jest: 20/20 ✅

## Critical Constraints
- NativeMinter DISABLED in genesis template (enforced)
- Chain ID **77** enforced in DeployTestnet.s.sol (refuses wrong chain)
- Chain ID 73571 = dev ONLY — never change
- VITE_NETWORK_LABEL must be "Testnet" for testnet builds (never "Mainnet")
- DO NOT start C15 automatically
