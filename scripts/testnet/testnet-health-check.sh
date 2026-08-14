#!/usr/bin/env bash
# ============================================================
# PrimeWave Testnet — Health Check
# Sprint PW-C14 | TESTNET ONLY
# ============================================================
# Comprehensive liveness check for all testnet components.
# Runs against a live testnet environment.
#
# Usage:
#   TESTNET_RPC_URL=https://rpc.primewave-testnet.example.com \
#   TESTNET_INDEXER_URL=https://indexer.primewave-testnet.example.com \
#   TESTNET_PWCSCAN_URL=https://testnet.pwcscan.example.com \
#   TESTNET_KEEPER_HEALTH_URL=http://keeper-host:8080 \
#   bash scripts/testnet/testnet-health-check.sh
# ============================================================
set -euo pipefail

RPC_URL="${TESTNET_RPC_URL:?}"
INDEXER_URL="${TESTNET_INDEXER_URL:-}"
PWCSCAN_URL="${TESTNET_PWCSCAN_URL:-}"
KEEPER_URL="${TESTNET_KEEPER_HEALTH_URL:-}"

PASS=0; FAIL=0; SKIP=0

check_http() {
  local id="$1" url="$2" expected_contains="${3:-}"
  if [[ -z "$url" ]]; then
    echo "[SKIP]  $id: URL not configured"
    SKIP=$((SKIP+1)); return
  fi
  local body
  body=$(curl -sf --max-time 10 "$url" 2>/dev/null || echo "__FAIL__")
  if [[ "$body" == "__FAIL__" ]]; then
    echo "[FAIL]  $id: $url — unreachable"
    FAIL=$((FAIL+1)); return
  fi
  if [[ -n "$expected_contains" && "$body" != *"$expected_contains"* ]]; then
    echo "[FAIL]  $id: $url — response missing '$expected_contains'"
    FAIL=$((FAIL+1)); return
  fi
  echo "[PASS]  $id: $url"
  PASS=$((PASS+1))
}

check_rpc() {
  local id="$1" method="$2" expected="${3:-}"
  local result
  result=$(curl -sf --max-time 10 -X POST -H 'Content-Type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":[],\"id\":1}" \
    "$RPC_URL" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result','ERROR'))" 2>/dev/null || echo "ERROR")
  if [[ "$result" == "ERROR" ]]; then
    echo "[FAIL]  $id: RPC $method failed"
    FAIL=$((FAIL+1)); return
  fi
  if [[ -n "$expected" && "$result" != "$expected" ]]; then
    echo "[FAIL]  $id: $method expected '$expected', got '$result'"
    FAIL=$((FAIL+1)); return
  fi
  echo "[PASS]  $id: RPC $method => $result"
  PASS=$((PASS+1))
}

echo ""
echo "══ PrimeWave Testnet Health Check ══"
echo "  $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

echo "── RPC Node ──"
check_rpc "HC-01" "eth_chainId" "0x12fc1"      # 77777 in hex
check_rpc "HC-02" "eth_blockNumber"
check_rpc "HC-03" "eth_gasPrice"
check_rpc "HC-04" "net_version" "77777"
check_rpc "HC-05" "web3_clientVersion"

echo ""
echo "── AvalancheGo Node Health ──"
check_http "HC-06" "${RPC_URL%/ext/*}/ext/health" '"healthy":true'
check_http "HC-07" "${RPC_URL%/ext/*}/ext/metrics" 'avalanche_'

echo ""
echo "── Indexer ──"
check_http "HC-08" "$INDEXER_URL/health" '"status":"ok"'
check_http "HC-09" "$INDEXER_URL/stats" '"isSynced":true'

echo ""
echo "── PWCScan Explorer ──"
check_http "HC-10" "$PWCSCAN_URL" 'PrimeWave'

echo ""
echo "── Keeper ──"
check_http "HC-11" "$KEEPER_URL/health" '"status":"ok"'

echo ""
echo "══ Summary ══"
echo "  PASS: $PASS | FAIL: $FAIL | SKIP: $SKIP"
if [[ "$FAIL" -gt 0 ]]; then
  echo "[ERROR] Health check FAILED. Investigate issues before proceeding."
  exit 1
fi
echo "[OK]    All components healthy."
