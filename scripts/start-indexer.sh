#!/usr/bin/env bash
# PrimeWave C12 Indexer — Replit Workflow Startup Script
# =======================================================
# Waits for the local chain, deploys protocol contracts if not already
# deployed, then starts the C12 indexer + REST API on port 4000.
#
# Replit workflow command:
#   bash scripts/start-indexer.sh
#
# Prerequisites (start these workflows first):
#   1. Chain workflow (scripts/start-chain.sh)
#   2. PostgreSQL is available via DATABASE_URL (Replit managed DB)
#
# ENVIRONMENT: LOCAL DEVELOPMENT ONLY

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

NETWORK_STATE="local-data/network-state.env"
CONTRACTS_ENV="local-data/deployed-contracts.env"

# ── 1. Wait for chain ─────────────────────────────────────────────────────────
echo -e "${YELLOW}[indexer] Waiting for PrimeWave chain RPC...${NC}"
PRIMEWAVE_RPC_URL=""
MAX_ATTEMPTS=30  # 30 × 3s = 90s
for i in $(seq 1 $MAX_ATTEMPTS); do
    if [[ -f "$NETWORK_STATE" ]]; then
        # shellcheck source=/dev/null
        source "$NETWORK_STATE"
        RPC="${PRIMEWAVE_RPC_URL:-}"
        if [[ -n "$RPC" ]]; then
            OK=$(curl -sf -X POST -H 'Content-Type: application/json' \
                -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
                "$RPC" --max-time 3 2>/dev/null \
                | python3 -c "import sys,json; d=json.load(sys.stdin); print('ok' if 'result' in d else '')" \
                2>/dev/null || echo "")
            if [[ "$OK" == "ok" ]]; then
                echo -e "${GREEN}[indexer] Chain ready: $RPC${NC}"
                break
            fi
        fi
    fi
    if [[ $i -eq $MAX_ATTEMPTS ]]; then
        echo -e "${RED}[indexer] Chain not ready after 90s. Start the chain workflow first.${NC}"
        exit 1
    fi
    echo "[indexer] Waiting for chain... ($i/$MAX_ATTEMPTS)"
    sleep 3
done

# ── 2. Deploy contracts if needed ─────────────────────────────────────────────
NEEDS_DEPLOY=false

if [[ ! -f "$CONTRACTS_ENV" ]]; then
    echo -e "${YELLOW}[indexer] No deployed-contracts.env — will deploy contracts.${NC}"
    NEEDS_DEPLOY=true
else
    # Verify contracts are actually deployed on-chain (chain may have been reset)
    # shellcheck source=/dev/null
    source "$CONTRACTS_ENV"
    FD="${ADDR_FEE_DISTRIBUTOR:-}"
    if [[ -z "$FD" ]]; then
        NEEDS_DEPLOY=true
        echo -e "${YELLOW}[indexer] ADDR_FEE_DISTRIBUTOR missing — will re-deploy.${NC}"
    else
        CODE=$(curl -sf -X POST -H 'Content-Type: application/json' \
            -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getCode\",\"params\":[\"$FD\",\"latest\"],\"id\":1}" \
            "$PRIMEWAVE_RPC_URL" --max-time 5 2>/dev/null \
            | python3 -c "import sys,json; d=json.load(sys.stdin); c=d.get('result','0x'); print('ok' if len(c)>4 else 'no')" \
            2>/dev/null || echo "no")
        if [[ "$CODE" != "ok" ]]; then
            echo -e "${YELLOW}[indexer] Contracts not found on-chain (chain may have been reset) — will re-deploy.${NC}"
            rm -f "$CONTRACTS_ENV"
            NEEDS_DEPLOY=true
        fi
    fi
fi

if [[ "$NEEDS_DEPLOY" == "true" ]]; then
    echo -e "${YELLOW}[indexer] Deploying protocol contracts via DevDeploy.s.sol...${NC}"
    export PATH="$REPO_ROOT/local-bin/foundry:$PATH"
    export DEV_PRIVATE_KEY_0="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

    if ! forge script contracts/script/DevDeploy.s.sol \
        --rpc-url "$PRIMEWAVE_RPC_URL" \
        --broadcast \
        --chain-id 73571 2>&1; then
        echo -e "${RED}[indexer] Contract deployment failed. Check forge output above.${NC}"
        exit 1
    fi

    if [[ ! -f "$CONTRACTS_ENV" ]]; then
        echo -e "${RED}[indexer] deployed-contracts.env was not created — DevDeploy likely failed.${NC}"
        exit 1
    fi
    echo -e "${GREEN}[indexer] Contracts deployed successfully.${NC}"
fi

# ── 3. Load contract addresses ────────────────────────────────────────────────
# shellcheck source=/dev/null
source "$CONTRACTS_ENV"
echo -e "${GREEN}[indexer] Contract addresses loaded:${NC}"
echo "  FeeDistributor    : ${ADDR_FEE_DISTRIBUTOR:-<not set>}"
echo "  ValidatorFeeVault : ${ADDR_VALIDATOR_FEE_VAULT:-<not set>}"
echo "  DevTreasury       : ${ADDR_DEV_TREASURY:-<not set>}"
echo "  RewardVault       : ${ADDR_REWARD_VAULT:-<not set>}"
echo "  ValidatorRegistry : ${ADDR_VALIDATOR_REGISTRY:-<not set>}"
echo "  EmergencyMultisig : ${ADDR_EMERGENCY_MULTISIG:-<not set>}"
echo "  Timelock          : ${ADDR_TIMELOCK:-<not set>}"

# ── 4. Build indexer if needed ────────────────────────────────────────────────
cd "$REPO_ROOT/indexer"
if [[ ! -f "dist/main.js" ]] || [[ src/main.ts -nt dist/main.js ]] || [[ ! -d "dist/db/migrations" ]]; then
    echo -e "${YELLOW}[indexer] Building C12 indexer...${NC}"
    npm run build
    echo -e "${GREEN}[indexer] Build complete.${NC}"
fi

# ── 5. Start indexer ──────────────────────────────────────────────────────────
echo -e "${GREEN}[indexer] Starting C12 indexer on port 4000...${NC}"

export INDEXER_RPC_URL="$PRIMEWAVE_RPC_URL"
export INDEXER_DB_URL="${DATABASE_URL:-postgresql://postgres:password@helium/heliumdb?sslmode=disable}"
export INDEXER_CHAIN_ID="73571"
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

exec node dist/main.js
