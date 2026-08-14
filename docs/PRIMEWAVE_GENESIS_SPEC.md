# PrimeWave Chain — Genesis Specification
**Sprint PW-C00 | Status: DESIGN DOCUMENT — NOT FOR PRODUCTION**

---

## 1. Overview

The genesis file defines the first block of PrimeWave Chain. It is permanent and immutable — no genesis corrections are possible after chain launch. This document specifies the architecture of the genesis file.

> **CRITICAL:** Do NOT finalize or create the production genesis file during PW-C00. This is a specification only.

---

## 2. Chain Configuration Parameters

| Parameter | Value | Notes |
|---|---|---|
| Chain Name | PrimeWave Chain | |
| Network Name | primewave | |
| Native Symbol | PW | |
| Decimals | 18 | Standard EVM (wei) |
| Chain ID | TBD — see Section 3 | Do NOT finalize in PW-C00 |
| Target Block Time | ~2 seconds | Validate on testnet |
| EVM Compatibility | Full | Subnet-EVM |
| Gas Model | EIP-1559 | Standard Subnet-EVM |
| Snowman++ | YES | Avalanche BFT consensus |

---

## 3. Chain ID Selection Process

> **HARD RULE:** Do NOT select a production Chain ID during PW-C00.

### 3.1 Why Chain ID Matters

- Chain ID is embedded in every signed transaction (EIP-155 replay protection)
- It appears in wallet configurations and dApp integrations permanently
- A duplicate Chain ID causes replay attack vulnerabilities between chains sharing the same ID
- Chain ID cannot be changed after genesis without breaking all existing signed transactions

### 3.2 Selection Process (Pre-Mainnet)

