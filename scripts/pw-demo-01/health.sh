#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
assert_demo_paths_isolated
[[ -f "$DEMO_READY_FILE" ]] || {
    demo_error "The isolated network has not passed startup verification."
    exit 1
}
read_demo_state

health="$(curl -fsS --max-time 5 \
    "http://127.0.0.1:${PRIMEWAVE_HTTP_PORT}/ext/health")" || {
    demo_error "AvalancheGo health endpoint is unavailable."
    exit 1
}
printf '%s\n' "$health" | jq -e '.healthy == true' >/dev/null || {
    demo_error "AvalancheGo health endpoint reports unhealthy."
    exit 1
}

actual_chain_id="$(curl -fsS --max-time 5 \
    -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
    "$PRIMEWAVE_RPC_URL" | jq -r '.result')"
[[ "$actual_chain_id" == "0x11f93" ]] || {
    demo_error "RPC identity mismatch; expected 0x11f93."
    exit 1
}
printf '[pw-demo-01] Healthy. EVM Chain ID %s; Blockchain ID %s; HTTP port %s; P2P port %s.\n' \
    "$actual_chain_id" "$PRIMEWAVE_BLOCKCHAIN_ID" \
    "$PRIMEWAVE_HTTP_PORT" "$PRIMEWAVE_P2P_PORT"
