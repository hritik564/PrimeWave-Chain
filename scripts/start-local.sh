#!/usr/bin/env bash
# PrimeWave Chain — Start Local Network
# ======================================
# ENVIRONMENT: LOCAL DEVELOPMENT ONLY
# NOT FOR TESTNET. NOT FOR MAINNET.
#
# What this script does:
#   1. Verifies binaries are installed (AvalancheGo, Avalanche CLI, subnet-evm)
#   2. On first run: deploys PrimeWave L1 via Avalanche CLI to populate P-Chain state
#      (Known limitation: CLI v1.9.5 fails at "setup VM binary" — expected and handled)
#   3. Configures the local cluster node for standalone operation with tracking
#   4. Starts avalanchego as a background daemon
#   5. Waits for node to become healthy (all chains + our L1)
#   6. Saves RPC endpoints to local-data/network-state.env
#   7. Prints connection information
#
# Usage: bash scripts/start-local.sh
# Stop:  bash scripts/stop-local.sh
#
# ARCHITECTURE NOTE (PW-C01):
#   Avalanche CLI v1.9.5 (maintenance mode, Dec 2025) predates AvalancheGo v1.14.2
#   (Mar 2026, rpcchainvm=45). The CLI's "setup VM binary" registry lookup is broken
#   for "subnet-evm" in this combination. The workaround:
#   - Run blockchain deploy to create ANR primary network + P-Chain records + local cluster
#   - CLI fails at "setup VM binary" (expected; this is after all P-Chain work is done)
#   - We then patch the local cluster node flags and start avalanchego directly
#   - The subnet-evm plugin binary (shipped in AvalancheGo v1.14.2 release) handles the EVM
#   See docs/PW-C01-LOCAL-DEVELOPMENT.md for full details.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

require_bins
require_jq
require_curl

# ── Network IDs ───────────────────────────────────────────────────────────────
# The VM ID is fixed (it is derived from the binary, not genesis).
# Subnet ID and Blockchain ID depend on genesis content and may change after reset+redeploy.
# If a saved state file exists, use those IDs; otherwise use the last-known defaults.
# After a fresh deploy these are overwritten from the deploy log output.
PRIMEWAVE_VM_ID="rXJjKFtAVSmpKwhMhw7ZMV6opKcsmhk5AuVxWNAzFG221wmM8"
PRIMEWAVE_HTTP_PORT="9656"

