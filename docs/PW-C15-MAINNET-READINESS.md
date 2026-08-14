# PW-C15 — MAINNET READINESS AUDIT

**Sprint:** PW-C15 — Testnet Battle Test + Mainnet Readiness
**Status:** FRAMEWORK COMPLETE — Scores pending testnet execution
**Environment:** Covers testnet validation + mainnet preparation

---

## 1. MAINNET CHAIN ID — AUTHORITATIVE COLLISION CHECK

### 1.1 Requested Preference

The original requested preference was **29**.

Per the C15 spec (§36): "29 is already associated with another network. C15 MUST NOT lock 29."

Chain ID 29 is registered on chainlist.network. Do not use it.

### 1.2 Two-Digit Availability

A live query of `chainid.network/chains.json` was performed on **2026-08-15** in-Replit:

```
Total 1–99 taken: 99 of 99
Available two-digit IDs: NONE
```

**All 99 two-digit EVM chain IDs (1–99) are registered.** A two-digit mainnet chain ID is not possible at this time.

### 1.3 Three-Digit Candidates

From the same chainid.network query (chains.json, 2026-08-15), first available three-digit IDs:

```
149, 209, 219, 229, 231, 235, 241, 243, 244, 245, 249, 257...
```

**Five recommended candidates for leadership review:**

| Candidate | Notes | Conflicts Observed |
|---|---|---|
| **149** | Clean; not associated with major L1 or L2 | None at query time |
| **209** | Clean; memorable | None at query time |
| **229** | Clean; near preferred range | None at query time |
| **235** | Clean | None at query time |
| **241** | Clean | None at query time |

### 1.4 Mandatory Verification Before Finalization

> **DO NOT finalize mainnet Chain ID without:**
>
> 1. Re-running `curl chainid.network/chains.json` and confirming availability is still current (the list changes frequently — new chains register monthly)
> 2. Cross-checking against EIP-155 registry: https://github.com/ethereum/EIPs/blob/master/EIPS/eip-155.md
> 3. Cross-checking against https://chainlist.org (human-readable view)
> 4. Explicit approval from PrimeWave leadership
>
> **Current status: MAINNET CHAIN ID = TBD**

---

## 2. MAINNET READINESS AUDIT

Each domain is evaluated as **PASS**, **FAIL**, or **DEFERRED**.

---

### 2.1 Architecture

| Item | Status | Notes |
|---|---|---|
| L1 subnet-evm architecture documented | PASS | docs/PRIMEWAVE_CHAIN_ARCHITECTURE.md |
| Avalanche L1 ACP-99 compliant | PASS | C09/C10 validated via 792/792 tests |
| Fuji P-Chain integration designed | PASS | C14 runbook; C15 execution pending |
| ICM/Warp integration designed | PASS | C09 keeper; C15 live test pending |
| PoA Phase 1 architecture locked | PASS | PoAManager; no PoS transition in C15 |
| PoS Phase 2 design complete | PASS | C09 PrimeWaveStakingManager; transition TBD |

**Architecture overall:** PASS (design + code) / DEFERRED (live network validation)

---

### 2.2 Genesis

| Item | Status | Notes |
|---|---|---|
| Genesis template complete | PASS | config/testnet/genesis-template.json |
| Chain ID 77 (testnet) locked | PASS | Verified via validator script |
| NativeMinter disabled | PASS | Confirmed in template + tests |
| 100M PW supply invariant | PASS | Python validation + C15 regression |
| 15M PW RewardVault funded | PASS | Template allocation correct |
| 70/20/10 FeeDistributor configured | PASS | RewardManager config correct |
| Genesis reproducibility | DEFERRED | Requires live ceremony execution |
| No production addresses in testnet | DEFERRED | Requires ceremony addresses |

**Genesis overall:** PASS (template + tooling) / DEFERRED (live ceremony)

---

### 2.3 Keys

| Item | Status | Notes |
|---|---|---|
| Testnet key generation script | PASS | scripts/testnet/generate-validator-keys.sh |
| Key security procedure documented | PASS | docs/PRIMEWAVE_KEY_SECURITY_PROCEDURE.md |
| No dev keys in testnet | DEFERRED | Ceremony not yet executed |
| No mainnet private keys generated | PASS | ✅ None generated |
| Mainnet key ceremony procedure | PASS | See §3 of this document |
| HSM / hardware security guidance | PASS | In key security procedure doc |

**Keys overall:** PASS (procedure + tooling) / DEFERRED (actual ceremony)

---

### 2.4 Validators

| Item | Status | Notes |
|---|---|---|
| Validator onboarding procedure | PASS | docs/PW-C14-VALIDATOR-ONBOARDING.md |
| ACP-99 lifecycle designed + tested | PASS | C09/C10 Forge tests |
| Real validator node deployment | DEFERRED | Requires cloud servers |
| 15 validators operational | DEFERRED | Requires Fuji + cloud |
| Multi-node consistency verified | DEFERRED | Requires live testnet |
| Validator churn tested | DEFERRED | Requires live testnet |

