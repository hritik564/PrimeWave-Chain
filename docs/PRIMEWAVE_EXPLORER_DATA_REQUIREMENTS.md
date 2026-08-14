# PrimeWave Chain Explorer Data Requirements

> Sprint: PW-C08 Protocol Integration + Production Configuration Hardening
> Audience: Block explorer integration team / off-chain indexing team
> Date: 2026-08-14

This document specifies all on-chain events, storage slots, and query patterns required by a PrimeWave Chain block explorer to display protocol activity accurately.

---

## 1. Chain Identity

| Field | Value |
|-------|-------|
| Network Name | PrimeWave Chain |
| Ticker | PW |
| Chain ID (dev) | 73571 |
| Chain ID (production) | TBD |
| Decimals | 18 |
| Max Supply | 100,000,000 PW (fixed at genesis) |
| Block Time (target) | ~1-2s |
| Consensus | Avalanche PoA Phase 1 -> PoS Phase 2 |
| EVM Version | Shanghai (Subnet-EVM 0.6.x) |

---

## 2. Contract Registry

The explorer MUST track the following contract addresses (all immutable post-genesis):

| Contract | Role | Key Display Name |
|----------|------|-----------------|
| FeeDistributor | Routes all tx fees | "Fee Distributor" |
| ValidatorFeeVault | Holds 70% of fees for validators | "Validator Fee Vault" |
| DevTreasury | Holds 20% of fees | "Development Treasury" |
| 0x000...dEaD | Permanent fee burn | "Burn Address" |
| RewardVault | Holds 15M PW staking rewards | "Reward Vault" |
| EmergencyMultisig | Emergency pause authority | "Emergency Multisig" |
| PrimeWaveTimelock | 48h governance timelock | "Protocol Timelock" |
| PrimeWaveValidatorRegistry | Validator lifecycle adapter | "Validator Registry" |

---

## 3. Events Reference

### 3.1 FeeDistributor Events

```solidity
event Distributed(
    uint256 indexed blockTimestamp,
    uint256 totalAmount,
    uint256 validatorShare,  // 70%
    uint256 treasuryShare,   // 20%
    uint256 burnShare        // 10%
);

event Paused(address indexed by);
event Unpaused(address indexed by);
```

**Explorer display:** Show each `Distributed` event as a "Fee Distribution" transaction. Annotate with the 70/20/10 split. Aggregate `burnShare` into "Total PW Burned" metric.

### 3.2 ValidatorFeeVault Events

```solidity
event FeeReceived(
    uint256 amount,
    uint256 newAccFeePerWeight,
    uint256 totalEffectiveWeight
);

event FeeClaimed(
    bytes32 indexed validationId,
    address indexed rewardRecipient,
    uint256 amount
);

event ValidatorRegistered(
    bytes32 indexed validationId,
    address indexed rewardRecipient,
    uint256 weight,
    uint256 uptimeBips
);

event ValidatorDeactivated(bytes32 indexed validationId);
event ValidatorActivated(bytes32 indexed validationId);
event BaseWeightSet(bytes32 indexed validationId, uint256 newWeight);
event UptimeBipsSet(bytes32 indexed validationId, uint256 newBips);
event RewardRecipientSet(bytes32 indexed validationId, address newRecipient);
event UnallocatedDistributed(address indexed recipient, uint256 amount);
event Paused(address indexed by);
event Unpaused(address indexed by);
```

**Explorer display:**
- `FeeReceived` -> update "Validator Pool Balance" widget
- `FeeClaimed` -> show as "Validator Fee Claim" with recipient address
- `ValidatorRegistered` -> show in Validators tab
- `FeeClaimed` -> aggregate by validationId for per-validator revenue chart

### 3.3 DevTreasury Events

DevTreasury is a simple ETH recipient (no custom events beyond inherited ERC-165 if any). Balance increases tracked via `FeeDistributor.Distributed.treasuryShare`. Withdrawals are tracked as outbound ETH transfers from the treasury address.

**Explorer display:** Show treasury balance. Show inbound transfers tagged as "Protocol Fee Income". Show outbound as "Treasury Expenditure".

### 3.4 RewardVault Events

```solidity
event Funded(address indexed sender, uint256 amount, uint256 newTotalFunded);

event RecipientRegistered(
    bytes32 indexed validationId,
    address indexed rewardAddress,
    uint256 weight
);

event Claimed(
    bytes32 indexed validationId,
    address indexed rewardAddress,
    uint256 amount
);

event EmissionRateSet(uint256 oldRate, uint256 newRate);
event EmissionPaused();    // rate set to 0
event EmissionResumed(uint256 rate);
event Exhausted();         // all funds emitted

event Paused(address indexed by);
event Unpaused(address indexed by);
```

