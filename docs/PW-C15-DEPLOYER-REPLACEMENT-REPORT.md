# PrimeWave Testnet — Deployer Key Replacement Report
## PW-C15 | 2026-08-16

**Reason:** Original testnet-deployer private key (`0x44A37aF5F03807B1AaA1b20D1BFb3d77959B4B5f`) was stored at `~/.primewave-keys/testnet-deployer.json` (ephemeral Replit home directory) and was permanently lost on container restart. Full key recovery investigation confirmed it is unrecoverable from any project-accessible location. The 2.0 AVAX on that address is stranded. No ceremony transactions were ever submitted.

---

## 1. ADDRESSES

### Old Deployer (ABANDONED — key permanently lost)

| Field | Value |
|---|---|
| C-Chain | `0x44A37aF5F03807B1AaA1b20D1BFb3d77959B4B5f` |
| Balance | 2.0 AVAX (stranded — do not attempt recovery) |
| Nonce | 0 (no transactions ever sent) |
| Status | **ABANDONED** |

### New Deployer

| Field | Value |
|---|---|
| **C-Chain** | `0xB518397E3D65a0E7475635F01C225E9426a76F11` |
| **P-Chain (Fuji)** | `P-fuji17c7fuusyh76r74zwge4sl0nc3458xdkv477adz` |
| X-Chain (Fuji) | `X-fuji17c7fuusyh76r74zwge4sl0nc3458xdkv477adz` |
| Balance | 0 AVAX (unfunded — fund via Fuji faucet before ceremony) |
| Nonce | 0 |
| Key kind | Avalanche CLI stored key |
| CLI key name | `testnet-deployer` |

---

## 2. KEY CREATION

```
./local-bin/avalanche key create testnet-deployer
```

Output:
```
Generating new key...
Key created
```

Key confirmed distinct from old deployer (different address). No pre-existing key with name `testnet-deployer` was found before creation (CLI key store was empty).

---

## 3. FEE DISTRIBUTOR ADDRESS — RECOMPUTED

The FeeDistributor is deployed by the deployer at nonce=4. Since the deployer address changed, the predicted FeeDistributor address also changes.

| | Old | New |
|---|---|---|
| Deployer | `0x44A37aF5...` | `0xB518397E...` |
| FeeDistributor (nonce=4) | `0xFd069eE048bB748EE60ce53f99D8c2E6ec1D7f99` | `0x27B15970700daC632f0814522118A1c3B200d971` |

Computation:
```bash
./local-bin/foundry/cast compute-address 0xB518397E3D65a0E7475635F01C225E9426a76F11 --nonce 4
# Computed Address: 0x27B15970700daC632f0814522118A1c3B200d971
```

This new address must be used in `rewardManagerConfig.initialRewardConfig.rewardAddress` when filling `config/testnet/genesis-template.json` at ceremony time.

---

## 4. FILES UPDATED

| File | Change |
|---|---|
| `config/testnet/bootstrap-validators.json` | All 4 `ChangeOwnerAddr` fields: `P-fuji1__REPLACE_DEPLOYER_P_CHAIN_ADDR__` → `P-fuji17c7fuusyh76r74zwge4sl0nc3458xdkv477adz` |
| `local-data/testnet-key-addresses.env` | `TESTNET_DEPLOYER_ADDRESS`, `TESTNET_FEE_DISTRIBUTOR_PREDICTED` updated; old address preserved as comment |
| `scripts/testnet/check-external-prerequisites.sh` | `DEPLOYER_CCHAIN` variable updated |
| `docs/PW-C15-TESTNET-DAY-0-CHECKLIST.md` | Lines 180 and 409: deployer address references updated |

### Files intentionally left unchanged (historical record)

| File | Reason |
|---|---|
| `docs/PW-C15-EOD-LAUNCH-READINESS.md` | Historical sprint-end report — old address correctly remains as record |
| `docs/PW-C15-V6-V9-PROVISIONING-REPORT.md` | Historical provisioning report |
| `docs/PW-C15-FINAL-PRE-CEREMONY-CHECK.md` | Historical check report — references old deployer deliberately |
| `docs/PW-PREFLIGHT-L1-LAUNCH-AUDIT.md` | Historical audit |
| `.agents/memory/primewave-pw-c15.md` | Updated separately (see below) |

