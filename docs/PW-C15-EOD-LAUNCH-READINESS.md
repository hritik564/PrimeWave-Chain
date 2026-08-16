# PrimeWave Testnet — EOD Launch Readiness Report
## PW-C15 | 2026-08-16 | GO / NO-GO Assessment

**Prepared by:** PW-C15 Sprint  
**Status:** NO-GO — External gates blocking  
**Next action:** Provision 4 VPS validators → collect node identities → fund deployer on Fuji → fill genesis addresses → run ceremony

---

## EXECUTIVE SUMMARY

All Replit-side preparation is complete. The code is correct and ready to execute. Launch is blocked by four external gates that require operator action outside Replit: VPS provisioning, Fuji AVAX funding, collection of 5 additional genesis wallet addresses, and node identity collection after servers are provisioned.

**Estimated time from operator-go to chain-live:** 2.5–3.5 hours

---

## PART 1 — WHAT WAS DONE THIS SPRINT (PW-C15)

### 1.1 Architecture Confirmed

**ValidatorManager/PoAManager flow — fully resolved:**

| Question | Answer |
|---|---|
| What is the ValidatorManager for Phase 1? | `PoAManager` from ava-labs/icm-contracts, wrapped as `ERC1967Proxy` |
| Where does it live? | On PrimeWave L1 itself, as a genesis predeploy |
| What is its address? | `0x0FEEDC0DE0000000000000000000000000000000` (Avalanche CLI standard) |
| Who deploys it? | The Avalanche CLI as part of `blockchain deploy --proof-of-authority --acp99` |
| How is it referenced in `ConvertSubnetToL1Tx`? | `validatorManagerBlockchainID` = L1's own chain ID; `validatorManagerAddress` = `0x0FEEDC0DE...` |
| Does genesis template include it? | No — CLI augments genesis during `blockchain deploy` |
| Can `PrimeWaveValidatorRegistry.validatorManager` be updated post-deploy? | **No — it's `immutable`** |

**CLI ceremony flags — confirmed from binary:**

| Prior docs | Correct | Impact |
|---|---|---|
| `--num-validators 4` | `--num-bootstrap-validators 4` | Wrong flag would cause CLI error |
| Interactive prompts assumed | `--bootstrap-filepath` for non-interactive input | Automation impossible without this |
| `--balance` not mentioned | `--balance 0.375` (AVAX per validator) | P-Chain fee requirement |
| `--change-owner-address` not documented | Required — P-Chain addr for exiting validators | Validator management broken without |

**Critical bug found and fixed:**
`DeployTestnet.s.sol` was passing `deployer` as the `validatorManager` argument to `PrimeWaveValidatorRegistry`. Since `validatorManager` is `immutable`, this would have permanently and irreversibly misconfigured the registry — validators would never have worked. Fixed to `0x0FEEDC0DE0000000000000000000000000000000`.

---

### 1.2 Documents Created

| Document | Purpose |
|---|---|
| `docs/PW-C15-VALIDATOR-MANAGER-FLOW.md` | Full architecture: PoAManager predeploy, deployment order, PWVR wiring, 12 architecture Q&A |
| `docs/PW-C15-FUJI-CEREMONY-RUNBOOK.md` | Operator runbook: exact CLI commands, timing, rollback options, error recovery |
| `docs/PW-C15-EOD-LAUNCH-READINESS.md` | This document |

---

### 1.3 Key Ceremony Completed

7 testnet keys generated at `~/.primewave-keys/` (never committed to git):

| Key | Address |
|---|---|
| testnet-deployer | `0x44A37aF5F03807B1AaA1b20D1BFb3d77959B4B5f` |
| testnet-keeper-signer | `0x56A717F87A8Cdb6e855f44a947B5941f6ba3FfA1` |
| testnet-ems-signer-1 | `0xb24F3FAF5B9ab7aFb625F105C791d5231b094853` |
| testnet-ems-signer-2 | `0x508367082eF7A3A8567fa10D92c98524EE2F3d30` |
| testnet-ems-signer-3 | `0xFa21258c9e5faa7aECbFD13f635863C5da0b8EC3` |
| testnet-ems-signer-4 | `0xB1346A22773B853552aF028b767bD6cC0171006a` |
| testnet-ems-signer-5 | `0x2D2d07AB95636Da735BAcBDC018420ca621C3448` |

