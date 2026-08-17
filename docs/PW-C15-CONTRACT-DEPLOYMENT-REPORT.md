# PW-C15 Contract Deployment Report
## PrimeWave Testnet — Phase 2: Contract Deployment + On-Chain Verification

**Report date:** 2026-08-17  
**Chain:** PrimeWave Testnet | Chain ID: 77 | Subnet ID: ovXTQNjfug8bipjnqnSKieZFdtHid2amTQnrbibg4kYQtrLbv  
**Blockchain ID:** 22iFuL8GqPYbtnPKNFrq7AzoDfv3FYwq8T93GubRi12LQVjLni  
**Primary RPC:** http://159.195.47.126/ext/bc/22iFuL8GqPYbtnPKNFrq7AzoDfv3FYwq8T93GubRi12LQVjLni/rpc  

---

## FINAL VERDICT: 🔴 RED

**Reason:** Pre-deployment safety check reveals a hard-stop blocking condition.  
**Deployment has NOT been broadcast.**  
**No contract has been deployed.**  

---

## Phase 1 — Deployment Script Audit

### Script: `contracts/script/DeployTestnet.s.sol`

**Deployment sequence (7 contracts in order):**

| # | Contract | Deploy Nonce (from start N) | Constructor Arguments | Post-Deploy Calls | Predicted Address | Address Written Into | Hardcoded Address | Genesis Match |
|---|---|---|---|---|---|---|---|---|
| 1 | EmergencyMultisig | N+0 | `[EMS_SIGNER_1..5]` (5 keys) | — | Yes (via nonce) | FeeDistributor (pauseController), RewardVault (pauseController) | 5 EMS signer addresses | No |
| 2 | PrimeWaveTimelock | N+1 | `deployer` | — | Yes (via nonce) | — | — | No |
| 3 | ValidatorFeeVault | N+2 | `predictedRegistry` | — | Yes (predicted) | FeeDistributor (validatorFeeVault), Registry (feeVault) | — | No |
| 4 | DevTreasury | N+3 | `predictedFD` | — | Yes (predicted) | — | predictedFD | **YES — genesis rewardAddress must match FD** |
| 5 | FeeDistributor | N+4 | `(feeVault, devTreasury, ems)` | — | Yes (predicted; must match genesis) | — | BURN_ADDRESS 0xdEaD | **YES — genesis rewardManagerConfig.rewardAddress** |
| 6 | PrimeWaveValidatorRegistry | N+5 | `(deployer, POA_MANAGER, feeVault)` | — | Yes (predicted) | FeeVault.protocolAdmin | POA_MANAGER 0x0Feedc0de | No |
| 7 | RewardVault | N+6 | `(deployer, INITIAL_RATE)` | `setPauseController(ems)`, `fund{15M PW}()` | No | — | — | No |

**Guard rails in the script:**
- Hard-reverts if `block.chainid != 77`
- Hard-reverts if deployer == `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` (dev mnemonic)
- Hard-reverts if any EMS signer == address(0)
- Hard-reverts if balance < 15,001 PW
- `require(address(feeDist) == predictedFD)` — self-consistency assertion
- `require(address(registry) == predictedRegistry)` — self-consistency assertion
- `require(rewardVault.totalFunded() == 15_000_000 ether)` — post-fund invariant

**Key constants verified:**
- `TESTNET_CHAIN_ID = 77` ✅
- `REWARD_VAULT_FUND = 15_000_000 ether` ✅
- `INITIAL_RATE = 3_000_000e18 / 31_536_000 = 95_129_375_951_293_760 wei/s` ✅
- `POA_MANAGER_ADDR = 0x0Feedc0de0000000000000000000000000000000` ✅
- `DEV_KEY_ADDR = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` ✅

**EMS signer addresses — cross-check against `local-data/testnet-key-addresses.env`:**

| Constant | Script Value | Env File Value | Match |
|---|---|---|---|
| EMS_SIGNER_1 | 0xb24F3FAF5B9ab7aFb625F105C791d5231b094853 | 0xb24F3FAF5B9ab7aFb625F105C791d5231b094853 | ✅ |
| EMS_SIGNER_2 | 0x508367082eF7A3A8567fa10D92c98524EE2F3d30 | 0x508367082eF7A3A8567fa10D92c98524EE2F3d30 | ✅ |
| EMS_SIGNER_3 | 0xFa21258c9e5faa7aECbFD13f635863C5da0b8EC3 | 0xFa21258c9e5faa7aECbFD13f635863C5da0b8EC3 | ✅ |
| EMS_SIGNER_4 | 0xB1346A22773B853552aF028b767bD6cC0171006a | 0xB1346A22773B853552aF028b767bD6cC0171006a | ✅ |
| EMS_SIGNER_5 | 0x2D2d07AB95636Da735BAcBDC018420ca621C3448 | 0x2D2d07AB95636Da735BAcBDC018420ca621C3448 | ✅ |

