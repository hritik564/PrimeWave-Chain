# PrimeWave Chain — Open Questions
**Sprint PW-C00 Decision Resolution | Updated: August 13, 2026**

---

## RESOLVED QUESTIONS (PW-C00 Decision Resolution)

### ✅ OQ-001 — Avalanche Dependencies (RESOLVED)

**Resolution:** The `ava-labs/icm-contracts` repository (archived December 3, 2025) has a confirmed official successor: **`ava-labs/icm-services`**.

The validator manager contracts now live at `icm-services/icm-contracts/` (same contract code, new home). The official Avalanche documentation at `build.avax.network` now sources from this repository (confirmed via edit URL in docs). The repo is actively maintained — last commit August 10, 2026.

**Confirmed dependency registry:**

| Component | Repository | Notes |
|---|---|---|
| PoAManager, ValidatorManager, StakingManager | `ava-labs/icm-services` (main branch) | Solidity 0.8.30, EVM: shanghai |
| AvalancheGo node | `ava-labs/avalanchego` v1.14.2 | Lock version at testnet initiation |
| Subnet-EVM | `ava-labs/subnet-evm` (latest stable) | Lock version at testnet initiation |
| Avalanche CLI | `ava-labs/avalanche-cli` (latest stable) | Used for L1 creation / bootstrap |
| OpenZeppelin Contracts | `openzeppelin/openzeppelin-contracts` v5.x | Audited; required for ERC-20, AccessControl, TimelockController |
| OpenZeppelin Upgradeable | `openzeppelin/openzeppelin-contracts-upgradeable` v5.x | Required for upgradeable proxy pattern |
| Foundry | `foundry-rs/foundry` | Build, test, deploy tooling |

**Pinning strategy:**
- `icm-services`: Pin to a specific release tag (not `main`). Do not use icm-contracts.
- `avalanchego`: Pin exact version at testnet; verify upgrade path before mainnet.
- `subnet-evm`: Pin exact version at testnet.
- OpenZeppelin: Pin to a specific version tag.
- Foundry: Pin to a specific commit hash in CI.

See `PRIMEWAVE_INFRASTRUCTURE.md` for full dependency registry with versions.

---

### ✅ OQ-002 — Genesis / Bootstrap (RESOLVED)

**Resolution:** Use the **standard Avalanche L1 creation and bootstrap sequence**. No custom genesis mechanism.

High-level sequence (all standard Avalanche tooling):

```
1. L1 Creation
   CreateSubnetTx on P-Chain (via Avalanche CLI)
   → produces subnetID

2. Genesis & Chain Creation
   CreateChainTx on P-Chain with genesis file
   → produces blockchainID (chainID on EVM)
   → Subnet-EVM starts with genesis alloc (100M PW distributed)

3. L1 Conversion (ACP-77)
   ConvertSubnetToL1Tx on P-Chain
   → references PoAManager contract address
   → initial bootstrap validators specified in conversion tx
   → L1 is now sovereign (no AVAX stake requirement)

4. Validator Manager Initialization
   PoAManager.initializeValidatorSet() on EVM
   → sets initial validator registration records
   → Warp confirmations from P-Chain for each initial validator

5. Network Activation
   All 15 validators confirmed and active
   → Block production under Snowman++ BFT
   → RPC endpoints operational
```

**What is standard Avalanche vs. PrimeWave custom:**

| Step | Type |
|---|---|
| CreateSubnetTx | Standard Avalanche |
| CreateChainTx | Standard Avalanche + PrimeWave genesis file |
| ConvertSubnetToL1Tx | Standard Avalanche + PrimeWave PoAManager address |
| Genesis file (alloc block) | **PrimeWave custom** — 100M PW distribution |
| PoAManager deployment | Standard ACP-99 contract (from icm-services) |
| PoAManager initialization | **PrimeWave configuration** — 15 validator identities |
| RewardVault, FeeDistributor | **PrimeWave custom contracts** — deployed at launch |

