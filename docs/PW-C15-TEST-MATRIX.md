# PW-C15 — TEST MATRIX

**Sprint:** PW-C15 — Testnet Battle Test + Mainnet Readiness
**Status:** MATRIX COMPLETE — Results pending live testnet execution
**Environment:** TESTNET ONLY — Chain ID 77

Legend:
- ✅ PASS — verified
- ❌ FAIL — failed (must be resolved before C16)
- 🔵 PENDING — requires live testnet infrastructure
- ⏳ DEFERRED — explicitly deferred with leadership sign-off

---

## CORE TESTNET FOUNDATION

| ID | Test | Method | Expected | Actual | Status |
|---|---|---|---|---|---|
| C15-01 | Testnet genesis | `validate-testnet-genesis.sh` + INV-G1..G9 | All invariants PASS; Chain ID 77; 100M PW | TBD | 🔵 |
| C15-02 | Chain ID (EVM) | `cast chain-id --rpc-url $RPC` | 77 | TBD | 🔵 |
| C15-03 | Blockchain ID | Recorded from Fuji P-Chain CreateChainTx | 32-byte hash (non-empty, non-dev) | TBD | 🔵 |
| C15-04 | Fuji P-Chain integration | CreateSubnetTx TX ID confirmed on Fuji | TX accepted; Subnet ID recorded | TBD | 🔵 |
| C15-05 | Subnet creation | ConvertSubnetToL1Tx confirmed | L1 conversion confirmed | TBD | 🔵 |

## VALIDATORS

| ID | Test | Method | Expected | Actual | Status |
|---|---|---|---|---|---|
| C15-06 | Validator registration | P-Chain validator add; Warp delivered to ValidatorManager | `completeValidatorRegistration()` succeeds | TBD | 🔵 |
| C15-07 | Validator activation | Keeper `syncValidator()`; registry weight set | Non-zero weight in registry | TBD | 🔵 |
| C15-08 | Validator synchronization | Fresh node bootstrap | Syncs to tip within 30m | TBD | 🔵 |
| C15-08b | Multi-node consistency | Compare block hash + state root across all validators | Identical hashes | TBD | 🔵 |
| C15-08c | Peer discovery | `info.peers` on each validator | ≥ 5 peers | TBD | 🔵 |
| C15-08d | Block propagation | Time from block proposal to all nodes | < 5 seconds | TBD | 🔵 |

## ICM / WARP

| ID | Test | Method | Expected | Actual | Status |
|---|---|---|---|---|---|
| C15-09 | ICM/Warp normal delivery | Validator registration triggers Warp message | Message delivered within 3 blocks | TBD | 🔵 |
| C15-09b | ICM retry | Stop relayer; restart; check pending messages | Queued messages delivered | TBD | 🔵 |
| C15-09c | ICM dedup | Send same Warp message twice | Second delivery rejected | TBD | 🔵 |

## KEEPER

| ID | Test | Method | Expected | Actual | Status |
|---|---|---|---|---|---|
| C15-10 | Keeper live operation | `journalctl -u primewave-keeper` | `syncValidator()` calls appear on validator changes | TBD | 🔵 |
| C15-10b | Keeper restart | `systemctl restart primewave-keeper` | Resumes from saved block; no duplicate syncs | TBD | 🔵 |
| C15-10c | Keeper stale detection | Stop keeper 10m; verify alert fires | KeeperStalled alert within 10m | TBD | 🔵 |

## RPC

| ID | Test | Method | Expected | Actual | Status |
|---|---|---|---|---|---|
| C15-11 | RPC all standard methods | curl each method against live RPC | All 10 methods respond correctly | TBD | 🔵 |
| C15-11b | `eth_chainId` | `cast chain-id` | 0x4d (77) | TBD | 🔵 |
| C15-11c | `net_version` | curl `net_version` | "77" | TBD | 🔵 |
| C15-12 | RPC security | Scan admin methods; test path traversal | All admin methods blocked / error | TBD | 🔵 |
| C15-12b | Invalid request handling | Malformed JSON; unknown method | Safe errors; no crash | TBD | 🔵 |

## WALLET

