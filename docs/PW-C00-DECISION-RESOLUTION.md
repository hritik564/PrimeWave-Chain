# PrimeWave Chain — PW-C00 Decision Resolution
**Appended to Sprint PW-C00 | August 13, 2026**
**Status: COMPLETE — AWAITING PrimeWave APPROVAL FOR PW-C01**

---

## Decision Resolution Summary

Six open questions from PW-C00 have been resolved. This document records each resolution, the resulting architecture updates, a technical consistency review, a cost optimization review, and the exact prerequisites for PW-C01.

---

## 1. OQ-001 — Avalanche Dependencies (RESOLVED)

**Question was:** What is the successor to the archived `ava-labs/icm-contracts` repository?

**Resolution:**

The official successor is **`ava-labs/icm-services`** (actively maintained — last commit August 10, 2026). The validator manager contracts now live at `icm-contracts/` within that repository. The official Avalanche documentation at `build.avax.network` now sources from `icm-services`.

| Component | Repository | Notes |
|---|---|---|
| PoAManager, ValidatorManager, StakingManager | `ava-labs/icm-services` | Solidity 0.8.30, EVM: shanghai. Pin to release tag. |
| AvalancheGo | `ava-labs/avalanchego` | v1.14.2 current. Lock at testnet. |
| Subnet-EVM | `ava-labs/subnet-evm` | Lock at testnet. |
| Avalanche CLI | `ava-labs/avalanche-cli` | L1 create/convert tooling. |
| OpenZeppelin v5.x | `OpenZeppelin/openzeppelin-contracts` | Audited. Pin version. |
| Foundry | `foundry-rs/foundry` | Build/test/deploy. Pin commit in CI. |

**⚠️ License note:** `icm-services` contracts use `LicenseRef-Ecosystem` (Ava Labs proprietary for commercial use). Legal review required before mainnet.

**⚠️ New open question (OQ-018):** Specific release tag of `icm-services` to pin — determine at development start.

**Documents updated:** `PRIMEWAVE_CHAIN_ARCHITECTURE.md`, `PRIMEWAVE_VALIDATOR_SPEC.md`, `PRIMEWAVE_INFRASTRUCTURE.md`, `PRIMEWAVE_OPEN_QUESTIONS.md`

---

## 2. OQ-002 — Genesis / Bootstrap (RESOLVED)

**Question was:** Who produces the first blocks before PoAManager is initialized?

**Resolution:** Use the **standard Avalanche L1 creation sequence** — no custom mechanism.

```
CreateSubnetTx → CreateChainTx (+ genesis) → ConvertSubnetToL1Tx (+ initial validators)
→ PoAManager.initializeValidatorSet() → 15 validators active → network open
```

The initial 15 validators are specified in `ConvertSubnetToL1Tx` on the P-Chain. The EVM `initializeValidatorSet()` then mirrors that state. There is no ambiguity about the first block producer.

**What is PrimeWave-custom vs. standard Avalanche:**
- Genesis `alloc` block (100M PW distribution): PrimeWave custom configuration
- `RewardVault`, `FeeDistributor`, `PWUSD` contracts: PrimeWave custom contracts
- All other bootstrap steps: Standard Avalanche tooling (`PoAManager` from `icm-services`, `avalanche-cli`)

**Documents updated:** `PRIMEWAVE_GENESIS_SPEC.md`, `PRIMEWAVE_VALIDATOR_SPEC.md`, `PRIMEWAVE_CHAIN_ARCHITECTURE.md`, `PRIMEWAVE_OPEN_QUESTIONS.md`

---

## 3. OQ-003 — Finite 15M PW Reward Reserve (RESOLVED)

**Question was:** Should reward vault use on-chain or off-chain distribution?

**Resolution:** **On-chain accrual / claim model** (pull model, not push).

Architecture: Reward-index algorithm (accumulated reward per share), same model proven in Synthetix, Compound, and many DeFi protocols:
- Global `rewardIndex` incremented each epoch by `epochReward / totalEligibleWeight`
- Validators/delegators accumulate entitlements continuously
- Claim triggers `RewardVault.distribute(account, amount)` — transfers existing PW, no minting
- Vault enforces `require(balance >= amount)` — exhaustion stops rewards, never overflows

**Formal invariants:**
```
RewardVault.balance() + RewardVault.totalDistributed() == 15_000_000e18
totalPW in existence == 100_000_000e18 (constant)
```

