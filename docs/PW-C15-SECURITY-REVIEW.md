# PW-C15 — SECURITY REVIEW

**Sprint:** PW-C15 — Testnet Battle Test + Mainnet Readiness
**Status:** PROCEDURE READY — PENDING EXTERNAL EXECUTION
**Environment:** TESTNET ONLY — Chain ID 77

This document covers the security attack testing required by C15 §25, mapping each
scenario from the C10 security test suite to the live testnet where applicable.
All tests use testnet credentials only. No real malicious credentials outside testnet.

---

## 1. SCOPE

| In scope | Out of scope |
|---|---|
| Smart contract security (testnet) | Mainnet contract attacks |
| Keeper compromise simulation | Real key theft |
| Governance boundary testing | External infrastructure penetration |
| RPC security | DNS hijacking (except controlled simulation) |
| Validator impersonation | Real validator keys |

---

## 2. ACCESS CONTROL TESTS

### 2.1 Unauthorized Admin

```bash
# Attempt admin functions from non-admin address
ATTACKER=$(cast wallet new | grep "Address:" | awk '{print $2}')

# Try to call pause() on FeeDistributor from non-admin
cast send $FEE_DISTRIBUTOR "pause()" \
  --from $ATTACKER \
  --rpc-url $TESTNET_RPC \
  --private-key $ATTACKER_PK 2>&1
# Expected: REVERTS with "AccessControl: account is missing role"
```

| Test | Expected | Actual |
|---|---|---|
| Non-admin calls pause() | REVERTS | TBD |
| Non-admin calls setWeight() | REVERTS | TBD |
| Non-admin calls updateRate() | REVERTS | TBD |
| Non-admin calls emergencyWithdraw() | REVERTS | TBD |

### 2.2 Malicious Validator

```bash
# Attempt to register a fake validator without P-Chain backing
# (Warp message would fail verification)
cast send $VALIDATOR_MANAGER "completeValidatorRegistration(uint32)" 0 \
  --from $ATTACKER \
  --rpc-url $TESTNET_RPC \
  --private-key $ATTACKER_PK 2>&1
# Expected: REVERTS — Warp message verification required
```

| Test | Expected | Actual |
|---|---|---|
| Fake validator registration | REVERTS (no Warp) | TBD |
| Fake Warp message | REVERTS (sig check) | TBD |
| Impersonate existing validator | REVERTS | TBD |

### 2.3 Weight Manipulation

```bash
# Attempt to set validator weight from non-keeper, non-admin
cast send $VALIDATOR_REGISTRY "setWeight(bytes32,uint64)" $NODE_ID_BYTES32 9999 \
  --from $ATTACKER \
  --private-key $ATTACKER_PK \
  --rpc-url $TESTNET_RPC 2>&1
# Expected: REVERTS — only keeper/admin role may call setWeight
```

---

## 3. REWARD AND FEE THEFT TESTS

### 3.1 Reward Theft

```bash
# Attacker tries to claim rewards for a validator they do not control
cast send $REWARD_VAULT "claim(bytes32)" $VICTIM_NODE_ID_BYTES32 \
  --from $ATTACKER \
  --private-key $ATTACKER_PK \
  --rpc-url $TESTNET_RPC 2>&1
# Expected: REVERTS — only registered reward address may claim
```

| Test | Expected | Actual |
|---|---|---|
| Claim other validator's rewards | REVERTS | TBD |
| Claim with wrong reward address | REVERTS | TBD |
| Double claim same epoch | REVERTS (already claimed) | TBD |

### 3.2 Fee Theft

```bash
# Attempt to drain ValidatorFeeVault from non-admin
cast send $VALIDATOR_FEE_VAULT "withdraw(address,uint256)" \
  $ATTACKER 999999999999999999 \
  --from $ATTACKER \
  --private-key $ATTACKER_PK \
  --rpc-url $TESTNET_RPC 2>&1
# Expected: REVERTS — no unauthorized withdrawal path
```

---

## 4. GOVERNANCE BOUNDARY TESTS

### 4.1 Governance Bypass Attempt

```bash
# Try to execute a timelocked action before the delay
cast send $TIMELOCK "execute(address,uint256,bytes,bytes32,bytes32)" \
  $TARGET 0 $CALLDATA $PREDECESSOR $SALT \
  --from $ATTACKER \
  --private-key $ATTACKER_PK \
  --rpc-url $TESTNET_RPC 2>&1
# Expected: REVERTS — TimelockController: operation is not ready
```

### 4.2 EmergencyMultisig: Insufficient Approvals

```bash
# 2-of-5 pause attempt (need 3)
cast send $EMERGENCY_MULTISIG "submitTransaction(address,uint256,bytes)" \
  $FEE_DISTRIBUTOR 0 "0x8456cb59" \
  --from $SIGNER_1 --private-key $SIGNER_1_PK --rpc-url $TESTNET_RPC

PAUSE_TX_HASH=$(...)
cast send $EMERGENCY_MULTISIG "confirmTransaction(bytes32)" $PAUSE_TX_HASH \
  --from $SIGNER_2 --private-key $SIGNER_2_PK --rpc-url $TESTNET_RPC

# Do NOT confirm from SIGNER_3 — attempt execution with only 2 confirmations
cast send $EMERGENCY_MULTISIG "executeTransaction(bytes32)" $PAUSE_TX_HASH \
  --from $SIGNER_1 --private-key $SIGNER_1_PK --rpc-url $TESTNET_RPC 2>&1
# Expected: REVERTS — insufficient confirmations
```

