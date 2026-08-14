# PrimeWave Chain — Key Security Procedure
**Sprint PW-C00 Pre-C01 Gate | August 13, 2026**
**Status: PROCEDURE DOCUMENT — NOT FOR PRODUCTION USE DURING PW-C00/PW-C01**

---

> **ABSOLUTE RULE:** No production private keys may be generated, stored, or used during PW-C00 or PW-C01 development phases. All key generation and ceremony activities described in this document take place only at the designated production deployment event, after explicit PrimeWave leadership approval.

---

## 1. Roles Requiring Key Security Procedures

| Role | Mechanism | Signer Count | Hardware Required |
|---|---|---|---|
| Protocol Admin | Multisig + 48h Timelock | 5 signers (threshold: 3-of-5) | YES — all signers |
| Treasury Admin | Separate multisig + 48h Timelock | 5 signers (threshold: 3-of-5) | YES — all signers |
| Emergency Multisig | 3-of-5 multisig | 5 signers (threshold: 3-of-5) | YES — all signers |
| Monetary Authority | Single designated role | 1 designated holder | YES |
| Validator Admin | Via Protocol Admin multisig | N/A (uses Protocol Admin keys) | YES — inherited |
| Validator Node Keys | Per-validator BLS + NodeID | 1 per validator | YES — recommended |

---

## 2. Hardware-Backed Signing Requirements

### 2.1 Required Hardware

Every signer must hold their key on a hardware security device. Acceptable devices:

| Device | Acceptable | Notes |
|---|---|---|
| Ledger Nano X / Nano S Plus / Stax | ✅ YES | Preferred for EVM multisig (supports MetaMask + WalletConnect integration) |
| Trezor Model T / Safe 3 | ✅ YES | Full EVM support |
| Keystone Pro | ✅ YES | Air-gapped; QR-code signing |
| GridPlus Lattice1 | ✅ YES | Hardware smart card |
| Software wallet (MetaMask, etc.) | ❌ NO | Forbidden for governance roles |
| Exchange custody | ❌ NO | Forbidden |
| Any cloud-based key storage | ❌ NO | Forbidden |
| Paper wallet alone (no hardware) | ❌ NO | Forbidden for active signing |

### 2.2 Firmware Requirement

All hardware wallets must:
- Run the latest stable firmware before the deployment ceremony
- Verify firmware authenticity via the manufacturer's verification process
- Update firmware before the ceremony if not already current

---

## 3. Key Generation

### 3.1 Generation Environment

Keys must be generated on the hardware wallet device itself — NOT on a computer and then imported.

**Process:**
1. Power on a factory-reset hardware wallet (or reset an existing one)
2. Use the device's built-in seed generation (do not import a seed)
3. Verify the device is genuine (check manufacturer authenticity verification)
4. Record the seed phrase ONLY on the device's screen — never on a computer, phone, camera, or networked device

### 3.2 Derivation Path

Use the standard EVM derivation path:
```
m/44'/60'/0'/0/0    (Ledger / MetaMask compatible)
```

Document the derivation path used for each signer's key in the deployment log.

### 3.3 Prohibited Generation Methods

The following are absolutely forbidden for production governance keys:
- Generating a seed on a computer and importing to hardware
- Using `cast wallet new` or any CLI keygen tool for production keys
- Generating keys on a networked machine, even temporarily
- Using any online key generation service

---

## 4. Seed Phrase Backup

### 4.1 Backup Material

Each signer must back up their 24-word seed phrase using at least one of:

| Method | Notes |
|---|---|
| Cryptosteel / Bilodal / similar metal backup | Recommended — fireproof, waterproof |
| Official hardware wallet backup card (laminated, stored securely) | Acceptable for interim use |
| Shamir's Secret Sharing (SSS) across 3+ physically separated locations | Recommended for critical roles |
| Encrypted digital backup | Forbidden unless air-gapped and offline-only |

