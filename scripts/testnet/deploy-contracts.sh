#!/usr/bin/env bash
# ============================================================
# PrimeWave Testnet — Contract Deployment
# Sprint PW-C14 | TESTNET ONLY
# ============================================================
# Deploys all 7 protocol contracts to the testnet and funds
# the RewardVault with exactly 15M PW.
#
# Prerequisites:
#   - Chain RPC accessible at $TESTNET_RPC_URL
#   - Deployer key set in $TESTNET_DEPLOYER_KEY
#   - Genesis alloc has funded deployer with >= 16M PW
#   - foundry toolchain (pinned v1.7.1)
#
# Usage:
#   TESTNET_RPC_URL=https://rpc.primewave-testnet.example.com \
#   TESTNET_DEPLOYER_KEY=0x... \
#   bash scripts/testnet/deploy-contracts.sh
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

export PATH="$REPO_ROOT/local-bin/foundry:$REPO_ROOT/local-bin:$PATH"

echo ""
echo "══ PrimeWave Testnet — Contract Deployment ══"
echo "  ENVIRONMENT:    TESTNET ONLY"
echo "  Foundry:        $(forge --version 2>/dev/null | head -1)"
echo "  RPC:            ${TESTNET_RPC_URL:?TESTNET_RPC_URL must be set}"
echo ""

# Verify chain ID
CHAIN_ID=$(cast chain-id --rpc-url "$TESTNET_RPC_URL" 2>/dev/null)
if [[ "$CHAIN_ID" != "77" ]]; then
  echo "[ERROR] Expected chain ID 77 (testnet), got: $CHAIN_ID"
  echo "        Refusing to deploy to wrong network."
  exit 1
fi
echo "[OK]    Chain ID verified: $CHAIN_ID"

# Verify deployer balance
DEPLOYER_ADDR=$(cast wallet address "$TESTNET_DEPLOYER_KEY")
BALANCE=$(cast balance "$DEPLOYER_ADDR" --rpc-url "$TESTNET_RPC_URL" --ether)
echo "[INFO]  Deployer: $DEPLOYER_ADDR"
echo "[INFO]  Balance:  $BALANCE PW"

OUTPUT_DIR="$REPO_ROOT/local-data/testnet-deployed-contracts.env"
mkdir -p "$(dirname "$OUTPUT_DIR")"

echo ""
echo "══ Deploying Protocol Contracts ══"
forge script "$REPO_ROOT/contracts/script/DeployTestnet.s.sol:DeployTestnet" \
  --rpc-url "$TESTNET_RPC_URL" \
  --private-key "$TESTNET_DEPLOYER_KEY" \
  --broadcast \
  --via-ir \
  -vvv

echo ""
if [[ -f "$OUTPUT_DIR" ]]; then
  echo "[OK]    Contract addresses written to: $OUTPUT_DIR"
  cat "$OUTPUT_DIR"
else
  echo "[WARN]  Expected $OUTPUT_DIR was not created — check DeployTestnet.s.sol output."
fi

echo ""
echo "══ Testnet Deployment Complete ══"
echo "  Run scripts/testnet/validate-testnet-genesis.sh to verify invariants."
