# PW-C17 — FeeDistributor Deterministic Deployment Analysis
## PrimeWave Testnet: Genesis Mismatch Root Cause & Resolution

**Report date:** 2026-08-17  
**Status:** ANALYSIS COMPLETE — awaiting operator authorization for chain recreation  
**No transactions executed. No files modified. Read-only analysis.**

---

## 1. Root Cause

### Problem Statement

The Avalanche EVM credits block transaction fees to the address configured in genesis `rewardManagerConfig.initialRewardConfig.rewardAddress`. On PrimeWave Testnet, this address is `0x27B15970700daC632f0814522118A1c3B200d971`. This address was pre-computed during the PW-C15 key ceremony to be the address where the `FeeDistributor` contract would land after deployment.

The pre-computation assumed the deployer's EVM nonce would be **0** at the time `DeployTestnet.s.sol` was first broadcast. This assumption was violated.

### What Actually Happened

During the PW-C16 chain-launch sprint, the deployer key (`0xB518397E3D65a0E7475635F01C225E9426a76F11`) was used to send **5 transactions** (nonces 0–4) to trigger block production and run chain diagnostics. The deployer's current nonce on the live chain is **5**.

This means the FeeDistributor, if deployed now, would land at nonce **9** (5 + 4 from script position), not nonce **4**. These are different addresses.

---

## 2. Current Nonce State

| Item | Value |
|---|---|
| Deployer address | `0xB518397E3D65a0E7475635F01C225E9426a76F11` |
| Current nonce on live chain | **5** |
| Nonces consumed by | Kick TX ×1 (nonce 0), diagnostic TXs ×3 (nonces 1–3), final diagnostic TX ×1 (nonce 4) |
| Current block height | 4 |

---

## 3. How FeeDistributor Address is Currently Derived

### Ethereum CREATE Opcode

All contracts in `DeployTestnet.s.sol` are deployed using the Solidity `new` keyword, which compiles to the EVM `CREATE` opcode. The address of a `CREATE` deployment is:

```
address = keccak256(RLP([deployer_address, nonce]))[12:]
```

This is nonce-based and deterministic for a given (deployer, nonce) pair. It is NOT random, NOT time-dependent, and does NOT depend on constructor arguments in the address computation (only in the initcode that gets stored). The address depends **only** on deployer address and the deployer's nonce at the time of that specific deployment transaction.

### DeployTestnet.s.sol Deployment Order

```
vm.startBroadcast()

nonce N+0 → EmergencyMultisig (5 signers)
nonce N+1 → PrimeWaveTimelock (deployer)
  [vm.getNonce(deployer) → returns N+2]
  predictedFD       = computeCreateAddress(deployer, N+4)  ← MUST match genesis
  predictedRegistry = computeCreateAddress(deployer, N+5)
nonce N+2 → ValidatorFeeVault(predictedRegistry)
nonce N+3 → DevTreasury(predictedFD)
nonce N+4 → FeeDistributor(feeVault, devTreasury, ems)   ← lands at predictedFD
nonce N+5 → PrimeWaveValidatorRegistry(deployer, POA, feeVault)  ← lands at predictedRegistry
nonce N+6 → RewardVault(deployer, INITIAL_RATE)
nonce N+7 → setPauseController(ems)  [tx, not deploy]
nonce N+8 → fund{15M PW}()  [tx, not deploy]
```

**Key observation:** The genesis `rewardAddress` must equal `computeCreateAddress(deployer, N+4)` where **N** is the deployer's nonce at the start of broadcast. The genesis was finalized with `N=0`. The live chain has `N=5`.

### Script Self-Consistency vs Genesis Consistency

The script contains `require(address(feeDist) == predictedFD)`. This check is **internally consistent** — it guarantees FeeDistributor lands where the script predicted. It does NOT guarantee FeeDistributor lands where genesis expected. These are the same only when N=0.

---

## 4. Current Genesis `rewardAddress`

| Item | Value |
|---|---|
| Genesis `rewardManagerConfig.rewardAddress` | `0x27B15970700daC632f0814522118A1c3B200d971` |
| How it was computed | `cast compute-address $DEPLOYER --nonce 4` (assumes N=0) |
| This is correct for | Deployer nonce 0, FD at nonce 4 |
| This is WRONG for | Deployer nonce 5, FD lands at nonce 9 |