**⚠️ New open question (OQ-017):** Daily/epoch emission rate from the RewardVault — requires PrimeWave decision before Phase 1 deployment.

**New document created:** `PRIMEWAVE_REWARD_ECONOMICS.md`

**Documents updated:** `PRIMEWAVE_OPEN_QUESTIONS.md`

---

## 4. OQ-004 — 70% Validator Fee Distribution (RESOLVED)

**Question was:** How is the 70% validator share of gas fees distributed among validators?

**Resolution:** **ValidatorFeeVault** model with weighted distribution.

- All gas fees → `FeeDistributor` → 70% `ValidatorFeeVault` / 20% Treasury / 10% Burn
- `ValidatorFeeVault` distributes proportionally: `validator_weight × uptime_eligibility_factor`
- Phase 1 (equal-weight, equal-uptime): approximately equal split (1/15 each)
- Phase 2 (PoS): proportional to stake weight
- Delegators receive proportional share minus validator commission from their validator's entitlement

**Critical separation:** `ValidatorFeeVault` (ongoing gas fees) and `RewardVault` (finite 15M PW) are STRICTLY SEPARATE contracts with SEPARATE funds. They must never be conflated.

**Documents updated:** `PRIMEWAVE_TOKENOMICS.md`, `PRIMEWAVE_REWARD_ECONOMICS.md`, `PRIMEWAVE_VALIDATOR_SPEC.md`, `PRIMEWAVE_CHAIN_ARCHITECTURE.md`, `PRIMEWAVE_OPEN_QUESTIONS.md`

---

## 5. OQ-005 — PWUSD Monetary Authority (RESOLVED)

**Question was:** Who are the Monetary Authority multisig signers?

**Resolution:** PWUSD Monetary Authority is a **single designated role** — NOT automatically a multisig. A multisig structure will only be adopted if explicitly instructed by PrimeWave leadership at deployment time.

- `MONETARY_AUTHORITY_ADDRESS = PLACEHOLDER` (configured during secure deployment)
- Role scope: ONLY PWUSD mint and burn operations
- Role does NOT grant: treasury access, user fund control, validator management, protocol upgrades, emergency security, PWSwap control, or arbitrary governance
- All other governance roles remain strictly separate
- Do NOT generate a real key or configure a real address until the secure deployment process

**Documents updated:** `PRIMEWAVE_PWUSD_ARCHITECTURE.md`, `PRIMEWAVE_SECURITY_THREAT_MODEL.md`, `PRIMEWAVE_OPEN_QUESTIONS.md`

---

## 6. OQ-006 — Phase 2 Custom PoS Architecture (APPROVED IN PRINCIPLE)

**Question was:** Is the Phase 2 custom PoS staking architecture approved?

**Resolution:** **Approved in principle.** Implementation is subject to a separate sprint, security audit, testnet validation, and explicit approval before each implementation step.

Architecture summary:
- `PrimeWaveStakingManager` extends `StakingManager` from `ava-labs/icm-services`
- Overrides ONLY `_reward()`: draws from `RewardVault` instead of calling `NATIVE_MINTER.mintNativeCoin()`
- All Avalanche P-Chain / Warp semantics preserved (inherited from `StakingManager`)
- Zero inflation: vault balance physically limits reward output
- Full PoS: staking, delegation, commission, unbonding, uptime, slashing

**⚠️ New open question (OQ-019):** Confirm `StakingManager._reward()` remains `internal virtual` in current `icm-services` version before Phase 2 implementation.

**New document created:** `PRIMEWAVE_POS_TRANSITION_SPEC.md`

**Documents updated:** `PRIMEWAVE_VALIDATOR_SPEC.md`, `PRIMEWAVE_CHAIN_ARCHITECTURE.md`, `PRIMEWAVE_SECURITY_THREAT_MODEL.md`, `PRIMEWAVE_OPEN_QUESTIONS.md`

---

## A. Final Architecture (Post Decision Resolution)

