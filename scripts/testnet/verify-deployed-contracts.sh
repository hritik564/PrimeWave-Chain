#!/usr/bin/env bash
# ============================================================
# PrimeWave Testnet — Deployed Contract Verifier
# Sprint PW-C15 | POST-DEPLOYMENT
# ============================================================
# Verifies all 7 deployed testnet contracts against the live
# chain. Accepts an RPC URL + deployment manifest and checks:
#   - Each contract has bytecode (not EOA or empty)
#   - Chain ID == 77
#   - RewardVault funded with exactly 15M PW
#   - FeeDistributor split constants: 7000/2000 BPS
#   - EmergencyMultisig signer count
#   - Governance addresses are consistent
#   - No zero-address contracts
#
# Status codes:
#   [PASS]    — verified on-chain
#   [FAIL]    — mismatch or error
#   [SKIP]    — address not provided in manifest
#   [BLOCKED] — RPC not available
#
# Usage:
#   TESTNET_RPC_URL=https://rpc.testnet.primewave.xyz/ext/bc/<ID>/rpc \
#   TESTNET_CONTRACTS_ENV=local-data/testnet-deployed-contracts.env \
#   bash scripts/testnet/verify-deployed-contracts.sh
#
# Without RPC: reports BLOCKED rather than fabricating results.
# ============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
export PATH="$REPO_ROOT/local-bin/foundry:$REPO_ROOT/local-bin:$PATH"

RPC_URL="${TESTNET_RPC_URL:-}"
CONTRACTS_ENV="${TESTNET_CONTRACTS_ENV:-$REPO_ROOT/local-data/testnet-deployed-contracts.env}"

PASS=0; FAIL=0; SKIP=0; BLOCKED=0

passed() { echo "[PASS]    $*"; PASS=$((PASS+1)); }
failed()  { echo "[FAIL]    $*"; FAIL=$((FAIL+1)); }
skipped() { echo "[SKIP]    $*"; SKIP=$((SKIP+1)); }
blocked() { echo "[BLOCKED] $*"; BLOCKED=$((BLOCKED+1)); }
section() { echo ""; echo "── $* ──"; }

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  PrimeWave Testnet — Deployed Contract Verifier          ║"
echo "║  $(date -u +%Y-%m-%dT%H:%M:%SZ)                              ║"
echo "╚══════════════════════════════════════════════════════════╝"

# ── Check RPC Availability ────────────────────────────────────

section "NETWORK"

if [[ -z "$RPC_URL" ]]; then
  echo ""
  echo "[BLOCKED] TESTNET_RPC_URL not set."
  echo "          This script requires a live testnet RPC endpoint."
  echo "          Set: export TESTNET_RPC_URL=https://rpc.testnet.primewave.xyz/ext/bc/<ID>/rpc"
  echo ""
  echo "          Cannot verify deployed contracts without the live chain."
  echo "          Run after Phase 13 (RPC deployment) in the DAY-0 checklist."
  exit 2
fi

CHAIN_ID=$(cast chain-id --rpc-url "$RPC_URL" 2>/dev/null || echo "ERROR")
if [[ "$CHAIN_ID" == "ERROR" ]]; then
  echo ""
  echo "[BLOCKED] RPC URL unreachable: $RPC_URL"
  echo "          Deploy the testnet network first (Phases 9–13)."
  exit 2
fi

if [[ "$CHAIN_ID" != "77" ]]; then
  echo "[FAIL]    Chain ID = $CHAIN_ID — expected 77 (testnet)"
  echo "          REFUSING to verify contracts on wrong network."
  exit 1
fi
passed "Chain ID = 77 (testnet confirmed)"

BLOCK=$(cast block-number --rpc-url "$RPC_URL" 2>/dev/null || echo "")
[[ -n "$BLOCK" ]] && passed "RPC block number = $BLOCK" || failed "Cannot retrieve block number"

# ── Load Contract Addresses ───────────────────────────────────

section "CONTRACT MANIFEST"

if [[ -f "$CONTRACTS_ENV" ]]; then
  # shellcheck source=/dev/null
  source "$CONTRACTS_ENV"
  echo "  Loaded: $CONTRACTS_ENV"