**Old deployer check:** The abandoned deployer `0x44A37aF5F03807B1AaA1b20D1BFb3d77959B4B5f` does NOT appear anywhere in `DeployTestnet.s.sol` or in any deployed contract constructor argument. ✅

---

## Phase 2 — Pre-Deployment Safety Check

### 2.1 RPC Health

| Check | Result |
|---|---|
| Primary RPC responds | ✅ YES |
| `eth_chainId` | `0x4d` = **77** ✅ |
| Block number | `0x4` = 4 blocks produced ✅ |
| Backup RPC (152.53.66.201) | ✅ block 4 |
| Backup RPC (159.195.44.104) | ✅ block 4 |
| Backup RPC (152.53.66.93) | ✅ block 4 |

### 2.2 Deployer Status

| Check | Result |
|---|---|
| Deployer address | `0xB518397E3D65a0E7475635F01C225E9426a76F11` |
| PW balance | `0xd3c21bce37b6d9f76f000` = **15,999,999.9974 PW** |
| Minimum required | 15,001 PW (15M fund + 1 PW buffer) |
| Balance sufficient | ✅ YES |
| **Current nonce** | **`0x5` = 5** ⚠️ |
| Deployer is abandoned key? | ✅ NO |
| Deployer is dev mnemonic? | ✅ NO |

### 2.3 Forge Build

**Result: ✅ PASS**  
Only a lint warning about an unsafe typecast in `test/ValidatorFeeVaultUnit.t.sol:46` (test code only, not deployed contracts). All production contracts compile cleanly.

### 2.4 Genesis Allocation Balances

| Address | Label | Expected | Actual On-Chain | Match |
|---|---|---|---|---|
| 0xB518397E3D65a0E7475635F01C225E9426a76F11 | Deployer | 16,000,000 PW | 16,000,000.00 PW | ✅ |
| 0x1F471d2Dc7CB8b2C773aFeD40d4bD467ed1FdaD8 | Treasury | 25,000,000 PW | 25,000,000.00 PW | ✅ |
| 0x46a419514f52A4763596F75A9169B0Bd0153C673 | Team | 20,000,000 PW | 20,000,000.00 PW | ✅ |
| 0xA6744C599A0d40082aAF03Bd643cfc30B2B16a0c | Community | 20,000,000 PW | 20,000,000.00 PW | ✅ |
| 0x2c5E541f667768dd1986C73530Dc29250fA86B7B | Ecosystem | 10,000,000 PW | 10,000,000.00 PW | ✅ |
| 0x3C98105b99bb9dc97B341D11ec264F5127A7221C | Reserve | 9,000,000 PW | 9,000,000.00 PW | ✅ |
| **Total** | | **100,000,000 PW** | **100,000,000 PW** | ✅ |

### 2.5 Key Address Code Checks

| Address | Expected | eth_getCode Result |
|---|---|---|
| `0x27B15970700daC632f0814522118A1c3B200d971` (genesis rewardAddress) | Empty (no code yet) | `0x` (empty) ✅ confirmed |
| `0x0Feedc0de0000000000000000000000000000000` (POA_MANAGER) | Native precompile (no EVM bytecode) | `0x` — expected for Avalanche native precompile ✅ |
| `0x44A37aF5F03807B1AaA1b20D1BFb3d77959B4B5f` (abandoned deployer) | Empty EOA | `0x` ✅ |

---

## 🛑 STOP CONDITION DETECTED — PHASE 2

### CRITICAL FINDING: FeeDistributor Address Mismatch — Nonce Drift

**This is a hard stop. Deployment is BLOCKED.**

#### Root Cause

The FeeDistributor's deployment address is determined by the deployer's nonce at the time of deployment (Ethereum CREATE opcode: `keccak256(RLP([deployer, nonce]))`).

The genesis `rewardManagerConfig.initialRewardConfig.rewardAddress` was set to `0x27B15970700daC632f0814522118A1c3B200d971` during the PW-C15 key ceremony, predicted with the assumption that the **deployer's starting nonce would be 0** at the time of contract deployment.

This prediction was correct for nonce=0:

