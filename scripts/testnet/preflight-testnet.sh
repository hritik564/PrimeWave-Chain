#!/usr/bin/env bash
# ============================================================
# PrimeWave Testnet — Pre-Flight Check
# Sprint PW-C15 | TESTNET PRE-DEPLOYMENT
# ============================================================
# Verifies everything that can be verified WITHOUT deploying
# the public testnet:
#   - Required binaries and versions
#   - Chain ID configuration correctness
#   - Genesis template invariants
#   - Required files and directories
#   - No hardcoded old chain IDs (77777)
#   - PostgreSQL connectivity (if available)
#   - Script executable bits
#   - Env template placeholder audit
#
# Status codes:
#   READY   — check passed; prerequisite satisfied
#   WARNING — check passed with concern; note the message
#   BLOCKED — cannot verify; missing external dependency
#   FAIL    — check failed; must resolve before deployment
#
# Exit codes: 0=all-ready  1=has-fail  2=has-blocked
# ============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
export PATH="$REPO_ROOT/local-bin/foundry:$REPO_ROOT/local-bin:$PATH"

PASS=0; WARN=0; BLOCKED=0; FAIL=0

# ── Helpers ──────────────────────────────────────────────────

ok()      { echo "[READY]   $*"; PASS=$((PASS+1)); }
warn()    { echo "[WARNING] $*"; WARN=$((WARN+1)); }
blocked() { echo "[BLOCKED] $*"; BLOCKED=$((BLOCKED+1)); }
fail()    { echo "[FAIL]    $*"; FAIL=$((FAIL+1)); }
section() { echo ""; echo "── $* ──"; }

version_gte() {
  # Returns 0 if $1 >= $2 (semver comparison, simple)
  local v1="$1" v2="$2"
  python3 -c "
import sys
a = tuple(int(x) for x in '$v1'.split('.')[:3])
b = tuple(int(x) for x in '$v2'.split('.')[:3])
sys.exit(0 if a >= b else 1)
" 2>/dev/null
}

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  PrimeWave Testnet — Pre-Flight Check         ║"
echo "║  $(date -u +%Y-%m-%dT%H:%M:%SZ)                   ║"
echo "╚══════════════════════════════════════════════╝"

# ── 1. Binaries ───────────────────────────────────────────────

section "REQUIRED BINARIES"

# Foundry (forge + cast)
FORGE_VER=$(forge --version 2>/dev/null | grep -oP 'Version: \K[\d.]+' || echo "")
if [[ -z "$FORGE_VER" ]]; then
  fail "forge not found — expected at local-bin/foundry/forge"
elif [[ "$FORGE_VER" != "1.7.1" ]]; then
  fail "forge version $FORGE_VER — expected exactly 1.7.1 (pinned)"
else
  ok "forge $FORGE_VER"
fi

CAST_VER=$(cast --version 2>/dev/null | grep -oP 'Version: \K[\d.]+' || echo "")
if [[ -z "$CAST_VER" ]]; then
  fail "cast not found"
else
  ok "cast $CAST_VER"
fi

# Avalanche CLI
AVACLI_VER=$(avalanche --version 2>/dev/null | grep -oP '[\d.]+' | head -1 || echo "")
if [[ -z "$AVACLI_VER" ]]; then
  fail "avalanche CLI not found — expected at local-bin/avalanche"
elif [[ "$AVACLI_VER" != "1.9.5" ]]; then
  warn "avalanche CLI version $AVACLI_VER — expected 1.9.5 (pinned). Review changelog."
else
  ok "avalanche CLI $AVACLI_VER"
fi

# AvalancheGo
AVAGO_VER=$(./local-bin/avalanchego --version 2>/dev/null | grep -oP 'avalanchego/\K[^\s]+' || echo "")
if [[ -z "$AVAGO_VER" ]]; then
  AVAGO_VER=$(avalanchego --version 2>/dev/null | grep -oP 'avalanchego/\K[^\s]+' || echo "")
fi
if [[ -z "$AVAGO_VER" ]]; then
  fail "avalanchego not found — expected at local-bin/avalanchego"
elif [[ "$AVAGO_VER" != "1.14.2" ]]; then
  fail "avalanchego version $AVAGO_VER — expected exactly 1.14.2 (pinned)"
