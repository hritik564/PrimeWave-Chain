# PW-C07 Governance Integration Specification

> Sprint: PW-C07 Phase-1 PoA Governance Hardening  
> Status: COMPLETE  
> Date: 2026-08-14  
> Author: PrimeWave Protocol Engineering

---

## 1. Objective

Sprint C07 hardens Phase-1 PoA governance by introducing the two on-chain governance authorities defined in `PRIMEWAVE_GOVERNANCE_POLICY.md` (locked C00), adding emergency pause capability to the three fee-bearing protocol contracts, and proving all properties with a comprehensive test suite (391 tests, 10 stateful invariants).

This spec covers:
- New contracts (EmergencyMultisig, PrimeWaveTimelock)
- Modifications to existing contracts (FeeDistributor, ValidatorFeeVault, RewardVault)
- Authority matrix and scope limitations
- Pause and unpause semantics
- Freeze semantics (PWUSD-only clarification)
- Timelock-gated action inventory
- Integration boundary with C05 ValidatorRegistry and C06 RewardVault

---

## 2. Governance Policy Reference (C00 — Locked Forever)

All governance design is anchored to `PRIMEWAVE_GOVERNANCE_POLICY.md`. Key provisions implemented in C07:

### §3: Protocol Admin Multisig + 48-Hour Timelock

Actions requiring the 48-hour timelock (exhaustive):
| Action | Target Contract |
|--------|----------------|
| Add or remove a PoA validator | ValidatorFeeVault / ValidatorRegistry |
| Change validator weight | ValidatorFeeVault / ValidatorRegistry |
| Change validator reward recipient | ValidatorFeeVault / ValidatorRegistry |
| Reduce RewardVault emission rate | RewardVault |
| Upgrade any proxy contract | Any |
| Change contract owner / admin | Any |
| Change gas fee parameters | AvalancheGo genesis / RewardManager |
| Change FeeDistributor split percentages | FeeDistributor (requires redeployment) |
| Change Emergency Multisig composition | EmergencyMultisig (requires redeployment) |
| Change any PrimeWaveTimelock parameter | PrimeWaveTimelock (requires redeployment) |

### §4.2: Emergency Multisig Authority (3-of-5)

The Emergency Multisig may ONLY:
- `pause(target)` — halt claims/distribution on the specified protocol contract
- `unpause(target)` — restore normal operation

The Emergency Multisig CANNOT:
- Mint PW or alter supply
- Transfer funds from any vault or treasury
- Change the validator set, weights, or reward recipients
- Bypass the 48-hour timelock for any action
- Upgrade contracts
- Change governance role membership

### §4.3: Freeze Semantics (Clarification)

`freeze(account)` is defined ONLY for **PWUSD** (AML/sanctions compliance, Phase 2).  
Phase 1 contracts (FeeDistributor, ValidatorFeeVault, RewardVault, ValidatorRegistry) have NO freeze operation. They have only **pause** (contract-level halt) and **unpause**.

---

## 3. New Contracts

### 3.1 EmergencyMultisig (`contracts/src/EmergencyMultisig.sol`)

**Purpose:** 3-of-5 multisig implementing the Emergency Authority defined in §4.2 of the governance policy.

**Security properties:**
- `THRESHOLD = 3` (compile-time constant, cannot be changed without redeployment)
- `MAX_SIGNERS = 5` (compile-time constant)
- Signer set is immutable after construction (no `addSigner`/`removeSigner`)
- Changing the signer set requires deploying a new EmergencyMultisig and executing a 48-hour timelock operation to rotate `pauseController` on each affected contract
- Proposals are identified by `keccak256(abi.encode(target, data, nonce))` where `nonce` is a globally incrementing counter
- Duplicate approvals from the same signer are rejected
- Executed proposals cannot be re-executed (replay protection)
- Cancelled proposals cannot be executed or re-approved
- Any account may propose; only authorized signers may approve; any account may execute once threshold is met

