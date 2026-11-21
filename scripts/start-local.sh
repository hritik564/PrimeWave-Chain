#!/usr/bin/env bash
# PrimeWave Chain — Start Local Network
# ======================================
# ENVIRONMENT: LOCAL DEVELOPMENT ONLY
# NOT FOR TESTNET. NOT FOR MAINNET.
#
# What this script does:
#   1. Verifies binaries are installed (AvalancheGo, Avalanche CLI, subnet-evm)
#   2. On first run: uses Avalanche CLI to create fresh local P-Chain/L1 state
#   3. Configures the local cluster node for standalone operation with tracking
#   4. Starts avalanchego as a background daemon
#   5. Waits for node to become healthy (all chains + our L1)
#   6. Saves RPC endpoints to local-data/network-state.env
#   7. Prints connection information
#
# Usage: bash scripts/start-local.sh
# Stop:  bash scripts/stop-local.sh
#
# The isolated demo uses a fresh CLI home mounted inside a user/mount namespace.
# Any nonzero deploy result is treated as a failed bootstrap and preserved for
# inspection; no "expected failure" is accepted as evidence of a complete L1.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

# Avalanche CLI v1.9.5 resolves subnet/VM state from the operating-system
# account home, even when HOME is overridden. Do not let an isolated launch
# silently write outside its requested runtime.
CLI_ACCOUNT_HOME=$(python3 -c 'import os, pwd; print(pwd.getpwuid(os.getuid()).pw_dir)')
if [[ "$(realpath -m "$HOME")" != "$(realpath -m "$CLI_ACCOUNT_HOME")" ]]; then
    log_error "Avalanche CLI resolves state under the OS account home; this HOME override is not isolated."
    log_error "Refusing to invoke Avalanche CLI or start a node."
    exit 1
fi

require_bins
require_jq
require_curl

# ── Network IDs ───────────────────────────────────────────────────────────────
# The VM ID is fixed (it is derived from the binary, not genesis).
# Subnet ID and Blockchain ID depend on genesis content and may change after reset+redeploy.
# If a saved state file exists, use only IDs recorded by this local runtime.
# Fresh networks must take their IDs from the current CLI deployment output.
PRIMEWAVE_VM_ID="rXJjKFtAVSmpKwhMhw7ZMV6opKcsmhk5AuVxWNAzFG221wmM8"
PRIMEWAVE_HTTP_PORT="${PRIMEWAVE_HTTP_PORT:-9656}"
PRIMEWAVE_P2P_PORT="${PRIMEWAVE_P2P_PORT:-}"

