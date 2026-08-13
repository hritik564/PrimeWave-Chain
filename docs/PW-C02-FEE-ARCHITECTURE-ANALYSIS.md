# PW-C02: Fee Architecture Analysis

> **ENVIRONMENT: LOCAL DEVELOPMENT ONLY**
> This document records technical findings from the PW-C02 validation sprint.
> No production contracts were deployed. No production configuration was changed.

---

## 1. Fee Manager

### 1.1 Status in Current PrimeWave Dev Genesis

**Status: NOT ACTIVE**

The FeeManager precompile (`0x0200000000000000000000000000000000000003`) is NOT configured in the current genesis. `eth_getCode` returns `0x` (no code). ETH calls to `getFeeConfig()` return `0x` (empty).

### 1.2 What FeeManager Controls

The FeeManager precompile (when activated) allows privileged addresses to dynamically modify fee parameters:

| Parameter | Genesis Value | Purpose |
|---|---|---|
| `gasLimit` | 30,000,000 | Max gas per block |
| `targetBlockRate` | 2 seconds | Block production rate |
| `minBaseFee` | 25,000,000,000 wei (25 gwei) | Minimum EIP-1559 base fee |
| `targetGas` | 15,000,000 | Gas target per block |
| `baseFeeChangeDenominator` | 36 | Rate of base fee adjustment |
| `minBlockGasCost` | 0 | Minimum block-level gas cost |
| `maxBlockGasCost` | 1,000,000 | Maximum block-level gas cost |
| `blockGasCostStep` | 200,000 | Block gas cost step size |

### 1.3 How Fee Configuration Can Be Queried

With FeeManager NOT active: fee parameters are immutable after genesis. Query genesis `feeConfig` block or use `eth_call` to `getFeeConfig()` — returns `0x` when not active.

With FeeManager ACTIVE: `getFeeConfig()` (selector `0x4f48eedf`) returns the full struct. Admins call `setFeeConfig()` to update.

### 1.4 Fee Configuration Recommendations for PrimeWave

| Question | Answer |
|---|---|
| Should FeeManager be activated? | **YES** — required for governance-controlled fee adjustments |
| Who controls FeeManager? | Protocol Admin (Emergency Multisig for emergency changes) |
| Subject to timelock? | **YES** — 48h timelock required per PW-C00 governance policy |
| When to activate? | At PrimeWave EVM genesis (production mainnet) or testnet |
| Risk if not activated? | Fee params fixed forever (inflexible for network growth) |

---

## 2. Reward Manager

### 2.1 Status in Current PrimeWave Dev Genesis

**Status: NOT ACTIVE**

The RewardManager precompile (`0x0200000000000000000000000000000000000004`) is NOT configured in the current genesis. `eth_getCode` returns `0x`. ETH calls return `0x` (empty responses).

### 2.2 What RewardManager Controls

The RewardManager precompile controls where transaction fees (the coinbase/miner reward) go. It supports exactly THREE modes:

| Mode | Config | Effect |
|---|---|---|
| **Burn (default)** | No RewardManager active | Fees → `0x0100...` (Avalanche blackhole) |
| **Fee Recipients** | `areFeeRecipientsAllowed = true` | Fees → validator's registered coinbase address |
| **Fixed Reward Address** | `currentRewardAddress = <addr>` | Fees → one specific address |

**Critical limitation:** The RewardManager does NOT support percentage splits. It cannot send 70% to one address and 30% to another natively. This limitation is fundamental to the Avalanche EVM architecture and determines the need for a FeeDistributor contract.

### 2.3 Answers to Reward Manager Questions (per PW-C02 spec §13)

| Question | Answer | Evidence |
|---|---|---|
| Who receives tx-fee rewards by default? | `0x0100...` (Avalanche blackhole — effectively burned) | Block 1 miner field = `0x0100...` |
| Can rewards go to validators? | YES — via `allowFeeRecipients: true` mode | RewardManager ABI |
| Can rewards be redirected to a vault? | YES — via `rewardAddress` mode | RewardManager ABI |
| Can rewards be split? | **NO** — RewardManager sends all to ONE address | Architecture limitation |
| Can a treasury receive a percentage? | **NOT NATIVELY** — requires FeeDistributor contract | Architecture limitation |
| Can a burn address receive a percentage? | **NOT NATIVELY** — requires FeeDistributor contract | Architecture limitation |
| Can validator rewards be pooled? | YES — via `rewardAddress = ValidatorFeeVault` | Design pattern |
| Does Reward Manager itself mint? | **NO** — rewards are transaction fees already in supply | Confirmed |
| Does it interact with NativeMinter? | **NO** — separate, independent precompiles | Architecture doc |
| Does it conflict with 100M fixed supply? | **NO** — redistributes existing PW, never creates new PW | Confirmed |
| Does it support 70/20/10 directly? | **NO** — maximum 2-party routing (one recipient) | Architecture limitation |