```
cast compute-address 0xB518397E3D65a0E7475635F01C225E9426a76F11 --nonce 4
  → 0x27B15970700daC632f0814522118A1c3B200d971  ✅ (matches genesis)
```

FeeDistributor is the 5th contract deployed (0-indexed: nonce+4), so with a starting nonce of 0, it lands at nonce 4.

#### Actual Current State

After the PW-C16 chain-launch verification session, the deployer executed **5 transactions** (nonces 0–4) for block production and chain diagnostics. The current nonce is **5**.

| Starting Nonce | FD Nonce | FD Address | Genesis Match |
|---|---|---|---|
| 0 | 4 | `0x27B15970700daC632f0814522118A1c3B200d971` | ✅ (was planned) |
| 1 | 5 | `0x14c47a0D544684FC0189Bce13220B38523Fff9da` | ❌ |
| 2 | 6 | `0x469B3d8B88006ea5b9eeC9c7c6aD650FB929C7e4` | ❌ |
| 3 | 7 | `0x0Dcb2A6718f012Faf373481C99c78513D06db49C` | ❌ |
| 4 | 8 | `0x8377408FD17bD4d9245089daDC9d80De60276c33` | ❌ |
| **5 (current)** | **9** | **`0x8C41F8A20C63f174C27B9dc9A610615c36c801Ca`** | **❌ MISMATCH** |

#### Projected Deployment Addresses at Current Nonce (5)

| Nonce | Contract | Projected Address |
|---|---|---|
| 5 | EmergencyMultisig | `0x14c47a0D544684FC0189Bce13220B38523Fff9da` |
| 6 | PrimeWaveTimelock | `0x469B3d8B88006ea5b9eeC9c7c6aD650FB929C7e4` |
| 7 | ValidatorFeeVault | `0x0Dcb2A6718f012Faf373481C99c78513D06db49C` |
| 8 | DevTreasury | `0x8377408FD17bD4d9245089daDC9d80De60276c33` |
| **9** | **FeeDistributor** | **`0x8C41F8A20C63f174C27B9dc9A610615c36c801Ca`** |
| 10 | PrimeWaveValidatorRegistry | `0x261C6FDF5e77ab6b2A0e97A10dB62B72E665f043` |
| 11 | RewardVault | `0x61c71f1F6EB604b6282e4b97Db5148c5daCD7884` |
| 12 | (tx) setPauseController | — |
| 13 | (tx) fund() | — |

#### Consequence if Deployment Proceeds As-Is

