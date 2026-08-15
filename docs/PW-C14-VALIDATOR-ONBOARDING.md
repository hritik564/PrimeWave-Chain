# PW-C14: Validator Onboarding Guide
**Sprint:** PW-C14
**Environment:** TESTNET ONLY — Chain ID **77** (Previous testnet Chain ID: 77777)
**Target:** 5 initial testnet validators

---

> ⚠️ **TESTNET ONLY.** These instructions produce testnet node keys.
> They are NOT used for mainnet validation.

---

## 1. Overview

This guide walks a new testnet validator operator through:
1. Provisioning a server
2. Installing AvalancheGo v1.15.0-fuji
3. Joining the PrimeWave testnet subnet
4. Providing NodeID and BLS key to PrimeWave for registration
5. Completing ACP-99 registration via the PoAManager

---

## 2. Server Requirements (Testnet Minimum)

| Component | Specification |
|---|---|
| CPU | 4 vCPU (x86-64) |
| RAM | 16 GB |
| Storage | 250 GB SSD |
| Network | 100 Mbps symmetric |
| OS | Ubuntu 22.04 LTS |
| Open Ports | 9651/tcp (P2P only) |

---

## 3. Step-by-Step Validator Setup

### Step 1: Install AvalancheGo v1.15.0-fuji

```bash
# Download (pinned version — DO NOT use a different version)
AVAGO_VER="v1.15.0-fuji"
curl -fsSL \
  "https://github.com/ava-labs/avalanchego/releases/download/${AVAGO_VER}/avalanchego-linux-amd64-${AVAGO_VER}.tar.gz" \
  | tar -xz -C /opt/avalanchego --strip-components=1

# Verify version
/opt/avalanchego/avalanchego --version
# Expected: avalanchego/1.15.0 [database=v1.4.5, rpcchainvm=46, ...]
```

### Step 2: Install Subnet-EVM Plugin

```bash
# The PrimeWave team provides the compiled subnet-evm binary.
# VM ID: rXJjKFtAVSmpKwhMhw7ZMV6opKcsmhk5AuVxWNAzFG221wmM8
mkdir -p /opt/avalanchego/plugins
# Copy binary provided by PrimeWave:
cp subnet-evm-binary /opt/avalanchego/plugins/rXJjKFtAVSmpKwhMhw7ZMV6opKcsmhk5AuVxWNAzFG221wmM8
chmod +x /opt/avalanchego/plugins/rXJjKFtAVSmpKwhMhw7ZMV6opKcsmhk5AuVxWNAzFG221wmM8
```

### Step 3: Configure Chain

```bash
BLOCKCHAIN_ID="__REPLACE_TESTNET_BLOCKCHAIN_ID__"
mkdir -p ~/.avalanchego/configs/chains/$BLOCKCHAIN_ID/
# Copy chain config provided by PrimeWave:
cat > ~/.avalanchego/configs/chains/$BLOCKCHAIN_ID/config.json << 'EOF'
{
  "pruning-enabled": false,
  "state-sync-enabled": false,
  "eth-apis": ["eth", "eth-filter", "net", "web3"],
  "log-level": "info",
  "allow-unprotected-txs": false
}
EOF
```

### Step 4: Start Node and Get Identity

```bash
# Start AvalancheGo (tracking testnet subnet)
/opt/avalanchego/avalanchego \
  --network-id=fuji \
  --http-host=127.0.0.1 \
  --http-port=9650 \
  --staking-port=9651 \
  --api-admin-enabled=false \
  --api-keystore-enabled=false \
  --track-subnets=__REPLACE_TESTNET_SUBNET_ID__ \
  --db-dir=/data/avalanchego/db \
  --plugin-dir=/opt/avalanchego/plugins \
  &

# Wait for startup (~30–60 seconds)
sleep 60

# Get NodeID
NODE_INFO=$(curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"info.getNodeID"}' \
  http://127.0.0.1:9650/ext/info)
echo "NodeID: $(echo $NODE_INFO | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['nodeID'])")"

# Get BLS Public Key
echo "BLS Public Key: $(echo $NODE_INFO | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['nodePOP']['publicKey'])")"
```

### Step 5: Submit Registration Data to PrimeWave

Provide to PrimeWave testnet coordinator:

```
Validator Operator: <your name / org>
NodeID: NodeID-<...>
BLS Public Key: 0x<...>
Server Public IP: <your server IP>
```

### Step 6: Await Registration Confirmation

PrimeWave admin will:
1. Propose validator registration via PoAManager + Timelock
2. Wait 48h delay (testnet may use reduced delay for rehearsal)
3. Execute registration
4. Warp message propagates to P-Chain
5. Notify you when registration is confirmed

### Step 7: Verify Registration

```bash
# Check validator appears in registry
cast call __REPLACE_VALIDATOR_REGISTRY_ADDRESS__ \
  "validatorCount()(uint256)" \
  --rpc-url https://rpc.primewave-testnet.example.com/ext/bc/__BLOCKCHAIN_ID__/rpc
```

---

## 4. Validator Operations

### Health Check

```bash
# Node health
curl -s http://127.0.0.1:9650/ext/health | python3 -m json.tool | grep healthy

# Block height (should advance ~every 2s)
cast block-number --rpc-url http://127.0.0.1:9650/ext/bc/$BLOCKCHAIN_ID/rpc
```

### Restart Procedure

```bash
systemctl restart primewave-testnet-node
# Wait 60s for re-bootstrap
journalctl -fu primewave-testnet-node | grep "bootstrapped"
```

### Graceful Stop (Planned Maintenance)

1. Notify PrimeWave testnet coordinator
2. `systemctl stop primewave-testnet-node`
3. Perform maintenance
4. `systemctl start primewave-testnet-node`
5. Confirm block height catches up

---

## 5. ACP-99 Validator Lifecycle

```
                    AvalancheGo Node Running
                           ↓
                   Submit NodeID + BLS Key
                           ↓
                  PoAManager.initiateRegistration()
                           ↓
                    Warp message → P-Chain
                           ↓
               PrimeWaveValidatorRegistry.syncValidator()
                           ↓
                    ValidatorFeeVault tracks fees
                           ↓
                   Validator earns 70% of gas fees
```

---

## 6. Testnet Validator Topology

| Validator | NodeID | BLS Public Key | Operator | Status |
|---|---|---|---|---|
| Validator 1 | TBD — ceremony | TBD — ceremony | PrimeWave | [ ] |
| Validator 2 | TBD — ceremony | TBD — ceremony | PrimeWave | [ ] |
| Validator 3 | TBD — ceremony | TBD — ceremony | PrimeWave | [ ] |
| Validator 4 | TBD — ceremony | TBD — ceremony | External Op A | [ ] |
| Validator 5 | TBD — ceremony | TBD — ceremony | External Op B | [ ] |