| ID | Test | Method | Expected | Actual | Status |
|---|---|---|---|---|---|
| C15-13 | Wallet connection | Add PrimeWave Testnet to MetaMask (Chain ID 77) | Network added; PW shown | TBD | 🔵 |
| C15-14 | PW transfer | `eth_sendRawTransaction` simple PW transfer | Tx confirmed; balance changes | TBD | 🔵 |
| C15-15 | Gas | Check gas pricing; estimate for contract calls | Gas > 0; estimates accurate | TBD | 🔵 |

## PROTOCOL ECONOMICS

| ID | Test | Method | Expected | Actual | Status |
|---|---|---|---|---|---|
| C15-16 | Fee distribution | 100 real txs; check 70/20/10 split | Zero conservation violations | TBD | 🔵 |
| C15-16b | Fee conservation (full batch) | SQL conservation check on all indexed blocks | No discrepancies | TBD | 🔵 |
| C15-16c | Rounding edge cases | Very small fees (1 gwei) | Rounding goes to burn | TBD | 🔵 |
| C15-17 | RewardVault funding | `eth_getBalance($REWARD_VAULT)` at genesis | 15,000,000 PW | TBD | 🔵 |
| C15-17b | RewardVault rate | Compare emission to 3M PW/year cap | Rate ≤ 3M/year | TBD | 🔵 |
| C15-17c | No minting | Scan Transfer(from=0x0) events | Zero mint events | TBD | 🔵 |
| C15-18 | Staking | Stake PW; verify eligibility threshold | Stake confirmed on-chain | TBD | 🔵 |
| C15-19 | Reward claim | Claim after accrual; verify transfer | Rewards received at reward address | TBD | 🔵 |
| C15-19b | Unbond initiation | Initiate unbond; verify 14-day timer | Timer correct; early withdraw REVERTS | TBD | 🔵 |
| C15-19c | Unbond completion | Wait 14 days (or time-warp sim) | Withdraw succeeds after 14 days | ⏳ | ⏳ |

## VALIDATOR CHURN

| ID | Test | Method | Expected | Actual | Status |
|---|---|---|---|---|---|
| C15-20 | Validator churn full cycle | V joins → operates → leaves → returns | All state correct at each step | TBD | 🔵 |
| C15-20b | Historical fee preservation | SQL: fees for exited validators still correct | No retroactive modification | TBD | 🔵 |
| C15-20c | No reward leakage | No validator receives another's allocation | Zero leakage | TBD | 🔵 |

## GOVERNANCE

| ID | Test | Method | Expected | Actual | Status |
|---|---|---|---|---|---|
| C15-21 | Governance system active | Confirm EmergencyMultisig + Timelock deployed | Contracts at expected addresses | TBD | 🔵 |
| C15-22 | Emergency pause | 3-of-5 multisig pause all contracts | All paused; block confirms | TBD | 🔵 |
| C15-22b | Emergency unpause | 3-of-5 multisig unpause | All unpaused | TBD | 🔵 |
| C15-22c | Insufficient approvals | Only 2-of-5 sign | REVERTS | TBD | 🔵 |
| C15-23 | Timelock 48h action | Schedule → wait 48h → execute | Executes only after delay | TBD | 🔵 |
| C15-23b | Timelock early execute | Try before 48h | REVERTS | TBD | 🔵 |
| C15-23c | Timelock replay | Re-execute completed op | REVERTS | TBD | 🔵 |

## INDEXER

| ID | Test | Method | Expected | Actual | Status |
|---|---|---|---|---|---|
| C15-24 | Indexer sync from genesis | Truncate DB; restart; measure | Syncs to tip; no gaps; no duplicates | TBD | 🔵 |
| C15-24b | Indexer continuous sync | Monitor lag during live chain | Lag < 5 blocks at steady state | TBD | 🔵 |
| C15-24c | Block continuity SQL | `SELECT missing_block FROM blocks` query | 0 rows returned | TBD | 🔵 |
| C15-24d | Parent hash continuity | SQL parent hash check | 0 mismatches | TBD | 🔵 |

## DATABASE

