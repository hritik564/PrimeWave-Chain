# PrimeWave Chain — Final Pre-Ceremony Check
## PW-C15 | 2026-08-16 | READ-ONLY VERIFICATION

**Purpose:** Final gate check before the Fuji L1 ceremony  
**Scope:** Live funding, node status, bootstrap-validators.json, genesis-template.json, placeholder audit  
**Executed:** Automated live checks via Replit → SSH and public Fuji RPC

---

## 1. LIVE FUNDING VERIFICATION

### Deployer C-Chain Address

```
0x44A37aF5F03807B1AaA1b20D1BFb3d77959B4B5f
```

### Fuji C-Chain Balance (live query)

| Field | Value |
|---|---|
| RPC endpoint | `https://api.avax-test.network/ext/bc/C/rpc` |
| Method | `eth_getBalance` |
| Raw result | `0x1bc16d674ec80000` |
| **Balance** | **2.0 AVAX** ✅ |
| Nonce (tx count) | 0 (no transactions sent yet) |

The operator reported funding 0.99 AVAX. The actual on-chain balance is **2.0 AVAX**, which exceeds the requirement. Nonce=0 confirms no ceremony transactions have been executed yet.

**Minimum required for ceremony:** ~1.5 AVAX (4 validators × 0.375 AVAX `Balance` field)  
**Current balance:** 2.0 AVAX ✅ **sufficient**

---

## 2. DEPLOYER P-CHAIN ADDRESS

### Key availability

The testnet-deployer private key was generated during the PW-C15 key ceremony and stored at:
```
~/.primewave-keys/testnet-deployer.json
```

This path is in the Replit container's **ephemeral home directory**, which does not survive container restarts. The file is **not present** in the current environment. The workspace (`local-data/testnet-key-addresses.env`) correctly notes: *"Private keys stored at: ~/.primewave-keys/ (NOT in git)"*.

The Avalanche CLI key store at `~/.avalanche-cli/key/` contains only the `ewoq` development key — the testnet-deployer was never imported.

**P-Chain address: NOT DERIVABLE from the current environment.**

### How to derive the P-Chain address (operator action required)

The P-Chain address uses a different derivation from the C-Chain address (SHA256+RIPEMD160 of the compressed public key, then Bech32). It **cannot** be derived from the C-Chain address alone.

**Option A — if the private key file is available on the operator's machine:**
```bash
# Import the key into Avalanche CLI
./local-bin/avalanche key import ~/.primewave-keys/testnet-deployer.json \
  --key-name testnet-deployer

# List to get the P-Chain address
./local-bin/avalanche key list --fuji
# Look for "P-fuji1..." under the testnet-deployer row
```

**Option B — if you have the hex private key:**
```bash
# Using avalanche key import with a private key string
./local-bin/avalanche key import <(echo "0x<private_key_hex>") \
  --key-name testnet-deployer
./local-bin/avalanche key list --fuji
```

**Option C — if you prefer a one-liner (no CLI import):**
```bash
# Python derivation (secp256k1 + SHA256 + RIPEMD160 + Bech32)
python3 scripts/testnet/derive-pchain-addr.py 0x<private_key_hex>
```
(This script does not exist yet; use Option A or B.)

Once known, the P-Chain address must be substituted into `config/testnet/bootstrap-validators.json` at all 4 `ChangeOwnerAddr` fields, replacing `P-fuji1__REPLACE_DEPLOYER_P_CHAIN_ADDR__`.

---

## 3. V6–V9 P-CHAIN BOOTSTRAP STATUS (LIVE)

Checked via SSH + `info.isBootstrapped` + `platform.getHeight` + `info.peers` at time of report.

| Node | IP | SVC | Restarts | isBootstrapped (P) | P-Chain Height | Peers | Errors |
|---|---|---|---|---|---|---|---|
| **V6** | 152.53.66.93 | active | 0 | **True** ✅ | **293022** | 55 | 0 |
| **V7** | 152.53.66.201 | active | 0 | **True** ✅ | **293022** | 55 | 0 |
| **V8** | 159.195.44.104 | active | 0 | **True** ✅ | **293022** | 55 | 0 |
| **V9** | 159.195.47.126 | active | 0 | **True** ✅ | **293022** | 55 | 0 |

**All 4 nodes are fully P-Chain bootstrapped.** Height 293022 is the current Fuji P-Chain tip; all 4 nodes have synced to the same point. The `health.bootstrapped` check is passing on all nodes.