See updated `PRIMEWAVE_GENESIS_SPEC.md` for full genesis sequence.

---

### ✅ OQ-003 — Finite 15M PW Reward Reserve (RESOLVED)

**Resolution:** The 15,000,000 PW validator/staking allocation is a **finite pre-funded RewardVault**. On-chain accrual/claim model using reward-index (accumulated reward per share) algorithm.

Key decisions:
- Rewards paid from existing PW — NO minting
- On-chain accrual (not per-validator push transactions)
- Validator/delegator claim model (pull, not push)
- When vault exhausted → rewards stop; no new PW created
- RewardVault and ValidatorFeeVault are **strictly separate**

See `PRIMEWAVE_REWARD_ECONOMICS.md` for full specification including invariants and algorithm.

---

### ✅ OQ-004 — 70% Validator Fee Distribution (RESOLVED)

**Resolution:** Validator Fee Vault model. Distribution is proportional to validator weight × uptime eligibility. Strictly separate from the 15M RewardVault.

Key decisions:
- `FeeDistributor` contract routes all gas fees: 70% ValidatorFeeVault / 20% Treasury / 10% Burn
- `ValidatorFeeVault` distributes to validators proportionally: `weight × uptime_factor`
- Phase 1 (15 equal-weight validators): approximately equal split
- Phase 2 (weighted PoS): proportional to stake weight
- Delegators receive proportional share minus validator commission

See `PRIMEWAVE_REWARD_ECONOMICS.md` Section 3 for full specification.

---

### ✅ OQ-005 — PWUSD Monetary Authority (RESOLVED)

**Resolution:** PWUSD has **one designated Monetary Authority** — a single role (not automatically a multisig). The actual identity/signing key will be configured during secure deployment.

Key decisions:
- `MONETARY_AUTHORITY_ROLE` is a single designated role
- **NOT automatically a multisig** — multisig will only be used if explicitly instructed later
- Actual authority address = **PLACEHOLDER** until secure deployment configuration
- Monetary Authority scope: ONLY PWUSD mint/burn operations
- All other governance roles remain strictly separate

See updated `PRIMEWAVE_PWUSD_ARCHITECTURE.md` for full specification.

---

### ✅ OQ-006 — Phase 2 Custom PoS Architecture (APPROVED IN PRINCIPLE)

**Resolution:** Phase 2 custom PoS staking architecture is approved in principle. Implementation is subject to:
- Detailed technical specification (complete — see `PRIMEWAVE_POS_TRANSITION_SPEC.md`)
- A separate implementation sprint
- Security audit of `PrimeWaveStakingManager` before deployment
- Testnet validation
- Explicit PrimeWave approval before each implementation step

The architecture: `PrimeWaveStakingManager` extends `StakingManager` from `ava-labs/icm-services`, overrides only `_reward()` to draw from `RewardVault` instead of minting. Full PoS semantics preserved. No inflation.

See `PRIMEWAVE_POS_TRANSITION_SPEC.md` for full specification.

---

## OPEN QUESTIONS — Still Unresolved

### OQ-007 — AvalancheGo / Subnet-EVM Version Lock
**Status:** 🟡 UNRESOLVED (deferred to testnet initiation)
**Question:** Which exact version of AvalancheGo and Subnet-EVM for testnet? Current latest: AvalancheGo v1.14.2. Must be locked at testnet launch.
**Action:** Lock versions at testnet initiation sprint.

---

### OQ-008 — Chain ID Selection
**Status:** 🟡 UNRESOLVED (intentionally deferred)
**Question:** What Chain IDs for testnet and mainnet?
**Process:** See `PRIMEWAVE_GENESIS_SPEC.md` Section 3.
**Action:** Select testnet Chain ID at testnet initiation sprint; mainnet Chain ID at mainnet prep sprint.

---

### OQ-009 — Minimum Stake Amount (Phase 2)
**Status:** 🟡 UNRESOLVED (deferred to testnet)
**Question:** Minimum PW stake for a Phase 2 validator?
**Action:** Testnet benchmark + economic modeling.

