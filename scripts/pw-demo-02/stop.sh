#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
assert_runtime_layout
pid_file="$LOCAL_DATA_DIR/node.pid"
[[ -f "$pid_file" ]] || {
    printf '[pw-demo-02] No isolated node PID file; nothing was signaled.\n'
    exit 0
}
pid="$(cat "$pid_file")"
[[ "$pid" =~ ^[0-9]+$ ]] || {
    demo_error "PID file is invalid; no process was signaled."
    exit 1
}
kill -0 "$pid" 2>/dev/null || {
    printf '[pw-demo-02] Recorded process is not running; PID and chain data were preserved.\n'
    exit 0
}

exe="$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)"
cmdline="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)"
[[ "$exe" == "$(readlink -f "$AVALANCHEGO_BIN")" && "$cmdline" == *"/root/.avalanche-cli/local/"* ]] || {
    demo_error "PID does not identify this isolated AvalancheGo node; refusing to signal it."
    exit 1
}

kill -TERM "$pid"
for _ in $(seq 1 30); do
    if ! kill -0 "$pid" 2>/dev/null; then
        printf '[pw-demo-02] Node stopped gracefully; all chain state and logs remain in the runtime.\n'
        exit 0
    fi
    sleep 1
done
demo_error "Node did not exit after SIGTERM; no force kill was attempted."
exit 1
