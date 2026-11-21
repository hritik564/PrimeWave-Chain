#!/usr/bin/env bash
# Offline production validation only. Required inputs are explicit; no local RPC
# fallback and no eth_getCode-based claims about native precompile activation.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$SCRIPT_DIR/mainnet/validate_genesis.py" "$@"