---

### OQ-010 — Gas Parameters
**Status:** 🟡 UNRESOLVED (deferred to testnet)
**Question:** Final gasLimit, minBaseFee, targetGas for mainnet?
**Action:** Testnet benchmarking with realistic load.

---

### ✅ OQ-011 — Unbonding Period (RESOLVED)

**Resolution (locked August 13, 2026):** **14-day unbonding period.**

- Applies to both validator exits and delegator exits in Phase 2 PoS
- Rewards continue to accrue during the unbonding window
- After the period ends: stake returned, validator deregistered from P-Chain
- Emergency forced-removal path does not bypass unbonding for non-slashed funds

**Documents updated:** `PRIMEWAVE_VALIDATOR_SPEC.md`, `PRIMEWAVE_POS_TRANSITION_SPEC.md`

---

### OQ-012 — Smart Contract Audit Firm
**Status:** 🟡 UNRESOLVED
**Question:** Which security audit firm(s) for PrimeWave Chain contracts?
**Action:** RFP process; require EVM/Solidity experience + Avalanche L1 familiarity.

---

### ✅ OQ-013 — Emergency Multisig (RESOLVED)

**Resolution (locked August 13, 2026):** **3-of-5 multisig with narrowly scoped emergency powers.**

Configuration:
- Threshold: 3-of-5 (any 3 of 5 signers must approve)
- Hardware wallet required for all signers
- Signers in ≥ 3 different geographic locations
- No signer may also hold Protocol Admin, Treasury Admin, or Monetary Authority keys

**Authorized powers (exhaustive):** Pause/unpause `PrimeWaveStakingManager`, `RewardVault`, `ValidatorFeeVault`, `FeeDistributor`, `PWUSD`. Freeze specific PWUSD accounts (AML/sanctions only). Nothing else.

**Strictly cannot:** Transfer Treasury funds, modify balances, mint PW, change supply, bypass governance timelock, arbitrarily modify validators, upgrade contracts, or recover/redirect user funds.

**Full specification:** `PRIMEWAVE_GOVERNANCE_POLICY.md` Section 4.

---

### OQ-014 — PWUSD Supply Cap
**Status:** 🟡 UNRESOLVED
**Question:** Should a governance-controlled PWUSD mint cap per period be implemented in V1?
**Decision required from:** PrimeWave leadership.

---

### ✅ OQ-015 — Presale Vesting (RESOLVED)

**Resolution (locked August 13, 2026 — previously approved by PrimeWave leadership):** **NO PRESALE VESTING.**

The three presale allocations have no vesting schedules:
- Presale Phase 1: 5,000,000 PW ($0.01/PW) — no vesting
- Presale Phase 2: 7,500,000 PW ($0.025/PW) — no vesting
- Presale Phase 3: 7,500,000 PW ($0.04/PW) — no vesting

Presale buyers receive their PW allocation without a lock-up or vesting schedule.

**Note:** The team & development allocation (10,000,000 PW) vesting question is separate and remains to be decided. See OQ-023 below.

**Documents updated:** `PRIMEWAVE_TOKENOMICS.md`

---

### ✅ OQ-016 — Governance Timelock Durations (RESOLVED)

**Resolution (locked August 13, 2026):** **48-hour timelock** for all ordinary protocol and treasury administrative changes.

- Emergency actions (pause/freeze by Emergency Multisig) bypass the timelock
- All other governance actions (upgrades, parameter changes, treasury disbursements, validator changes) require the full 48h timelock
- The timelock minimum delay cannot be shortened below 48h without a timelock-gated governance change

**Full specification of which exact actions are subject to the timelock:** `PRIMEWAVE_GOVERNANCE_POLICY.md` Section 3.

**Documents updated:** `PRIMEWAVE_GOVERNANCE_POLICY.md`

---

### ✅ OQ-017 — RewardVault Reward Schedule (RESOLVED)

**Resolution (locked August 13, 2026):** Maximum annual staking emissions of **3,000,000 PW/year**, distributed via linear schedule.

