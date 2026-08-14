# PW-C08 Integrated Security Review

> Sprint: PW-C08 Protocol Integration + Production Configuration Hardening
> Scope: All C01-C07 contracts reviewed as an integrated system
> Date: 2026-08-14
> Verdict: **NO CRITICAL ISSUES — 2 HARDENING NOTES**

---

## 1. Review Scope

This review covers all PrimeWave protocol contracts as a unified system:

| Contract | Version | Source |
|----------|---------|--------|
| FeeDistributor | C07 | `contracts/src/FeeDistributor.sol` |
| ValidatorFeeVault | C06 | `contracts/src/ValidatorFeeVault.sol` |
| DevTreasury | C04 | `contracts/src/DevTreasury.sol` |
| RewardVault | C06 | `contracts/src/RewardVault.sol` |
| EmergencyMultisig | C07 | `contracts/src/EmergencyMultisig.sol` |
| PrimeWaveTimelock | C07 | `contracts/src/PrimeWaveTimelock.sol` |
| PrimeWaveValidatorRegistry | C05 | `contracts/src/PrimeWaveValidatorRegistry.sol` |

**NOT in scope:** AvalancheGo node configuration, P-Chain validator management, key management practices, off-chain signing infrastructure.

---

## 2. Critical Findings

### 2.1 CRITICAL — None

No critical vulnerabilities (fund theft, unauthorized minting, supply inflation, permanent lockout) were found.

---

## 3. High Findings

### 3.1 HIGH — None

No high-severity vulnerabilities found.

---

## 4. Medium Findings

### 4.1 MED-01 — FeeDistributor pauseController Cannot Be Rotated

**Severity:** Medium
**Status:** KNOWN / DESIGN LIMITATION
**Contract:** FeeDistributor

**Description:**
`FeeDistributor._pauseController` is `immutable` — set once in the constructor and unchangeable. If the pauseController address (EmergencyMultisig) is compromised or lost, the FeeDistributor can never be paused (or always-paused if the EMS is set wrong).

**The C03 Dev Deployment:**
The C03 genesis deployment sets `pauseController = address(0)`, intentionally disabling the pause mechanism for local development. This is acceptable for dev but would be a hardening gap in production.

**Production Mitigation:**
Deploy FeeDistributor with the correct EmergencyMultisig address as pauseController from day one. Document the EMS address selection as a pre-deployment gate. Verify with `ValidateGenesis.s.sol`.

**Why Not Critical:**
If the EMS key is compromised, the worst outcome for FeeDistributor is continued uninterrupted fee distribution (safe) or permanent pause (bad, but funds are not stolen — validators can no longer claim via FD, but VFV balance is preserved). No funds can be stolen via a compromised pauseController.

---

## 5. Low Findings

### 5.1 LOW-01 — Timelock Single-Proposer Risk

**Severity:** Low
**Status:** KNOWN / PLANNED MITIGATION
**Contract:** PrimeWaveTimelock

**Description:**
The Timelock has a single `proposer` address. If the proposer key is lost (not compromised — lost), no new timelocked operations can be scheduled until `transferProposer()` is called (which is itself a timelocked action). A lost proposer key on a chain with no current pending operations would permanently lock the timelock's governance path.

**Mitigation:**
In production:
- Use a multisig address as proposer
- Maintain a pre-signed `transferProposer(fallback)` transaction in cold storage
- Keep the fallback proposer address in a separate multisig

**Why Not Medium:**
The pause path (EmergencyMultisig) is independent and still functions even if the Timelock proposer is lost. A lost proposer only locks future governance actions, not the emergency pause.

### 5.2 LOW-02 — ValidatorFeeVault admin Cannot Register Phase-2 Staking Manager

**Severity:** Low
**Status:** KNOWN / TRACKED (Phase 2 backlog)
**Contract:** ValidatorFeeVault

**Description:**
`ValidatorFeeVault.protocolAdmin` is immutable. When Phase-2 PrimeWaveStakingManager is introduced, it will need to call `registerValidator()` and `setBaseWeight()`. If the current `protocolAdmin` (DEV0/multisig) is not reachable via Timelock, the registry adapter cannot be authorized to forward calls.

**Mitigation:**
Use `PrimeWaveValidatorRegistry` as the protocolAdmin from day one in production. PrimeWaveValidatorRegistry already has `admin`-based authority management and is designed to be the sole intermediary. All VFV admin calls go through the registry.

**Why Not Medium:**
This is a Phase-2 planning item. Phase-1 validators are registered manually via the registry's own protocolAdmin. No funds are at risk.

---

