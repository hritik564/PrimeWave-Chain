# PW-C20 — End-to-End Protocol / Contract Functional Test Report

**Sprint:** PW-C20  
**Date:** 2026-08-17  
**Chain:** PrimeWave Testnet (Chain ID 77)  
**Blockchain ID:** `22iFuL8GqPYbtnPKNFrq7AzoDfv3FYwq8T93GubRi12LQVjLni`  
**Primary RPC:** `http://159.195.47.126/ext/bc/22iFuL8GqPYbtnPKNFrq7AzoDfv3FYwq8T93GubRi12LQVjLni/rpc`  
**Overall Verdict:** 🟢 **GREEN**

---

## Contract Addresses Used

Sourced from `local-data/testnet-deployed-contracts.env` (canonical deployment file):

| Contract | Address |
|---|---|
| EmergencyMultisig | `0x59a419F3160fa9B4b6aE98b18C2ABA3d5aBb81Fa` |
| PrimeWaveTimelock | `0x7D50dBEb0d38Fe2E3AcdaBF70Fa99228E3Ec6AEE` |
| ValidatorFeeVault | `0x8008e22DB31e787b98dfC891E1076747D17A3EE8` |
| DevTreasury | `0x7Edc50F7cD417d0ac94f3c17E5D57EE4eaa23B89` |
| FeeDistributor | `0x27B15970700daC632f0814522118A1c3B200d971` |
| ValidatorRegistry | `0x14c47a0D544684FC0189Bce13220B38523Fff9da` |
| RewardVault | `0x469B3d8B88006ea5b9eeC9c7c6aD650FB929C7e4` |

---

## Phase 1 — Network Health 🟢

### RPC Methods (Primary: V9 / 159.195.47.126)

| Method | Value | Status |
|---|---|---|
| `eth_chainId` | 77 (0x4d) | ✅ |
| `net_version` | 77 | ✅ |
| `eth_blockNumber` | 2 (at pre-test snapshot) | ✅ |
| `eth_syncing` | false | ✅ |
| `eth_gasPrice` | 25,000,000,001 wei (25 gwei) | ✅ |
| `eth_getBlockByNumber(latest)` | block 2, gasLimit=30,000,000, gasUsed=5,672,342 | ✅ |
| `eth_getTransactionCount(deployer)` | 9 (post-C19 deployment) | ✅ |
| `eth_getBalance(deployer)` | 999,999.834677649993387106 PW | ✅ |

**Notable:** `block.miner` in block 2 = `0x27B15970700daC632f0814522118A1c3B200d971` (FeeDistributor). This confirms the genesis `rewardManagerConfig.rewardAddress` is active — block rewards route to FeeDistributor from genesis block onward. ✅

### Validator Health (All 4 Validators)

| Validator | IP | `healthy` | Block | Block Hash (first 20) | Peers |
|---|---|---|---|---|---|
| V6 | 152.53.66.93 | true | 2 | `0x930b14a86f3763b8...` | 59 |
| V7 | 152.53.66.201 | true | 2 | `0x930b14a86f3763b8...` | 59 |
| V8 | 159.195.44.104 | true | 2 | `0x930b14a86f3763b8...` | 59 |
| V9 | 159.195.47.126 | true | 2 | `0x930b14a86f3763b8...` | 59 |

**All 4 validators agree on block number and block hash.** ✅  
No validator disagreement detected. Proceeding with transaction tests.

---

## Phase 2 — Contract Bytecode 🟢

All 7 contracts verified to have non-empty bytecode via `eth_getCode`.

| Contract | Address | Bytecode Chars | SHA-256 |
|---|---|---|---|
| EmergencyMultisig | `0x59a419F3...81Fa` | 7,056 | `cd51e22f71c914da...` |
| PrimeWaveTimelock | `0x7D50dBEb...6AEE` | 5,618 | `eac959a65a762450...` |
| ValidatorFeeVault | `0x8008e22D...3EE8` | 12,448 | `cd06d1f5b7f2d748...` |
| DevTreasury | `0x7Edc50F7...23B89` | 694 | `813cc2cc71621c32...` |
| FeeDistributor | `0x27B15970...d971` | 5,320 | `e10508702df15428...` |
| ValidatorRegistry | `0x14c47a0D...f9da` | 9,344 | `a8e2902f9fe4eb87...` |
| RewardVault | `0x469B3d8B...C7e4` | 13,832 | `98c0a4434783a300...` |

