---
name: PrimeWave Chain PW-C15
description: C15 Testnet Battle Test + Mainnet Readiness — scope, infra audit, chain ID research, deliverables, pitfalls
---

## Status
C15 IN PROGRESS — In-Replit work complete; PW-C15-External infrastructure audit complete.
Live testnet execution blocked on external cloud infrastructure.

## Critical Finding: Mainnet Chain ID
ALL two-digit EVM chain IDs (1–99) are registered on chainlist.network (verified 2026-08-15).
No two-digit mainnet chain ID is available. Three-digit candidates (all confirmed available 2026-08-15):
**149, 209, 229, 235, 241** — verify again at finalization time (list changes monthly).
DO NOT finalize without leadership approval. Current status: MAINNET CHAIN ID = TBD.

## Chain IDs (Locked)
- Development: 73571 (unchanged forever)
- Testnet: 77 / hex 0x4d (locked C14/post-C14)
- Mainnet: TBD — no two-digit IDs available

## Testnet-Deployer Key (Public Info Only — NEVER commit private key)
- Generated 2026-08-15 in Replit via `avalanche key create testnet-deployer`
- C-Chain (EVM): `0x2AD3152Ca630e2eF6679EBeb8da7b8311bfbFc60`
- P-Chain (Fuji): `P-fuji1p25rk6kz9lwg2plwmfmvkvzxsa5qd02kla0vsw`
- X-Chain (Fuji): `X-fuji1p25rk6kz9lwg2plwmfmvkvzxsa5qd02kla0vsw`
- Balance: 0 AVAX — fund via https://faucet.avax.network
- SECURITY NOTE: For production-grade testnet, regenerate on air-gapped hardware per KEY_SECURITY_PROCEDURE

## Infrastructure Audit Results (2026-08-15)
- Avalanche CLI v1.9.5: AVAILABLE (local-bin/avalanche)
- AvalancheGo v1.14.2: AVAILABLE + RUNNING (4 local dev nodes)
- subnet-evm: AVAILABLE (local-bin/subnet-evm)
- Fuji P-Chain API: REACHABLE — api.avax-test.network height 292884, networkID 5
- PostgreSQL 16.10: AVAILABLE (Replit PGHOST=helium)
- Cloud VPS servers: BLOCKED — no credentials, no SSH keys
- DNS management: BLOCKED
- TLS certificates: BLOCKED
- External validators: BLOCKED (binary exists; needs cloud servers)
- Fuji AVAX (testnet-deployer): BLOCKED — 0 balance; needs faucet funding

## Primary Unblock Path
1. Fund P-fuji1p25rk6kz9lwg2plwmfmvkvzxsa5qd02kla0vsw via faucet.avax.network
2. Provision ≥3 cloud VPS (Hetzner/AWS/GCP)
3. Register DNS: rpc.testnet.*, explorer.testnet.*
4. Issue Let's Encrypt TLS certs
5. Run: avalanche blockchain deploy primewave-testnet --fuji --key testnet-deployer
6. Fill genesis placeholders (6 __REPLACE_*__ entries)
7. Deploy validators, contracts, keeper, indexer, PWCScan

## In-Replit Deliverables (DONE)
- 13 docs in docs/PW-C15-*.md + docs/PW-C15-INFRA-PROVISIONING-GUIDE.md
- Forge 792/792, Indexer 57/57, Keeper 20/20 (regression run 2026-08-15)
- Genesis static validation: Chain ID 77, 100M PW, NativeMinter disabled ✅
- deploy-contracts.sh chain ID guard tested: correctly rejects dev chain 73571 ✅
- C16 entry gate updated: 64 items; 11 PASS, 51 BLOCKED, 1 DEFERRED
- testnet-deployer key generated (public addresses documented above)
- Infra provisioning guide with exact commands: docs/PW-C15-INFRA-PROVISIONING-GUIDE.md

## Deferred Item
- G-32 / C15-19c: 14-day real-time unbond — cannot complete within sprint; simulation documented.

## Key Pitfalls / Rules
- chainid.network/chains.json is the live check source — re-run before finalizing any chain ID
- ewoq key (0x8db97C7cEcE249c2b98bDC0226Cc4C2A57BF52FC) exists in CLI with Fuji balance — DO NOT use for testnet; it is a publicly known key
- 14-day unbond: NEVER label time-warp simulation as real behavior
- Keeper is NOT validator authority — ValidatorManager remains authoritative
- No mainnet private keys may be generated until C16 key ceremony
- Dev chain (Chain ID 73571, blockchain 2F3BHmNJWP4DNaBbMFQog3TvfcF6GRY7PX99r7Xzae4cRwAv6a) running locally with 4 nodes; blockchain health shows "false" (subnet VM may need restart)

## Regression Baseline
- Forge: 792/792 ✅
- Indexer Jest: 57/57 ✅
- Keeper Jest: 20/20 ✅
