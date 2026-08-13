#!/usr/bin/env bash
# PrimeWave Chain — Local Network Status
# ========================================
# ENVIRONMENT: LOCAL DEVELOPMENT ONLY
#
# Shows:
#   - Binary installation status
#   - Network running status
#   - Node health (via Avalanche healthcheck API)
#   - Latest block number
#   - Chain ID verification
#   - Account balances for dev accounts
#
# Usage: bash scripts/status-local.sh

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

require_jq
require_curl

log_section "PrimeWave Chain — Local Network Status"
echo -e "  ${YELLOW}DEVELOPMENT ONLY — Chain ID $PRIMEWAVE_DEV_CHAIN_ID${NC}"
echo ""

# ── Binary status ─────────────────────────────────────────────────────────────
log_section "Binaries"
if [[ -x "$AVALANCHEGO_BIN" ]]; then
    AGOVER_RAW="$("$AVALANCHEGO_BIN" --version 2>&1 | head -1)"
    # Format: "avalanchego/1.14.2 [database=v1.4.5, ...]" — extract main version
    AGOVER_NUM="$(echo "$AGOVER_RAW" | grep -oP 'avalanchego/\K[\d]+\.[\d]+\.[\d]+' || echo unknown)"
    echo -e "  ${GREEN}✓${NC} AvalancheGo: v$AGOVER_NUM  ($AGOVER_RAW)"
    if [[ "v$AGOVER_NUM" != "$AVALANCHEGO_VERSION" ]]; then
        echo -e "  ${YELLOW}!${NC} Expected: $AVALANCHEGO_VERSION (pinned)"
    fi
else
    echo -e "  ${RED}✗${NC} AvalancheGo: NOT INSTALLED"
    echo -e "     Run: bash scripts/setup-local.sh"
fi

if [[ -x "$AVALANCHE_CLI_BIN" ]]; then
    CLIVER="$("$AVALANCHE_CLI_BIN" --version 2>&1 | head -1)"
    echo -e "  ${GREEN}✓${NC} Avalanche CLI: $CLIVER"
else
    echo -e "  ${RED}✗${NC} Avalanche CLI: NOT INSTALLED"
    echo -e "     Run: bash scripts/setup-local.sh"
fi
echo ""

# ── Network state file ────────────────────────────────────────────────────────
if [[ ! -f "$NETWORK_STATE_FILE" ]]; then
    echo -e "  ${YELLOW}!${NC} No network state file found."
    echo -e "     Network may not have been started yet."
    echo -e "     Run: bash scripts/start-local.sh"
    echo ""
    exit 0
fi

log_section "Network Configuration"
echo -e "  Chain Name:    $PRIMEWAVE_CHAIN_NAME"
echo -e "  Chain ID:      $PRIMEWAVE_DEV_CHAIN_ID  ${YELLOW}(DEV ONLY)${NC}"
echo -e "  Blockchain ID: ${BLOCKCHAIN_ID:-UNKNOWN}"
echo -e "  RPC URL:       ${PRIMEWAVE_RPC_URL:-UNKNOWN}"
echo -e "  WebSocket:     ${PRIMEWAVE_WS_URL:-UNKNOWN}"
echo -e "  Nodes:         $NODE_COUNT"
echo ""

RPC_URL="${PRIMEWAVE_RPC_URL:-}"
if [[ -z "$RPC_URL" ]]; then
    echo -e "  ${RED}✗${NC} RPC URL not set in state file."
    exit 1
fi

# ── RPC health check ──────────────────────────────────────────────────────────
log_section "RPC Health"

rpc_call() {
    local method="$1"
    local params="${2:-[]}"
    curl -s \
        -X POST "$RPC_URL" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}" \
        --max-time 5 2>/dev/null || echo "{}"
}

# Chain ID
CHAIN_ID_HEX=$(rpc_call "eth_chainId" | jq -r '.result // "null"')
if [[ "$CHAIN_ID_HEX" == "null" || -z "$CHAIN_ID_HEX" ]]; then
    echo -e "  ${RED}✗${NC} RPC not responding at: $RPC_URL"
    echo -e "     Network may not be running. Start with: bash scripts/start-local.sh"
    exit 1
fi

CHAIN_ID_DEC=$(printf "%d" "$CHAIN_ID_HEX" 2>/dev/null || echo "parse error")
if [[ "$CHAIN_ID_DEC" == "$PRIMEWAVE_DEV_CHAIN_ID" ]]; then
    echo -e "  ${GREEN}✓${NC} Chain ID: $CHAIN_ID_DEC (expected $PRIMEWAVE_DEV_CHAIN_ID)"
else
    echo -e "  ${RED}✗${NC} Chain ID mismatch: got $CHAIN_ID_DEC, expected $PRIMEWAVE_DEV_CHAIN_ID"
fi

