# PW-C08 Integrated Architecture Specification

> Sprint: PW-C08 Protocol Integration + Production Configuration Hardening
> Status: COMPLETE
> Date: 2026-08-14

---

## 1. Architecture Overview

PrimeWave Chain is an Avalanche L1 (formerly Subnet) running Subnet-EVM with a fixed 100M PW native asset. The protocol consists of seven on-chain components governed by a two-tier governance architecture. All components are production-immutable (no proxies, no upgrade paths).

```
                    PRIMEWAVE L1 (Chain ID: 73571)
                         |
        +----------------+-----------------+
        |                |                 |
        v                v                 v
 ValidatorManager    Native PW          Governance
 (ACP-99 / Warp)    (100M fixed)       |
        |                |              +-- EmergencyMultisig (3-of-5)
        v                |              +-- PrimeWaveTimelock (48h)
 ValidatorRegistry       v
        |           FeeDistributor
        v                |
 ValidatorFeeVault   +---+---+---+
        |            |   |       |
        |           70%  20%    10%
        |            |   |       |
        +------------+   |       +-- Burn (0x000...dEaD)
                         |
                     DevTreasury

Separate system (parallel, no cross-connection):

15M PW
   |
   v
RewardVault
   |
   v
Future Phase-2 staking rewards (not yet implemented)
```

---

## 2. Component Dependency Map

### 2.1 Complete Table

| Component | Address Source | Deployer | Admin | Pause Authority | Upgrade | Funding Source | Outbound Authority |
|-----------|---------------|----------|-------|-----------------|---------|----------------|-------------------|
| ValidatorManager | ACP-99 / Warp | Avalanche P-Chain | N/A (protocol) | N/A | ACP-99 governance | N/A | P-Chain consensus |
| PrimeWaveValidatorRegistry | CREATE from DEV0 | DEV0 EOA | DEV0 -> multisig | None (no pause) | None (immutable) | None (read-only adapter) | feeVault.registerValidator() |
| ValidatorFeeVault | CREATE nonce 0 (C03) | DEV0 EOA | DEV0 (prod: TL+MS) | EmergencyMultisig | None (immutable) | FeeDistributor.distribute() | recipient.call{value}() |
| FeeDistributor | CREATE nonce 2 (C03) | DEV0 EOA | None (no admin) | EmergencyMultisig | AvalancheGo RewardManager | distribute() -> split | vault/treasury/burn.call{value}() |
| DevTreasury | CREATE nonce 1 (C03) | DEV0 EOA | None (no admin) | None | FeeDistributor | FeeDistributor 20% | Manual (multisig) |
| RewardVault | CREATE from DEV0 | DEV0 EOA | DEV0 (prod: multisig) | EmergencyMultisig | fund() / receive() | claim() -> recipient | recipient.call{value}() |
| EmergencyMultisig | CREATE from DEV0 | DEV0 EOA | None (immutable signers) | Self (cannot pause EMS) | None (immutable) | None | target.call() with pause-domain calls |
| PrimeWaveTimelock | CREATE from DEV0 | DEV0 EOA | None (proposer only) | None | None | None | target.call() with any function |
| Native PW | Genesis alloc | Genesis | None (no minter) | N/A | Genesis only | N/A | N/A |
| Genesis config | genesis.json | Avalanche L1 operators | N/A | N/A | N/A | N/A | N/A |
| Node config | AvalancheGo config | Operators | N/A | N/A | N/A | N/A | N/A |

### 2.2 C03 Genesis Deployment Addresses

These addresses are fixed by deployer nonce and cannot change without redeployment:

| Contract | Expected Address | Nonce |
|----------|-----------------|-------|
| ValidatorFeeVault | `0x5FbDB2315678afecb367f032d93F642f64180aa3` | 0 |
| DevTreasury | `0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512` | 1 |
| FeeDistributor | `0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0` | 2 |

---

## 3. Authority Graph

### 3.1 Complete Authority Inventory

