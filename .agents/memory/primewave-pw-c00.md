---
name: PrimeWave Chain PW-C00
description: Full architecture and research sprint for PrimeWave Chain — a fixed-supply sovereign Avalanche L1. Gate passed; 20 docs complete; awaiting PW-C01 approval.
---

## Rule
Never mint PW. Never use `ava-labs/icm-contracts` or `ava-labs/subnet-evm` (both archived). Do not begin PW-C01 without explicit approval.

## Key architecture decisions (all locked)
- 100M PW fixed supply — NativeMinter NOT activated
- Phase 1: PoAManager (from icm-services tag icm-relayer-v1.7.5)
- Phase 2: PrimeWaveStakingManager extends StakingManager, overrides _reward() only → draws from RewardVault (no mint)
- 15M PW RewardVault (genesis pre-funded) — max 3M PW/year emissions (~8,219.18 PW/day)
- Separate ValidatorFeeVault (70% of gas fees) — completely separate from RewardVault
- 70/20/10 gas split: ValidatorFeeVault / Treasury / Burn
- 14-day unbonding (Phase 2)
- 3-of-5 Emergency Multisig — pause/freeze ONLY; cannot transfer funds or upgrade
- 48-hour TimelockController for all governance/treasury changes
- Single PWUSD Monetary Authority (NOT multisig unless instructed) — PLACEHOLDER address
- No presale vesting (previously approved)
- No V1 bridge, no BEP-20 bridge

## Critical invariant
RewardVault.balance() + totalDistributed == 15_000_000e18 at all times.
totalPW == 100_000_000e18 always.

## Document corpus (docs/)
20 markdown files — see PW-C00-FINAL-GATE.md for full list.

## PW-C01 blockers remaining
- Pin Foundry commit in CI
- Source review of StakingManager.sol at commit 40e1c89 (OQ-019 full)
- Legal review of LicenseRef-Ecosystem on icm-services (pre-mainnet)
- Team allocation vesting decision (OQ-023 — does not block Phase 1)

**Why:** All other blocking OQs (001-006, 011, 013, 015-018) resolved. Gate passed Aug 13, 2026.
