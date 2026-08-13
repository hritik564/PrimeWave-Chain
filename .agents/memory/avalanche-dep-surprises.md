---
name: Avalanche dependency surprises
description: Two key Avalanche repos archived late 2025; successors, CLI+AvalancheGo version mismatch workaround, and subnet-evm binary provenance
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
| subnet-evm plugin binary | v1.14.2 (from AvalancheGo releases, NOT the archived repo) |
| ICM Services contracts | icm-relayer-v1.7.5 / 40e1c89 |
| Solidity | 0.8.30 |
| OpenZeppelin Contracts | v5.6.1 (npm latest; v5.7.0 still rc.0) |
| OpenZeppelin Upgradeable | v5.6.1 |
| Foundry | pin commit in CI at dev start |
| Avalanche CLI | v1.9.5 (maintenance mode; see version mismatch below) |

**Why:** Both archives happened as part of Avalanche Granite upgrade monorepo consolidation. icm-services is the active mono-service repo; AvalancheGo now ships the EVM plugin directly.

**How to apply:** Any future PrimeWave sprint that touches contract imports or node dependencies must use this stack. Check `docs/PRIMEWAVE_DEPENDENCY_COMPATIBILITY.md` for full registry with compatibility evidence.

---

## CLI v1.9.5 + AvalancheGo v1.14.2 version mismatch (CONFIRMED WORKAROUND)

**Problem:** CLI v1.9.5 (maintenance mode, Dec 2025) predates AvalancheGo v1.14.2 (Mar 2026). CLI's internal VM registry lookup for `"subnet-evm"` fails with `"unknown vm: subnet-evm"` — hardcoded registry that cannot be patched without rebuilding the CLI.

**Symptom:** `blockchain deploy` exits with "unknown vm: subnet-evm" or "setup VM binary" error. This happens AFTER all P-Chain work completes.

**Working workaround (implemented in `scripts/start-local.sh`):**
1. Run `blockchain deploy` — let it fail at "setup VM binary". All P-Chain state (subnet, blockchain, L1 conversion, local cluster bootstrap) is complete by then.
2. Patch local cluster `flags.json`: `sybil-protection-enabled=false`, `partial-sync-primary-network=false`, `track-subnets=<subnetID>`, clear bootstrap peers.
3. Place `local-bin/subnet-evm` (from AvalancheGo v1.14.2 release) at `~/.avalanche-cli/local/primewavedev-local-node-local-network/plugins/<VMID>`.
4. Start `local-bin/avalanchego` directly from patched flags — standalone single-node.
5. Node becomes healthy in ~3s. rpcchainvm=45 matches between avalanchego and subnet-evm.

**Why `partial-sync-primary-network=false` is required:** When `sybil-protection-enabled=false`, the node is treated as a validator for the primary network. Setting `partial-sync-primary-network=true` while being a validator triggers: "partial sync should not be configured for a validator". Both flags must be false together.

**subnet-evm binary source:** `https://github.com/ava-labs/avalanchego/releases/download/v1.14.2/subnet-evm-linux-amd64-v1.14.2.tar.gz`
Downloaded and saved to `local-bin/subnet-evm`. Reports: `Subnet-EVM/v1.14.2 [rpcchainvm=45]`.

**VMID:** `rXJjKFtAVSmpKwhMhw7ZMV6opKcsmhk5AuVxWNAzFG221wmM8`

**Confirmed working:** `eth_chainId` → `0x11f63` (73571), all health checks pass, 5 genesis accounts × 10,000 PW verified.
