# PrimeWave Testnet — C→P Fund Transfer Report
## PW-C15 | Ceremony Step 1 | 2026-08-16T18:58:57Z

---

## TRANSFER DETAILS

| Field | Value |
|---|---|
| Operation | ExportTx (C→P) + ImportTx (C→P) |
| Source chain | C-Chain (Fuji) |
| Destination chain | P-Chain (Fuji) |
| Source address | `0xB518397E3D65a0E7475635F01C225E9426a76F11` |
| Destination P-Chain address | `P-fuji17c7fuusyh76r74zwge4sl0nc3458xdkv477adz` |
| Requested amount | 1.5 AVAX |
| Execution timestamp | 2026-08-16T18:58:57Z |
| Completion timestamp | 2026-08-16T18:59:24Z |

### Command executed

```bash
./local-bin/avalanche key transfer \
  --key testnet-deployer \
  --fuji \
  --amount 1.5 \
  --c-chain-sender \
  --p-chain-receiver
```

*Note: The Day-0 checklist used `--source-chain C --destination-chain P` which are not valid flags in CLI v1.9.5. The equivalent flags `--c-chain-sender` / `--p-chain-receiver` were used instead. Behaviour is identical.*

---

## FEES

| Transaction | Fee |
|---|---|
| ExportTx C-Chain fee | 0.000000001 AVAX |
| ImportTx P-Chain fee | 0.000008270 AVAX |
| **Total fees** | **0.000008271 AVAX** |

---

## BALANCES

### C-Chain (`0xB518397E3D65a0E7475635F01C225E9426a76F11`)

| | Balance |
|---|---|
| Before | 2.000000000 AVAX |
| After | 0.499999999 AVAX |
| Change | −1.500000001 AVAX (1.5 sent + 0.000000001 export fee) |

### P-Chain (`P-fuji17c7fuusyh76r74zwge4sl0nc3458xdkv477adz`)

| | Balance |
|---|---|
| Before | 0.000000000 AVAX |
| After | 1.499991730 AVAX |
| Change | +1.499991730 AVAX (1.5 received − 0.000008270 import fee) |

### C-Chain nonce

| | Value |
|---|---|
| Before | 0 |
| After | 1 |
| Transactions submitted | **Exactly 1** ✅ |

---

## CONFIRMATION CHECKS

| Check | Result |
|---|---|
| P-Chain balance ≥ 1.4 AVAX (ceremony minimum) | ✅ 1.499991730 AVAX |
| C-Chain balance > 0 (gas reserve for contracts) | ✅ 0.499999999 AVAX |
| Destination address correct | ✅ `P-fuji17c7fuusyh76r74zwge4sl0nc3458xdkv477adz` |
| Sender correct (nonce 0→1) | ✅ `0xB518397E3D65a0E7475635F01C225E9426a76F11` |
| No unexpected transactions (nonce increased by exactly 1) | ✅ |
| Deployer key identity unchanged post-transfer | ✅ C-Chain and P-Chain addresses identical to pre-transfer |
| CLI exit code | ✅ 0 |

---

## KEY IDENTITY — POST-TRANSFER CONFIRMATION

| Field | Value |
|---|---|
| CLI key name | `testnet-deployer` |
| C-Chain | `0xB518397E3D65a0E7475635F01C225E9426a76F11` ✅ |
| P-Chain | `P-fuji17c7fuusyh76r74zwge4sl0nc3458xdkv477adz` ✅ |

---

## FINAL RESULT

```
┌────────────────────────────────────────────────────┐
│         C→P FUND TRANSFER: COMPLETE ✅              │
│                                                    │
│  Sent:      1.5 AVAX                               │
│  Received:  1.499991730 AVAX (after P-Chain fee)   │
│  C-Chain remaining: 0.499999999 AVAX               │
│                                                    │
│  Ceremony Step 1 of 3 DONE.                        │
│                                                    │
│  NEXT: Step 2 — Fill genesis + generate genesis.json│
│  THEN: Step 3 — avalanche blockchain deploy        │
│                (IRREVERSIBLE)                      │
└────────────────────────────────────────────────────┘
```

---

*No subnet created. No blockchain created. No contracts deployed. No validators registered.*  
*Ceremony stopped after Step 1 as instructed.*  
*Report: `docs/PW-C15-C2P-FUND-TRANSFER-REPORT.md` | PW-C15 | 2026-08-16*