**Explorer display:**
- Show "Staking Rewards" panel with: `totalFunded`, `totalEmitted`, `totalClaimed`, `accountedBalance`
- Show emission rate as "PW per year" (rate * 31,536,000 / 1e18)
- `Exhausted` event -> show prominent "Reward Pool Depleted" banner

### 3.5 EmergencyMultisig Events

```solidity
event ProposalCreated(
    uint256 indexed proposalId,
    address indexed proposer,
    address indexed target,
    bytes data,
    uint256 nonce
);

event Approved(
    uint256 indexed proposalId,
    address indexed signer,
    uint256 approvalCount
);

event Executed(
    uint256 indexed proposalId,
    address indexed executor,
    uint256 nonce
);

event Cancelled(uint256 indexed proposalId, address indexed by);
```

**Explorer display:**
- Show "Emergency Governance" panel listing all proposals with status (Pending/Executed/Cancelled)
- Highlight executed proposals prominently (these are emergency actions)
- Show approval count progress (e.g., "2/3 approvals")

### 3.6 PrimeWaveTimelock Events

```solidity
event CallScheduled(
    bytes32 indexed id,
    address indexed target,
    uint256 value,
    bytes data,
    bytes32 predecessor,
    uint256 delay
);

event CallExecuted(
    bytes32 indexed id,
    address indexed target,
    uint256 value,
    bytes data
);

event Cancelled(bytes32 indexed id);

event ProposerTransferred(
    address indexed oldProposer,
    address indexed newProposer
);
```

**Explorer display:**
- Show "Governance Queue" panel listing all pending operations with countdown timer
- Show executed operations as "Governance Actions" history
- ProposerTransferred -> show as "Governance Transfer" alert

---

## 4. Key Storage Reads (Read-Only RPC Calls)

### 4.1 FeeDistributor State

```solidity
// All callable via eth_call:
fd.totalDistributed()        // total ETH ever routed through FD
fd.totalValidatorShare()     // total sent to VFV
fd.totalTreasuryShare()      // total sent to Treasury
fd.totalBurnShare()          // total sent to Burn
fd.pendingDistribution()     // current undistributed balance
fd.VALIDATOR_BPS()           // 7000 (70%)
fd.TREASURY_BPS()            // 2000 (20%)
fd.BASIS_POINTS()            // 10000
fd.paused()                  // is distribution paused?
fd.pauseController()         // EmergencyMultisig address
```

### 4.2 ValidatorFeeVault State

```solidity
vfv.totalReceived()          // total ETH received from FD
vfv.totalClaimed()           // total ETH claimed by validators
vfv.vaultBalance()           // current ETH balance
vfv.accFeePerWeight()        // current fee index (scaled by 1e18)
vfv.totalEffectiveWeight()   // sum of active validator weights
vfv.validatorCount()         // total registered validators
vfv.paused()                 // is claiming paused?

// Per-validator:
vfv.getValidator(validationId)
// Returns: (active, rewardRecipient, baseWeight, uptimeBips, effectiveWeight, rewardDebt)

// Claimable fees for a validator (simulate call):
vfv.claimFees(validationId)  // Use staticcall to preview claimable
```

### 4.3 RewardVault State

```solidity
rv.totalFunded()             // total PW funded
rv.totalEmitted()            // total PW earned (emitted to index)
rv.totalClaimed()            // total PW claimed by recipients
rv.accountedBalance()        // totalFunded - totalEmitted
rv.emissionRatePerSecond()   // current rate in wei/second
rv.MAX_RATE_PER_SECOND()     // maximum allowed rate
rv.MAX_ANNUAL_EMISSION()     // 3,000,000 ether = 3M PW/year
rv.isExhausted()             // true if all funds have been emitted
rv.paused()                  // is claiming paused?
rv.accRewardPerWeight()      // current reward index
rv.lastUpdateTime()          // timestamp of last index update
rv.totalWeight()             // sum of recipient weights
```

### 4.4 EmergencyMultisig State

```solidity
ems.THRESHOLD()              // 3 (3-of-5)
ems.MAX_SIGNERS()            // 5
ems.nonce()                  // number of proposals executed
ems.isSigner(addr)           // is addr one of the 5 signers?
ems.getProposal(id)          // (target, data, nonce, executed, cancelled, approvalCount)
ems.hasApproved(id, addr)    // has signer approved proposal?
```

### 4.5 PrimeWaveTimelock State

```solidity
tl.MIN_DELAY()               // 172800 (48h)
tl.proposer()                // current proposer address
tl.getTimestamp(opId)        // 0 = not scheduled, 1 = executed, N = ready-at timestamp
tl.isOperation(opId)         // true if scheduled
tl.isOperationPending(opId)  // scheduled and not yet executed
tl.isOperationReady(opId)    // delay has elapsed, can be executed
tl.isOperationDone(opId)     // executed
```

---

## 5. Derived Metrics

### 5.1 Protocol Dashboard Metrics