**FeeDistributor predicted address:** `0xFd069eE048bB748EE60ce53f99D8c2E6ec1D7f99`  
(deployer nonce=4, computed via `cast compute-address 0x44A37aF5... --nonce 4`)

Public addresses saved to: `local-data/testnet-key-addresses.env`

**Key security notes:**
- Keys stored as `cast wallet new --json` output — array format `[{"address": ..., "private_key": ...}]`
- `~/.primewave-keys/` has mode 700; each key file has mode 600
- Keys are **testnet-only**. Never use on mainnet. Encrypt before backup.
- Private key files are at `~/.primewave-keys/*.json` — this directory is NOT in the repo

---

### 1.4 All Priority 3 Blockers Fixed

| Blocker | Fix Applied | Verified |
|---|---|---|
| **B1-CRITICAL**: `node-config.json` has `bootstrap-ids/ips` placeholders → breaks node startup | Removed both fields; added `"partial-sync-primary-network": true` | ✅ |
| **B2-CRITICAL**: `--partial-sync-primary-network` absent from all setup scripts and configs | Added to `node-config.json`; `setup-testnet-node.sh` now copies canonical service (which reads this via `--config-file`) | ✅ |
| **B3-CRITICAL**: Checklist Phase 7 has 6 placeholders; genesis has 7 | Added `__REPLACE_FEE_DISTRIBUTOR_ADDRESS__` to checklist, pre-computed value | ✅ |
| **B4-CRITICAL**: `testnet-deployer` private key absent | Keys generated; `DeployTestnet.s.sol` + checklist updated with new address | ✅ |
| **B5-HIGH**: `preflight-testnet.sh` checks for AvalancheGo v1.14.2; testnet needs v1.15.0-fuji | Version check updated to `1.15.0-fuji` | ✅ |
| **B6-HIGH**: PoAManager deployment not scripted; `DeployTestnet.s.sol` has wrong ValidatorManager | `POA_MANAGER_ADDR = 0x0FEEDC0DE...` constant added; registry constructor fixed | ✅ |
| **B7-HIGH**: All docs/scripts use wrong CLI flag `--num-validators` | Checklist Step 6.1 updated to `--num-bootstrap-validators 4` | ✅ |
| **B8-MED**: `setup-testnet-node.sh` had two conflicting service definitions | Script now copies canonical service file from `deploy/testnet/systemd/` | ✅ |
| **B9-MED**: `setup-testnet-node.sh` header has wrong server specs | Fixed to `4 vCPU / 8GB / 200GB` | ✅ |
| **B10-LOW**: `generate-validator-keys.sh` references v1.14.2 + wrong JSON parse | Version comment and JSON parse both fixed | ✅ |
| **B11-LOW**: `check-external-prerequisites.sh` had old deployer address | Updated to `0x44A37aF5F03807B1AaA1b20D1BFb3d77959B4B5f` | ✅ |
| **B12**: `EMS_SIGNER_1..5` were `address(0)` in `DeployTestnet.s.sol` | Filled with actual generated addresses | ✅ |

---

### 1.5 New Files Created

| File | Status |
|---|---|
| `docs/PW-C15-VALIDATOR-MANAGER-FLOW.md` | ✅ Created |
| `docs/PW-C15-FUJI-CEREMONY-RUNBOOK.md` | ✅ Created |
| `docs/PW-C15-EOD-LAUNCH-READINESS.md` | ✅ This file |
| `local-data/testnet-key-addresses.env` | ✅ Created (public addresses only) |
| `config/testnet/bootstrap-validators.json` | ✅ Created (template with placeholders, fill after node provisioning) |

---

## PART 2 — GO/NO-GO GATE ASSESSMENT

### 🔴 External Gates (BLOCKING — require operator action)

#### GATE-EXT-1: VPS Servers Not Provisioned

