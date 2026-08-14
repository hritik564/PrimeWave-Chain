# PW-C14: Testnet Acceptance Test Matrix
**Sprint:** PW-C14
**Environment:** TESTNET ONLY — Chain ID **77** (Previous testnet Chain ID: 77777)
**Reference:** Section 41 of PW-C14 spec

---

## Test Execution Status Key

| Symbol | Meaning |
|---|---|
| ✅ | PASS — verified on testnet |
| ❌ | FAIL — blocking issue |
| 🔵 | DEFERRED — requires external infrastructure |
| ⏳ | IN PROGRESS |
| ☐ | NOT YET RUN |

---

## NET-01 — NET-10: Chain Foundation

| ID | Test | Method | Expected | Status | Notes |
|---|---|---|---|---|---|
| NET-01 | Genesis valid | `validate-testnet-genesis.sh` | All INV-G* pass | 🔵 | Awaits Fuji P-Chain subnet creation |
| NET-02 | Chain ID correct (77) | `cast chain-id --rpc-url $RPC` | `77` | 🔵 | Awaits testnet RPC |
| NET-03 | Blockchain ID recorded | Genesis construction | Non-empty CB58 string | 🔵 | Generated at subnet creation |
| NET-04 | Native PW transfer works | `cast send ... --value 1ether` | tx included in block | 🔵 | |
| NET-05 | Gas paid in PW (not ETH) | Inspect tx receipt | `effectiveGasPrice > 0` in PW | 🔵 | |
| NET-06 | Public RPC reachable | `curl $RPC_URL/ext/health` | `{"healthy":true}` | 🔵 | Awaits nginx/TLS |
| NET-07 | Multiple nodes synchronize | Start 2nd node, watch sync | Block height matches | 🔵 | Awaits multi-node setup |
| NET-08 | Validator registration | PoAManager.initiateRegistration() | Validator appears in registry | 🔵 | Awaits real ACP-99 flow |
| NET-09 | Validator activation | Warp message confirmed | `isActive == true` on registry | 🔵 | |
| NET-10 | Validator sync (keeper) | Keeper calls syncValidator() | Registry updated | 🔵 | |

---

## NET-11 — NET-20: Protocol and Infrastructure

| ID | Test | Method | Expected | Status | Notes |
|---|---|---|---|---|---|
| NET-11 | Fee distribution (70/20/10) | Send txs, inspect FeeDistributor events | 70/20/10 split | 🔵 | |
| NET-12 | RewardVault funding (15M PW) | `rewardVault.totalFunded()` | `== 15_000_000 PW` | 🔵 | |
| NET-13 | Reward distribution | Advance time, claim rewards | `totalEmitted > 0` | 🔵 | |
| NET-14 | Governance (pause/unpause) | EMS.proposeAction(pause), 3-of-5 approve | Contracts paused | 🔵 | |
| NET-15 | Keeper liveness | `curl $KEEPER_HEALTH/health` | `{"status":"ok"}` | 🔵 | |
| NET-16 | Indexer synced | `curl $INDEXER/stats` | `isSynced: true` | 🔵 | |
| NET-17 | PWCScan live data | Browser — see blocks, txs | No "offline" state | 🔵 | |
| NET-18 | Search (tx hash lookup) | Search for deployed tx hash | Tx detail page loads | 🔵 | |
| NET-19 | Restart recovery (node) | See `docs/PW-C14-FAILURE-RECOVERY.md` §1 | Network continues | 🔵 | |
| NET-20 | Database backup → restore | See `docs/PW-C14-FAILURE-RECOVERY.md` §6 | Data identical | 🔵 | |

---

## NET-21 — NET-30: Resilience, Security, Operations

| ID | Test | Method | Expected | Status | Notes |
|---|---|---|---|---|---|
| NET-21 | Validator failure (1 offline) | Stop validator 5 | 4/5 continue consensus | 🔵 | |
| NET-22 | Validator recovery | Restart validator 5 | Re-syncs, rejoins | 🔵 | |
| NET-23 | Reindex from block 0 | `PRIMEWAVE_ALLOW_REINDEX=yes node reindex.js --from 0` | Identical results | 🔵 | |
| NET-24 | Data integrity (no duplicates) | DB unique constraint audit | 0 duplicate blocks/txs | 🔵 | |
| NET-25 | RPC security (admin blocked) | `curl -X POST -d debug_... $RPC` | Method not found | 🔵 | |
| NET-26 | Secret security (no keys in logs) | `journalctl \| grep -E '0x[a-f0-9]{64}'` | No matches | 🔵 | |
| NET-27 | Backup working | `backup-testnet-db.sh` runs cleanly | `.dump` file created | 🔵 | |
| NET-28 | Genesis reproducibility | Re-run genesis construction with same inputs | SHA-256 hash matches | 🔵 | |
| NET-29 | Monitoring active | Prometheus scrape targets | All `up==1` | 🔵 | |
| NET-30 | Public connectivity | From external machine: `curl $RPC/ext/health` | 200 OK | 🔵 | |

---

## C13-REG: C00-C13 Regression

| ID | Test | Command | Expected | Status |
|---|---|---|---|---|
| REG-01 | Forge protocol tests | `forge test` | 792/792 PASS | ✅ Verified |
| REG-02 | Indexer Jest tests | `cd indexer && npx jest` | 57/57 PASS | ✅ Verified |
| REG-03 | Keeper Jest tests | `cd keeper && npx jest` | 20/20 PASS | ✅ Verified |
| REG-04 | PWCScan live data (local dev) | Indexer + chain running locally | All 5 pages load with data | ✅ Verified |

---

## Local Dev Simulation: In-Replit Testnet Rehearsal

The following tests were run against the **local dev environment** (chain ID 73571) to rehearse
the testnet procedures. They represent what will be executed identically on chain ID 77:

| ID | Simulated Test | Result |
|---|---|---|
| SIM-01 | Contract deployment via DevDeploy.s.sol | ✅ 9 txs in block 1 |
| SIM-02 | RewardVault funded 1000 PW (dev amount) | ✅ totalFunded verified |
| SIM-03 | FeeDistributor 70/20/10 routing (unit tests) | ✅ 792/792 forge tests cover this |
| SIM-04 | Indexer syncs from block 0 | ✅ block 0-4 indexed |
| SIM-05 | PWCScan displays live block/tx data | ✅ Screenshot verified |
| SIM-06 | Transactions list endpoint | ✅ GET /transactions working |
| SIM-07 | Contracts page (7 protocol contracts) | ✅ All 7 indexed and displayed |
| SIM-08 | Keeper unit tests (syncValidator, updateWeight) | ✅ 20/20 pass |
| SIM-09 | Indexer restart/resume | ✅ Restart recovery works |
| SIM-10 | Health check endpoints | ✅ /health and /stats verified |

---

## Summary

| Category | Total | PASS | FAIL | DEFERRED (need infra) |
|---|---|---|---|---|
| NET-01 to NET-30 | 30 | 0 | 0 | 30 |
| C13 Regression | 4 | 4 | 0 | 0 |
| Local Simulation | 10 | 10 | 0 | 0 |
| **Total** | **44** | **14** | **0** | **30** |

All 30 NET-* tests are deferred pending real external infrastructure (Fuji P-Chain, cloud servers, DNS/TLS). The infrastructure, scripts, configs, and procedures are completely defined and ready to execute.
