# PW-C15 — INFRASTRUCTURE PROVISIONING GUIDE

**Sprint:** PW-C15-External
**Status:** REFERENCE DOCUMENT — Exact commands for human operators
**Date:** 2026-08-15

This document provides the exact steps a human operator must execute to provision
the real PrimeWave Testnet infrastructure. Nothing in this document requires Replit.
All commands run on the operator's own machines or cloud VPS instances.

---

## 1. DEPENDENCY MAP

```
OPERATOR WORKSTATION
      │
      ├── [1] Fund Fuji wallet via faucet.avax.network
      │
      ├── [2] Provision cloud VPS servers
      │         (15x validators + 1x RPC + 1x infra)
      │
      ├── [3] Register DNS
      │         rpc.testnet.primewave.xyz → RPC VPS IP
      │         explorer.testnet.primewave.xyz → Infra VPS IP
      │
      ├── [4] Issue TLS certificates
      │
      ├── [5] Fuji P-Chain setup
      │         CreateSubnetTx → SubnetID
      │         CreateChainTx → BlockchainID
      │         ConvertSubnetToL1Tx
      │
      ├── [6] Key ceremony (testnet keys only)
      │
      ├── [7] Fill genesis template → genesis.json
      │
      ├── [8] Deploy validators (copy from this repo)
      │
      ├── [9] Deploy contracts (forge script)
      │
      ├── [10] Deploy keeper / indexer / PWCScan
      │
      └── [11] Execute C15 battle test matrix
```

---

## 2. STEP 1: FUND FUJI TESTNET WALLET

The `testnet-deployer` key was generated in this Replit environment on 2026-08-15.

**Testnet-deployer public addresses (SAFE TO SHARE):**

| Chain | Address |
|---|---|
| C-Chain (EVM) | `0x2AD3152Ca630e2eF6679EBeb8da7b8311bfbFc60` |
| P-Chain (Fuji) | `P-fuji1p25rk6kz9lwg2plwmfmvkvzxsa5qd02kla0vsw` |
| X-Chain (Fuji) | `X-fuji1p25rk6kz9lwg2plwmfmvkvzxsa5qd02kla0vsw` |

> **SECURITY:** The private key for `testnet-deployer` is stored ONLY in the Replit
> environment at `~/.avalanche-cli/key/testnet-deployer.pk`. It must NOT be committed
> to this repository. For an actual security-grade testnet, generate keys on an
> air-gapped machine per `docs/PRIMEWAVE_KEY_SECURITY_PROCEDURE.md` and discard the
> Replit-generated key.

**Fund via Fuji faucet:**

1. Go to: https://faucet.avax.network
2. Enter C-Chain address: `0x2AD3152Ca630e2eF6679EBeb8da7b8311bfbFc60`
3. Select network: **Fuji**
4. Request AVAX (typically 2 AVAX per request per day)
5. Repeat as needed — Fuji P-Chain operations cost approximately:
   - CreateSubnetTx: dynamic fee (~0.001 AVAX with current fee config)
   - CreateChainTx: dynamic fee (~0.001 AVAX)
   - ConvertSubnetToL1Tx: depends on validator set size
   - **Total recommended**: fund with ≥ 2 AVAX on C-Chain, then export to P-Chain

**Export AVAX from C-Chain to P-Chain:**

```bash
export PATH="$REPO_ROOT/local-bin:$PATH"

# Export from C-Chain to P-Chain
avalanche key transfer \
  --key testnet-deployer \
  --fuji \
  --amount 1.0 \
  --destination-key testnet-deployer \
  --source-chain C \
  --destination-chain P
```

---

## 3. STEP 2: CLOUD SERVER PROVISIONING

### Minimum recommended topology

| Server | Role | Recommended size | Count |
|---|---|---|---|
| validator-01..15 | AvalancheGo validator | 4 vCPU / 8GB RAM / 500GB SSD | 15 |
| rpc-01 | Public RPC + nginx | 4 vCPU / 8GB RAM / 200GB SSD | 1 |
| infra-01 | Indexer + PWCScan + PostgreSQL + Keeper | 4 vCPU / 16GB RAM / 500GB SSD | 1 |
| monitoring-01 | Prometheus + Grafana | 2 vCPU / 4GB RAM / 100GB SSD | 1 |
| **Total** | | | **18 servers** |

### Cost estimate (Hetzner Cloud, approximate)

| Server type | Count | ~€/month | Subtotal |
|---|---|---|---|
| CX32 (4 vCPU / 8GB / 160GB, +SSD volume) | 16 | €15 | €240 |
| CX42 (8 vCPU / 16GB / 240GB) | 1 | €30 | €30 |
| CX22 (2 vCPU / 4GB / 80GB) | 1 | €8 | €8 |
| SSD volumes (300GB each, validators) | 15 | €12 | €180 |
| **Estimated monthly** | | | **~€458/month** |

