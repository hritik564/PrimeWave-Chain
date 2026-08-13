#!/usr/bin/env bash
# PrimeWave Chain — Shared Script Environment
# LOCAL DEVELOPMENT ONLY — NOT FOR TESTNET OR MAINNET
# =====================================================
# Source this file from all other scripts:
#   source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

set -euo pipefail

# ── Repository root ──────────────────────────────────────────────────────────
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT

# ── Foundry toolchain — add to PATH ──────────────────────────────────────────
# Foundry is installed via foundryup to ~/.foundry/bin/
# Version pinned below (PW-C02); update only with documented compatibility review.
FOUNDRY_BIN="${HOME:-/root}/.foundry/bin"
if [[ -d "$FOUNDRY_BIN" ]] && [[ ":$PATH:" != *":$FOUNDRY_BIN:"* ]]; then
    export PATH="$FOUNDRY_BIN:$PATH"
fi

# ── Pinned dependency versions (from PW-C00 FINAL GATE / PW-C02) ─────────────
# DO NOT change these without a documented compatibility review.
AVALANCHEGO_VERSION="v1.14.2"
AVALANCHE_CLI_VERSION="v1.9.5"
FOUNDRY_VERSION="1.7.1"
FOUNDRY_COMMIT="4072e48705af9d93e3c0f6e29e93b5e9a40caed8"
FOUNDRY_BUILD_DATE="2026-05-08"
export AVALANCHEGO_VERSION AVALANCHE_CLI_VERSION FOUNDRY_VERSION FOUNDRY_COMMIT FOUNDRY_BUILD_DATE

# ── Binary locations ──────────────────────────────────────────────────────────
LOCAL_BIN_DIR="$REPO_ROOT/local-bin"
AVALANCHEGO_BIN="$LOCAL_BIN_DIR/avalanchego"
AVALANCHE_CLI_BIN="$LOCAL_BIN_DIR/avalanche"
export LOCAL_BIN_DIR AVALANCHEGO_BIN AVALANCHE_CLI_BIN

# ── Chain configuration ───────────────────────────────────────────────────────
PRIMEWAVE_CHAIN_NAME="primewavedev"  # No special chars — Avalanche CLI requires letters only
PRIMEWAVE_DEV_CHAIN_ID="73571"
PRIMEWAVE_TOKEN_SYMBOL="PW"
PRIMEWAVE_TOKEN_NAME="PrimeWave"
export PRIMEWAVE_CHAIN_NAME PRIMEWAVE_DEV_CHAIN_ID PRIMEWAVE_TOKEN_SYMBOL PRIMEWAVE_TOKEN_NAME

# ── Network parameters ────────────────────────────────────────────────────────
NODE_COUNT="${PRIMEWAVE_NODE_COUNT:-1}"
LOCAL_HOST="127.0.0.1"
RPC_PORT="9656"    # Local cluster node HTTP port (set by Avalanche CLI tmpnet)
export NODE_COUNT LOCAL_HOST RPC_PORT

# ── Paths ─────────────────────────────────────────────────────────────────────
CHAIN_DIR="$REPO_ROOT/chain"
CONFIG_DIR="$REPO_ROOT/config"
TESTS_DIR="$REPO_ROOT/tests"
LOCAL_DATA_DIR="$REPO_ROOT/local-data"
NETWORK_STATE_FILE="$LOCAL_DATA_DIR/network-state.env"
export CHAIN_DIR CONFIG_DIR TESTS_DIR LOCAL_DATA_DIR NETWORK_STATE_FILE

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'
export RED GREEN YELLOW BLUE CYAN BOLD NC

# ── Logging helpers ───────────────────────────────────────────────────────────
log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_section() { echo -e "\n${BOLD}${CYAN}══ $* ══${NC}"; }
export -f log_info log_ok log_warn log_error log_section

# ── Load network state if it exists ──────────────────────────────────────────
if [[ -f "$NETWORK_STATE_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$NETWORK_STATE_FILE"
fi

# ── Prerequisite checks ───────────────────────────────────────────────────────
require_bins() {
    local missing=0
    for bin in "$AVALANCHEGO_BIN" "$AVALANCHE_CLI_BIN"; do
        if [[ ! -x "$bin" ]]; then
            log_error "Required binary not found or not executable: $bin"
            log_error "Run: bash scripts/setup-local.sh"
            missing=1
        fi
    done
    [[ $missing -eq 0 ]] || exit 1
}

require_jq() {
    if ! command -v jq &>/dev/null; then
        log_error "jq is required but not installed."
        exit 1
    fi
}

require_curl() {
    if ! command -v curl &>/dev/null; then
        log_error "curl is required but not installed."
        exit 1
    fi
}

export -f require_bins require_jq require_curl