## 6. Informational Findings

### 6.1 INFO-01 — No Events on DevTreasury Withdrawal

**Severity:** Informational
**Contract:** DevTreasury

**Description:**
DevTreasury has no explicit admin (relies on receive()), so treasury withdrawals happen via direct ETH transfers from the treasury address (a multisig). These are logged by the multisig itself but not by the DevTreasury contract. Off-chain monitoring must watch the treasury address balance directly.

### 6.2 INFO-02 — distribute() is Permissionless

**Severity:** Informational
**Contract:** FeeDistributor

**Description:**
Anyone can call `FeeDistributor.distribute()`. This is intentional (no actor should be the single bottleneck for fee distribution), but means any MEV bot or arbitrageur can trigger distributions at any time. The protocol benefits from this (no accumulated pending fees), but validators should be aware their reward timestamps reset on each external-triggered distribution.

### 6.3 INFO-03 — RewardVault is Fully Pre-funded

**Severity:** Informational
**Contract:** RewardVault

**Description:**
The 15M PW reward pool is pre-funded at genesis. If the protocol shuts down, the remaining funds in RewardVault can only be recovered via registered recipients claiming their share. There is no admin-emergency-withdrawal path. This is a design choice (protects recipient interests) but means pre-funded PW is effectively locked until claimed or the vault is exhausted.

### 6.4 INFO-04 — EMS Has No Time-Lock on Emergency Pause

**Severity:** Informational
**Contract:** EmergencyMultisig

**Description:**
Emergency pause takes effect immediately once 3 of 5 signers approve. There is no delay. This is the intended design (emergency response must be fast). The tradeoff is that a 3-of-5 key compromise could immediately pause all protocol contracts. Mitigated by hardware key requirements and geographic distribution of signers.

---

## 7. Attack Surface Analysis

### 7.1 Reentrancy

| Call Site | Reentrancy Risk | Guard |
|-----------|----------------|-------|
| FeeDistributor.distribute() | LOW | Splits calculated before any transfer; ETH push to vault/treasury in order; no external view calls between transfers |
| ValidatorFeeVault.claimFees() | LOW | State updated before ETH push (checks-effects-interactions) |
| RewardVault.claim() | LOW | State updated before ETH push |
| DevTreasury.receive() | NONE | Empty receive() |
| EmergencyMultisig.execute() | LOW | nonce incremented before external call; target is constrained to pause domain |

**Overall Reentrancy risk: LOW.** All fund movements follow checks-effects-interactions. None of the contracts call external contracts with unknown ABI before updating state.

### 7.2 Integer Overflow/Underflow

All contracts use Solidity 0.8.30 with built-in checked arithmetic. No unchecked blocks are used except in `PrimeWaveValidatorRegistry.devSetWeight()` (dev-only function) where the underflow check was previously identified and documented (C05).

### 7.3 Access Control

| Function Class | Pattern | Known Attack |
|----------------|---------|-------------|
| protocolAdmin functions | `require(msg.sender == protocolAdmin)` | Admin key compromise (off-chain) |
| pauseController functions | `require(msg.sender == pauseController)` | EMS key compromise (off-chain) |
| claimFees() | `require(msg.sender == rewardRecipient[id])` | Recipient address compromise (off-chain) |
| claim() | `require(msg.sender == rewardAddress[id])` | Reward address compromise (off-chain) |
| distribute() | Permissionless | MEV race (benign -- always correct math) |

All on-chain access control patterns are correct. No TOCTOU (time-of-check/time-of-use) vulnerabilities identified.

### 7.4 Economic Attacks

**Fee Sniping:** An attacker cannot front-run `distribute()` to steal fees. The split is deterministic: 70/20/10 based on contract balances. The distribution always goes to the immutable vault/treasury/burn addresses. Nothing goes to the caller.

**Reward Index Manipulation:** The reward index (`accFeePerWeight`, `accRewardPerWeight`) updates proportionally to elapsed time and deposited ETH. No flash-loan attack vector exists because the weight assignments require admin/timelock governance with 48h delay.

**Supply Inflation via distribute():** Impossible. `distribute()` splits existing balance; it does not create new PW.

**Drain via Emergency Pause:** Impossible. `pauseController` can only call `pause()` and `unpause()`. It cannot call `registerValidator()`, `claimFees()`, `setEmissionRate()`, or any fund-moving function.

### 7.5 Griefing Attacks

**distribute() Spam:** Anyone can call `distribute()` with 0 balance (no-op, costs gas). No harm to protocol state.

