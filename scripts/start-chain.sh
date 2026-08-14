#!/usr/bin/env bash
# PrimeWave Chain — Replit Workflow Wrapper
# ==========================================
# Starts the local PrimeWave chain and keeps this process alive
# (by tailing the node log) so the Replit workflow stays running.
#
# Replit workflow command:
#   bash scripts/start-chain.sh
#
# What this does:
#   1. Calls start-local.sh (handles all complex Avalanche setup)
#   2. Ensures node.log exists
#   3. exec tail -f on the log to keep the workflow process alive
#      while avalanchego runs as a background daemon
#
# To stop: stop the workflow (Replit will SIGTERM this process).
# The avalanchego daemon runs independently and survives workflow restarts.
# On workflow restart, start-local.sh detects the daemon is running and
# skips restarting it.
#
# ENVIRONMENT: LOCAL DEVELOPMENT ONLY

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

echo "[chain-workflow] Starting PrimeWave local chain..."
bash "$SCRIPT_DIR/start-local.sh"

# Ensure the log file exists (start-local.sh creates it, but be defensive)
touch local-data/node.log

echo "[chain-workflow] Chain is running. Tailing node log (Ctrl+C to stop workflow)..."
exec tail -f local-data/node.log
