# PW-C19 — Testnet Contract Deployment Report

**Sprint:** PW-C19  
**Date:** 2026-08-17  
**Chain:** PrimeWave Testnet (Chain ID 77)  
**Blockchain ID:** `22iFuL8GqPYbtnPKNFrq7AzoDfv3FYwq8T93GubRi12LQVjLni`  
**Verdict:** 🟢 **GREEN**

---

## 1. Secret / Address Verification

| Item | Value | Result |
|---|---|---|
| Secret used | `TESTNET_DEPLOYER_KEY` | ✅ |
| Derived address | `0xB518397E3D65a0E7475635F01C225E9426a76F11` | ✅ |
| Expected address | `0xB518397E3D65a0E7475635F01C225E9426a76F11` | ✅ MATCH |

Key derivation confirmed before any transaction. No key value printed, echoed, or committed.

---

## 2. Chain Verification (Pre-Deployment)

| Check | Value | Result |
|---|---|---|
| `eth_chainId` | 77 (0x4d) | ✅ |
| Blockchain ID | `22iFuL8GqPYbtnPKNFrq7AzoDfv3FYwq8T93GubRi12LQVjLni` | ✅ |
| Block number | 0 (genesis) | ✅ |
| Deployer nonce (latest) | 0 | ✅ |
| Deployer nonce (pending) | 0 | ✅ |
| V6 (152.53.66.93) healthy | true | ✅ |
| V7 (152.53.66.201) healthy | true | ✅ |
| V8 (159.195.44.104) healthy | true | ✅ |
| V9 (159.195.47.126) healthy | true | ✅ |
| Connected Fuji peers | 58 | ✅ |

No diagnostic or test transactions were sent before deployment. Deployer nonce was 0 at broadcast start.

---

## 3. Deployer AVAX Balance

This is a PrimeWave subnet. The native gas token is **PW** (not AVAX). The deployer holds no Fuji C-Chain AVAX — gas is paid in PW from the genesis allocation.

| Token | Balance | Source |
|---|---|---|
| AVAX (Fuji C-Chain) | N/A — not applicable | — |
| PW (native subnet token) | 16,000,000.000 PW | Genesis alloc |

---

## 4. Deployer PW Balance

Genesis allocation: **16,000,000 PW** to `0xB518397E3D65a0E7475635F01C225E9426a76F11`.

Post-deployment balance: **~999,999.83 PW**  
(16,000,000 − 15,000,000 funded to RewardVault − ~0.17 PW gas for 9 transactions)

---

## 5. Nonce Verification

| Check | Value | Result |
|---|---|---|
| Nonce at broadcast start | 0 | ✅ |
| Nonce-zero guard in script | `require(vm.getNonce(deployer) == 0, ...)` | ✅ PASSED |
| Nonce after deployment | 9 (7 CREATE + 2 CALL) | ✅ |

---

## 6. FeeDistributor Address Prediction

| Item | Value |
|---|---|
| Deployer | `0xB518397E3D65a0E7475635F01C225E9426a76F11` |
| Nonce at FeeDistributor deploy | 4 (after EMS + Timelock + FeeVault + DevTreasury) |
| Predicted address | `0x27B15970700daC632f0814522118A1c3B200d971` |
| Computed via | `cast compute-address <deployer> --nonce 4` |

---

## 7. Genesis `rewardManagerConfig.rewardAddress`

```json
"rewardManagerConfig": {
  "blockTimestamp": 0,
  "initialRewardConfig": {
    "rewardAddress": "0x27B15970700daC632f0814522118A1c3B200d971"
  }
}
```

---

## 8. FeeDistributor Address Match

| Item | Address |
|---|---|
| Predicted (nonce 4) | `0x27B15970700daC632f0814522118A1c3B200d971` |
| Genesis rewardAddress | `0x27B15970700daC632f0814522118A1c3B200d971` |
| Actual deployed | `0x27B15970700daC632f0814522118A1c3B200d971` |
| Match | ✅ **EXACT MATCH** |

The native RewardManager precompile will route all block reward fees to FeeDistributor from genesis block 0 onward.

---

## 9. Forge Build

```
forge build --via-ir
No files changed, compilation skipped
```

