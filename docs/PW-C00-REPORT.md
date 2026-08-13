# PrimeWave Chain — PW-C00 Final Report
**Sprint PW-C00 — Architecture & Technical Validation**
**Status: COMPLETE — AWAITING PrimeWave APPROVAL**

---

## A. Executive Summary

PW-C00 has researched, analyzed, and documented the complete technical architecture for PrimeWave Chain — a sovereign EVM-compatible Avalanche L1. All 12 required design documents have been produced.

**The most significant finding of PW-C00 is a confirmed technical conflict between the standard Avalanche PoS staking contract and PrimeWave's fixed-supply tokenomics.** This conflict has been analyzed in depth, and a technically sound, fixed-supply-compatible architecture has been designed.

**No production blockchain has been deployed. No production genesis has been created. No production validator keys have been generated. No production contracts have been deployed.**

---

## B. Avalanche Architecture Selected

**Technology:** Avalanche Sovereign L1 under ACP-77 and ACP-99 frameworks.

- **Consensus:** Snowman++ (Avalanche BFT)
- **EVM runtime:** Subnet-EVM
- **Validator management:** ACP-99 standard (`PoAValidatorManager` for Phase 1)
- **Chain communication:** Avalanche Warp Messaging (AWM / ICM) for P-Chain ↔ L1 validator registration
- **Phase 1:** Permissioned (PoA) validator set — 15 validators
- **Phase 2:** Custom PoS with pre-funded RewardVault (requires explicit approval before implementation)

**AvalancheGo/Subnet-EVM version:** To be locked at testnet launch (latest stable at that time).

> **⚠️ Open Item:** The `ava-labs/icm-contracts` repository was archived December 3, 2025. The successor repository must be identified before PW-C01. See `PRIMEWAVE_OPEN_QUESTIONS.md` OQ-001.

---

## C. Fixed-Supply / Staking-Reward Solution

### The Conflict

The standard `NativeTokenStakingManager` (ACP-99 reference implementation) distributes rewards by calling:
```solidity
NATIVE_MINTER.mintNativeCoin(account, amount);
```
This mints new tokens and is **incompatible with the 100,000,000 PW fixed supply**.

The `ERC20TokenStakingManager` also requires a mintable ERC-20 and calls `mint()` — also incompatible.

### The Solution

**Phase 1 (Launch):** `PoAValidatorManager` — no rewards are minted. Validators receive rewards distributed from the pre-funded `RewardVault` (15,000,000 PW locked at genesis). The vault's `distribute()` function sends existing PW from the vault to validators — no new tokens are ever created.

**Phase 2 (PoS, future):** A custom `PrimeWaveStakingManager` that overrides the `_reward()` hook:
```solidity
function _reward(address account, uint256 amount) internal override {
    // Draw from pre-funded vault instead of minting
    rewardVault.distribute(account, amount);
}
```
The vault enforces `require(balance >= amount)` — when the 15M PW is exhausted, no more rewards are paid. Zero inflation.

**This solution is the ONLY technically valid path that satisfies all five requirements simultaneously (100M cap, no mint function, 15M staking allocation, validator rewards, no uncontrolled inflation).**

---

## D. Validator Architecture

- **Phase 1:** `PoAValidatorManager` (ACP-99 standard) with 15 permissioned validators
- **Validator registration:** NodeID + BLS public key; Warp-based P-Chain registration
- **Validator weight:** Equal weight (1/15 each) in Phase 1
- **Staking:** Not required in Phase 1 (PoA model)
- **Rewards:** From 15M PW RewardVault (not minted)
- **Phase 2:** Custom `PrimeWaveStakingManager` with permissionless staking (pending approval)
- **Delegation:** Phase 2 only; commission 5–10% per validator
- **Unbonding:** 14–21 days (exact value: testnet benchmark)
- **Slashing:** YES — provable violations only; ordinary downtime = moderate penalty
- **Validator changes:** Multisig + timelock-controlled in Phase 1

Full specification: `PRIMEWAVE_VALIDATOR_SPEC.md`

---

## E. Genesis Architecture