These nodes use `partial-sync-primary-network: true`, so there is no C-Chain historical sync — only P-Chain state is needed for L1 registration, and it is complete.

The `Last-progress` log for all 4 nodes shows:
```json
{ "msg": "check started passing", "name": "bootstrapped", "tags": ["application"] }
```

**No restart needed. No action needed. Nodes are ceremony-ready.**

---

## 4. BOOTSTRAP-VALIDATORS.JSON VALIDATION

**File:** `config/testnet/bootstrap-validators.json`

### Structural checks

| Check | Result |
|---|---|
| Valid JSON | ✅ |
| Exactly 4 validators | ✅ |
| All 4 NodeIDs unique | ✅ (confirmed unique, cross-checked against V2–V5) |
| All 4 BLS public keys unique | ✅ |
| All 4 BLS proofs of possession present | ✅ |
| Weight=100 for all 4 | ✅ |
| Balance=0.375 for all 4 | ✅ |
| ChangeOwnerAddr identical and correct | ❌ **PLACEHOLDER UNRESOLVED** |
| No other unresolved placeholders | ✅ |

### Current validator table

| # | NodeID | BLS PubKey (prefix) | BLS PoP (prefix) | ChangeOwnerAddr |
|---|---|---|---|---|
| 1 | `NodeID-144dTzcL2vgpbKzX943xy5pEF3M8oGyiQ` | `0xafec5f...` | `0x950565...` | ❌ `P-fuji1__REPLACE...` |
| 2 | `NodeID-cwX3HFmaR5QmbxuZaDJCXAueJeyewjni` | `0xa73965...` | `0x93bed7...` | ❌ `P-fuji1__REPLACE...` |
| 3 | `NodeID-7DLuPUaMiDbyVoZ6P92RQdNRFS81cpYb5` | `0xa61adb...` | `0x90ef97...` | ❌ `P-fuji1__REPLACE...` |
| 4 | `NodeID-9TiHzx7DZgtCjB9pqyY6db55pZgVZELvJ` | `0x932046...` | `0x9571c3...` | ❌ `P-fuji1__REPLACE...` |

### Weight and quorum

Total weight = 4 × 100 = 400. The `warpConfig.quorumNumerator = 67` in genesis means 67% stake weight required for Warp signing. With 4 equal validators, 3/4 (75%) satisfies the threshold. This matches the documented PrimeWave architecture (4 validators, 3-of-4 for Warp quorum).

### Single remaining gap

`ChangeOwnerAddr` must be set to `P-fuji1<deployer-p-chain-addr>` on all 4 entries.  
This is a **one-line, one-value fill** — same address repeated 4 times.  
See Section 2 for derivation steps.

---

## 5. GENESIS-TEMPLATE.JSON VALIDATION

**File:** `config/testnet/genesis-template.json`

### Placeholder inventory (7 total)

| Placeholder | Location in file | Value to substitute | Status |
|---|---|---|---|
| `__REPLACE_FEE_DISTRIBUTOR_ADDRESS__` | `config.rewardManagerConfig.initialRewardConfig.rewardAddress` | `0xFd069eE048bB748EE60ce53f99D8c2E6ec1D7f99` | ✅ RESOLVABLE |
| `__REPLACE_TESTNET_DEPLOYER_ADDRESS__` | `alloc` key | `0x44A37aF5F03807B1AaA1b20D1BFb3d77959B4B5f` | ✅ RESOLVABLE |
| `__REPLACE_TESTNET_TREASURY_ADDRESS__` | `alloc` key | `0x1F471d2Dc7CB8b2C773aFeD40d4bD467ed1FdaD8` | ✅ RESOLVABLE |
| `__REPLACE_TESTNET_TEAM_ADDRESS__` | `alloc` key | `0x46a419514f52A4763596F75A9169B0Bd0153C673` | ✅ RESOLVABLE |
| `__REPLACE_TESTNET_COMMUNITY_ADDRESS__` | `alloc` key | `0xA6744C599A0d40082aAF03Bd643cfc30B2B16a0c` | ✅ RESOLVABLE |
| `__REPLACE_TESTNET_ECOSYSTEM_ADDRESS__` | `alloc` key | `0x2c5E541f667768dd1986C73530Dc29250fA86B7B` | ✅ RESOLVABLE |
| `__REPLACE_TESTNET_RESERVE_ADDRESS__` | `alloc` key | `0x3C98105b99bb9dc97B341D11ec264F5127A7221C` | ✅ RESOLVABLE |

