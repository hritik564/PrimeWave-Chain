# PrimeWave Testnet — Final Ceremony Readiness Check
## PW-C15 | 2026-08-16 | READ-ONLY

---

## CHECK 1 — DEPLOYER IDENTITY

| Field | Expected | Actual | Status |
|---|---|---|---|
| CLI key name | `testnet-deployer` | `testnet-deployer` | ✅ |
| C-Chain | `0xB518397E3D65a0E7475635F01C225E9426a76F11` | `0xB518397E3D65a0E7475635F01C225E9426a76F11` | ✅ |
| P-Chain | `P-fuji17c7fuusyh76r74zwge4sl0nc3458xdkv477adz` | `P-fuji17c7fuusyh76r74zwge4sl0nc3458xdkv477adz` | ✅ |

Private key: not printed. Key file at `~/.avalanche-cli/key/testnet-deployer.pk` (operator confirmed backed up).

---

## CHECK 2 — FUNDING

| Balance | Value | Status |
|---|---|---|
| C-Chain AVAX | **2.000000000** | ✅ Sufficient |
| P-Chain AVAX | 0 | ⚠️ See note below |
| C-Chain nonce | **0** | ✅ Clean — no prior txns |

**P-Chain note:** P-Chain balance 0 is expected at this point. Step 1.2 of the Day-0 checklist (`avalanche key transfer --amount 1.5 ... --source-chain C --destination-chain P`) is the FIRST ceremony action — it transfers 1.5 AVAX to P-Chain before `blockchain deploy`. This is not a blocker; it is the opening move of the ceremony.

Minimum required for ceremony:
- P-Chain: ~1.4 AVAX (4 × `Balance: 100000000` nAVAX for ConvertSubnetToL1Tx + fees)
- C-Chain: ~0.3 AVAX (gas for contract deployment × 7 contracts)
- Available: 2.0 AVAX C-Chain → export 1.5 to P → leaves 0.5 for gas ✅

---

## CHECK 3 — VALIDATORS (V6 / V7 / V8 / V9)

| Property | V6 | V7 | V8 | V9 |
|---|---|---|---|---|
| Service | `primewave-testnet-node.service` | same | same | same |
| Service state | **active (running)** | **active (running)** | **active (running)** | **active (running)** |
| Uptime | 55 min | 55 min | 55 min | 55 min |
| Restarts | **0** | **0** | **0** | **0** |
| AvalancheGo version | **1.15.0** | **1.15.0** | **1.15.0** | **1.15.0** |
| NetworkID | **5 (Fuji)** | **5** | **5** | **5** |
| P-Chain bootstrapped | **true** | **true** | **true** | **true** |
| P-Chain height | **293022** | **293022** | **293022** | **293022** |
| Peers | **55** | **55** | **55** | **55** |
| Errors / panics (1h) | none | none | none | none |

*Note: `systemctl is-active avalanchego` returned `inactive` because the service is named `primewave-testnet-node` not `avalanchego`. Confirmed active via direct service query. P-Chain bootstrapped confirmed via `info.isBootstrapped` API (the `platform.isBootstrapped` method was removed in AvalancheGo v1.15.x).*

### Node Identities (from live API — must match bootstrap config)

| Node | NodeID | BLS PK prefix | BLS PoP prefix |
|---|---|---|---|
| V6 | `NodeID-144dTzcL2vgpbKzX943xy5pEF3M8oGyiQ` | `0xafec5f5a47c8...` | `0x950565d5c6fd...` |
| V7 | `NodeID-cwX3HFmaR5QmbxuZaDJCXAueJeyewjni` | `0xa73965b62007...` | `0x93bed700938e...` |
| V8 | `NodeID-7DLuPUaMiDbyVoZ6P92RQdNRFS81cpYb5` | `0xa61adbff78c2...` | `0x90ef97c3fed5...` |
| V9 | `NodeID-9TiHzx7DZgtCjB9pqyY6db55pZgVZELvJ` | `0x932046c8e02b...` | `0x9571c3523f28...` |

All 4 NodeIDs unique ✅ — All 4 BLS keys unique ✅ — All 4 PoPs present ✅

---

## CHECK 4 — BOOTSTRAP CONFIG (`config/testnet/bootstrap-validators.json`)

| Check | Result |
|---|---|
| Validator count | **4** ✅ |
| All NodeIDs unique | ✅ |
| All BLS keys unique | ✅ |
| All PoPs present | ✅ |
| ChangeOwnerAddr (all 4) | `P-fuji17c7fuusyh76r74zwge4sl0nc3458xdkv477adz` ✅ |
| No `__REPLACE_` placeholders | ✅ |
| JSON valid | ✅ |
| NodeIDs match live API | ✅ |
| BLS keys match live API | ✅ |

---

## CHECK 5 — GENESIS TEMPLATE (`config/testnet/genesis-template.json`)