```
EmergencyMultisig (3-of-5)
   |-- pause() on FeeDistributor
   |-- unpause() on FeeDistributor
   |-- pause() on ValidatorFeeVault
   |-- unpause() on ValidatorFeeVault
   |-- pause() on RewardVault
   |-- unpause() on RewardVault
   |-- [PHASE 2] pause() on PWUSD
   |-- [PHASE 2] freeze(account) on PWUSD
   CANNOT:
   |-- mint PW
   |-- move funds
   |-- register validators
   |-- change emission rate
   |-- upgrade contracts
   |-- bypass timelock

PrimeWaveTimelock (via Protocol Admin) [48h delay on all below]
   |-- ValidatorFeeVault.registerValidator()
   |-- ValidatorFeeVault.deactivateValidator() / activateValidator()
   |-- ValidatorFeeVault.setBaseWeight() / setUptimeBips()
   |-- ValidatorFeeVault.setRewardRecipient()
   |-- ValidatorFeeVault.setPauseController() (rotate EMS)
   |-- RewardVault.setEmissionRate() (reduce only)
   |-- RewardVault.setPauseController()
   |-- FeeDistributor: no admin functions (deployer retains nothing)
   |-- Any contract: upgrade (requires redeploy -- no proxy)

ValidatorManager (ACP-99 / Warp)
   |-- Source of truth for validator existence, status, weight
   |-- Driven by P-Chain consensus (Warp messages)
   CANNOT be overridden by any PrimeWave contract

PrimeWaveValidatorRegistry (protocolAdmin = DEV0/multisig)
   |-- registerValidator() -> feeVault.registerValidator()
   |-- deactivateValidator() -> feeVault.deactivateValidator()
   |-- activateValidator() -> feeVault.activateValidator()
   |-- setUptimeBips() -> feeVault.setUptimeBips()
   |-- setRewardRecipient() -> feeVault.setRewardRecipient()
   |-- syncValidator() -> reads ValidatorManager, updates feeVault

AvalancheGo RewardManager (protocol-level)
   |-- Credits fees to FeeDistributor via StateDB.AddBalance()
   |-- Configured in genesis rewardManagerConfig
   |-- Change requires governance vote + node config update
```

### 3.2 Who Can Move PW?

| Authority | Can Move PW? | Where To? | Guard |
|-----------|-------------|-----------|-------|
| FeeDistributor.distribute() | YES | vault/treasury/burn ONLY | 70/20/10 split, immutable |
| ValidatorFeeVault.claimFees() | YES | rewardRecipient ONLY | caller == rewardRecipient |
| RewardVault.claim() | YES | rewardAddress ONLY | caller == rewardAddress |
| EmergencyMultisig | NO | N/A | Not in scope; reverts on any non-pause call |
| Timelock | YES (indirectly) | Via scheduled admin actions | 48h delay |
| Any EOA | NO (without specific role) | N/A | All functions check authority |

### 3.3 Who Can Pause?

| Target | Who Can Pause | Immediate? |
|--------|--------------|------------|
| FeeDistributor | EmergencyMultisig (pauseController) | YES |
| ValidatorFeeVault | EmergencyMultisig (pauseController) | YES |
| RewardVault | EmergencyMultisig (pauseController) | YES |
| PWUSD (Phase 2) | EmergencyMultisig | YES |
| PrimeWave L1 (chain halt) | 2/3 validator consensus failure | N/A |

### 3.4 Who Can Change Emission Rate?

Only `RewardVault.admin` (DEV0 EOA in dev; multisig+timelock in production) via `setEmissionRate()`. Rate can only be REDUCED from current value (monotone-decreasing). Maximum is compile-time constant `MAX_RATE_PER_SECOND = 3,000,000 PW / year`.

---

## 4. Fund Flow

### 4.1 Transaction Fee Flow

```
User transaction
      |
      v
AvalancheGo block finalization
      |
      v (StateDB.AddBalance -- no receive() called)
FeeDistributor balance increases
      |
      v (anyone calls distribute())
FeeDistributor.distribute()
      |
      +-- 70% --> ValidatorFeeVault.receive()
      |              |-- accFeePerWeight updates (O(1))
      |              |-- Validators can claimFees() anytime
      |
      +-- 20% --> DevTreasury (direct ETH transfer)
      |
      +-- 10% --> 0x000...dEaD (permanent burn)
```