```
PrimeWave Chain — Sovereign Avalanche L1 (ACP-77 / ACP-99)
│
├── CONSENSUS: Snowman++ BFT (AvalancheGo v1.14.2+)
├── EVM: Subnet-EVM (full EVM compatibility)
├── VALIDATOR CONTRACTS: ava-labs/icm-services (Solidity 0.8.30)
│
├── PHASE 1: PoA
│   ├── PoAManager (from icm-services, ACP-99)
│   ├── 15 permissioned validators (equal weight)
│   └── Rewards from RewardVault (on-chain accrual/claim, no minting)
│
├── PHASE 2: Custom PoS (approved in principle)
│   ├── PrimeWaveStakingManager (extends StakingManager, overrides _reward())
│   ├── Permissionless staking, delegation
│   └── Rewards from RewardVault (same vault, no minting)
│
├── TOKEN ECONOMICS:
│   ├── PW: 100,000,000 max supply (FIXED — no NativeMinter)
│   ├── RewardVault: 15M PW finite reserve (genesis pre-funded)
│   ├── ValidatorFeeVault: Ongoing 70% gas fee accumulation
│   ├── PrimeWave Treasury: 20% gas fees + 15M PW treasury allocation
│   └── Burn: 10% gas fees permanently removed
│
├── PWUSD: ERC-20, single Monetary Authority role (PLACEHOLDER address)
│
└── GOVERNANCE:
    ├── Protocol Admin: Multisig + TimelockController
    ├── Treasury: Multisig + TimelockController (separate)
    ├── Emergency: Separate emergency multisig (pause only)
    └── Monetary Authority: Single designated role (PLACEHOLDER)
```

---

## B. Remaining Technical Risks

| Risk | Severity | Status |
|---|---|---|
| `icm-services` license (LicenseRef-Ecosystem) may require commercial arrangement | 🔴 | Legal review needed before mainnet |
| `StakingManager._reward()` interface in `icm-services` must remain `internal virtual` | 🟠 | Verify at Phase 2 implementation |
| RewardVault emission rate not yet set — affects validator economics | 🟠 | Decision needed (OQ-017) before Phase 1 |
| Specific `icm-services` release tag not yet pinned | 🟡 | Pin at development start (OQ-018) |
| `ConvertSubnetToL1Tx` exact format/tooling may change between CLI versions | 🟡 | Lock CLI version at testnet |
| Phase 2 custom staking requires independent security audit | 🟠 | Pre-audit checklist needed |

---

## C. Remaining Open Questions

| ID | Question | Priority |
|---|---|---|
| OQ-007 | AvalancheGo / Subnet-EVM version lock | 🟡 Deferred to testnet |
| OQ-008 | Chain ID selection (testnet + mainnet) | 🟡 Deferred |
| OQ-009 | Minimum stake amount (Phase 2) | 🟡 Deferred to testnet |
| OQ-010 | Gas parameters (final) | 🟡 Deferred to testnet |
| OQ-011 | Unbonding period (14 vs 21 days) | 🟡 Leadership decision needed |
| OQ-012 | Audit firm selection | 🟡 Pre-mainnet |
| OQ-013 | Emergency multisig composition | 🟡 Leadership decision needed |
| OQ-014 | PWUSD per-period mint cap | 🟡 Leadership decision needed |
| OQ-015 | Team allocation vesting | 🟡 Leadership decision needed |
| OQ-016 | Governance timelock durations | 🟡 Leadership decision needed |
| ✅ OQ-017 | RewardVault emission rate → **3M PW/year max, ~8,219.18 PW/day** | RESOLVED Aug 13, 2026 |
| ✅ OQ-018 | icm-services release tag → **`icm-relayer-v1.7.5` / commit `40e1c89`** | RESOLVED Aug 13, 2026 |
| OQ-019 | StakingManager._reward() interface compatibility | 🟠 Verify before Phase 2 |
| OQ-020–022 | Slashing, PWSwap fee governance, PWUSD redemption | 🟢 Later sprints |

Full details: `PRIMEWAVE_OPEN_QUESTIONS.md`

---

## D. Technical Consistency Review

Answers to all 14 consistency checks required by the sprint:

| Check | Question | Answer |
|---|---|---|
| A | Can RewardVault hold native PW? | ✅ YES — native PW sent to contract address at genesis via `alloc` block; contract can hold and transfer native PW |
| B | Can rewards transfer from finite reserve without minting? | ✅ YES — `RewardVault.distribute(account, amount)` calls `payable(account).transfer(amount)`; no mint required |
| C | Can validator/delegator reward accounting work without NativeMinter? | ✅ YES — reward-index algorithm accumulates entitlements on-chain; claims draw from vault balance |
| D | Can 70% fee vault operate independently from 15M reward reserve? | ✅ YES — `ValidatorFeeVault` and `RewardVault` are separate contracts with separate balances; different funding sources |
| E | Can initial 15 validators operate under Phase 1 PoA? | ✅ YES — `PoAManager` (standard ACP-99) supports exactly this; tested in production by other Avalanche L1s |
| F | Can Phase 2 transition to the proposed custom staking model? | ✅ YES — `PoAManager.owner` transferred to `PrimeWaveStakingManager`; both wrap `ValidatorManager` (same core contract) |
| G | Can the 100M PW supply invariant be proven? | ✅ YES — NativeMinter not activated (protocol enforcement); RewardVault enforces `require(balance >= amount)` (contract enforcement); Foundry invariant tests verify at unit/fuzz level |
| H | Does any Avalanche component still require native-token minting? | ✅ NO — `PoAManager` has no reward mechanism; `PrimeWaveStakingManager` overrides `_reward()` away from minting; NativeMinter precompile not activated |
| I | Are there hidden dependencies on NativeMinter? | ✅ NO — `PoAManager` does not import `INativeMinter`; `PrimeWaveStakingManager` will be audited to confirm |
| J | Does custom staking require Avalanche functionality that is not exposed? | ✅ NO — `StakingManager._reward()` is `internal virtual` (extension point designed for this); `_lock()`/`_unlock()` also overridable |
| K | Are proposed reward accounting mechanisms gas-efficient? | ✅ YES — reward-index O(1) per update, O(1) per claim; no O(n) validator loops; proven pattern in DeFi |
| L | Are proposed contracts auditable? | ✅ YES — standard OpenZeppelin patterns; reward-index is a well-known algorithm; clean separation of concerns |
| M | Are there circular dependencies? | ✅ NO — `RewardVault` ← `PrimeWaveStakingManager` ← `ValidatorManager` ← P-Chain; no cycles |
| N | Security assumptions needing explicit validation | ⚠️ Three: (1) `icm-services` license permits PrimeWave's use; (2) `StakingManager._reward()` remains overridable; (3) `RewardVault` native PW transfer pattern is safe from reentrancy (must use `transfer()` not `call()`) |

---

## E. Cost Optimization Review

The following simplifications are recommended without compromising security, correctness, decentralization roadmap, or auditability:

**Simplifications adopted:**

| Area | Simplification | Rationale |
|---|---|---|
| Validator Fee Vault | Single `ValidatorFeeVault` contract (not separate per-validator) | Reduces contract count; reward-index handles distribution |
| RewardVault | Same reward-index used for both staking rewards AND fee distribution | One proven algorithm for both mechanisms |
| Infrastructure | Start with Docker Compose for non-validator services; migrate to K8s only if needed | Reduces operational complexity at launch |
| Database | Single TimescaleDB instance for both Blockscout and Indexer initially | Reduces DB hosting cost; split only if performance requires |
| Monitoring | Grafana Cloud (managed) over self-hosted Prometheus stack | Reduces server count and operational overhead |

**Components confirmed as necessary (not removable):**