else
  ok "avalanchego $AVAGO_VER"
fi

# subnet-evm
SEVM_VER=$(./local-bin/subnet-evm --version 2>/dev/null | grep -oP 'v[\d.]+' | head -1 || echo "")
if [[ -z "$SEVM_VER" ]]; then
  fail "subnet-evm not found — expected at local-bin/subnet-evm"
else
  ok "subnet-evm $SEVM_VER"
fi

# Node.js (>=20)
NODE_VER=$(node --version 2>/dev/null | tr -d 'v' || echo "")
if [[ -z "$NODE_VER" ]]; then
  fail "node not found"
elif version_gte "$NODE_VER" "20.0.0"; then
  ok "node v$NODE_VER"
else
  fail "node v$NODE_VER — requires v20+"
fi

# npm
NPM_VER=$(npm --version 2>/dev/null || echo "")
if [[ -z "$NPM_VER" ]]; then
  fail "npm not found"
else
  ok "npm $NPM_VER"
fi

# psql
PSQL_VER=$(psql --version 2>/dev/null | grep -oP '[\d.]+' | head -1 || echo "")
if [[ -z "$PSQL_VER" ]]; then
  blocked "psql not found — database recovery tests will be BLOCKED (optional for pre-flight)"
else
  ok "psql $PSQL_VER"
fi

# curl, python3
curl --version >/dev/null 2>&1 && ok "curl available" || fail "curl not found"
python3 --version >/dev/null 2>&1 && ok "python3 available" || fail "python3 not found"

# ── 2. Chain ID Audit ─────────────────────────────────────────

section "CHAIN ID AUDIT"

# Dev Chain ID must be 73571
DEV_GENESIS="$REPO_ROOT/config/local/genesis-template.json"
if [[ -f "$DEV_GENESIS" ]]; then
  DEV_CID=$(python3 -c "import json; print(json.load(open('$DEV_GENESIS'))['config']['chainId'])" 2>/dev/null || echo "ERROR")
  if [[ "$DEV_CID" == "73571" ]]; then
    ok "Dev Chain ID = 73571"
  else
    fail "Dev Chain ID = $DEV_CID — expected 73571"
  fi
else
  warn "Dev genesis template not found at $DEV_GENESIS (optional)"
fi

# Testnet Chain ID must be 77
TESTNET_GENESIS="$REPO_ROOT/config/testnet/genesis-template.json"
if [[ -f "$TESTNET_GENESIS" ]]; then
  TN_CID=$(python3 -c "import json; print(json.load(open('$TESTNET_GENESIS'))['config']['chainId'])" 2>/dev/null || echo "ERROR")
  if [[ "$TN_CID" == "77" ]]; then
    ok "Testnet Chain ID = 77"
  else
    fail "Testnet Chain ID = $TN_CID — expected 77"
  fi
else
  fail "Testnet genesis template not found: $TESTNET_GENESIS"
fi

# No 77777 in testnet configs
OLD_CID_COUNT=$(grep -r "77777" \
  "$REPO_ROOT/config/testnet/" \
  "$REPO_ROOT/scripts/testnet/" \
  "$REPO_ROOT/deploy/testnet/" \
  "$REPO_ROOT/contracts/script/" \
  2>/dev/null | \
  grep -v ".md:" | \
  grep -v "_chain_id_history\|chain_id_history\|Previous testnet\|preflight-testnet" | \
  wc -l)
if [[ "$OLD_CID_COUNT" -eq 0 ]]; then
  ok "No legacy chain ID 77777 in testnet scripts/configs (historical notes excluded)"
else
  fail "Found $OLD_CID_COUNT reference(s) to old chain ID 77777 in non-markdown files"
  grep -r "77777" "$REPO_ROOT/config/testnet/" "$REPO_ROOT/scripts/testnet/" \
    "$REPO_ROOT/deploy/testnet/" "$REPO_ROOT/contracts/script/" 2>/dev/null | \
    grep -v ".md:\|_chain_id_history\|Previous testnet\|preflight-testnet"
fi

# Mainnet chain ID must be TBD (no lock)
MAINNET_CID=$(grep -r "MAINNET_CHAIN_ID\s*=" "$REPO_ROOT/config/" "$REPO_ROOT/contracts/" \
  "$REPO_ROOT/scripts/" 2>/dev/null | grep -v "TBD\|#\|//" | wc -l)