Clean build. Only lint warnings on test files (unsafe-typecast in fuzz tests — not production code). Zero compilation errors.

---

## 10. Simulation

```
forge script DeployTestnet.s.sol --rpc-url $RPC --private-key $KEY --via-ir -vvv
Script ran successfully.
SIMULATION COMPLETE.
Estimated gas: 8,578,280 units (~0.429 PW at 50 gwei)
```

All guards passed in simulation:
- Chain ID == 77 ✅
- Deployer != dev key ✅
- Nonce == 0 ✅
- EMS signers all non-zero ✅
- FeeDistributor address prediction match ✅
- ValidatorRegistry address prediction match ✅
- Balance >= 15,001 PW ✅

EIP-3855 warning is cosmetic: Foundry does not recognize chain ID 77, but subnet-evm v1.15.0 (Durango) supports PUSH0. Simulation confirmed successful execution.

---

## 11. Deployment Transactions

All 9 transactions confirmed on-chain, all status = 1 (success).

| Nonce | Contract / Action | TX Hash | Block | Gas Used | Status |
|---|---|---|---|---|---|
| 0 | EmergencyMultisig (CREATE) | `0xb9e3443f3f33fe13de3659e71f6ff39a15681d6f3c1cdd42b6a8ed0dce540042` | 1 | 940,552 | ✅ |
| 1 | PrimeWaveTimelock (CREATE) | `0x3d5c72c4a7824bf7eb92dd17c119853df740e742a2b57608c075e2da1c799f15` | 2 | 685,251 | ✅ |
| 2 | ValidatorFeeVault (CREATE) | `0xa6255887052b0cb1af2955d56d3057cce8ef0ac5e2a9b6a933216c89b8d49f88` | 2 | 1,421,557 | ✅ |
| 3 | DevTreasury (CREATE) | `0xb6dd34625540b160f087ca2a1186d766d8080ec879d6157a7d67a11133c1deae` | 2 | 131,051 | ✅ |
| 4 | FeeDistributor (CREATE) | `0x05c77fbe956f2dbbc2f2fb94ae276fa02f7a47273b8a56848aaf4c57fb7cb7b7` | 2 | 656,475 | ✅ |
| 5 | ValidatorRegistry (CREATE) | `0xc7f2c846cdc5ce704386e9e8d41f2cc1308f519b2f25155618ea97011b79de5d` | 2 | 1,070,292 | ✅ |
| 6 | RewardVault (CREATE) | `0xd4db38711197e61d7f4d8c832589a6700a7a22c6cd83ec141e7090cfd595933b` | 2 | 1,616,712 | ✅ |
| 7 | RewardVault.setPauseController(EMS) (CALL) | `0x618b02a6450ed3363a459b96b7643aa2ff84c53b4781e77d81a83a359dfb9d86` | 2 | 45,455 | ✅ |
| 8 | RewardVault.fund{15M PW}() (CALL) | `0xab7d0b867c86a98d148e705631b1ad5050dc12722c7bb21a44a090fa901454f1` | 2 | 45,549 | ✅ |

Total gas: ~6,612,894 units

---

## 12. Deployed Contract Addresses

```
ADDR_EMERGENCY_MULTISIG=0x59a419F3160fa9B4b6aE98b18C2ABA3d5aBb81Fa
ADDR_TIMELOCK=0x7D50dBEb0d38Fe2E3AcdaBF70Fa99228E3Ec6AEE
ADDR_VALIDATOR_FEE_VAULT=0x8008e22DB31e787b98dfC891E1076747D17A3EE8
ADDR_DEV_TREASURY=0x7Edc50F7cD417d0ac94f3c17E5D57EE4eaa23B89
ADDR_FEE_DISTRIBUTOR=0x27B15970700daC632f0814522118A1c3B200d971
ADDR_VALIDATOR_REGISTRY=0x14c47a0D544684FC0189Bce13220B38523Fff9da
ADDR_REWARD_VAULT=0x469B3d8B88006ea5b9eeC9c7c6aD650FB929C7e4
```

Written to `local-data/testnet-deployed-contracts.env`.

---

## 13. Bytecode Verification

All 7 contracts confirmed to have non-empty bytecode at their deployed addresses.

