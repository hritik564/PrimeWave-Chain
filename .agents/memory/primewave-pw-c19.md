---
name: PrimeWave Chain PW-C19
description: Testnet contract deployment; all 7 contracts live; deployed addresses; wiring notes
---

## Result
C19 COMPLETE. All 7 PrimeWave protocol contracts deployed to testnet (Chain ID 77) via `DeployTestnet.s.sol`. Verdict: GREEN.

## Deployed Addresses (Testnet, Chain ID 77)
```
ADDR_EMERGENCY_MULTISIG=0x59a419F3160fa9B4b6aE98b18C2ABA3d5aBb81Fa
ADDR_TIMELOCK=0x7D50dBEb0d38Fe2E3AcdaBF70Fa99228E3Ec6AEE
ADDR_VALIDATOR_FEE_VAULT=0x8008e22DB31e787b98dfC891E1076747D17A3EE8
ADDR_DEV_TREASURY=0x7Edc50F7cD417d0ac94f3c17E5D57EE4eaa23B89
ADDR_FEE_DISTRIBUTOR=0x27B15970700daC632f0814522118A1c3B200d971
ADDR_VALIDATOR_REGISTRY=0x14c47a0D544684FC0189Bce13220B38523Fff9da
ADDR_REWARD_VAULT=0x469B3d8B88006ea5b9eeC9c7c6aD650FB929C7e4
```
Also in `local-data/testnet-deployed-contracts.env`.

## Key Facts
- FeeDistributor at 0x27B159...d971 = genesis rewardAddress — fee routing active from block 0
- ValidatorFeeVault.protocolAdmin() = ValidatorRegistry (by design — registry is FV admin, not deployer)
- RewardVault funded with 15,000,000 PW; emissionRatePerSecond = MAX_RATE_PER_SECOND (95129375951293759 wei/s)
- Deployer nonce post-deploy = 9; block post-deploy = 2
- EMS: 5 signers confirmed, THRESHOLD = 3
- Total PW supply confirmed 100,000,000 PW

## Pitfall
`cast call <addr> "fn()(type)" --rpc-url ...` — when return type is specified, cast returns decimal string.
If you then pipe to `python3 -c "print(int('$VAL',16))"`, it interprets the decimal string as hex (e.g. "7000" → 28672). Use `int('$VAL')` or just print `$VAL` directly.
Also: EMS threshold is a constant (`THRESHOLD()`), not a `threshold()` getter.
RewardVault rate getter is `emissionRatePerSecond()`, not `rewardRate()`.
BURN_ADDRESS = `0x000000000000000000000000000000000000dEaD` (standard dead address, confirmed on-chain).

## Test Suite (unchanged)
Forge: 792/792 | Indexer Jest: 57/57 | Keeper Jest: 20/20
