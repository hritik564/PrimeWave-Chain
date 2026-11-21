#!/usr/bin/env bash
set -euo pipefail

DEMO_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$DEMO_SCRIPT_DIR/../.." && pwd)"
RUNTIME_ROOT="$WORKSPACE_ROOT/.local-networks/pw-demo-02"
CLI_HOME="$RUNTIME_ROOT/cli-home"
ROOT_HOME="$RUNTIME_ROOT/os-home"
TMP_DIR="$RUNTIME_ROOT/tmp"
CONFIG_DIR="$RUNTIME_ROOT/config"
LOCAL_DATA_DIR="$RUNTIME_ROOT/data"
PRIVATE_DIR="$RUNTIME_ROOT/private"
METADATA_DIR="$RUNTIME_ROOT/metadata"
PID_DIR="$RUNTIME_ROOT/pids"
LOG_DIR="$RUNTIME_ROOT/logs"
CACHE_DIR="$RUNTIME_ROOT/cache"
HOST_ACCOUNT_HOME="${PWDEMO_HOST_ACCOUNT_HOME:-$(getent passwd "$(id -u)" | cut -d: -f6)}"
HOST_CLI_HOME="$HOST_ACCOUNT_HOME/.avalanche-cli"
SANDBOX_HOME="/root"
VM_ID="rXJjKFtAVSmpKwhMhw7ZMV6opKcsmhk5AuVxWNAzFG221wmM8"
EXPECTED_CHAIN_ID="73571"
EXPECTED_CHAIN_ID_HEX="0x11f63"

export LOCAL_BIN_DIR="$WORKSPACE_ROOT/local-bin"
export AVALANCHEGO_BIN="$LOCAL_BIN_DIR/avalanchego"
export AVALANCHE_CLI_BIN="$LOCAL_BIN_DIR/avalanche"
export CHAIN_DIR="$CONFIG_DIR"
export CONFIG_DIR LOCAL_DATA_DIR
export NETWORK_STATE_FILE="$LOCAL_DATA_DIR/network-state.env"
export PRIMEWAVE_ISOLATION_ROOT="$RUNTIME_ROOT"

source "$WORKSPACE_ROOT/scripts/_common.sh"

DEMO_READY_FILE="$METADATA_DIR/ready.json"
DEMO_ATTEMPT_FILE="$METADATA_DIR/initialization-started"
DEMO_ACCOUNTS_FILE="$METADATA_DIR/accounts.json"
DEMO_TRANSFER_FILE="$METADATA_DIR/transfer.json"
DEMO_TRANSFER_ATTEMPT_FILE="$METADATA_DIR/transfer-attempted"
DEMO_KEY_FILE="$PRIVATE_DIR/sender.key"
DEMO_RESTART_BASELINE="$METADATA_DIR/restart-baseline.json"

demo_error() {
    printf '[pw-demo-02] ERROR: %s\n' "$*" >&2
}

assert_runtime_layout() {
    local expected_parent expected_root resolved path
    expected_parent="$WORKSPACE_ROOT/.local-networks"
    [[ -d "$expected_parent" && ! -L "$expected_parent" ]] || {
        demo_error "The ignored runtime parent must exist as a real directory, not a symlink."
        return 1
    }
    [[ "$(realpath -e "$expected_parent")" == "$expected_parent" ]] || {
        demo_error "The runtime parent resolves outside the workspace."
        return 1
    }
    [[ ! -L "$RUNTIME_ROOT" ]] || {
        demo_error "Runtime root must not be a symlink."
        return 1
    }
    expected_root="$expected_parent/pw-demo-02"
    [[ "$(realpath -m "$RUNTIME_ROOT")" == "$expected_root" ]] || {
        demo_error "Runtime root resolves outside its approved workspace path."
        return 1
    }
    if [[ -e "$RUNTIME_ROOT" ]]; then
        [[ -d "$RUNTIME_ROOT" ]] || {
            demo_error "Runtime path exists but is not a directory."
            return 1
        }
    fi

    for path in "$CLI_HOME" "$ROOT_HOME" "$TMP_DIR" "$CONFIG_DIR" \
        "$CONFIG_DIR/genesis" "$LOCAL_DATA_DIR" "$PRIVATE_DIR" \
        "$METADATA_DIR" "$PID_DIR" "$LOG_DIR" "$CACHE_DIR"; do
        [[ ! -L "$path" ]] || {
            demo_error "A runtime path is a symlink: $path"
            return 1
        }
        if [[ -e "$path" ]]; then
            resolved="$(realpath -e "$path")"
            case "$resolved" in
                "$expected_root"/*) ;;
                *) demo_error "Writable path escapes the approved runtime: $path"; return 1 ;;
            esac
        fi
    done
}

read_demo_state() {
    [[ -f "$NETWORK_STATE_FILE" && ! -L "$NETWORK_STATE_FILE" ]] || {
        demo_error "No verified runtime network state exists."
        return 1
    }
    # This file is generated only after RPC identity verification and contains
    # public network identifiers and loopback URLs, never private keys.
    # shellcheck source=/dev/null
    source "$NETWORK_STATE_FILE"
    [[ "${PRIMEWAVE_DEV_CHAIN_ID:-}" == "$EXPECTED_CHAIN_ID" ]] || {
        demo_error "Saved runtime is not Chain ID $EXPECTED_CHAIN_ID."
        return 1
    }
    [[ "${PRIMEWAVE_RPC_URL:-}" == http://127.0.0.1:* ]] || {
        demo_error "Saved RPC URL is not loopback-only."
        return 1
    }
    [[ "${PRIMEWAVE_BLOCKCHAIN_ID:-}" =~ ^[A-Za-z0-9]{52}$ ]] || {
        demo_error "Saved Blockchain ID is invalid."
        return 1
    }
    [[ "${PRIMEWAVE_SUBNET_ID:-}" =~ ^[A-Za-z0-9]{52}$ ]] || {
        demo_error "Saved Subnet ID is invalid."
        return 1
    }
}

export -f demo_error assert_runtime_layout read_demo_state
