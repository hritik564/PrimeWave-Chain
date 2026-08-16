# PrimeWave — ValidatorManager / PoAManager Architecture
## PW-C15 | Phase 1 Testnet | Evidence-Based

**Status:** Authoritative — derived from actual contract code and CLI binary inspection  
**Date:** 2026-08-16  
**DO NOT execute any transaction until this document is signed off**

---

## 1. THE CRITICAL FINDING

`PrimeWaveValidatorRegistry.validatorManager` is **`public immutable`**.

```solidity
// contracts/src/PrimeWaveValidatorRegistry.sol line 140
IACP99ManagerReader public immutable validatorManager;

// constructor line 192
validatorManager = IACP99ManagerReader(_validatorManager);
```

**There is no `setValidatorManager()` function.** Once `DeployTestnet.s.sol` deploys the Registry, the ValidatorManager address is permanently fixed. The current code passes `deployer` as a placeholder — this is a bug. It must be changed to the real PoAManager proxy address **before** `DeployTestnet.s.sol` is run.

---

## 2. AVALANCHE L1 VALIDATOR MANAGER PREDEPLOY ADDRESS

Confirmed from `~/.avalanche-cli/subnets/primewavedev/sidecar.json`:

```json
"ValidatorManagerAddress": "0x0FEEDC0DE0000000000000000000000000000000"
```

This is the **Avalanche CLI standard predeploy address** for all L1 ValidatorManagers (PoA and PoS). The CLI injects the PoAManager proxy bytecode at this address into the genesis `alloc` when deploying with `--proof-of-authority --acp99`.

**This address is deterministic and known before any transaction.**

---

## 3. WHAT THE AVALANCHE CLI DOES DURING `blockchain deploy`

When `avalanche blockchain deploy primewave-testnet --fuji --key testnet-deployer` is run (without `--convert-only`), the CLI performs this exact sequence:

```
Step 1: CreateSubnetTx (P-Chain)
        → SubnetID produced (bytes32, base58-encoded)

Step 2: Augment genesis
        CLI merges into our genesis.json:
          alloc["0x0FEEDC0DE0000000000000000000000000000000"] = {
            code:    <ERC1967Proxy bytecode pointing to PoAManager implementation>,
            storage: <initialized proxy storage slots>,
            balance: "0x0"
          }
          alloc["<PoAManager implementation address>"] = {
            code:    <PoAManager implementation bytecode>,
            storage: {},
            balance: "0x0"
          }
          alloc["<ProxyAdmin address>"] = {
            code:    <ProxyAdmin bytecode>,
            storage: {},
            balance: "0x0"
          }
        The proxy is initialized with:
          - owner           = --validator-manager-owner address
          - subnetID        = SubnetID from Step 1
          - churnParams     = default (5% per 10 min)
          
Step 3: CreateChainTx (P-Chain)
        → BlockchainID produced (bytes32, base58-encoded)
        Genesis contains PoAManager proxy at 0x0FEEDC0DE...
        Chain is live from first block with PoAManager already deployed
        
Step 4: ConvertSubnetToL1Tx (P-Chain)
        Fields:
          subnetID                   = SubnetID from Step 1
          chainID                    = BlockchainID from Step 3
          validatorManagerBlockchainID = BlockchainID from Step 3 (same chain)
          validatorManagerAddress    = 0x0FEEDC0DE0000000000000000000000000000000
          initialValidators          = [from --bootstrap-filepath or --bootstrap-endpoints]
        
Step 5 (if NOT --convert-only): PoAManager post-initialization
        CLI calls PoAManager.initialize() to complete setup
        with the blockchain IDs and initial validator info
```

**The `--convert-only` flag SKIPS Steps 5 and node tracking.**  
**For remote validators, omit `--convert-only`** — the CLI will not restart remote nodes (it only restarts nodes managed by the CLI cluster). Without `--convert-only`, PoAManager is fully initialized by the CLI.

---

## 4. CONFIRMED ARCHITECTURE

