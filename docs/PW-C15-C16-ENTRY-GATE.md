# PW-C15 — C16 ENTRY GATE

**Sprint:** PW-C15 — Testnet Battle Test + Mainnet Readiness
**Status:** GATE DEFINED — Items pending live testnet execution
**Environment:** TESTNET / PRE-MAINNET

C16 (Mainnet) may begin ONLY when every item below is checked.
No ambiguous status. Each item is PASS, FAIL, or DEFERRED (with a defined plan).

---

## GATE CHECKLIST

### TESTNET FOUNDATION

| # | Item | Status | Evidence |
|---|---|---|---|
| G-01 | Real testnet deployed on Fuji | 🔵 PENDING | Subnet ID TBD; Blockchain ID TBD |
| G-02 | Testnet Chain ID 77 confirmed on-chain | 🔵 PENDING | `eth_chainId == 0x4d` via live RPC |
| G-03 | Blockchain ID recorded | 🔵 PENDING | TBD — Fuji P-Chain |
| G-04 | Genesis hash recorded | 🔵 PENDING | `sha256sum genesis.json` TBD |
| G-05 | Genesis reproducibility proven | 🔵 PENDING | Destroy + regenerate → same hash |

### VALIDATORS

| # | Item | Status | Evidence |
|---|---|---|---|
| G-06 | Validators operational (actual count) | 🔵 PENDING | TBD validators active |
| G-07 | P-Chain integration proven | 🔵 PENDING | CreateSubnetTx + CreateChainTx TX IDs |
| G-08 | ACP-99 registration proven | 🔵 PENDING | completeValidatorRegistration() TX TBD |
| G-09 | Validator churn proven | 🔵 PENDING | Join/leave/weight-change cycle tested |
| G-10 | Validator failure + recovery proven | 🔵 PENDING | F-01 results TBD |
| G-11 | Multi-node consistency verified | 🔵 PENDING | Same hash/stateRoot on all nodes |

### ICM / WARP

| # | Item | Status | Evidence |
|---|---|---|---|
| G-12 | ICM/Warp proven | 🔵 PENDING | Real Warp messages delivered |
| G-13 | ICM retry/dedup proven | 🔵 PENDING | ICM-02, ICM-03 results TBD |
| G-14 | ICM failure recovery proven | 🔵 PENDING | F-09 results TBD |

### KEEPER

| # | Item | Status | Evidence |
|---|---|---|---|
| G-15 | Keeper proven on testnet | 🔵 PENDING | Live syncValidator() TX TBD |
| G-16 | Keeper restart recovery proven | 🔵 PENDING | F-03 results TBD |
| G-17 | Keeper authority bounded | 🔵 PENDING | SEC test: keeper cannot steal funds |

### PUBLIC RPC

| # | Item | Status | Evidence |
|---|---|---|---|
| G-18 | Public RPC proven | 🔵 PENDING | All 10 standard methods respond |
| G-19 | RPC security proven | 🔵 PENDING | Admin methods blocked; invalid requests fail safely |
| G-20 | RPC load test completed | 🔵 PENDING | PW-C15-RPC-LOAD-TEST.md results |
| G-21 | Rate limiting verified | 🔵 PENDING | Threshold recorded |

### PWCSCAN + INDEXER

| # | Item | Status | Evidence |
|---|---|---|---|
| G-22 | PWCScan proven on testnet | 🔵 PENDING | All 15 routes verified; 🧪 Testnet badge; Chain ID 77 |
| G-23 | Indexer proven | 🔵 PENDING | 57/57 Jest + live sync verified |
| G-24 | Indexer restart recovery proven | 🔵 PENDING | F-04 results TBD |
| G-25 | Reindex proven | 🔵 PENDING | From-block-0 reindex verified |

### DATABASE

| # | Item | Status | Evidence |
|---|---|---|---|
| G-26 | PostgreSQL recovery proven | 🔵 PENDING | Backup → destroy → restore drill results |
| G-27 | RPO measured | 🔵 PENDING | ≤ 1 hour |
| G-28 | RTO measured | 🔵 PENDING | ≤ 30 minutes |

### PROTOCOL ECONOMICS

| # | Item | Status | Evidence |
|---|---|---|---|
| G-29 | Fee distribution proven | 🔵 PENDING | 70/20/10 verified on real txs; zero conservation violations |
| G-30 | RewardVault proven | 🔵 PENDING | 15M balance; ≤3M/yr rate; no minting |
| G-31 | Staking proven | 🔵 PENDING | Stake/claim cycle completed on testnet |
| G-32 | 14-day unbond verified | DEFERRED | Real-time 14d wait required; simulation documented |

> **G-32 DEFERRED NOTE:** A full 14-day real-time unbonding cycle cannot be completed
> within the current sprint. An accelerated time-warp simulation was performed on an
> isolated test chain and documented in PW-C15-TESTNET-BATTLE-TEST.md §8.
> Actual 14-day observation on the live testnet must complete before mainnet launch.
> C16 may begin with G-32 DEFERRED if leadership explicitly accepts this risk.

### GOVERNANCE

| # | Item | Status | Evidence |
|---|---|---|---|
| G-33 | Governance proven on testnet | 🔵 PENDING | GOV-01..GOV-09 results |
| G-34 | Emergency pause/unpause proven | 🔵 PENDING | Live 3-of-5 test |
| G-35 | Timelock 48h proven | 🔵 PENDING | Real 48h wait or acceptable simulation |

