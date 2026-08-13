# PrimeWave Chain — Governance Policy
**Sprint PW-C00 Pre-C01 Gate | August 13, 2026**
**Status: DESIGN DOCUMENT — NOT FOR PRODUCTION. No keys generated. No deployment.**

---

## 1. Overview

This document defines PrimeWave Chain's governance architecture: the roles that control the protocol, the timelock rules that protect it, and the emergency powers that can act faster when security demands it.

---

## 2. Governance Roles

### 2.1 Role Registry

| Role | Mechanism | Scope | Separate from other roles |
|---|---|---|---|
| Protocol Admin | Multisig + 48h TimelockController | Contract upgrades, parameter changes | YES |
| Treasury Admin | Separate multisig + 48h TimelockController | Treasury PW and fee disbursement | YES — separate from Protocol Admin |
| Emergency Multisig | 3-of-5 multisig, NO timelock for pause/freeze only | Pause/freeze actions listed below | YES — strictly limited scope |
| Monetary Authority | Single designated role (PLACEHOLDER) | PWUSD mint and burn only | YES |
| Validator Admin | Protocol Admin multisig via PoAManager | Validator registration/removal (Phase 1) | Inherits Protocol Admin |

> Each role must be held by different signers with different key material. No single person may hold keys in more than one governance role simultaneously without explicit PrimeWave leadership approval.

---

## 3. 48-Hour Timelock (OQ-016 RESOLVED)

**Decision (locked August 13, 2026):** 48-hour minimum timelock for all ordinary protocol and treasury administrative changes.

### 3.1 Timelock Implementation

```solidity
// OpenZeppelin TimelockController
// minDelay = 48 hours = 172,800 seconds

TimelockController protocolTimelock = new TimelockController(
    172_800,          // minDelay: 48 hours
    proposers,        // Protocol Admin multisig
    executors,        // Protocol Admin multisig (or open executor)
    admin             // address(0) — no admin after init
);
```

### 3.2 Actions Subject to 48-Hour Timelock

ALL of the following require a successful multisig proposal AND must wait 48 hours before execution:

**Protocol contracts:**
- Upgrading any protocol contract behind a proxy
- Changing the owner of any protocol contract
- Changing gas fee parameters (gasLimit, minBaseFee, targetGas)
- Changing the FeeDistributor split percentages (70/20/10)
- Changing the RewardVault emission rate cap
- Adding or removing a validator (Phase 1 PoA)
- Changing validator weight (Phase 1 PoA)
- Changing the MONETARY_AUTHORITY_ROLE assignment (PWUSD)
- Changing the Emergency Multisig address composition
- Changing any TimelockController parameter (including minDelay itself)

**Treasury:**
- Disbursing PW or other tokens from Treasury to any address
- Approving any Treasury grant or partnership payment
- Changing Treasury multisig signers

**PWUSD:**
- Changing mint/burn limits or caps
- Changing the PWUSD oracle or peg mechanism
- Pausing PWUSD (non-emergency)

### 3.3 Actions NOT Subject to Timelock

The following may execute immediately (without timelock) when authorized by the designated role:

| Action | Authorized by |
|---|---|
| Emergency pause of a protocol contract | Emergency Multisig (3-of-5) |
| Emergency freeze of a contract | Emergency Multisig (3-of-5) |
| PWUSD emergency pause | Emergency Multisig (3-of-5) |
| Validator uptime proof submission | Any authorized keeper |
| Reward claim | Any eligible validator/delegator |
| FeeDistributor.distribute() call | Any authorized keeper |

### 3.4 Timelock Execution Process

```
Day 0: Protocol Admin multisig proposes a change via TimelockController.schedule(...)
Day 0: Change is public on-chain for 48 hours — community can review
Day 2 (after 48h): Protocol Admin multisig calls TimelockController.execute(...)
       → Change takes effect
```

---

## 4. Emergency Multisig (OQ-013 RESOLVED)

**Decision (locked August 13, 2026):** 3-of-5 multisig with narrowly scoped emergency powers.

### 4.1 Configuration

| Parameter | Value |
|---|---|
| Threshold | 3-of-5 (any 3 of 5 signers must approve) |
| Signers | 5 designated PrimeWave signers (identities determined at deployment) |
| Hardware requirement | Hardware wallet mandatory for every signer — see `PRIMEWAVE_KEY_SECURITY_PROCEDURE.md` |
| Geographic requirement | Signers in at least 3 different geographic locations |
| Key separation | No signer may also hold Protocol Admin, Treasury Admin, or Monetary Authority keys |

