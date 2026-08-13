# PrimeWave Chain — Security Threat Model
**Sprint PW-C00 | Status: DESIGN DOCUMENT — NOT FOR PRODUCTION**

---

## 1. Overview

This document provides a preliminary threat model for all components of the PrimeWave ecosystem. It covers threats, their likelihood, impact, and recommended mitigations.

Risk ratings: 🔴 Critical | 🟠 High | 🟡 Medium | 🟢 Low

---

## 2. Blockchain / Consensus Threats

### 2.1 Validator Compromise
**Rating:** 🔴 Critical (if ≥5 of 15 initial validators compromised)
- **Threat:** An attacker compromises validator node(s) — steals private keys, takes remote control
- **Impact:** Biased block production, censorship, potential consensus failure above threshold
- **Mitigations:**
  - Validator node keys stored in HSM (Hardware Security Module) or equivalent
  - Validator nodes on isolated, hardened servers (no public SSH access)
  - Key rotation procedure documented and tested
  - Monitoring / alerting on validator behavior anomalies
  - Geographic distribution of validators

### 2.2 Validator Collusion
**Rating:** 🟠 High (requires ≥2/3 weight)
- **Threat:** Multiple validators collude to manipulate block ordering or double-sign
- **Impact:** Double-spend attacks, transaction censorship
- **Mitigations:**
  - Snowman++ BFT requires ≥2/3 honest validators — 15 validators gives strong guarantees if <5 are malicious
  - Diverse validator operator selection (PrimeWave + independent operators)
  - Slashing for provable collusion (double-sign)
  - Monitor for voting pattern anomalies

### 2.3 Sybil Attack
**Rating:** 🟡 Medium (Phase 1) / 🟠 High (Phase 2)
- **Threat:** Attacker registers many validators under different identities
- **Impact:** Disproportionate consensus influence
- **Mitigations (Phase 1):** PoAValidatorManager — only admin can register validators, Sybil attack impossible by design
- **Mitigations (Phase 2):** Minimum stake requirement; stake-weighted consensus limits influence per validator

### 2.4 Network Partition
**Rating:** 🟡 Medium
- **Threat:** Network split causes validators to see different chain states
- **Impact:** Temporary fork; after healing, shorter chain is abandoned
- **Mitigations:**
  - Snowman++ is resistant to network partitions (liveness over safety tradeoff)
  - Validators on diverse cloud providers and geographic regions
  - WebSocket RPC monitoring for fork detection

### 2.5 Consensus Failure / Chain Halt
**Rating:** 🟠 High
- **Threat:** Bug in AvalancheGo or Subnet-EVM causes chain halt
- **Impact:** Complete network unavailability
- **Mitigations:**
  - Use only stable, production-tested AvalancheGo/Subnet-EVM releases
  - Version lock at testnet; upgrade only after testnet validation
  - Emergency recovery procedure documented
  - Regular AvalancheGo upstream security patch tracking

### 2.6 RPC Compromise
**Rating:** 🟠 High
- **Threat:** Public RPC nodes are compromised, serve malicious data
- **Impact:** Wallets/applications receive incorrect chain state
- **Mitigations:**
  - Multiple independent RPC endpoints
  - TLS for all RPC connections
  - Rate limiting on public RPC
  - Application-level RPC response verification where possible
  - Private RPC for sensitive operations (treasury, governance)

### 2.7 Key Compromise (Node Keys)
**Rating:** 🔴 Critical
- **Threat:** Validator BLS private key or P-Chain key is stolen
- **Impact:** Attacker can act as that validator; potential double-signing
- **Mitigations:**
  - Keys stored offline / in HSM
  - Keys NEVER generated or stored on internet-connected systems
  - Key rotation procedure tested on testnet before mainnet

---

## 3. PW Token Threats

### 3.1 Unauthorized Minting
**Rating:** 🔴 Critical
- **Threat:** Someone enables the NativeMinter precompile or finds another mint pathway
- **Impact:** Supply inflation, destruction of economic model
- **Mitigations:**
  - NativeMinter precompile NOT activated in genesis
  - Genesis file cryptographically committed (hash documented)
  - No address granted minter role
  - Chain launch procedure verified independently before go-live

