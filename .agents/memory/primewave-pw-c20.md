---
name: PrimeWave Chain PW-C20
description: End-to-end functional test; distribute() confirmed live; key test wallet addresses; pitfalls
---

## Result
C20 COMPLETE. GREEN verdict. All release-blocker categories passed. One YELLOW: RewardVault dynamic claim deferred (no recipients until StakingManager deployed).

## Key Findings
- FeeDistributor.distribute() is permissionless and works. Call it any time fees accumulate.
- BURN_ADDRESS = 0x000...dEaD. After distribute(): dead address balance confirmed = burn share. ✅
- FD residual after distribute() = the gas fee from the distribute() TX itself (credited to FD as rewardAddress during same block). This is spec-correct, not a bug.
- Block 2 `miner` field = FeeDistributor address — confirms RewardManager routing active from genesis.
- PoAManager at 0x0Feedc0de... returns empty code via eth_getCode (expected — it's a native precompile).
- `scripts/start-indexer.sh` exports DEV_PRIVATE_KEY_0 (Hardhat default dev key, public, no testnet value). Low severity; move to .env.local for hygiene.

## Test Wallets Used (Ephemeral, Abandoned)
- W1 (sender): 0xe1d067E5D84b0fAA8567E79D7F53663030D4197C (~1.5 PW residual)
- W2 (recipient): 0x340313861881AE0d6f0652FC0d53927DdD36E3E7 (~0.5 PW residual)
- Unauth: 0x0Ef7532f8B4BaEBE7586a40f2962c1131F815A70 (~0.05 PW residual)

## Pitfall: cast call decimal vs hex parsing
When cast call returns a decoded decimal (e.g. "7000"), piping to `python3 -c "int('$VAL', 16)"` misreads it as hex (7000 hex = 28672). Use `int('$VAL')` for decoded values, or `int('$RAW_HEX', 16)` for raw 0x-prefixed hex.

## Deferred
- RewardVault claim/accrual: needs at least 1 registered validator (StakingManager not yet deployed)
- Validator registration flow: next phase after StakingManager deployment