**Lifecycle:**
```
propose(target, data) -> bytes32 proposalId
approve(proposalId)   [x3 required]
execute(target, data, nonce)
```

**Scope enforcement:** The scope limitation (pause/unpause only) is enforced by the target contracts: `pause()` and `unpause()` are restricted to `onlyPauseController`. The `pauseController` on each contract is set to the EmergencyMultisig address. All other functions on those contracts require different authorities (protocolAdmin, admin), so even if 3-of-5 signers approve a call to `registerValidator`, the target contract rejects it.

### 3.2 PrimeWaveTimelock (`contracts/src/PrimeWaveTimelock.sol`)

**Purpose:** Enforce a mandatory 48-hour delay before executing privileged governance actions per §3 of the governance policy.

**Security properties:**
- `MIN_DELAY = 172_800` seconds (48 hours, compile-time constant)
- The delay cannot be reduced through any governance action — it requires deploying a new timelock (itself a 48-hour timelocked action on the OLD timelock)
- Operations identified by `keccak256(abi.encode(target, data, predecessor, salt))`
- Parameter tampering after scheduling produces a different hash → execution reverts
- Executed operations are permanently marked → no replay
- Cancelled operations cannot execute
- Predecessor chains: an operation can declare a dependency; it cannot execute before its predecessor

**Proposer model:** A single proposer address (DEV0 EOA in Phase 1 dev; Protocol Admin multisig in production) schedules and cancels operations. Any account may execute once the delay has elapsed ("open executor").

---

## 4. Modified Contracts

### 4.1 FeeDistributor (C03)

**Change:** Added emergency pause capability.

**New state:**
```solidity
bool    public paused;
address public pauseController;  // set in constructor
```

**New constructor parameter:** `address _pauseController` (can be `address(0)` to disable pause)

**Pause semantics:**
- `distribute()` reverts with `"FeeDistributor: paused"` when paused
- All accounting state (`totalDistributed`, balances) is unchanged
- Fee credits from AvalancheGo's `AddBalance()` continue to accumulate in the contract balance (they bypass `receive()` and are unaffected by pause)
- The 70/20/10 split is unchanged and will apply to all accumulated balance when unpaused

**Authority:**
- `pause()` / `unpause()` / `setPauseController()` — only callable by `pauseController`
- `pauseController` can transfer the role to another address (self-transfer pattern)
- No other admin exists on FeeDistributor (it was and remains admin-less for all other operations)

### 4.2 ValidatorFeeVault (C04)

**Change:** Added emergency pause capability.

**New state:**
```solidity
bool    public paused;
address public pauseController;  // mutable; initially address(0)
```

**Pause semantics:**
- `claimFees(validationId)` reverts with `"VFV: paused"` when paused
- Accounting operations remain active during pause:
  - `receive()` — fee crediting continues; `totalReceived` and `accFeePerWeight` update
  - `registerValidator()` — admin can still register new validators
  - `deactivateValidator()` / `activateValidator()` — lifecycle management continues
  - `setUptimeBips()` / `setBaseWeight()` — weight management continues
  - `distributeUnallocated()` — permissionless; continues to work
- Validators accumulate fees during the pause period; they can claim after unpause

**Authority:**
- `setPauseController(address)` — callable by `protocolAdmin` (to initialize) OR by current `pauseController` (to rotate). Setting to `address(0)` disables pause.
- `pause()` / `unpause()` — `onlyPauseController` modifier

### 4.3 RewardVault (C06)

**Change:** Added emergency pause capability.

**New state:**
```solidity
bool    public paused;
address public pauseController;  // mutable; initially address(0)
```

**Pause semantics:**
- `claim(id)` reverts with `"RV: paused"` when paused
- Emission accrual continues during pause (the global index advances with time)
- Pending rewards accumulate; they can be claimed after unpause
- Admin operations remain active during pause: `registerRecipient()`, `activateRecipient()`, `deactivateRecipient()`, `setWeight()`, `setRewardAddress()`, `setEmissionRate()`