### Files NOT requiring change

| File | Reason |
|---|---|
| `contracts/script/DeployTestnet.s.sol` | Deployer is `msg.sender` — passed via `--private-key` env var at runtime; not hardcoded |
| `config/testnet/genesis-template.json` | Contains `__REPLACE_TESTNET_DEPLOYER_ADDRESS__` placeholder — fill at ceremony with new address |

---

## 5. BOOTSTRAP-VALIDATORS.JSON — FINAL STATE

```json
[
  { "NodeID": "NodeID-144dTzcL2vgpbKzX943xy5pEF3M8oGyiQ", "ChangeOwnerAddr": "P-fuji17c7fuusyh76r74zwge4sl0nc3458xdkv477adz", ... },
  { "NodeID": "NodeID-cwX3HFmaR5QmbxuZaDJCXAueJeyewjni",  "ChangeOwnerAddr": "P-fuji17c7fuusyh76r74zwge4sl0nc3458xdkv477adz", ... },
  { "NodeID": "NodeID-7DLuPUaMiDbyVoZ6P92RQdNRFS81cpYb5", "ChangeOwnerAddr": "P-fuji17c7fuusyh76r74zwge4sl0nc3458xdkv477adz", ... },
  { "NodeID": "NodeID-9TiHzx7DZgtCjB9pqyY6db55pZgVZELvJ", "ChangeOwnerAddr": "P-fuji17c7fuusyh76r74zwge4sl0nc3458xdkv477adz", ... }
]
```

Validation:
- 4 validators ✅
- All NodeIDs unique ✅
- All BLS keys and PoPs unchanged ✅
- `ChangeOwnerAddr` identical across all 4 ✅
- No `__REPLACE_` placeholder remaining ✅
- JSON valid ✅

---

## 6. GENESIS-TEMPLATE.JSON — PLACEHOLDER RESOLUTION TABLE (UPDATED)

At ceremony time, substitute as follows:

| Placeholder | Resolved Value |
|---|---|
| `__REPLACE_FEE_DISTRIBUTOR_ADDRESS__` | `0x27B15970700daC632f0814522118A1c3B200d971` ← **NEW** |
| `__REPLACE_TESTNET_DEPLOYER_ADDRESS__` | `0xB518397E3D65a0E7475635F01C225E9426a76F11` ← **NEW** |
| `__REPLACE_TESTNET_TREASURY_ADDRESS__` | `0x1F471d2Dc7CB8b2C773aFeD40d4bD467ed1FdaD8` |
| `__REPLACE_TESTNET_TEAM_ADDRESS__` | `0x46a419514f52A4763596F75A9169B0Bd0153C673` |
| `__REPLACE_TESTNET_COMMUNITY_ADDRESS__` | `0xA6744C599A0d40082aAF03Bd643cfc30B2B16a0c` |
| `__REPLACE_TESTNET_ECOSYSTEM_ADDRESS__` | `0x2c5E541f667768dd1986C73530Dc29250fA86B7B` |
| `__REPLACE_TESTNET_RESERVE_ADDRESS__` | `0x3C98105b99bb9dc97B341D11ec264F5127A7221C` |

---

## 7. UNRESOLVED PLACEHOLDERS REMAINING

After all updates, a full grep confirms zero `__REPLACE_` patterns in active config/script files:

| File | Remaining Placeholders |
|---|---|
| `config/testnet/bootstrap-validators.json` | **None** ✅ |
| `config/testnet/genesis-template.json` | 7 (by design — filled at ceremony) |
| `local-data/testnet-key-addresses.env` | **None** ✅ |
| `scripts/testnet/check-external-prerequisites.sh` | Audit-only pattern — not a data placeholder |

---

## 8. SECURE KEY BACKUP STATUS

