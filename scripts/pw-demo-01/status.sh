#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
assert_demo_paths_isolated

if [[ ! -f "$LOCAL_DATA_DIR/network-state.env" ]]; then
    printf '[pw-demo-01] No verified network state is recorded.\n'
    if [[ -f "$DEMO_ATTEMPT_FILE" ]]; then
        printf '[pw-demo-01] Initialization was attempted; inspect isolated logs before recovery.\n'
    fi
    exit 0
fi

read_demo_state
pid='not recorded'
rss='unknown'
proc_state='not running'
if [[ -f "$LOCAL_DATA_DIR/node.pid" ]]; then
    candidate="$(cat "$LOCAL_DATA_DIR/node.pid")"
    if [[ "$candidate" =~ ^[0-9]+$ ]] && kill -0 "$candidate" 2>/dev/null; then
        exe="$(readlink -f "/proc/$candidate/exe" 2>/dev/null || true)"
        cmdline="$(tr '\0' ' ' < "/proc/$candidate/cmdline" 2>/dev/null || true)"
        if [[ "$exe" == "$(readlink -f "$AVALANCHEGO_BIN")" && "$cmdline" == *"$HOME/.avalanche-cli/local/"* ]]; then
            pid="$candidate"
            proc_state='running'
            rss="$(awk '/VmRSS:/ {print $2 " KiB"}' "/proc/$candidate/status" 2>/dev/null || echo unknown)"
        else
            proc_state='PID exists but does not match isolated AvalancheGo'
        fi
    fi
fi

printf '[pw-demo-01] Process: %s (PID %s, RSS %s)\n' "$proc_state" "$pid" "$rss"
printf '[pw-demo-01] EVM Chain ID: %s\n' "$PRIMEWAVE_DEV_CHAIN_ID"
printf '[pw-demo-01] Subnet ID: %s\n' "$PRIMEWAVE_SUBNET_ID"
printf '[pw-demo-01] Blockchain ID: %s\n' "$PRIMEWAVE_BLOCKCHAIN_ID"
printf '[pw-demo-01] RPC: %s\n' "$PRIMEWAVE_RPC_URL"
printf '[pw-demo-01] HTTP port: %s; P2P port: %s\n' "$PRIMEWAVE_HTTP_PORT" "$PRIMEWAVE_P2P_PORT"
printf '[pw-demo-01] Runtime root: %s\n' "$RUNTIME_ROOT"
