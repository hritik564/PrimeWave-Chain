> HISTORICAL RUNBOOK — do not execute its old network, address, funding or four-server commands. Current preparation uses `scripts/mainnet/fuji_rehearsal.py`, explicit public manifests and owner approvals; C00 genesis predeployment replaces post-deployment RewardVault funding. No Fuji broadcast is authorized.

# PrimeWave — Fuji L1 Ceremony Runbook
## PW-C15 | Operator Execution Guide | Evidence-Based

**Date:** 2026-08-16  
**Status:** Pre-execution draft — to be executed by operator  
**Evidence basis:** `./local-bin/avalanche blockchain deploy --help` output (v1.9.5)

---

## CRITICAL CORRECTIONS FROM PRIOR DOCS

| Prior docs say | Correct form | Source |
|---|---|---|
| `--num-validators 4` | **`--num-bootstrap-validators 4`** | `--help` output |
| Prompt interactively for NodeIDs | **Use `--bootstrap-filepath` for non-interactive input** | `--help` output |
| `avalanche key transfer --num-validators` | No such flag — see exact commands below | `--help` output |

---

## 1. CLI FLAG REFERENCE (v1.9.5 `blockchain deploy`)

The following flags are relevant to the Fuji ceremony:

```
--key string                    CLI stored key to use (testnet-deployer)
--num-bootstrap-validators int  number of bootstrap validators for L1 conversion
--bootstrap-filepath string     JSON file with validator NodeID + BLS info (NON-INTERACTIVE)
--bootstrap-endpoints strings   query running node APIs to get validator info (ALTERNATIVE)
--balance float64               AVAX balance per bootstrap validator on P-Chain (continuous fee)
--change-owner-address string   P-Chain addr to receive remaining balance when validator exits
--weight uint64                 weight of each bootstrap validator
--vmc-L1                        deploy ValidatorManager contract into the L1 (via genesis)
--convert-only                  SKIP PoAManager setup (do NOT use — leaves PoAManager uninitialized)
--output-tx-path string         write tx to file for multi-sig (not needed for testnet)
--subnet-only                   stop after CreateSubnetTx (for staged deployment)
```

---

## 2. PRE-CEREMONY CHECKLIST

Complete ALL of these before running any CLI command.

### 2.1 CLI Blockchain Config Must Exist

```bash
# Check if primewave-testnet config exists
ls ~/.avalanche-cli/subnets/primewave-testnet/ 2>/dev/null || echo "MISSING — run Step 3.1"
```

If missing, run Step 3.1.

### 2.2 Keys

```bash
export PATH="$REPO/local-bin:$PATH"
avalanche key list --fuji
# Must show: testnet-deployer with P-Chain balance ≥ 1.5 AVAX
```

### 2.3 bootstrap-validators.json Must Exist

File: `config/testnet/bootstrap-validators.json`

```bash
ls config/testnet/bootstrap-validators.json || echo "MISSING — complete server provisioning first"
python3 -m json.tool config/testnet/bootstrap-validators.json
# Must show: array of 4 validator objects, no empty fields
```

### 2.4 genesis.json Must Exist (no placeholders)

```bash
grep "__REPLACE__" config/testnet/genesis.json && echo "BLOCKER: unfilled placeholders" || echo "OK: no placeholders"
```

### 2.5 AVAX Balance on P-Chain

```bash
avalanche key list --fuji | grep testnet-deployer
# Expect: P-Chain >= 1.5 AVAX
```

### 2.6 Verify PoA config stored in CLI

```bash
cat ~/.avalanche-cli/subnets/primewave-testnet/sidecar.json | python3 -c \
  "import json,sys; d=json.load(sys.stdin); print('PoA:', d.get('ValidatorManagement')); print('ACP99:', d.get('UseACP99'))"
# Expect: PoA: Proof Of Authority, ACP99: True
```

---

## 3. EXACT CEREMONY SEQUENCE

### STEP 3.1 — Create Blockchain Config (Replit, one-time)

