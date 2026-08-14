---
name: PW-C04 Validator Fee Vault Accounting
description: Reward-index model, integration test quirks, standalone node start pattern for C04 and beyond
---

## Status: COMPLETE ✅

Sprint C04 delivered: ValidatorFeeVault with per-validator fee accounting proven on live primewavedev chain.

---

## Reward-Index Model — Key Implementation Notes

`accFeePerWeight` scaled by 1e18. Must checkpoint (update `pendingReward` + reset `rewardDebt = accFeePerWeight`) before ANY operation that changes a validator's effective weight:
- `deactivateValidator` — checkpoint BEFORE setting `active = false` and removing weight
- `activateValidator` — sets `rewardDebt = accFeePerWeight` (no retro-accrual)
- `setUptimeBips` / `setBaseWeight` — compute old effective weight BEFORE updating the field, then subtract old and add new

**Why:** If you read `effectiveWeight` after changing the field, you get the new value. Old EW must be computed first.

---

## Solidity Gotcha: Struct Getter Returns Tuple, Not Struct

`mapping(bytes32 => ValidatorInfo) public validators` generates a getter that returns a **tuple**, not a struct object. You CANNOT do `vault.validators(id).active` — it won't compile. Must destructure: `(,,,bool active,,,) = vault.validators(id)`.

**Why:** Solidity ABI encoding of public mappings to structs returns positional tuples.

---

## Foundry Invariant Test API

The struct for `targetSelector()` is `FuzzSelector`, not `FuzzArtifact`. In forge-std:
```solidity
targetSelector(FuzzSelector({ addr: address(handler), selectors: selectors }));
```

---

## --via-ir Required for Integration Script

The `IntegrationC04.s.sol` script has enough local variables in `run()` to hit the stack depth limit. Must use `--via-ir` with `forge script`. Add to the command:
```
forge script ... --via-ir
```

Do NOT add `via_ir = true` to `foundry.toml` — it slows down all test compilation.

---

## Live Chain Integration Test: Fees Cannot Be Redirected Mid-Chain

The genesis has the **C03 FeeDistributor address** hardcoded as `rewardAddress`. Any new FeeDistributor deployed at a higher nonce does NOT receive chain fees. The integration test must either:
1. **Send ETH directly to the vault from DEV0** (simulates FeeDistributor.distribute() → vault.receive()), OR
2. Reset the chain state (changes blockchain ID)

Option 1 is correct for C04. It exercises all vault logic on-chain without touching genesis.

**Why:** AvalancheGo AddBalance() goes to the genesis `rewardAddress` only. No runtime reconfiguration.

---

## Standalone Node Start Pattern (C04+)

The node directory has a `flags.json` with multi-node bootstrap config from initial deploy. Must patch before each start:
1. `bootstrap-ids = ""`
2. `bootstrap-ips = ""`
3. `sybil-protection-enabled = false`
4. `partial-sync-primary-network = false`
5. `track-subnets = <SUBNET_ID>`
6. Add `chain-config-content` entry for our blockchain ID with full eth-apis

THEN build start command from patched flags.json and nohup it. The `start-local.sh` script does this automatically, but inline scripts must replicate the logic.

Wait loop: do NOT check for HTTP 200 alone — the P-Chain server starts first and returns 200 before the EVM chain is ready. Wait for `eth_blockNumber` to return a result starting with `0x`.

Also: block 0 (genesis) is a valid block number. Do NOT treat block 0 as "not ready". Check for empty/error response instead.

**Why:** The node serves P-Chain API immediately but subnet-evm takes ~1-2s more to load and respond to EVM calls.

---

## Test Counts Summary (C04)

- Unit: 60 tests
- Stateful invariant: 8 invariants × 128,000 handler calls
- Fuzz: 6 × 256 runs
- Integration: 18 on-chain assertions
- C03 regression: 39 tests (all still pass)
- Total: 113 unit/fuzz/invariant, all PASS

---

## C03 Test Update Required

`contracts/test/FeeDistributorUnit.t.sol` had `test_vaultEmitsEvent` referencing the old `ValidatorFeeReceived` event. Updated to `FeeReceived(amount, newAccFeePerWeight, totalEffectiveWeight)`. When no validators are registered (as in the C03 test harness), `totalEffectiveWeight == 0` so fees go to unallocated and accFeePerWeight stays 0.