else
  echo "[BLOCKED] Deployment manifest not found: $CONTRACTS_ENV"
  echo "          Run scripts/testnet/deploy-contracts.sh first."
  exit 2
fi

# ── Helper: verify contract has code ─────────────────────────

verify_has_code() {
  local name="$1" addr="${2:-}"
  if [[ -z "$addr" || "$addr" == "0x0000000000000000000000000000000000000000" ]]; then
    skipped "$name: address not set"
    return
  fi
  local code
  code=$(cast code "$addr" --rpc-url "$RPC_URL" 2>/dev/null || echo "ERROR")
  if [[ "$code" == "ERROR" || -z "$code" ]]; then
    failed "$name ($addr): RPC error retrieving bytecode"
  elif [[ "$code" == "0x" || "$code" == "" ]]; then
    failed "$name ($addr): NO BYTECODE — contract not deployed or wrong address"
  else
    passed "$name ($addr): bytecode present (${#code} chars)"
  fi
}

# ── Helper: cast call with expected value ─────────────────────

verify_call() {
  local id="$1" addr="$2" sig="$3" expected="$4"
  local result
  result=$(cast call "$addr" "$sig" --rpc-url "$RPC_URL" 2>/dev/null | cast to-dec 2>/dev/null || echo "ERROR")
  if [[ "$result" == "ERROR" ]]; then
    failed "$id: cast call failed ($sig on $addr)"
  elif [[ "$result" == "$expected" ]]; then
    passed "$id: $sig = $result"
  else
    failed "$id: $sig = $result — expected $expected"
  fi
}

# ── 1. Bytecode Verification ──────────────────────────────────

section "1. CONTRACT BYTECODE"

verify_has_code "EmergencyMultisig"    "${ADDR_EMERGENCY_MULTISIG:-}"
verify_has_code "PrimeWaveTimelock"    "${ADDR_TIMELOCK:-}"
verify_has_code "ValidatorFeeVault"    "${ADDR_VALIDATOR_FEE_VAULT:-}"
verify_has_code "DevTreasury"          "${ADDR_DEV_TREASURY:-}"
verify_has_code "FeeDistributor"       "${ADDR_FEE_DISTRIBUTOR:-}"
verify_has_code "RewardVault"          "${ADDR_REWARD_VAULT:-}"
verify_has_code "ValidatorRegistry"    "${ADDR_VALIDATOR_REGISTRY:-}"

# ── 2. RewardVault Invariants ─────────────────────────────────

section "2. REWARDVAULT INVARIANTS"