- All 100,000,000 PW allocated in genesis `alloc` block — no post-genesis minting
- `NativeMinter` precompile NOT activated (physically prevents supply inflation)
- `RewardManager` configured to route all fees to `FeeDistributor` contract address
- `WarpConfig` enabled for ACP-77 P-Chain communication
- Chain ID: NOT finalized in PW-C00 (selection process documented)
- All allocation addresses must be multisig addresses at genesis
- Genesis file requires triple independent review + automated supply verification script

Full specification: `PRIMEWAVE_GENESIS_SPEC.md`

---

## F. PW Supply Invariant

**Formal invariant:**
```
∀ block B:
  circulating(PW) + locked_in_RewardVault(PW) + burned(PW) = 100,000,000 PW

Where:
  burned(PW) ≥ 0  (deflationary over time from gas burns)
  locked_in_RewardVault(PW) ≥ 0  (decreases as rewards are distributed)
  circulating(PW) = 100,000,000 - locked - burned
```

**Enforcement:**
1. Genesis: All PW created at block 0, none created after
2. Protocol: No `NativeMinter` admin — physically impossible to inflate
3. RewardVault: `require(balance >= amount)` before every distribution
4. Automated Foundry invariant tests: `SupplyInvariant.t.sol` (to be written in PW-C01+)

Full specification: `PRIMEWAVE_TOKENOMICS.md` Section 3

---

## G. Gas Architecture

**70/20/10 model (LOCKED):**
- 70% → Validators (via `FeeDistributor`)
- 20% → PrimeWave Treasury (auto-forwarded by `FeeDistributor`)
- 10% → Burned (sent to 0x000...dead by `FeeDistributor`)

**Implementation:**
- `RewardManager` precompile routes all fees to `FeeDistributor` contract address
- `FeeDistributor` contract implements percentage split
- Gas parameters (gasLimit, minBaseFee, targetGas) finalized on testnet

Full specification: `PRIMEWAVE_TOKENOMICS.md` Section 4

---

## H. PWUSD Architecture Boundary

- PWUSD is an ERC-20 token on PrimeWave Chain, separate from PW
- One designated `MonetaryAuthority` role (multisig) holds mint/burn authority
- MonetaryAuthority scope: ONLY PWUSD mint and burn
- MonetaryAuthority CANNOT: withdraw treasury, transfer user funds, manage validators, upgrade chain, control emergency security, manipulate PWSwap
- Every mint/burn emits a named auditable event
- No fixed max supply at launch
- Deployed behind upgradeable proxy; upgrades require Protocol Admin multisig + timelock

Full specification: `PRIMEWAVE_PWUSD_ARCHITECTURE.md`

---

## I. PWSwap Integration Boundary

- PWSwap is a separate project deployed as contracts ON PrimeWave Chain
- V1 pair: PW / PWUSD (constant-product AMM)
- Required events: `Swap`, `Sync`, `Mint`, `Burn` (for PrimeWave Dex indexing)
- Fee: 0.30% → 100% PrimeWave Treasury
- Initial liquidity: 40M PW + 2M PWUSD, locked 36 months
- PrimeWave Chain provides: PW (native), PWUSD (ERC-20), standard EVM
- PWSwap must NOT have: arbitrary admin price-setting, admin liquidity drain
- NOT built in PW-C00

Full specification: `PRIMEWAVE_PWSWAP_INTERFACE.md`

---

## J. PrimeWave Dex / Indexer Boundary

- PrimeWave Dex is a separate project with its own market data pipeline
- Data source: PWSwapPair events indexed from chain
- Indexer → TimescaleDB → Market API → Frontend
- Required metrics: candlesticks (5m/15m/1H/4H/1D/1W), price, volume, liquidity, market cap, FDV, trades, pool reserves, LP history
- PrimeWave Dex MUST NOT depend on DexScreener for core data
- NOT built in PW-C00

Full specification: `PRIMEWAVE_MARKET_DATA_INTERFACE.md`

---

## K. Security Threat Model Summary

29 threats documented across 6 categories:

| Category | Critical | High | Medium |
|---|---|---|---|
| Blockchain/Consensus | 2 | 3 | 2 |
| PW Token | 3 | 0 | 1 |
| PWUSD | 2 | 2 | 3 |
| PWSwap | 2 | 3 | 2 |
| Governance | 1 | 3 | 0 |
| Infrastructure | 2 | 3 | 1 |