1. **Testnet Chain ID:** Choose a temporary, unique testnet Chain ID (e.g., 77777 or similar — verify uniqueness at testnet time)
2. **Mainnet Chain ID selection:**
   a. Check [chainlist.org](https://chainlist.org) for all registered Chain IDs
   b. Check [ethereum-lists/chains GitHub](https://github.com/ethereum-lists/chains) for all registered chains
   c. Select an unregistered ID (avoid IDs < 1000 as most are taken; prefer 5+ digit IDs)
   d. Reserve the ID by submitting a PR to ethereum-lists/chains before mainnet launch
   e. Document the selected ID with rationale

3. **Candidate range for consideration:** 12345-series or custom memorable number — to be decided during testnet preparation sprint

> This selection MUST happen before mainnet genesis is created, NOT before testnet.

---

## 4. Genesis Structure (Skeleton)

```json
{
  "config": {
    "chainId": <TBD — DO NOT FILL YET>,
    "homesteadBlock": 0,
    "eip150Block": 0,
    "eip155Block": 0,
    "eip158Block": 0,
    "byzantiumBlock": 0,
    "constantinopleBlock": 0,
    "petersburgBlock": 0,
    "istanbulBlock": 0,
    "muirGlacierBlock": 0,
    "subnetEVMTimestamp": 0,
    "feeConfig": {
      "gasLimit": 15000000,
      "targetBlockRate": 2,
      "minBaseFee": 1000000000,
      "targetGas": 10000000,
      "baseFeeChangeDenominator": 36,
      "minBlockGasCost": 0,
      "maxBlockGasCost": 1000000,
      "blockGasCostStep": 200000
    },
    "rewardManagerConfig": {
      "blockTimestamp": 0,
      "initialRewardConfig": {
        "rewardAddress": "<FeeDistributor contract address>"
      }
    },
    "contractNativeMinterConfig": null,
    "allowListConfig": null
  },
  "alloc": {
    "<PWSwap Liquidity address (multisig)>": {
      "balance": "0x1A784379D99DB42000000"
    },
    "<PrimeWave Treasury address (multisig + timelock)>": {
      "balance": "0xC685FA11FB8E8000000"
    },
    "<Team & Development address (multisig + vesting)>": {
      "balance": "0x84595161401484A000000"
    },
    "<RewardVault contract address>": {
      "balance": "0xC685FA11FB8E8000000"
    },
    "<Presale Phase 1 address>": {
      "balance": "0x422CA8B0A00A425000000"
    },
    "<Presale Phase 2 address>": {
      "balance": "0x633B29DC4AE20F4000000"
    },
    "<Presale Phase 3 address>": {
      "balance": "0x633B29DC4AE20F4000000"
    }
  },
  "difficulty": "0x0",
  "gasLimit": "0xE4E1C0",
  "nonce": "0x0",
  "timestamp": "<TBD — mainnet launch datetime in Unix hex>",
  "extraData": "0x",
  "mixHash": "0x0000000000000000000000000000000000000000000000000000000000000000"
}
```

### 4.1 Balance Values (wei)

| Allocation | PW Amount | Wei (hex) |
|---|---|---|
| PWSwap Liquidity | 40,000,000 PW | 0x1A784379D99DB42000000 |
| Treasury | 15,000,000 PW | 0xC685FA11FB8E8000000 |
| Team | 10,000,000 PW | 0x84595161401484A000000 |
| Validator Rewards | 15,000,000 PW | 0xC685FA11FB8E8000000 |
| Presale Phase 1 | 5,000,000 PW | 0x422CA8B0A00A425000000 |
| Presale Phase 2 | 7,500,000 PW | 0x633B29DC4AE20F4000000 |
| Presale Phase 3 | 7,500,000 PW | 0x633B29DC4AE20F4000000 |

> ⚠️ These hex values MUST be independently verified with a script before genesis creation. A calculation error is permanent.

### 4.2 Verification Script

Before genesis is finalized, run:
```python
# genesis_verify.py
allocations = {
    "PWSwap Liquidity": 40_000_000,
    "Treasury": 15_000_000,
    "Team": 10_000_000,
    "Validator Rewards": 15_000_000,
    "Presale P1": 5_000_000,
    "Presale P2": 7_500_000,
    "Presale P3": 7_500_000,
}
total = sum(allocations.values())
assert total == 100_000_000, f"SUPPLY ERROR: {total} != 100000000"
print(f"✅ Total supply verified: {total:,} PW")
for name, amount in allocations.items():
    wei = amount * 10**18
    print(f"  {name}: {amount:,} PW = {hex(wei)}")
```

---

## 5. Precompile Configuration

### 5.1 RewardManager (REQUIRED)

```json
"rewardManagerConfig": {
  "blockTimestamp": 0,
  "initialRewardConfig": {
    "rewardAddress": "<FeeDistributor contract address>"
  }
}
```

All block rewards (transaction fees) are sent to the `FeeDistributor` contract, which implements the 70/20/10 split.

### 5.2 NativeMinter (MUST NOT BE PRESENT)

The `contractNativeMinterConfig` key MUST either be absent or explicitly set to disable minting:

```json
"contractNativeMinterConfig": null
```

Or simply omit it. Do NOT add any address to minter or admin roles for the NativeMinter precompile.

### 5.3 WarpConfig (REQUIRED for ACP-77)

```json
"warpConfig": {
  "blockTimestamp": 0,
  "quorumNumerator": 67
}
```

Warp messaging is required for ValidatorManager ↔ P-Chain communication.

---

## 6. Pre-deployed Contracts

The following contracts must be deployed at genesis or immediately post-genesis before any validator registration:

| Contract | Deploy Method | Notes |
|---|---|---|
| `RewardVault` | Genesis `alloc` bytecode OR immediate post-genesis deploy | Must hold 15M PW |
| `FeeDistributor` | Immediate post-genesis | Must be set as RewardManager address |
| `PrimeWaveTreasury` | Immediate post-genesis | Multisig + timelock |
| `EmergencyMultisig` | Immediate post-genesis | |
| `PoAValidatorManager` | Immediate post-genesis | Before any validator registration |
| `PWUSD` | Immediate post-genesis | |

> Genesis `alloc` bytecode deployment is complex. Recommend deploying contracts in the first block via a dedicated deployer address that is pre-funded at genesis. Deployer address should be burned/zeroed after deployment.

---

## 7. Initial Validator Structure and Bootstrap Sequence (OQ-002 Resolved)

PrimeWave Chain uses the **standard Avalanche L1 creation and bootstrap sequence** — no custom mechanism.

### 7.1 Standard Bootstrap Sequence

```
Step 1: L1 Creation
  Avalanche CLI: avalanche subnet create primewave-chain
  → Issues CreateSubnetTx on P-Chain
  → Produces subnetID (permanent identifier)

Step 2: Genesis and Chain Creation
  → Genesis file reviewed and verified (supply = 100,000,000 PW)
  → Avalanche CLI: avalanche subnet deploy (testnet) or equivalent
  → Issues CreateChainTx on P-Chain with genesis file
  → Produces blockchainID (PrimeWave Chain's EVM chainID)
  → Subnet-EVM starts from genesis alloc block

Step 3: L1 Conversion (ACP-77 — ConvertSubnetToL1Tx)
  → PoAManager contract deployed at this point
  → Issues ConvertSubnetToL1Tx on P-Chain referencing:
      - PoAManager contract address
      - Initial bootstrap validator set (15 validators, specified in conversion tx)
  → Chain becomes sovereign (ACP-77 L1 status)
  → No AVAX stake required for validators

Step 4: Validator Manager Initialization
  → PoAManager.initializeValidatorSet() called on EVM
  → Warp confirmations received from P-Chain for each initial validator
  → All 15 validators registered in ValidatorManager state

Step 5: Network Activation
  → All 15 validators confirmed active
  → Block production under Snowman++ BFT
  → Core contracts deployed: RewardVault, FeeDistributor, PWUSD, Treasury
  → RPC endpoints operational
  → Network open for transactions
```

### 7.2 What Is Standard vs. PrimeWave Custom

| Step | Classification | Notes |
|---|---|---|
| CreateSubnetTx | ✅ Standard Avalanche | No customization |
| CreateChainTx | ✅ Standard + PrimeWave genesis file | Genesis alloc is PrimeWave-specific |
| ConvertSubnetToL1Tx | ✅ Standard Avalanche + PrimeWave PoAManager address | |
| PoAManager contract | ✅ Standard ACP-99 (from `ava-labs/icm-services`) | Used as-is, no modification |
| Genesis alloc (100M PW distribution) | 🔵 PrimeWave custom configuration | Specific to PrimeWave tokenomics |
| RewardVault contract | 🔵 PrimeWave custom contract | Not part of Avalanche standard |
| FeeDistributor contract | 🔵 PrimeWave custom contract | Not part of Avalanche standard |
| PWUSD contract | 🔵 PrimeWave custom contract | Not part of Avalanche standard |

### 7.3 The Bootstrap Validator Question (Resolved)

The initial bootstrap validators are specified directly in `ConvertSubnetToL1Tx`. This is the standard ACP-77 mechanism — the conversion transaction itself sets the initial validator set on the P-Chain. The EVM `initializeValidatorSet()` call then mirrors this state. There is no ambiguity about who produces the first blocks: they are produced by the 15 validators specified in the conversion transaction from the moment the chain is sovereign.

---

## 8. Genesis Security Review Process

Before mainnet genesis:

1. [ ] Genesis file reviewed line-by-line by ≥3 independent parties
2. [ ] Genesis allocation script run and verified
3. [ ] Genesis deployed to internal testnet and verified
4. [ ] Genesis deployed to public testnet and verified
5. [ ] Chain ID confirmed unique and registered
6. [ ] Genesis hash computed and published
7. [ ] All validators confirm they can start their nodes from this genesis
8. [ ] Block 0 verified on all validator nodes
9. [ ] No NativeMinter admin/minter roles present
10. [ ] RewardManager points to correct FeeDistributor address

---

*This document is a PW-C00 design specification. No production deployment has occurred.*

---

## 8. Funding Procedure (C11)

The RewardVault must be funded with exactly **15,000,000 PW** (15,000,000 × 10¹⁸ wei) immediately after contract deployment.

### 8.1 Address Placeholders (pre-ceremony)

These addresses are NOT yet generated. They will be produced during the Production Deployment Ceremony:

| Contract | Address |
|---|---|
| `FeeDistributor` | TBD — ceremony output |
| `ValidatorFeeVault` | TBD — ceremony output |
| `DevTreasury` | TBD — ceremony output |
| `RewardVault` | TBD — ceremony output |
| `PrimeWaveValidatorRegistry` | TBD — ceremony output |
| `EmergencyMultisig` | TBD — ceremony output |
| `PrimeWaveTimelock` | TBD — ceremony output |
| Deployer (burn after ceremony) | TBD — ceremony output |

### 8.2 Funding Transaction

```bash
# Performed during Step 14 of Production Deployment Ceremony
# via DeployProduction.s.sol (step 14 is embedded in the script)

forge script contracts/script/DeployProduction.s.sol:DeployProduction \
  --sig "fundRewardVault()" \
  --rpc-url $CHAIN_RPC_URL \
  --broadcast \
  --private-key $DEPLOYER_KEY

# Hard invariant in script:
# require(totalFunded == 15_000_000 * 10**18, "FUNDING INVARIANT FAILED");
```

### 8.3 Verification

```bash
bash scripts/validate-production-genesis.sh $CHAIN_RPC_URL 73571

# Section 5 of the script checks:
# - rewardVaultBalance >= 15_000_000 * 10**18
```

### 8.4 Why Exactly 15M

See `docs/PW-C00-FINAL-GATE.md` and `docs/PRIMEWAVE_TOKENOMICS.md`.
- Total supply: 100M PW (fixed, immutable)
- Reward allocation: 15M PW (5 years at 3M PW/year initial rate)
- This is a one-time transfer from the deployer genesis allocation — not a mint

---

*Updated C11: Funding procedure, address placeholders, and verification script added.*