### 4.2 Physical Security for Backup

- No seed phrase backup may be stored in the same physical location as the hardware wallet
- No two backup copies for the same seed may be in the same building
- Backup locations must be physically secure (safe, vault, or equivalent)
- At least one backup must survive a building fire/flood at the primary location

### 4.3 Backup Verification

Each signer must verify their backup is correct BEFORE the deployment ceremony by:
1. Resetting the hardware wallet
2. Restoring from the seed backup
3. Verifying the derived address matches the original
4. Resetting and re-generating (or re-confirming device seed)

Document verification in the deployment ceremony record.

---

## 5. Key Recovery

### 5.1 Signer Device Loss / Failure

If a signer's hardware wallet is lost, stolen, or fails:

1. The signer immediately notifies the PrimeWave security contact
2. The signer restores their seed phrase onto a new hardware wallet
3. Verify the restored address matches the original
4. If the device was stolen (not failed), the signer notifies all multisig co-signers and PrimeWave leadership — consider a key rotation ceremony

### 5.2 Seed Phrase Loss

If a signer loses their seed phrase AND their hardware wallet simultaneously (catastrophic loss):
- The signer notifies PrimeWave leadership immediately
- The multisig threshold (3-of-5) still allows other signers to operate
- A key rotation ceremony is triggered (see Section 7)
- The affected signer is replaced with a new signer and new key

### 5.3 Compromised Key

If a signer suspects their private key has been compromised (exposed, phished, hardware tampered):
1. Immediately notify PrimeWave security contact
2. DO NOT use the potentially compromised key for any further signing
3. Initiate emergency key rotation (see Section 7)
4. Protocol Admin multisig + 48h timelock rotates the compromised address out

---

## 6. Signer Separation Requirements

### 6.1 Role Separation

No single person may hold keys in more than one of the following roles:
- Protocol Admin
- Treasury Admin
- Emergency Multisig
- Monetary Authority

### 6.2 Geographic Separation

For each multisig:
- Signers must be in at least **3 different geographic locations** (cities or countries)
- No single location may hold more than 2 signers' hardware wallets simultaneously
- This ensures a physical disaster at one location does not incapacitate the multisig

### 6.3 Organizational Separation

- Not all signers should be employees of the same organization
- For the Emergency Multisig: at minimum 2 signers should be independent of PrimeWave (e.g., trusted external advisors or community representatives)
- This prevents a single organizational event (e.g., regulatory action, internal dispute) from compromising the multisig

### 6.4 Communication Separation

Signers must use different communication channels than the team:
- Emergency coordination: separate secure channel (Signal or equivalent E2E encrypted)
- Signing coordination: authenticated out-of-band channel only
- Never coordinate signing via unencrypted email or public chat

---

## 7. Key Rotation

### 7.1 Routine Rotation

Routine key rotation is not mandatory but is recommended:
- When a signer leaves their role (departing team member, etc.)
- Annually as a security hygiene practice
- After any suspected (but unconfirmed) security event

### 7.2 Rotation Process

```
1. New signer generates a new key on a hardware wallet (per Section 3)
2. New address is proposed via Protocol Admin multisig + 48h timelock
3. After timelock: old address removed, new address added
4. Old hardware wallet seed is securely destroyed (see Section 9)
5. New signer performs testnet verification before mainnet role
```

### 7.3 Emergency Rotation

If a key compromise is confirmed:
1. Emergency Multisig cannot rotate Protocol Admin (that requires Protocol Admin + timelock)
2. Remaining Protocol Admin signers (≥ 3-of-5 minus compromised) use the existing threshold to propose and execute rotation
3. The 48h timelock applies unless a shorter guardian path is activated (not in Phase 1 scope)
4. During the 48h window, all signers must be on high alert — the compromised signer cannot unilaterally act

---

## 8. Emergency Key Recovery

### 8.1 Threshold Survivability

PrimeWave governance is designed to survive any single-signer incident:

| Scenario | Can Protocol Continue? |
|---|---|
| 1 signer's device fails | YES — 4 remaining signers can reach 3-of-5 threshold |
| 1 signer's seed lost | YES — other signers continue; rotate within 7 days |
| 1 signer compromised/hostile | YES — remaining 4 refuse to co-sign malicious txs |
| 2 signers simultaneously incapacitated | YES — 3 remain, threshold is met |
| 3 signers simultaneously incapacitated | ❌ Governance halted — escalate to PrimeWave leadership immediately |

### 8.2 Recovery for Governance Halt

If fewer than 3 signers are operational (governance halted):
1. PrimeWave leadership activates the documented continuity plan
2. New signers are onboarded (standard process, not emergency)
3. This requires an in-person or video-verified key generation ceremony
4. No shortcuts: new keys must meet all requirements in this document

---

## 9. Secure Key Destruction

When a signing key must be retired:

1. Transfer all governance role powers to a new key FIRST (full rotation per Section 7)
2. Confirm the new key is operational and the role transfer is confirmed on-chain
3. Reset the hardware wallet (factory reset / wipe) using the device's secure erase function
4. Physically destroy the seed phrase backup if it will not be reused
   - Metal backup: drilling, shredding, or incineration
   - Paper backup: cross-cut shredding + destruction
5. Document the destruction date in the deployment log

---

## 10. Testnet Rehearsal

**Before any mainnet deployment, the following testnet rehearsal MUST be completed:**

### 10.1 Rehearsal Requirements

- [ ] All 5 signers for each multisig have generated testnet keys per this procedure (using the same hardware, different seed)
- [ ] All multisigs are deployed and configured on Fuji (Avalanche testnet) or PrimeWave testnet
- [ ] Each multisig has successfully proposed and executed at least 3 test operations
- [ ] Emergency Multisig has successfully paused and unpaused each contract type on testnet
- [ ] Monetary Authority has successfully minted and burned PWUSD on testnet
- [ ] At least one signer rotation has been completed on testnet (end-to-end)
- [ ] At least one "disaster scenario" rehearsal: 2 signers unavailable, operation still completes
- [ ] Document time-to-complete for emergency pause: target ≤ 30 minutes from alert to on-chain

### 10.2 Rehearsal Documentation

Each rehearsal must produce:
- Testnet transaction hashes for all operations
- Time-to-completion for emergency scenarios
- Any deviations from expected procedure
- Sign-off from PrimeWave leadership

---

## 11. Production Deployment Ceremony

The production deployment ceremony is a structured event — NOT a casual deployment. It must be planned and documented in advance.

### 11.1 Ceremony Prerequisites

- [ ] All testnet rehearsals completed and documented
- [ ] All signers have generated and verified their production keys per this procedure
- [ ] All signer addresses are collected and verified (multi-step confirmation)
- [ ] Genesis file reviewed and hash verified by ≥ 3 independent parties
- [ ] Contracts reviewed and deployment bytecode hash verified by ≥ 3 independent parties
- [ ] Legal review of icm-services license completed
- [ ] All PW-C00 open questions resolved (see `PW-C00-FINAL-GATE.md`)
- [ ] PW-C01 implementation complete, tested, and audited
- [ ] Explicit PrimeWave leadership sign-off

### 11.2 Ceremony Structure

