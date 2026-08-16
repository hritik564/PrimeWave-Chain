# PrimeWave Testnet — Genesis Generation Report
## PW-C15 | Ceremony Step 2 | 2026-08-16

---

## GENERATION COMMAND

```python
# Executed via inline Python (no external scripts required)
# Source: config/testnet/genesis-template.json
# Output: config/testnet/genesis.json

replacements = {
    "__REPLACE_TESTNET_DEPLOYER_ADDRESS__":  "0xB518397E3D65a0E7475635F01C225E9426a76F11",
    "__REPLACE_FEE_DISTRIBUTOR_ADDRESS__":   "0x27B15970700daC632f0814522118A1c3B200d971",
    "__REPLACE_TESTNET_TREASURY_ADDRESS__":  "0x1F471d2Dc7CB8b2C773aFeD40d4bD467ed1FdaD8",
    "__REPLACE_TESTNET_TEAM_ADDRESS__":      "0x46a419514f52A4763596F75A9169B0Bd0153C673",
    "__REPLACE_TESTNET_COMMUNITY_ADDRESS__": "0xA6744C599A0d40082aAF03Bd643cfc30B2B16a0c",
    "__REPLACE_TESTNET_ECOSYSTEM_ADDRESS__": "0x2c5E541f667768dd1986C73530Dc29250fA86B7B",
    "__REPLACE_TESTNET_RESERVE_ADDRESS__":   "0x3C98105b99bb9dc97B341D11ec264F5127A7221C",
}
```

---

## SOURCE AND OUTPUT

| Field | Value |
|---|---|
| Source template | `config/testnet/genesis-template.json` |
| Output file | `config/testnet/genesis.json` |
| File size | 3,155 bytes |
| **SHA256** | **`2e85b9753a51b429725fb768eb09f6208f36cb1cec614bb788886eedaba6a657`** |
| Generated at | 2026-08-16T18:59:xx UTC |

---

## PLACEHOLDER SUBSTITUTION (7/7)

| Placeholder | Substituted Value | Occurrences |
|---|---|---|
| `__REPLACE_TESTNET_DEPLOYER_ADDRESS__` | `0xB518397E3D65a0E7475635F01C225E9426a76F11` | 1 |
| `__REPLACE_FEE_DISTRIBUTOR_ADDRESS__` | `0x27B15970700daC632f0814522118A1c3B200d971` | 1 |
| `__REPLACE_TESTNET_TREASURY_ADDRESS__` | `0x1F471d2Dc7CB8b2C773aFeD40d4bD467ed1FdaD8` | 1 |
| `__REPLACE_TESTNET_TEAM_ADDRESS__` | `0x46a419514f52A4763596F75A9169B0Bd0153C673` | 1 |
| `__REPLACE_TESTNET_COMMUNITY_ADDRESS__` | `0xA6744C599A0d40082aAF03Bd643cfc30B2B16a0c` | 1 |
| `__REPLACE_TESTNET_ECOSYSTEM_ADDRESS__` | `0x2c5E541f667768dd1986C73530Dc29250fA86B7B` | 1 |
| `__REPLACE_TESTNET_RESERVE_ADDRESS__` | `0x3C98105b99bb9dc97B341D11ec264F5127A7221C` | 1 |

Remaining `__REPLACE_` strings in output: **0** ✅

---

## ADDRESS VALIDATION

### Genesis `alloc` (6 entries)

| Label | Address | Balance (hex) | Balance (PW) | Status |
|---|---|---|---|---|
| DEPLOYER | `0xB518397E3D65a0E7475635F01C225E9426a76F11` | `0xd3c21bcecceda10000000` | 1,000,000 | ✅ |
| TREASURY | `0x1F471d2Dc7CB8b2C773aFeD40d4bD467ed1FdaD8` | `0x14adf4b7320334b9000000` | 25,000,000 | ✅ |
| TEAM | `0x46a419514f52A4763596F75A9169B0Bd0153C673` | `0x108b2a2c28029094000000` | 20,000,000 | ✅ |
| COMMUNITY | `0xA6744C599A0d40082aAF03Bd643cfc30B2B16a0c` | `0x108b2a2c28029094000000` | 20,000,000 | ✅ |
| ECOSYSTEM | `0x2c5E541f667768dd1986C73530Dc29250fA86B7B` | `0x84595161401484a000000` | 10,000,000 | ✅ |
| RESERVE | `0x3C98105b99bb9dc97B341D11ec264F5127A7221C` | `0x771d2fa45345aa9000000` | 24,000,000 | ✅ |

**Total supply: 100,000,000 PW** ✅