**Status:** ❌ BLOCKING  
**Requirement:** 4 VPS servers (4 vCPU / 8GB / 200GB SSD, Ubuntu 22.04)  
**Why needed:** Node identities (NodeID + BLS keys) cannot be collected until AvalancheGo starts on each server.  
**Action:** Provision 4 servers; run `setup-testnet-node.sh`; start AvalancheGo once to generate identity; collect NodeID + BLS info from each.  
**Time estimate:** 30–60 min

#### GATE-EXT-2: Fuji AVAX — Testnet Deployer Unfunded

**Status:** ❌ BLOCKING  
**Requirement:** testnet-deployer needs ≥ 2 AVAX on Fuji C-Chain, then export 1.5 AVAX to P-Chain  
**Deployer address:** `0x44A37aF5F03807B1AaA1b20D1BFb3d77959B4B5f` (fund this on Fuji)  
**Why needed:** P-Chain ceremony requires AVAX for `CreateSubnetTx` + `ConvertSubnetToL1Tx` fees + validator balance (4 × 0.375 = 1.5 AVAX)  
**Action:**  
  1. Visit https://faucet.avax.network → fund C-Chain address above (≥2 AVAX)  
  2. Run: `avalanche key transfer --key testnet-deployer --fuji --amount 1.5 --source-chain C --destination-chain P`  
**Note:** Faucet typically gives 0.5–2 AVAX/day. If faucet limit is too low, request Ava Labs testnet AVAX via Discord.  
**Time estimate:** 10–30 min (faucet + confirmation)

#### GATE-EXT-3: `bootstrap-validators.json` Has Placeholders

**Status:** ❌ BLOCKING  
**Requirement:** All 4 validators' NodeID, BLS public key, and BLS proof of possession  
**File:** `config/testnet/bootstrap-validators.json` (template created — all fields are `__REPLACE__`)  
**Why needed:** Required by `--bootstrap-filepath` for `blockchain deploy`  
**Action:** After Gate-EXT-1 is satisfied, collect from each node:
  ```bash
  curl -sf http://localhost:9650/ext/info -X POST \
    -H 'Content-Type: application/json' \
    --data '{"jsonrpc":"2.0","id":1,"method":"info.getNodeID","params":{}}'
  ```
  Fill `config/testnet/bootstrap-validators.json` with all 4 validators' data.  
**Time estimate:** 15 min (after servers are up)

#### GATE-EXT-4: Genesis — 5 Wallet Addresses Unknown

**Status:** ❌ BLOCKING  
**Requirement:** 5 addresses not yet provided by operator:
  - `__REPLACE_TESTNET_TREASURY_ADDRESS__` — treasury multisig address
  - `__REPLACE_TESTNET_TEAM_ADDRESS__` — team vesting address  
  - `__REPLACE_TESTNET_COMMUNITY_ADDRESS__` — community pool address
  - `__REPLACE_TESTNET_ECOSYSTEM_ADDRESS__` — ecosystem fund address
  - `__REPLACE_TESTNET_RESERVE_ADDRESS__` — reserve address
  
2 addresses are already known (pre-computed):
  - `__REPLACE_TESTNET_DEPLOYER_ADDRESS__` → `0x44A37aF5F03807B1AaA1b20D1BFb3d77959B4B5f`
  - `__REPLACE_FEE_DISTRIBUTOR_ADDRESS__` → `0xFd069eE048bB748EE60ce53f99D8c2E6ec1D7f99`

**Action:** Operator must provide the 5 remaining addresses. These can be any Ethereum addresses (can be the same as deployer for testnet simplicity, or designated multisigs).  
**Time estimate:** 5 min to decide + fill

#### GATE-EXT-5: `avalanche blockchain create primewave-testnet` Not Yet Run

**Status:** ❌ BLOCKING (can be done now with known deployer address)  
**Requirement:** Local CLI config for `primewave-testnet` subnet must exist before `blockchain deploy`  
**Action:**  
  ```bash
  export PATH="$REPO/local-bin:$PATH"
  avalanche blockchain create primewave-testnet \
    --fuji \
    --genesis config/testnet/genesis.json \
    --vm subnet-evm \
    --evm-chain-id 77 \
    --proof-of-authority \
    --acp99 \
    --validator-manager-owner 0x44A37aF5F03807B1AaA1b20D1BFb3d77959B4B5f \
    --proxy-contract-owner 0x44A37aF5F03807B1AaA1b20D1BFb3d77959B4B5f
  ```
  **Note:** Genesis must be generated first (Gate-EXT-4 must be satisfied before this).  
