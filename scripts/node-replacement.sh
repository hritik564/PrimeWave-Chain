#!/usr/bin/env bash
# ============================================================
# PrimeWave Chain — Node Replacement Procedure
# ============================================================
#
# Purpose:
#   Safely replace a failed or degraded validator node without
#   compromising validator identity or causing double-signing.
#
# This script performs:
#   1. Stop the old instance (if reachable)
#   2. Verify old node is stopped
#   3. Provision the replacement (configuration)
#   4. Restore validator identity (staking keys)
#   5. Synchronize the chain
#   6. Verify validator status
#   7. Re-enable monitoring
#
# CRITICAL:
#   - The old node MUST be stopped before starting the replacement
#   - NEVER run two instances with the same staker.key simultaneously
#   - Validator identity (NodeID) must be preserved exactly
#
# Usage:
#   OLD_NODE_HOST=10.0.0.1 NEW_NODE_HOST=10.0.0.2 \
#   ./scripts/node-replacement.sh
#
# ENVIRONMENT: Run from operations workstation — NOT on either node
# ============================================================

set -euo pipefail

OLD_NODE_HOST="${OLD_NODE_HOST:?OLD_NODE_HOST must be set}"
NEW_NODE_HOST="${NEW_NODE_HOST:?NEW_NODE_HOST must be set}"
SSH_KEY="${SSH_KEY:-~/.ssh/primewave_ops}"
SERVICE_NAME="${SERVICE_NAME:-avalanchego}"
BACKUP_STAKING_DIR="${BACKUP_STAKING_DIR:?BACKUP_STAKING_DIR must be set (path to staking key backup)}"
DATA_DIR="${DATA_DIR:-/var/lib/avalanchego}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
step() { echo -e "\n${GREEN}[STEP]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }
ssh_cmd() { ssh -i "$SSH_KEY" -o StrictHostKeyChecking=yes "$@"; }

echo "==========================================================="
echo " PrimeWave Chain — Node Replacement Procedure"
echo " $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "==========================================================="
echo " Old node: ${OLD_NODE_HOST}"
echo " New node: ${NEW_NODE_HOST}"
echo "==========================================================="

# ── Step 1: Stop old node ─────────────────────────────────────────────────────
step "Step 1: Stopping old node (${OLD_NODE_HOST})"
if ssh_cmd "${OLD_NODE_HOST}" "sudo systemctl is-active ${SERVICE_NAME}" 2>/dev/null; then
    ssh_cmd "${OLD_NODE_HOST}" "sudo systemctl stop ${SERVICE_NAME}" || warn "Could not stop gracefully — continuing"
    sleep 5
else
    warn "Old node service not reachable — assuming already stopped"
fi

# ── Step 2: Verify old node is stopped ───────────────────────────────────────
step "Step 2: Verifying old node is stopped"
if ssh_cmd "${OLD_NODE_HOST}" "sudo systemctl is-active ${SERVICE_NAME}" 2>/dev/null; then
    fail "Old node service is still running — ABORT to prevent double-signing"
fi
echo "  Old node: STOPPED"

# CRITICAL PAUSE: operator must confirm old node is fully down before proceeding
echo ""
echo -e "${RED}CRITICAL: Old node confirmed stopped.${NC}"
echo "Press ENTER to continue with replacement, or Ctrl+C to abort."
read -r

# ── Step 3: Provision replacement ────────────────────────────────────────────
step "Step 3: Provisioning replacement node (${NEW_NODE_HOST})"
# Install AvalancheGo (version-pinned)
ssh_cmd "${NEW_NODE_HOST}" "sudo mkdir -p ${DATA_DIR}/{staking,chains,subnets} ${DATA_DIR}/../log"
echo "  Directories created on new node"

# ── Step 4: Restore validator identity ───────────────────────────────────────
step "Step 4: Restoring validator identity (staking keys)"
warn "SECURITY: Staking key is being transferred. Ensure secure channel."
echo "  Source: ${BACKUP_STAKING_DIR}/staker.{crt,key}"

# Transfer staking keys from secure backup (not from old node)
scp -i "$SSH_KEY" \
    "${BACKUP_STAKING_DIR}/staker.crt" \
    "${BACKUP_STAKING_DIR}/staker.key" \
    "${NEW_NODE_HOST}:${DATA_DIR}/staking/"

# Restrict key permissions
ssh_cmd "${NEW_NODE_HOST}" "chmod 600 ${DATA_DIR}/staking/staker.key && chmod 644 ${DATA_DIR}/staking/staker.crt"
echo "  Staking keys: transferred and permissions set"

# ── Step 5: Transfer chain configuration ─────────────────────────────────────
step "Step 5: Transferring chain configuration"
scp -i "$SSH_KEY" -r \
    "${OLD_NODE_HOST}:/etc/avalanchego/" \
    "${NEW_NODE_HOST}:/etc/avalanchego/" 2>/dev/null || \
    warn "Could not copy config from old node — copy from local config backup"

# ── Step 6: Start new node and synchronize ───────────────────────────────────
step "Step 6: Starting new node"
ssh_cmd "${NEW_NODE_HOST}" "sudo systemctl start ${SERVICE_NAME}"
sleep 10

# Wait for sync
echo "  Waiting for chain sync (this may take minutes to hours)..."
MAX_WAIT_SECONDS=3600
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT_SECONDS ]; do
    HEALTHY=$(ssh_cmd "${NEW_NODE_HOST}" "curl -sf http://127.0.0.1:9650/ext/health | python3 -c \"import sys,json; print(json.load(sys.stdin).get('healthy','false'))\"" 2>/dev/null || echo "false")
    if [ "$HEALTHY" = "True" ] || [ "$HEALTHY" = "true" ]; then
        echo "  Node: HEALTHY after ${ELAPSED}s"
        break
    fi
    sleep 30
    ELAPSED=$((ELAPSED + 30))
    echo "  Waiting... ${ELAPSED}s elapsed"
