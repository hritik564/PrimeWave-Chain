# PW-C15 — C16 ENTRY GATE

**Sprint:** PW-C15 — Testnet Battle Test + Mainnet Readiness
**Status:** GATE DEFINED — Updated 2026-08-15 after PW-C15-External audit
**Environment:** TESTNET / PRE-MAINNET

Status values:
- ✅ PASS — actually executed and verified
- ❌ FAIL — executed and failed (must resolve before C16)
- BLOCKED — cannot execute; specific missing dependency listed
- DEFERRED — explicitly deferred with required conditions listed

C16 may begin ONLY when every item is PASS (or formally DEFERRED with sign-off).
No ambiguous statuses. The gate only opens when real evidence exists.

---

## INFRASTRUCTURE AUDIT RESULTS (2026-08-15)

**Replit environment capabilities confirmed:**

| Resource | Available | Detail |
|---|---|---|
| Avalanche CLI v1.9.5 | ✅ YES | `local-bin/avalanche` |
| AvalancheGo v1.15.0-fuji | ✅ YES | Validator #1 (159.195.193.209) running v1.15.0-fuji, 56 peers, NRestarts=0 |
| subnet-evm binary | ✅ YES | `local-bin/subnet-evm` |
| Foundry (forge/cast) | ✅ YES | `local-bin/foundry/` |
| PostgreSQL 16.10 | ✅ YES | Replit managed DB at `PGHOST=helium` |
| Fuji P-Chain API | ✅ REACHABLE | `api.avax-test.network` — height 292884, networkID 5 |
| Internet access | ✅ YES | Outbound HTTPS confirmed |
| testnet-deployer key | ✅ GENERATED | C-Chain: `0x2AD3152Ca630e2eF6679EBeb8da7b8311bfbFc60` / P-Chain: `P-fuji1p25rk6kz9lwg2plwmfmvkvzxsa5qd02kla0vsw` |
| testnet-deployer AVAX balance | ❌ 0 AVAX | Fund via https://faucet.avax.network |
| Cloud/VPS servers | ❌ NONE | Provision externally: AWS / GCP / Hetzner |
| SSH keys to external servers | ❌ NONE | Generate and deploy with cloud servers |
| DNS management | ❌ NONE | Register with DNS provider |
| TLS certificates | ❌ NONE | Let's Encrypt after DNS + server |
| External validator nodes | ❌ NONE | Provision cloud VPS + deploy AvalancheGo |
| ICM/Warp relayer | ❌ NONE | Requires running Fuji subnet |

---

## GATE CHECKLIST

### TESTNET FOUNDATION

| # | Item | Status | Evidence / Blocker |
|---|---|---|---|
| G-01 | Real testnet deployed on Fuji | BLOCKED | Missing: funded P-Chain wallet + cloud servers. Need: ≥2 AVAX at P-fuji1p25rk6kz9lwg2plwmfmvkvzxsa5qd02kla0vsw, provision VPS, run `avalanche blockchain deploy primewave-testnet --fuji --key testnet-deployer` |
| G-02 | Testnet Chain ID 77 confirmed on-chain | BLOCKED | Depends on G-01 |
| G-03 | Blockchain ID recorded | BLOCKED | Depends on G-01 — output of CreateChainTx |
| G-04 | Genesis hash recorded | BLOCKED | Depends on G-06 (ceremony addresses) → fill placeholders → sha256sum genesis.json |
| G-05 | Genesis reproducibility proven | BLOCKED | Depends on G-04 |

### VALIDATORS

| # | Item | Status | Evidence / Blocker |
|---|---|---|---|
| G-06 | Validators operational (actual count reported) | BLOCKED | Missing: cloud VPS servers. Provision ≥3 VPS, deploy AvalancheGo v1.15.0-fuji, run `setup-testnet-node.sh`. Target: 15 / Actual: 1 (bootstrap validator running on 159.195.193.209) |
| G-07 | P-Chain integration proven | BLOCKED | Depends on G-01 + G-06 |
| G-08 | ACP-99 registration proven | BLOCKED | Depends on G-01 + G-06 + ICM relayer |
| G-09 | Validator churn proven | BLOCKED | Depends on G-06 |
| G-10 | Validator failure + recovery proven | BLOCKED | Depends on G-06 |
| G-11 | Multi-node consistency verified | BLOCKED | Depends on G-06 (need ≥2 validators) |

