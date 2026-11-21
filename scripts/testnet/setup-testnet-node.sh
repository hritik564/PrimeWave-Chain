#!/usr/bin/env bash
# ============================================================
# PrimeWave Testnet — Node Setup Script
# Sprint PW-C14 | TESTNET ONLY
# ============================================================
# Configures an Ubuntu 22.04 server to run a PrimeWave testnet
# validator or RPC node. Must be run as root or sudo.
#
# Prerequisites:
#   - Ubuntu 22.04 LTS
#   - 4 vCPU, 8GB RAM, 200GB SSD (validator)
#   - 8+ vCPU, 16GB RAM, 500GB NVMe SSD (RPC/archive)
#   - Node subnet ID and blockchain ID available
#
# Usage:
#   NODE_ROLE=validator \
#   TESTNET_SUBNET_ID=<subnet-id> \
#   TESTNET_BLOCKCHAIN_ID=<blockchain-id> \
#   bash scripts/testnet/setup-testnet-node.sh
# ============================================================
set -euo pipefail

NODE_ROLE="${NODE_ROLE:?NODE_ROLE must be 'validator' or 'rpc'}"
TESTNET_SUBNET_ID="${TESTNET_SUBNET_ID:?}"
AVALANCHEGO_VERSION="v1.15.0-fuji"
SUBNET_EVM_VERSION="v1.15.0-fuji"
NODE_USER="avalanche"
DATA_DIR="/data/avalanchego"
LOG_DIR="/var/log/avalanchego"
BIN_DIR="/opt/avalanchego"
PLUGIN_DIR="$BIN_DIR/plugins"

echo ""
echo "══ PrimeWave Testnet — Node Setup ══"
echo "  Role:              $NODE_ROLE"
echo "  AvalancheGo:       $AVALANCHEGO_VERSION (pinned)"
echo "  Subnet-EVM:        $SUBNET_EVM_VERSION (pinned)"
echo "  Subnet ID:         $TESTNET_SUBNET_ID"
echo ""

# Create service user
if ! id "$NODE_USER" &>/dev/null; then
  useradd -m -s /bin/bash "$NODE_USER"
  echo "[OK]    User $NODE_USER created"
fi

# Create directories
mkdir -p "$DATA_DIR" "$LOG_DIR" "$BIN_DIR" "$PLUGIN_DIR"
chown -R "$NODE_USER:$NODE_USER" "$DATA_DIR" "$LOG_DIR" "$BIN_DIR"
chmod 700 "$DATA_DIR"
echo "[OK]    Directories created"

# Install dependencies
apt-get update -qq
apt-get install -y -qq curl jq python3 build-essential
echo "[OK]    Dependencies installed"

# Download AvalancheGo
AVAGO_URL="https://github.com/ava-labs/avalanchego/releases/download/${AVALANCHEGO_VERSION}/avalanchego-linux-amd64-${AVALANCHEGO_VERSION}.tar.gz"
echo "[INFO]  Downloading AvalancheGo $AVALANCHEGO_VERSION ..."
curl -fsSL "$AVAGO_URL" | tar -xz -C "$BIN_DIR" --strip-components=1
chmod +x "$BIN_DIR/avalanchego"
echo "[OK]    AvalancheGo installed: $("$BIN_DIR/avalanchego" --version 2>&1 | head -1)"

# Place subnet-evm plugin
# Plugin (VM ID: rXJjKFtAVSmpKwhMhw7ZMV6opKcsmhk5AuVxWNAzFG221wmM8) is distributed as a
# pre-built tarball in the AvalancheGo v1.15.0-fuji release (subnet-evm moved into the
# AvalancheGo monorepo in v1.15.x — no separate compilation required).
# Download: https://github.com/ava-labs/avalanchego/releases/download/v1.15.0-fuji/subnet-evm-linux-amd64-v1.15.0-fuji.tar.gz
# The binary from the repository (local-bin/subnet-evm) is the correct v1.15.0-fuji binary.
SUBNET_EVM_URL="https://github.com/ava-labs/avalanchego/releases/download/${AVALANCHEGO_VERSION}/subnet-evm-linux-amd64-${SUBNET_EVM_VERSION}.tar.gz"
echo "[INFO]  Downloading subnet-evm $SUBNET_EVM_VERSION ..."
curl -fsSL "$SUBNET_EVM_URL" | tar -xz -C /tmp --strip-components=1
cp /tmp/subnet-evm "$PLUGIN_DIR/rXJjKFtAVSmpKwhMhw7ZMV6opKcsmhk5AuVxWNAzFG221wmM8"
chmod +x "$PLUGIN_DIR/rXJjKFtAVSmpKwhMhw7ZMV6opKcsmhk5AuVxWNAzFG221wmM8"
echo "[OK]    subnet-evm installed: $("$PLUGIN_DIR/rXJjKFtAVSmpKwhMhw7ZMV6opKcsmhk5AuVxWNAzFG221wmM8" --version 2>&1 | head -1)"

