# PW-C14: Testnet Genesis
**Sprint:** PW-C14
**Status:** TEMPLATE COMPLETE — Pending ceremony addresses
**Environment:** TESTNET ONLY — Chain ID 77777

---

## 1. Genesis Parameters

| Parameter | Value | Notes |
|---|---|---|
| Chain ID | **77777** | Testnet only — verify uniqueness before launch |
| Total Supply | 100,000,000 PW | Immutable — no NativeMinter |
| Block Gas Limit | 30,000,000 | Matches dev genesis |
| Target Block Rate | 2 seconds | |
| Min Base Fee | 25 Gwei | |
| NativeMinter | DISABLED | No new PW can ever be minted |
| WarpMessenger | ENABLED | ICM support (quorumNumerator: 67) |
| RewardManager | ENABLED | `rewardAddress` = FeeDistributor |

---

## 2. Genesis Allocations (100M PW Total)

| Recipient | Amount (PW) | Wei Hex | Notes |
|---|---|---|---|
| Testnet Deployer | 16,000,000 | `0xd3c21bcecceda10000000` | 15M → RewardVault + 1M ops |
| Testnet Treasury | 25,000,000 | `0x14adf4b7320334b9000000` | Governance/ops |
| Testnet Team | 20,000,000 | `0x108b2a2c28029094000000` | Rehearsal only |
| Testnet Community | 20,000,000 | `0x108b2a2c28029094000000` | Public testnet users |
| Testnet Ecosystem | 10,000,000 | `0x84595161401484a000000` | Partner rehearsal |
| Testnet Reserve | 9,000,000 | `0x771d2fa45345aa9000000` | Reserve |
| **Total** | **100,000,000** | `0x52b7d2dcc80cd2e4000000` | ✅ Invariant satisfied |

---

## 3. RewardVault Funding

The 15M PW RewardVault allocation is **NOT a genesis alloc** — it is transferred post-deploy:

```solidity
// DeployTestnet.s.sol
rewardVault.fund{value: 15_000_000 ether}();
require(rewardVault.totalFunded() == 15_000_000 ether, "FUNDING INVARIANT FAILED");
```

This follows the exact same mechanism as the production deployment (C11 DeployProduction.s.sol).

---

## 4. Precompile Configuration

| Precompile | Status | Address | Notes |
|---|---|---|---|
| ContractDeployerAllowList | DISABLED | — | Permissionless deployment |
| TxAllowList | DISABLED | — | Open network |
| FeeManager | DISABLED | — | Fixed gas price |
| **NativeMinter** | **DISABLED** | 0x0200000000000000000000000000000000000001 | No inflation possible |
| RewardManager | ENABLED | 0x0200000000000000000000000000000000000004 | Routes fees to FeeDistributor |
| WarpMessenger | ENABLED | 0x0200000000000000000000000000000000000005 | ICM/Warp messaging |

---

## 5. Genesis Construction Procedure

### Step 1: Deploy Contracts (Pre-Genesis)

Protocol contracts must be deployed **before** the genesis is finalized, because the genesis needs `rewardManagerConfig.rewardAddress` = FeeDistributor address.

**Option A: Nonce-based address prediction**
```bash
# Predict FeeDistributor address from deployer nonce
cast compute-address $DEPLOYER_ADDR --nonce $EXPECTED_NONCE
```

**Option B: CREATE2 deterministic deployment**
Use a deterministic deployer (e.g., ERC-2470 `SingletonFactory`) to pre-compute addresses.

### Step 2: Fill in Genesis Template

```bash
# Copy template
cp config/testnet/genesis-template.json config/testnet/genesis.json

# Replace all __REPLACE_*__ placeholders with ceremony-generated addresses
# (use sed or a fill-genesis.sh script)
```

### Step 3: Validate Genesis JSON

```bash
# Verify total supply = 100M PW
python3 -c "
import json
g = json.load(open('config/testnet/genesis.json'))
total = sum(int(v['balance'], 16) for k,v in g['alloc'].items() if not k.startswith('_'))
expected = 100_000_000 * 10**18
assert total == expected, f'Supply mismatch: {total} != {expected}'
print(f'Supply OK: {total // 10**18:,} PW')
print(f'Chain ID:  {g[\"config\"][\"chainId\"]}')
"

# Hash genesis file
sha256sum config/testnet/genesis.json
```

### Step 4: Validate NativeMinter Disabled

```bash
python3 -c "
import json
g = json.load(open('config/testnet/genesis.json'))
precompiles = g.get('config', {}).get('precompiles', {})
minter_addr = '0x0200000000000000000000000000000000000001'
assert minter_addr not in precompiles, 'ERROR: NativeMinter found in precompiles!'
print('OK: NativeMinter not in precompiles')

# Also check alloc doesn't have minter
alloc = g.get('alloc', {})
minter_key = minter_addr.lower().lstrip('0x')
for key in alloc:
    if key.lower().replace('0x','').lstrip('0') == minter_key.lstrip('0'):
        print(f'WARNING: Minter address found in alloc: {key}')
        break
else:
    print('OK: NativeMinter not in alloc')
"
```

### Step 5: Record Genesis Hash

```bash
GENESIS_HASH=$(sha256sum config/testnet/genesis.json | awk '{print $1}')
echo "Genesis SHA-256: $GENESIS_HASH"
# Record in docs/PW-C14-TESTNET-DEPLOYMENT-MANIFEST.md
```

---

## 6. Reproducibility

Given the same:
- Testnet addresses (from ceremony)
- AvalancheGo version (v1.14.2)
- Subnet-EVM version (v1.14.2)
- Genesis template (from this repo)

The same genesis file can be reproduced and verified by SHA-256 hash.

---

## 7. Genesis Invariants (Verification Checklist)

| ID | Invariant | Verification |
|---|---|---|
| INV-G1 | Chain ID == 77777 | `jq '.config.chainId' genesis.json` |
| INV-G2 | NativeMinter not in precompiles | `jq '.config.precompiles' genesis.json \| grep -i minter` |
| INV-G3 | Total alloc == 100M PW | Python sum script (Step 3 above) |
| INV-G4 | rewardManagerConfig.rewardAddress == FeeDistributor | `jq '.config.rewardManagerConfig.initialRewardConfig.rewardAddress'` |
| INV-G5 | WarpConfig present with quorumNumerator: 67 | `jq '.config.warpConfig'` |
| INV-G6 | No dev EOA keys in production genesis | Address audit against `config/dev/dev-keys.md` |
| INV-G7 | Genesis hash recorded and signed | SHA-256 in manifest |
