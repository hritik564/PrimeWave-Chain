#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
assert_demo_paths_isolated

pid_file="$LOCAL_DATA_DIR/node.pid"
[[ -f "$pid_file" ]] || {
    printf '[pw-demo-01] No isolated node PID file; nothing was signaled.\n'
    exit 0
}
pid="$(cat "$pid_file")"
[[ "$pid" =~ ^[0-9]+$ ]] || {
    demo_error "PID file is invalid; no process was signaled."
    exit 1
}
kill -0 "$pid" 2>/dev/null || {
    printf '[pw-demo-01] Recorded process is not running; preserved PID and chain data.\n'
    exit 0
}

exe="$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)"
cmdline="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)"
[[ "$exe" == "$(readlink -f "$AVALANCHEGO_BIN")" && "$cmdline" == *"$HOME/.avalanche-cli/local/"* ]] || {
    demo_error "PID does not match this isolated AvalancheGo runtime; refusing to signal it."
    exit 1
}

kill -TERM "$pid"
for _ in $(seq 1 30); do
    if ! kill -0 "$pid" 2>/dev/null; then
        printf '[pw-demo-01] Isolated node stopped gracefully; chain data and PID record were preserved.\n'
        exit 0
    fi
    sleep 1
done
demo_error "Isolated node did not exit after SIGTERM; no force kill was attempted."
exit 1
