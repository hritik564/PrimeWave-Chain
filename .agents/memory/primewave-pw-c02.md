---
name: PrimeWave Chain PW-C02
description: Transaction verification + fee architecture sprint — completed Aug 13 2026; all 13 tests pass, fee routing confirmed, 70/20/10 feasibility validated
---

## Status
**COMPLETE** — 13 PASS, 0 FAIL, 1 SKIP (restart). Tests 8-10 now pass.
Reports at: `docs/PW-C02-TRANSACTION-TEST-REPORT.md`, `docs/PW-C02-FEE-ARCHITECTURE-ANALYSIS.md`, `docs/PW-C02-FINAL-REPORT.md`

## What Was Done
- Installed Foundry v1.7.1 (commit `4072e48705`, 2026-05-08)
- Created `foundry.toml` (pinned solc=0.8.30, evm_version=shanghai, rpc alias `primewavedev`)
- Updated `scripts/_common.sh` to add Foundry to PATH and pin `FOUNDRY_VERSION`/`FOUNDRY_COMMIT`
- Updated Tests 8-10 in `tests/smoke-test.sh` with full balance+receipt verification using `cast send`
- Sent first-ever PW transaction on local dev chain

## Confirmed Transaction

| Field | Value |
|---|---|
| TX hash | `0x33e72fa680357740a093219ba8b79b4308ee5d9b1d6d9e5ade002a1959f9a7b2` |
| Block | 1 |
| Status | 0x1 (success) |
| Sender | DEV_ACCOUNT_0 `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` |
| Receiver | DEV_ACCOUNT_1 `0x70997970C51812dc3A010C7d01b50e0d17dc79C8` |
| Value | 1.0 PW |
| Gas used | 21,000 |
| Effective gas price | 25,000,000,001 wei/gas |
| Gas cost | 525,000,000,021,000 wei = 0.000525 PW |

## Critical Fee Architecture Findings

### 1. Avalanche EVM fee routing with `allowFeeRecipients: false`
- ALL fees (base fee + priority tip) go to `0x0100000000000000000000000000000000000000` (Avalanche blackhole)
- This is NOT the same as Ethereum mainnet which burns base fee via protocol
- In Avalanche EVM, total fee = gas × effectiveGasPrice → coinbase
- With `allowFeeRecipients=false`: coinbase = blackhole `0x0100...` (inaccessible, effectively burned)

**Why:** Confirmed by block.miner field in block 1 = `0x0100000000000000000000000000000000000000` and balance audit showing full gas cost missing from all known addresses (went to blackhole).

### 2. Precompile activation status in current dev genesis

| Precompile | Address | Status |
|---|---|---|
| NativeMinter | 0x0200...1 | NOT ACTIVE ✅ (must never be activated) |
| TxAllowList | 0x0200...2 | NOT ACTIVE |
| FeeManager | 0x0200...3 | NOT ACTIVE (needed for production) |
| RewardManager | 0x0200...4 | NOT ACTIVE (needed for production) |
| WarpMessenger | 0x0200...5 | NOT ACTIVE in dev mode (active in production with P-Chain) |

Detection method: `eth_getCode` returns `0x` = not active. ETH calls to inactive precompiles return `0x` (not a revert).

### 3. RewardManager cannot do percentage splits
RewardManager supports ONE destination: burn (to blackhole), fee recipients (one addr per validator), or one fixed rewardAddress. It CANNOT natively split 70/20/10. A FeeDistributor contract is required.

### 4. 70/20/10 is feasible via Model C
```
RewardManager.rewardAddress = FeeDistributor.address
FeeDistributor.distribute():
  70% → ValidatorFeeVault
  20% → PrimeWaveTreasury
  10% → 0x000...dead (burn address)
```
Confirmed consistent with locked PW-C00 architecture decisions.

### 5. Supply invariant holds
- 100M PW cap enforced: NativeMinter is inactive
- After TX: sum(all accounts + blackhole) = genesis total = 50,000 PW (dev accounts) ✅

## Foundry.toml Key Quirks
- Use `libs = ["contracts/lib"]` (ARRAY), NOT `lib = "contracts/lib"` (string)
- In v1.7.1: `lib` (singular) triggers "Found unknown `lib` config" warning on stderr; it still works but JSON parsing fails when stderr is merged with stdout via 2>&1
- Fix: separate stdout and stderr: `2>/tmp/cast-stderr.txt`
- `cast send --json` puts receipt JSON to stdout; warnings to stderr

## Files Created/Modified in PW-C02
- `foundry.toml` — NEW; pinned config
- `scripts/_common.sh` — Foundry PATH + version constants added
- `tests/smoke-test.sh` — Tests 8-10 fully implemented (balance + receipt verification)
- `docs/PW-C02-TRANSACTION-TEST-REPORT.md` — NEW
- `docs/PW-C02-FEE-ARCHITECTURE-ANALYSIS.md` — NEW
- `docs/PW-C02-FINAL-REPORT.md` — NEW
- `docs/PRIMEWAVE_DEPENDENCY_COMPATIBILITY.md` — §2.7 Foundry filled in

## Open Questions for PW-C03
OQ-C02-01 to OQ-C02-08 — see `docs/PW-C02-FEE-ARCHITECTURE-ANALYSIS.md` §14 and `docs/PW-C02-FINAL-REPORT.md` §K.

## DO NOT BEGIN PW-C03 without explicit user approval