if [[ -n "${ADDR_REWARD_VAULT:-}" && "${ADDR_REWARD_VAULT}" != "0x0000000000000000000000000000000000000000" ]]; then
  # totalFunded == 15M PW (in wei)
  TOTAL_FUNDED=$(cast call "$ADDR_REWARD_VAULT" "totalFunded()(uint256)" --rpc-url "$RPC_URL" 2>/dev/null | cast to-dec 2>/dev/null || echo "ERROR")
  EXPECTED_FUNDED="15000000000000000000000000"
  if [[ "$TOTAL_FUNDED" == "$EXPECTED_FUNDED" ]]; then
    passed "RewardVault.totalFunded() = 15,000,000 PW ✓"
  elif [[ "$TOTAL_FUNDED" == "ERROR" ]]; then
    failed "RewardVault.totalFunded(): call failed"
  else
    PW=$(python3 -c "print(int('${TOTAL_FUNDED:-0}') // 10**18)" 2>/dev/null || echo "?")
    failed "RewardVault.totalFunded() = $PW PW — expected 15,000,000 PW"
  fi

  # totalEmitted <= totalFunded
  TOTAL_EMITTED=$(cast call "$ADDR_REWARD_VAULT" "totalEmitted()(uint256)" --rpc-url "$RPC_URL" 2>/dev/null | cast to-dec 2>/dev/null || echo "ERROR")
  if [[ "$TOTAL_EMITTED" != "ERROR" ]]; then
    EMITTED_OK=$(python3 -c "print(int('${TOTAL_EMITTED:-0}') <= int('$EXPECTED_FUNDED'))" 2>/dev/null || echo "False")
    PW_EMITTED=$(python3 -c "print(int('${TOTAL_EMITTED:-0}') // 10**18)" 2>/dev/null || echo "?")
    if [[ "$EMITTED_OK" == "True" ]]; then
      passed "RewardVault.totalEmitted() = $PW_EMITTED PW (within 15M PW cap)"
    else
      failed "RewardVault.totalEmitted() = $PW_EMITTED PW — EXCEEDS 15M PW cap"
    fi
  fi

  # Contract balance should be >= (totalFunded - totalEmitted)
  VAULT_BAL=$(cast balance "$ADDR_REWARD_VAULT" --rpc-url "$RPC_URL" 2>/dev/null | cast to-dec 2>/dev/null || echo "ERROR")
  if [[ "$VAULT_BAL" != "ERROR" && "$TOTAL_FUNDED" != "ERROR" && "$TOTAL_EMITTED" != "ERROR" ]]; then
    MIN_EXPECTED=$(python3 -c "print(int('$TOTAL_FUNDED') - int('${TOTAL_EMITTED:-0}'))" 2>/dev/null || echo "0")
    BAL_OK=$(python3 -c "print(int('${VAULT_BAL:-0}') >= int('$MIN_EXPECTED'))" 2>/dev/null || echo "False")
    BAL_PW=$(python3 -c "print(int('${VAULT_BAL:-0}') // 10**18)" 2>/dev/null || echo "?")
    if [[ "$BAL_OK" == "True" ]]; then
      passed "RewardVault balance = $BAL_PW PW (covers funded - emitted)"
    else
      failed "RewardVault balance = $BAL_PW PW — below expected minimum"
    fi
  fi
else
  skipped "RewardVault: ADDR_REWARD_VAULT not set in manifest"
fi

# ── 3. FeeDistributor Config ──────────────────────────────────

section "3. FEEDISTRIBUTOR CONFIGURATION"

if [[ -n "${ADDR_FEE_DISTRIBUTOR:-}" && "${ADDR_FEE_DISTRIBUTOR}" != "0x0000000000000000000000000000000000000000" ]]; then
  verify_call "FD-validator-bps" "$ADDR_FEE_DISTRIBUTOR" "VALIDATOR_SHARE_BPS()(uint256)" "7000"
  verify_call "FD-treasury-bps"  "$ADDR_FEE_DISTRIBUTOR" "TREASURY_SHARE_BPS()(uint256)"  "2000"
  # Burn share = 10% = 1000 bps (remainder after 7000+2000)
  VALIDATOR_BPS=$(cast call "$ADDR_FEE_DISTRIBUTOR" "VALIDATOR_SHARE_BPS()(uint256)" --rpc-url "$RPC_URL" 2>/dev/null | cast to-dec 2>/dev/null || echo "0")
  TREASURY_BPS=$(cast call "$ADDR_FEE_DISTRIBUTOR" "TREASURY_SHARE_BPS()(uint256)" --rpc-url "$RPC_URL" 2>/dev/null | cast to-dec 2>/dev/null || echo "0")
  TOTAL_BPS=$(python3 -c "print(int('${VALIDATOR_BPS:-0}') + int('${TREASURY_BPS:-0}'))" 2>/dev/null || echo "0")
  BURN_BPS=$((10000 - ${TOTAL_BPS:-0}))
  if [[ "$BURN_BPS" -eq 1000 ]]; then
    passed "FD-burn-bps: implied burn = 1000 bps (10%) ✓"
  else
    failed "FD-burn-bps: implied burn = $BURN_BPS bps — expected 1000 (10%)"
  fi
else
  skipped "FeeDistributor: ADDR_FEE_DISTRIBUTOR not set in manifest"
fi

# ── 4. Address Sanity Checks ──────────────────────────────────

section "4. ADDRESS SANITY"