| Contract | Address | Bytecode Size | Result |
|---|---|---|---|
| EmergencyMultisig | `0x59a419F3160fa9B4b6aE98b18C2ABA3d5aBb81Fa` | 7,056 chars | ✅ |
| PrimeWaveTimelock | `0x7D50dBEb0d38Fe2E3AcdaBF70Fa99228E3Ec6AEE` | 5,618 chars | ✅ |
| ValidatorFeeVault | `0x8008e22DB31e787b98dfC891E1076747D17A3EE8` | 12,448 chars | ✅ |
| DevTreasury | `0x7Edc50F7cD417d0ac94f3c17E5D57EE4eaa23B89` | 694 chars | ✅ |
| FeeDistributor | `0x27B15970700daC632f0814522118A1c3B200d971` | 5,320 chars | ✅ |
| ValidatorRegistry | `0x14c47a0D544684FC0189Bce13220B38523Fff9da` | 9,344 chars | ✅ |
| RewardVault | `0x469B3d8B88006ea5b9eeC9c7c6aD650FB929C7e4` | 13,832 chars | ✅ |

---

## 14. Ownership / Admin Verification

| Contract | Getter | Value | Expected | Result |
|---|---|---|---|---|
| ValidatorRegistry | `protocolAdmin()` | `0xB518397E3D65a0E7475635F01C225E9426a76F11` | Deployer | ✅ |
| RewardVault | `admin()` | `0xB518397E3D65a0E7475635F01C225E9426a76F11` | Deployer | ✅ |
| PrimeWaveTimelock | `proposer()` | `0xB518397E3D65a0E7475635F01C225E9426a76F11` | Deployer | ✅ |
| ValidatorFeeVault | `protocolAdmin()` | `0x14c47a0D544684FC0189Bce13220B38523Fff9da` | ValidatorRegistry | ✅ (by design) |
| EmergencyMultisig | `THRESHOLD()` | 3 | 3 | ✅ |

**Note on ValidatorFeeVault.protocolAdmin():** The deployment script constructs `ValidatorFeeVault` with `predictedRegistry` (the ValidatorRegistry address) as its admin, not the deployer. This is intentional by design: the registry manages validator registration and is the entity entitled to pull fee distributions. This matches `DeployTestnet.s.sol` line `new ValidatorFeeVault(predictedRegistry)`.

---

## 15. Contract Wiring Verification

All wiring read directly from on-chain state — not inferred from deployment-script intent.

| Contract | Getter | Got | Expected | Result |
|---|---|---|---|---|
| FeeDistributor | `validatorFeeVault()` | `0x8008e22DB31e787b98dfC891E1076747D17A3EE8` | ValidatorFeeVault | ✅ |
| FeeDistributor | `treasury()` | `0x7Edc50F7cD417d0ac94f3c17E5D57EE4eaa23B89` | DevTreasury | ✅ |
| FeeDistributor | `pauseController()` | `0x59a419F3160fa9B4b6aE98b18C2ABA3d5aBb81Fa` | EMS | ✅ |
| DevTreasury | `feeDistributor()` | `0x27B15970700daC632f0814522118A1c3B200d971` | FeeDistributor | ✅ |
| ValidatorRegistry | `validatorManager()` | `0x0Feedc0de0000000000000000000000000000000` | PoAManager predeploy | ✅ |
| ValidatorRegistry | `feeVault()` | `0x8008e22DB31e787b98dfC891E1076747D17A3EE8` | ValidatorFeeVault | ✅ |
| RewardVault | `pauseController()` | `0x59a419F3160fa9B4b6aE98b18C2ABA3d5aBb81Fa` | EMS | ✅ |
| RewardVault | `totalFunded()` | 15,000,000 PW | 15,000,000 PW | ✅ |
| RewardVault | `emissionRatePerSecond()` | 95,129,375,951,293,759 wei/s | MAX_RATE_PER_SECOND | ✅ |
| RewardVault | `paused()` | false | false | ✅ |
| EMS | `signers(0)` | `0xb24F3FAF5B9ab7aFb625F105C791d5231b094853` | testnet-ems-signer-1 | ✅ |
| EMS | `signers(1)` | `0x508367082eF7A3A8567fa10D92c98524EE2F3d30` | testnet-ems-signer-2 | ✅ |
| EMS | `signers(2)` | `0xFa21258c9e5faa7aECbFD13f635863C5da0b8EC3` | testnet-ems-signer-3 | ✅ |
| EMS | `signers(3)` | `0xB1346A22773B853552aF028b767bD6cC0171006a` | testnet-ems-signer-4 | ✅ |
| EMS | `signers(4)` | `0x2D2d07AB95636Da735BAcBDC018420ca621C3448` | testnet-ems-signer-5 | ✅ |
| EMS | `THRESHOLD()` | 3 | 3 | ✅ |

