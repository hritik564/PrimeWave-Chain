# PrimeWave Chain — Reward Economics
**Sprint PW-C00 Decision Resolution | Status: DESIGN DOCUMENT — NOT FOR PRODUCTION**

---

## 1. Overview: Two Separate Mechanisms

PrimeWave Chain has two completely separate economic flows involving PW. They MUST NOT be confused or merged.

| Mechanism | Source | Purpose | Exhaustible? |
|---|---|---|---|
| **A. 15M PW RewardVault** | Genesis pre-allocation | Staking rewards for validators and delegators | YES — fixed 15M PW, stops when exhausted |
| **B. Validator Fee Vault** | Ongoing transaction fees (gas) | Gas fee revenue split (70/20/10) | NO — continuous while chain has transactions |

```
PrimeWave Chain Economics
│
├── A. STAKING REWARDS (finite)
│   └── 15,000,000 PW locked in RewardVault at genesis
│       └── Distributed to validators/delegators over time
│           └── When exhausted → staking rewards stop. No new PW minted.
│
└── B. GAS FEE REVENUE (ongoing)
    └── All transaction fees → FeeDistributor contract
        ├── 70% → Validator Fee Vault (distributed to validators by weight/uptime)
        ├── 20% → PrimeWave Treasury (multisig + timelock)
        └── 10% → Burned (permanently removed from supply)
```

---

## 2. Mechanism A: 15M PW RewardVault

### 2.1 Funding

At genesis, 15,000,000 PW is allocated directly to the `RewardVault` contract address in the genesis `alloc` block. This is existing PW — no minting occurs.

### 2.2 Purpose

Incentivizes validators and delegators to participate in network security. These rewards compensate for the opportunity cost of locked stake.

### 2.3 Reward Distribution Model: On-Chain Accrual / Claim

Rewards are NOT pushed to validators via transactions. Instead, the system maintains accrued reward balances. Validators and delegators **pull** (claim) their rewards.

**Recommended algorithm: Accumulated Reward Per Share (reward-index model)**

This is the same model used by Synthetix, Compound, and many mature DeFi protocols. It scales well to many validators and delegators without O(n) gas costs.

```
State:
  rewardIndex         uint256   // Global: total rewards accrued per unit of weight, scaled by 1e18
  validatorDebt       mapping(address => uint256)  // Checkpoint of rewardIndex at last claim
  pendingRewards      mapping(address => uint256)  // Accumulated but unclaimed rewards

On each reward epoch (e.g., per block or per epoch):
  epochReward = calculateEpochReward()          // Based on schedule / total vault / time elapsed
  rewardIndex += (epochReward × 1e18) / totalEligibleWeight

On validator claim:
  claimable = (rewardIndex - validatorDebt[v]) × validatorWeight[v] / 1e18
  validatorDebt[v] = rewardIndex
  pendingRewards[v] = 0
  RewardVault.transfer(validator, claimable)   // Transfer existing PW, NOT mint
```

### 2.4 Eligibility Conditions

A validator or delegator accumulates rewards only when:
1. **Active:** Registered and confirmed in ValidatorManager
2. **Uptime eligible:** Validator uptime ≥ threshold (target: 80%, exact value: testnet benchmark)
3. **Not slashed:** No active slashing penalty reducing entitlement
4. **Within allocation period:** RewardVault balance > 0

### 2.5 Reward Schedule

The reward schedule determines how much of the 15M PW is distributed per period. Options:

| Model | Description | Pros | Cons |
|---|---|---|---|
| Linear decay | Fixed amount per epoch | Predictable, simple | No early incentive boost |
| Exponential decay | Higher early rewards, trailing off | Classic DeFi incentive | Complex math |
| Fixed APR | Defined annual yield % on staked amount | Intuitive to validators | Rate must be set carefully |

**Recommended for Phase 1:** Linear schedule — divide 15M PW by expected Phase 1 duration (e.g., 3 years = ~13,700 PW/day). Governance can adjust the rate. When vault reaches 0, rewards stop.

> The exact reward schedule (daily emission rate) MUST be decided and documented before deployment.

### 2.6 Delegator Rewards

In Phase 2 (PoS), delegators receive a proportional share of their validator's reward, minus the validator's commission:

```
delegatorReward = (validatorEpochReward × delegationWeight / totalValidatorWeight)
                  × (1 - validatorCommissionBips / 10000)
```

In Phase 1 (PoA), no delegation exists. All rewards go to the 15 validators.

### 2.7 RewardVault Formal Invariants

```
INVARIANT-1: RewardVault.balance() >= 0
INVARIANT-2: RewardVault.totalDistributed() <= 15_000_000e18
INVARIANT-3: RewardVault.balance() + RewardVault.totalDistributed() == 15_000_000e18
INVARIANT-4: totalPWSupply == 100_000_000e18  (never changes; burns reduce circulating, not total)
INVARIANT-5: For any account a: claimed[a] <= earned[a]
```