1. **FeeDistributor deploys at nonce 9 → `0x8C41F8A20C63f174C27B9dc9A610615c36c801Ca`** (not the genesis address)
2. **The Avalanche EVM credits all block fees to `0x27B15970700daC632f0814522118A1c3B200d971`** — the address configured at genesis time, which is now a plain EOA with no code
3. **Block fees accumulate at `0x27B15970700daC632f0814522118A1c3B200d971` permanently, inaccessible** — nobody controls that private key (it's a predicted address, not funded)
4. **The FeeDistributor at `0x8C41F8A20C63f174C27B9dc9A610615c36c801Ca` receives zero block fees** — the 70/20/10 split never fires
5. **ValidatorFeeVault accumulates no fees** — validators earn nothing from transaction fees
6. **DevTreasury receives nothing** from fee routing

This breaks the entire fee routing architecture for testnet.

#### Can the RewardManager Precompile Fix This Post-Deployment?

The genesis `rewardManagerConfig` has **no `adminAddresses`**:

```json
"rewardManagerConfig": {
  "blockTimestamp": 0,
  "initialRewardConfig": {
    "rewardAddress": "0x27B15970700daC632f0814522118A1c3B200d971"
  }
}
```

Without an explicit admin address in the allowlist, the RewardManager precompile's `setRewardAddress()` function is uncallable by any user. The reward address is **permanently locked** to `0x27B15970700daC632f0814522118A1c3B200d971` for this chain.

**Conclusion: The FeeDistributor address mismatch cannot be corrected post-deployment without chain recreation.**

---

## Phase 3 — Dry Run

**SKIPPED — Blocked by Phase 2 STOP condition.**

The dry run was not performed because broadcasting a simulation to the live chain while a critical configuration mismatch exists risks confusion and is prohibited by the stop conditions.

---

## Phase 4 — Broadcast

**NOT EXECUTED — Blocked by Phase 2 STOP condition.**

---

## Phases 5–9 — On-Chain Verification, Wiring, Genesis, Smoke Test, Manifest

**NOT APPLICABLE — Deployment did not occur.**

---

## Summary of All Findings

### ❌ BLOCKER (Hard Stop)

| # | Finding | Severity | Resolvable Without Chain Recreation |
|---|---|---|---|
| 1 | Deployer nonce is 5 (was 0 at ceremony time); FeeDistributor will deploy at `0x8C41F8A20C63f174C27B9dc9A610615c36c801Ca`, not at genesis `rewardAddress` `0x27B15970700daC632f0814522118A1c3B200d971`; block fees permanently routed to wrong address; no RewardManager admin to fix post-deploy | **CRITICAL** | **NO** |

### ✅ PASS (All Passing Checks)

| # | Check | Result |
|---|---|---|
| 1 | RPC responds | ✅ All 4 RPCs healthy at block 4 |
| 2 | Chain ID = 77 | ✅ 0x4d |
| 3 | Deployer is correct new key | ✅ 0xB518397E3D65a0E7475635F01C225E9426a76F11 |
| 4 | No old deployer (0x44A3...) in active deployment code | ✅ Confirmed absent |
| 5 | No old FeeDistributor address in active deployment code | ✅ Script uses dynamic prediction |
| 6 | EMS signer addresses populated, non-zero, match env file | ✅ All 5 match |
| 7 | POA_MANAGER_ADDR = 0x0Feedc0de... | ✅ Correct (native precompile) |
| 8 | Deployer PW balance sufficient | ✅ 15,999,999.9974 PW ≥ 15,001 PW |
| 9 | Forge build succeeds | ✅ Clean (lint warning in test file only) |
| 10 | Genesis allocation balances correct | ✅ 100,000,000 PW across 6 addresses |
| 11 | Genesis rewardAddress has no code (pre-deployment state correct) | ✅ |
| 12 | Abandoned deployer has no code | ✅ |
| 13 | No hardcoded zero addresses in constructor arguments | ✅ |
| 14 | Backup RPCs healthy | ✅ All 3 at block 4 |
| 15 | REWARD_VAULT_FUND = 15M PW (matches genesis note) | ✅ |
| 16 | INITIAL_RATE matches governance-locked 3M PW/year | ✅ |
| 17 | RewardVault.fund() post-invariant check is present | ✅ |
| 18 | FD prediction self-consistency check in script | ✅ |
| 19 | Registry prediction self-consistency check in script | ✅ |
| 20 | Chain ID guard in script (reverts on wrong chain) | ✅ |

---

## Root Cause Analysis

The nonce drift occurred because during the PW-C16 sprint (chain launch verification), the deployer key was used to send block-production trigger transactions and a chain diagnostic transaction. At the time of the PW-C15 key ceremony, the genesis `rewardAddress` was computed with the assumption that no transactions would be sent from the deployer before the contract deployment. That assumption was violated.

**Nonce history:**
- Nonce 0: Block 1 kick transaction (PW-C16 chain launch)
- Nonce 1: Diagnostic TX 1 (PW-C16)
- Nonce 2: Diagnostic TX 2 (PW-C16)
- Nonce 3: Diagnostic TX 3 (PW-C16)
- Nonce 4: Final diagnostic TX (PW-C16 integrity check)
- **Nonce 5: Next available (current)**

---

## Recommended Resolution Options

The operator must choose one of the following before proceeding. None of these are within the scope of this automated deployment — they require explicit human decision and authorization.

### Option A: Accept Broken Fee Routing (Testnet-Only Compromise)
- Deploy contracts as-is with the understanding that FeeDistributor at `0x8C41F8A20C63f174C27B9dc9A610615c36c801Ca` will never receive block fees
- The DevTreasury, ValidatorFeeVault reward routing via FeeDistributor will not function
- The contracts themselves (EmergencyMultisig, Timelock, RewardVault, ValidatorRegistry) are fully functional
- RewardVault with 15M PW funds validator staking rewards correctly (independent of FeeDistributor)
- **Appropriate for**: A testnet where fee routing is being tested but not critical for all features
- **Not appropriate for**: Any test that validates the 70/20/10 fee split

### Option B: Recreate the Testnet Chain (Full Fix)
- Requires recreating the blockchain with genesis `rewardAddress` set to the correct FeeDistributor address
- The correct address with deployer nonce 0 is `0x27B15970700daC632f0814522118A1c3B200d971` (original plan) — this works if you use a fresh deployer or reset the chain
- **This is prohibited by the current prompt's instructions** ("DO NOT recreate the blockchain")
- Requires explicit operator authorization

### Option C: Fund a Forwarder at the Genesis Address (Infeasible)
- There is no practical way to deploy a contract at `0x27B15970700daC632f0814522118A1c3B200d971` that routes fees to the actual FeeDistributor — you cannot SET the nonce of the deployer backwards
- Infeasible without chain modification

### Option D: Update Genesis and Recreate (Cleanest Fix)
- Update `config/testnet/genesis.json` `rewardManagerConfig.rewardAddress` to `0x8C41F8A20C63f174C27B9dc9A610615c36c801Ca` (the actual FD address with deployer nonce 5)
- Update `local-data/testnet-key-addresses.env` `TESTNET_FEE_DISTRIBUTOR_PREDICTED`
- Recreate the blockchain (loses current chain state — 4 blocks)
- **Requires operator authorization** and changes the Blockchain ID

---

## Dry-Run Contract Wiring Preview (Reference Only — Not Executed)

If Option A is chosen and deployment proceeds despite the fee-routing issue, the expected wiring would be:

```
FeeDistributor (0x8C41F8A20C63f174C27B9dc9A610615c36c801Ca)
  ↓ validatorFeeVault → ValidatorFeeVault (0x0Dcb2A6718f012Faf373481C99c78513D06db49C)
  ↓ treasury          → DevTreasury       (0x8377408FD17bD4d9245089daDC9d80De60276c33)
  ↓ pauseController   → EmergencyMultisig (0x14c47a0D544684FC0189Bce13220B38523Fff9da)
  BURN_ADDRESS        → 0x000...dEaD

ValidatorFeeVault (0x0Dcb2A6718f012Faf373481C99c78513D06db49C)
  ↓ protocolAdmin     → Registry          (0x261C6FDF5e77ab6b2A0e97A10dB62B72E665f043)
  NOTE: FeeVault receives from FD; FD receives from genesis rewardAddress (MISMATCH)

PrimeWaveValidatorRegistry (0x261C6FDF5e77ab6b2A0e97A10dB62B72E665f043)
  ↓ protocolAdmin     → Deployer          (0xB518397E3D65a0E7475635F01C225E9426a76F11)
  ↓ validatorManager  → POA_MANAGER       (0x0Feedc0de0000000000000000000000000000000)
  ↓ feeVault          → ValidatorFeeVault (0x0Dcb2A6718f012Faf373481C99c78513D06db49C)

RewardVault (0x61c71f1F6EB604b6282e4b97Db5148c5daCD7884)
  ↓ admin             → Deployer          (0xB518397E3D65a0E7475635F01C225E9426a76F11)
  ↓ pauseController   → EmergencyMultisig (0x14c47a0D544684FC0189Bce13220B38523Fff9da)
  ↓ totalFunded       → 15,000,000 PW

DevTreasury (0x8377408FD17bD4d9245089daDC9d80De60276c33)
  ↓ feeDistributor    → FeeDistributor    (0x8C41F8A20C63f174C27B9dc9A610615c36c801Ca)

PrimeWaveTimelock (0x469B3d8B88006ea5b9eeC9c7c6aD650FB929C7e4)
  ↓ proposer          → Deployer          (0xB518397E3D65a0E7475635F01C225E9426a76F11)
  ↓ MIN_DELAY         → 172,800s (48 hours)

GENESIS rewardAddress: 0x27B15970700daC632f0814522118A1c3B200d971 (NO CODE — BROKEN FEE ROUTING)
```

---

## Exact Next Recommended Step

**Await operator decision** on the resolution option.

The question to answer before proceeding:

> **Is it acceptable for this testnet to have broken fee routing** (FeeDistributor never receives block fees; 70/20/10 split never fires; only RewardVault staking rewards work), **OR** must fee routing be functional, in which case the chain must be recreated?

If **Option A (proceed with broken fee routing)**:
- Authorize deployment with the understanding that the FeeDistributor will exist at `0x8C41F8A20C63f174C27B9dc9A610615c36c801Ca` and will never be funded by block fees on this chain
- Re-issue the deployment prompt with explicit authorization

If **Option B/D (fix and recreate)**:
- Update `config/testnet/genesis.json` → `rewardManagerConfig.rewardAddress` → `0x8C41F8A20C63f174C27B9dc9A610615c36c801Ca`
- Update `local-data/testnet-key-addresses.env` → `TESTNET_FEE_DISTRIBUTOR_PREDICTED` → `0x8C41F8A20C63f174C27B9dc9A610615c36c801Ca`
- Execute chain recreation (requires validator operator access)
- Re-run this deployment prompt

---

*Report generated by automated pre-deployment audit. No transactions were broadcast. No contracts were deployed.*