---

## 16. Genesis Allocation Verification

PW total supply = **100,000,000 PW** (confirmed: genesis alloc sum = 100,000,000 PW).

| Address | Genesis Alloc | On-Chain Balance | Match |
|---|---|---|---|
| `0x1F471d2Dc7CB8b2C773aFeD40d4bD467ed1FdaD8` | 25,000,000 PW | 25,000,000 PW | ✅ |
| `0x46a419514f52A4763596F75A9169B0Bd0153C673` | 20,000,000 PW | 20,000,000 PW | ✅ |
| `0xA6744C599A0d40082aAF03Bd643cfc30B2B16a0c` | 20,000,000 PW | 20,000,000 PW | ✅ |
| `0xB518397E3D65a0E7475635F01C225E9426a76F11` (deployer) | 16,000,000 PW | ~999,999.83 PW | ✅ (15M to RV + gas) |
| `0x2c5E541f667768dd1986C73530Dc29250fA86B7B` | 10,000,000 PW | 10,000,000 PW | ✅ |
| `0x3C98105b99bb9dc97B341D11ec264F5127A7221C` | 9,000,000 PW | 9,000,000 PW | ✅ |
| `0x469B3d8B88006ea5b9eeC9c7c6aD650FB929C7e4` (RewardVault) | — | 15,000,000 PW | ✅ (funded by deployer) |

Total circulating PW (all accounts): 100,000,000 PW ✅

**Note:** The genesis alloc labels (treasury, team, community, ecosystem, reserve) are identified by address only. The exact label-to-address mapping is in the key ceremony documentation.

---

## 17. Smoke Test Results

| Test | Result |
|---|---|
| All 7 contract bytecodes readable | ✅ |
| All wiring getters return expected values | ✅ |
| PW balances readable (all genesis alloc addresses) | ✅ |
| RewardVault balance = 15,000,000 PW (on-chain read) | ✅ |
| Deployer nonce post-deploy = 9 | ✅ |
| Block number post-deploy = 2 | ✅ |
| All 9 TX receipts status = 1 | ✅ |
| No unrelated transactions sent | ✅ |

---

## 18. Warnings

| # | Severity | Description |
|---|---|---|
| W-01 | LOW | EIP-3855 (PUSH0) Foundry warning on chain ID 77. Cosmetic only — subnet-evm v1.15.0 (Durango) supports PUSH0. Contracts deployed and executed correctly. |
| W-02 | INFO | ValidatorFeeVault.protocolAdmin() = ValidatorRegistry (not deployer). This is correct by design — the registry is constructed as the fee vault admin to enable per-validator fee distribution. |
| W-03 | INFO | Deployer private key is held only in Replit Secret `TESTNET_DEPLOYER_KEY`. It must be backed up securely by the operator before the next key rotation or session expiry. |

---

## 19. Final Verdict

🟢 **GREEN**

| Criterion | Status |
|---|---|
| Deployer address correct (`0xB518397...76F11`) | ✅ |
| Nonce started at 0 | ✅ |
| FeeDistributor deployed at `0x27B15970700daC632f0814522118A1c3B200d971` | ✅ |
| All 7 expected contracts deployed | ✅ |
| All expected bytecode present | ✅ |
| Ownership correct | ✅ |
| Wiring correct (all on-chain getters verified) | ✅ |
| No old/abandoned addresses | ✅ |
| No critical warnings | ✅ |
| Smoke tests pass | ✅ |

---

*STOP — per PW-C19 protocol spec, no further work beyond this report.*  
*Do NOT proceed to PWCScan, PWSwap, RPC domain configuration, or public launch work.*