---

## 5. Current Predicted FeeDistributor Address

If deployed right now (deployer nonce = 5):

| Nonce | Contract |
|---|---|
| 5 | EmergencyMultisig |
| 6 | PrimeWaveTimelock |
| 7 | ValidatorFeeVault |
| 8 | DevTreasury |
| **9** | **FeeDistributor → `0x8C41F8A20C63f174C27B9dc9A610615c36c801Ca`** |
| 10 | PrimeWaveValidatorRegistry |
| 11 | RewardVault |

**FeeDistributor at nonce 9 = `0x8C41F8A20C63f174C27B9dc9A610615c36c801Ca`**

This does NOT match genesis `rewardAddress`. Fee routing would be permanently broken.

---

## 6. Deterministic Deployment Options

### Option A — CREATE2 Deployment (FeeDistributor only)

**Mechanism:** Deploy FeeDistributor via a CREATE2 factory with a fixed salt. CREATE2 address formula:
```
address = keccak256(0xff ++ factory_address ++ salt ++ keccak256(initcode))[12:]
```

**Feasibility:** PARTIAL. FeeDistributor's initcode includes constructor args `(feeVault, devTreasury, ems)`. The `feeVault` and `devTreasury` addresses are themselves nonce-derived CREATE deployments and their addresses change with the deployer nonce. Therefore:

- FeeDistributor CREATE2 address depends on feeVault and devTreasury addresses
- feeVault and devTreasury addresses depend on deployer nonce
- CREATE2 for FD alone still inherits nonce dependency from its constructor args

**Does it change contract bytecode?** No — the FeeDistributor contract is unchanged; only the deployment transaction differs.

**Does it allow address to be known before genesis?** Only if feeVault and devTreasury addresses are ALSO known before genesis — which still requires nonce control.

**Genesis regen required?** Yes (new genesis rewardAddress).

**Introduces new trust/security dependency?** Yes — a CREATE2 factory contract must be trusted and operational on the new chain before FeeDistributor can be deployed. The ERC-2470 SingletonFactory or equivalent must be deployed first (itself a pre-deployment transaction, consuming a nonce).

**Verdict: Does not eliminate nonce dependency if only FD uses CREATE2. Adds complexity.**

---

### Option B — CREATE2 for ALL Contracts

**Mechanism:** Deploy all 7 contracts via CREATE2 with fixed salts and a common factory.

**Feasibility:** BLOCKED by circular constructor dependency.

The deployment graph has a circular dependency:
```
ValidatorFeeVault constructor  →  requires predictedRegistry address  (CREATE nonce or CREATE2 address)
ValidatorRegistry constructor  →  requires feeVault address           (CREATE nonce or CREATE2 address)
```

With CREATE2 for both: the address of each contract depends on its initcode hash, which includes constructor args, which include the other contract's address. This is a chicken-and-egg problem with no mathematical solution using pure CREATE2. Both addresses depend on each other.

**Resolution would require architectural changes:**
- Remove `protocolAdmin = predictedRegistry` from ValidatorFeeVault constructor (make it settable post-deploy)  
- Or: use a two-phase initialization pattern (deploy with placeholder admin, call initialize() after)
- Both changes alter the security model (introduce a mutable admin during deployment window)

**Verdict: Feasible only with significant contract redesign. Not recommended for a production-intent testnet.**

---

### Option C — Deploy a Dedicated CREATE2 Factory

**Mechanism:** Deploy a custom or standard CREATE2 factory (e.g., ERC-2470) to the new chain, then use it to deploy FeeDistributor.

**Feasibility:** Same limitations as Option A. The factory is nonce-independent for FeeDistributor's address, but FeeDistributor's constructor args (feeVault, devTreasury) are still nonce-derived.

**Additionally:** Deploying the factory itself consumes a deployer nonce, which shifts all subsequent nonces anyway.

**Verdict: No advantage over Option A. Adds a factory deployment step with no benefit.**

---

### Option D — Deliberately Controlling the Deployer Nonce

**Mechanism:** Accept the nonce-based address model, but make the nonce a controlled input. The procedure is:

1. Record the exact nonce the deployer will have at broadcast time
2. Compute FD address: `cast compute-address $DEPLOYER --nonce $(( nonce + 4 ))`
3. Set this address as `rewardAddress` in genesis
4. Finalize genesis with this address
5. Create blockchain
6. Enforce: deployer sends exactly this many pre-deployment TXs (or zero)
7. Deploy contracts

**Feasibility:** FULLY FEASIBLE. This is what the original process was supposed to do.

**Does it change contract bytecode?** No.

**Does genesis need to be regenerated?** Yes — but only the `rewardAddress` field changes. All other fields remain the same.

**Does the address depend on constructor arguments?** No — CREATE address is only function of (deployer, nonce). Constructor args do not affect it.

**Can the address be known before genesis?** YES — perfectly, as long as the exact nonce at deployment time is known in advance.

**Trust/security dependency?** None. Pure Ethereum determinism.

**Verdict: Fully feasible. No architectural changes. No new dependencies. Requires procedural discipline.**

---

### Option E — Nonce-Controlled with Fresh Chain (Zero Pre-Deployment TXs)

**Mechanism:** A special case of Option D where we commit to zero pre-deployment transactions. On a fresh chain, the deployer's nonce is always 0. FeeDistributor is always at nonce 4. The genesis `rewardAddress` is always `cast compute-address $DEPLOYER --nonce 4`.

**Feasibility:** FULLY FEASIBLE — and notably, the existing genesis.json already contains the correct `rewardAddress` for this exact scenario.

- Genesis `rewardAddress = 0x27B15970700daC632f0814522118A1c3B200d971` = `computeCreateAddress(deployer, 4)` ✓
- This remains correct on any fresh chain using the same deployer key
- No genesis change required

**Does it require genesis regeneration?** NO. The existing `config/testnet/genesis.json` is already correct for deployer nonce 0.

**What blocks are needed to start the chain?** None from the deployer. AvalancheGo produces blocks automatically based on validator activity — empty blocks if no transactions, populated blocks when transactions arrive. The PW-C16 block-kick transactions were diagnostic, not operationally required.

**Trust/security dependency?** None.

**Verdict: OPTIMAL. Zero new dependencies, zero contract changes, zero genesis changes, zero architecture changes. Requires one procedural rule: deployer key must not be used before DeployTestnet.s.sol.**

---

## 7. Recommended Architecture

### Recommendation: Option E — Nonce-Zero Controlled Deployment

**Rationale:**

| Criterion | Option A (CREATE2/FD) | Option B (CREATE2/All) | Option D (Nonce Control) | Option E (Nonce Zero) |
|---|---|---|---|---|
| Eliminates nonce dependency | ❌ Partial | ✅ (with redesign) | ✅ | ✅ |
| Contract changes required | ❌ None | ❌ Major | ✅ None | ✅ None |
| Genesis changes required | ❌ Yes | ❌ Yes | ❌ Yes | ✅ No |
| New trust dependencies | ❌ Factory trust | ❌ Factory trust | ✅ None | ✅ None |
| Address predictable pre-genesis | ❌ Partial | ✅ | ✅ | ✅ |
| Deployment complexity | ↑ Higher | ↑↑ Much higher | → Same | → Same |
| Robustness to future nonce drift | ❌ No | ✅ Yes | ❌ Depends | ❌ Depends (but procedurally clear) |

Option E wins across all criteria relevant to testnet. The only drawback relative to full CREATE2 is that a future operator could accidentally send a pre-deployment TX and create a new mismatch. This risk is eliminated by:

1. A clear, documented rule: **the deployer key MUST NOT be used for any purpose before `DeployTestnet.s.sol` completes**
2. Embedding a nonce check in the deployment script (see §8 below)
3. Block production uses AvalancheGo's natural block scheduling (no TX required)

---

## 8. Exact Deployment Sequence

### Pre-Conditions (before any on-chain action)

1. New blockchain exists and RPC is reachable
2. `eth_chainId = 0x4d` (77)
3. `eth_getTransactionCount(deployer, "latest") = 0x0` (MUST BE ZERO)
4. Deployer balance ≥ 15,001 PW
5. Forge build passes

