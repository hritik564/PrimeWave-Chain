#!/usr/bin/env bash
# PrimeWave C12 Indexer — local development startup only.
# Requires an isolated disposable development database and verified Chain ID 73571.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
NETWORK_STATE="local-data/network-state.env"
CONTRACTS_ENV="local-data/deployed-contracts.env"
EXPECTED_CHAIN_ID="73571"
SAFETY_HELPER="$REPO_ROOT/indexer/dist/startup-safety.js"

fail() {
    echo -e "${RED}[indexer] $1${NC}" >&2
    exit 1
}

# ── 1. Explicit development database gate ─────────────────────────────────────
[[ "${NODE_ENV:-}" != "production" ]] || fail "This startup script is development-only."
[[ -n "${INDEXER_DB_URL:-}" ]] || fail "INDEXER_DB_URL must explicitly identify the development database."
[[ "${INDEXER_DB_ENV:-}" == "development" &&
   "${INDEXER_DB_DISPOSABLE:-}" == "true" &&
   "${INDEXER_DB_ISOLATED:-}" == "true" ]] ||
    fail "Refusing startup without the development, disposable, and isolated database gates."
if [[ -n "${DATABASE_URL:-}" && "$INDEXER_DB_URL" == "$DATABASE_URL" ]]; then
    fail "INDEXER_DB_URL must be distinct from DATABASE_URL."
fi

# ── 2. Verify local RPC before any database connection, migration, or deploy ──
[[ -f "$NETWORK_STATE" ]] || fail "Missing local chain state; start and verify the local chain first."
# shellcheck source=/dev/null
source "$NETWORK_STATE"
RPC="${PRIMEWAVE_RPC_URL:-}"
[[ -n "$RPC" ]] || fail "No local RPC URL is recorded."

export INDEXER_RPC_URL="$RPC"
export INDEXER_CHAIN_ID="$EXPECTED_CHAIN_ID"

# A build has no database or RPC side effects and creates the preflight helper.
cd "$REPO_ROOT/indexer"
if [[ ! -f "dist/main.js" ]] ||
   [[ src/main.ts -nt dist/main.js ]] ||
   [[ src/startup-safety.ts -nt dist/startup-safety.js ]] ||
   [[ src/indexer/chain-reset-safety.ts -nt dist/indexer/chain-reset-safety.js ]] ||
   [[ ! -d "dist/db/migrations" ]]; then
    echo -e "${YELLOW}[indexer] Building indexer...${NC}"
    npm run build
fi
cd "$REPO_ROOT"

node "$SAFETY_HELPER" --preflight ||
    fail "Local RPC or database preflight failed; no deployment or DB operation was started."

# ── 3. Contract deployment is disabled unless explicitly opted in ─────────────
NEEDS_DEPLOY=false
if [[ ! -f "$CONTRACTS_ENV" ]]; then
    node "$SAFETY_HELPER" --auto-deploy-enabled ||
        fail "No contract record exists and deployment is disabled. Review and set INDEXER_AUTO_DEPLOY=true to opt in."
    NEEDS_DEPLOY=true
else
    # Preserve the address record on every failure; never auto-delete or replace it.
    # shellcheck source=/dev/null
    source "$CONTRACTS_ENV"
    FD="${ADDR_FEE_DISTRIBUTOR:-}"
    [[ -n "$FD" ]] || fail "deployed-contracts.env is incomplete; preserve it and review it manually."

    CODE=$(curl -fsS -X POST -H 'Content-Type: application/json' \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getCode\",\"params\":[\"$FD\",\"latest\"],\"id\":1}" \
        "$RPC" --max-time 5 2>/dev/null \
        | python3 -c "import sys,json; d=json.load(sys.stdin); c=d.get('result','0x'); print('ok' if isinstance(c,str) and len(c)>4 else 'no')" \
        2>/dev/null) || fail "Could not verify contract code; deployed-contracts.env was preserved."
    [[ "$CODE" == "ok" ]] ||
        fail "Recorded contract has no code on the verified chain; deployed-contracts.env was preserved for review."
fi

if [[ "$NEEDS_DEPLOY" == "true" ]]; then
    [[ -n "${DEV_PRIVATE_KEY_0:-}" ]] ||
        fail "Opt-in deployment also requires DEV_PRIVATE_KEY_0 to be configured through workspace secrets."

    echo -e "${YELLOW}[indexer] Explicit contract deployment opt-in is active.${NC}"
    export PATH="$REPO_ROOT/local-bin/foundry:$PATH"
    if ! forge script contracts/script/DevDeploy.s.sol \
        --rpc-url "$RPC" \
        --broadcast \
        --chain-id "$EXPECTED_CHAIN_ID"; then
        fail "Contract deployment failed. No address record was automatically removed."
    fi
    [[ -f "$CONTRACTS_ENV" ]] ||
        fail "Deployment returned without creating deployed-contracts.env; inspect the deployment output."
fi

# ── 4. Load addresses only after code verification or opted-in deployment ─────
# shellcheck source=/dev/null
source "$CONTRACTS_ENV"

# ── 5. Start the indexer ──────────────────────────────────────────────────────
export INDEXER_API_PORT="4000"
export INDEXER_POLL_MS="2000"
export INDEXER_BATCH_SIZE="50"
export INDEXER_CONFIRMATIONS="0"
export INDEXER_START_BLOCK="0"
export INDEXER_RETRY_DELAY_MS="3000"
export INDEXER_MAX_RETRIES="5"
export INDEXER_API_MAX_LIMIT="500"
export INDEXER_API_DEFAULT_LIMIT="25"
export LOG_LEVEL="info"

export ADDR_FEE_DISTRIBUTOR="${ADDR_FEE_DISTRIBUTOR:-}"
export ADDR_VALIDATOR_FEE_VAULT="${ADDR_VALIDATOR_FEE_VAULT:-}"
export ADDR_DEV_TREASURY="${ADDR_DEV_TREASURY:-}"
export ADDR_REWARD_VAULT="${ADDR_REWARD_VAULT:-}"
export ADDR_VALIDATOR_REGISTRY="${ADDR_VALIDATOR_REGISTRY:-}"
export ADDR_STAKING_MANAGER="${ADDR_STAKING_MANAGER:-}"
export ADDR_EMERGENCY_MULTISIG="${ADDR_EMERGENCY_MULTISIG:-}"
export ADDR_TIMELOCK="${ADDR_TIMELOCK:-}"

echo -e "${GREEN}[indexer] Starting verified Chain ID ${EXPECTED_CHAIN_ID} indexer on port 4000.${NC}"
cd "$REPO_ROOT/indexer"
exec node dist/main.js