### ICM / WARP

| # | Item | Status | Evidence / Blocker |
|---|---|---|---|
| G-12 | ICM/Warp proven | BLOCKED | Depends on G-01 + G-06 + ICM relayer running. Deploy ICM relayer: see Teleporter relayer docs |
| G-13 | ICM retry/dedup proven | BLOCKED | Depends on G-12 |
| G-14 | ICM failure recovery proven | BLOCKED | Depends on G-12 |

### KEEPER

| # | Item | Status | Evidence / Blocker |
|---|---|---|---|
| G-15 | Keeper proven on testnet | BLOCKED | Depends on G-01 + G-08. Deploy: `systemctl start primewave-testnet-keeper` on infra-01 |
| G-16 | Keeper restart recovery proven | BLOCKED | Depends on G-15 |
| G-17 | Keeper authority bounded (cannot steal) | BLOCKED | Depends on G-15. Test: run `PW-C15-SECURITY-REVIEW.md §6` against live keeper |

### PUBLIC RPC

| # | Item | Status | Evidence / Blocker |
|---|---|---|---|
| G-18 | Public RPC proven | BLOCKED | Missing: cloud VPS + nginx + TLS. Provision rpc-01, copy `deploy/testnet/nginx/rpc.conf`, issue Let's Encrypt cert |
| G-19 | RPC security proven (admin methods blocked) | BLOCKED | Depends on G-18. Run admin method scan from `PW-C15-RPC-LOAD-TEST.md §2.2` |
| G-20 | RPC load test completed | BLOCKED | Depends on G-18. Run k6 script from `PW-C15-RPC-LOAD-TEST.md §3` |
| G-21 | Rate limiting verified | BLOCKED | Depends on G-18 |

### PWCSCAN + INDEXER

| # | Item | Status | Evidence / Blocker |
|---|---|---|---|
| G-22 | PWCScan proven on testnet | BLOCKED | Depends on G-18 (RPC) + G-23 (indexer). Deploy: `systemctl start primewave-testnet-pwcscan` on infra-01. Verify 🧪 Testnet badge + Chain ID 77 |
| G-23 | Indexer proven | BLOCKED | Depends on G-01. PostgreSQL available at Replit `PGHOST=helium` or deploy PostgreSQL on infra-01. Start: `systemctl start primewave-testnet-indexer` |
| G-24 | Indexer restart recovery proven | BLOCKED | Depends on G-23 |
| G-25 | Reindex proven | BLOCKED | Depends on G-23 |

### DATABASE

| # | Item | Status | Evidence / Blocker |
|---|---|---|---|
| G-26 | PostgreSQL recovery proven | BLOCKED | PostgreSQL IS available (Replit PGHOST=helium) but disaster recovery drill requires testnet data. Depends on G-23 being populated |
| G-27 | RPO measured | BLOCKED | Depends on G-26 |
| G-28 | RTO measured | BLOCKED | Depends on G-26 |

### PROTOCOL ECONOMICS

| # | Item | Status | Evidence / Blocker |
|---|---|---|---|
| G-29 | Fee distribution proven (70/20/10 on-chain) | BLOCKED | Depends on G-01 + deployed contracts |
| G-30 | RewardVault proven (15M PW, ≤3M/yr rate, no mint) | BLOCKED | Depends on G-01 + deployed contracts |
| G-31 | Staking proven | BLOCKED | Depends on G-01 |
| G-32 | 14-day unbond verified (real-time) | DEFERRED | Requires 14 calendar days on live testnet. Acceptable to begin C16 if G-32 soak is in progress and leadership accepts. Accelerated simulation documented in `PW-C15-TESTNET-BATTLE-TEST.md §8`. |