### Recommended Script Addition (nonce guard)

Add the following check to `DeployTestnet.s.sol` immediately after the existing chain ID guard:

```solidity
// Hard guard: deployer nonce must be 0 to guarantee FeeDistributor lands at genesis rewardAddress
require(
    uint64(deployer.code.length) == 0 && tx.origin == deployer,
    "DeployTestnet: sanity"
);
uint64 deployerNonce = vm.getNonce(deployer);
require(
    deployerNonce == 0,
    string(abi.encodePacked(
        "DeployTestnet: deployer nonce is ", vm.toString(uint256(deployerNonce)),
        " (must be 0 — ensure no pre-deployment transactions were sent)"
    ))
);
```

This guard makes the script self-enforcing: if the deployer has sent any pre-deployment TXs, the script reverts before any gas is spent.

### Deployment Command

```bash
BLOCKCHAIN_ID=<new_blockchain_id>
TESTNET_RPC_URL="http://159.195.47.126/ext/bc/$BLOCKCHAIN_ID/rpc"

# Read deployer key from validator server
# NEVER print or log the key
forge script contracts/script/DeployTestnet.s.sol:DeployTestnet \
  --rpc-url "$TESTNET_RPC_URL" \
  --private-key "$TESTNET_DEPLOYER_KEY" \
  --broadcast \
  --via-ir \
  -vvv
```

### Post-Deployment Verification

After broadcast, verify on-chain:
- `eth_getCode(0x27B15970700daC632f0814522118A1c3B200d971)` → must return FeeDistributor bytecode (non-empty)
- FeeDistributor.validatorFeeVault() → must return ValidatorFeeVault address
- FeeDistributor.pauseController() → must return EmergencyMultisig address
- RewardVault.totalFunded() → must return 15,000,000 × 10^18

---

## 9. Exact Genesis-Generation Sequence

**Genesis.json does NOT need to be modified.** The existing `config/testnet/genesis.json` is already correct for this deployment.

The genesis template (`config/testnet/genesis-template.json`) has placeholder `__REPLACE_FEE_DISTRIBUTOR_ADDRESS__`. This was filled with `0x27B15970700daC632f0814522118A1c3B200d971` during the key ceremony, which equals `cast compute-address $DEPLOYER --nonce 4` (deployer nonce 0, FD at position 4). This is correct and remains correct for any fresh-chain deployment with the same deployer key.

**Verification that genesis is already correct:**

```bash
CAST=local-bin/foundry/cast
DEPLOYER="0xB518397E3D65a0E7475635F01C225E9426a76F11"
GENESIS_FD="0x27B15970700daC632f0814522118A1c3B200d971"
COMPUTED=$($CAST compute-address $DEPLOYER --nonce 4 | grep Computed | awk '{print $NF}')
[ "${COMPUTED,,}" = "${GENESIS_FD,,}" ] && echo "MATCH ✓" || echo "MISMATCH ✗"
# Expected: MATCH ✓
```

This confirms no change to genesis.json is needed.

---

## 10. Chain Recreation Procedure

### Context

The current chain (Blockchain ID: `22iFuL8GqPYbtnPKNFrq7AzoDfv3FYwq8T93GubRi12LQVjLni`) is 4 blocks tall with 5 diagnostic transactions and no deployed contracts. It can be abandoned and a new blockchain deployed on the same subnet.

**Subnet ID remains unchanged:** `ovXTQNjfug8bipjnqnSKieZFdtHid2amTQnrbibg4kYQtrLbv`  
**Validator set remains unchanged:** V6, V7, V8, V9 (same keys, same NodeIDs, same weights)  
**Deployer key remains unchanged:** `0xB518397E3D65a0E7475635F01C225E9426a76F11` (nonce resets to 0 on new chain)

### Step-by-Step Procedure

> All steps in this section are read-only documentation. None have been executed.

---

**Step 1: Confirm the new FeeDistributor address will match genesis**

On the Replit machine (no network access required):

```bash
CAST=local-bin/foundry/cast
DEPLOYER="0xB518397E3D65a0E7475635F01C225E9426a76F11"
$CAST compute-address $DEPLOYER --nonce 4
# Must output: 0x27B15970700daC632f0814522118A1c3B200d971
```