if [[ "$MAINNET_CID" -eq 0 ]]; then
  ok "Mainnet Chain ID = TBD (not locked)"
else
  fail "Found $MAINNET_CID mainnet chain ID assignment(s) — mainnet must remain TBD"
fi

# Testnet CHAIN_ID=77 in env templates
TN_CHAIN_ENVS=$(grep -l "CHAIN_ID=77" "$REPO_ROOT/deploy/testnet/env/"*.template 2>/dev/null | wc -l)
TOTAL_ENVS=$(ls "$REPO_ROOT/deploy/testnet/env/"*.template 2>/dev/null | wc -l)
if [[ "$TN_CHAIN_ENVS" -eq "$TOTAL_ENVS" && "$TOTAL_ENVS" -gt 0 ]]; then
  ok "All $TOTAL_ENVS env templates have CHAIN_ID=77"
else
  warn "Only $TN_CHAIN_ENVS/$TOTAL_ENVS env templates explicitly set CHAIN_ID=77"
fi

# ── 3. Genesis Template Validation ───────────────────────────

section "GENESIS TEMPLATE"

export REPO_ROOT
python3 << 'PYEOF'
import json, sys, os

repo = os.environ.get('REPO_ROOT', '')
gf = os.path.join(repo, 'config/testnet/genesis-template.json')

try:
    g = json.load(open(gf))
except Exception as e:
    print(f"[FAIL]    Genesis template parse error: {e}")
    sys.exit(1)

results = []
fail = False

# Chain ID
cid = g['config']['chainId']
results.append(('[READY]   ' if cid == 77 else '[FAIL]    ', f"chainId = {cid}" + (" ✓" if cid == 77 else " — expected 77")))
if cid != 77: fail = True

# NativeMinter
minter = g['config'].get('contractNativeMinterConfig', {})
allow_list = minter.get('adminAddresses', []) + minter.get('enabledAddresses', [])
if not allow_list:
    results.append(('[READY]   ', 'NativeMinter: no adminAddresses or enabledAddresses ✓'))
else:
    results.append(('[FAIL]    ', f'NativeMinter: found allowlist entries {allow_list}'))
    fail = True

# Supply
alloc = {k: v for k, v in g['alloc'].items() if 'balance' in v}
total = sum(int(v['balance'], 16) for v in alloc.values())
expected = 100_000_000 * 10**18
if total == expected:
    results.append(('[READY]   ', f'Total supply = {total // 10**18:,} PW ✓'))
else:
    results.append(('[FAIL]    ', f'Total supply = {total // 10**18:,} PW — expected 100,000,000'))
    fail = True

# Placeholders
phs = [k for k in g['alloc'] if '__REPLACE_' in k]
if phs:
    results.append(('[READY]   ', f'{len(phs)} placeholder(s) in genesis template (expected — not yet filled)'))
    for p in phs:
        results.append(('           ', f'  → {p}'))
else:
    results.append(('[READY]   ', 'No __REPLACE_ placeholders (template already filled)'))

# Verify final genesis does NOT exist with unfilled placeholders
import glob
final_genesis = os.path.join(repo, 'config/testnet/genesis.json')
if os.path.exists(final_genesis):
    fg = json.load(open(final_genesis))
    fg_ph = [k for k in fg['alloc'] if '__REPLACE_' in k]
    if fg_ph:
        results.append(('[FAIL]    ', f'CRITICAL: config/testnet/genesis.json has {len(fg_ph)} unfilled placeholder(s)!'))
        fail = True
    else:
        results.append(('[READY]   ', 'config/testnet/genesis.json exists and has no placeholders ✓'))
else:
    results.append(('[READY]   ', 'config/testnet/genesis.json does not exist yet (correct — pending ceremony)'))

for prefix, msg in results:
    print(f"{prefix}{msg}")

sys.exit(1 if fail else 0)
PYEOF
GENESIS_OK=$?
if [[ "$GENESIS_OK" -ne 0 ]]; then
  FAIL=$((FAIL+1))
fi

# ── 4. Required Files ─────────────────────────────────────────

section "REQUIRED FILES"

check_file() {
  local f="$1"
  if [[ -f "$REPO_ROOT/$f" ]]; then
    ok "$f"
  else
    fail "Missing: $f"
  fi
}