**Authority:**
- `setPauseController(address)` — callable by `admin` OR current `pauseController`
- `pause()` / `unpause()` — `onlyPauseController` modifier

---

## 5. Governance Authority Matrix

| Action | Caller Authority | Timelock? | Phase 1 Admin |
|--------|-----------------|-----------|---------------|
| pause() on FeeDistributor | EmergencyMultisig (3-of-5) | NO | N/A |
| unpause() on FeeDistributor | EmergencyMultisig (3-of-5) | NO | N/A |
| pause() on ValidatorFeeVault | EmergencyMultisig (3-of-5) | NO | N/A |
| unpause() on ValidatorFeeVault | EmergencyMultisig (3-of-5) | NO | N/A |
| pause() on RewardVault | EmergencyMultisig (3-of-5) | NO | N/A |
| unpause() on RewardVault | EmergencyMultisig (3-of-5) | NO | N/A |
| freeze(account) on PWUSD | EmergencyMultisig (3-of-5) | NO | PHASE 2 ONLY |
| registerValidator | Protocol Admin | YES (48h) | DEV0 EOA |
| deactivateValidator | Protocol Admin | YES (48h) | DEV0 EOA |
| activateValidator | Protocol Admin | YES (48h) | DEV0 EOA |
| setBaseWeight | Protocol Admin | YES (48h) | DEV0 EOA |
| setUptimeBips | Protocol Admin | YES (48h) | DEV0 EOA |
| setRewardRecipient | Protocol Admin | YES (48h) | DEV0 EOA |
| setEmissionRate (reduce) | Protocol Admin | YES (48h) | DEV0 EOA |
| setPauseController (any contract) | Protocol Admin + TL | YES (48h) | DEV0 EOA |
| Change EmergencyMultisig signers | Protocol Admin + TL (redeploy) | YES (48h) | DEV0 EOA |
| FeeDistributor split change | Protocol Admin + TL (redeploy) | YES (48h) | DEV0 EOA |

---

## 6. ValidatorRegistry Hardening

`PrimeWaveValidatorRegistry` (C05) enforces that all validator registrations reference an existing ACP-99 validationID in the authoritative `ValidatorManager`. This prevents the admin from inventing fake validators.

No additional modifications were made to the registry in C07. The registry remains the `protocolAdmin` of `ValidatorFeeVault` in the production C03 deployment. Governance actions targeting the registry's own validator lifecycle functions are governed by the registry's `protocolAdmin`, which in Phase 1 is DEV0 EOA and in production will be a Protocol Admin multisig + timelock.

---

## 7. Unchanged Invariants (C00 Locked)

All C00 invariants remain in force:
- 100M PW fixed supply; NativeMinter MUST NOT be activated
- Fee split: 70/20/10 (immutable in FeeDistributor — no `setSplit()`)
- 15M PW RewardVault funding cap; max 3,000,000 PW/year emission rate
- `totalEmitted <= totalFunded` at all times
- `totalClaimed <= totalEmitted` at all times
- Reward index model: `accRewardPerWeight` monotonically non-decreasing

---

## 8. Deployment Order (Phase 1 Dev)

```
1. Deploy EmergencyMultisig(signers[5])
2. Deploy PrimeWaveTimelock(protocolAdmin)
3. For each new contract deployment: pass EmergencyMultisig as pauseController in constructor
4. For existing contracts (C03-C06 already deployed):
   - RewardVault: DEV0 calls setPauseController(EmergencyMultisig)
   - ValidatorFeeVault: VFV admin calls setPauseController(EmergencyMultisig)
   - FeeDistributor: cannot be changed (no admin); redeploy with new constructor param
5. Verify all pause controllers are set correctly
```

---

## 9. Production Key Note

Development signers (DEV0-DEV4, Foundry well-known keys) are used in Phase 1. Production deployment MUST follow `PRIMEWAVE_KEY_SECURITY_PROCEDURE.md` for key generation and ceremony. No production keys were generated in this sprint.
