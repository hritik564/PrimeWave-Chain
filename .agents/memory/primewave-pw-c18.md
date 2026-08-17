---
name: PrimeWave Chain PW-C18
description: EVM state reset (DB wipe) on all 4 testnet validators; deployer nonce restored to 0; deployer key lost
---

## Summary
C18 goal was blockchain recreation (new blockchain ID) to reset deployer nonce from 5→0. Key was lost → pivoted to coordinated DB wipe on all 4 validators simultaneously. Chain returned to genesis state. Ready for contract deployment (Phase 8).

## Result
- Deployer nonce: **0** (was 5)
- Block number: **0** (genesis)
- Chain ID: 77 ✓ (unchanged)
- Blockchain ID: `22iFuL8GqPYbtnPKNFrq7AzoDfv3FYwq8T93GubRi12LQVjLni` (unchanged — same ID kept)
- All 4 validators healthy, `percentConnected: 1.0`, `disconnectedValidators: []`
- P-Chain synced to height 293086

## DB Wipe Details
Wiped on all 4 validators simultaneously:
- `/data/avalanchego/db/fuji/` — main LevelDB (~1.3G): P-Chain sync state + proposervm consensus state
- `/data/avalanchego/chainData/22iFuL8.../` — EVM state (~60K): block data, transactions
- P-Chain re-sync took ~7 minutes (293K blocks via partial-sync-primary-network: true)

**Why:** P-Chain still knows our blockchain exists → AvalancheGo re-initializes from genesis bytes in P-Chain. All 4 peers wiped simultaneously → no peer had old data → all started from genesis. Net: fresh EVM state with same blockchain ID.

## Critical: Deployer Key Lost
- EVM deployer `0xB518397E3D65a0E7475635F01C225E9426a76F11`
- Key not found in Replit `~/.avalanche-cli/key/` (ephemeral, wiped between sessions)
- Key not on any validator (V6–V9)
- `/tmp/sendtx/main.go` on V9 was a stub
- **Must be stored as Replit secret `TESTNET_DEPLOYER_KEY` before Phase 8 (contract deployment)**
- **Rule: After every session that touches the deployer key, immediately save it to a Replit secret**

## Nonce-Zero Guard
`contracts/script/DeployTestnet.s.sol` has a hard guard (`require(nonce == 0, ...)`) — permanent, never remove.

## Block Production Note
subnet-evm does NOT produce empty blocks. Block counter stays at 0 until first transaction. This is normal. First block will be produced during Phase 8 deployment.

## Phase 8 Pre-Conditions
- [x] Deployer nonce = 0
- [x] All 4 validators healthy
- [x] Chain ID = 77
- [x] Nonce-zero guard active
- [ ] Deployer private key → Replit secret `TESTNET_DEPLOYER_KEY`