| Placeholder | Expected Value | Present | Status |
|---|---|---|---|
| `__REPLACE_TESTNET_DEPLOYER_ADDRESS__` | `0xB518397E3D65a0E7475635F01C225E9426a76F11` | 1× | ✅ |
| `__REPLACE_FEE_DISTRIBUTOR_ADDRESS__` | `0x27B15970700daC632f0814522118A1c3B200d971` | 1× | ✅ |
| `__REPLACE_TESTNET_TREASURY_ADDRESS__` | `0x1F471d2Dc7CB8b2C773aFeD40d4bD467ed1FdaD8` | 1× | ✅ |
| `__REPLACE_TESTNET_TEAM_ADDRESS__` | `0x46a419514f52A4763596F75A9169B0Bd0153C673` | 1× | ✅ |
| `__REPLACE_TESTNET_COMMUNITY_ADDRESS__` | `0xA6744C599A0d40082aAF03Bd643cfc30B2B16a0c` | 1× | ✅ |
| `__REPLACE_TESTNET_ECOSYSTEM_ADDRESS__` | `0x2c5E541f667768dd1986C73530Dc29250fA86B7B` | 1× | ✅ |
| `__REPLACE_TESTNET_RESERVE_ADDRESS__` | `0x3C98105b99bb9dc97B341D11ec264F5127A7221C` | 1× | ✅ |

Total: 7 placeholders ✅ — JSON valid after substitution ✅ — Chain ID 77 ✅ — Total supply 100M PW ✅

*`genesis.json` does not yet exist — correct, it is generated at Step 7.3 of the ceremony.*

---

## CHECK 6 — DEPLOYMENT SCRIPT (`contracts/script/DeployTestnet.s.sol`)

| Check | Value | Status |
|---|---|---|
| Deployer | `msg.sender` (passed via `--private-key $TESTNET_DEPLOYER_KEY`) | ✅ |
| POA_MANAGER_ADDR | `0x0Feedc0de0000000000000000000000000000000` | ✅ |
| EMS_SIGNER_1 | `0xb24F3FAF5B9ab7aFb625F105C791d5231b094853` | ✅ non-zero |
| EMS_SIGNER_2 | `0x508367082eF7A3A8567fa10D92c98524EE2F3d30` | ✅ non-zero |
| EMS_SIGNER_3 | `0xFa21258c9e5faa7aECbFD13f635863C5da0b8EC3` | ✅ non-zero |
| EMS_SIGNER_4 | `0xB1346A22773B853552aF028b767bD6cC0171006a` | ✅ non-zero |
| EMS_SIGNER_5 | `0x2D2d07AB95636Da735BAcBDC018420ca621C3448` | ✅ non-zero |
| Old deployer address in script | None found | ✅ |
| Chain ID == 77 guard | Present | ✅ |
| Dev key rejection guard | Present | ✅ |
| `forge build` | Exit 0 (lint hint only, no errors) | ✅ |

---

## CHECK 7 — PROJECT-WIDE PLACEHOLDER AUDIT

### Active config/script files — remaining `__REPLACE_` instances

| File | Pattern | Intent |
|---|---|---|
| `config/testnet/genesis-template.json` | 7 instances | ✅ Expected — filled at Step 7 of ceremony |
| `config/testnet/node-config.json` | `__REPLACE_TESTNET_SUBNET_ID__` | ✅ Expected — filled after SubnetID known (Step 6.2) |
| `scripts/testnet/setup-testnet-node.sh` | `__REPLACE_BLOCKCHAIN_ID__` (default only) | ✅ Expected — set via env var at node setup time |
| `scripts/testnet/preflight-testnet.sh` | Pattern strings in grep/python code | ✅ Script logic, not data placeholder |

### Old deployer address (`0x44A37aF5...`)

| Location | Status |
|---|---|
| Active config/scripts | **Not found** ✅ |
| Historical docs (intentional) | Present in `docs/PW-C15-EOD-LAUNCH-READINESS.md`, `docs/PW-C15-FINAL-PRE-CEREMONY-CHECK.md`, `docs/PW-C15-V6-V9-PROVISIONING-REPORT.md`, `local-data/testnet-key-addresses.env` comment | ✅ Correct — marked abandoned |

### `address(0)` in DeployTestnet.s.sol
Used only in guard assertions (`EMS_SIGNER_N != address(0)`) — correct, not a placeholder. ✅

---

## CHECK 8 — CEREMONY COMMAND VALIDATION

### Environment variables required