# Write chain config
BLOCKCHAIN_ID="${TESTNET_BLOCKCHAIN_ID:-__REPLACE_BLOCKCHAIN_ID__}"
CHAIN_CONFIG_DIR="$DATA_DIR/chainData/chains/$BLOCKCHAIN_ID"
mkdir -p "$CHAIN_CONFIG_DIR"
cp "$(dirname "${BASH_SOURCE[0]}")/../../config/testnet/chain-config.json" "$CHAIN_CONFIG_DIR/config.json"
echo "[OK]    Chain config written to $CHAIN_CONFIG_DIR/config.json"

# Adjust chain config for role
if [[ "$NODE_ROLE" == "rpc" ]]; then
  python3 -c "
import json
with open('$CHAIN_CONFIG_DIR/config.json','r') as f: cfg=json.load(f)
cfg['eth-apis'] = ['eth','eth-filter','internal-blockchain','net','web3']
cfg['state-sync-enabled'] = False
with open('$CHAIN_CONFIG_DIR/config.json','w') as f: json.dump(cfg,f,indent=2)
print('[OK]    Chain config updated for RPC/archive node')
"
fi

# Install node configuration file and systemd service
# Uses the canonical service file from deploy/testnet/systemd/ (single source of truth).
# The service reads all flags from /etc/primewave/node-config.json via --config-file.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)"
mkdir -p /etc/primewave

# Write node-config.json with subnet ID and role-appropriate http-host filled in
python3 << PYEOF
import json
cfg = json.load(open('$REPO_ROOT/config/testnet/node-config.json'))
cfg['track-subnets'] = '$TESTNET_SUBNET_ID'
cfg['plugin-dir']    = '$PLUGIN_DIR'
cfg['db-dir']        = '$DATA_DIR/db'
cfg['log-dir']       = '$LOG_DIR'
if '$NODE_ROLE' == 'rpc':
    cfg['http-host'] = '0.0.0.0'
    # RPC nodes: disable partial-sync so they have full state for queries
    cfg.pop('partial-sync-primary-network', None)
json.dump(cfg, open('/etc/primewave/node-config.json', 'w'), indent=2)
print('[OK]    Node config written to /etc/primewave/node-config.json')
PYEOF

# Install canonical service file (source of truth: deploy/testnet/systemd/)
SERVICE_FILE="/etc/systemd/system/primewave-testnet-node.service"
cp "$REPO_ROOT/deploy/testnet/systemd/primewave-testnet-node.service" "$SERVICE_FILE"
# Patch user/group if different from default 'avalanche'
if [[ "$NODE_USER" != "avalanche" ]]; then
  sed -i "s|User=avalanche|User=$NODE_USER|g; s|Group=avalanche|Group=$NODE_USER|g" "$SERVICE_FILE"
fi
# Patch ReadWritePaths to match DATA_DIR and LOG_DIR
sed -i "s|ReadWritePaths=/data/avalanchego /var/log/avalanchego|ReadWritePaths=$DATA_DIR $LOG_DIR|g" "$SERVICE_FILE"

systemctl daemon-reload
echo "[OK]    Systemd service installed: $SERVICE_FILE"
echo ""
echo "  Start node:  systemctl start primewave-testnet-node"
echo "  Enable boot: systemctl enable primewave-testnet-node"
echo "  View logs:   journalctl -fu primewave-testnet-node"
echo ""
echo "[DONE]  Node setup complete. Configure firewall before starting."
echo "        See docs/PW-C14-DEPLOYMENT-RUNBOOK.md for next steps."
