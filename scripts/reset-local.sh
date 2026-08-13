#!/usr/bin/env bash
# PrimeWave Chain — Reset Local Environment
# ==========================================
# ENVIRONMENT: LOCAL DEVELOPMENT ONLY
#
# DESTRUCTIVE: Deletes all local network state.
# Use when you need a clean start.
#
# Usage: bash scripts/reset-local.sh

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

log_section "PrimeWave Chain — Reset Local Environment"
echo -e "  ${RED}WARNING: This will delete all local network state.${NC}"
echo -e "  This includes the P-Chain state and EVM data."
echo -e "  The chain will need to be fully redeployed after reset."
echo ""

# ── Stop running node ─────────────────────────────────────────────────────────
log_info "Stopping any running node..."
bash "$(dirname "${BASH_SOURCE[0]}")/stop-local.sh" 2>/dev/null || true
sleep 2

# ── Clean CLI state ───────────────────────────────────────────────────────────
log_section "Cleaning Avalanche CLI State"

log_info "Removing local cluster state..."
rm -rf "$HOME/.avalanche-cli/local/primewavedev-local-node-local-network" 2>/dev/null || true
log_ok "Local cluster removed"

log_info "Removing blockchain config..."
rm -rf "$HOME/.avalanche-cli/subnets/$PRIMEWAVE_CHAIN_NAME" 2>/dev/null || true
log_ok "Blockchain config removed"

log_info "Removing ANR network runs..."
rm -rf "$HOME/.avalanche-cli/runs" 2>/dev/null || true
log_ok "ANR runs removed"

log_info "Removing ANR snapshots..."
rm -rf "$HOME/.avalanche-cli/snapshots" 2>/dev/null || true
log_ok "ANR snapshots removed"

log_info "Clearing local network registry..."
echo '{}' > "$HOME/.avalanche-cli/localNetworks.json" 2>/dev/null || true
log_ok "localNetworks.json cleared"

# ── Clean local data ──────────────────────────────────────────────────────────
log_section "Cleaning Local Data"

log_info "Removing network state files..."
rm -f "$LOCAL_DATA_DIR/network-state.env" \
      "$LOCAL_DATA_DIR/node.pid" \
      "$LOCAL_DATA_DIR/node.log" \
      "$LOCAL_DATA_DIR/deploy.log" \
      "$LOCAL_DATA_DIR/setup-complete.env" \
      2>/dev/null || true
log_ok "Local data cleared"

# ── Done ──────────────────────────────────────────────────────────────────────
log_section "Reset Complete"
echo ""
echo -e "  ${GREEN}✓${NC} All local network state removed."
echo -e "  Binaries in local-bin/ are preserved (AvalancheGo, Avalanche CLI, subnet-evm)."
echo ""
echo -e "  ${BOLD}Next steps:${NC}"
echo -e "    bash scripts/setup-local.sh    — Recreate blockchain config"
echo -e "    bash scripts/start-local.sh    — Start fresh network"
echo ""
