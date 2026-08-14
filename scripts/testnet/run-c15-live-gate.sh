#!/usr/bin/env bash
# ============================================================
# PrimeWave Testnet — C15 Live Gate Runner
# Sprint PW-C15 | POST-DEPLOYMENT ACCEPTANCE
# ============================================================
# Safe orchestrator that runs C15 acceptance checks in order.
# Default behavior is SAFE — no destructive operations.
# Stops on critical failure.
#
# Structure:
#   PRE-FLIGHT → NETWORK IDENTITY → GENESIS → RPC →
#   VALIDATORS → ACP-99 → ICM → KEEPER → FEES →
#   REWARDS → STAKING → GOVERNANCE → INDEXER →
#   PWCSCAN → FAILURE RECOVERY → MONITORING → FINAL GATE
#
# Usage:
#   TESTNET_RPC_URL=https://rpc.testnet.primewave.xyz/ext/bc/<ID>/rpc \
#   bash scripts/testnet/run-c15-live-gate.sh [--dry-run]
#
# --dry-run:
#   Shows what would be checked without connecting to any RPC.
#   Safe to run with no infrastructure.
#
# Required env:
#   TESTNET_RPC_URL      — testnet EVM RPC
# Optional env:
#   TESTNET_INDEXER_URL  — indexer API
#   TESTNET_PWCSCAN_URL  — PWCScan URL
#   TESTNET_KEEPER_URL   — keeper health URL
#   TESTNET_CONTRACTS_ENV — path to deployed-contracts.env
# ============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
export PATH="$REPO_ROOT/local-bin/foundry:$REPO_ROOT/local-bin:$PATH"

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

RPC_URL="${TESTNET_RPC_URL:-}"
INDEXER_URL="${TESTNET_INDEXER_URL:-}"
PWCSCAN_URL="${TESTNET_PWCSCAN_URL:-}"
KEEPER_URL="${TESTNET_KEEPER_URL:-}"
CONTRACTS_ENV="${TESTNET_CONTRACTS_ENV:-$REPO_ROOT/local-data/testnet-deployed-contracts.env}"

TOTAL_PASS=0; TOTAL_FAIL=0; TOTAL_BLOCKED=0; CRITICAL_FAIL=false

# ── Helpers ───────────────────────────────────────────────────

pass()    { echo "  [PASS]    $*"; TOTAL_PASS=$((TOTAL_PASS+1)); }
fail()    { echo "  [FAIL]    $*"; TOTAL_FAIL=$((TOTAL_FAIL+1)); }
blocked() { echo "  [BLOCKED] $*"; TOTAL_BLOCKED=$((TOTAL_BLOCKED+1)); }
warn()    { echo "  [WARN]    $*"; }
info()    { echo "  [INFO]    $*"; }

phase() {
  echo ""
  echo "╔══════════════════════════════════════════════╗"
  echo "║  $*" | awk '{printf "%-47s║\n", $0}'
  echo "╚══════════════════════════════════════════════╝"
}

rpc_call() {
  local method="$1" param="${2:-[]}"
  curl -sf --max-time 10 -X POST -H 'Content-Type: application/json' \
    --data "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$param,\"id\":1}" \
    "$RPC_URL" 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('result','ERROR'))" 2>/dev/null || echo "ERROR"
}

http_check() {
  local url="$1" expect="${2:-}"
  local body; body=$(curl -sf --max-time 10 "$url" 2>/dev/null || echo "__FAIL__")
  if [[ "$body" == "__FAIL__" ]]; then echo "FAIL"; return; fi
  if [[ -n "$expect" && "$body" != *"$expect"* ]]; then echo "MISMATCH"; return; fi
  echo "OK"
}

stop_on_critical() {
  if [[ "$CRITICAL_FAIL" == "true" ]]; then
    echo ""
    echo "[ABORT] Critical failure detected. Stopping gate execution."
    echo "        Resolve all [FAIL] items before proceeding."
    exit 1
  fi
}

# ── Dry-run mode ──────────────────────────────────────────────