```
PRE-CEREMONY (day before):
  - All signers confirm hardware wallet readiness
  - All signers confirm they can sign transactions on ceremony day
  - Deployment bytecode and genesis hash distributed for final review

CEREMONY DAY:
  - Secure communication channel opened (Signal or equivalent)
  - Deployment wallet funds confirmed (for gas only)
  - Contracts deployed in order:
      1. TimelockController (Protocol Admin)
      2. TimelockController (Treasury Admin)
      3. PoAManager (referencing Protocol Admin timelock)
      4. RewardVault
      5. FeeDistributor
      6. ValidatorFeeVault
      7. PWUSD (with PLACEHOLDER Monetary Authority)
  - Each deployment: bytecode hash verified before broadcast
  - Genesis block created with correct alloc
  - L1 creation sequence executed (CreateSubnetTx → CreateChainTx → ConvertSubnetToL1Tx)
  - PoAManager.initializeValidatorSet() called
  - All 15 validators confirmed
  - MONETARY_AUTHORITY_ROLE transferred to final address (on-chain, with confirmation)
  - Deployment log signed by all key holders

POST-CEREMONY:
  - Verify all contract addresses match expected (compare to pre-deployment commitments)
  - Verify RewardVault balance = 15,000,000 PW
  - Verify total supply = 100,000,000 PW
  - Verify no NativeMinter is activated
  - Verify FeeDistributor routing is correct
  - Verify all 15 validators are active
  - Public announcement with contract addresses and genesis hash
```

### 11.3 No-Keys-During-Development Rule

Until the production deployment ceremony is formally scheduled and prerequisite-gated:
- No production-bound private keys are generated
- No "we'll use this testnet key for now" exceptions
- Placeholder addresses are used in all contracts during testing
- All development signing uses throwaway keys generated fresh per test run

---

## 12. Validator Node Keys

Each of the 15 initial validators requires:

| Key Type | Purpose | Security Level |
|---|---|---|
| NodeID key (ED25519) | P-Chain node identity | Hardware or HSM recommended |
| BLS public key | Validator registration on PoAManager | Public — derived from BLS private key |
| BLS private key | Signs Warp messages | Hardware or HSM required |

### 12.1 Validator Key Requirements

- Each validator operator is responsible for their own key security
- BLS private keys must not be stored on the same machine as the AvalancheGo node process
- NodeID and BLS keys should be generated in the same secure environment described in Section 3
- Validator operators must acknowledge this procedure before being registered on-chain

---

*This document defines the security procedure. No production keys have been generated during PW-C00/PW-C01. Execution of this procedure begins only after all prerequisites in `PW-C00-FINAL-GATE.md` are satisfied and explicit approval is received.*

---

## 13. EMS Signer Rotation Procedure (C11)

EmergencyMultisig signers are **immutable** after construction. There is no `updateSigner()` function. Rotation requires deploying a new EMS and transferring the `pauseController` role on all governed contracts.

### 13.1 When Rotation is Needed

- Compromise of an EMS signer key (confirmed or suspected)
- Scheduled rotation (annual recommended)
- Signer departure from the team

### 13.2 Rotation Steps

**Step 1:** Prepare new signer set (5 new hardware wallet addresses).

**Step 2:** Deploy new `EmergencyMultisig` contract with updated signers:
```bash
forge script contracts/script/DeployNewEMS.s.sol \
  --rpc-url $CHAIN_RPC_URL \
  --broadcast \
  --private-key $DEPLOYER_KEY
```

**Step 3:** Via Protocol Admin + 48h Timelock, call `setPauseController(newEmsAddress)` on each governed contract:
- `FeeDistributor`
- `ValidatorFeeVault`
- `RewardVault`
- `PrimeWaveTimelock` (if applicable)

**Step 4:** Wait 48h for timelock delay to expire. Execute the queued transactions.

**Step 5:** Verify old EMS no longer has `pauseController` on any contract.

**Step 6:** Old EMS signers destroy or archive (mark inactive) their key material per Section 7.

### 13.3 Security Notes

- This rotation requires NO new governance power — it goes through the existing Protocol Admin + 48h Timelock path
- The new EMS must have 5 signers and THRESHOLD = 3 (compile-time constant — enforced by `EmergencyMultisig` constructor)
- Document the new signer addresses in `docs/PRIMEWAVE_INFRASTRUCTURE.md`

---

*Updated C11: EMS rotation procedure added (resolves SEC-L-01 from C10 audit).*