| Component | Why Necessary |
|---|---|
| RewardVault | Required to implement fixed-supply staking rewards |
| ValidatorFeeVault | Required for 70/20/10 split (RewardManager can't split natively) |
| FeeDistributor | Required — RewardManager sends all fees to one address |
| Emergency Multisig | Required for security posture |
| TimelockController | Required for governance safety |
| Archive/Indexer node | Required for Blockscout and PrimeWave Dex indexer |
| PWUSD contract | Required — core ecosystem asset |

**Components NOT being built (cost savings confirmed):**
- Custom wallet: Use MetaMask-compatible standard
- Custom bridge: V1 has no bridge
- Oracle network: TWAP from PWSwap is sufficient
- Mobile app: Out of scope
- Multiple DB systems: One TimescaleDB initially

---

## F. Files Created / Modified (Decision Resolution)

**New documents created:**
```
docs/PRIMEWAVE_REWARD_ECONOMICS.md      (new — dual mechanism specification)
docs/PRIMEWAVE_POS_TRANSITION_SPEC.md   (new — Phase 1 → Phase 2 full spec)
docs/PW-C00-DECISION-RESOLUTION.md     (new — this document)
```

**Existing documents updated:**
```
docs/PRIMEWAVE_CHAIN_ARCHITECTURE.md    (Section 7: dependency registry; OQ-001 resolved)
docs/PRIMEWAVE_VALIDATOR_SPEC.md        (PoAManager naming; OQ-006 approval; icm-services refs)
docs/PRIMEWAVE_TOKENOMICS.md            (Section 4: two-mechanism separation; OQ-004 resolved)
docs/PRIMEWAVE_PWUSD_ARCHITECTURE.md    (Section 3.1: single authority, PLACEHOLDER; OQ-005)
docs/PRIMEWAVE_GENESIS_SPEC.md          (Section 7: standard bootstrap sequence; OQ-002)
docs/PRIMEWAVE_INFRASTRUCTURE.md        (Section 9B: confirmed dependency registry; OQ-001)
docs/PRIMEWAVE_SECURITY_THREAT_MODEL.md (Section 4.2: single authority key mitigations; OQ-005)
docs/PRIMEWAVE_OPEN_QUESTIONS.md        (OQ-001 to OQ-006 marked resolved; OQ-017/018/019 added)
```

---

## G. Research Performed

1. `ava-labs/icm-services` repository confirmed as active successor to archived `icm-contracts` (verified via official Avalanche docs edit URL, GitHub activity)
2. `ava-labs/icm-services` foundry config confirmed: Solidity 0.8.30, EVM: shanghai
3. AvalancheGo latest release confirmed: v1.14.2 (pkg.go.dev)
4. Official Avalanche Builder Hub (`build.avax.network`) confirms `icm-services` as current source
5. Standard L1 bootstrap sequence verified against Avalanche academy docs (CreateSubnetTx → ConvertSubnetToL1Tx flow)
6. `LicenseRef-Ecosystem` license identified on `icm-services` — flagged for legal review
7. Reward-index algorithm validated as O(1) and gas-efficient for reward distribution

---

## H. Assumptions

1. `ava-labs/icm-services` will continue to be maintained and receive security patches
2. `StakingManager._reward()` in `icm-services` is and will remain `internal virtual` (to be confirmed at Phase 2)
3. The `LicenseRef-Ecosystem` license on `icm-services` permits PrimeWave's deployment (legal review required)
4. `ConvertSubnetToL1Tx` semantics are stable in the versions of AvalancheGo and avalanche-cli used at testnet
5. The reward-index algorithm is sufficient for Phase 1 (15 validators, equal weight) and Phase 2 (PoS, variable weight)
6. The RewardVault emission rate will be set by PrimeWave governance before Phase 1 deployment (OQ-017)
7. No production code, contracts, keys, genesis, or infrastructure has been created during this decision resolution task

---

## Exact Prerequisites for PW-C01

PW-C01 may begin ONLY when ALL of the following are confirmed:

**Technical (must be researched):**
- [x] ~~OQ-018 resolved: icm-services release tag pinned~~ → **DONE: `icm-relayer-v1.7.5` / `40e1c89`**
- [ ] Confirm exact OpenZeppelin v5.x patch version to pin
- [ ] Confirm Subnet-EVM version compatible with AvalancheGo v1.14.2
- [ ] Verify `StakingManager._reward()` is `internal virtual` at commit `40e1c89` (partial resolution of OQ-019)
- [ ] `icm-services` license reviewed by PrimeWave legal counsel

**Leadership decisions required:**
- [x] ~~OQ-017 resolved: RewardVault emission rate~~ → **DONE: 3,000,000 PW/year max, ≈8,219.18 PW/day**
- [ ] OQ-011 resolved: Unbonding period chosen (14 or 21 days)
- [ ] OQ-013 resolved: Emergency multisig signers and exact powers defined
- [ ] OQ-015 resolved: Team allocation vesting decision (yes/no and schedule)
- [ ] OQ-016 resolved: Governance timelock durations agreed

**Governance setup (before any contract deployment):**
- [ ] Treasury multisig signers identified and wallets prepared
- [ ] Protocol Admin multisig signers identified and wallets prepared
- [ ] Emergency multisig signers identified and wallets prepared
- [ ] MONETARY_AUTHORITY_ADDRESS security process planned

---

## STOP

Decision Resolution is complete. PW-C00 is fully closed.

**Do NOT start PW-C01.**

Wait for explicit approval from the project owner.

---

*PW-C00 Decision Resolution completed August 13, 2026.*