```
Avalanche Fuji P-Chain
│
│  ConvertSubnetToL1Tx {
│    validatorManagerBlockchainID = <PrimeWave L1 BlockchainID>
│    validatorManagerAddress      = 0x0FEEDC0DE0000000000000000000000000000000
│    initialValidators            = [NodeID-x, NodeID-y, NodeID-z, NodeID-w]
│  }
│
▼
PrimeWave L1 (Chain ID 77)
│
│  0x0FEEDC0DE0000000000000000000000000000000
│  ├── ERC1967Proxy (deployed via genesis alloc)
│  └── implementation: PoAManager (from ava-labs/icm-contracts)
│       │  initiateValidatorRegistration(nodeID, blsKey, ...)
│       │  completeValidatorRegistration(messageIndex)
│       │  initiateValidatorRemoval(validationID)
│       │  completeValidatorRemoval(messageIndex)
│       │  getValidator(validationID) → ValidatorACP99
│
│  PrimeWaveValidatorRegistry (deployed by DeployTestnet.s.sol)
│  ├── validatorManager: immutable = 0x0FEEDC0DE0000000000000000000000000000000 ← MUST SET THIS
│  ├── registerValidator(validationID, rewardRecipient) → admin only
│  ├── syncValidator(validationID) → permissionless
│  └── → calls feeVault.{addValidator, setActive, setInactive, ...}
│
│  ValidatorFeeVault (deployed by DeployTestnet.s.sol)
│  └── reward-index accounting per validationID
│
│  FeeDistributor (deployed by DeployTestnet.s.sol)
│  └── receives tx fees via RewardManager precompile
│
│  RewardManager precompile (0x0200000000000000000000000000000000000004)
│  └── rewardAddress = FeeDistributor address (set in genesis)
│
│  WarpMessenger precompile (0x0200000000000000000000000000000000000005)
│  └── ICM/Warp cross-chain messaging (P-Chain ↔ L1)
```

---

## 5. DEPLOYMENT ORDER — EXACT AND COMPLETE

### Phase A: Before L1 Exists (can do now, Replit)

```
A1. Generate 7 EOA keys (testnet-deployer + keeper-signer + ems-signer-1..5)
    → testnet-deployer address = <DEPLOYER_ADDR>

A2. Compute FeeDistributor predicted address
    deployer nonce=4 when FeeDistributor is deployed
    predicted = CREATE(deployer, 4) = keccak256(RLP([deployer, 4]))[12:]
    → fd_addr = <FD_PREDICTED_ADDR>

A3. Finalize genesis.json
    Replace all 7 placeholders:
      __REPLACE_TESTNET_DEPLOYER_ADDRESS__ → <DEPLOYER_ADDR>
      __REPLACE_FEE_DISTRIBUTOR_ADDRESS__  → <FD_PREDICTED_ADDR>
      __REPLACE_TESTNET_TREASURY_ADDRESS__ → <operator-provided>
      __REPLACE_TESTNET_TEAM_ADDRESS__     → <operator-provided>
      __REPLACE_TESTNET_COMMUNITY_ADDRESS__→ <operator-provided>
      __REPLACE_TESTNET_ECOSYSTEM_ADDRESS__→ <operator-provided>
      __REPLACE_TESTNET_RESERVE_ADDRESS__  → <operator-provided>
    
    Verify SHA256 of genesis.json — all operators must agree
    
A4. Fix DeployTestnet.s.sol
    CHANGE:
      PrimeWaveValidatorRegistry registry = new PrimeWaveValidatorRegistry(
          deployer,
          deployer,   ← WRONG (immutable, placeholder, can never be updated)
          address(feeVault)
      );
    TO:
      address constant POA_MANAGER = 0x0FEEDC0DE0000000000000000000000000000000;
      ...
      PrimeWaveValidatorRegistry registry = new PrimeWaveValidatorRegistry(
          deployer,
          POA_MANAGER, ← CORRECT (predeploy address, exists from genesis block 0)
          address(feeVault)
      );
    
    ALSO FILL: EMS_SIGNER_1..5 constants with generated addresses

A5. Create blockchain config in Avalanche CLI
    avalanche blockchain create primewave-testnet \
      --fuji \
      --genesis config/testnet/genesis.json \
      --vm subnet-evm \
      --evm-chain-id 77 \
      --proof-of-authority \
      --acp99 \
      --validator-manager-owner <DEPLOYER_ADDR> \
      --proxy-contract-owner <DEPLOYER_ADDR>
```

