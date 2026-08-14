# PW-C03 Test Report — FeeDistributor + 70/20/10 Native PW Proof

**Sprint:** PW-C03  
**Date:** 2026-08-14  
**Status:** ✅ ALL TESTS PASS

---

## 1. Unit Tests (forge test)

**Result:** 39/39 PASS

| Suite | Tests | Result |
|---|---|---|
| `FeeDistributorUnit.t.sol` | 25 | ✅ PASS |
| `FeeDistributorInvariant.t.sol` | 14 (fuzz) | ✅ PASS |
| **Total** | **39** | **✅ PASS** |

Run command (from workspace root):
```
forge test -vv
```

### Unit Test Coverage (FeeDistributorUnit.t.sol — 25 tests)

| Test | Description |
|---|---|
| `test_SplitsCorrectly_SmallAmount` | 1000 wei → exact floor split |
| `test_SplitsCorrectly_OneWei` | 1 wei → vault 0, treasury 0, burn 1 (remainder) |
| `test_SplitsCorrectly_ExactBps` | 10000 wei → vault 7000, treasury 2000, burn 1000 |
| `test_SplitsCorrectly_LargeAmount` | 1 ether → exact floor split |
| `test_Distribute_CorrectBalances` | End-to-end balance verification |
| `test_Distribute_EmitsEvent` | `FeesDistributed` event emitted with correct values |
| `test_Distribute_UpdatesCounters` | Accumulator state variables updated correctly |
| `test_Distribute_ZeroBalance` | Reverts on zero balance |
| `test_Distribute_ReentrantGuard` | Reentrancy blocked via `ReentrancyGuard` |
| `test_Distribute_MultipleCalls` | Accumulates correctly across multiple calls |
| `test_VaultAddress` | Constructor assigns vault correctly |
| `test_TreasuryAddress` | Constructor assigns treasury correctly |
| `test_BurnAddress` | `BURN_ADDRESS` == `0x000…dEaD` |
| `test_ValidatorBps` | `VALIDATOR_BPS` == 7000 |
| `test_TreasuryBps` | `TREASURY_BPS` == 2000 |
| `test_BurnIsRemainder` | burn = amount - floor(70%) - floor(20%) |
| `test_NoDust` | v + t + b == amount for all inputs |
| `test_Conservation_Powers` | conservation holds at 1, 1e9, 1e18 wei |
| `test_VaultReceivesFunds` | vault balance increases by exactly 70% |
| `test_TreasuryReceivesFunds` | treasury balance increases by exactly 20% |
| `test_BurnReceivesFunds` | 0xdead balance increases by remainder |
| `test_VaultTotalReceived` | `ValidatorFeeVault.totalReceived` updated |
| `test_TreasuryTotalReceived` | `DevTreasury.totalReceived` updated |
| `test_PendingDistribution` | `pendingDistribution()` view function |
| `test_DeployedAddresses` | All 3 addresses match pre-computed values |

### Fuzz / Invariant Tests (FeeDistributorInvariant.t.sol — 14 tests, 256 runs each)

| Invariant | Description |
|---|---|
| `I1_Conservation` | v + t + b == amount for all random inputs |
| `I2_ValidatorFloor` | validator share == floor(amount × 7000 / 10000) |
| `I3_TreasuryFloor` | treasury share == floor(amount × 2000 / 10000) |
| `I4_BurnIsRemainder` | burn == amount - validator - treasury |
| `I5_NoDust` | No wei ever lost |
| `I6_ValidatorGe70Pct` | validator ≥ 70% always (floor rounds down, so = 70%) |
| `I7_TreasuryGe20Pct` | treasury ≥ 20% always (floor rounds down) |
| `I8_BurnGe10Pct_Minus1` | burn ≥ 10% - 1 (rounding cannot lose more than 1 wei) |
| `I9_CountersMatchTransfers` | accounting counters == sum of all actual transfers |
| `I10_OnlyFeeDistributorSends` | vault and treasury only receive from FeeDistributor |
| `I11_NoWithdrawal` | No withdrawal function on vault or treasury |
| `I12_PermissionlessDistribute` | Any caller can call distribute() |
| `I13_ZeroReverts` | distribute() reverts when balance == 0 |
| `I14_ReentrancyBlocked` | reentrancy cannot drain extra funds |

---

## 2. Integration Test — 70/20/10 Live Chain Proof

**Result:** ✅ PASS

### Test Environment

