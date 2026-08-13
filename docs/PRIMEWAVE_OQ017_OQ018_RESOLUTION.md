# PrimeWave Chain — OQ-017 & OQ-018 Resolution
**Supplemental Decision Record | August 13, 2026**
**Status: LOCKED — DO NOT BEGIN PW-C01 WITHOUT PROJECT OWNER APPROVAL**

---

## OQ-017 — RewardVault Emission Rate (RESOLVED)

### Decision

**Maximum annual staking emissions: 3,000,000 PW**

### Emission Parameters (Locked)

| Parameter | Value |
|---|---|
| Maximum annual emission | 3,000,000 PW |
| Daily maximum | ≈ 8,219.18 PW/day (3,000,000 ÷ 365) |
| Per-second maximum | ≈ 0.09513 PW/second |
| Per-block maximum (2s blocks) | ≈ 0.19027 PW/block |
| Vault starting balance | 15,000,000 PW |
| Minimum vault duration | **5 years** (at sustained maximum emissions and 100% validator eligibility) |
| Emissions model | Linear — fixed annual maximum cap |
| Unused emissions | Remain in RewardVault. Not burned, not redistributed. |
| Rate adjustability | Governance may only **reduce** (never increase) the cap |
| Maximum cap ceiling | 3,000,000 PW/year (hardcoded; requires protocol upgrade to raise) |

### Derivation

```
ANNUAL_CAP    = 3,000,000 PW
DAILY_MAX     = 3,000,000 / 365         = 8,219.178082... ≈ 8,219.18 PW/day
VAULT_LIFE    = 15,000,000 / 3,000,000  = 5.000 years (minimum; extends when unused)
```

At 2-second block time (43,200 blocks/day):
```
PER_BLOCK_MAX = 8,219.178082 / 43,200   ≈ 0.19027 PW/block
```

In wei (for Solidity implementation):
```solidity
uint256 constant MAX_ANNUAL_EMISSION_WEI = 3_000_000e18;
uint256 constant SECONDS_PER_YEAR = 31_536_000; // 365 * 86_400

// Per-epoch emission cap (computed dynamically from epoch duration):
uint256 maxEpochEmission = MAX_ANNUAL_EMISSION_WEI * epochDurationSeconds / SECONDS_PER_YEAR;

// Actual emission (respects vault balance):
uint256 epochEmission = Math.min(maxEpochEmission, rewardVault.balance());
```

### Unused Emissions Rule

If, in a given epoch, total eligible validator weight × uptime results in fewer PW actually claimable than the epoch cap, the difference remains in the vault. The vault balance decreases only by the amount actually distributed. This means:
- Vault life extends past 5 years in any period with less-than-maximum eligible distribution
- 5 years is a guaranteed minimum, not a ceiling

### Economic Implications

At 15 validators (Phase 1, equal weight, fully eligible):
```
Max per-validator per year = 3,000,000 / 15 = 200,000 PW/year
Max per-validator per day  = 200,000 / 365  ≈ 547.95 PW/day
```

At Phase 2 (PoS, variable stake weights), per-validator earnings are proportional to stake fraction of total weight.

### Documents Updated for OQ-017

- `PRIMEWAVE_REWARD_ECONOMICS.md` — Section 2.5 rewritten with locked emission parameters
- `PRIMEWAVE_TOKENOMICS.md` — Emission rate added to tokenomics summary
- `PRIMEWAVE_VALIDATOR_SPEC.md` — Reward schedule reference updated
- `PRIMEWAVE_OPEN_QUESTIONS.md` — OQ-017 marked resolved

---

## OQ-018 — icm-services Release Tag / Version Pin (RESOLVED)

### Decision

**Pin `ava-labs/icm-services` to tag `icm-relayer-v1.7.5`, commit `40e1c89`.**

### Research Findings

| Finding | Detail |
|---|---|
| Latest stable release tag | `icm-relayer-v1.7.5` |
| Tag commit | `40e1c89` |
| Release date | January 26, 2026 |
| AvalancheGo compatibility | v1.14.0 (Granite) — explicitly backwards-compatible to v1.14.2 (Granite.2, March 30 2026) per AvalancheGo release notes |
| Solidity version | 0.8.30 |
| EVM target | Shanghai |
| Contract path within repo | `icm-contracts/` subdirectory |
| icm-services dependency status | Active; Dependabot last updated April 17, 2026 |
| AvalancheGo v1.14.2 backwards-compatibility | ✅ Confirmed — "backwards compatible to v1.14.0" per Granite.2 release notes |

### Why This Tag