**Rounding rule:** `validatorShare = floor(amount * 7000 / 10000)`, `treasuryShare = floor(amount * 2000 / 10000)`, `burnShare = amount - validatorShare - treasuryShare`. Burn absorbs integer dust. Conservation: `validatorShare + treasuryShare + burnShare == amount` always.

### 4.2 Validator Fee Claim Flow

```
ValidatorFeeVault (receives 70% of all fees)
      |
      v (validator calls claimFees(validationId))
claimFees()
      |-- check: msg.sender == rewardRecipient
      |-- compute: claimable = (accFeePerWeight - rewardDebt) * effectiveWeight / PRECISION
      |-- update: rewardDebt[validator] = accFeePerWeight
      |
      v
rewardRecipient.call{value: claimable}()
```

### 4.3 Reward Vault Emission Flow

```
Admin pre-funds RewardVault (15M PW at genesis)
      |
      v (time passes)
accRewardPerWeight increases = rate * elapsed / PRECISION
      |
      v (recipient calls claim(id))
claim()
      |-- check: msg.sender == rewardAddress
      |-- compute: pending = (accRewardPerWeight - rewardDebt) * weight / PRECISION
      |-- update: rewardDebt = accRewardPerWeight
      |
      v
rewardAddress.call{value: pending}()
```

---

## 5. Supply Flow

### 5.1 Genesis Allocation (100M PW total)

| Allocation | Amount | Address Type | Notes |
|------------|--------|-------------|-------|
| PWSwap Liquidity | 40,000,000 PW (40%) | Multisig | 36-month lock |
| PrimeWave Treasury | 15,000,000 PW (15%) | Multisig+TL | DevTreasury receives 20% of fees additionally |
| Team & Development | 10,000,000 PW (10%) | Multisig+Vesting | OQ-023 pending |
| Validator & Staking Rewards | 15,000,000 PW (15%) | RewardVault contract | Emits <= 3M/year |
| Presale Phase 1 | 5,000,000 PW (5%) | Buyer addresses | No vesting |
| Presale Phase 2 | 7,500,000 PW (7.5%) | Buyer addresses | No vesting |
| Presale Phase 3 | 7,500,000 PW (7.5%) | Buyer addresses | No vesting |
| **TOTAL** | **100,000,000 PW** | | |

**Note:** The dev local genesis (primewavedev) does NOT contain the final production allocation split. DEV0 (0xf39F...) holds all 100M PW for testing purposes. Production genesis must be finalized separately.

### 5.2 Supply Conservation Rules

```
At any block B:
  circulating(PW) + locked_in_RewardVault(PW) + burned(PW) = 100,000,000 PW

Where:
  circulating  = all non-burned, non-vault PW (in EOAs, contracts, treasury, presale)
  locked       = RewardVault.totalFunded - RewardVault.totalClaimed
  burned       = 0x000...dEaD.balance (cumulative 10% of all fees)
```

**No minting is possible after genesis.** NativeMinter precompile is not activated.

---

## 6. Governance Flow

### 6.1 Normal Governance (48h Timelock)

```
Day 0: Protocol Admin identifies required change
Day 0: Protocol Admin calls timelock.schedule(target, data, predecessor, salt)
Day 0: Operation visible on-chain; community review window begins
Day 2+: Anyone calls timelock.execute(target, data, predecessor, salt)
       -> Change takes effect exactly as scheduled
```

### 6.2 Emergency Governance (No Delay)

```
Security incident detected
   |
   v
Any of 5 EMS signers proposes: ems.propose(target, pause/unpause data)
   |
   v (3 of 5 signers approve)
ems.approve(proposalId) x3
   |
   v (anyone executes)
ems.execute(target, data, nonce)
   |
   v
Contract is paused/unpaused immediately
```

**Scope:** Only `pause()` and `unpause()` functions are callable via EMS. Any other function on any contract will revert because EMS is not the `protocolAdmin` or `admin` of those functions.

---

## 7. Validator Flow