### Phase B: Server Provisioning (parallel with parts of Phase A)

```
B1. Provision 4 VPS servers (4 vCPU / 8GB / 200GB SSD, Ubuntu 22.04)

B2. On each server:
    bash setup-testnet-node.sh
    (downloads AvalancheGo v1.15.0-fuji + subnet-evm v1.15.0-fuji plugin)

B3. Start each node ONCE (without --track-subnets) to generate identity
    systemctl start primewave-testnet-node
    sleep 30
    
B4. Collect from each node:
    curl -s http://localhost:9650/ext/info -X POST \
      -H 'Content-Type: application/json' \
      --data '{"jsonrpc":"2.0","id":1,"method":"info.getNodeID","params":{}}' \
      | python3 -m json.tool
    
    Record per node:
      - NodeID (base58, e.g. NodeID-9wJ1Wh...)
      - BLSPublicKey (48-byte hex, from response.result.publicKey)
      - BLSProofOfPossession (96-byte hex, from response.result.proofOfPossession)

B5. Create bootstrap-validators.json:
    [
      {
        "NodeID": "NodeID-<validator-1>",
        "Weight": 100,
        "Balance": 0.375,
        "BLSPublicKey": "0x<48-byte-hex>",
        "BLSProofOfPossession": "0x<96-byte-hex>",
        "ChangeOwnerAddr": "P-fuji1<deployer-p-chain-addr>"
      },
      { ... validator 2 ... },
      { ... validator 3 ... },
      { ... validator 4 ... }
    ]
```

### Phase C: Fuji P-Chain Ceremony ← IRREVERSIBLE

```
C1. Fund testnet-deployer
    - Fuji C-Chain: ≥ 16,000,002 PW (from genesis alloc) — genesis-funded, no action
    - Fuji C-Chain AVAX: ≥ 2 AVAX (for P-Chain export + fees)
    - Source: faucet.avax.network
    
C2. Export C-Chain AVAX → P-Chain
    avalanche key transfer \
      --key testnet-deployer \
      --fuji \
      --amount 1.5 \
      --source-chain C \
      --destination-chain P
    
    # Verify
    avalanche key list --fuji
    # Expect: testnet-deployer P-Chain balance ≥ 1.5 AVAX

C3. Run Fuji L1 ceremony  ← POINT OF NO RETURN
    avalanche blockchain deploy primewave-testnet \
      --fuji \
      --key testnet-deployer \
      --bootstrap-filepath config/testnet/bootstrap-validators.json \
      --num-bootstrap-validators 4 \
      --balance 0.375 \
      --change-owner-address P-fuji1<deployer-p-chain-addr>
    
    Records from output:
      Subnet ID:      <TESTNET_SUBNET_ID>
      Blockchain ID:  <TESTNET_BLOCKCHAIN_ID>
      PoAManager:     0x0FEEDC0DE0000000000000000000000000000000
```

### Phase D: Chain Bootstrap

```
D1. Update node-config.json on each validator with SubnetID:
    python3 -c "
    import json
    c = json.load(open('/etc/primewave/node-config.json'))
    c['track-subnets'] = '<TESTNET_SUBNET_ID>'
    json.dump(c, open('/etc/primewave/node-config.json','w'), indent=2)
    "
    
D2. Copy chain-config.json to blockchain ID path:
    mkdir -p /data/avalanchego/chainData/chains/<TESTNET_BLOCKCHAIN_ID>/
    cp /opt/primewave/config/testnet/chain-config.json \
       /data/avalanchego/chainData/chains/<TESTNET_BLOCKCHAIN_ID>/config.json

D3. Restart all validators:
    systemctl restart primewave-testnet-node
    
D4. Wait for bootstrap (~30-60 min with --partial-sync-primary-network)
    # Poll health:
    curl -sf http://localhost:9650/ext/health | python3 -c \
      "import json,sys; d=json.load(sys.stdin); print('Healthy:', d.get('healthy'))"
    
D5. Verify block production:
    curl -sf https://api.avax-test.network/ext/bc/<TESTNET_BLOCKCHAIN_ID>/rpc \
      -X POST -H 'Content-Type: application/json' \
      --data '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}' \
      | python3 -m json.tool
```