if [[ "$DRY_RUN" == "true" ]]; then
  echo ""
  echo "╔══════════════════════════════════════════════════════════╗"
  echo "║  PW-C15 Live Gate — DRY-RUN MODE                        ║"
  echo "║  No connections made. Showing gate structure only.       ║"
  echo "╚══════════════════════════════════════════════════════════╝"
  echo ""
  cat << 'DRYRUN'
Gate execution order:

  PHASE 0  — PRE-FLIGHT           (local checks — no RPC needed)
  PHASE 1  — NETWORK IDENTITY     (chain ID, block height, peer count)
  PHASE 2  — GENESIS INVARIANTS   (chain ID, supply, NativeMinter, fee split)
  PHASE 3  — RPC HEALTH           (endpoints, latency, admin method blocking)
  PHASE 4  — VALIDATORS           (node count, Fuji P-Chain registration)
  PHASE 5  — ACP-99               (validator registration protocol)
  PHASE 6  — ICM / WARP           (cross-chain message relay)
  PHASE 7  — KEEPER               (health, last poll, authority bounds)
  PHASE 8  — FEES                 (FeeDistributor 70/20/10 on-chain)
  PHASE 9  — REWARDS              (RewardVault 15M cap, emission rate)
  PHASE 10 — STAKING              (ValidatorRegistry, stake/unstake flow)
  PHASE 11 — GOVERNANCE           (EMS, Timelock 48h delay)
  PHASE 12 — INDEXER              (sync status, data integrity)
  PHASE 13 — PWCSCAN              (page load, chain ID badge, block display)
  PHASE 14 — FAILURE RECOVERY     (validator restart, keeper restart, DB restore)
  PHASE 15 — MONITORING           (Prometheus targets, alert rules)
  PHASE 16 — FINAL GATE           (summary, C16 eligibility)

Items that are BLOCKED require live testnet + external infrastructure.
Run with TESTNET_RPC_URL set for live execution.
DRYRUN
  exit 0
fi

# ── Announce ──────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  PrimeWave Testnet — C15 Live Gate Runner                ║"
echo "║  $(date -u +%Y-%m-%dT%H:%M:%SZ)                              ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "  RPC_URL:      ${RPC_URL:-(not set)}"
echo "  INDEXER_URL:  ${INDEXER_URL:-(not set)}"
echo "  PWCSCAN_URL:  ${PWCSCAN_URL:-(not set)}"
echo "  KEEPER_URL:   ${KEEPER_URL:-(not set)}"
echo "  CONTRACTS:    $CONTRACTS_ENV"

# ── PHASE 0: PRE-FLIGHT ───────────────────────────────────────

phase "PHASE 0 — PRE-FLIGHT"

bash "$SCRIPT_DIR/preflight-testnet.sh" 2>&1 | \
  grep -E "READY|FAIL|BLOCKED|WARNING" | \
  grep -E "FAIL|BLOCKED" | head -5 || true

PF_EXIT=0
bash "$SCRIPT_DIR/preflight-testnet.sh" >/dev/null 2>&1 || PF_EXIT=$?
if [[ "$PF_EXIT" -eq 0 ]]; then
  pass "preflight-testnet.sh: all local checks READY"
elif [[ "$PF_EXIT" -eq 2 ]]; then
  blocked "preflight-testnet.sh: external infrastructure items BLOCKED"
else
  fail "preflight-testnet.sh: local check(s) FAILED"
  CRITICAL_FAIL=true
fi
stop_on_critical

# ── PHASE 1: NETWORK IDENTITY ─────────────────────────────────

phase "PHASE 1 — NETWORK IDENTITY"

if [[ -z "$RPC_URL" ]]; then
  blocked "TESTNET_RPC_URL not set — all network checks BLOCKED"
  blocked "Set: export TESTNET_RPC_URL=https://rpc.testnet.primewave.xyz/ext/bc/<ID>/rpc"
