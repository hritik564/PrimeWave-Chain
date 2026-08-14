#!/usr/bin/env bash
# ============================================================
# PrimeWave Chain — Node Health Check Script
# ============================================================
#
# Purpose:
#   Quickly verify the health of a PrimeWave Chain validator node
#   or RPC node. Designed to be called by monitoring systems,
#   cron jobs, or node replacement procedures.
#
# Usage:
#   export CHAIN_RPC_URL="http://127.0.0.1:9656/ext/bc/${BLOCKCHAIN_ID}/rpc"
#   export KEEPER_URL="http://127.0.0.1:8080"   # optional
#   ./scripts/health-check.sh
#
# Exit codes:
#   0 — all checks passed
#   1 — one or more checks failed (alert / intervention needed)
# ============================================================

set -euo pipefail

CHAIN_RPC="${CHAIN_RPC_URL:-http://127.0.0.1:9656/ext/bc/C/rpc}"
AVAGO_API="${AVAGO_API_URL:-http://127.0.0.1:9650}"
KEEPER_URL="${KEEPER_URL:-http://127.0.0.1:8080}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
PASS_COUNT=0; FAIL_COUNT=0; WARN_COUNT=0

pass() { echo -e "  ${GREEN}[OK  ]${NC} $1"; ((PASS_COUNT++)); }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $1"; ((WARN_COUNT++)); }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; ((FAIL_COUNT++)); }

rpc() {
    curl -sf -X POST -H "Content-Type: application/json" \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"$1\",\"params\":${2:-[]},\"id\":1}" \
        "${CHAIN_RPC}" --max-time 5 2>/dev/null \
        | python3 -c "import sys,json; print(json.load(sys.stdin).get('result',''))" 2>/dev/null || echo ""
}

echo ""
echo "==========================================================="
echo " PrimeWave Chain — Node Health Check"
echo " $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "==========================================================="

# ── 1. AvalancheGo node alive ────────────────────────────────────────────────
echo ""
echo "--- Node Liveness ---"
NODE_HEALTH=$(curl -sf "${AVAGO_API}/ext/health" --max-time 5 2>/dev/null | \
    python3 -c "import sys,json; h=json.load(sys.stdin); print(h.get('healthy','false'))" 2>/dev/null || echo "UNREACHABLE")

if [ "$NODE_HEALTH" = "True" ] || [ "$NODE_HEALTH" = "true" ]; then
    pass "AvalancheGo node alive"
else
    fail "AvalancheGo node UNREACHABLE or unhealthy (${NODE_HEALTH})"
fi

# ── 2. RPC alive ─────────────────────────────────────────────────────────────
echo ""
echo "--- RPC Health ---"
CHAIN_ID=$(rpc "eth_chainId")
if [ -n "$CHAIN_ID" ] && [ "$CHAIN_ID" != "" ]; then
    CHAIN_ID_DEC=$(python3 -c "print(int('${CHAIN_ID}',16))" 2>/dev/null || echo "?")
    pass "RPC alive (chainId=${CHAIN_ID_DEC})"
else
    fail "RPC UNREACHABLE at ${CHAIN_RPC}"
fi

# ── 3. Block production ───────────────────────────────────────────────────────
echo ""
echo "--- Block Production ---"
BLOCK_HEX=$(rpc "eth_blockNumber")
if [ -n "$BLOCK_HEX" ] && [ "$BLOCK_HEX" != "" ]; then
    BLOCK_NUM=$(python3 -c "print(int('${BLOCK_HEX}',16))" 2>/dev/null || echo "0")

    sleep 3
    BLOCK_HEX2=$(rpc "eth_blockNumber")
    BLOCK_NUM2=$(python3 -c "print(int('${BLOCK_HEX2:-0}',16))" 2>/dev/null || echo "0")

    if [ "$BLOCK_NUM2" -gt "$BLOCK_NUM" ]; then
        pass "Block production active (${BLOCK_NUM} → ${BLOCK_NUM2})"
    else
        warn "No new blocks in 3s — check if chain is halted (current: ${BLOCK_NUM})"
    fi
else
    fail "Could not read block number"
fi

# ── 4. Peer count ─────────────────────────────────────────────────────────────
echo ""
echo "--- Peer Count ---"
PEER_COUNT_HEX=$(rpc "net_peerCount")
if [ -n "$PEER_COUNT_HEX" ]; then
    PEER_COUNT=$(python3 -c "print(int('${PEER_COUNT_HEX}',16))" 2>/dev/null || echo "0")
    if [ "$PEER_COUNT" -ge 2 ]; then
        pass "Peer count: ${PEER_COUNT}"
    elif [ "$PEER_COUNT" -ge 1 ]; then
        warn "Low peer count: ${PEER_COUNT} (expected ≥ 2)"
    else
        fail "Zero peers — node may be isolated"
    fi
else
    warn "Could not read peer count"
fi

# ── 5. Disk space ─────────────────────────────────────────────────────────────
echo ""
echo "--- Disk Space ---"
DATA_DIR="${AVALANCHEGO_DATA_DIR:-/var/lib/avalanchego}"
if [ -d "$DATA_DIR" ]; then
    DISK_USAGE=$(df -h "$DATA_DIR" | tail -1 | awk '{print $5}' | tr -d '%')
    if [ "$DISK_USAGE" -lt 80 ]; then
        pass "Disk usage: ${DISK_USAGE}% (< 80%)"
    elif [ "$DISK_USAGE" -lt 90 ]; then
        warn "Disk usage: ${DISK_USAGE}% (WARNING: > 80%)"
    else
        fail "Disk usage: ${DISK_USAGE}% (CRITICAL: > 90% — immediate action required)"
    fi
else
    warn "Data directory ${DATA_DIR} not found — check AVALANCHEGO_DATA_DIR"
fi

# ── 6. Keeper health ─────────────────────────────────────────────────────────
echo ""
echo "--- Keeper Health ---"
KEEPER_STATUS=$(curl -sf "${KEEPER_URL}/health" --max-time 5 2>/dev/null | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('status','unknown'))" 2>/dev/null || echo "UNREACHABLE")

if [ "$KEEPER_STATUS" = "healthy" ]; then
    pass "Keeper: healthy"
elif [ "$KEEPER_STATUS" = "degraded" ]; then
    warn "Keeper: degraded (pending syncs > threshold)"
elif [ "$KEEPER_STATUS" = "UNREACHABLE" ]; then
    warn "Keeper not reachable at ${KEEPER_URL} — may not be deployed yet"
else
    fail "Keeper: ${KEEPER_STATUS}"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "==========================================================="
echo " HEALTH CHECK SUMMARY"
echo " PASS: ${PASS_COUNT}  WARN: ${WARN_COUNT}  FAIL: ${FAIL_COUNT}"
if [ "$FAIL_COUNT" -eq 0 ] && [ "$WARN_COUNT" -eq 0 ]; then
    echo -e " STATUS: ${GREEN}HEALTHY${NC}"
elif [ "$FAIL_COUNT" -eq 0 ]; then
    echo -e " STATUS: ${YELLOW}DEGRADED — review warnings${NC}"
else
    echo -e " STATUS: ${RED}UNHEALTHY — ${FAIL_COUNT} critical issue(s)${NC}"
fi
echo "==========================================================="

[ "$FAIL_COUNT" -eq 0 ]
