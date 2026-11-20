#!/usr/bin/env bash
# Start the verified local indexer as a managed background child and wait for
# its read-only health endpoint before the PWCScan artifact workflow starts.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

LOCAL_DATA_DIR="$REPO_ROOT/local-data"
PID_FILE="$LOCAL_DATA_DIR/indexer.pid"
LOG_FILE="$LOCAL_DATA_DIR/indexer.log"
HEALTH_URL="http://127.0.0.1:4000/health"

if [[ -f "$PID_FILE" ]]; then
    EXISTING_PID=$(cat "$PID_FILE" 2>/dev/null || true)
    if [[ -n "$EXISTING_PID" ]] && kill -0 "$EXISTING_PID" 2>/dev/null; then
        echo "[indexer-workflow] Refusing to start a second indexer; an indexer PID is already active." >&2
        exit 1
    fi
fi

if curl -fsS --max-time 2 "$HEALTH_URL" >/dev/null 2>&1; then
    echo "[indexer-workflow] Refusing to start a second indexer; port 4000 already serves a health response." >&2
    exit 1
fi

mkdir -p "$LOCAL_DATA_DIR"
LOG_PENDING=$(mktemp "$LOCAL_DATA_DIR/.indexer.log.pending.XXXXXX")
PID_PENDING=$(mktemp "$LOCAL_DATA_DIR/.indexer.pid.pending.XXXXXX")

nohup bash "$SCRIPT_DIR/start-indexer.sh" >"$LOG_PENDING" 2>&1 </dev/null &
INDEXER_PID=$!
printf '%s\n' "$INDEXER_PID" >"$PID_PENDING"

MAX_WAIT=90
for ((elapsed = 0; elapsed < MAX_WAIT; elapsed++)); do
    if curl -fsS --max-time 2 "$HEALTH_URL" >/dev/null 2>&1; then
        mv -f "$LOG_PENDING" "$LOG_FILE"
        mv -f "$PID_PENDING" "$PID_FILE"
        echo "[indexer-workflow] Verified indexer health; PWCScan preview may start."
        exit 0
    fi
    if ! kill -0 "$INDEXER_PID" 2>/dev/null; then
        FAILED_LOG="$LOCAL_DATA_DIR/indexer.failed.$(date -u +%Y%m%dT%H%M%SZ).log"
        mv -f "$LOG_PENDING" "$FAILED_LOG"
        rm -f "$PID_PENDING"
        echo "[indexer-workflow] Indexer exited before health was ready. Failure log: $FAILED_LOG" >&2
        exit 1
    fi
    sleep 1
done

kill "$INDEXER_PID" 2>/dev/null || true
for _ in 1 2 3 4 5; do
    kill -0 "$INDEXER_PID" 2>/dev/null || break
    sleep 1
done
FAILED_LOG="$LOCAL_DATA_DIR/indexer.failed.$(date -u +%Y%m%dT%H%M%SZ).log"
mv -f "$LOG_PENDING" "$FAILED_LOG"
rm -f "$PID_PENDING"
echo "[indexer-workflow] Indexer health did not become ready. Failure log: $FAILED_LOG" >&2
exit 1