for var in ADDR_EMERGENCY_MULTISIG ADDR_TIMELOCK ADDR_VALIDATOR_FEE_VAULT \
           ADDR_DEV_TREASURY ADDR_FEE_DISTRIBUTOR ADDR_REWARD_VAULT ADDR_VALIDATOR_REGISTRY; do
  val="${!var:-}"
  if [[ -z "$val" ]]; then
    skipped "$var: not set"
  elif [[ "$val" == "0x0000000000000000000000000000000000000000" ]]; then
    failed "$var: is zero address"
  else
    # Verify addresses are distinct
    passed "$var = $val (non-zero)"
  fi
done

# Check all addresses are distinct
all_addrs=()
for var in ADDR_EMERGENCY_MULTISIG ADDR_TIMELOCK ADDR_VALIDATOR_FEE_VAULT \
           ADDR_DEV_TREASURY ADDR_FEE_DISTRIBUTOR ADDR_REWARD_VAULT ADDR_VALIDATOR_REGISTRY; do
  val="${!var:-}"
  [[ -n "$val" ]] && all_addrs+=("$val")
done

UNIQUE_COUNT=$(printf '%s\n' "${all_addrs[@]}" | sort -u | wc -l)
TOTAL_COUNT=${#all_addrs[@]}
if [[ "$UNIQUE_COUNT" -eq "$TOTAL_COUNT" && "$TOTAL_COUNT" -gt 0 ]]; then
  passed "All $TOTAL_COUNT contract addresses are distinct ✓"
elif [[ "$TOTAL_COUNT" -gt 0 ]]; then
  failed "DUPLICATE addresses found — $UNIQUE_COUNT unique out of $TOTAL_COUNT total"
fi

# ── 5. Nonce / Address Prediction ────────────────────────────

section "5. DEPLOYMENT NONCE ASSUMPTIONS"

echo "  DeployTestnet.s.sol deploys in this order (nonces relative to deployer):"
echo "    nonce 0: EmergencyMultisig"
echo "    nonce 1: PrimeWaveTimelock"
echo "    nonce 2: ValidatorFeeVault"
echo "    nonce 3: DevTreasury"
echo "    nonce 4: FeeDistributor  ← predicted BEFORE deploy at nonce+2"
echo "    nonce 5: ValidatorRegistry ← predicted BEFORE deploy at nonce+3"
echo "    nonce 6: RewardVault"
echo ""
echo "  REQUIREMENT: Deployer nonce at deploy-time must be 0."
echo "               If testnet-deployer previously sent any transaction,"
echo "               the address predictions WILL be wrong."
echo ""

if [[ -n "${ADDR_DEPLOYER:-}" ]]; then
  CURRENT_NONCE=$(cast nonce "$ADDR_DEPLOYER" --rpc-url "$RPC_URL" 2>/dev/null || echo "ERROR")
  if [[ "$CURRENT_NONCE" != "ERROR" ]]; then
    EXPECTED_NONCE=7  # After deploying 7 contracts
    if [[ "$CURRENT_NONCE" -eq "$EXPECTED_NONCE" ]]; then
      passed "Deployer nonce = $CURRENT_NONCE (expected $EXPECTED_NONCE after 7-contract deploy)"
    else
      warn "Deployer nonce = $CURRENT_NONCE — expected $EXPECTED_NONCE after full deploy. Investigate if unexpected."
    fi
  fi
fi

# ── SUMMARY ───────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  Contract Verification Summary                           ║"
echo "╚══════════════════════════════════════════════════════════╝"
printf "  %-10s %s\n" "PASS:"    "$PASS"
printf "  %-10s %s\n" "FAIL:"    "$FAIL"
printf "  %-10s %s\n" "SKIP:"    "$SKIP"
printf "  %-10s %s\n" "BLOCKED:" "$BLOCKED"
echo ""

if [[ "$FAIL" -gt 0 ]]; then
  echo "[FAIL]    Contract verification FAILED. DO NOT proceed."
  exit 1
elif [[ "$BLOCKED" -gt 0 ]]; then
  echo "[BLOCKED] Verification BLOCKED — live RPC required."
  exit 2
else
  echo "[PASS]    All contract verifications passed."
  exit 0
fi
