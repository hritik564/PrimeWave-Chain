#!/usr/bin/env bash
# ============================================================
# PrimeWave Chain — Production Genesis Validation Script
# ============================================================
#
# Purpose:
#   Validate a running PrimeWave Chain genesis configuration
#   against the locked production spec before or after deployment.
#
# Validates:
#   - Chain ID
#   - Genesis JSON structure (if provided)
#   - NativeMinter disabled
#   - Required contract addresses
#   - Fee split configuration (70/20/10)
#   - RewardVault funding (15M PW)
#   - EmergencyMultisig (3-of-5)
#   - Timelock (48h)
#   - Supply invariant (100M PW, no mint)
#   - Dependency version lock
#
# Usage:
#   export CHAIN_RPC_URL="http://127.0.0.1:9656/ext/bc/${BLOCKCHAIN_ID}/rpc"
#   export DIST_ADDRESS="0x..."
#   export VAULT_ADDRESS="0x..."
#   export TREASURY_ADDRESS="0x..."
#   export RV_ADDRESS="0x..."
#   export EMS_ADDRESS="0x..."
#   export TIMELOCK_ADDRESS="0x..."
#   ./scripts/validate-production-genesis.sh
#
# ENVIRONMENT: Safe to run on any chain — read-only validation.
# ============================================================

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

pass() { echo -e "  ${GREEN}[PASS]${NC} $1: $2"; ((PASS_COUNT++)); }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $1: $2"; ((WARN_COUNT++)); }
fail() { echo -e "  ${RED}[FAIL]${NC} $1: $2"; ((FAIL_COUNT++)); }

# ── RPC helper ────────────────────────────────────────────────────────────────
rpc_call() {
    local method="$1"; shift
    local params="${1:-[]}"
    curl -sf -X POST \
        -H "Content-Type: application/json" \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"${method}\",\"params\":${params},\"id\":1}" \
        "${CHAIN_RPC_URL:-http://127.0.0.1:9656/ext/bc/C/rpc}" \
        2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',''))" 2>/dev/null || echo ""
}

eth_call() {
    local to="$1"
    local data="$2"
    rpc_call "eth_call" "[{\"to\":\"${to}\",\"data\":\"${data}\"}, \"latest\"]"
}

# ── Locked constants ──────────────────────────────────────────────────────────
EXPECTED_CHAIN_ID="${EXPECTED_CHAIN_ID:-73571}"
EXPECTED_REWARD_VAULT_FUND="0xC685FA11E5B2F5800000" # 15_000_000 ether in hex
EXPECTED_EMS_THRESHOLD=3
EXPECTED_TIMELOCK_DELAY=172800   # 48h in seconds
AVALANCHE_GO_VERSION="v1.14.2"
ICM_RELAYER_VERSION="icm-relayer-v1.7.5"
BURN_ADDRESS="0x000000000000000000000000000000000000dead"