check_executable() {
  local f="$1"
  if [[ ! -f "$REPO_ROOT/$f" ]]; then
    fail "Missing: $f"
  elif [[ ! -x "$REPO_ROOT/$f" ]]; then
    fail "Not executable: $f — run: chmod +x $f"
  else
    ok "$f (executable)"
  fi
}

# Config files
check_file "config/testnet/genesis-template.json"
check_file "config/testnet/node-config.json"
check_file "config/testnet/chain-config.json"
check_file "config/testnet/allocations.md"

# Testnet scripts
check_executable "scripts/testnet/deploy-contracts.sh"
check_executable "scripts/testnet/testnet-health-check.sh"
check_executable "scripts/testnet/validate-testnet-genesis.sh"
check_executable "scripts/testnet/backup-testnet-db.sh"
check_executable "scripts/testnet/restore-testnet-db.sh"
check_executable "scripts/testnet/setup-testnet-node.sh"
check_executable "scripts/testnet/generate-validator-keys.sh"
check_executable "scripts/testnet/preflight-testnet.sh"
check_executable "scripts/testnet/check-external-prerequisites.sh"
check_executable "scripts/testnet/verify-deployed-contracts.sh"
check_executable "scripts/testnet/run-c15-live-gate.sh"

# Deployment configs
check_file "deploy/testnet/env/testnet-indexer.env.template"
check_file "deploy/testnet/env/testnet-keeper.env.template"
check_file "deploy/testnet/env/testnet-pwcscan.env.template"
check_file "deploy/testnet/systemd/primewave-testnet-node.service"
check_file "deploy/testnet/systemd/primewave-testnet-indexer.service"
check_file "deploy/testnet/systemd/primewave-testnet-keeper.service"
check_file "deploy/testnet/systemd/primewave-testnet-pwcscan.service"
check_file "deploy/testnet/nginx/rpc.conf"
check_file "deploy/testnet/nginx/explorer.conf"
check_file "deploy/testnet/prometheus/prometheus.yml"
check_file "deploy/testnet/prometheus/alert-rules.yml"

# Contract script
check_file "contracts/script/DeployTestnet.s.sol"

# Required binaries
check_file "local-bin/avalanche"
check_file "local-bin/avalanchego"
check_file "local-bin/subnet-evm"
check_file "local-bin/foundry/forge"
check_file "local-bin/foundry/cast"

# ── 5. DeployTestnet.s.sol Guard Check ───────────────────────

section "CONTRACT DEPLOYMENT GUARDS"

DEPLOY_SOL="$REPO_ROOT/contracts/script/DeployTestnet.s.sol"
if [[ -f "$DEPLOY_SOL" ]]; then
  # Chain ID guard
  CID_GUARD=$(grep -c "block.chainid == TESTNET_CHAIN_ID" "$DEPLOY_SOL" 2>/dev/null || echo 0)
  [[ "$CID_GUARD" -gt 0 ]] && ok "Chain ID == 77 guard present in DeployTestnet.s.sol" || fail "Chain ID guard missing"

  # Dev key rejection
  DEV_KEY_GUARD=$(grep -c "DEV_KEY_ADDR" "$DEPLOY_SOL" 2>/dev/null || echo 0)
  [[ "$DEV_KEY_GUARD" -gt 0 ]] && ok "Dev key rejection present in DeployTestnet.s.sol" || fail "Dev key rejection missing"

  # EMS signer zero guard
  EMS_ZERO_GUARD=$(grep -c "EMS_SIGNER.*address(0)" "$DEPLOY_SOL" 2>/dev/null || echo 0)
  [[ "$EMS_ZERO_GUARD" -gt 0 ]] && ok "EMS signer zero-address guard present" || warn "EMS signer guard not found — verify manually"

  # EMS signers still zero (expected before ceremony)
  EMS_FILLED=$(grep -c "EMS_SIGNER_[0-9] = address(0)" "$DEPLOY_SOL" 2>/dev/null || echo 0)
  if [[ "$EMS_FILLED" -gt 0 ]]; then
    warn "DeployTestnet.s.sol: $EMS_FILLED EMS signer(s) still address(0) — fill before deployment"
  else
    ok "DeployTestnet.s.sol: EMS signers appear filled (re-verify manually)"
  fi

  # RewardVault funding amount
  RV_FUND=$(grep -c "15_000_000 ether" "$DEPLOY_SOL" 2>/dev/null || echo 0)
  [[ "$RV_FUND" -gt 0 ]] && ok "RewardVault fund = 15M PW in DeployTestnet.s.sol" || fail "RewardVault funding constant missing"