**Time estimate:** <1 min (local CLI operation, no network)

---

### ✅ Replit-Side Gates (ALL SATISFIED)

| Gate | Status |
|---|---|
| ValidatorManager architecture documented | ✅ PASS |
| CLI ceremony runbook written | ✅ PASS |
| `node-config.json`: partial-sync added, bootstrap placeholders removed | ✅ PASS |
| `DeployTestnet.s.sol`: EMS signers filled | ✅ PASS |
| `DeployTestnet.s.sol`: ValidatorManager immutable bug fixed (was `deployer`, now `POA_MANAGER_ADDR`) | ✅ PASS |
| `preflight-testnet.sh`: AvalancheGo version check fixed to v1.15.0-fuji | ✅ PASS |
| `setup-testnet-node.sh`: unified with canonical systemd service; specs corrected | ✅ PASS |
| `generate-validator-keys.sh`: version + JSON parse fixed | ✅ PASS |
| `check-external-prerequisites.sh`: deployer address updated | ✅ PASS |
| Checklist: `--num-bootstrap-validators 4` (was `--num-validators 3`) | ✅ PASS |
| Checklist: 7 genesis placeholders listed (was 6, missing FD) | ✅ PASS |
| 7 testnet keys generated and stored | ✅ PASS |
| FeeDistributor address pre-computed | ✅ PASS |
| `bootstrap-validators.json` template created | ✅ PASS |
| `local-data/testnet-key-addresses.env` created | ✅ PASS |
| Forge tests: 792/792 PASS (unaffected by script/sol changes) | ✅ PASS |

---

## PART 3 — CRITICAL RISKS AND MITIGATIONS

### RISK-1: `validatorManager` Immutability (FIXED ✅)

**Risk:** `PrimeWaveValidatorRegistry.validatorManager` is `immutable`. If deployed with wrong address, the entire registry is permanently broken — no validator can ever be registered.  
**Old state:** Deployer address was passed as placeholder. Would have been permanently set.  
**Fixed:** `POA_MANAGER_ADDR = 0x0FEEDC0DE0000000000000000000000000000000` now passed.  
**Verification after deploy:**
```bash
cast call $ADDR_VALIDATOR_REGISTRY "validatorManager()(address)" --rpc-url $TESTNET_RPC_URL
# Must return: 0x0FEEDC0DE0000000000000000000000000000000
```

### RISK-2: Wrong CLI Flag Would Fail Ceremony

**Risk:** `--num-validators` does not exist in CLI v1.9.5. Using it would cause a CLI error and the ceremony would abort.  
**Fixed:** All docs updated to `--num-bootstrap-validators 4`.  
**Verification before ceremony:** Dry-run: `avalanche blockchain deploy --help | grep bootstrap`

### RISK-3: FeeDistributor Address Prediction Depends on Nonce=4

**Risk:** If testnet-deployer sends ANY transaction before running `DeployTestnet.s.sol`, the nonce will be ≠ 0 and FeeDistributor will deploy at a different address than predicted. Genesis already has the predicted address hardcoded, so fees would go to an uninitialized address.  
**Mitigation:** 
- Never send any transaction from `0x44A37aF5F03807B1AaA1b20D1BFb3d77959B4B5f` before the deployment script runs.
- Do not use the deployer key for faucet requests (use a separate wallet).
- Verify deployer nonce is 0 before running: `cast nonce 0x44A37aF5F03807B1AaA1b20D1BFb3d77959B4B5f --rpc-url $TESTNET_RPC_URL`

### RISK-4: P-Chain Balance (Continuous Fee)