```bash
cd $REPO
export PATH="$REPO/local-bin:$PATH"

DEPLOYER_ADDR=$(python3 -c "import json; d=json.load(open('$HOME/.primewave-keys/testnet-deployer.json')); print(d['address'])")

avalanche blockchain create primewave-testnet \
  --fuji \
  --genesis config/testnet/genesis.json \
  --vm subnet-evm \
  --evm-chain-id 77 \
  --proof-of-authority \
  --acp99 \
  --validator-manager-owner "$DEPLOYER_ADDR" \
  --proxy-contract-owner "$DEPLOYER_ADDR"
```

**Expected:** Creates `~/.avalanche-cli/subnets/primewave-testnet/` with sidecar.json + genesis.json  
**Verify:** `cat ~/.avalanche-cli/subnets/primewave-testnet/sidecar.json | python3 -m json.tool`

---

### STEP 3.2 — Collect Validator Node Identities (Operator, per node)

Run on each of the 4 fresh VPS validators:

```bash
# After AvalancheGo has started at least once:
NODE_INFO=$(curl -sf http://localhost:9650/ext/info \
  -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"info.getNodeID","params":{}}')

echo "$NODE_INFO" | python3 -c "
import json, sys
d = json.load(sys.stdin)['result']
print('NodeID:', d['nodeID'])
print('BLSPublicKey:', d['publicKey'])
print('BLSProofOfPossession:', d['proofOfPossession'])
"
```

Also get the node's external IP for the change owner address (P-Chain format):

```bash
# Get deployer P-Chain address
avalanche key list --fuji | grep testnet-deployer
# Note the P-fuji1... address for --change-owner-address
```

---

### STEP 3.3 — Create bootstrap-validators.json (Replit, after all 4 nodes provide info)

Create file: `config/testnet/bootstrap-validators.json`

```json
[
  {
    "NodeID": "NodeID-<VALIDATOR_1_NODE_ID>",
    "Weight": 100,
    "Balance": 0.375,
    "BLSPublicKey": "0x<VALIDATOR_1_BLS_PUBLIC_KEY_48_BYTES_HEX>",
    "BLSProofOfPossession": "0x<VALIDATOR_1_BLS_PROOF_96_BYTES_HEX>",
    "ChangeOwnerAddr": "P-fuji1<DEPLOYER_P_CHAIN_ADDR>"
  },
  {
    "NodeID": "NodeID-<VALIDATOR_2_NODE_ID>",
    "Weight": 100,
    "Balance": 0.375,
    "BLSPublicKey": "0x<VALIDATOR_2_BLS_PUBLIC_KEY_48_BYTES_HEX>",
    "BLSProofOfPossession": "0x<VALIDATOR_2_BLS_PROOF_96_BYTES_HEX>",
    "ChangeOwnerAddr": "P-fuji1<DEPLOYER_P_CHAIN_ADDR>"
  },
  {
    "NodeID": "NodeID-<VALIDATOR_3_NODE_ID>",
    "Weight": 100,
    "Balance": 0.375,
    "BLSPublicKey": "0x<VALIDATOR_3_BLS_PUBLIC_KEY_48_BYTES_HEX>",
    "BLSProofOfPossession": "0x<VALIDATOR_3_BLS_PROOF_96_BYTES_HEX>",
    "ChangeOwnerAddr": "P-fuji1<DEPLOYER_P_CHAIN_ADDR>"
  },
  {
    "NodeID": "NodeID-<VALIDATOR_4_NODE_ID>",
    "Weight": 100,
    "Balance": 0.375,
    "BLSPublicKey": "0x<VALIDATOR_4_BLS_PUBLIC_KEY_48_BYTES_HEX>",
    "BLSProofOfPossession": "0x<VALIDATOR_4_BLS_PROOF_96_BYTES_HEX>",
    "ChangeOwnerAddr": "P-fuji1<DEPLOYER_P_CHAIN_ADDR>"
  }
]
```

**Notes:**
- `Balance: 0.375` = 0.375 AVAX per validator × 4 = 1.5 AVAX total P-Chain continuous fee balance
- `Weight: 100` = equal weight on all 4 validators → 3/4 quorum (1 fault tolerance)
- `ChangeOwnerAddr` = P-fuji1... address of testnet-deployer (receives balance if validator exits)
- BLSPublicKey: 48 bytes (96 hex chars after 0x)
- BLSProofOfPossession: 96 bytes (192 hex chars after 0x)

---