> Hetzner recommended for cost-effectiveness. AWS/GCP/DigitalOcean also supported.

### AWS equivalent

```bash
# AWS CLI — launch validator VPS
aws ec2 run-instances \
  --image-id ami-0c7217cdde317cfec \  # Ubuntu 22.04 LTS
  --instance-type t3.xlarge \
  --count 15 \
  --key-name primewave-testnet \
  --security-group-ids sg-XXXX \
  --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":500,"VolumeType":"gp3"}}]' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=primewave-validator}]'
```

### Required firewall rules

| Port | Protocol | Purpose | Allowed from |
|---|---|---|---|
| 22 | TCP | SSH (admin) | Operator IPs only |
| 9651 | TCP/UDP | AvalancheGo P2P | Public |
| 9650 | TCP | AvalancheGo API | Internal (localhost/LAN) only |
| 80, 443 | TCP | HTTP/HTTPS (RPC + PWCScan) | Public (RPC node only) |
| 5432 | TCP | PostgreSQL | Internal only |
| 9090 | TCP | Prometheus scrape | Monitoring server only |

---

## 4. STEP 3: DNS CONFIGURATION

Register the following DNS A records with your DNS provider:

| Hostname | Type | Target | TTL |
|---|---|---|---|
| `rpc.testnet.primewave.xyz` | A | RPC server IP | 300 |
| `explorer.testnet.primewave.xyz` | A | Infra server IP | 300 |
| `monitoring.testnet.primewave.xyz` | A | Monitoring server IP | 300 |

> Use a testnet-specific subdomain. Do NOT point `primewave.xyz` (root) or
> `pwcscan.com` at the testnet unless explicitly intended.

---

## 5. STEP 4: TLS CERTIFICATES

Install certbot and obtain Let's Encrypt certificates:

```bash
# On RPC server
sudo apt install certbot python3-certbot-nginx
sudo certbot --nginx -d rpc.testnet.primewave.xyz

# On Infra server
sudo certbot --nginx -d explorer.testnet.primewave.xyz

# Auto-renewal (add to crontab)
0 3 * * * certbot renew --quiet
```

Copy the nginx configs from this repo:

```bash
sudo cp deploy/testnet/nginx/rpc.conf /etc/nginx/sites-available/primewave-rpc
sudo cp deploy/testnet/nginx/explorer.conf /etc/nginx/sites-available/primewave-explorer
sudo ln -s /etc/nginx/sites-available/primewave-rpc /etc/nginx/sites-enabled/
sudo ln -s /etc/nginx/sites-available/primewave-explorer /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

---

## 6. STEP 5: FUJI P-CHAIN SUBNET SETUP

**Prerequisites:** testnet-deployer funded with ≥ 0.1 AVAX on P-Chain.

```bash
export PATH="$REPO_ROOT/local-bin:$PATH"

# Step 5a: Create Fuji subnet
avalanche blockchain deploy primewavedev \
  --fuji \
  --key testnet-deployer \
  --num-validators 5

# --- OR manually ---

# Create subnet (get SubnetID from output)
avalanche subnet create primewave-testnet \
  --genesis config/testnet/genesis.json \
  --vm subnet-evm \
  --evm-chain-id 77

# Deploy to Fuji (triggers CreateSubnetTx + CreateChainTx)
avalanche blockchain deploy primewave-testnet \
  --fuji \
  --key testnet-deployer

# Record from output:
# Subnet ID: <SUBNET_ID>
# Blockchain ID: <BLOCKCHAIN_ID>
```

**After deploy, update these files with the actual IDs:**

- `config/testnet/node-config.json` → fill `track-subnets`
- `deploy/testnet/env/testnet-*.env.template` → fill `INDEXER_BLOCKCHAIN_ID`, `KEEPER_BLOCKCHAIN_ID`

---

## 7. STEP 6: GENESIS CEREMONY AND FINAL GENESIS

```bash
# On air-gapped machine (per docs/PRIMEWAVE_KEY_SECURITY_PROCEDURE.md):
# Generate testnet ceremony keys

# Then fill genesis template:
# Replace all __REPLACE_*__ in config/testnet/genesis-template.json
# with actual ceremony addresses

# Verify before using:
python3 -c "
import json
g = json.load(open('config/testnet/genesis-template.json'))
remaining = [k for k in g['alloc'] if '__REPLACE_' in k]
assert not remaining, f'Unfilled placeholders: {remaining}'
print('All placeholders filled')
"

# Strip metadata and generate final genesis
python3 -c "
import json
g = json.load(open('config/testnet/genesis-template.json'))
clean = {k: v for k, v in g.items() if not k.startswith('_')}
clean['alloc'] = {k: {sk: sv for sk, sv in v.items() if not sk.startswith('_')}
                  for k, v in g['alloc'].items() if not k.startswith('_')}
json.dump(clean, open('config/testnet/genesis.json', 'w'), indent=2)
print('genesis.json generated')
"

