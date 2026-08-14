# PW-C11: Deployment Rehearsal Guide

**Sprint:** C11 — Production Infrastructure + Validator Keeper + Genesis Finalization
**Status:** COMPLETE
**Date:** 2026-08-14

---

## Purpose

The rehearsal validates the complete production deployment procedure using local Foundry (Anvil) or Fuji testnet — without touching mainnet. It MUST be run at least once before the production ceremony.

**Objective:** Confirm that `IntegrationC11.s.sol` runs green (0 FAIL) end-to-end.

---

## 1. Prerequisites

```bash
# Foundry installed and Forge working
forge --version   # must be v1.7.1+

# Node.js 22 LTS (for keeper tests)
node --version    # v22.x.x

# pnpm
pnpm --version    # 9.x+

# AvalancheGo (for full rehearsal — can be skipped for contract-only rehearsal)
avalanchego --version  # v1.14.2
```

---

## 2. Contract-Only Rehearsal (Recommended First)

### 2.1 Start Anvil

```bash
# Start a fresh Anvil with default accounts
anvil --chain-id 31337 --block-time 2 &
ANVIL_RPC="http://127.0.0.1:8545"
```

### 2.2 Run IntegrationC11.s.sol

```bash
cd contracts/

forge script script/IntegrationC11.s.sol:IntegrationC11Script \
  --rpc-url $ANVIL_RPC \
  --broadcast \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  -vvv 2>&1 | tee /tmp/rehearsal-output.txt
```

### 2.3 Expected Output

```
====================================================
 PrimeWave Chain C11 - Production Rehearsal
====================================================

[SECTION] STEPS 01-05: Pre-flight Checks
  [PASS] Step 1: Chain ID check          (31337 — local dev, expected)
  [PASS] Step 2: ENV flag check          (rehearsal mode)
  [PASS] Step 3: Foundry version         (v1.7.1)
  [PASS] Step 4: AvalancheGo version pin (documented: v1.14.2)
  [PASS] Step 5: OZ version pin          (5.6.1)

[SECTION] STEPS 06-13: Contract Deployment
  [PASS] Step 6:  EmergencyMultisig deployed
  [PASS] Step 7:  PrimeWaveTimelock deployed
  [PASS] Step 8:  EmergencyMultisig threshold = 3
  [PASS] Step 9:  Timelock MIN_DELAY = 172800 (48h)
  [PASS] Step 10: Pause controllers set
  [PASS] Step 11: Fee infrastructure deployed
  [PASS] Step 12: Fee split verified (70/20/10)
  [PASS] Step 13: ValidatorRegistry deployed
  [PASS] Step 14: RewardVault deployed

[SECTION] STEPS 14-16: RewardVault Funding (15M PW - OPTION B)
  [PASS] Step 15: RewardVault funded (15,000,000 PW)
  [PASS] Step 16: Funding invariant (totalFunded == 15M PW)

[SECTION] STEPS 17-22: Genesis Invariants
  [PASS] Step 17: NativeMinter disabled
  [PASS] Step 18: Fee split locked (70/20/10 BPS)
  [PASS] Step 19: EMS threshold = 3
  [PASS] Step 20: Timelock MIN_DELAY = 172800
  [PASS] Step 21: RewardVault solvency (emitted <= funded)
  [PASS] Step 22: Supply ceiling (no mint function)

[SECTION] STEPS 23-27: Fee Routing Verification
  [PASS] Step 23: FeeDistributor routing links
  [PASS] Step 24: Fee distribution 70/20/10 splits
  [PASS] Step 25: FeeDistributor balance drains to zero
  [PASS] Step 26: totalDistributed accounting correct
  [PASS] Step 27: Burn address received funds

[SECTION] STEPS 28-30: Final Gate
  [PASS] Step 28: All contract addresses non-zero
  [PASS] Step 29: Zero FAIL checks
  [PASS] Step 30: Rehearsal complete

====================================================
 REHEARSAL RESULT: 30/30 PASS, 0 FAIL
====================================================
```

**Any FAIL = stop. Fix the issue before proceeding to production.**

---

## 3. ValidateGenesis Script

After running IntegrationC11, also run the dedicated genesis validator:

```bash
cd contracts/

# Set contract addresses from IntegrationC11 output
export DIST_ADDRESS="0x..."        # from Step 11 output
export VAULT_ADDRESS="0x..."       # from Step 11 output
export TREASURY_ADDRESS="0x..."    # from Step 11 output
export RV_ADDRESS="0x..."          # from Step 14 output
export EMS_ADDRESS="0x..."         # from Step 6 output
export TIMELOCK_ADDRESS="0x..."    # from Step 7 output
export CHAIN_RPC_URL=$ANVIL_RPC

forge script script/ValidateGenesis.s.sol \
  --rpc-url $CHAIN_RPC_URL \
  --sig "run()" \
  -vvv
# Must complete with 0 FAIL
```

---

## 4. Keeper Service Rehearsal

```bash
cd keeper/
pnpm install
pnpm build
pnpm test

# Expected: 20/20 tests pass (17 keeper + 3 state store)
```

Optionally run keeper against Anvil:

```bash
export KEEPER_RPC_URL=$ANVIL_RPC
export KEEPER_CHAIN_ID=31337
export KEEPER_REGISTRY_ADDRESS="0x..."  # from rehearsal output
export KEEPER_VALIDATOR_MANAGER_ADDRESS="0x..."
export KEEPER_PRIVATE_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
export KEEPER_POLL_INTERVAL_MS=5000

node dist/keeper.js &

# Health check
curl http://localhost:8080/health
# Expected: {"status":"healthy",...}
```

---

## 5. Shell Script Rehearsal

```bash
# All scripts must be executable
chmod +x scripts/*.sh

# Health check (against Anvil)
export CHAIN_RPC_URL=$ANVIL_RPC
export AVAGO_API_URL="http://127.0.0.1:9650"  # may warn — expected
./scripts/health-check.sh

# Validate genesis
export DIST_ADDRESS="0x..."
./scripts/validate-production-genesis.sh
# Chain ID will warn (31337 != 73571) — expected in rehearsal
```

---

## 6. Full Network Rehearsal (With AvalancheGo)

Run a complete local PrimeWave Chain for end-to-end validation:

```bash
# 1. Start local AvalancheGo devnet
avalanchego --network-id=local --http-host=127.0.0.1 &

# 2. Create a local subnet and blockchain
#    (Use AvalancheCLI for this)
avalanche subnet create primewavedev
avalanche subnet deploy primewavedev --local

# 3. Set BLOCKCHAIN_ID from CLI output
export PRIMEWAVE_BLOCKCHAIN_ID="..."
export CHAIN_RPC_URL="http://127.0.0.1:9656/ext/bc/$PRIMEWAVE_BLOCKCHAIN_ID/rpc"

# 4. Deploy contracts to local subnet
forge script script/IntegrationC11.s.sol:IntegrationC11Script \
  --rpc-url $CHAIN_RPC_URL \
  --broadcast \
  --private-key $DEPLOYER_KEY \
  -vvv

# 5. Start keeper
node dist/keeper.js

# 6. Run genesis validation
./scripts/validate-production-genesis.sh

# 7. Run health check
./scripts/health-check.sh
```

---

## 7. Rehearsal Acceptance Criteria

The rehearsal PASSES only when ALL of the following are true:

- [ ] `IntegrationC11.s.sol` completes with 30/30 PASS, 0 FAIL
- [ ] `ValidateGenesis.s.sol` completes with 0 FAIL
- [ ] `forge test` shows ≥ 745 tests passing (C00–C10 regression) + C11 additions
- [ ] `keeper/pnpm test` shows 20/20 PASS
- [ ] `scripts/health-check.sh` exits 0 (on live node)
- [ ] `scripts/validate-production-genesis.sh` exits 0

**Gate:** The production ceremony MUST NOT begin until the rehearsal passes completely.

---

## 8. Rehearsal Failure Procedures

| Failure | Action |
|---------|--------|
| IntegrationC11 FAIL | Debug Solidity error, fix contract or deployment script, re-run |
| ValidateGenesis FAIL | Check which invariant failed, fix source of truth |
| Keeper test FAIL | Fix TypeScript, re-run `pnpm test` |
| Health check FAIL | Check node logs, resolve before rehearsal is complete |
| Address prediction mismatch | Check deployment order in IntegrationC11.s.sol, fix nonce calculations |

**All failures must be resolved and re-run before signing off on the rehearsal.**
