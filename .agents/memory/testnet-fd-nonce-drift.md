---
name: Testnet FeeDistributor Nonce Drift
description: Deployer nonce drifted to 5 during C16 chain-launch (was 0 at key ceremony); genesis rewardAddress predicted at nonce 4 no longer matches actual FeeDistributor address; fee routing is broken on the live testnet chain.
---

## Rule
Any time the deployer's current nonce ≠ 0 at contract deployment time, the FeeDistributor will NOT land at the address baked into `config/testnet/genesis.json` `rewardManagerConfig.rewardAddress`.

**Why:** Ethereum CREATE address = `keccak256(RLP([deployer, nonce]))[12:]`. The genesis key ceremony predicted the FD address assuming deployer nonce=0 (FD is nonce+4). Block-production and diagnostic TXs during C16 used nonces 0–4 before any contract was deployed, leaving nonce=5 at the time of the first deployment attempt.

**How to apply:** Before any testnet contract deployment, always confirm `eth_getTransactionCount(deployer, "latest")` == 0, OR recompute the genesis `rewardAddress` from the actual nonce at the time of deployment. If nonce > 0, update genesis and recreate the chain first.

## Concrete values (2026-08-17)

| Item | Value |
|---|---|
| Genesis rewardAddress | `0x27B15970700daC632f0814522118A1c3B200d971` |
| Based on deployer nonce | 4 (assumes start_nonce=0) |
| Actual current deployer nonce | **5** |
| Actual FeeDistributor nonce | 9 (5+4) |
| Actual FeeDistributor address | **`0x8C41F8A20C63f174C27B9dc9A610615c36c801Ca`** |
| Genesis rewardManagerConfig admins | None — reward address is permanently locked |
| Fix without chain recreation | **Impossible** (no RewardManager admin) |

## Projected addresses at start_nonce=5 (for reference if Option A chosen)

| Nonce | Contract | Address |
|---|---|---|
| 5 | EmergencyMultisig | `0x14c47a0D544684FC0189Bce13220B38523Fff9da` |
| 6 | PrimeWaveTimelock | `0x469B3d8B88006ea5b9eeC9c7c6aD650FB929C7e4` |
| 7 | ValidatorFeeVault | `0x0Dcb2A6718f012Faf373481C99c78513D06db49C` |
| 8 | DevTreasury | `0x8377408FD17bD4d9245089daDC9d80De60276c33` |
| 9 | FeeDistributor | `0x8C41F8A20C63f174C27B9dc9A610615c36c801Ca` |
| 10 | PrimeWaveValidatorRegistry | `0x261C6FDF5e77ab6b2A0e97A10dB62B72E665f043` |
| 11 | RewardVault | `0x61c71f1F6EB604b6282e4b97Db5148c5daCD7884` |

## Resolution options presented to operator

- **Option A**: Deploy as-is; fee routing broken for this chain; only RewardVault staking rewards work
- **Option B/D**: Update genesis `rewardAddress` → `0x8C41F8A20C63f174C27B9dc9A610615c36c801Ca`; recreate chain; then redeploy