---

## 3. Native Minter Implications

### 3.1 Status

**Status: NOT ACTIVE** ✅ (correct per PW-C00 mandate)

The NativeMinter precompile (`0x0200000000000000000000000000000000000001`) is NOT configured. `eth_getCode` returns `0x`. This is correct and must be maintained permanently.

### 3.2 Why It Must Never Be Activated

| Risk | Impact |
|---|---|
| NativeMinter allows new PW creation | Violates 100M hard cap immediately |
| Any activation pathway is irreversible | Once minted PW exists, supply invariant broken |
| No governance or timelock can un-mint | Inflation cannot be reversed |
| RewardVault design is nullified | 15M reward vault loses purpose if inflation allowed |

**ABSOLUTE RULE:** The NativeMinter precompile MUST NOT be configured in any PrimeWave genesis (dev, testnet, mainnet). No address must ever receive NativeMinter admin or minter roles.

### 3.3 Current PrimeWave Architecture Avoids NativeMinter Entirely

| Mechanism | Does it use NativeMinter? |
|---|---|
| Transaction fee routing | NO — existing PW redistributed |
| Validator staking rewards | NO — paid from pre-funded 15M RewardVault |
| PWUSD minting | NO — PWUSD is an ERC-20, not the native PW token |
| Gas payment | NO — uses existing PW |
| Emergency operations | NO — EmergencyMultisig has no mint authority |

---

## 4. Fee Collection

### 4.1 Current Behavior (Dev Genesis)

With `allowFeeRecipients: false` and no RewardManager active:

```
Transaction fee = gas_used × effectiveGasPrice
effectiveGasPrice = baseFeePerGas + maxPriorityFeePerGas

ALL fees (base fee + priority tip) → block.coinbase
block.coinbase = 0x0100000000000000000000000000000000000000 (Avalanche blackhole)
```

**Confirmed by observation (PW-C02 test transaction):**
- Gas used: 21,000
- Effective gas price: 25,000,000,001 wei/gas
- Total fee: 525,000,000,021,000 wei → blackhole address
- Blackhole balance after TX: 525,000,000,021,000 wei

> **Note on EIP-1559 in Avalanche EVM:** Unlike Ethereum mainnet (where EIP-1559 burns the base fee at the protocol level and only the priority tip goes to the miner), the Avalanche EVM sends the TOTAL fee (base fee + priority tip) to the coinbase address. The "burn" effect with `allowFeeRecipients: false` is achieved by routing ALL fees to the inaccessible blackhole address, not by protocol-level destruction.

### 4.2 Fee Collection in Production Architecture (Model C)

```
RewardManager: rewardAddress = FeeDistributor.address
→ ALL fees flow to FeeDistributor on each block
→ FeeDistributor.distribute() splits:
    70% → ValidatorFeeVault
    20% → PrimeWaveTreasury (multisig)
    10% → 0x0100... (blackhole/burn)
```

---

## 5. Validator Rewards

### 5.1 Two Separate Systems

| System | Source | Mechanism | Exhaustible? |
|---|---|---|---|
| **Gas fee revenue** (ongoing) | Transaction fees | RewardManager → FeeDistributor → ValidatorFeeVault → validators | NO |
| **Staking reward reserve** (finite) | Genesis 15M PW pre-allocation | RewardVault.claim() by validators | YES (15M cap) |

These systems MUST NOT be conflated. See `PRIMEWAVE_REWARD_ECONOMICS.md` for the dual-mechanism specification.

### 5.2 Gas Fee → Validator Distribution (Production Architecture)

```
ValidatorFeeVault.balance  ← 70% of all transaction fees (accumulated)

distribute():
  for each validator v:
    share[v] = ValidatorFeeVault.balance
               × validator_weight[v] × uptime_eligibility[v]
               / sum(all eligible validator weights)
```

Phase 1 (15 equal-weight validators, full uptime): each validator receives approximately 1/15 of the 70% share.

### 5.3 Whether Native Avalanche Architecture Supports Validator Fee Distribution