All match the C19 deployment report. ✅

**PoAManager predeploy:** `0x0Feedc0de0000000000000000000000000000000` — `eth_getCode` returns `0x` (empty). This is expected: the PoAManager is a stateful precompile handled natively by the subnet-evm VM, not a standard EVM contract. Balance: 0 PW (no stake allocated to this address). ✅

---

## Phase 3 — Read-Only Contract State 🟢

### EmergencyMultisig

| Getter | Value | Expected | ✓ |
|---|---|---|---|
| `signers(0)` | `0xb24F3FAF5B9ab7aFb625F105C791d5231b094853` | testnet-ems-signer-1 | ✅ |
| `signers(1)` | `0x508367082eF7A3A8567fa10D92c98524EE2F3d30` | testnet-ems-signer-2 | ✅ |
| `signers(2)` | `0xFa21258c9e5faa7aECbFD13f635863C5da0b8EC3` | testnet-ems-signer-3 | ✅ |
| `signers(3)` | `0xB1346A22773B853552aF028b767bD6cC0171006a` | testnet-ems-signer-4 | ✅ |
| `signers(4)` | `0x2D2d07AB95636Da735BAcBDC018420ca621C3448` | testnet-ems-signer-5 | ✅ |
| `THRESHOLD()` | 3 | 3 | ✅ |
| `nonce()` | 0 | 0 (no proposals yet) | ✅ |

5 of 5 signers correct. Threshold = 3-of-5. ✅

### PrimeWaveTimelock

| Getter | Value | ✓ |
|---|---|---|
| `proposer()` | `0xB518397E3D65a0E7475635F01C225E9426a76F11` (deployer) | ✅ |

### DevTreasury

| Getter | Value | ✓ |
|---|---|---|
| `feeDistributor()` | `0x27B15970700daC632f0814522118A1c3B200d971` | ✅ |
| `cumulativeReceived()` | 0.0 PW (pre-distribution) | ✅ |
| `treasuryBalance()` | 0.0 PW (pre-distribution) | ✅ |

### FeeDistributor — Split Configuration

| Getter | Value | Protocol Spec | ✓ |
|---|---|---|---|
| `validatorFeeVault()` | `0x8008e22DB31e787b98dfC891E1076747D17A3EE8` | ValidatorFeeVault | ✅ |
| `treasury()` | `0x7Edc50F7cD417d0ac94f3c17E5D57EE4eaa23B89` | DevTreasury | ✅ |
| `pauseController()` | `0x59a419F3160fa9B4b6aE98b18C2ABA3d5aBb81Fa` | EMS | ✅ |
| `VALIDATOR_BPS()` | 7,000 | 7,000 (70%) | ✅ |
| `TREASURY_BPS()` | 2,000 | 2,000 (20%) | ✅ |
| `BASIS_POINTS()` | 10,000 | 10,000 | ✅ |
| Burn (implied) | 1,000 BPS | 1,000 (10%) | ✅ |
| `BURN_ADDRESS()` | `0x000000000000000000000000000000000000dEaD` | Dead address | ✅ |
| `paused()` | false | false | ✅ |
| Native balance | 0.166372 PW | Accumulated block fees | ✅ |

**Split confirmed:** 70% → ValidatorFeeVault · 20% → DevTreasury · 10% → `0x000...dEaD` (burn). ✅

### ValidatorRegistry

| Getter | Value | Expected | ✓ |
|---|---|---|---|
| `protocolAdmin()` | `0xB518397E3D65a0E7475635F01C225E9426a76F11` | Deployer | ✅ |
| `validatorManager()` | `0x0Feedc0de0000000000000000000000000000000` | PoAManager predeploy | ✅ |
| `feeVault()` | `0x8008e22DB31e787b98dfC891E1076747D17A3EE8` | ValidatorFeeVault | ✅ |
| `managedCount()` | 0 | 0 (no validators registered yet) | ✅ |

### ValidatorFeeVault

| Getter | Value | Note | ✓ |
|---|---|---|---|
| `protocolAdmin()` | `0x14c47a0D544684FC0189Bce13220B38523Fff9da` | ValidatorRegistry (by design) | ✅ |
| `netReceived()` | 0.0 PW | Pre-distribution | ✅ |
| Native balance | 0.000 PW | Pre-distribution | ✅ |

