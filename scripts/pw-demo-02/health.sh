#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
assert_runtime_layout
[[ -f "$DEMO_READY_FILE" || -f "$DEMO_ATTEMPT_FILE" ]] || {
    demo_error "Network initialization has not started."
    exit 1
}
read_demo_state

health="$(curl -fsS --max-time 5 http://127.0.0.1:${PRIMEWAVE_HTTP_PORT}/ext/health)"
printf '%s\n' "$health" | jq -e '.healthy == true' >/dev/null || {
    demo_error "AvalancheGo health endpoint reports unhealthy."
    exit 1
}

actual_chain_id="$(curl -fsS --max-time 5 \
    -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
    "$PRIMEWAVE_RPC_URL" | jq -r '.result')"
[[ "$actual_chain_id" == "$EXPECTED_CHAIN_ID_HEX" ]] || {
    demo_error "RPC identity mismatch; expected $EXPECTED_CHAIN_ID_HEX."
    exit 1
}
if [[ -f "$DEMO_READY_FILE" ]]; then
    expected_genesis="$(jq -r '.genesisBlockHash' "$DEMO_READY_FILE")"
    actual_genesis="$(curl -fsS --max-time 5 \
        -H 'Content-Type: application/json' \
        -d '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["0x0",false],"id":3}' \
        "$PRIMEWAVE_RPC_URL" | jq -r '.result.hash')"
    [[ "$actual_genesis" == "$expected_genesis" ]] || {
        demo_error "Genesis block hash changed from the verified startup record."
        exit 1
    }
fi
block="$(curl -fsS --max-time 5 \
    -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":2}' \
    "$PRIMEWAVE_RPC_URL" | jq -r '.result')"
printf '[pw-demo-02] Healthy. Chain ID %s; block %s; Blockchain ID %s.\n' \
    "$actual_chain_id" "$block" "$PRIMEWAVE_BLOCKCHAIN_ID"