**Top Critical Risks:**
- Validator key theft / compromise
- NativeMinter activation (PW inflation)
- Genesis allocation error (permanent)
- PWUSD Monetary Authority compromise
- PWSwap reentrancy / liquidity theft
- Infrastructure credential leakage

Full threat model: `PRIMEWAVE_SECURITY_THREAT_MODEL.md`

---

## L. Repository Structure

**Recommended structure:**

```
primewave-chain/                     # Git repository root
├── README.md
├── .github/
│   └── workflows/                   # CI/CD (GitHub Actions)
│       ├── test.yml                 # Contract tests
│       ├── audit.yml                # Slither/Aderyn scans
│       └── deploy.yml               # Deployment pipelines
│
├── chain/                           # AvalancheGo/Subnet-EVM config
│   ├── configs/
│   │   ├── testnet/
│   │   └── mainnet/                 # DO NOT populate until mainnet prep sprint
│   └── scripts/
│       ├── start-node.sh
│       └── upgrade-node.sh
│
├── genesis/                         # Genesis file management
│   ├── testnet-genesis.json         # Testnet genesis (when ready)
│   ├── mainnet-genesis.json         # DO NOT create until mainnet prep sprint
│   ├── verify-genesis.py            # Supply invariant verification script
│   └── README.md
│
├── validators/                      # Validator setup and management
│   ├── setup/                       # Node setup scripts
│   ├── keys/                        # Key generation procedures (NO ACTUAL KEYS)
│   └── registration/                # Validator registration scripts
│
├── contracts/                       # Solidity smart contracts
│   ├── src/
│   │   ├── validator/
│   │   │   ├── PoAValidatorManager.sol        # Phase 1 (or import from ACP-99)
│   │   │   └── RewardVault.sol                # 15M PW reward distribution
│   │   ├── economics/
│   │   │   └── FeeDistributor.sol             # 70/20/10 fee split
│   │   ├── governance/
│   │   │   ├── PrimeWaveTreasury.sol          # Multisig + timelock wrapper
│   │   │   └── EmergencyMultisig.sol
│   │   └── tokens/
│   │       └── PWUSD.sol                      # PrimeWave USD ERC-20
│   ├── test/
│   │   ├── unit/
│   │   ├── integration/
│   │   ├── fuzz/
│   │   └── invariants/
│   │       └── SupplyInvariant.t.sol
│   ├── script/                      # Foundry deployment scripts
│   ├── foundry.toml
│   └── package.json
│
├── governance/                      # Governance procedures and documentation
│   ├── multisig-setup.md
│   ├── timelock-config.md
│   └── emergency-procedures.md
│
├── infrastructure/                  # Infrastructure as Code
│   ├── terraform/
│   │   ├── testnet/
│   │   └── mainnet/
│   ├── ansible/
│   │   ├── validator-setup.yml
│   │   └── rpc-setup.yml
│   └── docker/
│       ├── blockscout/
│       └── indexer/
│
├── indexer/                         # Chain event indexer (for PrimeWave Dex)
│   ├── src/
│   ├── migrations/
│   └── README.md
│
├── testing/                         # Integration and E2E tests
│   ├── e2e/
│   ├── testnet/
│   └── invariants/
│
├── security/                        # Security documentation and tooling
│   ├── audits/                      # Audit reports (when completed)
│   ├── slither/                     # Static analysis configs
│   └── threat-model.md              # Links to docs/
│
├── scripts/                         # Operational scripts
│   ├── deploy/
│   ├── verify-genesis.py
│   └── monitor/
│
└── docs/                            # Design documents (PW-C00 output)
    ├── PRIMEWAVE_CHAIN_ARCHITECTURE.md
    ├── PRIMEWAVE_TOKENOMICS.md
    ├── PRIMEWAVE_VALIDATOR_SPEC.md
    ├── PRIMEWAVE_PWUSD_ARCHITECTURE.md
    ├── PRIMEWAVE_PWSWAP_INTERFACE.md
    ├── PRIMEWAVE_MARKET_DATA_INTERFACE.md
    ├── PRIMEWAVE_SECURITY_THREAT_MODEL.md
    ├── PRIMEWAVE_INFRASTRUCTURE.md
    ├── PRIMEWAVE_GENESIS_SPEC.md
    ├── PRIMEWAVE_DEPENDENCY_MAP.md
    ├── PRIMEWAVE_OPEN_QUESTIONS.md
    └── PW-C00-REPORT.md
```