### STEP 3.4 — Fund P-Chain (Operator, browser + CLI)

```bash
# 1. Get Fuji AVAX via faucet (browser, ~2 AVAX/day max)
# https://faucet.avax.network → enter C-Chain deployer address

# 2. Export from C-Chain to P-Chain
avalanche key transfer \
  --key testnet-deployer \
  --fuji \
  --amount 1.5 \
  --source-chain C \
  --destination-chain P

# 3. Verify
avalanche key list --fuji | grep -A2 testnet-deployer
# Must show: P-Chain >= 1.5 AVAX
```

---

### STEP 3.5 — Deploy to Fuji ← IRREVERSIBLE POINT OF NO RETURN

**Requirements before executing:**
- [ ] `config/testnet/genesis.json` exists, 0 unfilled placeholders
- [ ] `config/testnet/bootstrap-validators.json` exists, 4 validators, all fields filled
- [ ] `~/.avalanche-cli/subnets/primewave-testnet/sidecar.json` exists, ValidatorManagement = "Proof Of Authority"
- [ ] testnet-deployer P-Chain balance ≥ 1.5 AVAX
- [ ] All 4 validator nodes are running (or at least have generated their identity)

```bash
cd $REPO
export PATH="$REPO/local-bin:$PATH"

# This executes CreateSubnetTx + CreateChainTx + ConvertSubnetToL1Tx
# It also deploys PoAManager proxy at 0x0FEEDC0DE0000000000000000000000000000000
# and initializes it as part of the ceremony
avalanche blockchain deploy primewave-testnet \
  --fuji \
  --key testnet-deployer \
  --bootstrap-filepath config/testnet/bootstrap-validators.json \
  --num-bootstrap-validators 4 \
  2>&1 | tee /tmp/fuji-ceremony.log
```

**Expected output (approximate):**
```
Creating subnet...
Subnet created with ID: <TESTNET_SUBNET_ID>
Creating blockchain...
Blockchain ID: <TESTNET_BLOCKCHAIN_ID>
Converting subnet to L1...
ValidatorManager deployed at: 0x0FEEDC0DE0000000000000000000000000000000
ConvertSubnetToL1Tx confirmed: <tx-id>
L1 converted successfully.
```

**Extract IDs:**
```bash
TESTNET_SUBNET_ID=$(grep "Subnet.*ID" /tmp/fuji-ceremony.log | grep -oP '[A-Za-z0-9]{40,}' | head -1)
TESTNET_BLOCKCHAIN_ID=$(grep "Blockchain ID" /tmp/fuji-ceremony.log | grep -oP '[A-Za-z0-9]{40,}' | head -1)
echo "SubnetID:     $TESTNET_SUBNET_ID"
echo "BlockchainID: $TESTNET_BLOCKCHAIN_ID"
```

**Save IDs immediately:**
```bash
cat >> local-data/testnet-network-ids.env << EOF
TESTNET_SUBNET_ID=$TESTNET_SUBNET_ID
TESTNET_BLOCKCHAIN_ID=$TESTNET_BLOCKCHAIN_ID
TESTNET_VALIDATOR_MANAGER=0x0FEEDC0DE0000000000000000000000000000000
TESTNET_RPC_URL=https://api.avax-test.network/ext/bc/${TESTNET_BLOCKCHAIN_ID}/rpc
EOF
```

---

### STEP 3.6 — Distribute IDs to Validators (Operator)

After ceremony, update each validator's node-config.json with the SubnetID and restart:

```bash
# Run on each of 4 validators:
TESTNET_SUBNET_ID=<from-step-3.5>
TESTNET_BLOCKCHAIN_ID=<from-step-3.5>

# Update node config with subnet tracking
python3 -c "
import json
c = json.load(open('/etc/primewave/node-config.json'))
c['track-subnets'] = '$TESTNET_SUBNET_ID'
json.dump(c, open('/etc/primewave/node-config.json', 'w'), indent=2)
"

# Copy chain config
mkdir -p /data/avalanchego/chainData/chains/$TESTNET_BLOCKCHAIN_ID/
cp /opt/primewave/config/testnet/chain-config.json \
   /data/avalanchego/chainData/chains/$TESTNET_BLOCKCHAIN_ID/config.json

# Restart
systemctl daemon-reload
systemctl restart primewave-testnet-node
```

