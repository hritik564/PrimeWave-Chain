---
name: Avalanche dependency surprises
description: Two key Avalanche repos were archived in late 2025; their successors and the corrected dependency stack for EVM L1 development
---

## Rule
Never reference `ava-labs/icm-contracts` or `ava-labs/subnet-evm` in PrimeWave code or docs.

## What happened
- `ava-labs/icm-contracts` — **archived December 3, 2025**. Successor: `ava-labs/icm-services` (contracts live in `icm-contracts/` subdir). Pin to tag `icm-relayer-v1.7.5` / commit `40e1c89`.
- `ava-labs/subnet-evm` — **archived December 16, 2025**. Code merged into `ava-labs/avalanchego` at v1.14.1 ("Granite.1 — Grafting EVM Repos"). No longer a separate dependency.

## Correct stack (as of Aug 13, 2026)
| Dependency | Pinned version |
|---|---|
| AvalancheGo (node + EVM) | v1.14.2 |
| ICM Services contracts | icm-relayer-v1.7.5 / 40e1c89 |
| Solidity | 0.8.30 |
| OpenZeppelin Contracts | v5.6.1 (npm latest; v5.7.0 still rc.0) |
| OpenZeppelin Upgradeable | v5.6.1 |
| Foundry | pin commit in CI at dev start |
| Avalanche CLI | pin at testnet initiation |

**Why:** Both archives happened as part of Avalanche Granite upgrade monorepo consolidation. icm-services is the active mono-service repo; AvalancheGo now ships the EVM plugin directly.

**How to apply:** Any future PrimeWave sprint that touches contract imports or node dependencies must use this stack. Check `docs/PRIMEWAVE_DEPENDENCY_COMPATIBILITY.md` for full registry with compatibility evidence.