---

**Step 2: Verify genesis.json is unchanged and correct**

```bash
python3 -c "
import json
g = json.load(open('config/testnet/genesis.json'))
fd = g['config']['rewardManagerConfig']['initialRewardConfig']['rewardAddress']
assert fd == '0x27B15970700daC632f0814522118A1c3B200d971', f'WRONG: {fd}'
print(f'genesis rewardAddress: {fd} ✓')
print(f'Chain ID: {g[\"config\"][\"chainId\"]}')
"
```

---

**Step 3: Deploy new blockchain on the existing subnet (operator action on validator server)**

The operator runs the following on V9 (or any validator with the Avalanche CLI and testnet-deployer key):

```bash
# Option 1: Re-deploy the blockchain configuration using the existing subnet
avalanche blockchain deploy primewavechain \
  --fuji \
  --subnet-id ovXTQNjfug8bipjnqnSKieZFdtHid2amTQnrbibg4kYQtrLbv \
  --genesis-file /path/to/config/testnet/genesis.json

# Record the new Blockchain ID from the output.
# It will be different from: 22iFuL8GqPYbtnPKNFrq7AzoDfv3FYwq8T93GubRi12LQVjLni
```

> **Note:** The exact Avalanche CLI command for adding a new blockchain to an existing L1 subnet must be verified against the CLI version in use (v1.9.5+). This may require `blockchain create` followed by `blockchain deploy`, or a different flow. The operator should consult `avalanche blockchain --help` on the validator.

---

**Step 4: Update nginx RPC configurations on all 4 validators**

Replace `22iFuL8GqPYbtnPKNFrq7AzoDfv3FYwq8T93GubRi12LQVjLni` with `<NEW_BLOCKCHAIN_ID>` in nginx configs on V6, V7, V8, V9.

---

**Step 5: Update local-data/testnet-key-addresses.env**

Change `TESTNET_BLOCKCHAIN_ID` to the new value.

---

**Step 6: Verify new chain is live and deployer nonce is 0**

```bash
NEW_BLOCKCHAIN_ID=<from_step_3>
RPC="http://159.195.47.126/ext/bc/$NEW_BLOCKCHAIN_ID/rpc"
DEPLOYER="0xB518397E3D65a0E7475635F01C225E9426a76F11"

# Chain ID check
curl -s -X POST $RPC -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'
# Expected: {"result":"0x4d"}

# CRITICAL: Deployer nonce must be 0
curl -s -X POST $RPC -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getTransactionCount\",\"params\":[\"$DEPLOYER\",\"latest\"],\"id\":2}"
# Expected: {"result":"0x0"}
```

---

**Step 7: Run the pre-deployment safety check and dry run**

```bash
# Run Phases 1-3 of the contract deployment prompt (with nonce guard added to script)
# Confirm ALL checks pass including deployer nonce == 0
```

---

**Step 8: Broadcast the deployment**

```bash
# From validator server with deployer key:
TESTNET_DEPLOYER_KEY=$(cat ~/.avalanche-cli/key/testnet-deployer.pk)
TESTNET_RPC_URL="http://159.195.47.126/ext/bc/$NEW_BLOCKCHAIN_ID/rpc"

cd /path/to/workspace/contracts
forge script script/DeployTestnet.s.sol:DeployTestnet \
  --rpc-url "$TESTNET_RPC_URL" \
  --private-key "0x$TESTNET_DEPLOYER_KEY" \
  --broadcast \
  --via-ir \
  -vvv
```

---

**Step 9: Verify FeeDistributor landed at genesis rewardAddress**

```bash
# FeeDistributor must have code at the genesis rewardAddress
cast code 0x27B15970700daC632f0814522118A1c3B200d971 --rpc-url $TESTNET_RPC_URL | head -c 20
# Must be non-empty (not "0x")
```

---