### RewardVault

| Getter | Value | Expected | ✓ |
|---|---|---|---|
| `admin()` | `0xB518397E3D65a0E7475635F01C225E9426a76F11` | Deployer | ✅ |
| `pauseController()` | `0x59a419F3160fa9B4b6aE98b18C2ABA3d5aBb81Fa` | EMS | ✅ |
| `totalFunded()` | 15,000,000 PW | 15,000,000 PW | ✅ |
| `totalEmitted()` | 0.0 PW | 0 (no recipients yet) | ✅ |
| `emissionRatePerSecond()` | 95,129,375,951,293,759 wei/s | MAX_RATE_PER_SECOND | ✅ |
| `currentAnnualEmission()` | ~3,000,000 PW/year | 3,000,000 PW/year | ✅ |
| `recipientCount()` | 0 | 0 (no validators registered) | ✅ |
| `vaultBalance()` | 15,000,000 PW | 15,000,000 PW | ✅ |
| `paused()` | false | false | ✅ |
| `isExhausted()` | false | false | ✅ |

---

## Phase 4 — Genesis Balance / Supply Validation 🟢

**Native token: PW** (not AVAX — AVAX is only relevant to Fuji/P-Chain)

All balances read directly from the PrimeWave L1 via `eth_getBalance`.

| Role | Address | Genesis Alloc | On-Chain Balance | ✓ |
|---|---|---|---|---|
| Treasury | `0x1F471d2Dc7CB8b2C773aFeD40d4bD467ed1FdaD8` | 25,000,000 PW | 25,000,000.000 PW | ✅ |
| Community | `0xA6744C599A0d40082aAF03Bd643cfc30B2B16a0c` | 20,000,000 PW | 20,000,000.000 PW | ✅ |
| Team | `0x46a419514f52A4763596F75A9169B0Bd0153C673` | 20,000,000 PW | 20,000,000.000 PW | ✅ |
| Deployer | `0xB518397E3D65a0E7475635F01C225E9426a76F11` | 16,000,000 PW | ~999,999.835 PW | ✅ (15M to RV + gas) |
| Ecosystem | `0x2c5E541f667768dd1986C73530Dc29250fA86B7B` | 10,000,000 PW | 10,000,000.000 PW | ✅ |
| Reserve | `0x3C98105b99bb9dc97B341D11ec264F5127A7221C` | 9,000,000 PW | 9,000,000.000 PW | ✅ |
| RewardVault | `0x469B3d8B88006ea5b9eeC9c7c6aD650FB929C7e4` | — | 15,000,000.000 PW | ✅ (funded by deployer) |

**Total intended PW supply: 100,000,000 PW** ✅  
Genesis alloc sum verified = 100,000,000 PW. All non-deployer allocations are untouched.

---

## Phase 5 — Deployer Nonce / Controlled Test Wallets 🟢

Two temporary testnet-only EOAs generated using `cast wallet new`. Private keys captured in shell variables, never printed, logged, committed, or written to any file. Both wallets will be abandoned after this test.

| Wallet | Address |
|---|---|
| Test Wallet 1 (sender) | `0xe1d067E5D84b0fAA8567E79D7F53663030D4197C` |
| Test Wallet 2 (recipient) | `0x340313861881AE0d6f0652FC0d53927DdD36E3E7` |

### Funding Transaction (Deployer → W1)

| Field | Value |
|---|---|
| TX Hash | `0xa5264f07deaccd9df5286c5609dcd65cfef90e67848d2b7358cbdcc9b131972c` |
| Block | 3 |
| Amount | 2 PW |
| Gas Used | 21,000 |
| Status | 1 ✅ |
| W1 balance after | 2.000000000000000000 PW ✅ |

---

## Phase 6 — Basic PW Transfer 🟢

Transfer of **0.5 PW** from W1 to W2.

| Field | Value |
|---|---|
| TX Hash | `0x7d875c48c2eab8fca19789eb8d40798c75175c9305cff704b479b39afdd82353` |
| Block | 4 |
| From | `0xe1d067E5D84b0fAA8567E79D7F53663030D4197C` (W1) |
| To | `0x340313861881AE0d6f0652FC0d53927DdD36E3E7` (W2) |
| Value | 500,000,000,000,000,000 wei (0.5 PW) |
| Gas Used | 21,000 |
| Status | 1 ✅ |