| ID | Test | Method | Expected | Actual | Status |
|---|---|---|---|---|---|
| C15-25 | Database backup | `backup-testnet-db.sh` | Backup file created; SHA verified | TBD | 🔵 |
| C15-26 | Database restore | Destroy DB; `restore-testnet-db.sh`; restart indexer | Data restored; indexer catches up | TBD | 🔵 |
| C15-26b | RPO measurement | Backup timestamp vs. restore point | ≤ 1 hour | TBD | 🔵 |
| C15-26c | RTO measurement | Time from destroy to fully caught up | ≤ 30 minutes | TBD | 🔵 |

## PWCSCAN

| ID | Test | Method | Expected | Actual | Status |
|---|---|---|---|---|---|
| C15-27 | PWCScan live | Browse all 15 routes on live testnet | All load; 🧪 Testnet badge; Chain ID 77 | TBD | 🔵 |
| C15-27b | No mocked data | Cross-reference DB row vs. `eth_getBlockByNumber` | Match | TBD | 🔵 |
| C15-27c | Validator page | View validator list; weights; history | Reflects live registry state | TBD | 🔵 |
| C15-28 | Search | Search by TX hash; block number; address | Correct results | TBD | 🔵 |
| C15-29 | Reindex | Truncate DB; reindex; verify PWCScan | Data reappears correctly | TBD | 🔵 |

## FAILURE / RECOVERY

| ID | Test | Method | Expected | Actual | Status |
|---|---|---|---|---|---|
| C15-30 | Node restart | `systemctl restart primewave-node` | Resyncs to tip; rejoins peers | TBD | 🔵 |
| C15-31 | Validator failure | Kill validator-05; verify network continues | N-1 validators produce blocks | TBD | 🔵 |
| C15-32 | Validator recovery | Restart validator-05 | Syncs; rejoins; no dup fees | TBD | 🔵 |
| C15-33 | RPC failure | `systemctl stop nginx` | Alert fires within 1m | TBD | 🔵 |
| C15-33b | RPC recovery | `systemctl start nginx` | All methods respond within 30s | TBD | 🔵 |
| C15-34 | Keeper failure | `systemctl stop primewave-keeper` | KeeperStalled alert within 10m | TBD | 🔵 |
| C15-34b | Keeper recovery | `systemctl start primewave-keeper` | Resumes from saved block | TBD | 🔵 |
| C15-35 | Indexer failure | `systemctl stop primewave-indexer` | IndexerSyncLag alert | TBD | 🔵 |
| C15-35b | Indexer recovery | `systemctl start primewave-indexer` | Resumes; no block gap | TBD | 🔵 |
| C15-36 | PostgreSQL failure | `systemctl stop postgresql` | Services log DB errors | TBD | 🔵 |
| C15-36b | PostgreSQL recovery | `systemctl start postgresql` | Services reconnect; data intact | TBD | 🔵 |
| C15-37 | ICM failure | Kill ICM relayer | Warp messages queue | TBD | 🔵 |
| C15-37b | ICM recovery | Restart relayer | Queued messages delivered | TBD | 🔵 |

## MONITORING

| ID | Test | Method | Expected | Actual | Status |
|---|---|---|---|---|---|
| C15-38 | Monitoring operational | Prometheus scraping all targets | All targets UP | TBD | 🔵 |
| C15-38b | Grafana dashboard | View key dashboards | Block rate; validator count; fee rate visible | TBD | 🔵 |
| C15-39 | Alert recovery cycle | Stop indexer → alert fires → start indexer → alert clears | Full cycle completes | TBD | 🔵 |
| C15-39b | Disk pressure alert | Fill disk to 95% → DiskPressure alert | Alert fires; clears after fix | TBD | 🔵 |

## PERFORMANCE + STABILITY

| ID | Test | Method | Expected | Actual | Status |
|---|---|---|---|---|---|
| C15-40 | Genesis reproducibility | Destroy + regenerate from same inputs | Identical genesis hash both runs | TBD | 🔵 |
| C15-41 | Performance measurement | Block time, TPS, RPC latency, indexer rate | Documented; not fabricated | TBD | 🔵 |
| C15-42 | Soak test | 24h continuous run; monitor all services | All services stable; no violations | TBD | 🔵 |

## SECURITY

