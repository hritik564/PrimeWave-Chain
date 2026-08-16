#!/usr/bin/env bash
# ============================================================
# PrimeWave Testnet — External Prerequisites Check
# Sprint PW-C15 | TESTNET PRE-DEPLOYMENT
# ============================================================
# Checks what can actually be verified from the current
# environment regarding external infrastructure:
#   - Fuji P-Chain API reachability
#   - Testnet deployer address existence on Fuji
#   - Testnet deployer Fuji AVAX balance
#   - DNS resolution for testnet hostnames
#   - TLS endpoint reachability
#   - SSH reachability (reports BLOCKED if no keys)
#   - Required ports accessible
#   - Cloud node connectivity
#
# Returns a clear BLOCKED report for missing infrastructure.
# Does NOT simulate or fake any result.
#
# Usage:
#   bash scripts/testnet/check-external-prerequisites.sh
#
# Optional env vars:
#   TESTNET_RPC_URL   — public RPC (to check if testnet is live)
#   TESTNET_RPC_HOST  — RPC hostname for DNS/TLS checks
#   TESTNET_EXPLORER  — PWCScan URL for DNS/TLS checks
# ============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
export PATH="$REPO_ROOT/local-bin/foundry:$REPO_ROOT/local-bin:$PATH"

PASS=0; BLOCKED=0; FAIL=0; WARN=0

ok()      { echo "[PASS]    $*"; PASS=$((PASS+1)); }
blocked() { echo "[BLOCKED] $*"; BLOCKED=$((BLOCKED+1)); }
fail()    { echo "[FAIL]    $*"; FAIL=$((FAIL+1)); }
warn()    { echo "[WARN]    $*"; WARN=$((WARN+1)); }
section() { echo ""; echo "── $* ──"; }

DEPLOYER_CCHAIN="0x44A37aF5F03807B1AaA1b20D1BFb3d77959B4B5f"
DEPLOYER_PCHAIN="P-fuji1p25rk6kz9lwg2plwmfmvkvzxsa5qd02kla0vsw"
TESTNET_RPC_URL="${TESTNET_RPC_URL:-}"
TESTNET_RPC_HOST="${TESTNET_RPC_HOST:-rpc.testnet.primewave.xyz}"
TESTNET_EXPLORER="${TESTNET_EXPLORER:-https://explorer.testnet.primewave.xyz}"

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  PrimeWave Testnet — External Prerequisites Check        ║"
echo "║  $(date -u +%Y-%m-%dT%H:%M:%SZ)                              ║"
echo "╚══════════════════════════════════════════════════════════╝"

# ── A. Fuji P-Chain API ───────────────────────────────────────

section "A. FUJI P-CHAIN API"

FUJI_RESULT=$(curl -sf --max-time 10 \
  -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"platform.getHeight","params":{}}' \
  https://api.avax-test.network/ext/bc/P 2>/dev/null || echo "")

if [[ -z "$FUJI_RESULT" ]]; then
  blocked "Fuji P-Chain API: UNREACHABLE (timeout or network block)"
  blocked "  Endpoint: https://api.avax-test.network/ext/bc/P"
  blocked "  Required for: CreateSubnetTx, CreateChainTx, ConvertSubnetToL1Tx"
else
  HEIGHT=$(echo "$FUJI_RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['result']['height'])" 2>/dev/null || echo "ERROR")
  if [[ "$HEIGHT" =~ ^[0-9]+$ ]]; then
    ok "Fuji P-Chain API: reachable — height $HEIGHT"
  else
    fail "Fuji P-Chain API: responded but parsing failed — raw: ${FUJI_RESULT:0:100}"
  fi
fi

# Fuji network ID
FUJI_NET=$(curl -sf --max-time 10 \
  -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"info.getNetworkID","params":{}}' \
  https://api.avax-test.network/ext/info 2>/dev/null | \
  python3 -c "import json,sys; print(json.load(sys.stdin)['result']['networkID'])" 2>/dev/null || echo "")
if [[ "$FUJI_NET" == "5" ]]; then
  ok "Fuji network ID = 5 (confirmed Fuji testnet)"
elif [[ -n "$FUJI_NET" ]]; then
  fail "Network ID = $FUJI_NET — expected 5 (Fuji)"
fi

# ── B. Testnet Deployer Balance ───────────────────────────────

section "B. TESTNET DEPLOYER BALANCE"

echo "  Deployer (C-Chain): $DEPLOYER_CCHAIN"
echo "  Deployer (P-Chain): $DEPLOYER_PCHAIN"