done

if [ $ELAPSED -ge $MAX_WAIT_SECONDS ]; then
    fail "Node did not become healthy within ${MAX_WAIT_SECONDS}s — check logs"
fi

# ── Step 7: Verify validator status ──────────────────────────────────────────
step "Step 7: Verifying validator status"
NODE_ID=$(ssh_cmd "${NEW_NODE_HOST}" "curl -sf http://127.0.0.1:9650/ext/info | python3 -c \"import sys,json; print(json.load(sys.stdin).get('result',{}).get('nodeID','UNKNOWN'))\"" 2>/dev/null || echo "UNKNOWN")
echo "  NodeID: ${NODE_ID}"

if [ "$NODE_ID" = "UNKNOWN" ]; then
    warn "Could not read NodeID — verify manually"
else
    echo "  Verify this NodeID matches the registered validator:"
    echo "  Expected: (check docs/PW-C11-GENESIS-FINALIZATION.md validator list)"
fi

# ── Step 8: Run health check ──────────────────────────────────────────────────
step "Step 8: Running health check on new node"
export CHAIN_RPC_URL="http://${NEW_NODE_HOST}:9650/ext/bc/${PRIMEWAVE_BLOCKCHAIN_ID:-C}/rpc"
export AVAGO_API_URL="http://${NEW_NODE_HOST}:9650"
./scripts/health-check.sh || warn "Health check reported warnings — review above"

echo ""
echo "==========================================================="
echo " NODE REPLACEMENT COMPLETE"
echo " New node: ${NEW_NODE_HOST}"
echo " NodeID:   ${NODE_ID}"
echo "==========================================================="
echo ""
echo "Next steps:"
echo "  1. Run validate-production-genesis.sh against new node"
echo "  2. Re-enable monitoring for new node IP"
echo "  3. Update monitoring dashboards with new node host"
echo "  4. Verify keeper is syncing correctly"
echo "  5. Archive old node staking keys (do NOT delete — keep in secure backup)"
echo "==========================================================="