**Validators overall:** DEFERRED (cloud infrastructure required)

---

### 2.5 RPC

| Item | Status | Notes |
|---|---|---|
| Public RPC nginx config | PASS | deploy/testnet/nginx/rpc.conf |
| TLS configuration templated | PASS | C14 deploy package |
| Admin method blocking specified | PASS | C15 RPC load test doc |
| RPC deployed and live | DEFERRED | Requires testnet |
| Load test completed | DEFERRED | Requires live RPC |
| Rate limiting verified | DEFERRED | Requires live RPC |

**RPC overall:** DEFERRED (live network required)

---

### 2.6 ICM / ACP-99

| Item | Status | Notes |
|---|---|---|
| ACP-99 contracts coded + tested | PASS | 792/792 Forge tests |
| ICM/Warp integration coded | PASS | C09 keeper + C10 tests |
| Real Fuji Warp message tested | DEFERRED | Requires Fuji testnet |
| Message dedup verified | DEFERRED | Requires live ICM relayer |
| Retry/failure recovery tested | DEFERRED | Requires live ICM relayer |

**ICM/ACP-99 overall:** PASS (code) / DEFERRED (live execution)

---

### 2.7 Keeper

| Item | Status | Notes |
|---|---|---|
| Keeper coded + tested | PASS | 20/20 Jest tests |
| Keeper deployment config | PASS | systemd + env template |
| Keeper live on testnet | DEFERRED | Requires live testnet |
| Restart recovery tested | DEFERRED | Requires live testnet |
| Duplicate prevention verified | DEFERRED | Requires live testnet |

**Keeper overall:** PASS (code) / DEFERRED (live execution)

---

### 2.8 Governance

| Item | Status | Notes |
|---|---|---|
| EmergencyMultisig (3-of-5) coded + tested | PASS | 792/792 Forge tests |
| Timelock (48h) coded + tested | PASS | 792/792 Forge tests |
| Governance deployed on testnet | DEFERRED | Requires live testnet |
| Governance battle test executed | DEFERRED | Requires live testnet |
| Emergency powers verified limited | DEFERRED | Requires live testnet |

**Governance overall:** PASS (code) / DEFERRED (live testnet)

---

### 2.9 Rewards

| Item | Status | Notes |
|---|---|---|
| RewardVault coded + tested | PASS | 282/282 relevant Forge tests |
| 3M PW/year cap enforced | PASS | Tested in Forge |
| totalEmitted write-only | PASS | C06 pitfall documented |
| RewardVault live battle test | DEFERRED | Requires live testnet |
| Emission rate verified on-chain | DEFERRED | Requires live testnet |

**Rewards overall:** PASS (code) / DEFERRED (live testnet)

---

### 2.10 Fees

| Item | Status | Notes |
|---|---|---|
| FeeDistributor 70/20/10 coded + tested | PASS | 792/792 Forge tests |
| Conservation invariant tested | PASS | Tested in Forge |
| Live fee distribution verified | DEFERRED | Requires live testnet |
| Rounding edge cases live | DEFERRED | Requires live testnet |
| Validator churn fee accounting | DEFERRED | Requires live testnet |

**Fees overall:** PASS (code) / DEFERRED (live testnet)

---

### 2.11 Indexer

| Item | Status | Notes |
|---|---|---|
| Indexer coded + tested | PASS | 57/57 Jest tests; 17-table schema |
| All endpoints implemented | PASS | 20+ REST endpoints |
| Live testnet indexing | DEFERRED | Requires live testnet |
| Integrity checks on live data | DEFERRED | Requires live testnet |
| Database disaster recovery | DEFERRED | Requires live testnet |

**Indexer overall:** PASS (code) / DEFERRED (live testnet)

---

### 2.12 Database

| Item | Status | Notes |
|---|---|---|
| PostgreSQL schema designed | PASS | 17-table C12 schema |
| Backup script present | PASS | scripts/testnet/backup-testnet-db.sh |
| Restore script present | PASS | scripts/testnet/restore-testnet-db.sh |
| RPO/RTO measured on testnet | DEFERRED | Requires live testnet |
| Disaster recovery drill | DEFERRED | Requires live testnet |

**Database overall:** PASS (design + scripts) / DEFERRED (live DR drill)

---

### 2.13 PWCScan

