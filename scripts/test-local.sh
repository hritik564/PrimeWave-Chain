#!/usr/bin/env bash
# PrimeWave Chain — Run Local Smoke Tests
# =========================================
# ENVIRONMENT: LOCAL DEVELOPMENT ONLY
#
# Wrapper that delegates to tests/smoke-test.sh.
# Verifies the network is running before delegating.
#
# Usage: bash scripts/test-local.sh [--no-tx]
#   --no-tx   Skip the PW transfer test (useful when running tests before
#             a funded account is available in the local context)

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

require_bins
require_jq
require_curl

log_section "PrimeWave Chain — Automated Smoke Tests"
echo -e "  ${YELLOW}DEVELOPMENT ONLY — Chain ID $PRIMEWAVE_DEV_CHAIN_ID${NC}"
echo ""

# Check network state
if [[ ! -f "$NETWORK_STATE_FILE" ]]; then
    log_error "Network state not found. Is the network running?"
    log_error "Run: bash scripts/start-local.sh"
    exit 1
fi

source "$NETWORK_STATE_FILE"

if [[ -z "${PRIMEWAVE_RPC_URL:-}" ]]; then
    log_error "PRIMEWAVE_RPC_URL not set in network state."
    log_error "Re-start the network: bash scripts/start-local.sh"
    exit 1
fi

# Quick pre-check
RPC_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "$PRIMEWAVE_RPC_URL" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
    --max-time 5 2>/dev/null || echo "000")

if [[ "$RPC_STATUS" != "200" ]]; then
    log_error "RPC not responding (HTTP $RPC_STATUS)."
    log_error "Network may not be running: bash scripts/start-local.sh"
    exit 1
fi

# Run the smoke tests
exec bash "$TESTS_DIR/smoke-test.sh" "$@"