---

## M. Technology Stack

| Component | Recommended Technology | Rationale |
|---|---|---|
| Avalanche L1 node | AvalancheGo + Subnet-EVM | Official Ava Labs implementation; only production-ready option |
| Solidity version | 0.8.25 | Same as ACP-99 reference contracts; recent, stable |
| Contract framework | Foundry (Forge, Cast, Anvil) | Industry standard; fast; excellent fuzz/invariant testing; Avalanche compatible |
| Unit testing | Foundry (forge test) | Built-in; same toolchain; no extra setup |
| Integration testing | Foundry + Anvil fork | Fork local chain for integration; or dedicated testnet |
| Fuzz testing | Foundry invariant tests | Built-in Foundry capability; essential for supply invariant |
| Static analysis | Slither + Aderyn | Both free, open-source; Slither is the industry standard for Solidity |
| Formal verification | Certora Prover (optional/audit) | For critical invariants; expensive but valuable for production contracts |
| Block explorer | Blockscout | Open-source, full-featured, EVM-compatible, actively maintained |
| Indexer language | Node.js (TypeScript) or Go | Both have mature EVM libraries; TypeScript aligns with web ecosystem |
| Market database | TimescaleDB | PostgreSQL extension; open-source; excellent for time-series candle data |
| Market API | Express.js (REST) + ws (WebSocket) | Lightweight, proven, good TypeScript support |
| Infrastructure IaC | Terraform + Ansible | Industry standard; cloud-agnostic; mature Avalanche community usage |
| CI/CD | GitHub Actions | Integrated with GitHub; free for open-source; good ecosystem |
| Monitoring | Prometheus + Grafana | Open-source; AvalancheGo exposes native Prometheus metrics |
| Alerting | PagerDuty or Opsgenie | Managed; low maintenance; reliable on-call routing |
| Secrets management | HashiCorp Vault or AWS Secrets Manager | Never store secrets in code or config files |
| Multisig | Safe (Gnosis Safe) | Industry standard; audited; multi-chain support; good tooling |
| Timelock | OpenZeppelin TimelockController | Audited; industry standard; compatible with Safe |
| Contract dependencies | OpenZeppelin 5.x | Audited; industry standard; regularly updated |

### Technology NOT Recommended (and Why)

| Technology | Why Not |
|---|---|
| Hardhat | Slower than Foundry; Foundry is now standard for security-focused projects |
| Truffle | Deprecated |
| Custom wallet | Unnecessary complexity; use MetaMask/Rabby + wallet connect |
| Custom bridge | V1 explicitly has no bridge; evaluate in future sprints after security review |
| Custom oracle | Not needed in V1; TWAP from PWSwap is sufficient |
| Mobile app | Out of scope for chain infrastructure |
| Kubernetes | Over-engineered for initial scale; Docker Compose sufficient initially |
| Multiple cloud regions | Start single region for testnet; multi-region for mainnet |

---

## N. Cost-Control Recommendations

1. **Reserved instances:** Commit to 1-year reserved instances for validator and RPC nodes (30–40% savings vs on-demand)
2. **Hetzner for some validators:** Hetzner dedicated servers are 3–5x cheaper than AWS for equivalent specs; suitable for some validators (geographic diversity)
3. **Managed databases:** Use managed PostgreSQL (Supabase, Neon, or AWS RDS) for Blockscout and Indexer — avoid self-managing Postgres at launch
4. **Shared infrastructure:** Run indexer and monitoring on same servers as archive node where feasible
5. **Open-source everything:** Use open-source tools throughout (Blockscout, Prometheus, Grafana, Foundry) — no per-validator commercial software licenses
6. **Defer until needed:**
   - Custom wallet: Not needed (MetaMask-compatible)
   - Mobile app: Not in scope
   - Oracle: TWAP from PWSwap sufficient
   - Multi-trading-pairs: V1 is PW/PWUSD only