---

### STEP 3.7 — Wait for Chain Bootstrap

```bash
# Poll until healthy (expect ~30-60 min with --partial-sync-primary-network):
watch -n 30 'curl -sf http://localhost:9650/ext/health | python3 -c \
  "import json,sys; d=json.load(sys.stdin); print(\"Healthy:\", d.get(\"healthy\"))"'

# Verify block production via public Fuji API:
curl -sf https://api.avax-test.network/ext/bc/<TESTNET_BLOCKCHAIN_ID>/rpc \
  -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}' \
  | python3 -m json.tool
# Expect: result is a non-zero hex block number
```

---

### STEP 3.8 — Verify PoAManager Predeploy (Replit)

```bash
TESTNET_RPC_URL=https://api.avax-test.network/ext/bc/$TESTNET_BLOCKCHAIN_ID/rpc

# PoAManager must have bytecode at predeploy address
POA_CODE=$(cast code 0x0FEEDC0DE0000000000000000000000000000000 --rpc-url $TESTNET_RPC_URL)
if [[ "$POA_CODE" == "0x" || -z "$POA_CODE" ]]; then
  echo "BLOCKER: PoAManager not deployed at predeploy address"
else
  echo "OK: PoAManager deployed (${#POA_CODE} bytes)"
fi
```

---

### STEP 3.9 — Deploy Protocol Contracts (Replit)

```bash
TESTNET_DEPLOYER_KEY=$(cat ~/.primewave-keys/testnet-deployer.json | \
  python3 -c "import json,sys; print(json.load(sys.stdin)['privateKey'])")

TESTNET_RPC_URL=https://api.avax-test.network/ext/bc/$TESTNET_BLOCKCHAIN_ID/rpc \
TESTNET_DEPLOYER_KEY=$TESTNET_DEPLOYER_KEY \
bash scripts/testnet/deploy-contracts.sh

# Expected output: 7 contract addresses written to local-data/testnet-deployed-contracts.env
source local-data/testnet-deployed-contracts.env
echo "Registry ValidatorManager:"
cast call $ADDR_VALIDATOR_REGISTRY \
  "validatorManager()(address)" \
  --rpc-url $TESTNET_RPC_URL
# Must return: 0x0FEEDC0DE0000000000000000000000000000000
```

---

### STEP 3.10 — Register Initial Validators (Admin)

For each of the 4 initial validators (after `ConvertSubnetToL1Tx` made them Active in PoAManager):

```bash
# The CLI-set initial validators are already Active in PoAManager.
# Get their validationIDs from PoAManager events or from the ceremony log.

# Register each in PrimeWaveValidatorRegistry (binds to fee accounting):
cast send $ADDR_VALIDATOR_REGISTRY \
  "registerValidator(bytes32,address)" \
  <VALIDATION_ID_1> <VALIDATOR_1_REWARD_RECIPIENT> \
  --rpc-url $TESTNET_RPC_URL \
  --private-key $TESTNET_DEPLOYER_KEY
# Repeat for validators 2, 3, 4
```

---

## 4. ALTERNATIVE: `--bootstrap-endpoints` (if nodes are reachable from Replit)

Instead of creating `bootstrap-validators.json` manually, if the validator nodes are reachable from Replit:

```bash
avalanche blockchain deploy primewave-testnet \
  --fuji \
  --key testnet-deployer \
  --bootstrap-endpoints \
    "http://<VALIDATOR_1_IP>:9650,http://<VALIDATOR_2_IP>:9650,http://<VALIDATOR_3_IP>:9650,http://<VALIDATOR_4_IP>:9650" \
  --num-bootstrap-validators 4 \
  --balance 0.375 \
  --change-owner-address P-fuji1<DEPLOYER_P_CHAIN_ADDR>
```

The CLI will query each endpoint for NodeID and BLS info automatically.

**Caution:** This requires:
1. Port 9650 is accessible from the Replit environment (usually NOT publicly exposed — 9651 is the P2P port)
2. The nodes are up before the ceremony

**Recommendation: Use `--bootstrap-filepath` with a manually prepared JSON.** This avoids network connectivity requirements and allows pre-verification.

---

## 5. DRY-RUN / SIMULATION OPTIONS