Native Avalanche EVM: **partially**. With `allowFeeRecipients: true`, each validator's registered coinbase receives ALL fees directly during blocks they propose. This is simple but does not support pooling, weight-based splitting, or uptime eligibility — all of which PrimeWave requires.

**Conclusion:** Native `allowFeeRecipients: true` is insufficient. A `ValidatorFeeVault` contract with on-chain distribution logic is required.

---

## 6. Treasury Routing

### 6.1 Current State

No Treasury routing is implemented. All fees currently go to blackhole.

### 6.2 Production Architecture

The 20% Treasury share flows as follows:

```
FeeDistributor.distribute():
  treasuryShare = totalFees × 20 / 100
  PrimeWaveTreasury.transfer(treasuryShare)
```

The `PrimeWaveTreasury` contract must be:
- A multisig (3-of-5 Emergency Multisig or dedicated Treasury multisig)
- Subject to the 48-hour timelock for all non-emergency disbursements
- Auditable (all inflows and outflows on-chain)
- **NOT** the production multisig (not created in PW-C02)

For PW-C02 development testing: a clearly labeled development Treasury address was observed (not needed for local tests). Production Treasury setup is PW-C03+.

---

## 7. Burn Mechanism

### 7.1 Current Behavior

With `allowFeeRecipients: false`: **100% of fees are burned** to the Avalanche blackhole (`0x0100...`). This exceeds the intended 10% burn; the current config is for development only.

### 7.2 Burn Mechanism Options

| Approach | Mechanism | Removes from Supply? | Observable? | Reversible? | Requires Contract? |
|---|---|---|---|---|---|
| **A. Avalanche blackhole** (`0x0100...`) | Send to coinbase with `allowFeeRecipients=false` | No (accumulates in inaccessible address) | YES (balance query) | NO (no private key) | NO |
| **B. Ethereum zero address** (`0x0000...`) | Send to 0x0 | No (same as A) | YES | NO | NO (or minimal) |
| **C. Named burn address** (`0x000...dead`) | FeeDistributor sends to dead address | No (same as A and B) | YES | NO | YES |
| **D. Protocol burn** | EIP-1559 base fee destruction | YES (removed from state entirely) | INDIRECT | NO | NO |

### 7.3 Recommended Burn Approach for PrimeWave

**Recommendation: Approach C — `0x000000000000000000000000000000000000dEaD`**

Rationale:
- The "dead" address (`0xdead`) is the Ethereum ecosystem standard for burns
- Widely recognized as burned by block explorers and analytics tools
- Burns are permanently observable via `eth_getBalance(0x...dead)`
- Compatible with 100M maximum supply (no PW leaves the EVM state, but it accumulates in an inaccessible address)
- No contract required for the burn destination itself

**Supply accounting note:** PW sent to any inaccessible address (blackhole, 0x0, 0xdead) is NOT destroyed from the EVM state — it accumulates in that address's balance. However, it is economically equivalent to a burn because it can never circulate. The supply invariant should track this:

```
effective_supply = total_genesis_supply - burned_to_dead_address
circulating_supply = effective_supply - locked_in_RewardVault
```

### 7.4 Does Burning Affect the 100M Maximum?

- **Technically:** No. EVM state always contains exactly 100M PW minus any burned base fees (via EIP-1559 protocol burn if enabled) plus nothing (NativeMinter is off).
- **Economically:** Yes. Burns permanently reduce circulating supply, making PW deflationary over time.
- **Invariant:** The supply invariant (`TOTAL_PW ≤ 100M`) is maintained in all scenarios because no PW is created after genesis.

---

## 8. 70/20/10 Feasibility

### 8.1 Four Models Evaluated

#### MODEL A: Native Avalanche Fee/Reward Manager Only

**Feasibility: NOT FEASIBLE for 70/20/10**

| Property | Assessment |
|---|---|
| Correctness | ❌ Cannot split fees 3 ways natively |
| Security | ✅ N/A (not used) |
| Complexity | ✅ Lowest |
| Upgradeability | ❌ No upgrade path to 70/20/10 |

RewardManager supports ONE fee destination (or burn all, or validators directly). There is no native percentage split. Model A can implement 0/0/100 (all burned), 100/0/0 (all to validators), or 0/100/0 (all to Treasury). It cannot implement 70/20/10.

#### MODEL B: FeeManager + RewardManager Configuration

**Feasibility: NOT FEASIBLE for 70/20/10**

| Property | Assessment |
|---|---|
| Correctness | ❌ FeeManager controls fee params, not fee routing |
| Security | ✅ Both are Avalanche-native precompiles |
| Complexity | 🟡 Moderate |
| Upgradeability | ✅ Both support admin changes |