# Load persisted IDs if available (set on first deploy or after reset)
SAVED_BLOCKCHAIN_ID="yNRRcwqYaWqn9g4XcAiNe7DufgEHqpF2mmvcG6go1cRvtZo4S"   # fallback: PW-C02 IDs
SAVED_SUBNET_ID="2W9boARgCWL25z6pMFNtkCfNA5v28VGg9PmBgUJfuKndEdhrvw"
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
    log_section "Phase 1: Initial Deploy (Creating L1)"
    log_info "This is the first run. Deploying blockchain to create P-Chain state..."
    log_info "The Avalanche CLI will fail at 'setup VM binary' — this is EXPECTED."
    log_info "All P-Chain work (subnet, blockchain, L1 conversion) completes before that step."
    echo ""

    # Ensure sidecar config exists
    if [[ ! -f "$CLI_SUBNET_DIR/sidecar.json" ]]; then
        log_warn "Blockchain config not found. Running setup first..."
        bash "$(dirname "${BASH_SOURCE[0]}")/setup-local.sh"
    fi

    # Pre-place subnet-evm binary so the plugin directory is ready
    mkdir -p "$LOCAL_CLUSTER_DIR/plugins"
    cp "$SUBNET_EVM_BIN" "$LOCAL_CLUSTER_DIR/plugins/$PRIMEWAVE_VM_ID"

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
    DEPLOY_LOG="$LOCAL_DATA_DIR/deploy.log"
    mkdir -p "$LOCAL_DATA_DIR"

    set +e
    "$AVALANCHE_CLI_BIN" blockchain deploy "$PRIMEWAVE_CHAIN_NAME" \
        --local \
        --avalanchego-path "$AVALANCHEGO_BIN" \
        --num-nodes 3 \
        --ewoq \
        --skip-update-check \
        2>&1 | tee "$DEPLOY_LOG"
    DEPLOY_EXIT=${PIPESTATUS[0]}
    set -e

    kill $WATCHER_PID 2>/dev/null || true

    # Check for expected failure vs unexpected failure
    if [[ $DEPLOY_EXIT -ne 0 ]]; then
        if grep -q "setup VM binary" "$DEPLOY_LOG" 2>/dev/null; then
            log_warn "Deploy exited at 'setup VM binary' (expected for CLI v1.9.5 + AvalancheGo v1.14.2)."
            log_info "P-Chain state was created. Proceeding with manual node startup."
        else
            # Unexpected failure — check if it's the "already exists" interactive prompt failure
            if grep -q "already exists" "$DEPLOY_LOG" 2>/dev/null; then
                log_warn "Deploy encountered 'already exists' prompt. This may indicate stale state."
                log_warn "Try: bash scripts/reset-local.sh && bash scripts/start-local.sh"
                exit 1
            else
                log_error "Unexpected deploy failure (exit $DEPLOY_EXIT)."
                log_error "Check: $DEPLOY_LOG"
                exit 1
            fi
        fi
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
    NEW_BLOCKCHAIN_ID=$(grep -oP "(?<=Blockchain ID: )\S+" "$DEPLOY_LOG" 2>/dev/null | tail -1 || echo "")
    NEW_SUBNET_ID=$(grep -oP "(?<=Subnet ID: )\S+" "$DEPLOY_LOG" 2>/dev/null | tail -1 || echo "")

    # Also try URL-based extraction as fallback
    if [[ -z "$NEW_BLOCKCHAIN_ID" ]]; then
        NEW_BLOCKCHAIN_ID=$(grep -oP "(?<=/ext/bc/)[A-Za-z0-9]+" "$DEPLOY_LOG" 2>/dev/null | tail -1 || echo "")
    fi

    if [[ -n "$NEW_BLOCKCHAIN_ID" ]]; then
        PRIMEWAVE_BLOCKCHAIN_ID="$NEW_BLOCKCHAIN_ID"
        PRIMEWAVE_RPC_URL="http://127.0.0.1:${PRIMEWAVE_HTTP_PORT}/ext/bc/${PRIMEWAVE_BLOCKCHAIN_ID}/rpc"
        PRIMEWAVE_WS_URL="ws://127.0.0.1:${PRIMEWAVE_HTTP_PORT}/ext/bc/${PRIMEWAVE_BLOCKCHAIN_ID}/ws"
        log_ok "Discovered Blockchain ID: $PRIMEWAVE_BLOCKCHAIN_ID"
    else
        log_warn "Could not parse Blockchain ID from deploy log. Using saved/fallback ID."
        log_warn "Check $DEPLOY_LOG if RPC fails."
    fi

    if [[ -n "$NEW_SUBNET_ID" ]]; then
        PRIMEWAVE_SUBNET_ID="$NEW_SUBNET_ID"
        log_ok "Discovered Subnet ID: $PRIMEWAVE_SUBNET_ID"
    fi

    # Persist discovered IDs for future runs (survive restarts without re-deploying)
    mkdir -p "$LOCAL_DATA_DIR"
    cat > "$NETWORK_IDS_FILE" <<IDSEOF
## PrimeWave Chain — Persisted Network IDs
## Generated by start-local.sh on first deploy / after reset
## These IDs depend on genesis content — update after reset+redeploy with new genesis.
PRIMEWAVE_BLOCKCHAIN_ID_SAVED="$PRIMEWAVE_BLOCKCHAIN_ID"
PRIMEWAVE_SUBNET_ID_SAVED="$PRIMEWAVE_SUBNET_ID"
PRIMEWAVE_VM_ID_SAVED="$PRIMEWAVE_VM_ID"
IDSEOF
    log_ok "Network IDs persisted to: $NETWORK_IDS_FILE"
fi

# ── Phase 2: Configure node for standalone operation ──────────────────────────
log_section "Phase 2: Configuring Node"
log_info "Node directory: $NODE_DIR"

FLAGS_JSON="$NODE_DIR/flags.json"
if [[ ! -f "$FLAGS_JSON" ]]; then
    log_error "flags.json not found: $FLAGS_JSON"
    exit 1
fi

# Patch flags.json for standalone single-node development mode
python3 << PYEOF
import json, os, base64

