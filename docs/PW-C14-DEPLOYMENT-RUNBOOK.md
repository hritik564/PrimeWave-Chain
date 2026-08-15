# PW-C14: Testnet Deployment Runbook
**Sprint:** PW-C14
**Environment:** TESTNET ONLY — Chain ID 77 (Previous testnet Chain ID: 77777)
**Last Updated:** 2026-08-15

---

> **CRITICAL:** This runbook is for the PrimeWave **TESTNET** only.
> Chain ID **77**. NEVER execute against mainnet configuration.
> NEVER generate or use mainnet keys.

---

## Prerequisites

| Item | Required | Status |
|---|---|---|
| Cloud servers provisioned (Ubuntu 22.04) | 5 validators + 1 RPC + 1 explorer + 1 sentinel | [ ] |
| AvalancheGo v1.15.0-fuji downloaded | All nodes | [ ] |
| Subnet-EVM v1.15.0-fuji downloaded (tarball from release) | All nodes | [ ] |
| ICM Relayer icm-relayer-v1.8.0-fuji built | Sentinel | [ ] |
| Fuji testnet AVAX available (subnet creation) | ~2 AVAX | [ ] |
| Testnet keys generated | deployer + EMS ×5 + keeper | [ ] |
| Foundry v1.7.1 available | Deploy machine | [ ] |
| Domain names configured (DNS) | rpc.*, testnet.pwcscan.* | [ ] |

---

## Section 1: Key Generation

```bash
# Generate all testnet operational keys
TESTNET_KEY_DIR=/secure/testnet-keys \
bash scripts/testnet/generate-validator-keys.sh

# Record all PUBLIC addresses — never commit private keys
# See output for each address
```

---

## Section 2: Install Subnet-EVM Plugin

```bash
# Subnet-EVM is now distributed as a pre-built tarball from the AvalancheGo release
# (merged into AvalancheGo monorepo in v1.15.x — no separate compilation required)
SUBNET_EVM_VER="v1.15.0-fuji"
curl -fsSL \
  "https://github.com/ava-labs/avalanchego/releases/download/${SUBNET_EVM_VER}/subnet-evm-linux-amd64-${SUBNET_EVM_VER}.tar.gz" \
  | tar -xz -C /tmp --strip-components=1
sudo cp /tmp/subnet-evm /opt/avalanchego/plugins/rXJjKFtAVSmpKwhMhw7ZMV6opKcsmhk5AuVxWNAzFG221wmM8
sudo chmod +x /opt/avalanchego/plugins/rXJjKFtAVSmpKwhMhw7ZMV6opKcsmhk5AuVxWNAzFG221wmM8
# Verify: should report Subnet-EVM/v1.15.0 [rpcchainvm=46]
/opt/avalanchego/plugins/rXJjKFtAVSmpKwhMhw7ZMV6opKcsmhk5AuVxWNAzFG221wmM8 --version 2>&1 || true
# VM ID must match: rXJjKFtAVSmpKwhMhw7ZMV6opKcsmhk5AuVxWNAzFG221wmM8
```

---

## Section 3: Fuji P-Chain — Create Subnet and Blockchain

```bash
# Install Avalanche CLI v1.9.5
# Create subnet (spends ~0.001 AVAX Fuji)
avalanche subnet create primewaveTestnet

# Deploy to Fuji (creates P-Chain transactions)
avalanche subnet deploy primewaveTestnet --fuji \
  --key ~/.avalanche-cli/key/fuji-deployer.pk

# Record:
#   Subnet ID:       ________________
#   Blockchain ID:   ________________
#   VM ID:           ________________
# These IDs are permanent and go into the genesis + all node configs.
```

---

## Section 4: Genesis Construction

```bash
# Fill in genesis template with ceremony addresses
cp config/testnet/genesis-template.json config/testnet/genesis.json

# Edit config/testnet/genesis.json:
#   Replace __REPLACE_FEE_DISTRIBUTOR_ADDRESS__ with actual FeeDistributor address
#   Replace __REPLACE_TESTNET_DEPLOYER_ADDRESS__ with testnet deployer address
#   Replace __REPLACE_TESTNET_TREASURY_ADDRESS__ with testnet treasury address
#   (etc. for all __REPLACE_*__ placeholders)

# Validate
python3 -c "
import json
g=json.load(open('config/testnet/genesis.json'))
alloc = {k:v for k,v in g['alloc'].items() if not k.startswith('_')}
total = sum(int(v['balance'],16) for v in alloc.values())
assert total == 100_000_000*10**18, f'BAD SUPPLY: {total}'
assert g['config']['chainId'] == 77
print('Genesis OK — Chain ID 77, Supply 100M PW')
print(f'SHA-256: ', end=''); import subprocess; subprocess.run(['sha256sum','config/testnet/genesis.json'])
"

# Apply genesis to Avalanche CLI subnet config
# (avalanche subnet addGenesis primewaveTestnet --genesis config/testnet/genesis.json)
```