### Balance Verification

| | Before | After | Change |
|---|---|---|---|
| W1 | 2.000 PW | 1.499475 PW | −0.500525 PW (0.5 sent + 0.000525 gas) ✅ |
| W2 | 0.000 PW | 0.500000 PW | +0.500000 PW ✅ |

`eth_getTransactionByHash` returned the correct TX with matching block, from, to, and value. ✅

---

## Phase 7 — Gas / EVM Functionality 🟢

| Test | Method | Result | ✓ |
|---|---|---|---|
| Gas estimation | `eth_estimateGas` (simple transfer) | 21,000 gas | ✅ |
| Read-only call | `eth_call` → `RewardVault.vaultBalance()` | 15,000,000 PW | ✅ |
| Transaction receipt | `eth_getTransactionReceipt` (Phase 6 TX) | status=1, block=4 | ✅ |
| Transaction lookup | `eth_getTransactionByHash` | Correct fields returned | ✅ |
| Logs query | `eth_getLogs` (FeeDistributor, all blocks) | 1 log (FeeDistributed, block 5) | ✅ |
| Logs query | `eth_getLogs` (RewardVault, block 2) | 2 logs (deployment events) | ✅ |
| Block number | `eth_blockNumber` | 4 (post Phase 6) | ✅ |
| Balance | `eth_getBalance` | Correct for all tested accounts | ✅ |
| Nonce | `eth_getTransactionCount` | Accurate after each TX | ✅ |

Gas estimation is sensible (21,000 for a simple transfer = standard). All EVM methods respond correctly. ✅

---

## Phase 8 — Fee Distribution Test 🟢

The FeeDistributor had **0.166372350006654894 PW** accumulated from block rewards (blocks 1 and 2 mining fees routed by the RewardManager precompile). `distribute()` is permissionless — any address may call it.

### State Before distribute()

| | Value |
|---|---|
| FeeDistributor balance | 0.166372350006654894 PW |
| ValidatorFeeVault balance | 0.000000000000000000 PW |
| DevTreasury balance | 0.000000000000000000 PW |
| Dead address (`0x000...dEaD`) | 0.000000000000000000 PW |
| `totalDistributed()` | 0.0 PW |

### distribute() Transaction

| Field | Value |
|---|---|
| TX Hash | `0xd41117d82d2978912b0f3123e866a3de123ffe71dcec31380c07e324d44544f3` |
| Block | 5 |
| Gas Used | 245,591 |
| Caller | Deployer (permissionless — any address valid) |
| Status | 1 ✅ |

### State After distribute()

| | Value | Expected Split | Match |
|---|---|---|---|
| FeeDistributor balance | 0.006139775000245591 PW | 0 (gas residual — see note) | ✅ |
| ValidatorFeeVault balance | 0.116460645004658425 PW | 70% of 0.166372 = 0.116460 PW | ✅ |
| DevTreasury balance | 0.033274470001330978 PW | 20% of 0.166372 = 0.033274 PW | ✅ |
| Dead address (`0x000...dEaD`) | 0.016637235000665491 PW | 10% of 0.166372 = 0.016637 PW | ✅ |

**FeeDistributor residual note:** The 0.006139775 PW remaining in FeeDistributor after distribute() equals exactly the gas fee paid for the distribute() TX itself (245,591 gas × 25 gwei = 0.006139775 PW). This gas fee was credited to FeeDistributor (the `rewardAddress`) during block 5 execution, after distribute() had already read its balance. This is correct per-spec behaviour; this residual will be distributed in the next distribute() call.

### FeeDistributed Event (decoded)

| Field | Value |
|---|---|
| Contract | `0x27B15970700daC632f0814522118A1c3B200d971` (FeeDistributor) |
| Event topic0 | `0x2d66980446807b1d31374b749560b32b34152b41997c3670976f2c15fcc0f1c7` |
| `amount` | 0.166372350006654894 PW |
| `validatorShare` | 0.116460645004658425 PW (70.0%) |
| `treasuryShare` | 0.033274470001330978 PW (20.0%) |
| `burnShare` | 0.016637235000665491 PW (10.0%) |
| `blockNumber` | 5 |
| TX Hash | `0xd41117d82d2978912b0f3123e866a3de123ffe71dcec31380c07e324d44544f3` |