FeeManager controls gas price floors, target rate, etc. RewardManager controls fee destination. Together they give governance control over fee parameters and a single destination address. Still cannot split to three destinations.

#### MODEL C: RewardManager + Custom FeeDistributor Contract ✅ RECOMMENDED

**Feasibility: FULLY FEASIBLE**

```
genesis/governance:
  RewardManager.setRewardAddress(FeeDistributor.address)

Each block:
  All fees → FeeDistributor.address (accumulated)

FeeDistributor.distribute() [callable by anyone]:
  total = address(this).balance
  validatorShare = total × 70 / 100 → ValidatorFeeVault
  treasuryShare  = total × 20 / 100 → PrimeWaveTreasury
  burnShare      = total - validatorShare - treasuryShare → 0x000...dead
```

| Property | Assessment |
|---|---|
| Correctness | ✅ Exact 70/20/10 implementable |
| Security | ✅ Simple math, auditable |
| Gas cost | ✅ ~50K gas per distribution call (amortized across many blocks) |
| Complexity | 🟡 Moderate — requires 3 contracts (FeeDistributor, ValidatorFeeVault, Treasury) |
| Upgradeability | ✅ FeeDistributor address in RewardManager can be updated via governance |
| Auditability | ✅ All flows on-chain; FeeDistributor emits events |
| Supply invariant | ✅ No minting; only redistributes existing PW |
| Validator compatibility | ✅ ValidatorFeeVault handles per-validator weight distribution |
| Delegation compatibility | ✅ ValidatorFeeVault can include delegator sub-accounting |
| Operational complexity | 🟡 `distribute()` must be called periodically (incentivized keeper or per-block automation) |

**This model is consistent with the locked PW-C00 architecture decision.**

#### MODEL D: Fee Collection → ValidatorFeeVault First → Distribution

**Feasibility: FEASIBLE but less architecturally clean**

| Property | Assessment |
|---|---|
| Correctness | ✅ Can implement 70/20/10 |
| Security | 🟡 ValidatorFeeVault must handle 3-way split + per-validator split (higher complexity) |
| Complexity | 🔴 Higher than Model C |
| Separation of concerns | ❌ ValidatorFeeVault must also handle Treasury and burn routing |

Model D routes all fees to ValidatorFeeVault, which then pushes Treasury and burn shares out. This couples too many responsibilities into one contract. Model C's FeeDistributor is a cleaner separator.

### 8.2 Conclusion

**Model C is the correct architecture for PrimeWave's 70/20/10 fee split.**

It is consistent with the locked PW-C00 design (`RewardManager → FeeDistributor → 70/20/10`), fully feasible within Avalanche EVM's native primitives, and requires exactly the set of contracts already planned: `FeeDistributor`, `ValidatorFeeVault`, `PrimeWaveTreasury`.

---

## 9. Recommended Architecture

### 9.1 Production Precompile Configuration (Genesis)

```json
{
  "config": {
    "feeManagerConfig": {
      "blockTimestamp": 0,
      "adminAddresses": ["<EMERGENCY_MULTISIG_ADDRESS>"]
    },
    "rewardManagerConfig": {
      "blockTimestamp": 0,
      "adminAddresses": ["<EMERGENCY_MULTISIG_ADDRESS>"],
      "initialRewardConfig": {
        "rewardAddress": "<FEE_DISTRIBUTOR_ADDRESS>"
      }
    }
  }
}
```

**DO NOT** include `nativeMinterConfig`. **DO NOT** include `allowFeeRecipients: true`.

### 9.2 Contract Stack Required (PW-C03+)

| Contract | Role | Priority |
|---|---|---|
| `FeeDistributor.sol` | Receives all fees; distributes 70/20/10 | PW-C03 |
| `ValidatorFeeVault.sol` | Pools 70% validator share; distributes by weight | PW-C03 |
| `PrimeWaveTreasury.sol` | Multisig + timelock treasury | PW-C03 |
| `PoAManager.sol` | Validator set management (from icm-services) | PW-C03 |

### 9.3 Operational Requirements

- `FeeDistributor.distribute()` must be called to flush accumulated fees
- Options: (a) anyone can call (incentivized by gas reward), (b) keeper bot, (c) called by validators
- Recommended: public `distribute()` function; any caller receives a small gas bounty (e.g. 0.1% of distributed amount)
- Minimum distribution threshold to prevent micro-distributions (e.g. 0.01 PW)

