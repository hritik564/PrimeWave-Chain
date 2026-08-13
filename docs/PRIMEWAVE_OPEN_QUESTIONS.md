# PrimeWave Chain — Open Questions
**Sprint PW-C00 | Status: DESIGN DOCUMENT — NOT FOR PRODUCTION**

---

This document lists all unresolved technical and architectural questions that MUST be answered before or during the sprint in which they are relevant. No question here may be silently assumed away.

---

## CRITICAL — Must Resolve Before PW-C01

### OQ-001: icm-contracts Repository Succession
**Status:** 🔴 UNRESOLVED

The `ava-labs/icm-contracts` repository (which contains the ACP-99 ValidatorManager reference implementations: `PoAValidatorManager`, `NativeTokenStakingManager`, `ERC20TokenStakingManager`, `StakingManager`) was **archived on December 3, 2025** and is now read-only.

**Question:** What is the successor repository? Where is the current, maintained ACP-99 ValidatorManager implementation?

**Research needed:**
- Check Ava Labs GitHub for successor repos
- Check Avalanche Foundation ACPs for updated implementation references
- Check `avalanche-starter-kit` or similar for current recommended contracts

**Blocker for:** All contract development (Phase 1 PoAValidatorManager deployment)

---

### OQ-002: Genesis Bootstrap — Who Produces the First Blocks?
**Status:** 🔴 UNRESOLVED

In ACP-77, validators are registered via the `PoAValidatorManager` contract AFTER the chain is running. But the chain needs validators to produce blocks from block 0.

**Question:** What is the exact mechanism for bootstrapping an ACP-77 L1 from zero? How are the initial blocks produced before `PoAValidatorManager` is initialized? Is there a pre-P-Chain genesis validator configuration in AvalancheGo? Does the L1 node config specify initial validators separately from the contract?

**Research needed:**
- Avalanche L1 launch tutorials/documentation
- AvalancheGo L1 configuration options
- avalanche-starter-kit examples for initial launch

**Blocker for:** PW-C01 testnet launch

---

### OQ-003: RewardVault — On-chain vs Off-chain Distribution
**Status:** 🟠 UNRESOLVED

**Question:** Should the 15M PW validator reward vault distribute rewards:
- **On-chain automatically** (via a permissioned keeper/bot calling `distribute()` on schedule), OR
- **On-chain via validator claim** (validators call `claim()` after each epoch), OR
- **Off-chain calculated, on-chain settled** (governance signs and submits rewards)?

Each option has different security, decentralization, and complexity tradeoffs.

**Decision required from:** PrimeWave project leadership

**Blocker for:** RewardVault contract design (PW-C01+)

---

### OQ-004: Validator Fee Distribution (70% Share)
**Status:** 🟠 UNRESOLVED

**Question:** Within the 70% validator share of gas fees collected by `FeeDistributor`, how are fees split among the 15 validators?
- Equal split (each validator gets 70% / 15)?
- Weighted by uptime?
- Weighted by stake weight?
- Validators collect their own coinbase fees (different model)?

**Decision required from:** PrimeWave project leadership

**Blocker for:** FeeDistributor contract design

---

### OQ-005: Monetary Authority — Multisig Composition
**Status:** 🟠 UNRESOLVED

**Question:** Who are the signers on the Monetary Authority multisig? What is the threshold (e.g., 3-of-5)?

**Decision required from:** PrimeWave leadership (operational/organizational decision)

**Blocker for:** PWUSD contract deployment

---

### OQ-006: Phase 2 PoS Transition — Explicit Approval Required
**Status:** 🟠 AWAITING APPROVAL

The Phase 2 transition from `PoAValidatorManager` to a custom `PrimeWaveStakingManager` (with RewardVault-funded rewards) is the recommended architecture for permissionless PoS.

**Question:** Does PrimeWave approve:
1. The Phase 2 architecture (custom StakingManager + RewardVault)?
2. The timeline for Phase 2 (which sprint)?
3. The requirement for a security audit of the custom StakingManager before deployment?

**Blocker for:** Phase 2 sprint planning

---

## HIGH PRIORITY — Must Resolve Before Testnet

### OQ-007: AvalancheGo Version Lock
**Status:** 🟡 UNRESOLVED

**Question:** Which exact version of AvalancheGo and Subnet-EVM should be used for testnet? Is there a current stable release that includes full ACP-77 support?

**Action:** Check `ava-labs/avalanchego` releases at testnet initiation time and lock to a specific version.

---

### OQ-008: Chain ID Selection
**Status:** 🟡 UNRESOLVED (intentionally deferred)