### 4.2 Authorized Emergency Powers (Exhaustive List)

The Emergency Multisig may ONLY do the following:

| Action | Target Contract | Effect |
|---|---|---|
| `pause()` on PrimeWaveStakingManager | PrimeWaveStakingManager | Halts new staking/delegation/claims; running validators unaffected |
| `pause()` on RewardVault | RewardVault | Halts reward claims; vault balance unchanged |
| `pause()` on ValidatorFeeVault | ValidatorFeeVault | Halts fee distribution claims |
| `pause()` on FeeDistributor | FeeDistributor | Halts fee splits; fees accumulate in contract |
| `pause()` on PWUSD | PWUSD | Halts all PWUSD transfers, mints, and burns |
| `freeze(account)` on PWUSD | PWUSD | Blocks a specific account from PWUSD transfers (AML/sanctions compliance only) |
| `unpause()` on any of the above | Any paused contract | Restores normal operation |

All other actions — including upgrade, fund transfer, validator set changes, and supply changes — require the full Protocol Admin multisig + 48-hour timelock process, even in an emergency.

### 4.3 What the Emergency Multisig CANNOT Do

The following are **absolutely forbidden** for the Emergency Multisig, with no exceptions:

- Transfer, move, or approve any PW or other token from Treasury, RewardVault, or ValidatorFeeVault
- Modify any user's token balance
- Mint PW or any other token
- Change the PW total supply
- Bypass the 48-hour timelock for any non-pause/freeze action
- Add, remove, or change the weight of any validator
- Upgrade any contract
- Change any governance role or signer address
- Recover or redirect user funds

### 4.4 Emergency Response Process

```
1. Security event detected by any party
2. Alert emergency multisig signers (out-of-band secure channel)
3. Signers confirm severity independently before signing
4. 3-of-5 approval: Emergency Multisig calls pause() on affected contract
5. Event is investigated; root cause identified
6. If incident is resolved:
   Protocol Admin multisig + timelock calls unpause() after review
7. If contract must be upgraded or funds recovered:
   Full Protocol Admin + 48h timelock process — Emergency Multisig CANNOT do this
8. Post-mortem published within 72 hours of resolution
```

### 4.5 Pause vs. Emergency Upgrade

A pause is a temporary state — no funds are moved, no balances changed, no upgrades made. If an incident requires an upgrade or fund recovery (e.g., a critical bug), that upgrade MUST go through the Protocol Admin multisig + 48h timelock. The Emergency Multisig cannot short-circuit this.

If 48 hours is too slow for a critical incident: PrimeWave may, at a future governance vote, add a `guardianUpgrade` path with a shorter timelock (e.g., 12h) that requires both Emergency Multisig and Protocol Admin agreement. This is NOT in scope for Phase 1.

---

## 5. Monetary Authority

**Decision (OQ-005, locked):** Single designated role, NOT automatically a multisig.

- Role: `MONETARY_AUTHORITY_ROLE`
- Address: `PLACEHOLDER` — configured during secure deployment per `PRIMEWAVE_KEY_SECURITY_PROCEDURE.md`
- Powers: PWUSD mint and burn ONLY
- Cannot be exercised while PWUSD is paused by Emergency Multisig

---

## 6. Role Separation Matrix

This matrix verifies that no governance action creates a conflict-of-interest concentration:

| Role | Can transfer Treasury funds | Can mint PW | Can pause contracts | Can upgrade contracts | Can change validators |
|---|---|---|---|---|---|
| Protocol Admin (multisig + 48h TL) | NO (Treasury has separate role) | NO | NO | YES | YES (Phase 1 PoA) |
| Treasury Admin (multisig + 48h TL) | YES (own Treasury only) | NO | NO | NO | NO |
| Emergency Multisig (3-of-5) | **NO** | **NO** | YES (pause/unpause only) | **NO** | **NO** |
| Monetary Authority | NO | YES (PWUSD only, not PW) | NO | NO | NO |
| Validator Admin | NO | NO | NO | NO | YES (Phase 1, via Protocol Admin) |

---

## 7. Future Governance Upgrades

The following are NOT in scope for Phase 1 but are acknowledged:

- On-chain governance token voting (e.g., PW-weighted votes replacing multisig)
- Shorter emergency upgrade timelock (12h guardian path)
- Multisig for Monetary Authority (if instructed)
- Governance council expansion beyond 5 emergency signers

---

*This document is a PW-C00 Pre-C01 Gate specification. No production deployment has occurred.*
