---
name: PrimeWave Chain PW-C15
description: C15 Testnet Battle Test + Mainnet Readiness — scope, chain ID research, deliverables, pitfalls
---

## Status
C15 IN PROGRESS — In-Replit work complete; live testnet execution requires external infrastructure.

## Critical Finding: Mainnet Chain ID
ALL two-digit EVM chain IDs (1–99) are registered on chainlist.network (verified 2026-08-15).
No two-digit mainnet chain ID is available. Three-digit candidates (all confirmed available 2026-08-15):
**149, 209, 229, 235, 241** — verify again at finalization time (list changes monthly).
DO NOT finalize without leadership approval. Current status: MAINNET CHAIN ID = TBD.

## Chain IDs (Locked)
- Development: 73571 (unchanged forever)
- Testnet: 77 / hex 0x4d (locked C14/post-C14)
- Mainnet: TBD — no two-digit IDs available

## In-Replit Deliverables (DONE)
- 13 docs in docs/PW-C15-*.md (12 per §41 + test matrix)
- Forge 792/792, Indexer 57/57, Keeper 20/20 (regression run 2026-08-15)
- Chain ID 77 consistent across all config files, scripts, docs
- C16 entry gate: 53 checklist items defined; 6 PASS (in-Replit), 46 PENDING (live infra), 1 DEFERRED (14-day unbond)
- Mainnet key ceremony procedure complete (in PW-C15-MAINNET-READINESS.md §3)
- All 95 test matrix items defined: 10 PASS, 84 PENDING, 1 DEFERRED

## External Infrastructure Required (BLOCKING)
- Fuji P-Chain deployment (CreateSubnetTx, CreateChainTx, ConvertSubnetToL1Tx)
- Cloud servers for validator nodes (target: 15)
- DNS + TLS for RPC and PWCScan endpoints
- Real testnet key ceremony (addresses for genesis placeholders)
- ICM/Warp relayer operational
- All battle tests (fees, rewards, staking, governance, security, soak)

## Deferred Item
- C15-19c: 14-day real-time unbond — cannot complete within sprint; simulation documented;
  requires leadership sign-off in C16 entry gate (G-32).

## Key Pitfalls / Rules
- chainid.network/chains.json is the live check source — re-run before finalizing any chain ID
- The chain list changes monthly; 2026-08-15 snapshot shows all 1–99 taken
- 14-day unbond: NEVER label time-warp simulation as real behavior
- Keeper is NOT validator authority — ValidatorManager remains authoritative
- No mainnet private keys may be generated until C16 key ceremony

## Regression Baseline
- Forge: 792/792 ✅
- Indexer Jest: 57/57 ✅
- Keeper Jest: 20/20 ✅