---

## Section 5: Node Setup (All Nodes)

```bash
# On each server (as root):
NODE_ROLE=validator \         # or 'rpc'
TESTNET_SUBNET_ID=<id> \
TESTNET_BLOCKCHAIN_ID=<id> \
bash scripts/testnet/setup-testnet-node.sh

# Copy chain config
mkdir -p ~/.avalanchego/configs/chains/<BLOCKCHAIN_ID>/
cp config/testnet/chain-config.json \
   ~/.avalanchego/configs/chains/<BLOCKCHAIN_ID>/config.json

# Install subnet-evm plugin
cp build/subnet-evm ~/.avalanchego/plugins/rXJjKFtAVSmpKwhMhw7ZMV6opKcsmhk5AuVxWNAzFG221wmM8

# Start node
systemctl start primewave-testnet-node
systemctl enable primewave-testnet-node

# Wait for bootstrap (may take 10–30 minutes on Fuji)
journalctl -fu primewave-testnet-node | grep -E "bootstrapped|healthy|error"
```

---

## Section 6: Contract Deployment

```bash
# On the deploy machine (with testnet deployer key):
TESTNET_RPC_URL=https://rpc.primewave-testnet.example.com/ext/bc/<BLOCKCHAIN_ID>/rpc \
TESTNET_DEPLOYER_KEY=<testnet-deployer-private-key> \
bash scripts/testnet/deploy-contracts.sh

# Contracts deployed:
#   EmergencyMultisig
#   PrimeWaveTimelock
#   FeeDistributor
#   ValidatorFeeVault
#   DevTreasury
#   RewardVault
#   PrimeWaveValidatorRegistry

# RewardVault funded with 15M PW automatically by script.
# Addresses saved to local-data/testnet-deployed-contracts.env
```

---

## Section 7: Validator Registration (ACP-99)

```bash
# For each validator node, get NodeID and BLS public key:
curl -s http://localhost:9650/ext/info | jq '{"nodeID":.nodeID,"blsPublicKey":.publicKey}'

# Register validators via PoAManager (via Protocol Admin multisig + Timelock):
# 1. Propose validator registration via multisig
# 2. Wait 48h timelock delay
# 3. Execute registration
# 4. Warp message propagates to P-Chain
# 5. Verify: validator appears in PrimeWaveValidatorRegistry
```

---

## Section 8: Indexer and Keeper

```bash
# Indexer — on Explorer Host:
cp deploy/testnet/env/testnet-indexer.env.template /etc/primewave/testnet-indexer.env
# Edit /etc/primewave/testnet-indexer.env with actual values
systemctl start primewave-testnet-indexer
curl http://localhost:4000/health  # Should return {"success":true}

# Keeper — on Sentinel:
cp deploy/testnet/env/testnet-keeper.env.template /etc/primewave/testnet-keeper.env
# Edit with keeper signer key and contract addresses
systemctl start primewave-testnet-keeper
curl http://localhost:8080/health  # Should return {"status":"ok"}
```

---

## Section 9: PWCScan Explorer

```bash
# Build PWCScan for testnet
cd artifacts/pwcscan
VITE_NETWORK_LABEL=Testnet \
VITE_CHAIN_ID=77 \
pnpm build

# Copy to explorer host, serve via nginx
# Nginx config: deploy/testnet/nginx/explorer.conf
```

---

## Section 10: TLS / nginx

```bash
# Install certbot
apt-get install -y certbot python3-certbot-nginx

# Obtain certificates
certbot --nginx \
  -d rpc.primewave-testnet.example.com \
  -d testnet.pwcscan.example.com

# Deploy nginx configs
cp deploy/testnet/nginx/rpc.conf /etc/nginx/sites-available/
cp deploy/testnet/nginx/explorer.conf /etc/nginx/sites-available/
nginx -t && systemctl reload nginx
```

---

## Section 11: Monitoring

```bash
# On Sentinel:
# Install Prometheus + Alertmanager + Grafana
cp deploy/testnet/prometheus/prometheus.yml /etc/prometheus/
cp deploy/testnet/prometheus/alert-rules.yml /etc/prometheus/rules/
systemctl restart prometheus

# Run health check
TESTNET_RPC_URL=https://rpc.primewave-testnet.example.com/ext/bc/<ID>/rpc \
TESTNET_INDEXER_URL=https://testnet.pwcscan.example.com/indexer-api \
bash scripts/testnet/testnet-health-check.sh
```

---

## Section 12: Acceptance Validation

```bash
# Validate genesis invariants
TESTNET_RPC_URL=... \
source local-data/testnet-deployed-contracts.env \
bash scripts/testnet/validate-testnet-genesis.sh

# Run full health check
bash scripts/testnet/testnet-health-check.sh

# C00-C13 regression (on local dev environment)
bash scripts/test-local.sh
```
