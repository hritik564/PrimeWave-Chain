#!/usr/bin/env bash
# ============================================================
# PrimeWave Chain — Validator Node Startup Script
# ============================================================
#
# Purpose:
#   Start a PrimeWave Chain AvalancheGo validator node with
#   the correct configuration and chain settings.
#
# Pre-requisites:
#   - AvalancheGo v1.14.2 installed at AVALANCHEGO_BIN
#   - PrimeWave chain config at CHAIN_CONFIG_DIR
#   - Staker certificate and key at STAKING_DIR
#   - Data directory writable at DATA_DIR
#
# Usage:
#   export AVALANCHEGO_BIN="/usr/local/bin/avalanchego"
#   export NETWORK_ID="primewavedev"   # or "fuji" for testnet
#   export DATA_DIR="/var/lib/avalanchego"
#   export LOG_DIR="/var/log/avalanchego"
#   ./scripts/start-validator.sh
#
# SECURITY:
#   - Do NOT run as root
#   - Staking key must be readable only by the service user
#   - Do NOT expose validator ports publicly (use firewall)
#   - P2P port (9651) may be public; API port (9650) should NOT
#
# ENVIRONMENT: Validator nodes only — not for RPC/archive nodes
# ============================================================

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────
AVALANCHEGO_BIN="${AVALANCHEGO_BIN:-/usr/local/bin/avalanchego}"
AVALANCHEGO_VERSION="${AVALANCHEGO_VERSION:-v1.14.2}"  # LOCKED — do not change without approval

NETWORK_ID="${NETWORK_ID:-primewavedev}"
DATA_DIR="${DATA_DIR:-/var/lib/avalanchego}"
LOG_DIR="${LOG_DIR:-/var/log/avalanchego}"
STAKING_DIR="${STAKING_DIR:-${DATA_DIR}/staking}"
CHAIN_CONFIG_DIR="${CHAIN_CONFIG_DIR:-/etc/avalanchego/chains}"
SUBNET_CONFIG_DIR="${SUBNET_CONFIG_DIR:-/etc/avalanchego/subnets}"

API_IP="${API_IP:-127.0.0.1}"         # Bind API to localhost only
API_PORT="${API_PORT:-9650}"
P2P_PORT="${P2P_PORT:-9651}"

PRIMEWAVE_BLOCKCHAIN_ID="${PRIMEWAVE_BLOCKCHAIN_ID:?PRIMEWAVE_BLOCKCHAIN_ID must be set}"
PRIMEWAVE_SUBNET_ID="${PRIMEWAVE_SUBNET_ID:?PRIMEWAVE_SUBNET_ID must be set}"

LOG_LEVEL="${LOG_LEVEL:-info}"
LOG_FORMAT="${LOG_FORMAT:-json}"

# ── Pre-flight checks ─────────────────────────────────────────────────────────
echo "==========================================================="
echo " PrimeWave Chain — Validator Node Startup"
echo " $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "==========================================================="
echo ""

# Verify AvalancheGo version
if [ ! -f "$AVALANCHEGO_BIN" ]; then
    echo "[ERROR] AvalancheGo not found at ${AVALANCHEGO_BIN}"
    echo "        Install AvalancheGo ${AVALANCHEGO_VERSION} before running this script"
    exit 1
fi

INSTALLED_VERSION=$("$AVALANCHEGO_BIN" --version 2>&1 | grep -oP 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
if [ "$INSTALLED_VERSION" != "$AVALANCHEGO_VERSION" ]; then
    echo "[WARN] AvalancheGo version mismatch: installed=${INSTALLED_VERSION} expected=${AVALANCHEGO_VERSION}"
    echo "       Proceeding — but verify compatibility before mainnet deployment"
fi
echo "  [OK] AvalancheGo: ${INSTALLED_VERSION}"

# Verify directories
for dir in "$DATA_DIR" "$LOG_DIR" "$STAKING_DIR"; do
    if [ ! -d "$dir" ]; then
        echo "[ERROR] Directory not found: ${dir}"
        exit 1
    fi
done
echo "  [OK] Data directories: OK"

# Verify staking keys
if [ ! -f "${STAKING_DIR}/staker.crt" ] || [ ! -f "${STAKING_DIR}/staker.key" ]; then
    echo "[ERROR] Staking certificate/key not found in ${STAKING_DIR}"
    echo "        Generate validator identity per PRIMEWAVE_KEY_SECURITY_PROCEDURE.md"
    exit 1
fi
echo "  [OK] Staking keys: found"

# Verify chain config
CHAIN_CONFIG_FILE="${CHAIN_CONFIG_DIR}/${PRIMEWAVE_BLOCKCHAIN_ID}/config.json"
if [ ! -f "$CHAIN_CONFIG_FILE" ]; then
    echo "[WARN] Chain config not found: ${CHAIN_CONFIG_FILE}"
    echo "       Creating minimal config..."
    mkdir -p "${CHAIN_CONFIG_DIR}/${PRIMEWAVE_BLOCKCHAIN_ID}"
    cat > "$CHAIN_CONFIG_FILE" << 'EOF'
{
  "pruning-enabled": false,
  "state-sync-enabled": false,
  "log-level": "info"
}
EOF
fi
echo "  [OK] Chain config: ${CHAIN_CONFIG_FILE}"

echo ""
echo "  Environment: ${NETWORK_ID}"
echo "  Blockchain ID: ${PRIMEWAVE_BLOCKCHAIN_ID}"
echo "  Subnet ID: ${PRIMEWAVE_SUBNET_ID}"
echo "  API: ${API_IP}:${API_PORT} (local only)"
echo "  P2P: 0.0.0.0:${P2P_PORT}"
echo ""
echo "==========================================================="
echo " Starting AvalancheGo..."
echo "==========================================================="

# ── Start AvalancheGo ─────────────────────────────────────────────────────────
exec "$AVALANCHEGO_BIN" \
    --network-id="${NETWORK_ID}" \
    --data-dir="${DATA_DIR}" \
    --log-dir="${LOG_DIR}" \
    --log-level="${LOG_LEVEL}" \
    --log-format="${LOG_FORMAT}" \
    --http-host="${API_IP}" \
    --http-port="${API_PORT}" \
    --staking-port="${P2P_PORT}" \
    --staking-tls-cert-file="${STAKING_DIR}/staker.crt" \
    --staking-tls-key-file="${STAKING_DIR}/staker.key" \
    --chain-config-dir="${CHAIN_CONFIG_DIR}" \
    --subnet-config-dir="${SUBNET_CONFIG_DIR}" \
    --track-subnets="${PRIMEWAVE_SUBNET_ID}" \
    --api-keystore-enabled=false \
    --api-admin-enabled=false