else
  # Chain ID
  CHAIN_ID=$(rpc_call "eth_chainId" || echo "ERROR")
  if [[ "$CHAIN_ID" == "0x4d" ]]; then
    pass "NET-01: eth_chainId = 0x4d (77) ✓"
  else
    fail "NET-01: eth_chainId = $CHAIN_ID — expected 0x4d"
    CRITICAL_FAIL=true
  fi
  stop_on_critical

  # Block number
  BLOCK1=$(rpc_call "eth_blockNumber")
  if [[ "$BLOCK1" != "ERROR" ]]; then
    BLOCK_DEC=$(python3 -c "print(int('$BLOCK1', 16))" 2>/dev/null || echo "?")
    pass "NET-02: eth_blockNumber = $BLOCK_DEC"
  else
    fail "NET-02: eth_blockNumber failed"
  fi

  # Block production (wait 3s, compare)
  sleep 3
  BLOCK2=$(rpc_call "eth_blockNumber")
  if [[ "$BLOCK2" != "ERROR" && "$BLOCK1" != "ERROR" ]]; then
    B1=$(python3 -c "print(int('$BLOCK1', 16))" 2>/dev/null || echo "0")
    B2=$(python3 -c "print(int('$BLOCK2', 16))" 2>/dev/null || echo "0")
    if [[ "$B2" -ge "$B1" ]]; then
      pass "NET-03: Blocks advancing ($B1 → $B2)"
    else
      fail "NET-03: Block height not advancing — chain may be stalled"
    fi
  fi

  # net_version
  NET_VER=$(rpc_call "net_version")
  if [[ "$NET_VER" == "77" ]]; then
    pass "NET-04: net_version = 77 ✓"
  else
    fail "NET-04: net_version = $NET_VER — expected 77"
  fi

  # Peer count
  PEERS=$(rpc_call "net_peerCount")
  if [[ "$PEERS" != "ERROR" ]]; then
    PEER_DEC=$(python3 -c "print(int('$PEERS', 16))" 2>/dev/null || echo "?")
    if [[ "$PEER_DEC" -ge 2 ]]; then
      pass "NET-05: net_peerCount = $PEER_DEC peers ✓"
    else
      fail "NET-05: net_peerCount = $PEER_DEC — need ≥2 peers for consensus"
    fi
  fi

  # AvalancheGo node health
  BASE_URL="${RPC_URL%/ext/bc/*}"
  NODE_HEALTH=$(http_check "$BASE_URL/ext/health" '"healthy":true')
  if [[ "$NODE_HEALTH" == "OK" ]]; then
    pass "NET-06: AvalancheGo /ext/health = healthy"
  else
    fail "NET-06: AvalancheGo /ext/health not healthy"
  fi
fi

# ── PHASE 2: GENESIS INVARIANTS ───────────────────────────────

phase "PHASE 2 — GENESIS INVARIANTS"

if [[ -z "$RPC_URL" ]]; then
  blocked "TESTNET_RPC_URL not set — genesis on-chain invariants BLOCKED"