| ID | Test | Method | Expected | Actual | Status |
|---|---|---|---|---|---|
| C15-43 | Security attack scenarios | C10 suite on live testnet | All attacks REVERT; no theft; no bypass | TBD | 🔵 |
| C15-43b | Unauthorized admin | Non-admin calls restricted functions | REVERTS | TBD | 🔵 |
| C15-43c | Reward theft attempt | Claim other validator's rewards | REVERTS | TBD | 🔵 |
| C15-43d | Keeper compromise sim | Keeper key holder tries to drain vault | REVERTS — no withdrawal authority | TBD | 🔵 |
| C15-43e | Governance replay | Re-execute completed governance op | REVERTS | TBD | 🔵 |

## MAINNET PREPARATION

| ID | Test | Method | Expected | Actual | Status |
|---|---|---|---|---|---|
| C15-44 | Deployment rehearsal | Execute 11-step rehearsal on testnet infra | All steps PASS; reproducible | TBD | 🔵 |
| C15-44b | Mainnet chain ID check | `curl chainid.network/chains.json` | Available candidate identified; TBD approved | ✅ | ✅ |
| C15-45 | C16 entry gate | All 53 gate items evaluated | Gate defined; pending infra | ✅ | ✅ |

## IN-REPLIT VERIFIED

| ID | Test | Method | Expected | Actual | Status |
|---|---|---|---|---|---|
| REG-01 | Forge regression | `forge test --via-ir` | 792/792 PASS | 792/792 | ✅ |
| REG-02 | Indexer Jest | `npx jest --no-coverage` (indexer) | 57/57 PASS | 57/57 | ✅ |
| REG-03 | Keeper Jest | `npx jest --no-coverage` (keeper) | 20/20 PASS | 20/20 | ✅ |
| REG-04 | DeployTestnet.s.sol compiles | `forge build` | Compiler run successful | PASS | ✅ |
| REG-05 | Genesis Chain ID == 77 | Python validation | chainId: 77; 100M PW | PASS | ✅ |
| REG-06 | No active 77777 references | grep scan | Zero active config references | PASS | ✅ |
| REG-07 | Chain ID 77 consistent in docs | grep scan | All 11 C14 docs + all 13 C15 docs correct | PASS | ✅ |
| REG-08 | All 1–99 chain IDs taken | chainid.network live query | 99/99 taken; 3-digit candidates identified | PASS | ✅ |

---

## MATRIX SUMMARY

| Category | Total | ✅ PASS | 🔵 PENDING | ⏳ DEFERRED | ❌ FAIL |
|---|---|---|---|---|---|
| Testnet Foundation | 5 | 0 | 5 | 0 | 0 |
| Validators | 6 | 0 | 6 | 0 | 0 |
| ICM/Warp | 3 | 0 | 3 | 0 | 0 |
| Keeper | 3 | 0 | 3 | 0 | 0 |
| RPC | 5 | 0 | 5 | 0 | 0 |
| Wallet | 3 | 0 | 3 | 0 | 0 |
| Protocol Economics | 10 | 0 | 9 | 1 | 0 |
| Validator Churn | 3 | 0 | 3 | 0 | 0 |
| Governance | 7 | 0 | 7 | 0 | 0 |
| Indexer | 4 | 0 | 4 | 0 | 0 |
| Database | 4 | 0 | 4 | 0 | 0 |
| PWCScan | 5 | 0 | 5 | 0 | 0 |
| Failure/Recovery | 13 | 0 | 13 | 0 | 0 |
| Monitoring | 4 | 0 | 4 | 0 | 0 |
| Performance+Stability | 3 | 0 | 3 | 0 | 0 |
| Security | 5 | 0 | 5 | 0 | 0 |
| Mainnet Preparation | 3 | 2 | 1 | 0 | 0 |
| In-Replit Verified | 8 | 8 | 0 | 0 | 0 |
| **TOTAL** | **95** | **10** | **84** | **1** | **0** |

**In-Replit:** 10/10 PASS ✅
**Live testnet:** 84 items pending external infrastructure
**Deferred (explicit):** 1 (C15-19c: 14-day real-time unbond — leadership-accepted)
**Failures:** 0