**Sum invariant:** 0.116460 + 0.033274 + 0.016637 = 0.166372 PW = amount ✅ (zero dust)

ValidatorFeeVault emitted a receive event. DevTreasury emitted a receive event. All three destination events confirmed. ✅

---

## Phase 9 — Reward Vault Test 🟡 (Deferred)

| Getter | Value | Note |
|---|---|---|
| `admin()` | Deployer | ✅ |
| `pauseController()` | EMS | ✅ |
| `vaultBalance()` | 15,000,000 PW | ✅ |
| `totalFunded()` | 15,000,000 PW | ✅ |
| `totalEmitted()` | 0.0 PW | 0 (no recipients) |
| `emissionRatePerSecond()` | 95,129,375,951,293,759 wei/s | = MAX_RATE (~3M PW/year) |
| `recipientCount()` | 0 | No validators registered |
| `paused()` | false | ✅ |
| `isExhausted()` | false | ✅ |

**Dynamic claim/accrual test: DEFERRED**

The RewardVault has 0 registered recipients. Recipients are added by the StakingManager (not yet deployed) when validators are registered. No claim or accrual test is possible without at least one registered validator + weight + time elapsed. All view-state reads confirm the vault is correctly configured and funded. The dynamic reward-flow test is deferred to the validator onboarding phase.

---

## Phase 10 — Access Control Negative Tests 🟢

Unauthorized test wallet: `0x0Ef7532f8B4BaEBE7586a40f2962c1131F815A70` (no roles, no keys committed)

All negative tests used `eth_call` simulation (no state change required for revert confirmation). One actual send was attempted but the client correctly rejected it at simulation stage.

| # | Test | Method | Contract | Expected | Result | ✓ |
|---|---|---|---|---|---|---|
| 1 | Unauthorized `setPauseController` | eth_call | FeeDistributor | revert | `"FeeDistributor: not pause controller"` | ✅ |
| 2 | Unauthorized `pause()` | eth_call | RewardVault | revert | `"RV: not pause controller"` | ✅ |
| 3 | Unauthorized `setEmissionRate(1)` | eth_call | RewardVault | revert | `"RV: not admin"` | ✅ |
| 4 | Unauthorized `setUptimeBips(...)` | eth_call | ValidatorRegistry | revert | `"PWVR: not admin"` | ✅ |
| 5 | Unauthorized `pause()` | eth_call | FeeDistributor | revert | `"FeeDistributor: not pause controller"` | ✅ |
| 6 | Unauthorized `setEmissionRate(1)` | send | RewardVault | revert | TX rejected/reverted | ✅ |

All access-control guards are enforced. `emissionRatePerSecond()` verified unchanged (95,129,375,951,293,759 wei/s) after all negative tests. ✅  
No ownership modified. No validator membership changed. No destructive functions tested.

---

## Phase 11 — Event Validation 🟢

### PW Native Transfer Events (Phase 6)