### 3.2 Supply Inflation
**Rating:** 🔴 Critical (see 3.1)
- Covered by 3.1. Additional mitigation: on-chain supply monitoring via indexer alert.

### 3.3 Genesis Allocation Error
**Rating:** 🔴 Critical
- **Threat:** Incorrect amounts in genesis `alloc` block (wrong address, wrong amount)
- **Impact:** Permanent — genesis is immutable
- **Mitigations:**
  - Genesis file reviewed by ≥3 independent parties before launch
  - Genesis file tested on testnet with identical parameters
  - Automated script to verify genesis `alloc` totals = 100,000,000 PW before launch
  - Genesis hash documented; chain start verified against expected hash

### 3.4 Unauthorized PW Transfer
**Rating:** 🟡 Medium
- **Threat:** Private key to allocation address is stolen before distribution
- **Impact:** Theft of presale, treasury, or team funds
- **Mitigations:**
  - All large allocations sent to multisig addresses at genesis, not single EOAs
  - Multisig setup tested before mainnet genesis

---

## 4. PWUSD Threats

### 4.1 Unauthorized Mint
**Rating:** 🔴 Critical
- **Threat:** Non-authority address mints PWUSD
- **Impact:** PWUSD supply inflation, potential economic damage
- **Mitigations:**
  - `onlyRole(MONETARY_AUTHORITY_ROLE)` enforced in contract
  - Smart contract audit required
  - Role assignment verified post-deploy

### 4.2 Monetary Authority Compromise
**Rating:** 🔴 Critical
- **Threat:** Monetary Authority multisig key(s) stolen
- **Impact:** Unlimited PWUSD minting
- **Mitigations:**
  - Monetary Authority MUST be a multisig (minimum 3-of-5)
  - Signers on separate hardware wallets, different geographic locations
  - Alert threshold: if PWUSD total supply increases by >X% in 24h, trigger investigation

### 4.3 Excessive Minting
**Rating:** 🟠 High
- **Threat:** Monetary Authority mints far more PWUSD than business needs justify
- **Impact:** Inflation, ecosystem damage
- **Mitigations:**
  - On-chain event monitoring (every mint emits Minted event)
  - Optional: governance-enforced mint caps per period

### 4.4 Role Escalation
**Rating:** 🟠 High
- **Threat:** Monetary Authority role is used to gain other roles
- **Impact:** Unauthorized control of other systems
- **Mitigations:**
  - AccessControl: Monetary Authority role grants ONLY mint/burn
  - DEFAULT_ADMIN_ROLE held by separate governance multisig
  - Role separation verified in audit

### 4.5 Unauthorized Burn
**Rating:** 🟡 Medium
- **Threat:** Monetary Authority burns PWUSD from user wallets without consent
- **Impact:** User funds destroyed
- **Mitigations:**
  - Burn function requires explicit `from` address parameter
  - Governance monitoring of all burn events
  - Legal/operational controls on Monetary Authority

### 4.6 Replay Attack
**Rating:** 🟡 Medium
- **Threat:** Signed authorization replayed to mint/burn multiple times
- **Impact:** Unauthorized supply changes
- **Mitigations:**
  - Use standard OpenZeppelin AccessControl (no signature-based mint)
  - If permit-style minting is ever added: EIP-712 nonces required

### 4.7 Accounting Mismatch
**Rating:** 🟡 Medium
- **Threat:** Off-chain accounting of PWUSD income diverges from on-chain reality
- **Impact:** Incorrect income distributions
- **Mitigations:**
  - All PWUSD flows tracked via on-chain events
  - Regular reconciliation between PrimeWave app and on-chain state

---

## 5. PWSwap Threats

### 5.1 Reentrancy
**Rating:** 🔴 Critical
- **Threat:** Malicious token contract re-enters PWSwap during swap execution
- **Impact:** Drain of pool reserves
- **Mitigations:**
  - Reentrancy guard on all state-changing functions
  - Follow check-effects-interactions pattern
  - Formal security audit