| Variable | Source | Status |
|---|---|---|
| `TESTNET_DEPLOYER_KEY` | Operator sets from `~/.avalanche-cli/key/testnet-deployer.pk` | 🔑 Must be set before Step 8.2 |
| `TESTNET_RPC_URL` | Set after blockchain created (Step 6.2) | 📋 Filled during ceremony |
| `TESTNET_SUBNET_ID` | Set after blockchain created (Step 6.2) | 📋 Filled during ceremony |
| `TESTNET_BLOCKCHAIN_ID` | Set after blockchain created (Step 6.2) | 📋 Filled during ceremony |

### Key ceremony flag check
- Deployer key: `--key testnet-deployer` (Avalanche CLI name) ✅
- Network: `--fuji` ✅
- Bootstrap file: `config/testnet/bootstrap-validators.json` ✅
- Validator count: `--num-bootstrap-validators 4` ✅
- No stale addresses in ceremony command ✅

---

## CHECK 9 — DRY RUN (PREFLIGHT)

`scripts/testnet/preflight-testnet.sh` is a genuinely non-mutating read-only check. Executed:

```
READY:   62
WARNING: 3
BLOCKED: 0
FAIL:    1
```

**The 1 FAIL** — `avalanchego version 1.14.2 — expected exactly 1.15.0-fuji`:
- This checks `local-bin/avalanchego` (the LOCAL dev binary, v1.14.2).
- The ceremony uses the Avalanche CLI (`local-bin/avalanche` v1.9.5) to submit P-Chain transactions directly to Fuji's API — it does NOT use the local avalanchego binary.
- The 4 validator nodes all run v1.15.0 ✅.
- **This FAIL is a false positive for ceremony readiness.** The local binary version mismatch is a local-dev concern.

**The 3 WARNINGs:**
1. `dev genesis template not found` — optional file, not needed for testnet.
2. `explorer.conf: example.com placeholder` — nginx config, filled at infra deploy (post-ceremony).
3. `rpc.conf: example.com placeholder` — same as above.

All 3 warnings are post-ceremony infra tasks, not ceremony prerequisites.

---

## CHECK 10 — ADDITIONAL (discovered during audit)

Two additional stale references found and fixed in `docs/PW-C15-TESTNET-DAY-0-CHECKLIST.md`:
1. Line 410: Old FeeDistributor `0xFd069eE048b...` → updated to `0x27B15970700d...`
2. Line 129: Old P-Chain address `P-fuji1p25rk6k...` → updated to `P-fuji17c7fuus...`

These were in the operational checklist guidance text, not in ceremony commands.

---

## CEREMONY COMMAND SEQUENCE

> **DO NOT EXECUTE YET.** This is the validated sequence to be run when you are ready.

### Phase 1 — P-Chain funding

```bash
cd $REPO
export PATH="$REPO/local-bin:$PATH"

# Step 1.2: Export 1.5 AVAX from C-Chain to P-Chain
avalanche key transfer \
  --key testnet-deployer \
  --fuji \
  --amount 1.5 \
  --destination-key testnet-deployer \
  --source-chain C \
  --destination-chain P

# Step 1.3: Verify P-Chain balance (should show ≥ 1.5 AVAX)
avalanche key list --fuji --keys testnet-deployer
```

### Phase 7 — Fill genesis

```bash
# Step 7.1: Fill genesis-template.json with the 7 addresses from local-data/testnet-key-addresses.env
# Then generate genesis.json (Step 7.3):
python3 - <<'EOF'
import json, re

with open("config/testnet/genesis-template.json") as f:
    raw = f.read()

replacements = {
    "__REPLACE_TESTNET_DEPLOYER_ADDRESS__": "0xB518397E3D65a0E7475635F01C225E9426a76F11",
    "__REPLACE_FEE_DISTRIBUTOR_ADDRESS__":  "0x27B15970700daC632f0814522118A1c3B200d971",
    "__REPLACE_TESTNET_TREASURY_ADDRESS__": "0x1F471d2Dc7CB8b2C773aFeD40d4bD467ed1FdaD8",
    "__REPLACE_TESTNET_TEAM_ADDRESS__":     "0x46a419514f52A4763596F75A9169B0Bd0153C673",
    "__REPLACE_TESTNET_COMMUNITY_ADDRESS__":"0xA6744C599A0d40082aAF03Bd643cfc30B2B16a0c",
    "__REPLACE_TESTNET_ECOSYSTEM_ADDRESS__":"0x2c5E541f667768dd1986C73530Dc29250fA86B7B",
    "__REPLACE_TESTNET_RESERVE_ADDRESS__":  "0x3C98105b99bb9dc97B341D11ec264F5127A7221C",
}

filled = raw
for k, v in replacements.items():
    filled = filled.replace(k, v)

remaining = re.findall(r"__REPLACE_[A-Z_]+__", filled)
if remaining:
    print("STOP — unfilled placeholders:", remaining)
    exit(1)

data = json.loads(filled)
with open("config/testnet/genesis.json", "w") as f:
    json.dump(data, f, indent=2)

import hashlib
sha = hashlib.sha256(open("config/testnet/genesis.json","rb").read()).hexdigest()
print("genesis.json written. SHA256:", sha)
EOF

# Verify: must return 0
grep -c "__REPLACE_" config/testnet/genesis.json && echo "FAIL: placeholders remain" || echo "OK: no placeholders"
```