# Verify
bash scripts/testnet/validate-testnet-genesis.sh config/testnet/genesis.json

# Record hashes
sha256sum config/testnet/genesis.json
```

---

## 8. STEP 7: DEPLOY VALIDATOR NODES

On each validator VPS:

```bash
# Copy repository to server
git clone <repo> /opt/primewave
cd /opt/primewave

# Copy AvalancheGo binary
cp local-bin/avalanchego /usr/local/bin/avalanchego
cp local-bin/subnet-evm /opt/primewave/plugins/

# Configure node
bash scripts/testnet/setup-testnet-node.sh

# Install systemd unit
sudo cp deploy/testnet/systemd/primewave-testnet-node.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable primewave-testnet-node
sudo systemctl start primewave-testnet-node

# Monitor
journalctl -u primewave-testnet-node -f
```

---

## 9. STEP 8: DEPLOY CONTRACTS

```bash
# From operator workstation (or infra server) after testnet RPC is live
export TESTNET_RPC_URL=https://rpc.testnet.primewave.xyz
export TESTNET_DEPLOYER_KEY=<testnet-deployer private key — KEEP SECRET>

# This script enforces chain ID == 77 (refuses dev or wrong network)
bash scripts/testnet/deploy-contracts.sh

# Record all output contract addresses
```

---

## 10. STEP 9: DEPLOY KEEPER + INDEXER + PWCSCAN

```bash
# On infra-01 server
# Copy env templates
cp deploy/testnet/env/testnet-keeper.env.template /etc/testnet/keeper.env
cp deploy/testnet/env/testnet-indexer.env.template /etc/testnet/indexer.env
cp deploy/testnet/env/testnet-pwcscan.env.template /etc/testnet/pwcscan.env

# Fill in actual values:
# KEEPER_RPC_URL, KEEPER_PRIVATE_KEY, KEEPER_REGISTRY_ADDRESS, etc.
# INDEXER_RPC_URL, INDEXER_CHAIN_ID=77, DATABASE_URL
# VITE_RPC_URL, VITE_CHAIN_ID=77, VITE_NETWORK_LABEL=Testnet

# Install and start systemd units
sudo cp deploy/testnet/systemd/primewave-testnet-*.service /etc/systemd/system/
sudo systemctl daemon-reload
for svc in primewave-testnet-indexer primewave-testnet-keeper primewave-testnet-pwcscan; do
  sudo systemctl enable $svc
  sudo systemctl start $svc
done

# Verify health
bash scripts/testnet/testnet-health-check.sh
```

---

## 11. STEP 10: MONITORING

```bash
# On monitoring-01
sudo apt install prometheus grafana

# Use our config
sudo cp deploy/testnet/prometheus/prometheus.yml /etc/prometheus/prometheus.yml
sudo cp deploy/testnet/prometheus/alert-rules.yml /etc/prometheus/alert-rules.yml
sudo systemctl restart prometheus
```

---

## 12. MINIMUM VIABLE TESTNET (REDUCED SCOPE)

If 15 validators cannot be provisioned immediately, a 3-validator minimum viable
testnet can validate most C15 gate items:

| Server | Role |
|---|---|
| validator-01 | Bootstrap validator |
| validator-02 | Second validator |
| validator-03 | Third validator |
| infra-01 | RPC + Keeper + Indexer + PostgreSQL + PWCScan |

This topology can validate all protocol behavior tests. Validator count must be
reported as ACTUAL = 3 (not 15).

---

## 13. WHAT IS EXECUTABLE NOW (IN REPLIT, NO EXTERNAL INFRA)

| Item | Status | Evidence |
|---|---|---|
| Forge 792/792 | ✅ PASS | Run 2026-08-15 |
| Indexer Jest 57/57 | ✅ PASS | Run 2026-08-15 |
| Keeper Jest 20/20 | ✅ PASS | Run 2026-08-15 |
| Genesis static validation (Chain ID, supply, NativeMinter) | ✅ PASS | Python check |
| deploy-contracts.sh chain ID guard (rejects dev chain) | ✅ PASS | Tested against dev RPC |
| Fuji P-Chain API reachability | ✅ PASS | api.avax-test.network: height 292884 |
| testnet-deployer key generated | ✅ DONE | C-Chain: 0x2AD3152Ca630e2eF6679EBeb8da7b8311bfbFc60 |
| testnet-deployer Fuji balance | ❌ 0 AVAX | Fund via faucet.avax.network |
| Fuji subnet creation | BLOCKED | Needs funded P-Chain wallet + external validator nodes |
| Cloud validator nodes | BLOCKED | Needs cloud VPS |
| Public RPC | BLOCKED | Needs cloud VPS + DNS + TLS |
| PWCScan live on testnet | BLOCKED | Needs live testnet RPC |
| All C15 battle test items | BLOCKED | Needs live testnet |