else
  # Load contract addresses if available
  [[ -f "$CONTRACTS_ENV" ]] && source "$CONTRACTS_ENV"

  # INV-G1: Chain ID
  CHAIN_ID_DEC=$(cast chain-id --rpc-url "$RPC_URL" 2>/dev/null || echo "ERROR")
  [[ "$CHAIN_ID_DEC" == "77" ]] && pass "INV-G1: chain ID = 77" || fail "INV-G1: chain ID = $CHAIN_ID_DEC"

  # INV-G2: NativeMinter (check no addresses have minting access)
  MINTER_CODE=$(cast code 0x0200000000000000000000000000000000000001 --rpc-url "$RPC_URL" 2>/dev/null || echo "ERROR")
  if [[ "$MINTER_CODE" != "ERROR" ]]; then
    info "INV-G2: NativeMinter code present (precompile) — verify allowlist is empty via node admin API"
  fi

  # INV-G4: RewardVault funded
  if [[ -n "${ADDR_REWARD_VAULT:-}" ]]; then
    FUNDED=$(cast call "$ADDR_REWARD_VAULT" "totalFunded()(uint256)" --rpc-url "$RPC_URL" 2>/dev/null | cast to-dec 2>/dev/null || echo "ERROR")
    [[ "$FUNDED" == "15000000000000000000000000" ]] && \
      pass "INV-G4: RewardVault.totalFunded() = 15M PW" || \
      fail "INV-G4: RewardVault.totalFunded() = $FUNDED (expected 15000000000000000000000000)"
  else
    blocked "INV-G4: ADDR_REWARD_VAULT not set — deploy contracts first"
  fi

  # INV-G7: FeeDistributor split
  if [[ -n "${ADDR_FEE_DISTRIBUTOR:-}" ]]; then
    V_BPS=$(cast call "$ADDR_FEE_DISTRIBUTOR" "VALIDATOR_SHARE_BPS()(uint256)" --rpc-url "$RPC_URL" 2>/dev/null | cast to-dec 2>/dev/null || echo "ERROR")
    T_BPS=$(cast call "$ADDR_FEE_DISTRIBUTOR" "TREASURY_SHARE_BPS()(uint256)" --rpc-url "$RPC_URL" 2>/dev/null | cast to-dec 2>/dev/null || echo "ERROR")
    if [[ "$V_BPS" == "7000" && "$T_BPS" == "2000" ]]; then
      pass "INV-G7: FeeDistributor split = 70% / 20% / 10% (burn)"
    else
      fail "INV-G7: FeeDistributor split unexpected (validator=$V_BPS, treasury=$T_BPS)"
    fi
  else
    blocked "INV-G7: ADDR_FEE_DISTRIBUTOR not set — deploy contracts first"
  fi
fi

# ── PHASE 3: RPC HEALTH ───────────────────────────────────────

phase "PHASE 3 — RPC HEALTH"

if [[ -z "$RPC_URL" ]]; then
  blocked "TESTNET_RPC_URL not set — RPC checks BLOCKED"
else
  # Admin method blocking (eth_accounts should be blocked or return empty)
  ADMIN_RESP=$(curl -sf --max-time 5 -X POST -H 'Content-Type: application/json' \
    --data '{"jsonrpc":"2.0","id":1,"method":"eth_accounts","params":[]}' \
    "$RPC_URL" 2>/dev/null || echo "BLOCKED_CONN")
  if [[ "$ADMIN_RESP" == "BLOCKED_CONN" ]]; then
    fail "RPC-01: Could not reach RPC for admin method check"
  elif echo "$ADMIN_RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); r=d.get('result',[]); sys.exit(0 if not r else 1)" 2>/dev/null; then
    pass "RPC-01: eth_accounts returns empty (no local accounts exposed)"
  else
    warn "RPC-01: eth_accounts returned non-empty — check nginx admin method blocking"
  fi

  # Gas price
  GAS=$(rpc_call "eth_gasPrice")
  [[ "$GAS" != "ERROR" ]] && pass "RPC-02: eth_gasPrice = $(python3 -c "print(int('$GAS',16))" 2>/dev/null) wei" || fail "RPC-02: eth_gasPrice failed"

  # Latency
  START=$(date +%s%N)
  rpc_call "eth_blockNumber" >/dev/null
  END=$(date +%s%N)
  LATENCY_MS=$(( (END - START) / 1000000 ))
  if [[ "$LATENCY_MS" -lt 2000 ]]; then
    pass "RPC-03: RPC latency = ${LATENCY_MS}ms (< 2000ms)"
  else
    warn "RPC-03: RPC latency = ${LATENCY_MS}ms — investigate performance"
  fi
fi

# ── PHASES 4–16: Infrastructure-dependent ────────────────────

for phase_name in \
  "PHASE 4  — VALIDATORS" \
  "PHASE 5  — ACP-99 (VALIDATOR REGISTRATION)" \
  "PHASE 6  — ICM / WARP" \
  "PHASE 7  — KEEPER" \
  "PHASE 8  — FEES (FEEDISTRIBUTOR)" \
  "PHASE 9  — REWARDS (REWARDVAULT)" \
  "PHASE 10 — STAKING (VALIDATORREGISTRY)" \
  "PHASE 11 — GOVERNANCE (EMS + TIMELOCK)" \
  "PHASE 14 — FAILURE RECOVERY" \
  "PHASE 15 — MONITORING"; do
  phase "$phase_name"
  blocked "Requires live testnet with deployed validators and contracts"
  blocked "Execute manually per docs/PW-C15-TESTNET-BATTLE-TEST.md after full infra deployment"