**Question:** What Chain ID will PrimeWave Chain use?

**Process:** 
1. At testnet initiation: pick a temporary testnet Chain ID
2. At mainnet preparation: select a unique, unregistered mainnet Chain ID
3. Register at `ethereum-lists/chains` before launch

See `PRIMEWAVE_GENESIS_SPEC.md` Section 3 for full process.

---

### OQ-009: Minimum Stake (Phase 2)
**Status:** 🟡 UNRESOLVED (deferred to testnet)

**Question:** What is the minimum stake amount for a Phase 2 PoS validator?

**Approach:** Determine through testnet benchmarking. Consider economic factors (barrier to entry vs. security).

---

### OQ-010: Gas Parameters
**Status:** 🟡 UNRESOLVED (deferred to testnet)

**Question:** What are the final gas parameters for mainnet?
- gasLimit per block
- minBaseFee
- targetGas
- Other EIP-1559 parameters

**Approach:** Benchmark on testnet with realistic transaction load.

---

### OQ-011: Unbonding Period (Phase 2)
**Status:** 🟡 UNRESOLVED

**Question:** What is the exact unbonding period — 14 days or 21 days?

**Decision required from:** PrimeWave leadership (economic policy decision)

---

## MEDIUM PRIORITY — Resolve Before Mainnet

### OQ-012: Smart Contract Audit Firm
**Status:** 🟡 UNRESOLVED

**Question:** Which security audit firm(s) will audit PrimeWave Chain contracts before mainnet?

**Requirements:** Firm must have EVM/Solidity experience and preferably Avalanche L1 experience.

---

### OQ-013: Emergency Multisig Composition and Powers
**Status:** 🟡 UNRESOLVED

**Question:** Who are the emergency multisig signers? What exact powers does it have (which contracts can it pause, what is the auto-expiry on pauses)?

**Decision required from:** PrimeWave leadership

---

### OQ-014: PWUSD Supply Cap
**Status:** 🟡 UNRESOLVED

**Question:** Should a governance-controlled PWUSD mint cap per period be implemented in V1, or is operational policy sufficient?

**Tradeoff:** On-chain cap = stronger guarantee but less operational flexibility. Policy-only = simpler but weaker guarantee.

**Decision required from:** PrimeWave leadership

---

### OQ-015: Team & Development Allocation Vesting
**Status:** 🟡 UNRESOLVED

**Question:** The 10,000,000 PW Team & Development allocation — does it vest? If so, over what schedule?

The sprint doc states "NO presale vesting" (LOCKED for presale allocations), but team vesting was not explicitly addressed.

**Decision required from:** PrimeWave leadership

---

### OQ-016: Governance Timelock Durations
**Status:** 🟡 UNRESOLVED

**Question:** What are the minimum timelock durations for:
- Normal governance operations (treasury spending, parameter changes)?
- Protocol upgrades?
- Emergency actions?

**Recommendation:** 48h normal / 7 days upgrades / no timelock for emergency pause-only.

**Decision required from:** PrimeWave leadership for final values.

---

## LOWER PRIORITY — Resolve Before Phase 2 / Later Sprints

### OQ-017: PWSwap Fee Governance
**Status:** 🟢 DEFERRED (PW-Swap sprints)

Should the 0.30% PWSwap swap fee be changeable via governance? If so, with what constraints (min/max)?

### OQ-018: PWUSD → USDT Redemption Architecture
**Status:** 🟢 DEFERRED (future)

The long-term objective for PWUSD ↔ USDT redemption requires a separate design. Not a PW-C00 item.

### OQ-019: PrimeWave Dex — DexScreener Integration Strategy
**Status:** 🟢 DEFERRED (PrimeWave Dex sprints)

Should PrimeWave Dex also list on external aggregators (DexScreener, CoinGecko, etc.) for discoverability? If so, which and when?

### OQ-020: Slashing Mechanics Implementation
**Status:** 🟢 DEFERRED (Phase 2)

Exact slashing percentages, governance process for slash proposals, and appeal mechanism — to be designed in Phase 2.

---

## Summary

| Priority | Count | Must Resolve By |
|---|---|---|
| 🔴 Critical | 2 (OQ-001, OQ-002) | Before PW-C01 |
| 🟠 High | 4 (OQ-003 to OQ-006) | Before PW-C01 |
| 🟡 Medium | 10 (OQ-007 to OQ-016) | Before testnet/mainnet |
| 🟢 Lower | 4 (OQ-017 to OQ-020) | Later sprints |

---

*This document is a PW-C00 design specification. No production deployment has occurred.*