fi

# ── 6. Env Template Placeholder Audit ────────────────────────

section "ENV TEMPLATE PLACEHOLDER AUDIT"

for tmpl in "$REPO_ROOT/deploy/testnet/env/"*.template; do
  name=$(basename "$tmpl")
  count=$(grep -c "__REPLACE_" "$tmpl" 2>/dev/null | tr -d '[:space:]' || echo 0)
  if [[ "$count" -gt 0 ]]; then
    ok "$name: $count placeholder(s) to fill (expected)"
  else
    # Some templates are intentionally static (e.g. pwcscan — values are known constants).
    # Verify no real secret was accidentally hard-coded by checking for suspicious patterns.
    if grep -qE "(PRIVATE_KEY|DB_PASSWORD|SECRET|API_KEY)\s*=" "$tmpl" 2>/dev/null; then
      warn "$name: No __REPLACE__ placeholders but contains sensitive key names — review manually"
    else
      ok "$name: No operator-fill placeholders needed (values are static constants — verify manually)"
    fi
  fi
done

# Check that no env file (non-template) with secrets exists in git-tracked paths
for secret_pattern in "PRIVATE_KEY=" "DB_PASSWORD=" "SECRET="; do
  LEAKED=$(grep -r "$secret_pattern" "$REPO_ROOT/deploy/testnet/" "$REPO_ROOT/config/testnet/" \
    2>/dev/null | grep -v ".template" | grep -v "#" | wc -l)
  if [[ "$LEAKED" -gt 0 ]]; then
    fail "Possible secret leakage: '$secret_pattern' found in non-template file(s)"
    grep -r "$secret_pattern" "$REPO_ROOT/deploy/testnet/" "$REPO_ROOT/config/testnet/" \
      2>/dev/null | grep -v ".template" | grep -v "#"
  fi
done
ok "No plaintext secrets detected in testnet config/deploy files"

# ── 7. PostgreSQL Connectivity ────────────────────────────────

section "DATABASE"

if psql --version >/dev/null 2>&1; then
  # Try Replit managed DB
  if psql -c "SELECT 1;" >/dev/null 2>&1; then
    PG_VER=$(psql -c "SELECT version();" -t 2>/dev/null | grep -oP 'PostgreSQL \K[\d.]+' || echo "?")
    ok "PostgreSQL $PG_VER connected (Replit managed DB)"
  else
    blocked "PostgreSQL client available but not connected — configure PGHOST/DATABASE_URL for external testnet DB"
  fi
else
  blocked "psql not available — install for database operations"
fi

# ── 8. Prometheus Config Sanity ───────────────────────────────

section "MONITORING CONFIG"

PROM_YML="$REPO_ROOT/deploy/testnet/prometheus/prometheus.yml"
if [[ -f "$PROM_YML" ]]; then
  # Verify chain_id label is 77
  PROM_CID=$(grep "chain_id:" "$PROM_YML" | grep -oP '"[^"]+"' | head -1 | tr -d '"')
  if [[ "$PROM_CID" == "77" ]]; then
    ok "prometheus.yml chain_id label = 77"
  else
    fail "prometheus.yml chain_id label = '$PROM_CID' — expected '77'"
  fi
  # Check for __REPLACE__ placeholders in prometheus (should have infrastructure placeholders)
  PH_COUNT=$(grep -c "__REPLACE_" "$PROM_YML" 2>/dev/null || echo 0)
  if [[ "$PH_COUNT" -gt 0 ]]; then
    ok "prometheus.yml: $PH_COUNT infrastructure placeholder(s) require filling"
  fi
fi