```
P-Chain ConvertSubnetToL1Tx (15 validators)
      |
      v (Warp messages)
ValidatorManager (ACP-99)
      |
      v (registry.registerValidator())
PrimeWaveValidatorRegistry
      |
      +-- verify: validatorManager.getValidator(id).status == Active
      +-- call: feeVault.registerValidator(id, recipient, weight, uptimeBips)
      |
      v
ValidatorFeeVault (fee accounting begins)
      |
      v (receive() called on each distribute())
accFeePerWeight increases proportionally to effective weight
      |
      v (validator calls claimFees())
Fees transferred to rewardRecipient
```

---

## 8. Pause Architecture

### 8.1 What Pausing Does and Does Not Do

| Contract | Paused Blocks | Paused Allows | Invariants During Pause |
|----------|--------------|---------------|------------------------|
| FeeDistributor | `distribute()` | `receive()` (fees accumulate) | Pending grows; accounting unchanged |
| ValidatorFeeVault | `claimFees()` | `receive()`, `registerValidator()`, `setUptimeBips()`, `distributeUnallocated()` | Fees continue accruing; can't withdraw |
| RewardVault | `claim()` | `fund()`, `registerRecipient()`, `setEmissionRate()` | Emission continues; can't withdraw |

**Critical:** Pause is per-contract and independent. Pausing VFV does not pause FD or RV.

**No chain-wide pause exists.** Block production continues regardless of contract pause state.

### 8.2 Pause Recovery Properties

After `unpause()`:
- No retroactive overpayment
- No duplicated fees
- All accrued-during-pause rewards are claimable
- Conservation invariants hold immediately

---

## 9. Timelock Architecture

### 9.1 Properties

- `MIN_DELAY = 172_800` — compile-time constant (48 hours). Cannot be changed without redeployment.
- `proposer` — single address (DEV0 in dev, multisig in production). Transferable via `timelock.transferProposer()`.
- Open executor — any address can call `execute()` once delay has elapsed.
- Predecessor chains — operation B can require operation A to be executed first.
- Cancellation — proposer can cancel any pending operation.

### 9.2 Operation Lifecycle

```
UNSCHEDULED -> schedule() -> SCHEDULED -> [48h] -> execute() -> EXECUTED
                                |
                                +-> cancel() -> CANCELLED
```

Replay protection: executed and cancelled operations cannot be re-executed.

---

## 10. Upgradeability

**None.** All PrimeWave protocol contracts are non-upgradeable:

| Contract | Proxy? | upgradeTo? | delegatecall? | Verdict |
|----------|--------|-----------|---------------|---------|
| FeeDistributor | NO | NO | NO | IMMUTABLE |
| ValidatorFeeVault | NO | NO | NO | IMMUTABLE |
| DevTreasury | NO | NO | NO | IMMUTABLE |
| RewardVault | NO | NO | NO | IMMUTABLE |
| EmergencyMultisig | NO | NO | NO | IMMUTABLE |
| PrimeWaveTimelock | NO | NO | NO | IMMUTABLE |
| PrimeWaveValidatorRegistry | NO | NO | NO | IMMUTABLE |

To change any contract's logic, a new contract must be deployed and all dependent contracts must be updated (which requires timelock governance for each).

---

## 11. Initialization Security

### 11.1 Zero-Address Guards

| Contract | Param | Zero Allowed? | Behavior |
|----------|-------|--------------|----------|
| FeeDistributor | `_validatorFeeVault` | NO | Reverts: "FeeDistributor: zero vault" |
| FeeDistributor | `_treasury` | NO | Reverts: "FeeDistributor: zero treasury" |
| FeeDistributor | `_pauseController` | YES (intentional) | Disables pause functionality |
| ValidatorFeeVault | `_protocolAdmin` | NO | Reverts: "VFV: zero admin" |
| RewardVault | `_admin` | NO | Reverts: "RV: zero admin" |
| DevTreasury | `_feeDistributor` | NO | Reverts: "DevTreasury: zero distributor" |
| EmergencyMultisig | any signer | NO | Reverts: "EMS: zero signer" |
| EmergencyMultisig | duplicate signer | NO | Reverts: "EMS: duplicate signer" |
| PrimeWaveTimelock | `_proposer` | NO | Reverts: "PWTL: zero proposer" |
| PrimeWaveValidatorRegistry | all params | NO | Reverts with specific messages |