### 5.2 Flash-Loan Manipulation
**Rating:** 🟠 High
- **Threat:** Attacker uses flash loans to temporarily manipulate pool price
- **Impact:** Arbitrage profit at LP expense; price oracle manipulation
- **Mitigations:**
  - TWAP oracle (not spot price) for any on-chain price references
  - Slippage protection on all swaps
  - Do not use PWSwap spot price for critical decisions without TWAP

### 5.3 Price Manipulation
**Rating:** 🟠 High (related to 5.2)
- See 5.2. Additional mitigation: PWSwap fee creates friction for rapid manipulation.

### 5.4 Oracle Manipulation
**Rating:** 🟠 High
- **Threat:** If PWSwap TWAP is used as an oracle, manipulation is possible with sufficient capital
- **Impact:** Incorrect price-dependent decisions
- **Mitigations:**
  - Use sufficiently long TWAP windows (minimum 30 minutes)
  - Do not use PWSwap as sole price oracle for critical decisions in V1

### 5.5 Liquidity Theft
**Rating:** 🔴 Critical
- **Threat:** Bug allows attacker to withdraw LP funds without LP tokens
- **Impact:** Complete loss of pooled PW and PWUSD
- **Mitigations:**
  - Formal audit of all liquidity functions
  - Invariant testing: k = x*y must hold after every operation
  - No arbitrary admin withdrawal function

### 5.6 LP Accounting Errors
**Rating:** 🟠 High
- **Threat:** LP token issuance/burning miscalculates share
- **Impact:** LPs receive incorrect amounts on withdrawal
- **Mitigations:**
  - Foundry invariant tests on LP share calculation
  - Audit

### 5.7 Fee Accounting Errors
**Rating:** 🟡 Medium
- **Threat:** 0.30% fee is incorrectly calculated or routed
- **Impact:** Treasury receives less than expected; or users overpay
- **Mitigations:**
  - Unit tests for fee calculation
  - Fuzz tests for edge cases (very small/large trades)

---

## 6. Governance Threats

### 6.1 Multisig Compromise
**Rating:** 🔴 Critical
- **Threat:** Majority of multisig signers are compromised simultaneously
- **Impact:** Attacker gains treasury/admin control
- **Mitigations:**
  - Minimum 3-of-5 multisig (consider 4-of-7 for treasury)
  - Signers on separate hardware wallets
  - Signers in different geographic jurisdictions
  - No single person holds multiple signer keys

### 6.2 Timelock Bypass
**Rating:** 🟠 High
- **Threat:** Attacker finds a way to execute governance actions before timelock expires
- **Impact:** Unauthorized changes without community review window
- **Mitigations:**
  - Use audited OpenZeppelin TimelockController
  - Minimum timelock: 48 hours for normal governance; 7 days for large operations
  - No bypass function

### 6.3 Malicious Upgrade
**Rating:** 🟠 High
- **Threat:** Malicious contract upgrade replaces contract logic with attacker code
- **Impact:** Complete control of upgraded contract
- **Mitigations:**
  - All upgrades require multisig + timelock
  - Upgrade process must include public announcement period
  - Emergency multisig can pause contracts but NOT upgrade them

### 6.4 Emergency Authority Abuse
**Rating:** 🟠 High
- **Threat:** Emergency multisig is used beyond its intended scope
- **Impact:** Unauthorized pausing or fund seizure
- **Mitigations:**
  - Emergency multisig can ONLY pause/unpause contracts
  - Emergency multisig CANNOT withdraw funds, mint tokens, or upgrade contracts
  - Emergency actions are time-limited (auto-unpause after N hours if not renewed)
  - All emergency actions emit events and are publicly visible

---

## 7. Infrastructure Threats

### 7.1 RPC Failure
**Rating:** 🟠 High
- **Threat:** Primary RPC nodes go offline
- **Impact:** Applications and wallets lose chain access
- **Mitigations:**
  - Multiple geographically distributed RPC nodes
  - Load balancer with health checks
  - Fallback RPC endpoints published
  - Monitoring with automated alerting

### 7.2 Database Corruption (Indexer)
**Rating:** 🟠 High
- **Threat:** Indexer database is corrupted or deleted
- **Impact:** Market data and historical chain data unavailable
- **Mitigations:**
  - Regular automated backups (daily minimum)
  - Point-in-time recovery capability
  - Indexer can resync from chain from block 0 (chain is the source of truth)