| Item | Status |
|---|---|
| Key file location | `~/.avalanche-cli/key/testnet-deployer.pk` (mode 600) |
| Persistence | ⚠️ **EPHEMERAL** — home directory is not persisted across Replit container restarts |
| In git | ❌ No (correct — must never be committed) |
| In Replit Secrets | ❌ No |
| Physical backup | ❌ Not yet performed |

### ⚠️ OPERATOR ACTION REQUIRED BEFORE CEREMONY

The private key at `~/.avalanche-cli/key/testnet-deployer.pk` will be lost if the Replit container restarts. Immediately after review:

1. **Export the private key** from the CLI key file (using the Avalanche CLI or a secure offline tool).
2. **Back it up physically** per `docs/PRIMEWAVE_KEY_SECURITY_PROCEDURE.md` — hardware wallet or Cryptosteel.
3. **Do NOT email, paste, or commit** the private key.

The Replit environment has no approved secure digital persistence for private keys. The documented procedure requires physical backup. This is the operator's responsibility before the Fuji AVAX faucet is used to fund this address.

---

## 9. FUNDING STATUS

| Address | Balance | Action Required |
|---|---|---|
| Old deployer `0x44A37aF5...` | 2.0 AVAX (stranded) | Do nothing — key is gone |
| **New deployer `0xB518397E...`** | **0 AVAX** | **Fund via faucet before ceremony** |

Fund at: https://faucet.avax.network  
Network: Fuji  
Address: `0xB518397E3D65a0E7475635F01C225E9426a76F11`

Minimum required: ~1.5 AVAX (4 validators × 0.375 AVAX `Balance` for `ConvertSubnetToL1Tx`)  
Recommended: 2+ AVAX (same buffer as before)

---

## 10. VALIDATION SUMMARY

| Check | Result |
|---|---|
| New C-Chain address ≠ old deployer | ✅ Different |
| bootstrap-validators.json valid JSON | ✅ |
| All 4 ChangeOwnerAddr = new P-Chain addr | ✅ |
| No `__REPLACE_DEPLOYER_P_CHAIN_ADDR__` remains | ✅ |
| genesis-template.json deployer placeholder resolvable | ✅ (new address known) |
| DeployTestnet.s.sol deployer reference | ✅ No hardcoded address (uses `msg.sender`) |
| No accidental replacement of non-deployer addresses | ✅ Only deployer references updated |
| No transaction submitted | ✅ Nonce=0 on new address |
| EMS signers unchanged | ✅ All 5 still correct |
| NodeIDs / BLS keys unchanged | ✅ |

---

## 11. GO / NO-GO

```
┌──────────────────────────────────────────────────────────────────┐
│                   DEPLOYER REPLACEMENT STATUS                     │
├──────────────────────────────────────────────┬───────────────────┤
│ New key created (distinct from old)          │ ✅                │
│ C-Chain address verified                     │ ✅                │
│ P-Chain address derived                      │ ✅                │
│ bootstrap-validators.json updated, no gaps   │ ✅                │
│ testnet-key-addresses.env updated            │ ✅                │
│ check-external-prerequisites.sh updated      │ ✅                │
│ Day-0 checklist updated                      │ ✅                │
│ FeeDistributor prediction recomputed         │ ✅                │
│ No accidental address replacements           │ ✅                │
│ No ceremony transactions executed            │ ✅                │
├──────────────────────────────────────────────┼───────────────────┤
│ Key backup (physical)                        │ ⚠️ PENDING        │
│ Fuji AVAX funding of new deployer            │ ❌ UNFUNDED       │
├──────────────────────────────────────────────┴───────────────────┤
│                                                                   │
│   VERDICT: READY TO FUND                                          │
│                                                                   │
│   Operator must:                                                  │
│   1. Back up ~/.avalanche-cli/key/testnet-deployer.pk physically  │
│   2. Fund 0xB518397E3D65a0E7475635F01C225E9426a76F11 on Fuji     │
│      (minimum ~1.5 AVAX, recommend 2 AVAX)                       │
│                                                                   │
│   Once funded and key is backed up → ceremony is GO              │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
```

---

*Report generated: 2026-08-16 | PW-C15 | No ceremony transactions executed*
