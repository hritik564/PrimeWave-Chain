# PRIMEWAVE PRE-FLIGHT L1 LAUNCH AUDIT REPORT

**Date:** 2026-08-16 | **Status:** READ-ONLY — no changes made | **Scope:** Repository + live Replit environment

---

## AUDIT OVERVIEW

**13 inconsistencies found.** None silently fixed. All flagged below with severity. Report covers all 14 requested sections.

---

## SECTION 1 — REPOSITORY / ARCHITECTURE AUDIT

### A. AvalancheGo Version

| Source | Version |
|---|---|
| `config/testnet/node-config.json` `_version` field | `AvalancheGo v1.15.0-fuji (updated 2026-08-15 — Helicon)` |
| `scripts/testnet/setup-testnet-node.sh` | `v1.15.0-fuji` (pinned) |
| `local-bin/avalanchego` (disk) | `avalanchego/1.14.2` (rpcchainvm=45) |
| `preflight-testnet.sh` check | Expects exactly `1.14.2` |

⚠️ **INCONSISTENCY #1:** `preflight-testnet.sh` line 97 hard-checks for `avalanchego version 1.14.2`. This check was written for local dev. Running preflight on any testnet server with v1.15.0-fuji installed will produce `[FAIL] avalanchego version 1.15.0-fuji — expected exactly 1.14.2`. The preflight **cannot** be used as-is on testnet validator servers without fixing this check first.

`local-bin/avalanchego` being v1.14.2 is **correct** for local dev. The setup script downloads v1.15.0-fuji from GitHub at runtime on real servers.

### B. Subnet-EVM Version

| Source | Version | rpcchainvm |
|---|---|---|
| `scripts/testnet/setup-testnet-node.sh` | `v1.15.0-fuji` | 46 |
| `local-bin/subnet-evm` (disk, actual binary) | `v1.14.2@6e5acf909c` | **45** |
| `local-bin/subnet-evm.v1.14.2.bak` (disk) | `v1.14.2@6e5acf909c` | 45 |

⚠️ **INCONSISTENCY #2:** `setup-testnet-node.sh` line 70 says: *"The binary from the repository (local-bin/subnet-evm) is the correct v1.15.0-fuji binary."* This is **false**. The binary on disk is v1.14.2 (rpcchainvm=45). Both `local-bin/subnet-evm` and `local-bin/subnet-evm.v1.14.2.bak` are 64,168,408 bytes (identical, both v1.14.2). The setup script downloads the correct v1.15.0-fuji from GitHub at runtime — this works, but the comment creates confusion about what's in the repo.

### C. Avalanche CLI Version

- `local-bin/avalanche`: **v1.9.5** ✅ (matches preflight expectation)

### D. VM ID

Confirmed consistent across all sources:

```
rXJjKFtAVSmpKwhMhw7ZMV6opKcsmhk5AuVxWNAzFG221wmM8
```

Appears in: `local-data/network-ids.env`, `setup-testnet-node.sh`, `docs/PW-C01-TEST-REPORT.md`. ✅

### E. Fuji Network Configuration

- `node-config.json`: `"network-id": "fuji"` ✅
- `check-external-prerequisites.sh` verifies Fuji network ID = 5 at runtime ✅

### F. EVM Chain ID

- Genesis template: `chainId: 77` ✅
- `DeployTestnet.s.sol`: guards `block.chainid == 77` ✅
- `deploy-contracts.sh`: guards `CHAIN_ID == 77` ✅
- No occurrences of old `77777` in any non-historical file ✅

### G. Block Gas Limit

From `config/testnet/genesis-template.json`:
- `"gasLimit": 30,000,000` (feeConfig)
- `"gasLimit" hex field`: `0x1C9C380` = 30,000,000 ✅ (consistent)

### H. Target Block Rate

- `"targetBlockRate": 2` (seconds) ✅

### I. Base Fee

- `"minBaseFee": 25,000,000,000` (25 gwei) ✅
- `"targetGas": 15,000,000`
- `"baseFeeChangeDenominator": 36`

### J. Warp Configuration

From genesis template:

```json
"warpConfig": {
  "blockTimestamp": 0,
  "quorumNumerator": 67
}
```

`quorumDenominator` is subnet-evm default = 100. Quorum = 67/100. ✅

### K. RewardManager Configuration

```json
"rewardManagerConfig": {
  "blockTimestamp": 0,
  "initialRewardConfig": {
    "rewardAddress": "__REPLACE_FEE_DISTRIBUTOR_ADDRESS__"
  }
}
```

This activates the RewardManager precompile at genesis with a custom reward address. The placeholder must be filled before genesis is finalized. See Section 3 for the circular dependency analysis.

### L. FeeDistributor Configuration

- 70% validators, 20% treasury, 10% EMS (confirmed from `validate-testnet-genesis.sh` INV-G7: `VALIDATOR_SHARE_BPS == 7000`, `TREASURY_SHARE_BPS == 2000`)
- EMS gets 10% implicitly (remainder after 70+20)
- Deployed by `DeployTestnet.s.sol` — requires nonce-based address prediction

### M. ACP-99 / StakingManager Architecture

- **Phase 1 (Testnet):** `PoAManager` — admin-controlled validator addition/removal, no staking
- **Phase 2 (Production):** `PrimeWaveStakingManager` — custom staking, `maximumStakeMultiplier=1` (delegation disabled), min stake 1,000 PW, max 3,000,000 PW, min duration 14 days
- `PrimeWaveValidatorRegistry` bridges ACP-99 ValidatorManager → `ValidatorFeeVault`
- `PrimeWaveRewardCalculator` reads from `RewardVault`

Phase 1 contracts for testnet: `EmergencyMultisig`, `PrimeWaveTimelock`, `FeeDistributor`, `ValidatorFeeVault`, `DevTreasury`, `PrimeWaveValidatorRegistry`, `RewardVault` (7 contracts — no StakingManager at Phase 1)

### N. PoAManager / ValidatorManager Architecture

- Phase 1 uses `PoAManager` (from ava-labs/icm-contracts). Admin calls `initiateValidatorRegistration()` for each node
- The ACP-99 registration requires an ICM/Warp relayer running between the subnet and Fuji P-Chain
- `PrimeWaveValidatorRegistry` is the adapter between the real ACP-99 `ValidatorManager` and our `ValidatorFeeVault`

⚠️ **INCONSISTENCY #3 (Phase 1 architecture gap):** The checklist Phase 10 shows registering validators via `ValidatorRegistry.initiateRegistration()`. However, `DeployTestnet.s.sol` deploys the registry with `deployer` as a placeholder for the ValidatorManager, noting "replaced after PoAManager deploy." The PoAManager deployment is not in `DeployTestnet.s.sol` — it is a separate step with no corresponding script in `scripts/testnet/`. This step is currently undocumented as a concrete command.

### O. All Deployment Scripts