| Parameter | Value |
|---|---|
| Chain name | `primewavedev` |
| Chain ID | `73571` |
| Blockchain ID | `2F3BHmNJWP4DNaBbMFQog3TvfcF6GRY7PX99r7Xzae4cRwAv6a` |
| Subnet ID | `2W9boARgCWL25z6pMFNtkCfNA5v28VGg9PmBgUJfuKndEdhrvw` |
| RPC URL | `http://127.0.0.1:9656/ext/bc/2F3BHmNJWP4DNaBbMFQog3TvfcF6GRY7PX99r7Xzae4cRwAv6a/rpc` |
| DEV0 (deployer) | `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` |
| Foundry version | v1.7.1 (workspace-bundled at `local-bin/foundry/`) |

### Deployed Contract Addresses

| Contract | Address | Match Expected? |
|---|---|---|
| `ValidatorFeeVault` (nonce 0) | `0x5FbDB2315678afecb367f032d93F642f64180aa3` | ✅ Yes |
| `DevTreasury` (nonce 1) | `0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512` | ✅ Yes |
| `FeeDistributor` (nonce 2) | `0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0` | ✅ Yes |

**Genesis `rewardAddress` == `FeeDistributor` address ✅**

### Fee Accumulation (Deploy + 10 Transactions)

Fees were routed to FeeDistributor automatically via the `rewardManagerConfig` genesis field:
- Fees from 3 deployment transactions
- Fees from 10 transfer transactions (DEV0 → DEV1, 1 PW each, `--legacy` gas = 21,000 gas × 25 gwei)

| Item | Value |
|---|---|
| FeeDistributor balance (from deploy fees) | `20,029,550,000,801,182 wei` |
| 10 tx fees accumulated | `5,250,000,000,210,000 wei` |
| **Total input to distribute()** | **`25,279,550,001,011,182 wei`** |

### distribute() Results

| Recipient | Expected | Actual | Match |
|---|---|---|---|
| `ValidatorFeeVault` (70% floor) | `17,695,685,000,707,827` wei | `17,695,685,000,707,827` wei | ✅ |
| `DevTreasury` (20% floor) | `5,055,910,000,202,236` wei | `5,055,910,000,202,236` wei | ✅ |
| `Burn / 0xdead` (remainder) | `2,527,955,000,101,119` wei | `2,527,955,000,101,119` wei | ✅ |
| **Conservation (v+t+b = input)** | `25,279,550,001,011,182` | `25,279,550,001,011,182` | ✅ |

**distribute() TX:** `0x7830e0057728b61baf5f10f5a8235045aedb844d88414b511a502ee3ee4128c4`

### Final Contract State

| Variable | Value |
|---|---|
| `FeeDistributor.totalDistributed` | `25,279,550,001,011,182 wei` |
| `FeeDistributor.totalValidatorShare` | `17,695,685,000,707,827 wei` |
| `FeeDistributor.totalTreasuryShare` | `5,055,910,000,202,236 wei` |
| `FeeDistributor.totalBurnShare` | `2,527,955,000,101,119 wei` |
| `ValidatorFeeVault.totalReceived` | `17,695,685,000,707,827 wei` |
| `DevTreasury.totalReceived` | `5,055,910,000,202,236 wei` |

---

## 3. Deployment Artifacts

Broadcast file: `broadcast/DeployC03.s.sol/73571/run-latest.json`

---

## 4. Notable Observations

### Blockchain ID Changed After Genesis Modification
When `rewardManagerConfig` was added to `dev-genesis.json`, the blockchain ID computed by the P-Chain changed:
- **Before (PW-C02):** `yNRRcwqYaWqn9g4XcAiNe7DufgEHqpF2mmvcG6go1cRvtZo4S`
- **After (PW-C03):** `2F3BHmNJWP4DNaBbMFQog3TvfcF6GRY7PX99r7Xzae4cRwAv6a`

This is expected: the CreateChainTx hash on the P-Chain incorporates genesis bytes, so modifying genesis changes the blockchain ID.

### forge create vs forge script
`forge create` with `--constructor-args` had a parsing bug in Foundry v1.7.1 (returned "Constructor argument count mismatch: expected 1 but got 3"). Switched to `forge script` (`DeployC03.s.sol`) which deployed correctly.

### Fee Routing Without Explicit RewardManager Activation
The `rewardManagerConfig` genesis field with `allowFeeRecipients: true` and `rewardAddress: 0x9fE...a6e0` was sufficient to route all transaction fees to FeeDistributor. The RewardManager precompile at `0x020...004` returned a minimal code blob (as expected for a precompile — not an EVM contract), but fees flowed correctly.

---

## Summary

| Test Category | Count | Result |
|---|---|---|
| Unit tests | 25 | ✅ PASS |
| Fuzz / invariant tests | 14 (×256 runs) | ✅ PASS |
| Integration test | 1 (end-to-end) | ✅ PASS |
| **TOTAL** | **39+1** | **✅ ALL PASS** |