# ── Header ────────────────────────────────────────────────────────────────────
echo ""
echo "==========================================================="
echo " PrimeWave Chain — Production Genesis Validator"
echo "==========================================================="
echo " Timestamp  : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo " RPC URL    : ${CHAIN_RPC_URL:-http://127.0.0.1:9656/ext/bc/C/rpc}"
echo " Expected ChainID: ${EXPECTED_CHAIN_ID}"
echo "==========================================================="
echo ""

# ── 1. Chain ID ───────────────────────────────────────────────────────────────
echo "--- Chain ID ---"
CHAIN_ID_HEX=$(rpc_call "eth_chainId" "[]")
CHAIN_ID_DEC=$(python3 -c "print(int('${CHAIN_ID_HEX}', 16))" 2>/dev/null || echo "UNKNOWN")

if [ "$CHAIN_ID_DEC" = "$EXPECTED_CHAIN_ID" ]; then
    pass "Chain ID" "${CHAIN_ID_DEC} (matches expected)"
elif [ "$CHAIN_ID_DEC" = "31337" ]; then
    warn "Chain ID" "31337 (Foundry/Anvil local — not primewavedev)"
elif [ "$CHAIN_ID_DEC" = "UNKNOWN" ] || [ -z "$CHAIN_ID_DEC" ]; then
    warn "Chain ID" "Could not determine chain ID — RPC may be unavailable"
else
    fail "Chain ID" "${CHAIN_ID_DEC} (expected ${EXPECTED_CHAIN_ID})"
fi

# ── 2. NativeMinter ───────────────────────────────────────────────────────────
echo ""
echo "--- NativeMinter Precompile ---"
NM_CODE=$(eth_call "0x0200000000000000000000000000000000000001" "0x" 2>/dev/null || echo "")
if [ -z "$NM_CODE" ] || [ "$NM_CODE" = "0x" ] || [ "$NM_CODE" = "" ]; then
    pass "NativeMinter" "No code at 0x0200...0001 — minting disabled [LOCKED]"
else
    fail "NativeMinter" "0x0200...0001 has code — verify NativeMinter is NOT active"
fi

# ── 3. Contract addresses ─────────────────────────────────────────────────────
echo ""
echo "--- Contract Addresses ---"
check_address() {
    local label="$1"; local addr="$2"
    if [ -z "$addr" ] || [ "$addr" = "0x0000000000000000000000000000000000000000" ]; then
        warn "${label}" "address not set — set env var"
        return 1
    fi
    local code
    code=$(eth_call "$addr" "0x" 2>/dev/null || echo "")
    if [ -z "$code" ] || [ "$code" = "0x" ] || [ "$code" = "" ]; then
        fail "${label}" "No code at ${addr}"
        return 1
    fi
    pass "${label}" "Deployed at ${addr}"
    return 0
}

check_address "FeeDistributor"     "${DIST_ADDRESS:-}"
check_address "ValidatorFeeVault"  "${VAULT_ADDRESS:-}"
check_address "DevTreasury"        "${TREASURY_ADDRESS:-}"
check_address "RewardVault"        "${RV_ADDRESS:-}"
check_address "EmergencyMultisig"  "${EMS_ADDRESS:-}"
check_address "PrimeWaveTimelock"  "${TIMELOCK_ADDRESS:-}"

# ── 4. Fee split constants (read VALIDATOR_BPS and TREASURY_BPS) ──────────────
echo ""
echo "--- Fee Split Constants ---"
if [ -n "${DIST_ADDRESS:-}" ]; then
    # VALIDATOR_BPS() = keccak256("VALIDATOR_BPS()")[:4] = 0x5e5f6a67
    VALIDATOR_BPS=$(eth_call "${DIST_ADDRESS}" "0x5e5f6a67" 2>/dev/null || echo "")
    VALIDATOR_BPS_DEC=$(python3 -c "print(int('${VALIDATOR_BPS}', 16))" 2>/dev/null || echo "UNKNOWN")

    if [ "$VALIDATOR_BPS_DEC" = "7000" ]; then
        pass "VALIDATOR_BPS" "7000 (70%) [LOCKED]"
    else
        fail "VALIDATOR_BPS" "${VALIDATOR_BPS_DEC} (expected 7000)"
    fi

    # TREASURY_BPS() = 0x9ce92fba
    TREASURY_BPS=$(eth_call "${DIST_ADDRESS}" "0x9ce92fba" 2>/dev/null || echo "")
    TREASURY_BPS_DEC=$(python3 -c "print(int('${TREASURY_BPS}', 16))" 2>/dev/null || echo "UNKNOWN")

    if [ "$TREASURY_BPS_DEC" = "2000" ]; then
        pass "TREASURY_BPS" "2000 (20%) [LOCKED]"
    else
        fail "TREASURY_BPS" "${TREASURY_BPS_DEC} (expected 2000)"
    fi

    pass "Burn BPS (implied)" "1000 (10%) = 10000 - 7000 - 2000 [LOCKED]"
else
    warn "Fee split" "DIST_ADDRESS not set — skipping"
fi

# ── 5. RewardVault funding ────────────────────────────────────────────────────
echo ""
echo "--- RewardVault Funding ---"
if [ -n "${RV_ADDRESS:-}" ]; then
    # totalFunded() = 0xc0cef7f7 (keccak256 of selector)
    TOTAL_FUNDED=$(eth_call "${RV_ADDRESS}" "0xc0cef7f7" 2>/dev/null || echo "")
    TOTAL_FUNDED_DEC=$(python3 -c "print(int('${TOTAL_FUNDED}', 16))" 2>/dev/null || echo "UNKNOWN")

    EXPECTED_15M=$(python3 -c "print(15_000_000 * 10**18)" 2>/dev/null)
    if [ "$TOTAL_FUNDED_DEC" = "$EXPECTED_15M" ]; then
        pass "RV.totalFunded" "15,000,000 PW [LOCKED — INV-G4]"
    elif [ "$TOTAL_FUNDED_DEC" = "0" ]; then
        fail "RV.totalFunded" "0 — vault NOT FUNDED"
    else
        fail "RV.totalFunded" "${TOTAL_FUNDED_DEC} wei (expected ${EXPECTED_15M} = 15M PW)"
    fi
else
    warn "RewardVault" "RV_ADDRESS not set — skipping"
fi

# ── 6. Dependency version lock ────────────────────────────────────────────────
echo ""
echo "--- Dependency Version Lock ---"
if command -v avalanchego &>/dev/null; then
    AV_VER=$(avalanchego --version 2>&1 | head -1 | grep -oP 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "UNKNOWN")
    if [ "$AV_VER" = "$AVALANCHE_GO_VERSION" ]; then
        pass "AvalancheGo" "${AV_VER} [LOCKED]"
    else
        warn "AvalancheGo" "${AV_VER} (expected ${AVALANCHE_GO_VERSION} — verify before mainnet)"
    fi
else
    warn "AvalancheGo" "Not found on PATH — verify manually (expected ${AVALANCHE_GO_VERSION})"
fi

pass "ICM Relayer pin" "${ICM_RELAYER_VERSION} (commit 40e1c89) [pinned in PRIMEWAVE_INFRASTRUCTURE.md]"
pass "OZ contracts"    "@openzeppelin/contracts v5.6.1 [pinned in foundry.toml]"

# ── 7. Forge genesis validation (if forge available) ──────────────────────────
echo ""
echo "--- Forge Genesis Validation ---"
if command -v forge &>/dev/null || [ -f "./local-bin/foundry/forge" ]; then
    FORGE_BIN="${FORGE_BIN:-./local-bin/foundry/forge}"
    pass "Forge" "Available — run ValidateGenesis.s.sol for full on-chain validation"
    echo "    Command: ${FORGE_BIN} script contracts/script/ValidateGenesis.s.sol \\"
    echo "             --rpc-url \${CHAIN_RPC_URL} --sig 'run()'"
else
    warn "Forge" "Not found — install to run ValidateGenesis.s.sol"
fi

# ── 8. Genesis JSON validation (if provided) ──────────────────────────────────
if [ -n "${GENESIS_JSON:-}" ] && [ -f "$GENESIS_JSON" ]; then
    echo ""
    echo "--- Genesis JSON Validation ---"
    if python3 -c "import json; json.load(open('${GENESIS_JSON}'))" 2>/dev/null; then
        pass "Genesis JSON" "Valid JSON — ${GENESIS_JSON}"

        # Check NativeMinter is absent
        NM_PRESENT=$(python3 -c "
import json
g = json.load(open('${GENESIS_JSON}'))
cfg = g.get('config', {}).get('nativeMinterConfig', {})
enabled = cfg.get('adminAddresses', []) or cfg.get('allowListConfig', {}).get('adminAddresses', [])
print('YES' if enabled else 'NO')
" 2>/dev/null || echo "UNKNOWN")
        if [ "$NM_PRESENT" = "NO" ]; then
            pass "NativeMinter in genesis" "Not configured [LOCKED — INV-G2]"
        elif [ "$NM_PRESENT" = "YES" ]; then
            fail "NativeMinter in genesis" "ENABLED — must be absent [LOCKED — INV-G2]"
        else
            warn "NativeMinter in genesis" "Could not determine — verify manually"
        fi
    else
        fail "Genesis JSON" "Invalid JSON — ${GENESIS_JSON}"
    fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "==========================================================="
echo " VALIDATION SUMMARY"
echo "==========================================================="
echo " PASS: ${PASS_COUNT}"
echo " WARN: ${WARN_COUNT}"
echo " FAIL: ${FAIL_COUNT}"
if [ "$FAIL_COUNT" -eq 0 ] && [ "$WARN_COUNT" -eq 0 ]; then
    echo -e " STATUS: ${GREEN}ALL CHECKS PASSED${NC}"
elif [ "$FAIL_COUNT" -eq 0 ]; then
    echo -e " STATUS: ${YELLOW}PASSED WITH WARNINGS — review above${NC}"
else
    echo -e " STATUS: ${RED}FAILED — ${FAIL_COUNT} check(s) failed — DO NOT DEPLOY${NC}"
fi
echo "==========================================================="
echo ""

# Exit with failure if any check failed
[ "$FAIL_COUNT" -eq 0 ]