SUBNET_ID   = "$PRIMEWAVE_SUBNET_ID"
BLOCKCHAIN_ID = "$PRIMEWAVE_BLOCKCHAIN_ID"
flags_path  = "$FLAGS_JSON"

with open(flags_path) as f:
    flags = json.load(f)

# Standalone single-node settings
flags["bootstrap-ids"]               = ""
flags["bootstrap-ips"]               = ""
flags["sybil-protection-enabled"]    = False   # No peer quorum needed for single-node dev
flags["partial-sync-primary-network"] = False   # Required when sybil-protection is disabled
flags["track-subnets"]               = SUBNET_ID

# Add our blockchain's EVM chain config (debug APIs)
our_chain_config = {
    "log-level": "debug",
    "eth-apis": [
        "eth", "eth-filter", "net", "admin", "web3",
        "internal-eth", "internal-blockchain", "internal-transaction",
        "internal-debug", "internal-account", "internal-personal",
        "debug", "debug-tracer", "debug-file-tracer", "debug-handler"
    ]
}
chain_cfg_b64 = flags.get("chain-config-content", "")
chain_cfg = json.loads(base64.b64decode(chain_cfg_b64).decode()) if chain_cfg_b64 else {}
chain_cfg[BLOCKCHAIN_ID] = {
    "Config": base64.b64encode(json.dumps(our_chain_config, indent=2).encode()).decode(),
    "Upgrade": None
}
flags["chain-config-content"] = base64.b64encode(json.dumps(chain_cfg).encode()).decode()

with open(flags_path, "w") as f:
    json.dump(flags, f, indent=2)
print(f"Flags updated: track-subnets={SUBNET_ID}")
print(f"  sybil-protection-enabled=False, partial-sync-primary-network=False")
PYEOF

# Ensure subnet-evm plugin binary is in plugins dir
mkdir -p "$LOCAL_CLUSTER_DIR/plugins"
cp "$SUBNET_EVM_BIN" "$LOCAL_CLUSTER_DIR/plugins/$PRIMEWAVE_VM_ID"
log_ok "subnet-evm plugin placed: $LOCAL_CLUSTER_DIR/plugins/$PRIMEWAVE_VM_ID"

# ── Phase 3: Start the node ───────────────────────────────────────────────────
log_section "Phase 3: Starting Node"

# Build startup command from flags.json
python3 << PYEOF2
import json, os

flags_path = "$FLAGS_JSON"
agbin      = "$AVALANCHEGO_BIN"
start_sh   = "/tmp/pw-node-start.sh"

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
NODE_LOG="$LOCAL_DATA_DIR/node.log"

log_info "Starting avalanchego (PID will be saved to $PID_FILE)..."
nohup bash /tmp/pw-node-start.sh > "$NODE_LOG" 2>&1 &
NODE_PID=$!
echo $NODE_PID > "$PID_FILE"
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
        log_error "Check logs: $NODE_LOG"
        tail -20 "$NODE_LOG" >&2
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

# ── Phase 5: Verify RPC and save state ────────────────────────────────────────
log_section "Phase 5: Verifying RPC"
ACTUAL_CHAIN_ID=$(curl -s \
    -X POST "$PRIMEWAVE_RPC_URL" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
    --max-time 5 2>/dev/null \
    | python3 -c "import sys,json; r=json.load(sys.stdin); print(int(r.get('result','0x0'),16))" 2>/dev/null || echo "unknown")

if [[ "$ACTUAL_CHAIN_ID" == "$PRIMEWAVE_DEV_CHAIN_ID" ]]; then
    log_ok "Chain ID verified: $ACTUAL_CHAIN_ID ✓"
else
    log_warn "Chain ID: expected $PRIMEWAVE_DEV_CHAIN_ID, got $ACTUAL_CHAIN_ID"
fi

# Save network state
NODE_ID=$(basename "$NODE_DIR")
cat > "$NETWORK_STATE_FILE" <<STATEEOF
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
PRIMEWAVE_CHAIN_ID="$PRIMEWAVE_DEV_CHAIN_ID"
NODE_COUNT="1"
LOCAL_HOST="127.0.0.1"
RPC_PORT="$PRIMEWAVE_HTTP_PORT"
BLOCKCHAIN_ID="$PRIMEWAVE_BLOCKCHAIN_ID"
NETWORK_STARTED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
STATEEOF

log_ok "Network state saved to: $NETWORK_STATE_FILE"

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