### GOVERNANCE

| # | Item | Status | Evidence / Blocker |
|---|---|---|---|
| G-33 | Governance proven on testnet | BLOCKED | Depends on G-01 + deployed contracts |
| G-34 | Emergency pause/unpause proven | BLOCKED | Depends on G-33 |
| G-35 | Timelock 48h proven | BLOCKED | Depends on G-33. Real 48h wait OR leadership-accepted simulation. |

### MONITORING + OPERATIONS

| # | Item | Status | Evidence / Blocker |
|---|---|---|---|
| G-36 | Monitoring proven | BLOCKED | Depends on G-06 + running infrastructure. Deploy: `cp deploy/testnet/prometheus/prometheus.yml /etc/prometheus/`, start Prometheus + Grafana on monitoring-01 |
| G-37 | Alert recovery cycle proven | BLOCKED | Depends on G-36 |
| G-38 | Backup/restore proven | BLOCKED | Depends on G-23 (indexer with real data). Scripts ready: `backup-testnet-db.sh`, `restore-testnet-db.sh` |
| G-39 | DNS/TLS verified | BLOCKED | Missing: DNS provider access + cloud server. Register A records for `rpc.testnet.*` and `explorer.testnet.*`, issue Let's Encrypt certs |

### PERFORMANCE + STABILITY

| # | Item | Status | Evidence / Blocker |
|---|---|---|---|
| G-40 | Performance measured | BLOCKED | Depends on G-01 + G-06 |
| G-41 | Soak test ≥24h or explicitly accepted | BLOCKED | Depends on live testnet. Cannot soak a non-existent network |
| G-42 | All failure recovery scenarios passed | BLOCKED | Depends on G-01 + G-06 |

### SECURITY

| # | Item | Status | Evidence / Blocker |
|---|---|---|---|
| G-43 | Security audit clean | BLOCKED | Depends on G-01 + deployed contracts |
| G-44 | No Critical findings outstanding | BLOCKED | Depends on G-43 |
| G-45 | No High findings outstanding | BLOCKED | Depends on G-43 |

### MAINNET PREPARATION

| # | Item | Status | Evidence / Blocker |
|---|---|---|---|
| G-46 | Mainnet deployment rehearsal complete | BLOCKED | Depends on G-01 (need live testnet to rehearse on) |
| G-47 | Mainnet Chain ID TBD or explicitly approved | ✅ PASS | TBD confirmed. All 1–99 taken per chainid.network 2026-08-15. Candidates: 149, 209, 229, 235, 241 |
| G-48 | Mainnet key ceremony procedure prepared | ✅ PASS | `PW-C15-MAINNET-READINESS.md §3` complete |
| G-49 | No mainnet private keys generated | ✅ PASS | Confirmed — only testnet-deployer generated |
| G-50 | PWC-20 not implemented (PROPOSED only) | ✅ PASS | Not touched in C14 or C15 |

### REGRESSION (IN-REPLIT VERIFIED 2026-08-15)

| # | Item | Status | Evidence |
|---|---|---|---|
| G-51 | Forge 792/792 | ✅ PASS | Run 2026-08-15 |
| G-52 | Indexer Jest 57/57 | ✅ PASS | Run 2026-08-15 |
| G-53 | Keeper Jest 20/20 | ✅ PASS | Run 2026-08-15 |

### ADDITIONAL IN-REPLIT VERIFIED ITEMS