### Phase E: Contract Deployment

```
E1. Set RPC URL:
    export TESTNET_RPC_URL=https://api.avax-test.network/ext/bc/<TESTNET_BLOCKCHAIN_ID>/rpc
    # OR after DNS: https://rpc.testnet.primewave.xyz
    
E2. Verify PoAManager exists at predeploy address:
    cast code 0x0FEEDC0DE0000000000000000000000000000000 \
      --rpc-url $TESTNET_RPC_URL
    # Must return non-empty bytecode
    
E3. Deploy PrimeWave contracts:
    TESTNET_RPC_URL=$TESTNET_RPC_URL \
    TESTNET_DEPLOYER_KEY=0x$(cat /secure/testnet-keys/testnet-deployer.json | python3 -c "import json,sys; print(json.load(sys.stdin)['privateKey'][2:])") \
    bash scripts/testnet/deploy-contracts.sh
    
E4. Verify:
    source local-data/testnet-deployed-contracts.env
    # ADDR_VALIDATOR_REGISTRY.validatorManager should return 0x0FEEDC0DE...
    cast call $ADDR_VALIDATOR_REGISTRY \
      "validatorManager()(address)" \
      --rpc-url $TESTNET_RPC_URL
    # Must return: 0x0FEEDC0DE0000000000000000000000000000000
```

### Phase F: Validator Registration via PoAManager (ACP-99)

```
F1. Admin binds validators in PrimeWaveValidatorRegistry
    # For each validator (after PoAManager.initiateValidatorRegistration runs via keeper/CLI):
    cast send $ADDR_VALIDATOR_REGISTRY \
      "registerValidator(bytes32,address)" \
      <validationID> <validator-reward-recipient> \
      --rpc-url $TESTNET_RPC_URL \
      --private-key $TESTNET_DEPLOYER_KEY
    
F2. Verify each validator is active:
    cast call $ADDR_VALIDATOR_REGISTRY \
      "validatorStatus(bytes32)(uint8)" \
      <validationID> \
      --rpc-url $TESTNET_RPC_URL
    # Returns: 2 (Active)
```

---

## 6. KEY DEPENDENCY: IMMUTABLE VALIDATORMANAGER

The most important fix required before running `DeployTestnet.s.sol`:

**Current code (BROKEN):**
```solidity
PrimeWaveValidatorRegistry registry = new PrimeWaveValidatorRegistry(
    deployer,
    deployer,   // placeholder — IMMUTABLE — can NEVER be changed after deploy
    address(feeVault)
);
```

**Fixed code (CORRECT):**
```solidity
address constant POA_MANAGER_ADDR = 0x0FEEDC0DE0000000000000000000000000000000;
...
PrimeWaveValidatorRegistry registry = new PrimeWaveValidatorRegistry(
    deployer,
    POA_MANAGER_ADDR,   // real predeploy address — exists from genesis block 0
    address(feeVault)
);
```

**Evidence for address:**
- `~/.avalanche-cli/subnets/primewavedev/sidecar.json` → `"ValidatorManagerAddress": "0x0FEEDC0DE0000000000000000000000000000000"`
- This is the universal Avalanche CLI ValidatorManager predeploy address for all L1 chains

**Why this is safe to hardcode:**
- The CLI ALWAYS deploys the PoAManager proxy at this address when using `--proof-of-authority`
- The address exists from genesis block 0 (it is in the genesis alloc)
- The address is the same on all Avalanche L1 chains
- The chain will not produce blocks without it

---

## 7. THE WARP ROUND-TRIP FOR POST-LAUNCH VALIDATOR CHANGES

After the initial 4 validators are set via `ConvertSubnetToL1Tx`, adding or removing validators requires:

```
Admin calls on PrimeWave L1:
  PoAManager.initiateValidatorRegistration(nodeID, blsKey, ...) 
  ↓ emits Warp message (via 0x0200...0005 precompile)

ICM Relayer monitors PrimeWave L1 for Warp messages
  ↓ picks up initiateValidatorRegistration message
  ↓ aggregates BLS signatures from 3/4 validators
  ↓ submits RegisterL1ValidatorTx to Fuji P-Chain

Fuji P-Chain confirms
  ↓ sends Warp response back

ICM Relayer picks up P-Chain response
  ↓ delivers to PrimeWave L1

Keeper (testnet-keeper-signer) calls:
  PoAManager.completeValidatorRegistration(messageIndex)
  ↓ validator status becomes Active in PoAManager

Admin calls on PrimeWave L1:
  PrimeWaveValidatorRegistry.registerValidator(validationID, rewardRecipient)
  ↓ validator enters fee accounting in ValidatorFeeVault
```

**The initial 4 validators from `ConvertSubnetToL1Tx` are automatically Active in PoAManager.**  
They still require `PrimeWaveValidatorRegistry.registerValidator()` to enter fee accounting.

---

## 8. ANSWERS TO ALL 12 QUESTIONS FROM AUDIT REQUEST

| Q | Answer |
|---|---|
| 1. What contract is the ValidatorManager for Phase 1? | `PoAManager` from ava-labs/icm-contracts, deployed as `ERC1967Proxy` |
| 2. Architecture type? | ERC1967Proxy → PoAManager (no separate ValidatorManager, no custom proxy) |
| 3. Where must it live at ConvertSubnetToL1Tx? | On the PrimeWave L1 itself, as a genesis predeploy |
| 4. On which blockchain? | PrimeWave L1 (BlockchainID = L1's own chain ID) |
| 5. How does address reach ConvertSubnetToL1Tx? | Hardcoded at `0x0FEEDC0DE0000000000000000000000000000000`; CLI reads from sidecar config |
| 6. Does genesis already contain it? | NO — our genesis template does NOT contain it. The CLI ADDS it to the genesis before CreateChainTx |
| 7. What is its exact address? | `0x0FEEDC0DE0000000000000000000000000000000` |
| 7b. How initialized? | CLI calls `initialize()` on the proxy as part of `blockchain deploy` |
| 7c. How connected to PoAManager? | The proxy IS the PoAManager (proxy → implementation); no separate connection |
| 8. N/A — genesis does not contain it (CLI adds it) | — |
| 9. How does PrimeWaveValidatorRegistry get real address? | **Must be hardcoded in DeployTestnet.s.sol.** The `validatorManager` field is immutable. Must pass `0x0FEEDC0DE...` directly instead of `deployer` placeholder |
| 10. What calls initialize the validator set? | `ConvertSubnetToL1Tx` on P-Chain (initial set); `PoAManager.initiateValidatorRegistration()` + ICM relayer + `completeValidatorRegistration()` for subsequent additions |
| 11. What calls are required after conversion? | (1) `registry.registerValidator(validationID, rewardRecipient)` for each initial validator; (2) Deploy ICM relayer; (3) Deploy keeper |
| 12. Is the diagram correct? | Partially. The correct architecture: `ConvertSubnetToL1Tx → ERC1967Proxy(PoAManager) ← PrimeWaveValidatorRegistry → ValidatorFeeVault`. There is no separate "ValidatorManager" layer above PoAManager — PoAManager IS the ValidatorManager. |

---

## 9. SUMMARY: BLOCKERS SPECIFIC TO THIS SECTION

| Blocker | Fix | Status |
|---|---|---|
| `DeployTestnet.s.sol` passes `deployer` (not `0x0FEEDC0DE...`) as immutable `validatorManager` | Change to `0x0FEEDC0DE0000000000000000000000000000000` | ❌ Not yet fixed |
| `avalanche blockchain create` not yet run for `primewave-testnet` | Run with `--proof-of-authority --acp99 --validator-manager-owner <addr>` | ❌ Not yet done |
| `bootstrap-validators.json` file not yet created | Created after all 4 nodes generate identities | ❌ Nodes not provisioned |
| `--num-validators 4` in all docs (wrong flag) | Change to `--num-bootstrap-validators 4` | ❌ All docs need update |