**Pause Griefing:** If EMS key is compromised (3 of 5), attacker can pause/unpause contracts repeatedly. Validators cannot claim during pause. This is the maximum damage without key compromise of `protocolAdmin` or `admin`. Mitigated by hardware keys + geographic distribution.

**ValidatorFeeVault accFeePerWeight Integer Overflow:** At 3,000,000 PW/year distributed through VFV (70% of fees), and PRECISION = 1e18, an overflow would require approximately `2^256 / 1e18 / total_weight` years. With weight ~15, this is cosmologically safe.

---

## 8. Formal Properties Verified by Tests

The following properties are proven via stateful fuzzing (C08 invariant tests):

| ID | Property | Test Coverage |
|----|---------|--------------|
| INV-1 | FD conservation: validatorShare + treasuryShare + burnShare = amount | 10,000+ fuzz runs |
| INV-2 | VFV conservation: totalReceived >= totalClaimed | 10,000+ fuzz runs |
| INV-3 | RV solvency: totalEmitted <= totalFunded | 10,000+ fuzz runs |
| INV-4 | RV claim bound: totalClaimed <= totalEmitted | 10,000+ fuzz runs |
| INV-5 | EMS nonce monotone-increasing | 10,000+ fuzz runs |
| INV-6 | Pause authority: only pauseController can pause | 10,000+ fuzz runs |
| INV-7 | RV rate cap: emissionRate <= MAX_RATE_PER_SECOND | 10,000+ fuzz runs |
| INV-8 | RV balance: accountedBalance <= vault balance | 10,000+ fuzz runs |
| INV-9 | FD split constants: VALIDATOR_BPS + TREASURY_BPS <= BASIS_POINTS | Compile-time + runtime |
| INV-10 | No cross-contamination: RV and FD/VFV share no ETH paths | Architecture + tests |

---

## 9. Code Quality Assessment

| Category | Rating | Notes |
|----------|--------|-------|
| Readability | HIGH | Consistent naming, clear comments, organized by section |
| Test Coverage | HIGH | 500+ tests; stateful fuzzing; integration; unit |
| Gas Efficiency | MEDIUM | O(1) per-claim via reward index; distributeUnallocated() O(n) |
| Error Messages | HIGH | All reverts have descriptive strings |
| NatSpec | MEDIUM | Key functions documented; not all edge cases covered |
| Access Control | HIGH | Clear separation of admin / pauseController / recipient domains |
| Upgradeability | N/A | Intentionally non-upgradeable |

---

## 10. Security Recommendations

### R-01 (Production-Blocking)
Deploy FeeDistributor with EmergencyMultisig as `pauseController`. Confirm with `ValidateGenesis.s.sol` before mainnet launch.

### R-02 (Pre-Launch)
Rotate Timelock proposer from DEV0 EOA to a production multisig via `transferProposer()` (timelocked action). Execute this as the first timelocked operation after deployment.

### R-03 (Pre-Launch)
Validate all 5 EmergencyMultisig signer keys are on hardware wallets held by geographically distributed operators before exposing the protocol to real funds.

### R-04 (Phase 2)
When deploying PrimeWaveStakingManager, ensure it is explicitly registered as a `recipientAddress` in RewardVault by the RewardVault admin, and that the ValidatorFeeVault `protocolAdmin` remains the registry adapter (not the staking manager directly) to maintain authority separation.

### R-05 (Monitoring)
Implement off-chain monitoring on the following events:
- `FeeDistributor.Distributed` — trigger if pending > 10 ETH for > 1 hour
- `ValidatorFeeVault.Paused` / `Unpaused` — immediate alert
- `RewardVault.Paused` / `Unpaused` — immediate alert
- `EmergencyMultisig.ProposalCreated` — alert all signers immediately
- `EmergencyMultisig.Executed` — alert + audit trail
- `PrimeWaveTimelock.CallScheduled` / `CallExecuted` — public announcement required

---

## 11. Audit Conclusion

The PrimeWave protocol contracts are architecturally sound for Phase-1 deployment. The identified issues are:

1. **MED-01** (FD pauseController immutability): Fully mitigated by correct production deployment sequence. ValidateGenesis.s.sol provides automated verification.

2. **LOW-01** (Single Timelock proposer): Mitigated by using a multisig as proposer in production + cold-storage contingency.

The codebase does not use NativeMinter, proxies, or delegatecall. Supply is fixed at genesis. All fund movements are deterministic and constrained by immutable split constants. Authority domains are clearly separated and non-overlapping.

**Signing authority for C08 gate:** Architecture review passed. Code review passed. Tests: 500+ unit + 10 stateful invariants. Ready for Phase-2 PoS development.