| Item | Status | Notes |
|---|---|---|
| PWCScan coded + locally verified | PASS | C13 complete; dev chain tested |
| Testnet badge (🧪 Testnet) | PASS | C14 — VITE_NETWORK_LABEL |
| Chain ID 77 displayed | PASS | VITE_CHAIN_ID=77 configured |
| No mocked data | PASS | All data from indexer/RPC |
| PWCScan live on testnet | DEFERRED | Requires live testnet |
| All explorer routes verified live | DEFERRED | Requires live testnet |

**PWCScan overall:** PASS (code + config) / DEFERRED (live testnet)

---

### 2.14 Monitoring

| Item | Status | Notes |
|---|---|---|
| Prometheus config present | PASS | deploy/testnet/prometheus/ |
| Alert rules defined | PASS | alert-rules.yml |
| Systemd unit for monitoring | PASS | C14 deploy package |
| Live monitoring verified | DEFERRED | Requires live testnet |
| Controlled alert test | DEFERRED | Requires live testnet |

**Monitoring overall:** PASS (config) / DEFERRED (live testnet)

---

### 2.15 Backups

| Item | Status | Notes |
|---|---|---|
| DB backup procedure | PASS | Script present and tested conceptually |
| Node state backup guidance | PASS | Documented in validator ops |
| Config backup procedure | PASS | Documented |
| No private keys stored insecurely | PASS | Procedure enforces encryption |
| Live backup/restore drill | DEFERRED | Requires live testnet |

**Backups overall:** PASS (procedure) / DEFERRED (live drill)

---

### 2.16 Security

| Item | Status | Notes |
|---|---|---|
| Smart contract security (Forge) | PASS | 792/792 tests including security scenarios |
| C10 security attack tests | PASS | All 745→792 tests passing |
| Live testnet security tests | DEFERRED | Requires live testnet |
| RPC admin method blocking | DEFERRED | Requires live RPC |
| Key ceremony security | PASS | Procedure documented |
| No mainnet private keys | PASS | ✅ Confirmed — none generated |

**Security overall:** PASS (code/procedure) / DEFERRED (live testnet audit)

---

### 2.17 Deployment

| Item | Status | Notes |
|---|---|---|
| Deployment scripts complete | PASS | scripts/testnet/ fully scripted |
| Systemd units present | PASS | deploy/testnet/systemd/ |
| Nginx configs present | PASS | deploy/testnet/nginx/ |
| Env templates present | PASS | deploy/testnet/env/ |
| Actual testnet deployed | DEFERRED | Requires external infra |
| Deployment rehearsal executed | DEFERRED | Requires external infra |

**Deployment overall:** PASS (scripts) / DEFERRED (execution)

---

### 2.18 Documentation

| Item | Status | Notes |
|---|---|---|
| Architecture docs (C00–C14) | PASS | 20+ architecture docs |
| C14 testnet deployment docs (11 files) | PASS | All updated to Chain ID 77 |
| C15 operational docs (12 files) | PASS | This sprint |
| Validator onboarding guide | PASS | PW-C14-VALIDATOR-ONBOARDING.md |
| Failure recovery runbook | PASS | PW-C14-FAILURE-RECOVERY.md + C15 |
| Deployment runbook | PASS | PW-C14-DEPLOYMENT-RUNBOOK.md |

**Documentation overall:** PASS

---

## 3. MAINNET KEY CEREMONY PROCEDURE

> DO NOT generate mainnet private keys during C15. The ceremony belongs to C16.

### 3.1 Roles Required

| Role | Count | Responsibility |
|---|---|---|
| Ceremony Lead | 1 | Coordinates procedure; does not hold keys |
| Key Holders | 5 | Each holds 1 of 5 multisig keys |
| Independent Witnesses | 2 | Observe generation; sign attestation |
| Security Auditor | 1 | Verifies hardware and procedure |
| Backup Key Custodians | 3 | Encrypted backup holders (separate from key holders) |

### 3.2 Hardware Requirements

| Requirement | Specification |
|---|---|
| Key generation device | Air-gapped laptop (never connected to internet) |
| Entropy source | Hardware RNG (e.g., OneRNG or YubiKey HSM) |
| Storage medium | Hardware security module (HSM) preferred; encrypted USB as fallback |
| Verification device | Separate air-gapped device to verify outputs |
| Destruction device | Physical shredder or degausser for paper backups |

### 3.3 Geographic Separation

- Key holders must be in at least 3 different physical locations
- No two key holders in the same datacenter, building, or city
- Backup custodians in different jurisdictions from key holders

### 3.4 Ceremony Checklist

```
[ ] Hardware sourced and security-audited (no pre-installed malware)
[ ] Air-gap verified (Faraday cage or physical disconnection)
[ ] RNG entropy verified
[ ] All witnesses present (in person or verified video call)
[ ] Generate 5 multisig key pairs on air-gapped hardware
[ ] Generate deployer key on air-gapped hardware
[ ] Generate treasury key on air-gapped hardware
[ ] Generate keeper key on separate device
[ ] Verify all public keys match expected addresses
[ ] Record public keys + predicted contract addresses
[ ] Encrypt and distribute private keys to individual key holders
[ ] Verify each key holder can decrypt their key
[ ] Destroy intermediate artifacts (unencrypted files, paper)
[ ] Witnesses sign attestation
[ ] Security auditor signs attestation
[ ] All attestations stored in project records
[ ] Rotation procedure documented and tested with test keys
```