# C-Chain balance via Fuji C-Chain
FUJI_CCHAIN_BAL=$(curl -sf --max-time 10 \
  -X POST -H 'Content-Type: application/json' \
  --data "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getBalance\",\"params\":[\"$DEPLOYER_CCHAIN\",\"latest\"]}" \
  https://api.avax-test.network/ext/bc/C/rpc 2>/dev/null | \
  python3 -c "
import json, sys
d = json.load(sys.stdin)
bal_wei = int(d['result'], 16)
bal_avax = bal_wei / 10**18
print(f'{bal_avax:.6f}')
" 2>/dev/null || echo "")

if [[ -z "$FUJI_CCHAIN_BAL" ]]; then
  blocked "C-Chain balance: could not retrieve (Fuji API unreachable)"
else
  CCHAIN_AVAX=$(echo "$FUJI_CCHAIN_BAL" | python3 -c "import sys; v=float(sys.stdin.read()); print(v >= 2.0)" 2>/dev/null || echo "False")
  echo "  C-Chain balance: $FUJI_CCHAIN_BAL AVAX"
  if [[ "$CCHAIN_AVAX" == "True" ]]; then
    ok "C-Chain balance >= 2 AVAX — adequate for deployment"
  elif [[ $(echo "$FUJI_CCHAIN_BAL" | python3 -c "import sys; print(float(sys.stdin.read()) > 0)" 2>/dev/null) == "True" ]]; then
    warn "C-Chain balance $FUJI_CCHAIN_BAL AVAX — recommend >=2 AVAX; may be enough for CreateSubnetTx"
  else
    blocked "C-Chain balance = 0 AVAX — fund via: https://faucet.avax.network"
    blocked "  Enter address: $DEPLOYER_CCHAIN"
  fi
fi

# P-Chain balance via Avalanche CLI (list keys --fuji)
PCHAIN_BAL=$(avalanche key list --fuji 2>/dev/null | grep -A1 "testnet-deployer" | grep "P-Chain" | grep -oP '[\d.]+ AVAX' | head -1 || echo "")
if [[ -n "$PCHAIN_BAL" ]]; then
  echo "  P-Chain balance: $PCHAIN_BAL"
  PCHAIN_AVAX=$(echo "$PCHAIN_BAL" | grep -oP '[\d.]+')
  PCHAIN_ENOUGH=$(python3 -c "print(float('${PCHAIN_AVAX:-0}') >= 0.1)" 2>/dev/null || echo "False")
  if [[ "$PCHAIN_ENOUGH" == "True" ]]; then
    ok "P-Chain balance >= 0.1 AVAX — sufficient for CreateSubnetTx fees"
  else
    blocked "P-Chain balance $PCHAIN_BAL — need >=0.1 AVAX on P-Chain"
    blocked "  Export from C-Chain: avalanche key transfer --key testnet-deployer --fuji --amount 1.0 --source-chain C --destination-chain P"
  fi
else
  blocked "P-Chain balance: could not retrieve (avalanche key not found or Fuji unreachable)"
fi

# ── C. DNS Resolution ─────────────────────────────────────────

section "C. DNS RESOLUTION"

for host in "$TESTNET_RPC_HOST" "explorer.testnet.primewave.xyz"; do
  IP=$(python3 -c "import socket; print(socket.gethostbyname('$host'))" 2>/dev/null || echo "")
  if [[ -z "$IP" ]]; then
    blocked "DNS: $host — NXDOMAIN or unresolvable"
    blocked "  Register A record: $host → <infra-01 IP>"
  else
    ok "DNS: $host → $IP"
  fi
done

# ── D. TLS / HTTPS Endpoints ──────────────────────────────────

section "D. TLS ENDPOINTS"

for url in "https://$TESTNET_RPC_HOST" "$TESTNET_EXPLORER"; do
  RESULT=$(curl -sf --max-time 10 -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "")
  if [[ -z "$RESULT" || "$RESULT" == "000" ]]; then
    blocked "TLS: $url — unreachable (server not provisioned or cert not issued)"
  elif [[ "$RESULT" =~ ^[23] ]]; then
    ok "TLS: $url — HTTP $RESULT"
  else
    warn "TLS: $url — HTTP $RESULT (may require investigation)"
  fi
done

# ── E. Live Testnet RPC (if configured) ───────────────────────

section "E. LIVE TESTNET RPC"

if [[ -n "$TESTNET_RPC_URL" ]]; then
  CHAIN_ID=$(cast chain-id --rpc-url "$TESTNET_RPC_URL" 2>/dev/null || echo "")
  if [[ "$CHAIN_ID" == "77" ]]; then
    ok "Testnet RPC: Chain ID 77 confirmed at $TESTNET_RPC_URL"
    BLOCK=$(cast block-number --rpc-url "$TESTNET_RPC_URL" 2>/dev/null || echo "")
    [[ -n "$BLOCK" ]] && ok "Testnet RPC: current block $BLOCK" || warn "Testnet RPC: block number unavailable"
  elif [[ -n "$CHAIN_ID" ]]; then
    fail "Testnet RPC: Chain ID $CHAIN_ID — expected 77"
  else
    blocked "Testnet RPC: $TESTNET_RPC_URL — unreachable or not responding"
  fi
else
  blocked "Testnet RPC: TESTNET_RPC_URL not set — set after Phases 9–13 complete"
fi

# ── F. SSH Access ─────────────────────────────────────────────

section "F. SSH ACCESS"

SSH_KEY_COUNT=$(ls ~/.ssh/id_*.pub 2>/dev/null | wc -l)
if [[ "$SSH_KEY_COUNT" -gt 0 ]]; then
  ok "SSH key(s) present: $SSH_KEY_COUNT key file(s) in ~/.ssh/"
else
  blocked "SSH: no keys in ~/.ssh/ — generate with: ssh-keygen -t ed25519 -C 'primewave-testnet'"
  blocked "  Then add public key to each server's authorized_keys before provisioning"
fi

# Check if any validator hosts are reachable (conceptual — would need actual IPs)
echo "  NOTE: SSH connectivity to validator servers requires actual server IPs."
echo "        Set VALIDATOR_IP_LIST env var to test: host1,host2,host3"
if [[ -n "${VALIDATOR_IP_LIST:-}" ]]; then
  IFS=',' read -ra VIPS <<< "$VALIDATOR_IP_LIST"
  for ip in "${VIPS[@]}"; do
    if ssh -o ConnectTimeout=5 -o BatchMode=yes "ubuntu@$ip" exit 2>/dev/null; then
      ok "SSH: ubuntu@$ip — accessible"
    else
      blocked "SSH: ubuntu@$ip — not accessible"
    fi
  done
fi

# ── G. Port Accessibility ────────────────────────────────────

section "G. PORT DOCUMENTATION"

echo "  Required ports for testnet operation:"
echo ""
echo "  ┌──────────────┬──────────┬─────────────────────────┐"
echo "  │ Port         │ Proto    │ Purpose                 │"
echo "  ├──────────────┼──────────┼─────────────────────────┤"
echo "  │ 22           │ TCP      │ SSH (admin)             │"
echo "  │ 9651         │ TCP/UDP  │ AvalancheGo P2P         │"
echo "  │ 9650         │ TCP      │ AvalancheGo API (local) │"
echo "  │ 80           │ TCP      │ HTTP → redirect to HTTPS│"
echo "  │ 443          │ TCP      │ HTTPS RPC + PWCScan     │"
echo "  │ 5432         │ TCP      │ PostgreSQL (internal)   │"
echo "  │ 4000         │ TCP      │ Indexer API (internal)  │"
echo "  │ 8080         │ TCP      │ Keeper health (internal)│"
echo "  │ 9090         │ TCP      │ Prometheus scrape       │"
echo "  └──────────────┴──────────┴─────────────────────────┘"
echo ""
echo "  Validators: open 9651 TCP+UDP publicly; 9650 internal only"
echo "  infra-01: open 80, 443 publicly; all others internal only"
echo ""
blocked "Port firewall configuration: requires external server access"

# ── SUMMARY ───────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  External Prerequisites Summary                          ║"
echo "╚══════════════════════════════════════════════════════════╝"
printf "  %-10s %s\n" "PASS:"    "$PASS"
printf "  %-10s %s\n" "BLOCKED:" "$BLOCKED"
printf "  %-10s %s\n" "FAIL:"    "$FAIL"
printf "  %-10s %s\n" "WARN:"    "$WARN"
echo ""

if [[ "$FAIL" -gt 0 ]]; then
  echo "[FAIL]    Critical failures detected. Resolve before deployment."
  exit 1
elif [[ "$BLOCKED" -gt 0 ]]; then
  echo "[BLOCKED] $BLOCKED external prerequisite(s) unavailable."
  echo "          Testnet deployment requires external cloud infrastructure."
  echo "          See: docs/PW-C15-EXTERNAL-HANDOFF.md"
  exit 2
else
  echo "[PASS]    All checkable external prerequisites are satisfied."
  exit 0
fi