### MONITORING + OPERATIONS

| # | Item | Status | Evidence |
|---|---|---|---|
| G-36 | Monitoring proven | 🔵 PENDING | Prometheus scraping; controlled alert fired |
| G-37 | Alert recovery cycle proven | 🔵 PENDING | Alert fires → resolves |
| G-38 | Backup/restore proven | 🔵 PENDING | Drill completed |
| G-39 | DNS/TLS verified | 🔵 PENDING | HTTPS on all public endpoints |

### PERFORMANCE + STABILITY

| # | Item | Status | Evidence |
|---|---|---|---|
| G-40 | Performance measured | 🔵 PENDING | PW-C15-PERFORMANCE-REPORT.md results |
| G-41 | Soak test completed or explicitly accepted | 🔵 PENDING | PW-C15-SOAK-TEST.md: ≥24h or shortfall documented |
| G-42 | All failure recovery scenarios passed | 🔵 PENDING | F-01..F-12 all PASS |

### SECURITY

| # | Item | Status | Evidence |
|---|---|---|---|
| G-43 | Security audit clean | 🔵 PENDING | PW-C15-SECURITY-REVIEW.md summary |
| G-44 | No Critical findings outstanding | 🔵 PENDING | Findings log TBD |
| G-45 | No High findings outstanding | 🔵 PENDING | All High findings remediated |

### MAINNET PREPARATION

| # | Item | Status | Evidence |
|---|---|---|---|
| G-46 | Mainnet deployment rehearsal complete | 🔵 PENDING | Rehearsal steps 1-11 all PASS |
| G-47 | Mainnet Chain ID still intentionally TBD or explicitly approved | ✅ PASS | TBD — all 2-digit taken; 3-digit candidates listed |
| G-48 | Mainnet key ceremony procedure prepared | ✅ PASS | PW-C15-MAINNET-READINESS.md §3 |
| G-49 | No mainnet private keys generated | ✅ PASS | Confirmed — none generated in C14 or C15 |
| G-50 | PWC-20 not implemented (PROPOSED only) | ✅ PASS | Not touched in C14 or C15 |

### REGRESSION

| # | Item | Status | Evidence |
|---|---|---|---|
| G-51 | Forge 792/792 | ✅ PASS | C15 regression run 2026-08-15 |
| G-52 | Indexer Jest 57/57 | ✅ PASS | C15 regression run 2026-08-15 |
| G-53 | Keeper Jest 20/20 | ✅ PASS | C15 regression run 2026-08-15 |

---

## GATE SUMMARY

| Category | Total Items | PASS | DEFERRED | PENDING LIVE |
|---|---|---|---|---|
| Testnet Foundation | 5 | 0 | 0 | 5 |
| Validators | 6 | 0 | 0 | 6 |
| ICM/Warp | 3 | 0 | 0 | 3 |
| Keeper | 3 | 0 | 0 | 3 |
| RPC | 4 | 0 | 0 | 4 |
| PWCScan + Indexer | 4 | 0 | 0 | 4 |
| Database | 3 | 0 | 0 | 3 |
| Protocol Economics | 4 | 0 | 1 | 3 |
| Governance | 3 | 0 | 0 | 3 |
| Monitoring + Operations | 4 | 0 | 0 | 4 |
| Performance + Stability | 3 | 0 | 0 | 3 |
| Security | 3 | 0 | 0 | 3 |
| Mainnet Preparation | 5 | 3 | 0 | 2 |
| Regression | 3 | 3 | 0 | 0 |
| **TOTAL** | **53** | **6** | **1** | **46** |

**C16 gate status: BLOCKED — 46 items require live testnet execution**

All 46 pending items require external infrastructure (Fuji P-Chain, cloud servers,
validators, DNS, TLS). All code, procedures, scripts, and documentation are
complete and ready. Gate opens when infrastructure is provisioned and live testnet
battle testing completes.

---

## GATE OPENING PROCEDURE

When all items are resolved:

1. Fill in every TBD field in this document with actual values
2. Confirm all 53 items are PASS (or explicitly DEFERRED with leadership sign-off)
3. Run final regression: Forge 792/792, Indexer 57/57, Keeper 20/20
4. Leadership signs off on any DEFERREDs (currently: G-32 14-day unbond)
5. Document is countersigned by Ceremony Lead and Security Auditor
6. C16 may begin

---

## STOP CONDITIONS (BLOCKING C16)

Any of the following permanently blocks C16 until resolved:

| Condition | Reason |
|---|---|
| Mainnet private keys generated prematurely | Security — key ceremony belongs to C16 |
| Mainnet Chain ID changed without approval | Architecture integrity |
| Testnet Chain ID 77 inconsistent | Network identity broken |
| NativeMinter enabled | Supply invariant broken |
| Fixed 100M supply broken | Tokenomics violation |
| RewardVault minting | Extra emission beyond 15M |
| Fee split broken | Economic protocol violation |
| ValidatorManager authority bypassed | Consensus integrity |
| Nodes diverge persistently | Chain consistency broken |
| Indexer loses chain data | Data integrity broken |
| PWCScan fabricates data | Explorer integrity broken |
| Critical or High security finding outstanding | Security — must be remediated |
| Genesis not reproducible | Deployment procedure broken |