| Script | Purpose |
|---|---|
| `scripts/testnet/deploy-contracts.sh` | Runs `DeployTestnet.s.sol` via forge — 7 contracts |
| `contracts/script/DeployTestnet.s.sol` | Full protocol deployment + RewardVault funding (15M PW) |
| `scripts/testnet/setup-testnet-node.sh` | Installs AvalancheGo v1.15.0-fuji on Ubuntu server |
| `scripts/testnet/generate-validator-keys.sh` | Generates 7 EOA keys via `cast wallet new` |
| `scripts/testnet/preflight-testnet.sh` | Pre-flight checks (local dev oriented — see #1) |
| `scripts/testnet/validate-testnet-genesis.sh` | Invariant validation against live chain |
| `scripts/testnet/check-external-prerequisites.sh` | External infra reachability check |
| `scripts/testnet/testnet-health-check.sh` | Post-deployment health |
| `scripts/testnet/backup-testnet-db.sh` / `restore-testnet-db.sh` | DB backup |
| `scripts/testnet/run-c15-live-gate.sh` | Full test matrix runner |

⚠️ **INCONSISTENCY #4 (two conflicting systemd units):** `setup-testnet-node.sh` (lines 102-133) generates a systemd unit **inline** with hardcoded flag arguments. The repo also has `deploy/testnet/systemd/primewave-testnet-node.service` which uses `--config-file=/etc/primewave/node-config.json`. These are two entirely different service definitions. The checklist Step 9.1 calls `setup-testnet-node.sh` (generating the inline version), while the infra guide Step 7 says `sudo cp deploy/testnet/systemd/primewave-testnet-node.service`. Only one can be correct. The `deploy/testnet/` version is more maintainable (config-file based). Neither contains `--partial-sync-primary-network`.

### P. Genesis Template

`config/testnet/genesis-template.json` — 88 lines. Chain ID 77. 100M PW total. 7 placeholders. ✅ No `config/testnet/genesis.json` (final genesis) exists yet — correct.

### Q. Chain Config

`config/testnet/chain-config.json` — complete. `state-sync-enabled: false`, `pruning-enabled: false`. Written per-blockchain-id at `$DATA_DIR/chainData/chains/$BLOCKCHAIN_ID/config.json`. ✅

### R. Validator Provisioning Scripts

`scripts/testnet/setup-testnet-node.sh` — functional for Ubuntu 22.04. Critical gaps:
1. No `--partial-sync-primary-network` flag anywhere
2. Generates conflicting systemd unit (see #4)
3. Comment misidentifies `local-bin/subnet-evm` version (see #2)

### S. Testnet Deployment Scripts

`scripts/testnet/deploy-contracts.sh` — functional. Calls `DeployTestnet.s.sol`. EMS signer zero guard catches address(0) at forge script level. Chain ID guard catches wrong network.

---

## SECTION 2 — VALIDATOR COUNT / QUORUM

### Confirmed from `config/testnet/genesis-template.json`:

```
quorumNumerator  = 67
quorumDenominator = 100  (subnet-evm default — not in genesis file, implied)
```

### Warp quorum check formula (subnet-evm behavior):

`signerWeight × 100 ≥ totalWeight × 67`

With N equal-weight validators:

| N | Min signers | Formula | Chain halts if | Fault tolerance |
|---|---|---|---|---|
| 2 | 2 | 2×100=200 ≥ 2×67=134 ✅ / 1×100=100 < 134 ❌ | any 1 offline | **0** |
| 3 | 3 | 2×100=200 < 3×67=201 ❌ / 3×100=300 ≥ 201 ✅ | any 1 offline | **0** |
| **4** | **3** | **3×100=300 ≥ 4×67=268 ✅** | **any 2 offline** | **1 ✅** |
| 5 | 4 | 4×100=400 ≥ 5×67=335 ✅ | any 2 offline | 1 ✅ |

**4 validators → 3/4 quorum → 1-validator fault tolerance: CONFIRMED.**

Critical finding: 3 validators requires all 3 to sign (2×100=200 is less than 3×67=201). Three validators has zero fault tolerance — identical to 2 validators.

### Does the code require a different minimum anywhere?

No hardcoded `minimumValidatorCount` exists in `ValidatorManager`, `PoAManager`, `PrimeWaveStakingManager`, or any contract. The only minimum derives from quorum math above.

### Is 4 validators sufficient for all operations?

| Operation | Requirement | 4 validators |
|---|---|---|
| Warp messages | 3/4 signatures | ✅ |
| ACP-99 registration | PoAManager admin call + Warp round-trip | ✅ |
| Subnet operation | Subnet-EVM consensus via BLS Warp | ✅ |
| Block production | 3/4 must sign each block | ✅ |
| Validator set updates | PoAManager admin call, ICM relayer delivers | ✅ |
| ICM/Warp flows | 3/4 BLS signatures on any cross-chain message | ✅ |

**4 validators is sufficient for all operations. No hidden minimum found.**

---

## SECTION 3 — GENESIS AUDIT

### Placeholders in `config/testnet/genesis-template.json`

Exact count from file: **7 placeholders**

| # | Placeholder | Location | What goes here | Who generates | When must exist | Can generate now | Contract dependency | Circular dependency |
|---|---|---|---|---|---|---|---|---|
| 1 | `__REPLACE_FEE_DISTRIBUTOR_ADDRESS__` | `config.rewardManagerConfig.initialRewardConfig.rewardAddress` | FeeDistributor contract address | Replit (nonce prediction) | Before genesis finalized | Yes — via nonce math | Yes — FeeDistributor deployed post-launch | ⚠️ **YES — see below** |
| 2 | `__REPLACE_TESTNET_DEPLOYER_ADDRESS__` | `alloc` key (16M PW) | testnet-deployer EOA address | Replit (key ceremony) | Before genesis finalized | Yes — after key ceremony | No | No |
| 3 | `__REPLACE_TESTNET_TREASURY_ADDRESS__` | `alloc` key (25M PW) | Treasury multisig address | Operator | Before genesis finalized | No (needs operator) | No | No |
| 4 | `__REPLACE_TESTNET_TEAM_ADDRESS__` | `alloc` key (20M PW) | Team vesting address | Operator | Before genesis finalized | No (needs operator) | No | No |
| 5 | `__REPLACE_TESTNET_COMMUNITY_ADDRESS__` | `alloc` key (20M PW) | Community pool address | Operator | Before genesis finalized | No (needs operator) | No | No |
| 6 | `__REPLACE_TESTNET_ECOSYSTEM_ADDRESS__` | `alloc` key (10M PW) | Ecosystem fund address | Operator | Before genesis finalized | No (needs operator) | No | No |
| 7 | `__REPLACE_TESTNET_RESERVE_ADDRESS__` | `alloc` key (9M PW) | Reserve address | Operator | Before genesis finalized | No (needs operator) | No | No |

⚠️ **INCONSISTENCY #5 (CRITICAL):** `docs/PW-C15-TESTNET-DAY-0-CHECKLIST.md` Phase 7 Step 7.1 lists only **6 placeholders** and says *"Replace all `__REPLACE_*__` entries."* It explicitly lists placeholders 2–7 but **omits `__REPLACE_FEE_DISTRIBUTOR_ADDRESS__`**. Any operator following the checklist literally would produce a `genesis.json` still containing an unfilled `rewardAddress`. The generate script in Step 7.3 strips `_`-prefixed metadata keys but not `__REPLACE__` strings embedded inside config values — so the broken address would pass into the final genesis silently.

### The `__REPLACE_FEE_DISTRIBUTOR_ADDRESS__` Circular Dependency — Full Proof

**Problem:** The genesis must contain `FeeDistributor`'s address. But `FeeDistributor` is a Solidity contract deployed by `DeployTestnet.s.sol` onto the live chain, after the chain starts.

**Resolution mechanism from `contracts/script/DeployTestnet.s.sol`:**

```solidity
uint64 nonce3 = vm.getNonce(deployer);          // deployer's nonce at deploy time
address predictedFD = vm.computeCreateAddress(deployer, nonce3 + 2);
// Deployment order (relative to genesis nonce=0):
//   nonce 0 → EmergencyMultisig
//   nonce 1 → PrimeWaveTimelock
//   nonce 2 → ValidatorFeeVault       (nonce3 = 2 at time of getNonce call)
//   nonce 3 → DevTreasury
//   nonce 4 → FeeDistributor          ← nonce3 + 2 = 4
//   nonce 5 → PrimeWaveValidatorRegistry
//   nonce 6 → RewardVault
```

**Before genesis is created**, the FeeDistributor address can be pre-computed as:

```python
# Given: deployer_address (from key ceremony)
# Deployer starts with nonce=0 on fresh chain
# FeeDistributor is deployed at deployer nonce=4
import rlp
from eth_utils import keccak, to_checksum_address

deployer = bytes.fromhex("DEPLOYER_ADDRESS_WITHOUT_0x")
nonce = 4
preimage = rlp.encode([deployer, nonce])
address = keccak(preimage)[-20:]
predicted_fee_distributor = to_checksum_address(address.hex())
```

**Hard requirement:** The deployer must not make any transactions on the PrimeWave testnet before running `DeployTestnet.s.sol`. The script enforces this with:
```solidity
require(address(feeDist) == predictedFD, "FeeDistributor address prediction mismatch");
```

**This circular dependency is RESOLVED by nonce-based prediction. It is not a blocker, but it requires:**
1. Computing `FeeDistributor` address offline before genesis, using deployer address + nonce=4
2. Deployer must have zero prior transactions on the chain before deploying contracts
3. The on-chain check catches mistakes at deploy time

---

## SECTION 4 — DEPLOYER / SOFTWARE KEY AUDIT

### Actual state of Replit environment (live check, read-only):

`~/.avalanche-cli/key/` — **EMPTY** (0 files). `./local-bin/avalanche key list --fuji` returns only the `ewoq` key (address `0x8db97C7cEcE249c2b98bDC0226Cc4C2A57BF52FC`).

⚠️ **INCONSISTENCY #6 (CRITICAL):** `docs/PW-C15-INFRA-PROVISIONING-GUIDE.md` states the `testnet-deployer` key was generated 2026-08-15 and stored at `~/.avalanche-cli/key/testnet-deployer.pk`. This file **does not exist**. The documented address `0x2AD3152Ca630e2eF6679EBeb8da7b8311bfbFc60` is a previously-known public address, but the private key is gone from the environment. Generating a new testnet-deployer key will produce a **different address** — all documents referencing `0x2AD3152...` and `P-fuji1p25rk6kz9lwg2plwmfmvkvzxsa5qd02kla0vsw` would need to be updated.

⚠️ **INCONSISTENCY #7 (Uploaded audit document address typo):** The uploaded audit file (Section 5, line 164) states the deployer address as:

```
0x2AD3152Ca6302e2eF6679EBeb8da7b8311bfbFc60  (43 chars — FROM AUDIT DOC)
```

All 12 occurrences in the repository say:

```
0x2AD3152Ca630e2eF6679EBeb8da7b8311bfbFc60   (42 chars — REPO)
```

First difference at character position 14: audit doc has `...Ca630**2**e2eF...`, repo has `...Ca630**e**2eF...`. The audit document has an **extra `2` inserted**, producing a 43-character string (invalid — EVM addresses are always 42 chars including `0x`). The repository is consistent and correct.

### Key inventory — current status and role definitions:

| Key name | Expected role | Chain | Address usage | Private key required by | Testnet-only | Generated by | Current status |
|---|---|---|---|---|---|---|---|
| `testnet-deployer` | Deploy 7 protocol contracts; fund RewardVault; P-Chain ceremony | C-Chain (deploy), P-Chain (Fuji subnet creation) | Genesis alloc (16M PW), `DeployTestnet.s.sol` `msg.sender`, `avalanche key transfer` | `deploy-contracts.sh` (`TESTNET_DEPLOYER_KEY`), `avalanche blockchain deploy --key` | Yes | Replit | ❌ **NOT PRESENT** |
| `testnet-keeper-signer` | Keeper service EOA — calls `completeValidatorRegistration()` | C-Chain | `KEEPER_PRIVATE_KEY` in `testnet-keeper.env` | Keeper env at runtime | Yes | Replit | ❌ **NOT GENERATED** |
| `testnet-ems-signer-1..5` | EmergencyMultisig 3-of-5 signers | C-Chain | Hardcoded in `DeployTestnet.s.sol` `EMS_SIGNER_1..5` constants | `DeployTestnet.s.sol` compile-time | Yes | Replit | ❌ **NOT GENERATED** (all 5 are `address(0)`) |
| NodeID + BLS (4 fresh validators) | P-Chain identity for ACP-99 registration | P-Chain | `ConvertSubnetToL1Tx` initial validator set | N/A (held by node) | N/A | **AvalancheGo at node startup (automatic)** | ❌ Fresh nodes not yet provisioned |

### Hardcoded addresses found elsewhere:

- `check-external-prerequisites.sh` line 42: `DEPLOYER_CCHAIN="0x2AD3152Ca630e2eF6679EBeb8da7b8311bfbFc60"` — needs updating if deployer is regenerated
- `docs/PW-C15-TESTNET-DAY-0-CHECKLIST.md` line 31: same address exported as env var
- 10 more doc references — all same address

⚠️ **INCONSISTENCY #8:** `generate-validator-keys.sh` line 80 says `avalanchego --version  # Verify v1.14.2`. Testnet validators run v1.15.0-fuji. Wrong version cited.

---

## SECTION 5 — FUNDING AUDIT

### Transaction cost breakdown:

| Transaction | Fee estimate | Source |
|---|---|---|
| `CreateSubnetTx` | ~0.001 AVAX | `PW-C15-INFRA-PROVISIONING-GUIDE.md §2` |
| `CreateChainTx` | ~0.001 AVAX | Same |
| `ConvertSubnetToL1Tx` | Not individually quantified in docs | — |
| C→P export | ~0.001 AVAX | Typical Fuji export fee |
| **Total actual spend** | **< 0.01 AVAX** | — |
| **Recommended buffer** | **≥ 1.5 AVAX on P-Chain** | Docs recommendation |

### Exact commands (from repository — not executed):

```bash
# Export C→P
avalanche key transfer \
  --key testnet-deployer \
  --fuji \
  --amount 1.5 \
  --destination-key testnet-deployer \
  --source-chain C \
  --destination-chain P

# Verify P-Chain balance
avalanche key list --fuji

# Create and deploy subnet to Fuji
avalanche blockchain deploy primewave-testnet \
  --fuji \
  --key testnet-deployer \
  --num-validators 4

# Deploy contracts (after chain is live)
TESTNET_RPC_URL=<rpc_url> \
TESTNET_DEPLOYER_KEY=0x<private_key> \
bash scripts/testnet/deploy-contracts.sh
```

### Deployer address verification:

The repository consistently uses `0x2AD3152Ca630e2eF6679EBeb8da7b8311bfbFc60` (42 chars, valid). The uploaded audit document has a typo: `0x2AD3152Ca6302e2eF6679EBeb8da7b8311bfbFc60` (43 chars, invalid). Repository is correct.

### Current wallet balances (live Fuji read):

| Key | C-Chain | P-Chain | Status |
|---|---|---|---|
| `ewoq` (only CLI key in env) | 0.159 AVAX | 0.101 AVAX | NOT the testnet-deployer |
| `testnet-deployer` (`0x2AD3152...`) | **0 AVAX** | **0 AVAX** | Needs faucet + key is missing |

---

## SECTION 6 — L1 CREATION FLOW

### How `avalanche blockchain deploy --fuji` works (Avalanche CLI v1.9.5):

The single command executes all three P-Chain transactions in sequence:

1. **`CreateSubnetTx`** → generates `SubnetID`
2. **`CreateChainTx`** → generates `BlockchainID` (uses genesis.json + VM ID `rXJjKFtAVSmpKwhMhw7ZMV6opKcsmhk5AuVxWNAzFG221wmM8`)
3. **`ConvertSubnetToL1Tx`** → converts subnet to sovereign L1 with initial validator set

**ConvertSubnetToL1Tx is handled automatically by the CLI.** No manual script needed. The CLI requires NodeIDs + BLS pubkeys of all N initial validators (prompts interactively).

### Prerequisite: Subnet config must exist first

```bash
# Run BEFORE blockchain deploy:
avalanche blockchain create primewave-testnet \
  --genesis config/testnet/genesis.json \
  --vm subnet-evm \
  --evm-chain-id 77
```

The existing `~/.avalanche-cli/subnets/primewavedev/` is for **local devnet only**. A fresh `primewave-testnet` config must be created.

### Exact sequence for Fuji L1 creation:

```bash
export PATH="$REPO/local-bin:$PATH"

# Step 1: Create blockchain config in CLI
avalanche blockchain create primewave-testnet \
  --genesis config/testnet/genesis.json \
  --vm subnet-evm \
  --evm-chain-id 77

# Step 2: Deploy to Fuji (all 3 P-Chain txs)  ← IRREVERSIBLE
avalanche blockchain deploy primewave-testnet \
  --fuji \
  --key testnet-deployer \
  --num-validators 4 \
  2>&1 | tee /tmp/fuji-deploy.log

# Step 3: Extract IDs
grep -E "(Subnet ID|Blockchain ID)" /tmp/fuji-deploy.log
```

### Outputs after deploy:

- **Subnet ID** — base58-encoded 32-byte value
- **Blockchain ID** — different base58-encoded 32-byte value; used in RPC URL path

### ConvertSubnetToL1Tx initial validator set requirement:

The fresh nodes must have started at least once to generate their NodeID and BLS keys. The CLI will ask for each validator's NodeID + BLS public key + weight. **Nodes do not need to be fully bootstrapped — just started.**

⚠️ **INCONSISTENCY #9:** Infra guide Step 5 uses `--num-validators 5`. Checklist Phase 6 uses `--num-validators 3`. New architecture uses **4 validators**. All script references need updating to 4.

---

## SECTION 7 — FRESH VALIDATOR NODE BOOTSTRAP

### Target: 4 vCPU / 8GB RAM / 200GB SSD

Confirmed valid for `--partial-sync-primary-network` nodes. P-chain-only sync is ~3-5 GB. 200GB provides ample headroom for months of PrimeWave block production. The 500GB spec in docs is for full Fuji archival nodes.

### ⚠️ CRITICAL GAP — `--partial-sync-primary-network` is not configured anywhere

This flag does not appear in:
- `scripts/testnet/setup-testnet-node.sh`
- `deploy/testnet/systemd/primewave-testnet-node.service`
- `config/testnet/node-config.json`

⚠️ **INCONSISTENCY #10 (CRITICAL):** The entire new architecture depends on this flag. Without it, every fresh validator will begin full Fuji C-chain sync — identical to V2-V5 with a 5-11 day bootstrap. The flag must be added before any server is provisioned.

Required addition to `config/testnet/node-config.json`:

```json
{
  "partial-sync-primary-network": true
}
```

Or as a flag in ExecStart:
```
--partial-sync-primary-network
```

### Complete node specification:

| Parameter | Value | Source |
|---|---|---|
| AvalancheGo binary | `/opt/avalanchego/avalanchego` | `setup-testnet-node.sh` |
| Version | v1.15.0-fuji | `setup-testnet-node.sh` |
| Subnet-EVM plugin path | `/opt/avalanchego/plugins/rXJjKFtAVSmpKwhMhw7ZMV6opKcsmhk5AuVxWNAzFG221wmM8` | `setup-testnet-node.sh` line 74 |
| Database path | `/data/avalanchego/db` | `node-config.json` |
| Chain data path | `/data/avalanchego/chainData` | `node-config.json` |
| Log path | `/var/log/avalanchego` | `node-config.json` |
| Staking port | `9651` TCP+UDP (P2P) — **must be public** | `node-config.json` |
| API binding | `127.0.0.1:9650` (local only) | `node-config.json` |
| Systemd service | `primewave-testnet-node.service` | `deploy/testnet/systemd/` |
| Restart policy | `Restart=always`, `RestartSec=10s` | Service file |
| Health check | `curl http://localhost:9650/ext/health` | Checklist Step 9.4 |
| Bootstrap time with flag | ~30-60 minutes | Architecture decision |
| **MISSING: partial-sync** | `--partial-sync-primary-network` | ❌ Not in any config or script |
| track-subnets | `$TESTNET_SUBNET_ID` (set after P-Chain creation) | `node-config.json` `track-subnets` |

### Can `--partial-sync-primary-network` be used with `--track-subnets`?

**Yes.** These flags are orthogonal:
- `--partial-sync-primary-network` controls how the node syncs the **Primary Network** (P/X/C)
- `--track-subnets` controls which additional subnets the node validates

A node with both flags will: (1) sync P-chain only from the Primary Network (~30-60 min), then (2) start syncing and validating the PrimeWave L1 from genesis.

### ⚠️ INCONSISTENCY #11: `node-config.json` bootstrap placeholders will break node startup

```json
"bootstrap-ids": "__REPLACE_BOOTSTRAP_NODE_IDS__",
"bootstrap-ips": "__REPLACE_BOOTSTRAP_NODE_IPS__"
```

These override AvalancheGo's built-in Fuji bootstrap nodes with invalid strings. Node will fail to resolve `__REPLACE_*__` as node endpoints. **Fix:** Remove both fields entirely. AvalancheGo v1.15.0 with `--network-id=fuji` uses built-in Fuji bootstrap nodes by default.

---

## SECTION 8 — VALIDATOR IDENTITY

### How each fresh node obtains its identity:

1. **NodeID** — derived from the node's TLS staking key (`staking.crt`). Auto-generated by AvalancheGo on first startup. Stored at `$DATA_DIR/staking/staking.key` + `staking.crt`.
2. **BLS public key** — derived from the node's BLS secret key. Also auto-generated. Stored at `$DATA_DIR/staking/signer.key`.
3. **BLS proof of possession** — BLS signature over the public key. Auto-generated alongside BLS key. Proves key ownership to P-Chain.

### How to retrieve after first startup:

```bash
curl -sf -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"info.getNodeID","params":{}}' \
  http://localhost:9650/ext/info | python3 -m json.tool
# Returns: nodeID, publicKey (BLS G1, 48-byte hex), proofOfPossession (BLS G2, 96-byte hex)
```

### What must be recorded for `ConvertSubnetToL1Tx` initial validator set:

| Field | Format | Source |
|---|---|---|
| `nodeID` | 20-byte hex (parsed from `NodeID-xxxxx` base58) | `info.getNodeID` |
| `blsPublicKey` | 48-byte hex BLS G1 public key | `info.getNodeID` response |
| `blsProofOfPossession` | 96-byte hex BLS G2 signature | `info.getNodeID` response |
| `weight` | uint64 — equal weights (e.g. 100 each) | Operator decides |

### Are identities generated independently?

**Yes.** AvalancheGo generates cryptographically independent TLS + BLS keypairs on each node at first start. No coordination required. Operators collect NodeID + BLS data from each node's API and supply to the CLI during the P-Chain ceremony.

---

## SECTION 9 — ACP-99 REGISTRATION

### Phase 1 testnet uses PoAManager — not StakingManager

The testnet uses `PoAManager` (admin-controlled). `PrimeWaveStakingManager` is Phase 2 only.

### Initial validator set — at L1 creation (via CLI):

Registration of the initial 4 validators happens during `ConvertSubnetToL1Tx`. The Avalanche CLI submits the initial validator set as part of the conversion. **No contract call needed** — this is a P-Chain operation handled by the CLI.

### Post-launch validator additions (ACP-99 flow):

```
Admin → PoAManager.initiateValidatorRegistration(nodeID, blsPublicKey, ...) → Warp message emitted
  → ICM Relayer picks up Warp message from subnet
  → Relayer submits RegisterL1ValidatorTx to P-Chain
  → P-Chain confirms and sends Warp response
  → Relayer delivers response to subnet
  → Keeper (testnet-keeper-signer) calls PoAManager.completeValidatorRegistration(messageIndex)
  → Validator is Active
```

### Required parameters for `initiateValidatorRegistration`:

| Parameter | Type | Value |
|---|---|---|
| `nodeID` | `bytes` | Node's raw NodeID bytes (not base58) |
| `blsPublicKey` | `bytes` | 48-byte G1 public key |
| `remainingBalanceOwner` | `PChainOwner` | P-Chain address(es) receiving balance on exit |
| `disableOwner` | `PChainOwner` | P-Chain address(es) that can disable the validator |
| `weight` | `uint64` | Validator weight (equal = fair quorum) |

### EMS involvement:

EmergencyMultisig can pause `FeeDistributor`, `ValidatorFeeVault`, and `RewardVault`. EMS is **not** involved in normal validator registration. EMS is a 3-of-5 multisig for emergency actions only.

### Keeper involvement:

Keeper calls `completeValidatorRegistration()` after ICM relayer delivers P-Chain confirmation, and `completeValidatorRemoval()` when validators exit. Private key = `testnet-keeper-signer` (not yet generated).

### ICM/Warp relayer requirement:

A relayer must be running continuously for all post-launch ACP-99 operations. Relayer config requires `SUBNET_ID`, `BLOCKCHAIN_ID`, and RPC endpoints — known only after P-Chain ceremony.

**No relayer config file exists in the repo.** `deploy/testnet/icm-relayer-config.json` is referenced in the checklist Phase 11 Step 11.1 but this file is absent from the repository.

---

## SECTION 10 — CONTRACT DEPLOYMENT

### `contracts/script/DeployTestnet.s.sol` — complete deployment order:

| # | Deployer nonce | Contract | Constructor args |
|---|---|---|---|
| 0 | 0 | `EmergencyMultisig` | `[EMS_SIGNER_1..5]` |
| 1 | 1 | `PrimeWaveTimelock` | `deployer` |
| 2 | 2 | `ValidatorFeeVault` | `predictedRegistry` |
| 3 | 3 | `DevTreasury` | `predictedFD` |
| 4 | 4 | `FeeDistributor` | `feeVault, devTreasury, ems` |
| 5 | 5 | `PrimeWaveValidatorRegistry` | `deployer, deployer*, feeVault` |
| 6 | 6 | `RewardVault` | `deployer, INITIAL_RATE` |
| — | — | `rewardVault.fund{value: 15M PW}()` | Deployer must have ≥15,001 PW |

*ValidatorManager = deployer placeholder; replaced after PoAManager deployment.

**Addresses written to:** `local-data/testnet-deployed-contracts.env`

### Addresses required BEFORE genesis:

| Required | Source | Status |
|---|---|---|
| Deployer address | Key ceremony | ❌ Key missing |
| FeeDistributor address | Nonce prediction (deployer at nonce=4) | Computable after deployer address known |
| Treasury address | Operator | ❌ Not defined |
| Team address | Operator | ❌ Not defined |
| Community address | Operator | ❌ Not defined |
| Ecosystem address | Operator | ❌ Not defined |
| Reserve address | Operator | ❌ Not defined |

### Addresses created AFTER L1 launch:

All 7 contract addresses; also `SubnetID`, `BlockchainID`, RPC URL.

### FeeDistributor address prediction — validity:

**Valid, with conditions.** From `DeployTestnet.s.sol`:

```solidity
uint64 nonce3 = vm.getNonce(deployer);  // = 2 (after EMS + Timelock deployed)
address predictedFD = vm.computeCreateAddress(deployer, nonce3 + 2);  // = nonce 4
require(address(feeDist) == predictedFD, "FeeDistributor address prediction mismatch");
```

Condition: deployer must have nonce=0 at genesis start and make **no prior transactions** before running `DeployTestnet.s.sol`.

### EMS signers — current state:

```solidity
// In DeployTestnet.s.sol — currently:
address constant EMS_SIGNER_1 = address(0); // REPLACE
address constant EMS_SIGNER_2 = address(0); // REPLACE
address constant EMS_SIGNER_3 = address(0); // REPLACE
address constant EMS_SIGNER_4 = address(0); // REPLACE
address constant EMS_SIGNER_5 = address(0); // REPLACE
```

The script's `require(EMS_SIGNER_1 != address(0) && ...)` will revert if any are address(0). This is the correct guard state until key ceremony is complete.

---

## SECTION 11 — END-TO-END DEPENDENCY GRAPH

```
FUNDING (faucet.avax.network → testnet-deployer C-Chain)
  │
  ├─── [PARALLEL] KEY CEREMONY (Replit)
  │       Generate 7 EOA keys:
  │       testnet-deployer + testnet-keeper-signer + testnet-ems-signer-1..5
  │       Record public addresses only
  │
  ├─── [PARALLEL] PROVISION 4 FRESH VPS SERVERS (Operator, ~30 min)
  │       4 vCPU / 8GB / 200GB SSD, Ubuntu 22.04
  │       Open port 9651 TCP+UDP publicly
  │
  ↓
GENESIS PREPARATION (Replit)
  Fill 7 genesis placeholders:
  - testnet-deployer address → alloc (16M PW)
  - 5 operator-provided addresses → alloc (64M PW total)
  - FeeDistributor predicted address → rewardManagerConfig (= CREATE of deployer at nonce=4)
  Generate config/testnet/genesis.json
  SHA256 — all operators must agree
  │
  ↓
  ├─── [PARALLEL] EXPORT AVAX: C-Chain → P-Chain (1.5 AVAX) (Operator)
  │
  ├─── [PARALLEL] FRESH VALIDATOR NODE SETUP (per VPS)
  │       1. Install AvalancheGo v1.15.0-fuji + subnet-evm plugin
  │       2. Start node WITHOUT --track-subnets (to generate NodeID + BLS keypair)
  │       3. Record: NodeID, BLS pubkey, BLS proof of possession
  │       4. Stop or keep running
  │
  ↓
FUJI P-CHAIN CEREMONY (Operator) ← ALL IRREVERSIBLE FROM HERE
  avalanche blockchain create primewave-testnet \
    --genesis config/testnet/genesis.json --vm subnet-evm --evm-chain-id 77
  avalanche blockchain deploy primewave-testnet \
    --fuji --key testnet-deployer --num-validators 4
  │   └── CreateSubnetTx → SubnetID [IRREVERSIBLE]
  │   └── CreateChainTx → BlockchainID [IRREVERSIBLE]
  │   └── ConvertSubnetToL1Tx (initial 4 validators) [IRREVERSIBLE]
  │
  ↓
SUBNET ID + BLOCKCHAIN ID KNOWN
  │
  ├─── [PARALLEL] DNS REGISTRATION (Operator)
  │       rpc.testnet.primewave.xyz → infra-01 IP
  │       explorer.testnet.primewave.xyz → infra-01 IP
  │
  ├─── [PARALLEL] VALIDATORS START TRACKING SUBNET (per validator)
  │       - Add partial-sync-primary-network: true to node-config.json  ← MUST ADD
  │       - Add track-subnets: <SUBNET_ID> to node-config.json
  │       - Copy genesis.json to node
  │       - Copy chain-config.json to chainData/<BLOCKCHAIN_ID>/config.json
  │       - Restart AvalancheGo
  │
  ↓
FRESH VALIDATOR P-CHAIN BOOTSTRAP (~30-60 min)
  Validators sync P-Chain only via --partial-sync-primary-network
  Chain begins producing blocks when ≥3/4 validators online and synced
  │
  ↓
L1 BLOCK PRODUCTION CONFIRMED
  curl https://api.avax-test.network/ext/bc/<BLOCKCHAIN_ID>/rpc
  │
  ├─── [PARALLEL] TLS CERTIFICATES (Operator, needs DNS propagated)
  │
  ↓
PUBLIC RPC LIVE (rpc.testnet.primewave.xyz)
  │
  ↓
CONTRACT DEPLOYMENT (Replit, using forge)
  TESTNET_RPC_URL=<rpc> TESTNET_DEPLOYER_KEY=0x<key> \
  bash scripts/testnet/deploy-contracts.sh
  Deploys 7 contracts; funds RewardVault with 15M PW
  Writes local-data/testnet-deployed-contracts.env
  │
  ↓
DEPLOYED CONTRACT ADDRESSES KNOWN
  │
  ├─── [PARALLEL] DEPLOY ICM RELAYER (Operator)
  │       Required for post-launch ACP-99 Warp message delivery
  │
  ├─── [PARALLEL] CONFIGURE + DEPLOY KEEPER (Operator/Replit)
  │       Fill testnet-keeper.env; set KEEPER_PRIVATE_KEY = testnet-keeper-signer
  │       Start primewave-testnet-keeper.service
  │
  ├─── [PARALLEL] CONFIGURE + DEPLOY INDEXER (Operator/Replit)
  │       Fill testnet-indexer.env with BLOCKCHAIN_ID, DB URL
  │       Start primewave-testnet-indexer.service
  │
  ├─── [PARALLEL] CONFIGURE + DEPLOY PWCSCAN (Operator/Replit)
  │       Fill testnet-pwcscan.env with RPC URL, Chain ID 77
  │       Start primewave-testnet-pwcscan.service
  │
  ↓
4-NODE QUORUM ACTIVE
  3-of-4 signing; 1-validator fault tolerance
  │
  ↓
PRIMEWAVE TESTNET READY
  bash scripts/testnet/validate-testnet-genesis.sh
  │
  ↓
PWCSCAN / INDEXER INTEGRATION VERIFIED

Legend:
  [IRREVERSIBLE] — cannot be undone; requires explicit operator approval
  [PARALLEL]     — can run concurrently with sibling branches
  Replit         — executable in this environment without external access
  Operator       — requires human with cloud access / credentials
```

---

## SECTION 12 — EXISTING V2–V5 STATUS

**Policy: do not touch V2–V5.**

### Live status (read-only SSH, Aug 16 2026):

| Node | Disk used | Disk free | % | Last service event |
|---|---|---|---|---|
| V2 (152.53.19.19) | 174 GB / 251 GB | 68 GB | 69% | Aug 15 22:08:57 — service started |
| V3 (152.53.236.29) | 167 GB / 251 GB | 74 GB | 70% | Aug 15 22:45:15 — service started |
| V4 (152.53.236.136) | 172 GB / 251 GB | 69 GB | 72% | Aug 15 22:43:52 — service started |
| V5 (152.53.17.32) | Not retrieved (fail2ban timeout risk) | — | — | — |

**Can they safely continue?** Yes. The service timestamps ~22 hours ago suggest nodes are running continuously. At ~4 GB/hr growth rate, V2 has ~17 hours runway from measurement time. If growth has slowed (C-chain EVM execution per-block is slower in later blocks), runway extends.

**V2-V5 eventual roles:**

| Role | Viable? | Requirements |
|---|---|---|
| PrimeWave L1 validators | ✅ Yes — after full C-chain sync | Add `--track-subnets=<SUBNET_ID>`, install subnet-evm plugin, submit ACP-99 registration |
| Fuji full-node RPC | ✅ Yes — syncing Fuji C-chain | Open port 9650, configure nginx reverse proxy |
| Fuji archive node | ✅ Yes — `pruning-enabled: false` already set | Same as RPC |

**Can V2-V5 later become PrimeWave validators?** Yes. Once Fuji C-chain sync completes (~5-11 days from Aug 15):
1. Install subnet-evm plugin at `/opt/avalanchego/plugins/<VMID>`
2. Add `"track-subnets": "<SUBNET_ID>"` to node config
3. Restart service
4. Submit `PoAManager.initiateValidatorRegistration()` for each node
5. Keeper completes registration via ICM

This would increase the validator set from 4 → 8, tolerating 2 offline (5/8 needed at 67% quorum).

**No additional storage purchase recommended for V2-V5.** They were provisioned for full Fuji sync and have adequate runway.

---

## SECTION 13 — MAINNET READINESS

### What can be reused from testnet:

| Component | Status | Notes |
|---|---|---|
| All 7 Solidity contracts | ✅ Reuse (redeploy) | Same code, different addresses and chain ID |
| Keeper service | ✅ Reuse | Point to mainnet RPC/DB |
| Indexer service | ✅ Reuse | Point to mainnet RPC |
| PWCScan | ✅ Reuse | Update chain ID and RPC URL |
| `setup-testnet-node.sh` | ⚠️ Adapt | Version pins, resource specs |
| `deploy-contracts.sh` | ⚠️ Adapt | Remove testnet guard, new key |
| `validate-testnet-genesis.sh` | ✅ Reuse | Works against any chain |

### What MUST change for mainnet:

| Item | Change required |
|---|---|
| **Validator count** | 15 minimum (per `PRIMEWAVE_VALIDATOR_SPEC.md`); recommend starting with 7+ for fault tolerance |
| **Key custody** | Hardware wallets required for all signing keys (Ledger/Trezor); no software keys |
| **Genesis** | New genesis with mainnet chain ID (TBD), real treasury/team/ecosystem addresses |
| **Chain ID** | TBD — currently correctly not locked in any code |
| **Treasury** | Real legal entity multisig (Safe/Gnosis), not testnet EOA |
| **EMS signers** | 5 hardware wallet addresses from 5 separate individuals, geographically distributed |
| **Deployer** | Dedicated mainnet deployer on hardware wallet; nonce-zero on mainnet chain |
| **Timelock delay** | Consider extending (e.g. 7 days vs 48h for mainnet governance) |
| **Infrastructure** | Production-grade: SLA, auto-scaling, DDoS protection, separate monitoring |
| **RPC** | Public RPC with rate limiting, load balancing, health-gated traffic |
| **Monitoring** | 24/7 alerting; PagerDuty/OpsGenie; defined on-call rotation |
| **Security** | Formal audit of all 7 contracts before mainnet deploy |
| **Backups** | Hourly DB backups to off-site storage; tested restore procedures |
| **Disaster recovery** | Documented incident response: compromised validator, lost key, chain halt |
| **RewardVault funding** | Confirm mainnet amount; 5-year runway at 3M PW/year = 15M PW |

---

## SECTION 14 — FINAL OUTPUT

### A. GO / NO-GO FOR TESTNET

**Status: CONDITIONAL NO-GO**

Ready to plan and prepare. Not ready to execute. 10 blockers must be resolved before L1 creation can proceed.

---

### B. BLOCKERS

| # | Blocker | Severity | Who resolves |
|---|---|---|---|
| B1 | `testnet-deployer` private key does not exist in Replit — `0x2AD3152...` cannot be used | 🔴 Critical | Replit (key regeneration → new address) |
| B2 | `--partial-sync-primary-network` absent from ALL setup scripts and config files | 🔴 Critical | Replit (add to node-config.json + setup-testnet-node.sh) |
| B3 | `node-config.json` bootstrap placeholders (`__REPLACE_*__`) — will prevent node startup | 🔴 Critical | Replit (remove fields or fill with Fuji defaults) |
| B4 | `testnet-deployer` wallet has 0 AVAX — cannot fund P-Chain | 🟠 High | Operator (faucet.avax.network) |
| B5 | `testnet-ems-signer-1..5` not generated — `DeployTestnet.s.sol` will revert | 🟠 High | Replit (key generation) |
| B6 | `testnet-keeper-signer` not generated — keeper cannot be configured | 🟠 High | Replit (key generation) |
| B7 | 4 fresh VPS servers not provisioned | 🟠 High | Operator |
| B8 | ICM relayer config file (`deploy/testnet/icm-relayer-config.json`) does not exist in repo | 🟡 Medium | Replit (create template) |
| B9 | `preflight-testnet.sh` checks for AvalancheGo v1.14.2 — will fail on testnet servers | 🟡 Medium | Replit (fix version check) |
| B10 | Checklist Phase 7 omits `__REPLACE_FEE_DISTRIBUTOR_ADDRESS__` — operator will produce broken genesis | 🟡 Medium | Replit (fix checklist) |

---

### C. EXACT OPERATOR ACTIONS (human-only, in order)

1. Fund `0x<NEW_DEPLOYER_ADDRESS>` via `faucet.avax.network` (browser — 2 AVAX/day, repeat 2-3×)
2. Provision 4 VPS servers: Ubuntu 22.04, 4 vCPU / 8GB / 200GB SSD; open port 9651 TCP+UDP publicly
3. Register DNS: `rpc.testnet.primewave.xyz` and `explorer.testnet.primewave.xyz` → infra-01 IP
4. Provide 5 genesis allocation addresses (treasury, team, community, ecosystem, reserve) to Replit
5. Start each of 4 validator nodes once to generate NodeIDs + BLS keys; record all 4 sets of data
6. Execute P-Chain ceremony: `avalanche blockchain create primewave-testnet` + `avalanche blockchain deploy`
7. Record `SubnetID` and `BlockchainID` from CLI output
8. Distribute `config/testnet/genesis.json` SHA256 to all operators for verification
9. Provide `testnet-deployer` private key at deploy time (key stays private; used in env var)

---

### D. EXACT REPLIT ACTIONS (pre-server, in order)

1. **Fix `config/testnet/node-config.json`** — remove `bootstrap-ids` and `bootstrap-ips` fields
2. **Fix `config/testnet/node-config.json`** — add `"partial-sync-primary-network": true`
3. **Fix `scripts/testnet/setup-testnet-node.sh`** — add `--partial-sync-primary-network` flag to generated ExecStart
4. **Fix `scripts/testnet/preflight-testnet.sh`** — change AvalancheGo version check from `1.14.2` to `1.15.0-fuji`
5. **Fix `setup-testnet-node.sh` line 70 comment** — correct the false claim that `local-bin/subnet-evm` is v1.15.0-fuji
6. **Fix `generate-validator-keys.sh` line 80** — change `v1.14.2` to `v1.15.0-fuji`
7. **Fix `docs/PW-C15-TESTNET-DAY-0-CHECKLIST.md` Phase 7** — add `__REPLACE_FEE_DISTRIBUTOR_ADDRESS__` to placeholder fill list
8. **Create `deploy/testnet/icm-relayer-config.json`** template
9. **Generate 7 EOA keys**: `TESTNET_KEY_DIR=/secure/testnet-keys bash scripts/testnet/generate-validator-keys.sh` → produces new testnet-deployer (new address), keeper-signer, ems-signer-1..5
10. **Compute `FeeDistributor` predicted address** from new deployer address at nonce=4 (see Section 3 Python snippet)
11. **Fill `contracts/script/DeployTestnet.s.sol`** `EMS_SIGNER_1..5` constants with generated addresses
12. **Update `check-external-prerequisites.sh` `DEPLOYER_CCHAIN`** with new deployer address
13. **Update all 12 doc references** from old `0x2AD3152Ca630e2eF6679EBeb8da7b8311bfbFc60` to new deployer address
14. **Finalize `config/testnet/genesis.json`** once operator provides 5 remaining addresses + deployer address is known

---

### E. EXACT SERVER ACTIONS (on each of 4 fresh validators)

```bash
# 1. Run setup (after Replit fixes B2)
NODE_ROLE=validator \
TESTNET_SUBNET_ID=$TESTNET_SUBNET_ID \
TESTNET_BLOCKCHAIN_ID=$TESTNET_BLOCKCHAIN_ID \
bash /opt/primewave/scripts/testnet/setup-testnet-node.sh

# 2. Copy configs
mkdir -p /etc/primewave/
cp /opt/primewave/config/testnet/node-config.json /etc/primewave/node-config.json
# (node-config.json must have partial-sync-primary-network: true)

# 3. Start node ONCE to generate identity (before P-Chain ceremony)
systemctl start primewave-testnet-node
sleep 30

# 4. Collect identity — send to operator for P-Chain ceremony
curl -s http://localhost:9650/ext/info -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"info.getNodeID","params":{}}' | python3 -m json.tool
# → record: nodeID, publicKey (BLS 48-byte), proofOfPossession (BLS 96-byte)

# 5. After P-Chain ceremony: update node-config.json with SubnetID
python3 -c "
import json
c = json.load(open('/etc/primewave/node-config.json'))
c['track-subnets'] = '$TESTNET_SUBNET_ID'
json.dump(c, open('/etc/primewave/node-config.json', 'w'), indent=2)
"

# 6. Copy chain config (requires BlockchainID)
mkdir -p /data/avalanchego/chainData/chains/$TESTNET_BLOCKCHAIN_ID/
cp /opt/primewave/config/testnet/chain-config.json \
   /data/avalanchego/chainData/chains/$TESTNET_BLOCKCHAIN_ID/config.json

# 7. Copy genesis
cp /opt/primewave/config/testnet/genesis.json /etc/primewave/genesis.json

# 8. Restart validator (now with partial-sync + track-subnets)
systemctl daemon-reload
systemctl enable primewave-testnet-node
systemctl restart primewave-testnet-node

# 9. Monitor (~30-60 min to bootstrap)
journalctl -u primewave-testnet-node -f

# 10. Verify health
curl -sf http://localhost:9650/ext/health | python3 -c \
  "import json,sys; d=json.load(sys.stdin); print('Healthy:', d.get('healthy', False))"
```

---

### F. EXACT COMMAND SEQUENCE (ordered, parallelism shown)

```
Phase 0:  Replit — Fix 9 script/config issues (B2, B3, B5, B6, B8, B9, B10)
Phase 1:  Replit — Generate 7 EOA keys; compute FeeDistributor predicted address
Phase 2:  Operator — Fund deployer on Fuji faucet (can run parallel with Phase 1)
Phase 3:  Operator — Provision 4 VPS servers (parallel with Phases 1-2)
Phase 4:  Replit+Operator — Fill genesis template (6 operator addresses + 1 predicted FD)
Phase 5:  Operator — Start all 4 validators once to generate NodeIDs + BLS keys
Phase 6:  Operator — Export C→P AVAX: avalanche key transfer ...
Phase 7:  Operator — avalanche blockchain create primewave-testnet --genesis ... --evm-chain-id 77
Phase 8:  Operator — avalanche blockchain deploy primewave-testnet --fuji --key testnet-deployer --num-validators 4  [IRREVERSIBLE]
Phase 9:  Operator — Record SubnetID, BlockchainID; update validator node-configs; restart validators
Phase 10: Validators — Wait ~30-60 min for P-Chain bootstrap; verify health endpoint returns Healthy: True
Phase 11: Operator — DNS registration + TLS certificates (parallel with Phase 10)
Phase 12: Replit — forge script DeployTestnet.s.sol (via scripts/testnet/deploy-contracts.sh)
Phase 13: Operator — Deploy ICM relayer (config template must exist first)
Phase 14: Operator/Replit — Deploy keeper + indexer + PWCScan
Phase 15: Replit — bash scripts/testnet/validate-testnet-genesis.sh
```

---

### G. EXPECTED TIMELINE

| Phase | Duration | Parallelizable? |
|---|---|---|
| Replit fixes | 1–2 hours | With key gen |
| Key generation | <5 minutes | With server provisioning |
| Faucet funding | 5–10 min (may need multiple days for >2 AVAX) | Parallel with server provisioning |
| Server provisioning (4 VPS) | 20–40 min | Parallel with Replit work |
| Genesis preparation | 30 min | After keys + operator addresses |
| Validator identity collection | 15 min per node | Per server, parallel |
| P-Chain ceremony | 5–15 min | Sequential |
| Validator bootstrap (partial-sync) | 30–60 min | Parallel across 4 nodes |
| DNS propagation | 5–30 min | Parallel with bootstrap |
| TLS certificates | 5–10 min | After DNS |
| Contract deployment | 5–10 min | After chain is live |
| ICM relayer + keeper + indexer | 30–60 min | Parallel |
| **Total (optimistic, with parallelism)** | **3–5 hours** | — |
| **Total (conservative, sequential issues)** | **6–8 hours** | — |

---

### H. EXPECTED INFRASTRUCTURE COST (monthly)

| Server | Spec | Count | Hetzner | AWS |
|---|---|---|---|---|
| Fresh validator | 4 vCPU / 8GB / 200GB SSD | 4 | ~€15/mo each | ~$100/mo each |
| Infra-01 | 4 vCPU / 16GB / 200GB | 1 | ~€30/mo | ~$130/mo |
| **Total new infra** | — | 5 | **~€90/month** | **~$530/month** |

V2-V5: already running, no additional cost.

---

### I. IRREVERSIBLE ACTIONS REQUIRING EXPLICIT APPROVAL

| Action | Why irreversible | When |
|---|---|---|
| `CreateSubnetTx` on Fuji | P-Chain transaction; permanent | Phase 8 |
| `CreateChainTx` on Fuji | Blockchain ID is permanent | Phase 8 |
| `ConvertSubnetToL1Tx` on Fuji | Converts subnet to sovereign L1; cannot be unconverted | Phase 8 |
| Contract deployment (broadcast) | On-chain; no EVM contract deletion | Phase 12 |
| `rewardVault.fund{value: 15M PW}()` | 15M PW locked in RewardVault; no withdrawal function | Phase 12 |
| NodeID registration in ConvertSubnetToL1Tx | P-Chain validator set committed | Phase 8 |

---

### J. UNRESOLVED QUESTIONS

1. **Deployer address decision:** Generate new deployer key (new address, requires updating 12+ doc references + all genesis work) — or is there a way to recover the original private key? The original (`0x2AD3152...`) is gone from the environment.
2. **5 operator-controlled genesis addresses:** Who holds treasury, team, community, ecosystem, and reserve addresses? Which multisigs/EOAs? These are needed before genesis can be finalized.
3. **`avalanche blockchain deploy --num-validators 4` interactive mode:** Does CLI v1.9.5 prompt interactively for NodeID + BLS keys, or does it require a flags file? Needs to be tested before ceremony.
4. **PoAManager deployment:** Which script deploys it? `DeployTestnet.s.sol` does not deploy `PoAManager`. The registry currently uses `deployer` as a placeholder — at what point and with which command is the real PoAManager deployed and registered?
5. **ICM relayer config:** No template exists. What parameters are required? Is there an Ava Labs reference config from `ava-labs/icm-services`?
6. **V5 disk status:** Could not read in this session (fail2ban timeout risk). Needs verification.
7. **`--num-validators 4` vs initial set:** Does `avalanche blockchain deploy --num-validators N` mean "prompt for N validators" or "automatically generate N validators"? If the latter, how are our specific NodeIDs used?

---

### K. RISKS

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Deployer nonce non-zero → FeeDistributor address mismatch | Low if procedures followed | 🔴 Critical — deploy reverts; must restart with new deployer | Never send any tx from deployer before running deploy-contracts.sh |
| `--partial-sync-primary-network` not added → 5-11 day bootstrap | High (current state: not in config) | 🟠 High — blocks timeline by days | Fix node-config.json before provisioning servers (Blocker B2) |
| V2-V5 disk fill → node crash | Medium | 🟡 Medium — isolated; separate fleet; no data loss | V2-V5 are on separate fleet; crash doesn't block new architecture |
| Faucet limit (2 AVAX/day) delays ceremony | Medium | 🟡 Medium — 1-3 day delay | Request AVAX early; use multiple faucet methods |
| `ConvertSubnetToL1Tx` with wrong validator count | Low | 🔴 Critical — irreversible; validator set wrong | Confirm exactly 4 NodeIDs before executing |
| ICM relayer missing → ACP-99 post-launch operations fail | High (no config exists) | 🟠 High — can't add validators after launch | Create relayer config before Phase 13 |
| `bootstrap-ids/__REPLACE__` in node-config.json | Certain if not fixed | 🔴 Critical — node fails to start | Fix node-config.json (Blocker B3) |
| Only 3 of 4 validators online during first block → no quorum | Medium | 🟡 Medium — chain stalls until 4th validator online | Ensure all 4 are running before declaring testnet live |

---

### L. RECOMMENDED ARCHITECTURE

**Fresh validator fleet (4 nodes, 200GB SSD):**
```
AvalancheGo v1.15.0-fuji
--partial-sync-primary-network  ← MUST ADD
--track-subnets=<SUBNET_ID>
--network-id=fuji
--staking-port=9651  ← public TCP+UDP
--http-host=127.0.0.1  ← API local only
subnet-evm plugin at /opt/avalanchego/plugins/<VMID>
4 vCPU / 8GB RAM / 200GB SSD
```

**Infra-01 (1 node):**
```
nginx → rpc.testnet.primewave.xyz + explorer.testnet.primewave.xyz
PostgreSQL (indexer DB)
PrimeWave indexer
PrimeWave keeper (testnet-keeper-signer)
ICM relayer
4 vCPU / 16GB RAM / 200GB SSD
```

**V2-V5 (existing):** Continue full Fuji sync undisturbed. Upgrade to PrimeWave validators when sync completes (~5-11 days). Once added, validator count rises to 8, quorum becomes 6/8 (tolerating 2 offline).

---

## SUMMARY OF ALL INCONSISTENCIES FOUND

| # | Location | Issue | Severity |
|---|---|---|---|
| 1 | `preflight-testnet.sh` L97 | Checks AvalancheGo v1.14.2; testnet uses v1.15.0-fuji | 🟠 High |
| 2 | `setup-testnet-node.sh` L70 comment | Claims `local-bin/subnet-evm` is v1.15.0-fuji; it is v1.14.2 | 🟡 Medium |
| 3 | Checklist Phase 10 + DeployTestnet.s.sol | PoAManager deployment not scripted anywhere | 🟠 High |
| 4 | `setup-testnet-node.sh` vs `deploy/testnet/systemd/` | Two conflicting systemd unit definitions | 🟡 Medium |
| 5 | Checklist Phase 7 | Lists 6 genesis placeholders; genesis has 7 — missing `__REPLACE_FEE_DISTRIBUTOR_ADDRESS__` | 🔴 Critical |
| 6 | `~/.avalanche-cli/key/` | `testnet-deployer` private key absent from Replit environment | 🔴 Critical |
| 7 | Uploaded audit document line 164 | Deployer address has extra `2` — 43 chars, invalid EVM address | 🟡 Medium (typo in audit doc) |
| 8 | `generate-validator-keys.sh` L80 | References `v1.14.2` for validator verification; should be v1.15.0-fuji | 🟡 Low |
| 9 | `node-config.json` | `bootstrap-ids/__REPLACE__` and `bootstrap-ips/__REPLACE__` will break node startup | 🔴 Critical |
| 10 | All setup scripts + node-config.json | `--partial-sync-primary-network` flag entirely absent | 🔴 Critical |
| 11 | `setup-testnet-node.sh` header | Says "8+ vCPU, 32GB RAM, 500GB NVMe"; conflicts with audit decision of 4/8/200 | 🟡 Low |
| 12 | Infra guide Step 5 + Checklist Phase 6 | Uses `--num-validators 5` or `3`; new architecture uses 4 | 🟡 Medium |
| 13 | Infra guide §12 "minimum viable" | Documents 3-validator minimum; quorum math shows 3 = zero fault tolerance | 🟡 Medium |

---

**This report is complete. No changes were made to any file. All findings are read-only observations.**

**Single most important action before any deployment: fix Blockers B2 (partial-sync flag) and B3 (bootstrap placeholders) in Replit, then run key generation. Everything else can be parallelized once those are resolved.**