### 7.3 Indexer Corruption
**Rating:** 🟡 Medium
- **Threat:** Indexer processes events incorrectly, producing wrong market data
- **Impact:** Incorrect prices/volumes shown to users
- **Mitigations:**
  - Periodic cross-check of indexed data against on-chain state
  - Alert on significant deviations between indexed state and RPC query results

### 7.4 DDoS
**Rating:** 🟠 High
- **Threat:** Denial-of-service attack on RPC or infrastructure
- **Impact:** Chain access unavailable to legitimate users
- **Mitigations:**
  - Rate limiting on public RPC
  - Cloudflare or equivalent DDoS protection on public endpoints
  - Private RPC for critical operations (treasury, governance) not exposed publicly

### 7.5 Credential Leakage
**Rating:** 🔴 Critical
- **Threat:** Infrastructure credentials (cloud provider, database, etc.) are leaked
- **Impact:** Attacker gains control of infrastructure
- **Mitigations:**
  - All credentials stored in secrets management system (never in code, config files, or environment variables in plaintext)
  - Principle of least privilege for all service accounts
  - Regular credential rotation
  - Secret scanning in CI/CD

### 7.6 Validator Key Theft
**Rating:** 🔴 Critical (see Blockchain section 2.7)
- **Threat:** Validator signing keys are stolen from server
- **Impact:** Attacker impersonates validator
- **Mitigations:** See Section 2.7

---

## 8. Summary Risk Register

| ID | Threat | Rating | Status |
|---|---|---|---|
| B1 | Validator Compromise | 🔴 Critical | Mitigation designed |
| B2 | Validator Collusion | 🟠 High | Mitigation designed |
| B3 | Sybil Attack | 🟡 Medium (Ph1) / 🟠 High (Ph2) | Mitigated in Ph1 by PoA |
| B4 | Network Partition | 🟡 Medium | Protocol-level mitigation |
| B5 | Chain Halt | 🟠 High | Mitigation designed |
| B6 | RPC Compromise | 🟠 High | Mitigation designed |
| B7 | Key Compromise | 🔴 Critical | Mitigation designed |
| PW1 | Unauthorized Minting | 🔴 Critical | Mitigated by no NativeMinter |
| PW2 | Supply Inflation | 🔴 Critical | Mitigated by fixed genesis |
| PW3 | Genesis Allocation Error | 🔴 Critical | Process controls required |
| PW4 | Unauthorized Transfer | 🟡 Medium | Multisig allocations |
| U1 | PWUSD Unauthorized Mint | 🔴 Critical | Contract + audit |
| U2 | Monetary Authority Compromise | 🔴 Critical | Multisig required |
| U3 | Excessive Minting | 🟠 High | Monitoring + governance |
| U4 | Role Escalation | 🟠 High | AccessControl design |
| U5 | Unauthorized Burn | 🟡 Medium | Operational controls |
| U6 | Replay Attack | 🟡 Medium | Standard AccessControl |
| U7 | Accounting Mismatch | 🟡 Medium | Event monitoring |
| S1 | Reentrancy | 🔴 Critical | ReentrancyGuard + audit |
| S2 | Flash-Loan Manipulation | 🟠 High | TWAP + slippage |
| S3 | Liquidity Theft | 🔴 Critical | Audit + invariant tests |
| G1 | Multisig Compromise | 🔴 Critical | Key hygiene |
| G2 | Timelock Bypass | 🟠 High | Audited timelock |
| G3 | Malicious Upgrade | 🟠 High | Multisig + timelock |
| G4 | Emergency Authority Abuse | 🟠 High | Narrow scope |
| I1 | RPC Failure | 🟠 High | Redundancy |
| I2 | Database Corruption | 🟠 High | Backups + resync |
| I3 | DDoS | 🟠 High | Rate limiting + Cloudflare |
| I4 | Credential Leakage | 🔴 Critical | Secrets management |
| I5 | Validator Key Theft | 🔴 Critical | HSM + offline storage |

---

*This document is a PW-C00 design specification. No production deployment has occurred.*