1. It is the latest stable, tagged release of icm-services (as of research date Aug 13, 2026)
2. The Solidity contracts within `icm-services/icm-contracts/` do not carry their own separate version tags; they travel with the repository at the tagged commit
3. Using a tagged commit (not `main`) gives a reproducible reference for security audits, Foundry builds, and version control
4. AvalancheGo v1.14.2 is backwards compatible to v1.14.0 (Granite), which is the version the contracts were designed against — no breaking protocol changes affect the validator manager contract interfaces

### How to Use in Development (Instructions for PW-C01)

```bash
# Reference the contracts in Foundry (foundry.toml):
[dependencies]
icm-services = { git = "https://github.com/ava-labs/icm-services", tag = "icm-relayer-v1.7.5" }

# OR clone and checkout the specific commit:
git clone https://github.com/ava-labs/icm-services.git
cd icm-services
git checkout 40e1c89

# The contracts to import are under:
# icm-services/icm-contracts/contracts/validator-manager/
#   PoAManager.sol
#   ValidatorManager.sol
#   StakingManager.sol (abstract — used for Phase 2 extension point)
#   PoSValidatorManager.sol / NativeTokenStakingManager.sol (do NOT use directly — mints)
```

### Version Lock Table (Complete Registry)

| Dependency | Repository | Pinned Version | Commit / Tag |
|---|---|---|---|
| Validator Manager contracts | `ava-labs/icm-services` | `icm-relayer-v1.7.5` | `40e1c89` |
| AvalancheGo | `ava-labs/avalanchego` | `v1.14.2` | Lock at testnet initiation |
| Subnet-EVM | `ava-labs/subnet-evm` | TBD | Lock at testnet initiation |
| Avalanche CLI | `ava-labs/avalanche-cli` | TBD | Lock at testnet initiation |
| OpenZeppelin Contracts | `OpenZeppelin/openzeppelin-contracts` | `v5.x` (pin exact at dev start) | Pin at dev start |
| OpenZeppelin Upgradeable | `OpenZeppelin/openzeppelin-contracts-upgradeable` | `v5.x` (pin exact at dev start) | Pin at dev start |
| Foundry | `foundry-rs/foundry` | Pin commit in CI | Pin at dev start |

### Action Required Before PW-C01

- [ ] Confirm `icm-contracts/contracts/validator-manager/StakingManager.sol` at commit `40e1c89` exposes `_reward()` as `internal virtual` (addresses OQ-019)
- [ ] Confirm exact OpenZeppelin v5.x patch version to pin
- [ ] Confirm exact Subnet-EVM version compatible with AvalancheGo v1.14.2

### Documents Updated for OQ-018

- `PRIMEWAVE_CHAIN_ARCHITECTURE.md` — Dependency table updated with pinned commit
- `PRIMEWAVE_INFRASTRUCTURE.md` — Dependency registry table updated with pinned commit
- `PRIMEWAVE_OPEN_QUESTIONS.md` — OQ-018 marked resolved; OQ-019 prerequisite clarified

---

## Updated Prerequisites for PW-C01

With OQ-017 and OQ-018 resolved, the prerequisite list for PW-C01 is:

**Technical (must be researched):**
- [ ] ✅ ~~OQ-018 resolved: icm-services release tag pinned~~ → **DONE: `icm-relayer-v1.7.5` / `40e1c89`**
- [ ] Confirm exact OpenZeppelin v5 patch version to pin
- [ ] Confirm Subnet-EVM version compatible with AvalancheGo v1.14.2
- [ ] Verify `StakingManager._reward()` is `internal virtual` at commit `40e1c89` (partial resolution of OQ-019)
- [ ] `icm-services` license reviewed by PrimeWave legal counsel

**Leadership decisions required:**
- [ ] ✅ ~~OQ-017 resolved: RewardVault emission rate~~ → **DONE: 3,000,000 PW/year max, ~8,219.18 PW/day**
- [ ] OQ-011: Unbonding period (14 or 21 days)
- [ ] OQ-013: Emergency multisig signers and exact powers
- [ ] OQ-015: Team allocation vesting decision
- [ ] OQ-016: Governance timelock durations

**Governance setup (before any contract deployment):**
- [ ] Treasury multisig signers identified and wallets prepared
- [ ] Protocol Admin multisig signers identified and wallets prepared
- [ ] Emergency multisig signers identified and wallets prepared
- [ ] MONETARY_AUTHORITY_ADDRESS security process planned

---

*This document supplements `PW-C00-DECISION-RESOLUTION.md`. No production deployment has occurred.*