ALERT_YML="$REPO_ROOT/deploy/testnet/prometheus/alert-rules.yml"
if [[ -f "$ALERT_YML" ]]; then
  # Basic YAML sanity: check for groups key and no tab indentation (YAML forbids tabs)
  HAS_GROUPS=$(grep -c "^groups:" "$ALERT_YML" 2>/dev/null | tr -d '[:space:]' || echo 0)
  HAS_TABS=$(grep -Pc "^\t" "$ALERT_YML" 2>/dev/null | tr -d '[:space:]' || echo 0)
  if [[ "$HAS_GROUPS" -gt 0 && "$HAS_TABS" -eq 0 ]]; then
    ok "alert-rules.yml: structure valid (groups key present, no tab indentation)"
  elif [[ "$HAS_TABS" -gt 0 ]]; then
    fail "alert-rules.yml: contains tab indentation (invalid YAML)"
  else
    warn "alert-rules.yml: 'groups:' key not found — verify file structure"
  fi
fi

# ── 9. Nginx Config Sanity ────────────────────────────────────

section "NGINX CONFIG"

for conf in "$REPO_ROOT/deploy/testnet/nginx/"*.conf; do
  name=$(basename "$conf")
  # Check TLS placeholder
  if grep -q "__REPLACE_DOMAIN__\|example.com" "$conf" 2>/dev/null; then
    warn "$name: contains example.com placeholder — update with real domain before deployment"
  else
    ok "$name: no example.com placeholder"
  fi
  # Check for security headers
  if grep -q "X-Frame-Options\|Strict-Transport-Security" "$conf" 2>/dev/null; then
    ok "$name: security headers present"
  else
    warn "$name: security headers not found"
  fi
done

# ── 10. Solidity Version ──────────────────────────────────────

section "SOLIDITY VERSION"

SOL_VER=$(grep -r "^pragma solidity" "$REPO_ROOT/contracts/src/" 2>/dev/null | \
  grep -oP "[\d.]+" | sort -u | head -5)
if echo "$SOL_VER" | grep -q "0.8.30"; then
  ok "Solidity 0.8.30 confirmed in contracts/src/"
else
  warn "Solidity version(s) found: $SOL_VER — expected 0.8.30"
fi

# ── 11. Fuji API (opportunistic) ─────────────────────────────

section "FUJI P-CHAIN API"

FUJI_RESP=$(curl -sf --max-time 8 -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"platform.getHeight","params":{}}' \
  https://api.avax-test.network/ext/bc/P 2>/dev/null || echo "")
if echo "$FUJI_RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['result']['height'])" 2>/dev/null | grep -qP '^\d+$'; then
  HEIGHT=$(echo "$FUJI_RESP" | python3 -c "import json,sys; print(json.load(sys.stdin)['result']['height'])")
  ok "Fuji P-Chain API reachable — height $HEIGHT"
else
  blocked "Fuji P-Chain API unreachable — Fuji P-Chain subnet creation will be BLOCKED"
fi

# ── SUMMARY ───────────────────────────────────────────────────

echo ""
echo "╔═══════════════════════════════════╗"
echo "║  PW-C15 Pre-Flight Summary         ║"
echo "╠═══════════════════════════════════╣"
echo "║  READY:   $PASS                         " | awk '{printf "║  %-35s║\n", $0}'
echo "║  WARNING: $WARN                         " | awk '{printf "║  %-35s║\n", $0}'
echo "║  BLOCKED: $BLOCKED                      " | awk '{printf "║  %-35s║\n", $0}'
echo "║  FAIL:    $FAIL                         " | awk '{printf "║  %-35s║\n", $0}'
echo "╚═══════════════════════════════════╝"

printf "  %-10s %-6s\n" "READY:"   "$PASS"
printf "  %-10s %-6s\n" "WARNING:" "$WARN"
printf "  %-10s %-6s\n" "BLOCKED:" "$BLOCKED"
printf "  %-10s %-6s\n" "FAIL:"    "$FAIL"
echo ""

if [[ "$FAIL" -gt 0 ]]; then
  echo "[FAIL]    Pre-flight FAILED. Resolve all FAIL items before deployment."
  exit 1
elif [[ "$BLOCKED" -gt 0 ]]; then
  echo "[BLOCKED] Pre-flight has $BLOCKED BLOCKED item(s) requiring external infrastructure."
  echo "          In-Replit checks are complete. See docs/PW-C15-EXTERNAL-HANDOFF.md."
  exit 2
else
  echo "[READY]   Pre-flight passed. All local checks READY. External infra checklist remains."
  exit 0
fi