**All 7 placeholders are resolvable.** All required data is known.

### FeeDistributor address verification

`0xFd069eE048bB748EE60ce53f99D8c2E6ec1D7f99` was predicted using `cast compute-address` at deployer nonce=4:

```
deployer = 0x44A37aF5F03807B1AaA1b20D1BFb3d77959B4B5f
nonce    = 4  (after: EMS, Timelock, FeeVault, DevTreasury)
result   = 0xFd069eE048bB748EE60ce53f99D8c2E6ec1D7f99
```

Deployer's on-chain nonce is currently **0** (confirmed via `eth_getTransactionCount`), so the prediction remains valid. The deployment script (`DeployTestnet.s.sol` line 136) also contains a runtime assertion:
```solidity
require(address(feeDist) == predictedFD, "DeployTestnet: FeeDistributor address prediction mismatch");
```

This will cause the deployment to revert if prediction is wrong, providing a hard safety check.

### Genesis allocation check

| Wallet | Address | PW Amount | Balance (hex) |
|---|---|---|---|
| Deployer | `0x44A37aF5...` | 16M | `0xd3c21bcecceda10000000` |
| Treasury | `0x1F471d2D...` | 25M | `0x14adf4b7320334b9000000` |
| Team | `0x46a41951...` | 20M | `0x108b2a2c28029094000000` |
| Community | `0xA6744C59...` | 20M | `0x108b2a2c28029094000000` |
| Ecosystem | `0x2c5E541f...` | 10M | `0x84595161401484a000000` |
| Reserve | `0x3C98105b...` | 9M | `0x771d2fa45345aa9000000` |
| **Total** | | **100M PW** | |

Total supply = 100M PW. ✅ Matches documented tokenomics.

The RewardVault receives 15M PW from the Deployer allocation post-deployment via `DeployTestnet.s.sol:fundRewardVault()`, leaving the Deployer with 1M PW for operations.

### Address(0) check

No `address(0)` appears in any genesis alloc key or config value. ✅

### EMS signer configuration

EMS signers are **not** in genesis JSON — they are set during **contract deployment** (correct architecture). Confirmed populated in `contracts/script/DeployTestnet.s.sol`:

```solidity
address constant EMS_SIGNER_1 = 0xb24F3FAF5B9ab7aFb625F105C791d5231b094853; // testnet-ems-signer-1
address constant EMS_SIGNER_2 = 0x508367082eF7A3A8567fa10D92c98524EE2F3d30; // testnet-ems-signer-2
address constant EMS_SIGNER_3 = 0xFa21258c9e5faa7aECbFD13f635863C5da0b8EC3; // testnet-ems-signer-3
address constant EMS_SIGNER_4 = 0xB1346A22773B853552aF028b767bD6cC0171006a; // testnet-ems-signer-4
address constant EMS_SIGNER_5 = 0x2D2d07AB95636Da735BAcBDC018420ca621C3448; // testnet-ems-signer-5
```

The script also contains a guard at line 89–93:
```solidity
require(
    EMS_SIGNER_1 != address(0) && EMS_SIGNER_2 != address(0) &&
    EMS_SIGNER_3 != address(0) && EMS_SIGNER_4 != address(0) &&
    EMS_SIGNER_5 != address(0),
    ...
```

**All 5 EMS signer slots are populated with real addresses. No address(0) remains.** ✅

---

## 6. UNRESOLVED PLACEHOLDERS AND TODOs — FULL AUDIT

Grep scope: all `.json`, `.sh`, `.md`, `.sol`, `.env` files in the repo.

### Blockers (unresolved for ceremony)

| Location | Placeholder | Resolution |
|---|---|---|
| `config/testnet/bootstrap-validators.json` (×4) | `P-fuji1__REPLACE_DEPLOYER_P_CHAIN_ADDR__` | Derive from testnet-deployer private key (Section 2) |

### Non-blockers (correctly deferred or documented as future work)

| Location | Pattern | Reason NOT a blocker |
|---|---|---|
| `scripts/testnet/setup-testnet-node.sh` | `__REPLACE_BLOCKCHAIN_ID__` | Expected — blockchain ID is generated at ceremony, filled afterward |
| `docs/PRIMEWAVE_PWUSD_ARCHITECTURE.md` et al. | `MONETARY_AUTHORITY_ADDRESS = PLACEHOLDER` | PWUSD mainnet future work, not testnet ceremony dependency |
| `docs/PW-C00-FINAL-GATE.md` et al. | `PLACEHOLDER` (various) | Historical/locked design docs, not ceremony inputs |
| `docs/PW-C15-FUJI-CEREMONY-RUNBOOK.md` | `NodeID-<...>` examples | Template examples in the runbook itself, not config data |
| `contracts/src/FeeDistributor.sol` etc. | `address(0)` | Guard clauses (check that a value is NOT address(0)), correct |

