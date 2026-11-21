#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
assert_runtime_layout

if [[ ! -f "$NETWORK_STATE_FILE" ]]; then
    printf '[pw-demo-02] No verified network state is recorded.\n'
    if [[ -f "$DEMO_ATTEMPT_FILE" ]]; then
        printf '[pw-demo-02] Initialization was attempted; logs and runtime were preserved.\n'
    fi
    exit 0
fi
read_demo_state

pid='not recorded'
proc_state='not running'
rss='unknown'
if [[ -f "$LOCAL_DATA_DIR/node.pid" ]]; then
    candidate="$(cat "$LOCAL_DATA_DIR/node.pid")"
    if [[ "$candidate" =~ ^[0-9]+$ ]] && kill -0 "$candidate" 2>/dev/null; then
        exe="$(readlink -f "/proc/$candidate/exe" 2>/dev/null || true)"
        cmdline="$(tr '\0' ' ' < "/proc/$candidate/cmdline" 2>/dev/null || true)"
        if [[ "$exe" == "$(readlink -f "$AVALANCHEGO_BIN")" && "$cmdline" == *"/root/.avalanche-cli/local/"* ]]; then
            pid="$candidate"
            proc_state='running'
            rss="$(awk '/VmRSS:/ {print $2 " KiB"}' "/proc/$candidate/status" 2>/dev/null || echo unknown)"
        else
            proc_state='PID exists but does not match this runtime'
        fi
    fi
fi

printf '[pw-demo-02] Process: %s (PID %s, RSS %s)\n' "$proc_state" "$pid" "$rss"
printf '[pw-demo-02] Chain ID: %s; Blockchain ID: %s; Subnet ID: %s\n' \
    "$PRIMEWAVE_DEV_CHAIN_ID" "$PRIMEWAVE_BLOCKCHAIN_ID" "$PRIMEWAVE_SUBNET_ID"
printf '[pw-demo-02] RPC: %s; runtime: %s\n' "$PRIMEWAVE_RPC_URL" "$RUNTIME_ROOT"