---

## 10. Security Implications

| Risk | Description | Mitigation |
|---|---|---|
| RewardManager admin compromise | Admin can redirect all fees to attacker's address | Admin = Emergency Multisig (3-of-5); 48h timelock |
| FeeDistributor math error | Integer overflow/underflow in fee split | Use SafeMath or Solidity ≥0.8.0 overflow protection; invariant testing |
| FeeDistributor upgrade | Malicious upgrade redirects fees | UUPS proxy + timelock + Multisig; or make immutable |
| ValidatorFeeVault drain | Admin drains validator fees | Non-custodial design: validators pull, contract never pushes |
| Treasury governance | Treasury can be drained | 3-of-5 multisig + 48h timelock required |
| Burn address reuse | Funds sent to 0x...dead might be non-zero start | Burn to 0x...dead is safe; verify at genesis it has 0 balance |

---

## 11. Gas Implications

| Operation | Estimated Gas | Notes |
|---|---|---|
| `FeeDistributor.distribute()` | ~50,000 gas | Simple balance split to 3 addresses |
| `ValidatorFeeVault.distribute()` | ~21,000 × N gas | N = number of validators; 15 validators ≈ 315K gas |
| `ValidatorFeeVault.claim()` | ~25,000 gas per validator | Pull model; validator initiates |
| FeeManager admin call | ~30,000 gas | Change fee parameters |
| RewardManager admin call | ~30,000 gas | Change fee destination |

Gas costs are payable in PW. At 25 gwei base fee: distribute() costs ≈ 0.00125 PW per call.

---

## 12. Upgrade Implications

| Upgrade | Mechanism | Risk |
|---|---|---|
| Change fee parameters | FeeManager admin → setFeeConfig() | Low — no state change; 48h timelock |
| Change fee destination | RewardManager admin → setRewardAddress() | Medium — affects all future fees; 48h timelock |
| Upgrade FeeDistributor | UUPS proxy pattern + Multisig + Timelock | Medium — audit required before upgrade |
| Change split percentages | Immutable constants in FeeDistributor | HIGH — requires contract upgrade and timelock |
| Emergency pause | EmergencyMultisig → FeeDistributor.pause() | Low — fees accumulate, no loss |

---

## 13. Supply-Invariant Implications

**The 70/20/10 fee architecture is FULLY COMPATIBLE with the 100M PW supply invariant.**

| Check | Result |
|---|---|
| Does fee routing create new PW? | ❌ NO — redistributes existing PW only |
| Does NativeMinter interact with fee routing? | ❌ NO — NativeMinter is inactive |
| Does FeeDistributor mint? | ❌ NO — it only splits received balance |
| Does ValidatorFeeVault mint? | ❌ NO — it distributes from accumulated fees |
| Does the burn permanently reduce supply? | ✅ YES (economically) — PW sent to 0x...dead is inaccessible |
| Can fee routing cause supply > 100M? | ❌ IMPOSSIBLE — NativeMinter is not active |

**Supply invariant at all times:**
```
CIRCULATING_PW = genesis_supply - burned_fees - RewardVault_balance
              = 100,000,000 PW - Σ(10% of all historical fees) - RewardVault.balance()
```

---

## 14. Open Questions

| # | Question | Priority | Required For |
|---|---|---|---|
| OQ-C02-01 | Exact `distribute()` incentive mechanism — who calls it and how? | 🟠 High | PW-C03 |
| OQ-C02-02 | Should FeeDistributor be upgradeable (UUPS) or immutable? | 🟠 High | PW-C03 |
| OQ-C02-03 | What is the minimum PW threshold before `distribute()` is callable? | 🟡 Medium | PW-C03 |
| OQ-C02-04 | Should ValidatorFeeVault distribution be auto or pull-based? | 🟠 High | PW-C03 |
| OQ-C02-05 | What uptime threshold qualifies a validator for fee share? | 🟠 High | PW-C03 |
| OQ-C02-06 | Is `0x000...dead` the preferred burn address or should we use `0x0100...`? | 🟡 Medium | PW-C03 |
| OQ-C02-07 | FeeDistributor address in production genesis — how is it set before deployment? | 🟠 High | PW-C03 |
| OQ-C02-08 | Does WarpMessenger need explicit configuration in production genesis for L1 validator management? | 🟠 High | PW-C03 |

---

*Analysis: PW-C02 | Fee Architecture Validation | 2026-08-13 | LOCAL DEV ONLY*