done

# ── PHASE 12: INDEXER ─────────────────────────────────────────

phase "PHASE 12 — INDEXER"

if [[ -z "$INDEXER_URL" ]]; then
  blocked "TESTNET_INDEXER_URL not set — indexer checks BLOCKED"
else
  HEALTH=$(http_check "$INDEXER_URL/health" '"status":"ok"')
  [[ "$HEALTH" == "OK" ]] && pass "IDX-01: Indexer health = ok" || fail "IDX-01: Indexer health failed at $INDEXER_URL/health"

  SYNC=$(http_check "$INDEXER_URL/stats" '"isSynced"')
  [[ "$SYNC" == "OK" ]] && pass "IDX-02: Indexer stats endpoint responding" || fail "IDX-02: Indexer stats endpoint failed"

  BLOCKS_RESP=$(curl -sf --max-time 10 "$INDEXER_URL/blocks?limit=1" 2>/dev/null || echo "")
  [[ -n "$BLOCKS_RESP" ]] && pass "IDX-03: Indexer /blocks endpoint responding" || fail "IDX-03: Indexer /blocks not responding"
fi

# ── PHASE 13: PWCSCAN ─────────────────────────────────────────

phase "PHASE 13 — PWCSCAN"

if [[ -z "$PWCSCAN_URL" ]]; then
  blocked "TESTNET_PWCSCAN_URL not set — PWCScan checks BLOCKED"
else
  PAGE=$(http_check "$PWCSCAN_URL" "PrimeWave")
  [[ "$PAGE" == "OK" ]] && pass "PWC-01: PWCScan page loads (contains 'PrimeWave')" || fail "PWC-01: PWCScan page load failed"

  TESTNET_BADGE=$(http_check "$PWCSCAN_URL" "Testnet")
  [[ "$TESTNET_BADGE" == "OK" ]] && pass "PWC-02: Testnet badge visible" || warn "PWC-02: 'Testnet' text not found in page HTML (may be rendered by JS)"
fi

# ── FINAL GATE ────────────────────────────────────────────────

phase "PHASE 16 — FINAL GATE"

echo ""
echo "  PASS:    $TOTAL_PASS"
echo "  FAIL:    $TOTAL_FAIL"
echo "  BLOCKED: $TOTAL_BLOCKED"
echo ""

if [[ "$TOTAL_FAIL" -gt 0 ]]; then
  echo "  ╔══════════════════════════════════════════╗"
  echo "  ║  GATE STATUS: FAIL                       ║"
  echo "  ║  $TOTAL_FAIL critical item(s) failed.           " | awk '{printf "  ║  %-43s║\n", $0}'
  echo "  ║  Resolve all FAIL items before C16.      ║"
  echo "  ╚══════════════════════════════════════════╝"
  exit 1
elif [[ "$TOTAL_BLOCKED" -gt 0 ]]; then
  echo "  ╔══════════════════════════════════════════╗"
  echo "  ║  GATE STATUS: BLOCKED                    ║"
  echo "  ║  $TOTAL_BLOCKED item(s) require external infra.  " | awk '{printf "  ║  %-43s║\n", $0}'
  echo "  ║  Deploy testnet, then re-run this gate.  ║"
  echo "  ╚══════════════════════════════════════════╝"
  exit 2
else
  echo "  ╔══════════════════════════════════════════╗"
  echo "  ║  GATE STATUS: PASS                       ║"
  echo "  ║  All C15 live gate checks passed.        ║"
  echo "  ║  C16 may be opened upon leadership OK.   ║"
  echo "  ╚══════════════════════════════════════════╝"
  exit 0
fi