# Block number
BLOCK_HEX=$(rpc_call "eth_blockNumber" | jq -r '.result // "0x0"')
BLOCK_NUM=$(printf "%d" "$BLOCK_HEX" 2>/dev/null || echo "parse error")
echo -e "  ${GREEN}✓${NC} Latest block: #$BLOCK_NUM"

# Gas price
GAS_HEX=$(rpc_call "eth_gasPrice" | jq -r '.result // "0x0"')
GAS_GWEI=$(echo "scale=2; $(printf "%d" "$GAS_HEX" 2>/dev/null || echo 0) / 1000000000" | bc 2>/dev/null || echo "N/A")
echo -e "  ${GREEN}✓${NC} Gas price: ${GAS_GWEI} gwei (PW)"

# net_version
NET_VER=$(rpc_call "net_version" | jq -r '.result // "null"')
echo -e "  ${GREEN}✓${NC} net_version: $NET_VER"

# web3_clientVersion
CLIENT_VER=$(rpc_call "web3_clientVersion" | jq -r '.result // "null"' | cut -c1-80)
echo -e "  ${GREEN}✓${NC} Client: $CLIENT_VER"
echo ""

# ── Dev account balances ──────────────────────────────────────────────────────
log_section "Dev Account Balances (PW)"

DEV_ACCOUNTS=(
    "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266:DEV_ACCOUNT_0"
    "0x70997970C51812dc3A010C7d01b50e0d17dc79C8:DEV_ACCOUNT_1"
    "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC:DEV_ACCOUNT_2"
)

for entry in "${DEV_ACCOUNTS[@]}"; do
    ADDR="${entry%%:*}"
    LABEL="${entry##*:}"
    BAL_HEX=$(rpc_call "eth_getBalance" "[\"$ADDR\",\"latest\"]" | jq -r '.result // "0x0"')
    BAL_WEI=$(printf "%d" "$BAL_HEX" 2>/dev/null || echo "0")
    # Convert wei to PW (divide by 10^18, show up to 4 decimal places)
    BAL_PW=$(echo "scale=4; $BAL_WEI / 1000000000000000000" | bc 2>/dev/null || echo "N/A")
    echo -e "  $LABEL  $ADDR  ${CYAN}$BAL_PW PW${NC}"
done
echo ""

# ── Node status (Avalanche health API) ───────────────────────────────────────
log_section "Avalanche Node Health"
HEALTH_URL="http://$LOCAL_HOST:$RPC_PORT/ext/health"
HEALTH_RESP=$(curl -s "$HEALTH_URL" --max-time 5 2>/dev/null || echo "{}")
HEALTH_STATUS=$(echo "$HEALTH_RESP" | jq -r '.healthy // "unknown"' 2>/dev/null || echo "unknown")
if [[ "$HEALTH_STATUS" == "true" ]]; then
    echo -e "  ${GREEN}✓${NC} Node 1 ($LOCAL_HOST:$RPC_PORT) healthy"
else
    echo -e "  ${YELLOW}?${NC} Node 1 ($LOCAL_HOST:$RPC_PORT) health: $HEALTH_STATUS"
fi

# Network runner manages additional nodes on different ports
for i in 1 2; do
    ALT_PORT=$((RPC_PORT + i * 2))
    ALT_HEALTH=$(curl -s "http://$LOCAL_HOST:$ALT_PORT/ext/health" --max-time 2 2>/dev/null | \
        jq -r '.healthy // "unreachable"' 2>/dev/null || echo "unreachable")
    if [[ "$ALT_HEALTH" == "true" ]]; then
        echo -e "  ${GREEN}✓${NC} Node $((i+1)) ($LOCAL_HOST:$ALT_PORT) healthy"
    else
        echo -e "  ${YELLOW}?${NC} Node $((i+1)) ($LOCAL_HOST:$ALT_PORT) status: $ALT_HEALTH"
        echo -e "     (Node ports are allocated by ANR; run 'avalanche network status' for details)"
    fi
done
echo ""

# ── CLI network status ────────────────────────────────────────────────────────
log_section "Avalanche CLI Network Status"
if [[ -x "$AVALANCHE_CLI_BIN" ]]; then
    "$AVALANCHE_CLI_BIN" network status 2>/dev/null || \
        log_warn "CLI network status unavailable (network may not have been started via CLI)"
fi
echo ""

log_section "Summary"
echo -e "  ${GREEN}✓${NC} Local PrimeWave Chain is running"
echo -e "  RPC URL:    ${CYAN}$RPC_URL${NC}"
echo -e "  Chain ID:   $PRIMEWAVE_DEV_CHAIN_ID ${YELLOW}(DEV ONLY)${NC}"
echo -e "  Latest block: #$BLOCK_NUM"
echo ""
echo -e "  Run tests:   bash scripts/test-local.sh"
echo -e "  Stop:        bash scripts/stop-local.sh"
echo ""