*Note: FeeDistributor (`0x27B15970700daC632f0814522118A1c3B200d971`) has no genesis alloc — correct by design. It is deployed at deployer nonce=4 during contract deployment and receives its funding from DeployTestnet.s.sol.*

### `rewardManagerConfig.initialRewardConfig.rewardAddress`

| Expected | Actual | Status |
|---|---|---|
| `0x27B15970700daC632f0814522118A1c3B200d971` | `0x27B15970700daC632f0814522118A1c3B200d971` | ✅ |

### Other address checks

| Check | Result |
|---|---|
| `address(0)` in alloc | Not present ✅ |
| Old deployer (`0x44A37aF5...`) anywhere in genesis | Not present ✅ |
| Old FeeDistributor (`0xFd069eE0...`) anywhere in genesis | Not present ✅ |

---

## EMS SIGNERS VALIDATION

All 5 EMS signer addresses confirmed non-zero in `contracts/script/DeployTestnet.s.sol`:

| Signer | Address | Status |
|---|---|---|
| EMS_SIGNER_1 | `0xb24F3FAF5B9ab7aFb625F105C791d5231b094853` | ✅ non-zero |
| EMS_SIGNER_2 | `0x508367082eF7A3A8567fa10D92c98524EE2F3d30` | ✅ non-zero |
| EMS_SIGNER_3 | `0xFa21258c9e5faa7aECbFD13f635863C5da0b8EC3` | ✅ non-zero |
| EMS_SIGNER_4 | `0xB1346A22773B853552aF028b767bD6cC0171006a` | ✅ non-zero |
| EMS_SIGNER_5 | `0x2D2d07AB95636Da735BAcBDC018420ca621C3448` | ✅ non-zero |

---

## BOOTSTRAP-VALIDATORS.JSON VALIDATION

| Check | Result |
|---|---|
| Validator count | 4 ✅ |
| Unique NodeIDs | 4 ✅ |
| Unique BLS keys | 4 ✅ |
| All PoPs present | ✅ |
| ChangeOwnerAddr (all 4) | `P-fuji17c7fuusyh76r74zwge4sl0nc3458xdkv477adz` ✅ |
| No placeholders | ✅ |

| Node | NodeID |
|---|---|
| V6 | `NodeID-144dTzcL2vgpbKzX943xy5pEF3M8oGyiQ` |
| V7 | `NodeID-cwX3HFmaR5QmbxuZaDJCXAueJeyewjni` |
| V8 | `NodeID-7DLuPUaMiDbyVoZ6P92RQdNRFS81cpYb5` |
| V9 | `NodeID-9TiHzx7DZgtCjB9pqyY6db55pZgVZELvJ` |

---

## SAFE VALIDATION COMMANDS RUN

| Command | Result |
|---|---|
| `grep -c "__REPLACE_" config/testnet/genesis.json` | `0` ✅ |
| JSON parse (Python `json.loads`) | Valid ✅ |
| `sha256sum config/testnet/genesis.json` | `2e85b9753a...` ✅ |
| `scripts/testnet/validate-testnet-genesis.sh` | BLOCKED — requires `TESTNET_RPC_URL` (chain not yet deployed — expected at this stage) |

---

## WARNINGS

None. All checks passed.

The validate-testnet-genesis.sh script is blocked only because it validates on-chain genesis post-deployment. That script is run in Step 8 (after the chain is live), not here.

---

## FINAL VALIDATION RESULT

```
┌─────────────────────────────────────────────────────┐
│          GENESIS GENERATION: SUCCESS ✅              │
│                                                     │
│  File:    config/testnet/genesis.json               │
│  SHA256:  2e85b9753a51b429725fb768eb09f6208f36cb1   │
│           cec614bb788886eedaba6a657                 │
│                                                     │
│  Placeholders filled:     7 / 7                     │
│  Alloc addresses correct: 6 / 6                     │
│  Total supply:            100,000,000 PW            │
│  chainId:                 77                        │
│  FeeDistributor in rewardManager: ✅                │
│  No address(0):           ✅                        │
│  No old deployer address: ✅                        │
│                                                     │
│  Ceremony stopped after Step 2 as instructed.       │
│                                                     │
│  NEXT: Step 3 — avalanche blockchain deploy         │
│        (IRREVERSIBLE — await operator instruction)  │
└─────────────────────────────────────────────────────┘
```

---

*Completely off-chain. No transactions submitted. No chain created. No contracts deployed.*  
*Report: `docs/PW-C15-GENESIS-GENERATION-REPORT.md` | PW-C15 | 2026-08-16*