### 4.3 Replay Attack

```bash
# After a tx is executed, attempt to re-execute with same params
cast send $TIMELOCK "execute(address,uint256,bytes,bytes32,bytes32)" \
  $TARGET 0 $CALLDATA $PREDECESSOR $SALT \
  --rpc-url $TESTNET_RPC 2>&1
# Expected: REVERTS — operation already executed
```

| Test | Expected | Actual |
|---|---|---|
| Timelock before delay | REVERTS | TBD |
| Only 2-of-5 signatures | REVERTS | TBD |
| Unauthorized signer | REVERTS | TBD |
| Replay executed tx | REVERTS | TBD |
| Expired/cancelled op | REVERTS | TBD |
| Emergency powers exceed scope | REVERTS | TBD |

---

## 5. ICM / WARP SECURITY

### 5.1 Duplicate Sync Attack

```bash
# Attempt to replay a Warp registration message
# (ICM relayer must deduplicate by message ID)
# Submit the same message twice — second should be rejected
```

| Test | Expected | Actual |
|---|---|---|
| Duplicate Warp message | Rejected (already processed) | TBD |
| Forged Warp signature | REVERTS (signature verification fails) | TBD |
| Wrong source chain Warp | REVERTS (wrong sourceChainID) | TBD |

---

## 6. KEEPER COMPROMISE SIMULATION

```bash
# Simulate keeper key compromise: attacker obtains keeper private key
# Can attacker steal funds via keeper role?

# Attempt: call syncValidator with malicious weight
cast send $VALIDATOR_REGISTRY "setWeight(bytes32,uint64)" $NODE_ID 0 \
  --from $KEEPER_ADDR \
  --private-key $KEEPER_PK \
  --rpc-url $TESTNET_RPC

# This succeeds (keeper has setWeight authority)
# But check: can keeper withdraw from ValidatorFeeVault?
cast send $VALIDATOR_FEE_VAULT "withdraw(address,uint256)" $ATTACKER 1e18 \
  --from $KEEPER_ADDR \
  --private-key $KEEPER_PK \
  --rpc-url $TESTNET_RPC 2>&1
# Expected: REVERTS — keeper role does not include withdrawal authority
```

**Analysis:** Keeper compromise risks:
- Can zero-out validator weights → validators stop earning fees (DoS, not theft)
- Cannot withdraw from vault (no withdrawal authority)
- Cannot mint tokens (NativeMinter disabled)
- Cannot bypass governance

**Mitigation:** Rotate keeper key immediately on suspected compromise. Emergency pause via multisig if needed.

---

## 7. RPC SECURITY

### 7.1 Admin Method Exposure Scan

```bash
METHODS=(
  "admin_peers" "admin_addPeer" "admin_removePeer"
  "debug_traceTransaction" "debug_traceBlock"
  "personal_listAccounts" "personal_unlockAccount"
  "miner_start" "miner_stop"
  "txpool_content"
)

for method in "${METHODS[@]}"; do
  RESULT=$(curl -sf -X POST -H 'Content-Type: application/json' \
    --data "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":[],\"id\":1}" \
    https://rpc.testnet.primewave.xyz | jq -r '.error.code // .result // "no_response"')
  echo "$method: $RESULT"
  # All must return error or be absent — never return data
done
```

### 7.2 Path Traversal / Injection

```bash
# Test for path traversal in any HTTP endpoints
curl -sf https://rpc.testnet.primewave.xyz/../../../etc/passwd
# Expected: 404 or connection refused

# Test SQL injection in indexer API (if exposed)
curl -sf "https://explorer.testnet.primewave.xyz/api/blocks?limit=1;DROP%20TABLE%20blocks;--"
# Expected: error or sanitized response — not SQL execution
```

---

## 8. FINDINGS LOG

> Fill during and after live testnet security testing.

| ID | Category | Severity | Description | Status | Resolution |
|---|---|---|---|---|---|
| SEC-01 | — | — | — | 🔵 PENDING | — |

**Severity levels:** Critical / High / Medium / Low / Informational

**STOP conditions:**
- Any Critical finding → immediately halt and report
- Any High finding → halt, investigate, fix before proceeding to C16

---

## 9. SECURITY REVIEW SUMMARY

| Domain | Tests | Pass | Fail | Critical/High | Status |
|---|---|---|---|---|---|
| Access control | TBD | TBD | TBD | TBD | 🔵 |
| Reward/fee theft | TBD | TBD | TBD | TBD | 🔵 |
| Governance | TBD | TBD | TBD | TBD | 🔵 |
| ICM/Warp | TBD | TBD | TBD | TBD | 🔵 |
| Keeper compromise | TBD | TBD | TBD | TBD | 🔵 |
| RPC security | TBD | TBD | TBD | TBD | 🔵 |

**Acceptance for C16 entry:** Zero Critical findings, zero High findings (or all remediated).