### 11.2 Front-Running Resistance

All contracts are deployed via CREATE (deterministic from deployer+nonce). The deployer address is the Protocol Admin key; if the key is secure, deployment addresses are predictable and the deployment cannot be front-run to a different address. Constructors execute atomically — no two-step initialization that could be hijacked.

### 11.3 Re-initialization

None of the contracts use `initialize()` patterns (no OpenZeppelin Initializable). All state is set in the constructor which runs exactly once. Re-initialization is impossible by design.

---

## 12. Security Boundaries

```
BOUNDARY 1: RewardVault <-> Fee Flow
  - FeeDistributor cannot route to RewardVault (immutable destinations)
  - RewardVault cannot receive from FeeDistributor (no path exists)
  - Verified: dist.validatorFeeVault() != address(rv)
  - Verified: dist.treasury() != address(rv)
  - Verified: dist.BURN_ADDRESS() != address(rv)

BOUNDARY 2: EmergencyMultisig scope
  - EMS can ONLY call pause()/unpause()
  - All other functions on protocol contracts require different authority
  - Verified: EMS cannot call registerValidator (not protocolAdmin)
  - Verified: EMS cannot call setEmissionRate (not admin)
  - Verified: EMS cannot call setRewardAddress (not admin)

BOUNDARY 3: Timelock vs. EmergencyMultisig
  - Timelock cannot call pause() (not pauseController)
  - EMS cannot schedule timelocked operations
  - Each authority operates in its own domain

BOUNDARY 4: Minting
  - NativeMinter precompile NOT activated in genesis
  - No contract references the NativeMinter interface (0x020...01)
  - No mint() function exists on any protocol contract
  - Supply increase is physically impossible post-genesis

BOUNDARY 5: Admin authority isolation
  - FeeDistributor has NO admin (no owner, no setter functions)
  - ValidatorFeeVault.protocolAdmin is immutable
  - RewardVault.admin is immutable
  - protocolAdmin and admin are different addresses from pauseController
```

---

## 13. Production Configuration

### 13.1 Required Wiring at Deployment

The following wiring MUST be correct at genesis/deployment time:

1. **genesis.rewardManagerConfig.initialRewardConfig.rewardAddress** = FeeDistributor address
2. **FeeDistributor._validatorFeeVault** = ValidatorFeeVault address
3. **FeeDistributor._treasury** = DevTreasury address
4. **FeeDistributor._pauseController** = EmergencyMultisig address (NOT address(0))
5. **ValidatorFeeVault.setPauseController(EMS)** called after EmergencyMultisig is deployed
6. **RewardVault.setPauseController(EMS)** called after EmergencyMultisig is deployed
7. **RewardVault funded** with 15,000,000 PW from genesis allocation

### 13.2 C03 Genesis Gap (Known Production Issue)

The C03 genesis deployment (`DeployC03.s.sol`) deploys FeeDistributor with `pauseController = address(0)`. Because FeeDistributor has no admin, the pauseController CANNOT be rotated post-deployment.

**Production fix:** Deploy FeeDistributor with EmergencyMultisig as pauseController from day one:
```solidity
new FeeDistributor(
    payable(vaultAddress),
    payable(treasuryAddress),
    emsAddress  // NOT address(0)
);
```

This requires the EmergencyMultisig to be deployed BEFORE the FeeDistributor in the production deployment sequence.

---

## 14. Known Limitations

1. **FeeDistributor genesis pauseController = address(0)** — cannot be changed without redeployment
2. **Single proposer on Timelock** — DEV0 EOA in Phase 1; must be rotated to multisig for production via `transferProposer()` (itself a timelocked action)
3. **PrimeWaveStakingManager** — Phase 2 contract not yet deployed; RewardVault.claim is accessible to registered recipients with no staking requirement
4. **ValidatorManager on local dev** — uses MockValidatorManager (no real Warp); production requires real ACP-99 ValidatorManager
5. **Dev genesis allocation** — DEV0 holds all 100M PW for testing; production genesis must use real multi-party allocation