## 11. Risks

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| Another pre-deployment TX is accidentally sent before broadcast | Low (procedurally preventable) | High (breaks fee routing again) | Add nonce==0 guard to DeployTestnet.s.sol; run as first act on new chain |
| Blockchain creation fails on Fuji due to insufficient AVAX | Low | Medium | Operator confirms Fuji P-Chain balance before recreating |
| Wrong Blockchain ID used in nginx (old vs new) | Medium | Low (RPC failure, easily fixed) | Update all 4 validators in one session before deploying |
| Chain does not produce blocks after creation | Low | High | Validators should auto-produce once in sync |
| RewardManager precompile has no admin (can't change rewardAddress if nonce drift happens again) | Certain | High (same root cause) | Nonce guard in script prevents recurrence; documented rule |
| Deployer key is not accessible from Replit environment | Certain | Deployment requires operator | Deployment runs from validator server where key is stored; this is by design |
| Reusing the same deployer address on new chain creates address collisions with any off-chain expectations | Very low | Low | All contract addresses change with new chain; update configs accordingly |

---

## 12. Rollback / Abort Conditions

Abort chain recreation and hold if:

- Fuji P-Chain AVAX balance insufficient for new blockchain creation fee
- Avalanche CLI cannot locate or authenticate to the existing subnet
- The new blockchain does not appear in `eth_blockNumber` within 5 minutes of creation
- `eth_chainId` on the new blockchain does not return `0x4d` (77)
- Deployer nonce on new chain is not `0x0` before any TX is sent

If any abort condition is hit: do not send the deployer TX. The existing old chain can remain as-is (it has nothing deployed). A new recreation attempt can be made after diagnosing the abort condition.

---

## 13. Final GO / NO-GO

### GO — with chain recreation and nonce-zero procedural rule

| Gate | Status |
|---|---|
| Architecture is sound | ✅ Option E (nonce-zero) confirmed correct |
| Genesis.json is correct as-is | ✅ `rewardAddress = computeCreateAddress(deployer, 4)` confirmed |
| Genesis does NOT need to be modified | ✅ No changes to any file needed |
| Contract code does not need to be modified | ✅ No contract changes needed |
| DeployTestnet.s.sol logic is correct | ✅ Script is internally consistent |
| Recommended addition: nonce guard to script | ⚠️ Optional but strongly advised |
| Deployer key is the same (nonce resets on new chain) | ✅ Confirmed |
| Subnet ID is unchanged | ✅ Validators unchanged |
| Only blockchain ID changes | ✅ nginx config update required |
| Chain recreation destroys current state | ✅ Acceptable — 4 blocks, no contracts, no value |

### What is authorized by this GO

- Recreate the blockchain (new Blockchain ID) on the existing subnet
- Update nginx configs on all 4 validators with new Blockchain ID
- Update `local-data/testnet-key-addresses.env` TESTNET_BLOCKCHAIN_ID
- Optionally add nonce guard to `DeployTestnet.s.sol`
- Run contract deployment after confirming deployer nonce = 0

### What is NOT authorized

- Changing genesis.json
- Changing the Subnet ID
- Changing validator identities, keys, or weights
- Modifying any contract source code (unless nonce guard is added)
- Using the deployer key for any pre-deployment transaction on the new chain

---

## Summary Table

| Finding | Value |
|---|---|
| Root cause | 5 pre-deployment TXs consumed deployer nonces 0–4; FD now lands at nonce 9, not 4 |
| Genesis rewardAddress | `0x27B15970700daC632f0814522118A1c3B200d971` (correct for nonce 0) |
| Actual FD address if deployed now | `0x8C41F8A20C63f174C27B9dc9A610615c36c801Ca` (nonce 9) |
| Recommended fix | Option E: chain recreation, zero pre-deployment TXs, no genesis change |
| Genesis change needed | **NO** |
| Contract change needed | **NO** (nonce guard optional but recommended) |
| New blockchain ID | Will be assigned by Avalanche CLI at blockchain creation |
| Subnet ID | **Unchanged**: `ovXTQNjfug8bipjnqnSKieZFdtHid2amTQnrbibg4kYQtrLbv` |
| Validator set | **Unchanged**: V6 (144d…), V7 (cwX3…), V8 (7DLu…), V9 (9TiH…) |
| Deployer address | **Unchanged**: `0xB518397E3D65a0E7475635F01C225E9426a76F11` |
| Final verdict | **GO — chain recreation authorized, pending operator decision** |

---

*Analysis performed 2026-08-17. No transactions executed. No files modified.*