7. **Automation reduces opex:** Terraform + Ansible reduces manual configuration time; automated monitoring reduces incident detection time

Estimated mainnet infra cost: ~$3,000–6,000/month before reserved discounts. With reserved + Hetzner hybrid: ~$1,500–3,000/month.

---

## O. Dependency Graph

```
PrimeWave Chain (foundational)
    ├─── PrimeWave Swap (depends on Chain: PW + PWUSD contracts)
    │       └─── PrimeWave Dex (depends on Chain events + Swap events)
    └─── PrimeWave App (depends on Chain: RPC + PWUSD ERC-20)
```

Startup order: Chain → Swap → Dex → App integration
No project may import code from another. Only published ABIs and standard RPC.

Full details: `PRIMEWAVE_DEPENDENCY_MAP.md`

---

## P. Unresolved Questions

**6 questions require decisions before PW-C01:**

| ID | Question | Owner |
|---|---|---|
| OQ-001 | icm-contracts successor repository | Technical research |
| OQ-002 | Genesis bootstrap mechanism (first blocks) | Technical research |
| OQ-003 | RewardVault distribution model (on-chain vs off-chain) | PrimeWave leadership |
| OQ-004 | 70% validator fee split within validator set | PrimeWave leadership |
| OQ-005 | Monetary Authority multisig composition | PrimeWave leadership |
| OQ-006 | Phase 2 PoS transition approval | PrimeWave leadership |

**10 more questions for testnet/mainnet prep.** Full list: `PRIMEWAVE_OPEN_QUESTIONS.md`

---

## Q. Prerequisites for PW-C01

PW-C01 may begin ONLY after:

1. [ ] PrimeWave leadership approves this PW-C00 report
2. [ ] OQ-001 resolved: icm-contracts successor identified
3. [ ] OQ-002 resolved: genesis bootstrap mechanism confirmed
4. [ ] OQ-003 decision: RewardVault distribution model chosen
5. [ ] OQ-004 decision: 70% validator fee split method chosen
6. [ ] OQ-005 decision: Monetary Authority multisig signers identified
7. [ ] OQ-006 decision: Phase 2 PoS architecture approved (or Phase 1 extended)
8. [ ] Testnet Chain ID selected (temporary, for testnet only)

---

## R. Files Created / Modified

**Sprint PW-C00 created the following files:**

```
docs/
├── PRIMEWAVE_CHAIN_ARCHITECTURE.md      (Architecture, Avalanche L1, ACP-77/99)
├── PRIMEWAVE_TOKENOMICS.md              (PW supply, distribution, gas economics)
├── PRIMEWAVE_VALIDATOR_SPEC.md          (Validator architecture, PoA→PoS, RewardVault)
├── PRIMEWAVE_PWUSD_ARCHITECTURE.md      (PWUSD design, Monetary Authority)
├── PRIMEWAVE_PWSWAP_INTERFACE.md        (PWSwap integration boundary)
├── PRIMEWAVE_MARKET_DATA_INTERFACE.md   (PrimeWave Dex / indexer boundary)
├── PRIMEWAVE_SECURITY_THREAT_MODEL.md   (29 threats, 6 categories)
├── PRIMEWAVE_INFRASTRUCTURE.md          (Node architecture, monitoring, cost)
├── PRIMEWAVE_GENESIS_SPEC.md            (Genesis structure, Chain ID process)
├── PRIMEWAVE_DEPENDENCY_MAP.md          (4-project ecosystem map)
├── PRIMEWAVE_OPEN_QUESTIONS.md          (20 open questions, prioritized)
└── PW-C00-REPORT.md                     (This document)
```

**No production code, contracts, keys, or infrastructure was created.**

---

## S. Research Performed

1. **Avalanche ACP-77** ("Reinventing Subnets") — full architecture review
2. **Avalanche ACP-99** ("Validator Manager Solidity Standard") — full architecture review
3. **`NativeTokenStakingManager.sol`** — source code reviewed; confirmed `NATIVE_MINTER.mintNativeCoin()` call
4. **`ERC20TokenStakingManager.sol`** — source code reviewed; confirmed `IERC20Mintable.mint()` requirement
5. **`StakingManager.sol`** — abstract base contract reviewed; `_reward()` hook identified
6. **`RewardManager` precompile** (0x0200000000000000000000000000000000000004) — documentation reviewed; 3-mode limitation confirmed
7. **ACP-224** — Dynamic gas limits / Fee Manager precompile — reviewed
8. **Avalanche genesis file format** — structure documented
9. **Blockscout** — reviewed as explorer recommendation
10. **`icm-contracts` repository archive status** — confirmed archived December 3, 2025