| Parameter | Value |
|---|---|
| Annual cap | 3,000,000 PW |
| Daily maximum | ≈ 8,219.18 PW/day |
| Vault life (at max rate) | **5 years minimum** (extends if unused) |
| Unused emissions | Stay in vault — not burned, not rolled over |
| Rate adjustability | Governance may only reduce the cap (never raise above 3M/year) |

**Full details:** `PRIMEWAVE_REWARD_ECONOMICS.md` Section 2.5 and `PRIMEWAVE_OQ017_OQ018_RESOLUTION.md`.

---

### ✅ OQ-018 — icm-services Release Tag / Version Pin (RESOLVED)

**Resolution (locked August 13, 2026):** Pin `ava-labs/icm-services` to tag **`icm-relayer-v1.7.5`**, commit **`40e1c89`** (released January 26, 2026).

- AvalancheGo compatibility: v1.14.0 (Granite) and v1.14.2 (Granite.2 — explicitly backwards-compatible)
- Solidity version: 0.8.30, EVM target: Shanghai
- Contracts path: `icm-contracts/contracts/validator-manager/`
- Foundry reference: `{ git = "https://github.com/ava-labs/icm-services", tag = "icm-relayer-v1.7.5" }`

**Full details:** `PRIMEWAVE_OQ017_OQ018_RESOLUTION.md`.

---

### 🔵 OQ-019 — StakingManager Interface Compatibility (PARTIALLY VERIFIED)

**Status:** Substantively confirmed; final source review deferred to PW-C01.

**Evidence:** The Avalanche Builder Hub documents `StakingManager` as an abstract contract. `NativeTokenStakingManager` overrides `_reward()` to call `NATIVE_MINTER.mintNativeCoin()` — this can only compile if `_reward()` is `internal virtual` in the base. This confirms the extension point exists by design.

**Remaining action (PW-C01):** Direct source review of `StakingManager.sol` at commit `40e1c89` to confirm `_lock()`, `_unlock()` are also overridable, and that no new mandatory interface has been added.

See `PRIMEWAVE_DEPENDENCY_COMPATIBILITY.md` Section 2.3 for the full verification table.

---

### OQ-020 — Slashing Mechanics Implementation
**Status:** 🟢 DEFERRED (Phase 2)
Exact slashing percentages, governance process for slash proposals, and appeal mechanism — to be designed in Phase 2 sprint.

---

### OQ-021 — PWSwap Fee Governance
**Status:** 🟢 DEFERRED (PW-Swap sprints)
Should the 0.30% swap fee be changeable via governance? What constraints (min/max)?

---

### OQ-022 — PWUSD → USDT Redemption Architecture
**Status:** 🟢 DEFERRED (future)
Long-term objective; requires separate design, legal review, and custodial arrangement.

---

### OQ-023 — Team & Development Allocation Vesting
**Status:** 🟡 UNRESOLVED (separated from OQ-015 which covered presale vesting)
**Question:** Does the 10,000,000 PW team & development allocation vest? If so, over what schedule (e.g., 4-year linear vest with 1-year cliff)?
**Decision required from:** PrimeWave leadership.
**Note:** This is distinct from OQ-015 (presale vesting = no vesting, locked). Team vesting is a separate governance decision that does not block Phase 1 launch.

---

## Summary

| Priority | Count | Status |
|---|---|---|
| ✅ Resolved (OQ-001 to OQ-006, OQ-011, OQ-013, OQ-015 to OQ-018) | 12 | Resolved in PW-C00 |
| ✅ Partially verified (OQ-019) | 1 | `_reward()` is `internal virtual` — final source review in PW-C01 |
| 🟡 Medium (OQ-007 to OQ-010, OQ-012, OQ-014, OQ-023) | 7 | Resolve before testnet/mainnet |
| 🟢 Deferred (OQ-020 to OQ-022) | 3 | Later sprints |

---

*Updated during PW-C00 Decision Resolution. No production deployment has occurred.*