**Risk:** Each validator needs 0.375 AVAX on P-Chain as a continuous fee balance. 4 validators × 0.375 = 1.5 AVAX total.  
**Requirement:** testnet-deployer needs ≥ 1.5 AVAX on P-Chain PLUS ~0.02 AVAX for P-Chain transaction fees.  
**Mitigation:** Fund 2 AVAX from faucet (C-Chain), export 1.6 AVAX to P-Chain (keep 0.4 on C-Chain for later contract deployment gas).

### RISK-5: `--convert-only` Must NOT Be Used

**Risk:** `--convert-only` skips PoAManager initialization. If used, the PoAManager proxy exists at `0x0FEEDC0DE...` but is uninitialized. Validators cannot be registered.  
**Mitigation:** Do not use `--convert-only`. The CLI will initialize PoAManager without it. It will NOT try to restart remote nodes — only local CLI-managed nodes are restarted.

---

## PART 4 — EXECUTION PLAN (OPERATOR SEQUENCE)

When all external gates are ready:

```
Hour 0:
  ✅ Provision 4 VPS (parallel)
  ✅ Provide 5 genesis wallet addresses to PW engineering team

Hour 0.5:
  ✅ Run setup-testnet-node.sh on all 4 VPS
  ✅ Start each node once to generate identity
  ✅ Collect NodeID + BLS info from each node
  ✅ Fill config/testnet/bootstrap-validators.json
  ✅ Fund testnet-deployer from Fuji faucet (0x44A37aF5F03807B1AaA1b20D1BFb3d77959B4B5f)
  ✅ Fill 5 remaining genesis placeholders in genesis-template.json
  ✅ Run: python3 scripts to generate config/testnet/genesis.json
  ✅ Record genesis SHA256 — share with all 4 operators for verification

Hour 1:
  ✅ Run validate-testnet-genesis.sh (all 9 invariants must PASS)
  ✅ Export AVAX from C-Chain to P-Chain (1.5 AVAX)
  ✅ Run: avalanche blockchain create primewave-testnet [...]
  ✅ Run: avalanche blockchain deploy primewave-testnet [...] ← IRREVERSIBLE

Hour 1.5–2:
  ✅ Record SubnetID + BlockchainID from ceremony log
  ✅ Update node-config.json on all 4 validators with SubnetID
  ✅ Restart all validators
  ✅ Monitor bootstrap (~30-60 min with partial-sync)

Hour 2–2.5:
  ✅ Verify PoAManager at 0x0FEEDC0DE... has bytecode
  ✅ Run: deploy-contracts.sh (7 contracts)
  ✅ Verify registry.validatorManager() returns 0x0FEEDC0DE...
  ✅ For each initial validator: call registry.registerValidator(validationID, rewardAddr)

Hour 2.5–3:
  ✅ Deploy ICM relayer
  ✅ Deploy keeper
  ✅ Run post-deploy verification scripts
  ✅ Announce testnet RPC URL
```

---

## PART 5 — READINESS SCORECARD

| Category | Score | Notes |
|---|---|---|
| Architecture clarity | 10/10 | PoAManager flow fully documented with evidence |
| Contract correctness | 10/10 | ValidatorManager bug fixed; EMS signers filled; compiles clean |
| Script correctness | 10/10 | All 12 known bugs fixed; unified service file; correct versions |
| Key ceremony | 10/10 | 7 keys generated; FD address pre-computed |
| Documentation | 10/10 | 3 new docs covering arch, runbook, readiness |
| Genesis readiness | 7/10 | 2/7 placeholders filled; 5 need operator input |
| Server provisioning | 0/10 | 0/4 servers provisioned |
| Fuji funding | 0/10 | Deployer balance = 0 AVAX |
| Node identities | 0/10 | 0/4 collected (need servers first) |
| **OVERALL** | **6.3/10** | **NO-GO** — external gates blocking |

---

## FINAL VERDICT

> **NO-GO** as of 2026-08-16 EOD.  
> All preparation that can be done in Replit is complete and verified.  
> The 5 remaining external gates are outside Replit scope and require operator action.  
> Once those 5 gates are satisfied, the launch sequence can execute within 2.5–3.5 hours.

**Critical path:**  
Provision servers → Collect node identities + operator wallet addresses → Fund deployer → Generate genesis → Ceremony → Bootstrap → Deploy contracts → LIVE