| # | Item | Status | Evidence |
|---|---|---|---|
| G-54 | Genesis static invariants (Chain ID 77, 100M PW, NativeMinter disabled) | ✅ PASS | Python validation 2026-08-15 |
| G-55 | deploy-contracts.sh chain ID guard rejects wrong chain | ✅ PASS | Tested against dev chain 73571 — correctly rejected |
| G-56 | Fuji P-Chain API reachable from deployment environment | ✅ PASS | api.avax-test.network height 292884 confirmed |
| G-57 | testnet-deployer key generated (public key inventoried) | ✅ PASS | C-Chain: 0x2AD3152Ca630e2eF6679EBeb8da7b8311bfbFc60 |
| G-58 | testnet-deployer Fuji balance adequate (≥2 AVAX P-Chain) | BLOCKED | Current balance: 0 AVAX. Fund via faucet.avax.network → export C→P |
| G-59 | 6 genesis placeholders identified and documented | ✅ PASS | `__REPLACE_TESTNET_DEPLOYER_ADDRESS__` and 5 others — see `config/testnet/genesis-template.json` |
| G-60 | All C14 testnet config files consistent (Chain ID 77) | ✅ PASS | Verified 2026-08-15 via grep scan |

---

## GATE SUMMARY

| Category | Total Items | ✅ PASS | BLOCKED | DEFERRED | ❌ FAIL |
|---|---|---|---|---|---|
| Testnet Foundation | 5 | 0 | 5 | 0 | 0 |
| Validators | 6 | 0 | 6 | 0 | 0 |
| ICM/Warp | 3 | 0 | 3 | 0 | 0 |
| Keeper | 3 | 0 | 3 | 0 | 0 |
| RPC | 4 | 0 | 4 | 0 | 0 |
| PWCScan + Indexer | 4 | 0 | 4 | 0 | 0 |
| Database | 3 | 0 | 3 | 0 | 0 |
| Protocol Economics | 4 | 0 | 3 | 1 | 0 |
| Governance | 3 | 0 | 3 | 0 | 0 |
| Monitoring + Operations | 4 | 0 | 4 | 0 | 0 |
| Performance + Stability | 3 | 0 | 3 | 0 | 0 |
| Security | 3 | 0 | 3 | 0 | 0 |
| Mainnet Preparation | 5 | 3 | 1 | 0 | 0 |
| Regression | 3 | 3 | 0 | 0 | 0 |
| In-Replit Verified | 7 | 5 | 2 | 0 | 0 |
| **TOTAL** | **64** | **11** | **51** | **1** | **0** |

**C16 gate status: BLOCKED**

**PRIMARY BLOCKER:** External cloud infrastructure not provisioned.

**Minimum required to unblock:**
1. Fund `P-fuji1p25rk6kz9lwg2plwmfmvkvzxsa5qd02kla0vsw` with ≥ 2 AVAX via faucet.avax.network
2. Provision ≥ 3 cloud VPS servers (minimum viable testnet)
3. Register DNS records for testnet subdomains
4. Issue TLS certificates (Let's Encrypt)
5. Execute `avalanche blockchain deploy primewave-testnet --fuji --key testnet-deployer`
6. Fill genesis placeholders + generate genesis.json
7. Deploy validators + contracts + keeper + indexer + PWCScan
8. Execute C15 test matrix

See `docs/PW-C15-INFRA-PROVISIONING-GUIDE.md` for exact commands.

---

## STOP CONDITIONS (PERMANENTLY BLOCKING C16)

| Condition | Current Status |
|---|---|
| Mainnet private keys generated | ✅ NONE (only testnet-deployer generated) |
| Mainnet Chain ID changed without approval | ✅ TBD — unchanged |
| Testnet Chain ID 77 inconsistent | ✅ Consistent across all files |
| NativeMinter enabled | ✅ Disabled (genesis validated) |
| Fixed 100M supply broken | ✅ Confirmed (genesis validated) |
| RewardVault can mint | ✅ No mint path (NativeMinter disabled) |
| Fee split broken | ✅ 70/20/10 confirmed in all configs |
| ValidatorManager authority bypassed | ✅ Not bypassed in code |
| Critical or High security finding outstanding | ✅ None found in code (live audit pending) |
| Genesis not reproducible | BLOCKED — live ceremony pending |
| Production credentials in testnet | ✅ None committed |