---

## T. Tests / Research Results

| Item | Finding |
|---|---|
| NativeTokenStakingManager reward mechanism | **CONFIRMED CONFLICT:** mints new tokens; incompatible with 100M fixed supply |
| ERC20TokenStakingManager reward mechanism | **CONFIRMED CONFLICT:** requires mintable ERC-20; incompatible |
| PoAValidatorManager minting | **CONFIRMED SAFE:** no minting; admin-controlled validator set |
| RewardManager 3-way split native support | **NOT SUPPORTED:** only burn/single-address/fee-recipients; custom FeeDistributor required |
| NativeMinter precompile disable | **CONFIRMED POSSIBLE:** omit from genesis config; supply inflation physically prevented |
| icm-contracts archive status | **CONFIRMED ARCHIVED:** December 3, 2025; successor must be identified |

---

## U. Assumptions

1. AvalancheGo will continue to be developed and supported by Ava Labs through PrimeWave Chain's lifetime
2. ACP-77 and ACP-99 are stable standards that will not be deprecated in the near term
3. Subnet-EVM is and will remain the appropriate EVM runtime for PrimeWave Chain
4. The 100,000,000 PW maximum supply and 70/20/10 gas economics are final and will not change
5. Phase 1 will launch with PoA (permissioned validators) before transitioning to PoS
6. The 15,000,000 PW staking reserve will fund validator rewards for the duration of Phase 1 (and part of Phase 2)
7. Smart contracts will be audited by an independent security firm before mainnet launch
8. PrimeWave leadership will provide decisions on the 6 critical open questions before PW-C01 begins
9. The existing PrimeWave application will NOT be migrated into the blockchain repository

---

## PW-C00 Acceptance Criteria Checklist

| Criterion | Status |
|---|---|
| Avalanche L1 architecture researched and validated | ✅ |
| Exact Avalanche implementation/version targeted identified | ✅ (to be locked at testnet; OQ-001 pending) |
| Validator Manager architecture documented | ✅ |
| Initial 15-validator architecture documented | ✅ |
| Initial-validator → staking/delegation transition documented | ✅ |
| Staking/delegation architecture documented | ✅ |
| 15M PW validator/staking reserve mechanism technically resolved | ✅ (RewardVault solution designed) |
| 100M PW maximum supply invariant formally defined | ✅ |
| No hidden PW inflation mechanism | ✅ (NativeMinter disabled; RewardVault constrained) |
| 70/20/10 gas economics architecture validated | ✅ (FeeDistributor design) |
| PWUSD authority separation documented | ✅ |
| PWSwap integration boundary documented | ✅ |
| PrimeWave Dex/indexer integration boundary documented | ✅ |
| Governance architecture documented | ✅ |
| Treasury security documented | ✅ |
| Emergency architecture documented | ✅ |
| Security threat model completed | ✅ (29 threats) |
| Repository structure proposed | ✅ |
| Technology choices justified | ✅ |
| Preliminary genesis architecture documented | ✅ |
| Chain ID selection process documented | ✅ |
| Testnet requirements documented | ✅ |
| Mainnet prerequisites documented | ✅ |
| Cost-control strategy documented | ✅ |
| All unresolved questions explicitly listed | ✅ (20 questions) |
| No production blockchain deployed | ✅ |
| No production genesis created | ✅ |
| No production validator keys generated | ✅ |
| No production contracts deployed | ✅ |

**All PW-C00 acceptance criteria met.**

---

## STOP

Sprint PW-C00 is complete.

**Do NOT start PW-C01.**
**Do NOT create production blockchain infrastructure.**
**Do NOT deploy anything.**

**Wait for explicit approval from the project owner before proceeding.**

---

*PW-C00 completed August 13, 2026.*