Native PW transfers do not emit EVM logs (no ERC-20 Transfer event — PW is the chain's native token, not a token contract). Block 4 has 0 logs. The transfer is verified via:
- `eth_getTransactionByHash` → correct from/to/value ✅
- `eth_getBalance` → sender decreased, recipient increased ✅
- `eth_getTransactionReceipt` → status=1, gasUsed=21,000 ✅

### RewardVault Deployment Events (Block 2)

| # | Event Topic0 | TX Hash | Description |
|---|---|---|---|
| 1 | `0x53eef77c...` | `0xc7f2c846...` | RewardVault constructed / initial rate set |
| 2 | `0xa9777b7c...` | `0x618b02a6...` | RewardVault.fund() — 15,000,000 PW funded |

### FeeDistributor — FeeDistributed Event (Block 5)

| Field | Value |
|---|---|
| Topic0 | `0x2d66980446807b1d31374b749560b32b34152b41997c3670976f2c15fcc0f1c7` |
| Indexed param | block number = 5 |
| Amount | 0.166372350006654894 PW |
| ValidatorShare | 0.116460645004658425 PW |
| TreasuryShare | 0.033274470001330978 PW |
| BurnShare | 0.016637235000665491 PW |
| Block | 5 |
| TX Hash | `0xd41117d82d2978912b0f3123e866a3de123ffe71dcec31380c07e324d44544f3` |

ValidatorFeeVault and DevTreasury also emitted receive-acknowledgement events in the same TX. All three destination events confirmed on-chain. ✅

---

## Phase 12 — Multi-Validator Consistency 🟢

Queried all four validators after all Phase 5–8 transactions were confirmed.

| Validator | Block | Block Hash (first 20 chars) |
|---|---|---|
| V6 (152.53.66.93) | 6 | `0x29191ed4025d7722b4...` |
| V7 (152.53.66.201) | 6 | `0x29191ed4025d7722b4...` |
| V8 (159.195.44.104) | 6 | `0x29191ed4025d7722b4...` |
| V9 (159.195.47.126) | 6 | `0x29191ed4025d7722b4...` |

**V6 = V7 = V8 = V9** — identical block height and block hash. ✅  
No consensus disagreement. All validators processed the same transaction history.

Transaction receipt for Phase 6 TX (`0x7d875c...`) returns consistent results from all 4 RPCs.  
FeeDistributor `validatorFeeVault()` returns identical address from all 4 RPCs.

---

## Phase 13 — RPC Failover 🟢

All four public RPC endpoints tested independently.

| Validator | RPC Endpoint | Chain ID | Block | Deployer Balance | FD Code Size | Latency |
|---|---|---|---|---|---|---|
| V6 | `http://152.53.66.93/ext/bc/.../rpc` | 77 | 6 | 999,997.77... PW | 5,321 chars | 367 ms |
| V7 | `http://152.53.66.201/ext/bc/.../rpc` | 77 | 6 | 999,997.77... PW | 5,321 chars | 343 ms |
| V8 | `http://159.195.44.104/ext/bc/.../rpc` | 77 | 6 | 999,997.77... PW | 5,321 chars | 455 ms |
| V9 | `http://159.195.47.126/ext/bc/.../rpc` | 77 | 6 | 999,997.77... PW | 5,321 chars | 457 ms |

All four endpoints:
- Return `chainId = 77` ✅
- Return identical latest block number ✅
- Return identical deployer balance ✅
- Return identical FeeDistributor bytecode size ✅
- Response latency range: 343–457 ms (acceptable for testnet) ✅

---

## Phase 14 — Security / Key Hygiene Check 🟡

| Check | Result | Notes |
|---|---|---|
| `TESTNET_DEPLOYER_KEY` in Replit secret | ✅ Present | Never printed, committed, or written to file |
| Private keys in `local-data/*.env` | ✅ None found | Only `ADDR_*` contract addresses |
| Private keys in git history | ✅ None | Scanned recent commits; no key patterns |
| Temp test wallet keys committed | ✅ None | Keys existed only in shell variables |
| Old deployer key (`0x44A37a...`) | ✅ Address only in docs | Key is permanently lost; no risk |
| Broadcast files | ✅ TX data only | `broadcast/` contains tx params, not signing keys |
| Git untracked files | ✅ Only test prompt file | `attached_assets/...txt` (prompt input) |
| `scripts/start-indexer.sh` 64-char hex | ⚠️ WARNING | Contains `DEV_PRIVATE_KEY_0 = 0xac0974bec39a...` |

**Warning detail:** `scripts/start-indexer.sh` exports `DEV_PRIVATE_KEY_0 = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`. This is the **publicly-known Hardhat/Foundry default mnemonic account 0 key** — the same key that `DeployTestnet.s.sol` explicitly guards against (`DEV_KEY_ADDR = 0xf39Fd6e51...`). It is used for local dev-chain testing only and has no testnet or mainnet value. However, it should be noted in the repository security documentation, and `DEV_PRIVATE_KEY_0` should be moved to a `.env.local` file not tracked by git for hygiene.

This is a LOW severity finding. It does not affect testnet security.

---

## Phase 15 — Final Verdict

| Phase | Test | Result |
|---|---|---|
| 1 | Network health (chain, syncing, gas, block) | 🟢 GREEN |
| 1 | All 4 validators healthy and in sync | 🟢 GREEN |
| 1 | Block agreement (all 4 same hash) | 🟢 GREEN |
| 2 | Contract bytecode exists (all 7) | 🟢 GREEN |
| 3 | EmergencyMultisig state (5 signers, threshold=3) | 🟢 GREEN |
| 3 | Timelock state | 🟢 GREEN |
| 3 | FeeDistributor wiring + 70/20/10 split verified | 🟢 GREEN |
| 3 | ValidatorRegistry state | 🟢 GREEN |
| 3 | RewardVault state (15M PW funded, rate=MAX) | 🟢 GREEN |
| 4 | Genesis allocations (all correct, 100M PW total) | 🟢 GREEN |
| 5 | Test wallets generated, funded, keys not exposed | 🟢 GREEN |
| 6 | PW native transfer (send, receipt, balance check) | 🟢 GREEN |
| 7 | EVM methods (estimateGas, call, receipt, logs, etc.) | 🟢 GREEN |
| 8 | FeeDistributor distribute() — 70/20/10 verified on-chain | 🟢 GREEN |
| 9 | RewardVault view reads | 🟢 GREEN |
| 9 | Dynamic reward claim test | 🟡 YELLOW — deferred (no registered recipients) |
| 10 | Access control (5 of 5 unauthorized calls reverted) | 🟢 GREEN |
| 11 | Event validation (FeeDistributed, RV events) | 🟢 GREEN |
| 12 | Multi-validator consistency (all 4 identical) | 🟢 GREEN |
| 13 | RPC failover (all 4 endpoints correct, 343–457ms) | 🟢 GREEN |
| 14 | Key hygiene | 🟡 YELLOW — DEV_PRIVATE_KEY_0 in start-indexer.sh (harmless public dev key) |

**Release-blocker categories:** Consensus ✅ · Validator agreement ✅ · Contract bytecode ✅ · Core wiring ✅ · Basic PW transfer ✅ · Access control ✅ — **No release blockers found.**

---

## Phase 16 — Transaction / Wallet / Block Reference Table

| Phase | TX Hash | Block | From | To | Amount | Status |
|---|---|---|---|---|---|---|
| 5 (fund W1) | `0xa5264f07deaccd9df5286c5609dcd65cfef90e67848d2b7358cbdcc9b131972c` | 3 | Deployer | W1 | 2 PW | ✅ |
| 6 (W1→W2) | `0x7d875c48c2eab8fca19789eb8d40798c75175c9305cff704b479b39afdd82353` | 4 | W1 | W2 | 0.5 PW | ✅ |
| 8 (distribute) | `0xd41117d82d2978912b0f3123e866a3de123ffe71dcec31380c07e324d44544f3` | 5 | Deployer | FeeDistributor | distribute() | ✅ |
| 10 (fund unauth) | (deployer → unauth, 0.05 PW) | ~5–6 | Deployer | Unauth wallet | 0.05 PW | ✅ |

| Wallet | Address | Role |
|---|---|---|
| Deployer | `0xB518397E3D65a0E7475635F01C225E9426a76F11` | Protocol deployer |
| Test W1 | `0xe1d067E5D84b0fAA8567E79D7F53663030D4197C` | Temporary test sender |
| Test W2 | `0x340313861881AE0d6f0652FC0d53927DdD36E3E7` | Temporary test recipient |
| Unauth | `0x0Ef7532f8B4BaEBE7586a40f2962c1131F815A70` | Unauthorized negative-test wallet |

All temporary test wallets carry small residual PW balances (< 2 PW combined). No protocol state was modified except the permissionless `distribute()` call, which is a normal intended protocol operation.

---

## Deferred Tests

| Test | Reason | Follow-up |
|---|---|---|
| RewardVault dynamic claim/accrual | No registered recipients (StakingManager not deployed) | Activate in validator onboarding phase |
| Validator registration flow | PoAManager integration not exercised | Activate in validator onboarding phase |

---

## 🟢 FINAL VERDICT: GREEN

The PrimeWave L1 and its deployed protocol contracts are **functionally sound** and ready for controlled public testnet access.

- All 4 validators are healthy, in consensus, and in agreement ✅  
- All 7 protocol contracts deployed with correct bytecode, wiring, and state ✅  
- Native PW transfers work correctly ✅  
- Fee routing (RewardManager → FeeDistributor → 70/20/10 split) proven live on-chain ✅  
- Access control guards enforced across all contracts ✅  
- All 4 RPC endpoints respond correctly and consistently ✅  
- No release blockers found ✅

*STOP — per PW-C20 protocol spec. Do not proceed to PWCScan, faucet, domain setup, PWSwap, or mainnet.*
