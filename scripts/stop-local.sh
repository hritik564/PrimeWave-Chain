#!/usr/bin/env bash
# PrimeWave Chain — Stop Local Network
# =====================================
# ENVIRONMENT: LOCAL DEVELOPMENT ONLY
#
# Usage: bash scripts/stop-local.sh

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

log_section "PrimeWave Chain — Stopping Local Network"

PID_FILE="$LOCAL_DATA_DIR/node.pid"
STOPPED=0

# ── Stop via PID file ─────────────────────────────────────────────────────────
if [[ -f "$PID_FILE" ]]; then
    NODE_PID=$(cat "$PID_FILE" 2>/dev/null || echo "")
    if [[ -n "$NODE_PID" ]] && kill -0 "$NODE_PID" 2>/dev/null; then
        log_info "Stopping avalanchego (PID $NODE_PID)..."
        kill -TERM "$NODE_PID" 2>/dev/null || true
        # Wait up to 10s for graceful shutdown
        for i in $(seq 1 10); do
            sleep 1
            if ! kill -0 "$NODE_PID" 2>/dev/null; then
                log_ok "Node stopped gracefully."
                STOPPED=1
                break
            fi
        done
        if [[ $STOPPED -eq 0 ]]; then
            log_warn "Graceful stop timed out. Force-killing..."
            kill -KILL "$NODE_PID" 2>/dev/null || true
            STOPPED=1
        fi
    else
        log_warn "PID file found ($NODE_PID) but process is not running."
        STOPPED=1
    fi
    rm -f "$PID_FILE"
fi

# ── Kill any stray avalanchego / subnet-evm processes ────────────────────────
STRAY_AVAGO=$(pgrep -f "avalanchego.*9656" 2>/dev/null || echo "")
STRAY_SEVM=$(pgrep -f "subnet-evm" 2>/dev/null || echo "")

if [[ -n "$STRAY_AVAGO" ]]; then
    log_info "Killing stray avalanchego: PIDs $STRAY_AVAGO"
    echo "$STRAY_AVAGO" | xargs kill -TERM 2>/dev/null || true
    STOPPED=1
fi
if [[ -n "$STRAY_SEVM" ]]; then
    log_info "Killing stray subnet-evm: PIDs $STRAY_SEVM"
    echo "$STRAY_SEVM" | xargs kill -TERM 2>/dev/null || true
fi

# ── Also stop any ANR primary network (if running) ───────────────────────────
"$AVALANCHE_CLI_BIN" network stop --skip-update-check 2>/dev/null || true

if [[ $STOPPED -eq 0 ]]; then
    log_warn "No running PrimeWave node found."
else
    log_ok "Network stopped."
fi

echo ""