| Metric | Formula | Update Frequency |
|--------|---------|-----------------|
| Total Fees Collected | `fd.totalDistributed()` | Per block |
| Total PW Burned | `fd.totalBurnShare()` or `burnAddress.balance` | Per block |
| Circulating Supply | `100M - rv.accountedBalance() - burnAddress.balance` | Per block |
| Annual Fee APY (validators) | `vfv.totalReceived() / 365 days * annualized / totalStaked` | Daily |
| Reward Pool Remaining | `rv.accountedBalance() / 1e18` PW | Per block |
| Emission Rate | `rv.emissionRatePerSecond() * 31536000 / 1e18` PW/year | On change |
| Years Until Reward Exhaustion | `rv.accountedBalance() / (rv.emissionRatePerSecond() * 31536000)` | Daily |

### 5.2 Per-Validator Metrics

| Metric | Formula |
|--------|---------|
| Total Fees Earned | Sum of `FeeClaimed` events for validationId |
| Claimable Now | `(accFeePerWeight - rewardDebt) * effectiveWeight / 1e18` |
| Uptime Score | `validator.uptimeBips / 10000 * 100` % |
| Weight Share | `validator.effectiveWeight / totalEffectiveWeight * 100` % |
| Fees Earned (share) | weight share * totalReceived |

---

## 6. Fee Distribution Visualization

The explorer should show a real-time "fee waterfall" diagram on the protocol overview page:

```
Block Gas Fees
     |
     v (automatic via RewardManager)
FeeDistributor
     |
     +-----70%-----> ValidatorFeeVault
     |                    |
     |               (per validator, by weight)
     |                    |
     |               Validator Wallets
     |
     +-----20%-----> DevTreasury
     |               (held by protocol)
     |
     +-----10%-----> 0x000...dEaD
                    (permanently burned)
```

---

## 7. Token Metadata

```json
{
  "name": "PrimeWave",
  "symbol": "PW",
  "decimals": 18,
  "totalSupply": "100000000000000000000000000",
  "logoURI": "https://primewave.io/assets/pw-logo.svg",
  "description": "Native gas token of PrimeWave Chain. Fixed supply of 100M PW at genesis. No minting possible.",
  "links": {
    "website": "https://primewave.io",
    "docs": "https://docs.primewave.io",
    "explorer": "https://explorer.primewave.io"
  }
}
```

---

## 8. Transaction Labeling Guide

The explorer should apply the following labels to transactions calling the protocol contracts:

| Target | Function Selector | Label |
|--------|------------------|-------|
| FeeDistributor | `distribute()` | "Fee Distribution" |
| ValidatorFeeVault | `claimFees(bytes32)` | "Validator Fee Claim" |
| ValidatorFeeVault | `registerValidator(...)` | "Validator Registration" |
| ValidatorFeeVault | `deactivateValidator(bytes32)` | "Validator Deactivated" |
| RewardVault | `fund()` | "Reward Pool Funding" |
| RewardVault | `claim(bytes32)` | "Staking Reward Claim" |
| RewardVault | `setEmissionRate(uint256)` | "Emission Rate Update" |
| EmergencyMultisig | `propose(...)` | "Emergency Proposal" |
| EmergencyMultisig | `approve(uint256)` | "Emergency Approval" |
| EmergencyMultisig | `execute(...)` | "EMERGENCY ACTION" (highlight in red) |
| PrimeWaveTimelock | `schedule(...)` | "Governance Proposal" |
| PrimeWaveTimelock | `execute(...)` | "Governance Execution" |
| PrimeWaveTimelock | `cancel(bytes32)` | "Governance Cancelled" |
| PrimeWaveValidatorRegistry | `registerValidator(...)` | "Validator Onboarded" |
| PrimeWaveValidatorRegistry | `syncValidator(bytes32)` | "Validator Sync" |

---

## 9. Indexing Notes

### 9.1 FeeDistributor Balance Tracking

AvalancheGo credits fees to the FeeDistributor via `StateDB.AddBalance()` at block finalization. This does NOT emit an EVM event. The explorer must track the FeeDistributor's ETH balance via `eth_getBalance` polling or by monitoring the `Distributed` event and computing:

```
balance_before = totalDistributed + pendingDistribution (at any prior block)
balance_after  = totalDistributed + pendingDistribution (at current block)
delta          = balance_after - balance_before = fees collected this period
```

### 9.2 Burn Address Tracking

Standard balance polling on `0x000...dEaD` is sufficient. No PW can ever leave this address (no private key controls it).

### 9.3 Re-org Handling

PrimeWave Chain uses Avalanche consensus with instant finality (finalized blocks cannot be re-orged). Re-org handling is not required for confirmed blocks. Use `finalized` block tag where available.

### 9.4 Validator ID Format

Validator IDs are `bytes32` hashes (Avalanche validation IDs). The explorer should display them as `0x{hex}` with an option to show the decoded Avalanche NodeID if the mapping is known.