# Never fall back to identifiers from another local network.
SAVED_BLOCKCHAIN_ID=""
SAVED_SUBNET_ID=""
NETWORK_IDS_FILE="$LOCAL_DATA_DIR/network-ids.env"
if [[ -f "$NETWORK_IDS_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$NETWORK_IDS_FILE"
    SAVED_BLOCKCHAIN_ID="${PRIMEWAVE_BLOCKCHAIN_ID_SAVED:-$SAVED_BLOCKCHAIN_ID}"
    SAVED_SUBNET_ID="${PRIMEWAVE_SUBNET_ID_SAVED:-$SAVED_SUBNET_ID}"
fi

PRIMEWAVE_SUBNET_ID="$SAVED_SUBNET_ID"
PRIMEWAVE_BLOCKCHAIN_ID="$SAVED_BLOCKCHAIN_ID"
PRIMEWAVE_RPC_URL="http://127.0.0.1:${PRIMEWAVE_HTTP_PORT}/ext/bc/${PRIMEWAVE_BLOCKCHAIN_ID}/rpc"
PRIMEWAVE_WS_URL="ws://127.0.0.1:${PRIMEWAVE_HTTP_PORT}/ext/bc/${PRIMEWAVE_BLOCKCHAIN_ID}/ws"

SUBNET_EVM_BIN="$LOCAL_BIN_DIR/subnet-evm"
CLI_SUBNET_DIR="$HOME/.avalanche-cli/subnets/$PRIMEWAVE_CHAIN_NAME"
LOCAL_CLUSTER_DIR="$HOME/.avalanche-cli/local/primewavedev-local-node-local-network"
PID_FILE="$LOCAL_DATA_DIR/node.pid"
DEPLOY_LOG_PENDING=""

verify_local_rpc_identity() {
    local actual_chain_id
    actual_chain_id=$(curl -fsS \
        -X POST "$PRIMEWAVE_RPC_URL" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
        --max-time 5 2>/dev/null \
        | python3 -c "import sys,json; r=json.load(sys.stdin); v=r.get('result'); print(int(v,16) if isinstance(v,str) else 'unknown')" \
        2>/dev/null) || actual_chain_id="unknown"

    if [[ "$actual_chain_id" != "$PRIMEWAVE_DEV_CHAIN_ID" ]]; then
        log_error "Local RPC identity mismatch: expected Chain ID $PRIMEWAVE_DEV_CHAIN_ID; refusing to save local metadata."
        return 1
    fi
    ACTUAL_CHAIN_ID="$actual_chain_id"
}

log_section "PrimeWave Chain — Starting Local Network"
echo -e "  ${YELLOW}DEVELOPMENT ONLY — Chain ID $PRIMEWAVE_DEV_CHAIN_ID${NC}"
echo ""

# ── Check if already running ──────────────────────────────────────────────────
if [[ -f "$PID_FILE" ]]; then
    SAVED_PID=$(cat "$PID_FILE" 2>/dev/null || echo "")
    if [[ -n "$SAVED_PID" ]] && kill -0 "$SAVED_PID" 2>/dev/null; then
        RPC_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
            -X POST "$PRIMEWAVE_RPC_URL" \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
            --max-time 3 2>/dev/null || echo "000")
        if [[ "$RPC_STATUS" == "200" ]]; then
            if ! verify_local_rpc_identity; then
                exit 1
            fi
            log_ok "Network is already running (PID $SAVED_PID)."
            echo -e "  RPC URL: ${CYAN}$PRIMEWAVE_RPC_URL${NC}"
            echo -e "  WS URL:  ${CYAN}$PRIMEWAVE_WS_URL${NC}"
            echo ""
            echo -e "  Run ${BOLD}bash scripts/status-local.sh${NC} for details."
            exit 0
        fi
    fi
fi

# ── Verify prerequisites ──────────────────────────────────────────────────────
if [[ ! -x "$SUBNET_EVM_BIN" ]]; then
    log_error "subnet-evm binary not found at $SUBNET_EVM_BIN"
    log_error "Run: bash scripts/setup-local.sh"
    exit 1
fi

# ── Phase 1: First-time deploy (creates P-Chain state and local cluster DB) ───
NODE_DIR=$(ls -d "$LOCAL_CLUSTER_DIR"/NodeID-* 2>/dev/null | head -1 || echo "")
if [[ -z "$NODE_DIR" ]]; then
    if [[ -d "$LOCAL_CLUSTER_DIR" ]] && \
       [[ -n "$(find "$LOCAL_CLUSTER_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
        log_error "Local cluster directory contains partial or unrecognized state but no NodeID directory."
        log_error "Refusing to create a new network identity over existing data. Inspect the directory before proceeding."
        exit 1
    fi

    log_section "Phase 1: Initial Deploy (Creating L1)"
    log_info "This is the first run. Deploying blockchain to create P-Chain state..."
    log_info "The CLI must complete all local P-Chain and L1 registration steps."
    echo ""

    # Ensure sidecar config exists
    if [[ ! -f "$CLI_SUBNET_DIR/sidecar.json" ]]; then
        log_warn "Blockchain config not found. Running setup first..."
        bash "$(dirname "${BASH_SOURCE[0]}")/setup-local.sh"
    fi

    # Pre-place subnet-evm binary so the plugin directory is ready
    mkdir -p "$LOCAL_CLUSTER_DIR/plugins"
    if [[ ! -e "$LOCAL_CLUSTER_DIR/plugins/$PRIMEWAVE_VM_ID" ]]; then
        cp "$SUBNET_EVM_BIN" "$LOCAL_CLUSTER_DIR/plugins/$PRIMEWAVE_VM_ID"
    fi

    # Background watcher: re-place plugin as soon as any plugins dir appears
    VMID="$PRIMEWAVE_VM_ID"
    (
        while true; do
            if [[ -d "$LOCAL_CLUSTER_DIR/plugins" ]] && \
               [[ ! -f "$LOCAL_CLUSTER_DIR/plugins/$VMID" ]]; then
                cp "$SUBNET_EVM_BIN" "$LOCAL_CLUSTER_DIR/plugins/$VMID"
            fi
            sleep 0.1
        done
    ) &
    WATCHER_PID=$!

    # Run deploy — expected to fail at "setup VM binary" after creating P-Chain state
    mkdir -p "$LOCAL_DATA_DIR"
    DEPLOY_LOG_PENDING=$(mktemp "$LOCAL_DATA_DIR/.deploy.log.pending.XXXXXX")
    DEPLOY_LOG="$DEPLOY_LOG_PENDING"

    set +e
    "$AVALANCHE_CLI_BIN" blockchain deploy "$PRIMEWAVE_CHAIN_NAME" \
        --local \
        --avalanchego-path "$AVALANCHEGO_BIN" \
        --num-nodes 1 \
        --ewoq \
        --skip-update-check \
        2>&1 | tee "$DEPLOY_LOG"
    DEPLOY_EXIT=${PIPESTATUS[0]}
    set -e

    kill $WATCHER_PID 2>/dev/null || true

    # Fail closed on every nonzero deployment result. A partial P-Chain
    # transaction sequence is not an initialized EVM blockchain.
    if [[ $DEPLOY_EXIT -ne 0 ]]; then
        log_error "Local P-Chain/L1 deployment failed (exit $DEPLOY_EXIT)."
        log_error "Partial runtime data is preserved; no retry or reset was attempted."
        log_error "Inspect: $DEPLOY_LOG"
        exit 1
    fi

    NODE_DIR=$(ls -d "$LOCAL_CLUSTER_DIR"/NodeID-* 2>/dev/null | head -1 || echo "")
    if [[ -z "$NODE_DIR" ]]; then
        log_error "Local cluster node directory not found after deploy."
        log_error "The deploy may have failed before creating the local cluster."
        log_error "Check: $DEPLOY_LOG"
        exit 1
    fi
    log_ok "Local cluster created: $NODE_DIR"

    # ── Parse and persist new IDs from the deploy log ──────────────────────────
    # The CLI prints "RPC URL: http://.../<blockchain_id>/rpc" in the deploy log.
    # Extract Blockchain ID and Subnet ID from the output.
    # Newer Avalanche CLI versions render deployment IDs in a table:
    #   | Blockchain ID | <id> |
    #   | Subnet ID     | <id> |
    # Parse that format first, then retain the text/URL fallbacks below for
    # older CLI output.
    NEW_BLOCKCHAIN_ID=$(awk -F'|' '$2 ~ /Blockchain ID/ {gsub(/[[:space:]]/, "", $3); if ($3 != "") print $3}' "$DEPLOY_LOG" 2>/dev/null | tail -1 || echo "")
    NEW_SUBNET_ID=$(awk -F'|' '$2 ~ /Subnet ID/ {gsub(/[[:space:]]/, "", $3); if ($3 != "") print $3}' "$DEPLOY_LOG" 2>/dev/null | tail -1 || echo "")

    if [[ -z "$NEW_BLOCKCHAIN_ID" ]]; then
        NEW_BLOCKCHAIN_ID=$(grep -oP "(?<=Blockchain ID: )\S+" "$DEPLOY_LOG" 2>/dev/null | tail -1 || echo "")
    fi
    if [[ -z "$NEW_SUBNET_ID" ]]; then
        NEW_SUBNET_ID=$(grep -oP "(?<=Subnet ID: )\S+" "$DEPLOY_LOG" 2>/dev/null | tail -1 || echo "")
    fi

    if [[ -n "$NEW_BLOCKCHAIN_ID" ]]; then
        PRIMEWAVE_BLOCKCHAIN_ID="$NEW_BLOCKCHAIN_ID"
        log_ok "Discovered Blockchain ID: $PRIMEWAVE_BLOCKCHAIN_ID"
    else
        log_error "Could not parse a fresh Blockchain ID from the deploy log."
        log_error "Refusing to use a saved or historical identifier."
        exit 1
    fi

    if [[ -n "$NEW_SUBNET_ID" ]]; then
        PRIMEWAVE_SUBNET_ID="$NEW_SUBNET_ID"
        log_ok "Discovered Subnet ID: $PRIMEWAVE_SUBNET_ID"
    else
        log_error "Could not parse a fresh Subnet ID from the deploy log."
        log_error "Refusing to use a saved or historical identifier."
        exit 1
    fi

fi

if [[ -z "$PRIMEWAVE_BLOCKCHAIN_ID" || -z "$PRIMEWAVE_SUBNET_ID" ]]; then
    log_error "This isolated runtime has no verified network IDs; refusing startup."
    exit 1
fi

# ── Phase 2: Configure node for standalone operation ──────────────────────────
log_section "Phase 2: Configuring Node"
log_info "Node directory: $NODE_DIR"

FLAGS_JSON="$NODE_DIR/flags.json"
if [[ ! -f "$FLAGS_JSON" ]]; then
    log_error "flags.json not found: $FLAGS_JSON"
    exit 1
fi

# Read the ports actually selected by Avalanche CLI for this local network.
read -r PRIMEWAVE_HTTP_PORT PRIMEWAVE_P2P_PORT < <(
    python3 - "$FLAGS_JSON" <<'PYPORTS'
import json, sys
with open(sys.argv[1], encoding="utf-8") as source:
    flags = json.load(source)
http = int(flags.get("http-port", 0))
p2p = int(flags.get("staking-port", 0))
if not (1 <= http <= 65535 and 1 <= p2p <= 65535):
    raise SystemExit("invalid HTTP or staking port in Avalanche CLI flags")
print(http, p2p)
PYPORTS
)
PRIMEWAVE_RPC_URL="http://127.0.0.1:${PRIMEWAVE_HTTP_PORT}/ext/bc/${PRIMEWAVE_BLOCKCHAIN_ID}/rpc"
PRIMEWAVE_WS_URL="ws://127.0.0.1:${PRIMEWAVE_HTTP_PORT}/ext/bc/${PRIMEWAVE_BLOCKCHAIN_ID}/ws"
log_info "Discovered local ports from flags.json: HTTP $PRIMEWAVE_HTTP_PORT, P2P $PRIMEWAVE_P2P_PORT"

FLAGS_JSON_PENDING=$(mktemp "$NODE_DIR/.flags.json.pending.XXXXXX")
cp "$FLAGS_JSON" "$FLAGS_JSON_PENDING"

# Patch flags.json for standalone single-node development mode
python3 << PYEOF
import json, os, base64

SUBNET_ID   = "$PRIMEWAVE_SUBNET_ID"
BLOCKCHAIN_ID = "$PRIMEWAVE_BLOCKCHAIN_ID"
flags_path  = "$FLAGS_JSON_PENDING"
runtime_root = os.environ.get("PRIMEWAVE_ISOLATION_ROOT", "")

with open(flags_path) as f:
    flags = json.load(f)

# Standalone single-node settings
flags["bootstrap-ids"]               = ""
flags["bootstrap-ips"]               = ""
flags["sybil-protection-enabled"]    = False   # No peer quorum needed for single-node dev
flags["partial-sync-primary-network"] = False   # Required when sybil-protection is disabled
flags["track-subnets"]               = SUBNET_ID

# Enable the local Ethereum RPC services, including eth block/balance methods.
our_chain_config = {
    "log-level": "debug",
    "eth-apis": ["eth", "eth-filter", "internal-blockchain", "net", "web3"]
}
flags["http-host"] = "127.0.0.1"
flags["staking-host"] = "127.0.0.1"
flags["public-ip"] = "127.0.0.1"

# In the isolated demo, reject any node data, key, plugin, config, or log path
# that resolves outside the runtime or the sandboxed CLI-home mount aliases.
if runtime_root:
    allowed_roots = [
        os.path.realpath(runtime_root),
        os.path.realpath("/root"),
        os.path.realpath("/home/runner/.avalanche-cli"),
        os.path.realpath("/tmp"),
    ]
    path_flags = {
        "data-dir", "db-dir", "log-dir", "plugin-dir", "chain-config-dir",
        "staking-tls-cert-file", "staking-tls-key-file",
        "staking-signer-key-file", "genesis-file", "config-file",
    }
    for key in ("staking-tls-key-file-content", "staking-signer-key-file-content"):
        if flags.get(key):
            raise SystemExit(f"refusing to expose key material through node argument {key}")
    for key in path_flags:
        value = flags.get(key)
        if not value:
            continue
        if not isinstance(value, str) or not os.path.isabs(value):
            raise SystemExit(f"isolated node path is not absolute: {key}")
        resolved = os.path.realpath(value)
        if not any(
            os.path.commonpath((resolved, allowed)) == allowed
            for allowed in allowed_roots
        ):
            raise SystemExit(f"isolated node path escapes runtime: {key}")

chain_cfg_b64 = flags.get("chain-config-content", "")
chain_cfg = json.loads(base64.b64decode(chain_cfg_b64).decode()) if chain_cfg_b64 else {}
chain_cfg[BLOCKCHAIN_ID] = {
    "Config": base64.b64encode(json.dumps(our_chain_config, indent=2).encode()).decode(),
    "Upgrade": None
}
flags["chain-config-content"] = base64.b64encode(json.dumps(chain_cfg).encode()).decode()

with open(flags_path, "w") as f:
    json.dump(flags, f, indent=2)
os.chmod(flags_path, 0o600)
print(f"Flags updated: track-subnets={SUBNET_ID}")
print(f"  sybil-protection-enabled=False, partial-sync-primary-network=False")
print("  http-host, staking-host, and public-ip bound to 127.0.0.1")
PYEOF

# Ensure subnet-evm plugin binary is in plugins dir
mkdir -p "$LOCAL_CLUSTER_DIR/plugins"
if [[ ! -e "$LOCAL_CLUSTER_DIR/plugins/$PRIMEWAVE_VM_ID" ]]; then
    cp "$SUBNET_EVM_BIN" "$LOCAL_CLUSTER_DIR/plugins/$PRIMEWAVE_VM_ID"
fi
log_ok "subnet-evm plugin placed: $LOCAL_CLUSTER_DIR/plugins/$PRIMEWAVE_VM_ID"

# ── Phase 3: Start the node ───────────────────────────────────────────────────
log_section "Phase 3: Starting Node"

# Kill any stale avalanchego that already holds port $PRIMEWAVE_HTTP_PORT.
# The Avalanche CLI's 'blockchain deploy' now starts the local-cluster node before
# failing at "setup VM binary". That node runs with pre-Phase-2 flags (no subnet
# tracking, missing chain configs). We must kill it so Phase 3 can start with the
# correctly-patched flags.json produced by Phase 2.
STALE_PID=$(ps aux 2>/dev/null | grep -v grep | \
    while IFS= read -r line; do
        pid=$(echo "$line" | awk '{print $2}')
        cmdline=$(cat /proc/$pid/cmdline 2>/dev/null | tr '\0' ' ' || echo "")
        if echo "$cmdline" | grep -qF "$LOCAL_CLUSTER_DIR"; then
            echo "$pid"
        fi
    done | head -1 || true)

if [[ -n "$STALE_PID" ]]; then
    log_warn "Found stale avalanchego (PID $STALE_PID) using $LOCAL_CLUSTER_DIR."
    log_info "Stopping it so we can start with patched flags (Phase 2)..."
    kill "$STALE_PID" 2>/dev/null || true
    # Wait for port to release (max 5s)
    for _i in 1 2 3 4 5; do
        if ! kill -0 "$STALE_PID" 2>/dev/null; then break; fi
        sleep 1
    done
    log_ok "Stale node stopped."
fi

# Refuse to start or resume an isolated demo whose fresh identifiers collide
# with any documented or saved project blockchain/subnet identifier.
if [[ -n "${PRIMEWAVE_ISOLATION_ROOT:-}" ]]; then
    python3 "$REPO_ROOT/scripts/pw-demo-02/check-identifiers.py" \
        "$PRIMEWAVE_SUBNET_ID" "$PRIMEWAVE_BLOCKCHAIN_ID"
fi

# Build startup command from the pending standalone flags; the existing
# Avalanche CLI flags.json is replaced only after local RPC identity succeeds.
python3 << PYEOF2
import json, os

flags_path = "$FLAGS_JSON_PENDING"
agbin      = "$AVALANCHEGO_BIN"
start_sh   = os.path.join("$LOCAL_DATA_DIR", "node-start.sh")

with open(flags_path) as f:
    flags = json.load(f)

cmd = [agbin] + [f"--{k}={v}" for k, v in flags.items()]
with open(start_sh, "w") as f:
    f.write("#!/bin/bash\n")
    f.write("exec " + " \\\n  ".join(repr(c) for c in cmd) + "\n")
os.chmod(start_sh, 0o755)
print(f"Startup script: {start_sh}")
PYEOF2

mkdir -p "$LOCAL_DATA_DIR"
NODE_LOG_PENDING=$(mktemp "$LOCAL_DATA_DIR/.node.log.pending.XXXXXX")
NODE_PID_PENDING=$(mktemp "$LOCAL_DATA_DIR/.node.pid.pending.XXXXXX")

log_info "Starting avalanchego; its PID and log remain pending until identity is verified..."
nohup bash "$LOCAL_DATA_DIR/node-start.sh" > "$NODE_LOG_PENDING" 2>&1 &
NODE_PID=$!
echo "$NODE_PID" > "$NODE_PID_PENDING"
log_ok "Node started (PID $NODE_PID)"

# ── Phase 4: Wait for health ──────────────────────────────────────────────────
log_section "Phase 4: Waiting for Network Health"
log_info "Health endpoint: http://127.0.0.1:${PRIMEWAVE_HTTP_PORT}/ext/health"
HEALTH_URL="http://127.0.0.1:${PRIMEWAVE_HTTP_PORT}/ext/health"

MAX_WAIT=60
WAITED=0
while true; do
    if ! kill -0 $NODE_PID 2>/dev/null; then
        log_error "Node process died (PID $NODE_PID)."
        log_error "Pending node log: $NODE_LOG_PENDING"
        tail -20 "$NODE_LOG_PENDING" >&2
        exit 1
    fi

    HEALTH=$(curl -sf --max-time 2 "$HEALTH_URL" 2>/dev/null || echo "{}")
    if echo "$HEALTH" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if d.get('healthy') else 1)" 2>/dev/null; then
        log_ok "Node healthy!"
        break
    fi

    if [[ $WAITED -ge $MAX_WAIT ]]; then
        log_warn "Node not fully healthy after ${MAX_WAIT}s. May still be starting."
        log_warn "Check: curl http://127.0.0.1:${PRIMEWAVE_HTTP_PORT}/ext/health"
        break
    fi

    echo -n "."
    sleep 1
    WAITED=$((WAITED+1))
done
echo ""

# ── Phase 5: Verify RPC identity before replacing any persisted metadata ───────
log_section "Phase 5: Verifying RPC"
if ! verify_local_rpc_identity; then
    log_error "Stopping only the node started by this attempt; existing persisted metadata is unchanged."
    kill "$NODE_PID" 2>/dev/null || true
    exit 1
fi
log_ok "Chain ID verified: $ACTUAL_CHAIN_ID ✓"

# Persist the verified standalone flags and all local state through same-folder
# temporary files so existing metadata remains intact until this point.
mv -f "$FLAGS_JSON_PENDING" "$FLAGS_JSON"
if [[ -n "$DEPLOY_LOG_PENDING" ]]; then
    mv -f "$DEPLOY_LOG_PENDING" "$LOCAL_DATA_DIR/deploy.log"
fi
mv -f "$NODE_LOG_PENDING" "$LOCAL_DATA_DIR/node.log"
mv -f "$NODE_PID_PENDING" "$PID_FILE"

NETWORK_IDS_PENDING=$(mktemp "$LOCAL_DATA_DIR/.network-ids.env.pending.XXXXXX")
cat > "$NETWORK_IDS_PENDING" <<IDSEOF
## PrimeWave Chain — Persisted Network IDs
## Written only after local Chain ID $PRIMEWAVE_DEV_CHAIN_ID is verified.
PRIMEWAVE_BLOCKCHAIN_ID_SAVED="$PRIMEWAVE_BLOCKCHAIN_ID"
PRIMEWAVE_SUBNET_ID_SAVED="$PRIMEWAVE_SUBNET_ID"
PRIMEWAVE_VM_ID_SAVED="$PRIMEWAVE_VM_ID"
IDSEOF
mv -f "$NETWORK_IDS_PENDING" "$NETWORK_IDS_FILE"
log_ok "Verified network IDs persisted to: $NETWORK_IDS_FILE"

# Save network state
NODE_ID=$(basename "$NODE_DIR")
NETWORK_STATE_PENDING=$(mktemp "$LOCAL_DATA_DIR/.network-state.env.pending.XXXXXX")
cat > "$NETWORK_STATE_PENDING" <<STATEEOF
## PrimeWave Chain — Local Network State
## Generated by start-local.sh at $(date -u +%Y-%m-%dT%H:%M:%SZ)
## DEVELOPMENT ONLY

PRIMEWAVE_CHAIN_NAME="$PRIMEWAVE_CHAIN_NAME"
PRIMEWAVE_DEV_CHAIN_ID="$PRIMEWAVE_DEV_CHAIN_ID"
PRIMEWAVE_SUBNET_ID="$PRIMEWAVE_SUBNET_ID"
PRIMEWAVE_BLOCKCHAIN_ID="$PRIMEWAVE_BLOCKCHAIN_ID"
PRIMEWAVE_VM_ID="$PRIMEWAVE_VM_ID"
PRIMEWAVE_NODE_ID="$NODE_ID"
PRIMEWAVE_RPC_URL="$PRIMEWAVE_RPC_URL"
PRIMEWAVE_WS_URL="$PRIMEWAVE_WS_URL"
PRIMEWAVE_HTTP_PORT="$PRIMEWAVE_HTTP_PORT"
PRIMEWAVE_P2P_PORT="$PRIMEWAVE_P2P_PORT"
PRIMEWAVE_CHAIN_ID="$PRIMEWAVE_DEV_CHAIN_ID"
NODE_COUNT="1"
LOCAL_HOST="127.0.0.1"
RPC_PORT="$PRIMEWAVE_HTTP_PORT"
BLOCKCHAIN_ID="$PRIMEWAVE_BLOCKCHAIN_ID"
NETWORK_STARTED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
STATEEOF
mv -f "$NETWORK_STATE_PENDING" "$NETWORK_STATE_FILE"

log_ok "Network state saved to: $NETWORK_STATE_FILE"

# Setup completion metadata is also committed only after successful identity
# verification, preserving any previous record on startup failure.
SETUP_STATE_PENDING=$(mktemp "$LOCAL_DATA_DIR/.setup-complete.env.pending.XXXXXX")
cat > "$SETUP_STATE_PENDING" <<EOF
SETUP_TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
AVALANCHEGO_VERSION_INSTALLED="$("$AVALANCHEGO_BIN" --version 2>&1 | head -1 | tr -d '\n')"
AVALANCHE_CLI_VERSION_INSTALLED="$("$AVALANCHE_CLI_BIN" --version 2>&1 | head -1 | tr -d '\n')"
PLATFORM="$(uname -s | tr '[:upper:]' '[:lower:]')/$(uname -m)"
CHAIN_NAME="$PRIMEWAVE_CHAIN_NAME"
CHAIN_ID="$PRIMEWAVE_DEV_CHAIN_ID"
EOF
mv -f "$SETUP_STATE_PENDING" "$LOCAL_DATA_DIR/setup-complete.env"
NODE_LOG="$LOCAL_DATA_DIR/node.log"

# ── Done ──────────────────────────────────────────────────────────────────────
log_section "Network Running"
echo ""
echo -e "  ${BOLD}Chain Name:${NC}     $PRIMEWAVE_CHAIN_NAME"
echo -e "  ${BOLD}Chain ID:${NC}       $PRIMEWAVE_DEV_CHAIN_ID  ${YELLOW}(DEV ONLY)${NC}"
echo -e "  ${BOLD}Blockchain ID:${NC}  $PRIMEWAVE_BLOCKCHAIN_ID"
echo -e "  ${BOLD}Subnet ID:${NC}      $PRIMEWAVE_SUBNET_ID"
echo -e "  ${BOLD}Node PID:${NC}       $NODE_PID  (saved to $PID_FILE)"
echo -e "  ${BOLD}Node Log:${NC}       $NODE_LOG"
echo -e "  ${BOLD}RPC URL:${NC}        ${CYAN}$PRIMEWAVE_RPC_URL${NC}"
echo -e "  ${BOLD}WebSocket:${NC}      ${CYAN}$PRIMEWAVE_WS_URL${NC}"
echo ""
echo -e "  ${BOLD}MetaMask Config:${NC}"
echo -e "    Network Name:      PrimeWave Dev"
echo -e "    RPC URL:           $PRIMEWAVE_RPC_URL"
echo -e "    Chain ID:          $PRIMEWAVE_DEV_CHAIN_ID"
echo -e "    Currency Symbol:   PW"
echo ""
echo -e "  ${BOLD}Dev Keys:${NC}        See config/dev/dev-keys.md"
echo -e "  ${BOLD}Run tests:${NC}       bash scripts/test-local.sh"
echo -e "  ${BOLD}Stop network:${NC}    bash scripts/stop-local.sh"
echo ""
echo -e "  ${YELLOW}⚠ REMINDER: LOCAL DEVELOPMENT ONLY — Chain ID $PRIMEWAVE_DEV_CHAIN_ID${NC}"
echo ""