**Can we simulate without broadcasting to Fuji?** Partially yes:

| Operation | Can simulate? | How |
|---|---|---|
| `blockchain create primewave-testnet` | ✅ Yes | Run it — creates only local config, no P-Chain tx |
| `blockchain deploy` P-Chain transactions | ❌ No dry-run | Not supported by CLI |
| Contract deployment (forge) | ✅ Yes | `forge script --rpc-url <local> --no-broadcast` |
| PoAManager predeploy behavior | ✅ Yes | Check local dev chain — same predeploy address |
| Validator bootstrap | ❌ No | Requires live Fuji P-Chain |

**Verify PoAManager predeploy behavior on local dev chain (harmless):**
```bash
# The local dev chain should have PoAManager at same address
cast code 0x0FEEDC0DE0000000000000000000000000000000 \
  --rpc-url http://localhost:9650/ext/bc/2F3BHmNJWP4DNaBbMFQog3TvfcF6GRY7PX99r7Xzae4cRwAv6a/rpc
# If local chain is running, should return bytecode
```

---

## 6. ROLLBACK OPTIONS

| Transaction | Reversible? | Notes |
|---|---|---|
| `blockchain create primewave-testnet` | ✅ Yes — delete `~/.avalanche-cli/subnets/primewave-testnet/` | Just deletes local config |
| `CreateSubnetTx` | ❌ Irreversible | SubnetID is permanent on Fuji |
| `CreateChainTx` | ❌ Irreversible | BlockchainID is permanent on Fuji |
| `ConvertSubnetToL1Tx` | ❌ Irreversible | L1 conversion cannot be undone |
| Contract deployment | ❌ Irreversible | On-chain; no EVM contract deletion |
| `rewardVault.fund()` 15M PW | ❌ Irreversible | No withdrawal function |

**Before the ceremony:** All preparation is reversible. Genesis can be regenerated, keys can be regenerated, config can be deleted and recreated.

**After `CreateSubnetTx`:** Fuji P-Chain state is modified. The SubnetID exists permanently.

---

## 7. ERROR RECOVERY

### Error: "insufficient funds for gas * price + value"
- Deployer needs AVAX on C-Chain
- Solution: faucet.avax.network, then re-export to P-Chain

### Error: "P-Chain balance too low"
- Need more AVAX on P-Chain
- Solution: repeat `avalanche key transfer` for more AVAX

### Error: "blockchain already exists in subnet"
- A previous partial run created the chain
- Check if SubnetID + BlockchainID are recorded in `/tmp/fuji-ceremony.log`
- Do NOT re-run full deploy; use the existing IDs

### Error: "validator already exists"  
- A NodeID was already registered on P-Chain
- Use a different NodeID or check if it's already an L1 validator

### Error: "FeeDistributor address prediction mismatch"
- Deployer has prior transactions on chain (nonce ≠ 0)
- This means someone sent a tx from deployer before running deploy-contracts.sh
- Solution: Do not send any tx from deployer before deployment

### Error: `validatorManager()` returns deployer address (not 0x0FEEDC0DE...)
- `DeployTestnet.s.sol` was run with the old `deployer` placeholder
- This is a CRITICAL bug — the registry is permanently misconfigured
- No fix except redeployment of all contracts
- Prevention: ensure DeployTestnet.s.sol uses `0x0FEEDC0DE0000000000000000000000000000000` BEFORE running

---

## 8. TIMING ESTIMATE

| Step | Duration | Notes |
|---|---|---|
| `blockchain create` | <1 min | Local CLI operation only |
| Fund P-Chain (faucet + export) | 10–20 min | Faucet may have delays |
| Server provisioning (4 VPS) | 20–40 min | Parallel |
| Validator identity collection | 15 min | Per server, parallel |
| `blockchain deploy` (all 3 P-Chain txs + PoAManager init) | 5–15 min | Fuji P-Chain latency |
| Validator bootstrap (partial-sync) | 30–60 min | Parallel, all 4 nodes |
| DNS + TLS | 5–30 min | DNS TTL propagation |
| Contract deployment | 5–10 min | 7 contracts + RewardVault fund |
| **TOTAL (parallel where possible)** | **~2.5–3.5 hours** | — |