### 3.5 Recovery Procedure

If one key is lost:
- 3-of-5 multisig still functions with remaining 4 keys
- Initiate key rotation via timelock after 48h
- Replace lost key holder; repeat ceremony for replacement key only

### 3.6 Rotation Policy

- Rotate all keys at minimum every 12 months
- Rotate immediately on suspected compromise
- Emergency rotation uses emergency multisig + timelock
- Rotation ceremony follows same security level as initial ceremony

### 3.7 Secure Destruction

At end of testnet lifecycle:
- Cryptographically wipe all testnet key material
- Physical destruction for any paper records
- Document destruction per security policy

---

## 4. DEPLOYMENT REHEARSAL PROCEDURE

A mainnet deployment rehearsal must be performed on testnet credentials
before C16 begins.

### 4.1 Rehearsal Sequence

```
1. Genesis construction (testnet addresses → simulated mainnet)
2. Node provisioning (same scripts, testnet hardware)
3. Validator initialization (ACP-99 on Fuji testnet)
4. Contract deployment (DeployTestnet.s.sol against testnet)
5. Governance configuration (EmergencyMultisig 3-of-5 testnet keys)
6. RewardVault funding (15M PW transfer from genesis alloc)
7. Keeper deployment (testnet keeper key)
8. Indexer deployment (connect to testnet RPC)
9. PWCScan deployment (VITE_CHAIN_ID=77, VITE_NETWORK_LABEL=Testnet)
10. Monitoring deployment (Prometheus + Grafana)
11. Health checks (all 8 HC-xx checks pass)
```

### 4.2 Rehearsal Pass/Fail Criteria

| Step | Pass Criterion | Status |
|---|---|---|
| Genesis construction | Identical genesis hash each run | 🔵 PENDING |
| Node provisioning | Validator joins subnet | 🔵 PENDING |
| Validator initialization | ACP-99 registration confirmed | 🔵 PENDING |
| Contract deployment | All 8 contracts at predicted addresses | 🔵 PENDING |
| Governance config | 3-of-5 confirmed; timelock set | 🔵 PENDING |
| RewardVault funding | 15M PW confirmed on-chain | 🔵 PENDING |
| Keeper deployment | syncValidator fires within 5m | 🔵 PENDING |
| Indexer deployment | Syncs to tip within 30m | 🔵 PENDING |
| PWCScan deployment | All routes load; Chain ID 77 shown | 🔵 PENDING |
| Monitoring | Prometheus scraped; alerts tested | 🔵 PENDING |
| Health checks | All HC-xx: PASS | 🔵 PENDING |

**Acceptance:** The rehearsal must be reproducible — same steps, same outcome, twice.

---

## 5. MAINNET READINESS SUMMARY

| Domain | Code/Design | Live Testnet | Overall |
|---|---|---|---|
| Architecture | PASS | DEFERRED | DEFERRED |
| Genesis | PASS | DEFERRED | DEFERRED |
| Keys | PASS | DEFERRED | DEFERRED |
| Validators | PASS | DEFERRED | DEFERRED |
| RPC | PASS | DEFERRED | DEFERRED |
| ICM/ACP-99 | PASS | DEFERRED | DEFERRED |
| Keeper | PASS | DEFERRED | DEFERRED |
| Governance | PASS | DEFERRED | DEFERRED |
| Rewards | PASS | DEFERRED | DEFERRED |
| Fees | PASS | DEFERRED | DEFERRED |
| Indexer | PASS | DEFERRED | DEFERRED |
| Database | PASS | DEFERRED | DEFERRED |
| PWCScan | PASS | DEFERRED | DEFERRED |
| Monitoring | PASS | DEFERRED | DEFERRED |
| Backups | PASS | DEFERRED | DEFERRED |
| Security | PASS | DEFERRED | DEFERRED |
| Deployment | PASS | DEFERRED | DEFERRED |
| Documentation | PASS | N/A | PASS |

**Overall Mainnet Readiness:**
- Code and procedures: ✅ READY (792/792 + 57/57 + 20/20 + all docs)
- Live testnet execution: 🔵 PENDING EXTERNAL INFRASTRUCTURE
- C16 eligibility: Blocked until live testnet passes all battle tests

**Mainnet Chain ID status:** TBD — all two-digit IDs taken; three-digit candidates
(149, 209, 229, 235, 241) recommended pending leadership approval.