### Previously-flagged items now resolved

| Item | Previous status | Current status |
|---|---|---|
| Deployer AVAX funding | ❌ 0 AVAX | ✅ 2.0 AVAX confirmed |
| 5 genesis wallet addresses | ❌ Not supplied | ✅ All 5 supplied by operator |
| V6–V9 P-Chain bootstrap | ❌ Not provisioned | ✅ All 4 bootstrapped, height=293022 |
| partial-sync-primary-network flag | ❌ Was missing | ✅ Confirmed active on all 4 nodes |
| bootstrap-validators.json NodeIDs/BLS | ❌ Template only | ✅ All 4 real identities populated |
| EMS signer addresses in deployment script | ❌ Was deployer address | ✅ 5 real addresses |
| POA_MANAGER_ADDR in deployment script | ❌ Was deployer placeholder | ✅ `0x0Feedc0de...` |

---

## 7. REMAINING EXTERNAL PREREQUISITES

| # | Item | Status | Action |
|---|---|---|---|
| 1 | **Deployer P-Chain address** | ❌ Key not in environment | Operator: derive P-Chain address from private key (see Section 2), then update `bootstrap-validators.json` |
| 2 | **`avalanche blockchain create primewave-testnet`** | ❌ Not yet run | Ceremony step — run after `ChangeOwnerAddr` is filled |
| 3 | Fill **genesis-template.json** | ⏳ Data all available | Ceremony step — all 7 substitutions known, fill before `avalanche blockchain create` |

Everything else that was previously listed as a gate is now resolved.

---

## 8. GO / NO-GO DECISION

```
┌─────────────────────────────────────────────────────────────────────┐
│                    CEREMONY READINESS STATUS                         │
├────────────────────────────────────────────────┬────────────────────┤
│ Deployer AVAX funding (2.0 AVAX on-chain)      │ ✅ GO              │
│ V6 P-Chain bootstrapped (height 293022)         │ ✅ GO              │
│ V7 P-Chain bootstrapped (height 293022)         │ ✅ GO              │
│ V8 P-Chain bootstrapped (height 293022)         │ ✅ GO              │
│ V9 P-Chain bootstrapped (height 293022)         │ ✅ GO              │
│ All 4 NodeIDs unique (cross-checked V2–V9)      │ ✅ GO              │
│ All 4 BLS public keys populated                 │ ✅ GO              │
│ All 4 BLS proofs of possession populated        │ ✅ GO              │
│ 5 genesis wallet addresses supplied             │ ✅ GO              │
│ FeeDistributor address verified (nonce=4)       │ ✅ GO              │
│ EMS signers populated in deployment script      │ ✅ GO              │
│ POA_MANAGER_ADDR correct in deployment script   │ ✅ GO              │
│ genesis-template.json — all 7 data known        │ ✅ GO              │
│ No address(0) in ceremony-critical paths        │ ✅ GO              │
│ No fatal errors on any V6–V9 node               │ ✅ GO              │
├────────────────────────────────────────────────┼────────────────────┤
│ ChangeOwnerAddr in bootstrap-validators.json    │ ❌ BLOCKED         │
│   → Deployer P-Chain address not in env         │                    │
├────────────────────────────────────────────────┴────────────────────┤
│                                                                      │
│   VERDICT: CONDITIONAL GO                                            │
│                                                                      │
│   Everything is ready except one item: the deployer's Fuji          │
│   P-Chain address must be derived from the private key and          │
│   substituted into bootstrap-validators.json (4 identical           │
│   ChangeOwnerAddr fields).                                           │
│                                                                      │
│   Once that single fill is done, the project is ready for the       │
│   Fuji L1 ceremony:                                                  │
│     Step 1: Fill genesis-template.json (all data known)             │
│     Step 2: avalanche blockchain create primewave-testnet            │
│     Step 3: ConvertSubnetToL1Tx (via Avalanche CLI)                 │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

*Report generated: 2026-08-16 | PW-C15 | All node checks live at time of generation*