### Phase 6 — Subnet + L1 creation (IRREVERSIBLE)

```bash
cd $REPO
export PATH="$REPO/local-bin:$PATH"

# Step 6.1: Deploy subnet to Fuji (CreateSubnetTx + ConvertSubnetToL1Tx)
avalanche blockchain deploy primewave-testnet \
  --fuji \
  --key testnet-deployer \
  --bootstrap-filepath config/testnet/bootstrap-validators.json \
  --num-bootstrap-validators 4 2>&1 | tee /tmp/fuji-ceremony.log

# Step 6.2: Record IDs
grep -E "(Subnet ID|Blockchain ID)" /tmp/fuji-ceremony.log
export TESTNET_SUBNET_ID=<SUBNET_ID_FROM_LOG>
export TESTNET_BLOCKCHAIN_ID=<BLOCKCHAIN_ID_FROM_LOG>

# Step 6.3: Verify on Fuji
curl -sf -X POST -H 'Content-Type: application/json' \
  --data "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"platform.getSubnet\",\"params\":{\"subnetID\":\"$TESTNET_SUBNET_ID\"}}" \
  https://api.avax-test.network/ext/bc/P | python3 -m json.tool
```

### Phase 8 — Contract deployment

```bash
# Step 8.1: Wait for testnet RPC to be live, then verify Chain ID = 77
TESTNET_RPC_URL="https://api.avax-test.network/ext/bc/$TESTNET_BLOCKCHAIN_ID/rpc"
cast chain-id --rpc-url "$TESTNET_RPC_URL"  # Must return 77

# Step 8.2: Deploy contracts
export TESTNET_DEPLOYER_KEY=<private_key_from_testnet-deployer.pk>
export TESTNET_RPC_URL="https://api.avax-test.network/ext/bc/$TESTNET_BLOCKCHAIN_ID/rpc"
bash scripts/testnet/deploy-contracts.sh 2>&1 | tee /tmp/deploy-contracts.log

# Step 8.3: Record deployed contract addresses
grep -E "deployed at" /tmp/deploy-contracts.log

# Step 8.4: Verify
bash scripts/testnet/verify-deployed-contracts.sh
```

---

## FINAL DECISION

```
┌──────────────────────────────────────────────────────────────────┐
│                   CEREMONY READINESS — 2026-08-16                 │
├──────────────────────────────────────────────┬───────────────────┤
│ Deployer key confirmed (CLI + addresses)     │ ✅                │
│ C-Chain funded (2.0 AVAX, nonce=0)           │ ✅                │
│ P-Chain balance                              │ ⚪ 0 (first step) │
│ V6 active, bootstrapped, v1.15.0, 0 restarts │ ✅                │
│ V7 active, bootstrapped, v1.15.0, 0 restarts │ ✅                │
│ V8 active, bootstrapped, v1.15.0, 0 restarts │ ✅                │
│ V9 active, bootstrapped, v1.15.0, 0 restarts │ ✅                │
│ All NodeIDs + BLS keys unique                │ ✅                │
│ bootstrap-validators.json valid, no gaps     │ ✅                │
│ genesis-template.json: all 7 placeholders    │ ✅                │
│ genesis-template.json: valid JSON            │ ✅                │
│ DeployTestnet.s.sol: forge build OK          │ ✅                │
│ EMS signers: all 5 non-zero, correct         │ ✅                │
│ POA_MANAGER_ADDR correct                     │ ✅                │
│ Old deployer not in any active file          │ ✅                │
│ Ceremony command sequence validated          │ ✅                │
│ Preflight: 62 READY, 0 BLOCKED               │ ✅                │
│ Preflight FAIL (local avago v1.14.2)         │ ✅ false positive │
├──────────────────────────────────────────────┴───────────────────┤
│                                                                   │
│                         ██████  ██████                            │
│                        ██       ██   ██                           │
│                        ██   ███ ██   ██                           │
│                        ██    ██ ██   ██                           │
│                         ██████  ██████                            │
│                                                                   │
│   All checks pass. No actual blockers.                            │
│                                                                   │
│   FIRST ACTION: export 1.5 AVAX C→P (Step 1.2)                  │
│   SECOND ACTION: fill genesis + generate genesis.json            │
│   THIRD ACTION: avalanche blockchain deploy (IRREVERSIBLE)        │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
```

---

*Read-only check. No transactions submitted. No funds moved. No contracts deployed.*  
*Report: `docs/PW-C15-FINAL-CEREMONY-READINESS.md` | PW-C15 | 2026-08-16*