**Automated test specification** (Foundry invariant tests, to be implemented in PW-C01):

```solidity
// testing/invariants/RewardVaultInvariant.t.sol
contract RewardVaultInvariant is Test {
    function invariant_vaultNeverNegative() public {
        assertGe(rewardVault.balance(), 0);
    }
    function invariant_totalDistributedCapped() public {
        assertLe(rewardVault.totalDistributed(), 15_000_000e18);
    }
    function invariant_balancePlusDistributedEqualsAllocation() public {
        assertEq(rewardVault.balance() + rewardVault.totalDistributed(), 15_000_000e18);
    }
    function invariant_totalSupplyFixed() public {
        assertEq(address(rewardVault).balance + circulatingPW() + burnedPW(), 100_000_000e18);
    }
}
```

---

## 3. Mechanism B: Validator Fee Vault (70/20/10)

### 3.1 Source

Every transaction on PrimeWave Chain pays a gas fee. Under EIP-1559 (standard Subnet-EVM), these fees are collected per block.

The `RewardManager` precompile routes all fees to the `FeeDistributor` contract address.

### 3.2 FeeDistributor Split

```
FeeDistributor.distribute() is called (periodically or per block):

  totalFees = address(FeeDistributor).balance

  validatorShare   = totalFees × 70 / 100   → Validator Fee Vault
  treasuryShare    = totalFees × 20 / 100   → PrimeWave Treasury
  burnShare        = totalFees - validatorShare - treasuryShare  → burn address

  Transfer validatorShare to ValidatorFeeVault contract
  Transfer treasuryShare to PrimeWaveTreasury multisig
  Transfer burnShare to 0x000000000000000000000000000000000000dEaD
```

### 3.3 Validator Fee Vault Distribution

The `ValidatorFeeVault` accumulates the 70% validator share. Distribution among validators uses the same reward-index model as the RewardVault:

```
validator fee entitlement ∝ effective_validator_weight × uptime_eligibility_factor
```

For Phase 1 (15 equal-weight, equal-uptime validators):
```
each_validator_share = ValidatorFeeVault.balance × (1/15)
```

In Phase 2 (weighted PoS):
```
each_validator_share = ValidatorFeeVault.balance × (validator_weight / total_weight)
                       × uptime_eligibility_factor
```

Delegators receive their proportional share from the validator's fee entitlement, minus commission (same calculation as staking rewards in Section 2.6).

### 3.4 Validator Fee Vault Formal Invariants

```
INVARIANT-A: ValidatorFeeVault distributes ONLY collected fees; it cannot create new PW
INVARIANT-B: sum(all_distributions) <= sum(all_fees_received)
INVARIANT-C: ValidatorFeeVault.balance() >= 0 at all times
INVARIANT-D: treasuryReceived + validatorVaultReceived + burned == totalFeesCollected
```

### 3.5 Separation from RewardVault

| Property | RewardVault | ValidatorFeeVault |
|---|---|---|
| Source of funds | Genesis pre-allocation (existing PW) | Ongoing transaction fees |
| Total available | Fixed: 15,000,000 PW | Unlimited (depends on chain activity) |
| Purpose | Staking incentives | Gas fee revenue share |
| Exhaustible | YES | NO |
| Burns supply? | NO | YES (10% burn from fees) |

---

## 4. Combined PW Supply Flow

```
t=0 (Genesis)
  Total supply: 100,000,000 PW
  ├── RewardVault: 15,000,000 PW (locked)
  ├── PWSwap Liquidity: 40,000,000 PW (locked 36 months)
  ├── Treasury: 15,000,000 PW
  ├── Team: 10,000,000 PW
  └── Presale P1+P2+P3: 20,000,000 PW

t>0 (Ongoing)
  RewardVault → (claimed rewards) → validators/delegators (circulating)
  Gas fees → FeeDistributor → 70% ValidatorFeeVault → validators/delegators (circulating)
                            → 20% Treasury
                            → 10% BURNED ← permanent supply reduction

  At all times: circulating + RewardVault_remaining + burned = 100,000,000 PW
```

---

## 5. Economic Sustainability

When the 15M PW RewardVault is exhausted, validators and delegators continue to earn from the Validator Fee Vault (70% of transaction fees). This provides ongoing economic incentive as long as the chain has meaningful transaction volume.

This is equivalent to Bitcoin's model: block subsidies (staking rewards from vault) eventually end; transaction fees (validator fee vault) sustain the validator set indefinitely.

---

*This document is a PW-C00 Decision Resolution specification. No production deployment has occurred.*
