# PW-C03 Final Report — FeeDistributor + 70/20/10 Native PW Proof

**Sprint:** PW-C03  
**Date:** 2026-08-14  
**Status:** ✅ COMPLETE — All objectives met

---

## Objective

Implement and prove the PrimeWave Chain fee distribution system on a live sovereign EVM L1:

- Deploy `ValidatorFeeVault`, `DevTreasury`, and `FeeDistributor` contracts at deterministic addresses
- Configure the Avalanche subnet genesis so all transaction fees route to `FeeDistributor`
- Prove on-chain that `distribute()` splits accumulated fees **70% / 20% / 10%** exactly
- Enforce immutable compile-time constants; no admin functions; no NativeMinter

---

## Deliverables

### Contracts

| File | Description |
|---|---|
| `contracts/src/ValidatorFeeVault.sol` | Receives 70% of fees; tracks `totalReceived`; no withdrawal |
| `contracts/src/DevTreasury.sol` | Receives 20% of fees; tracks `totalReceived`; no governance |
| `contracts/src/FeeDistributor.sol` | Permissionless `distribute()`; 70/20/10 split; CEI + ReentrancyGuard |

### Tests

| File | Tests | Result |
|---|---|---|
| `contracts/test/FeeDistributorUnit.t.sol` | 25 unit tests | ✅ PASS |
| `contracts/test/FeeDistributorInvariant.t.sol` | 14 fuzz tests (256 runs each) | ✅ PASS |
| Integration (live chain) | 1 end-to-end proof | ✅ PASS |

### Scripts & Genesis

| File | Change |
|---|---|
| `contracts/script/DeployC03.s.sol` | Forge deployment script; nonce-based address verification |
| `chain/genesis/dev-genesis.json` | Added `rewardManagerConfig.initialRewardConfig.rewardAddress = FeeDistributor` |
| `local-data/network-state.env` | Updated with C03 blockchain ID |

### Documentation

| File | Description |
|---|---|
| `docs/PW-C03-FEEDISTRIBUTOR_SPEC.md` | Full specification: fee loop, rounding, access control |
| `docs/PW-C03-TEST-REPORT.md` | All test results with detailed per-test breakdown |
| `docs/PW-C03-FINAL-REPORT.md` | This document |

---

## Contract Architecture

```
Avalanche L1 (primewavedev, chain 73571)
│
│  Every transaction's gas fee
│  (baseFee + priorityFee × gasUsed)
│         │
│         ▼  [genesis rewardManagerConfig]
│  ┌──────────────────────────────┐
│  │     FeeDistributor           │
│  │  0x9fE...a6e0  (nonce 2)    │
│  │                              │
│  │  distribute() — permissionless
│  │  ┌────────────────────────┐  │
│  │  │ 70% → ValidatorFeeVault│  │
│  │  │ 20% → DevTreasury      │  │
│  │  │ rem → 0x000…dEaD (burn)│  │
│  │  └────────────────────────┘  │
│  └──────────────────────────────┘
│         │         │         │
│         ▼         ▼         ▼
│  ValidatorFeeVault  DevTreasury  0xdead
│  0x5FbDB…0aa3      0xe7f17…0512  (burn)
│  (nonce 0)         (nonce 1)
```

---

## Deployed Contract Addresses (Local Dev)

| Contract | Address |
|---|---|
| `ValidatorFeeVault` | `0x5FbDB2315678afecb367f032d93F642f64180aa3` |
| `DevTreasury` | `0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512` |
| `FeeDistributor` | `0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0` |
| Genesis `rewardAddress` | `0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0` |
| Burn address | `0x000000000000000000000000000000000000dEaD` |

---

## Network Parameters (C03)

| Parameter | Value |
|---|---|
| Chain name | `primewavedev` |
| Chain ID | `73571` |
| Blockchain ID | `2F3BHmNJWP4DNaBbMFQog3TvfcF6GRY7PX99r7Xzae4cRwAv6a` |
| Subnet ID | `2W9boARgCWL25z6pMFNtkCfNA5v28VGg9PmBgUJfuKndEdhrvw` |
| RPC | `http://127.0.0.1:9656/ext/bc/2F3BHmNJWP4DNaBbMFQog3TvfcF6GRY7PX99r7Xzae4cRwAv6a/rpc` |

> **Note:** The blockchain ID changed from PW-C02 because modifying genesis (`rewardManagerConfig`) changes the CreateChainTx hash on the P-Chain, which is the blockchain ID.

---

## Live Chain Proof — 70/20/10 Distribution

**Input:** `25,279,550,001,011,182 wei` (from deploy + 10 transfer TXs)

| Recipient | Formula | Expected | Actual | Match |
|---|---|---|---|---|
| `ValidatorFeeVault` | `floor(input × 7000 / 10000)` | `17,695,685,000,707,827` | `17,695,685,000,707,827` | ✅ |
| `DevTreasury` | `floor(input × 2000 / 10000)` | `5,055,910,000,202,236` | `5,055,910,000,202,236` | ✅ |
| `Burn / 0xdead` | `input − validator − treasury` | `2,527,955,000,101,119` | `2,527,955,000,101,119` | ✅ |
| **Conservation** | `v + t + b = input` | `25,279,550,001,011,182` | `25,279,550,001,011,182` | ✅ |

**distribute() TX:** `0x7830e0057728b61baf5f10f5a8235045aedb844d88414b511a502ee3ee4128c4`

---

## Design Decisions Carried Forward from Spec

| Decision | Implementation |
|---|---|
| Immutable 70/20/10 | `VALIDATOR_BPS = 7000`, `TREASURY_BPS = 2000` as `uint256 constant` |
| Rounding | Floor for validator and treasury; burn gets exact remainder — no dust |
| Burn address | `0x000…dEaD` (widely accepted inaccessibility standard) |
| CEI pattern | Balance zeroed (via `pendingDistribution` internal) before transfers |
| ReentrancyGuard | OpenZeppelin-compatible non-reentrant modifier |
| No admin | No owner, no `onlyOwner`, no withdrawal, no upgradeable proxy |
| Permissionless | Any EOA or contract can call `distribute()` |
| NativeMinter OFF | Confirmed absent from genesis precompile config |

---

## Known Limitations (Deferred to Future Sprints)

| Limitation | Notes |
|---|---|
| Validator distribution logic | ValidatorFeeVault holds 70% as a pool; per-validator split is PW-C04+ |
| Governance | Treasury has no governance; multisig/timelock is PW-C05+ |
| Fee withdrawal | ValidatorFeeVault has no withdrawal — intentional for this sprint |
| Mainnet genesis | This is the local dev genesis; mainnet genesis is a separate gate |
| Formal verification | Out of scope; property-based fuzz tests are the current level of assurance |

---

## Toolchain

| Tool | Version | Notes |
|---|---|---|
| Foundry (forge, cast) | v1.7.1 | Workspace-bundled at `local-bin/foundry/`; NOT `~/.foundry/bin/` |
| AvalancheGo | v1.14.2 | |
| Avalanche CLI | v1.9.5 | |
| subnet-evm | custom build | Copied to `local-bin/subnet-evm` and plugin dir |
| Solidity | 0.8.30 | |

**Important:** Use `forge script` (not `forge create`) for deployment. Foundry v1.7.1 has a bug in `--constructor-args` parsing for single-address constructors that returns "Constructor argument count mismatch: expected 1 but got 3" with exit code 0, resulting in no deployment.

---

## How to Reproduce (Local Dev)

```bash
cd /path/to/workspace
export PATH="$PWD/local-bin/foundry:$PWD/local-bin:$PATH"
export DEV_PRIVATE_KEY_0="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

# 1. Run unit/fuzz tests
forge test -vv

# 2. Start local node (blockchain ID: 2F3BHmNJWP4...a6e0)
#    (Kill any stale: pkill -9 -x avalanchego)
bash /tmp/pw-node.sh &   # rebuild from flags.json first

# 3. Deploy contracts (nonce must be 0)
forge script contracts/script/DeployC03.s.sol:DeployC03 \
    --rpc-url http://127.0.0.1:9656/ext/bc/2F3BHmNJWP4DNaBbMFQog3TvfcF6GRY7PX99r7Xzae4cRwAv6a/rpc \
    --broadcast --legacy

# 4. Send transactions
cast send 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 --value 1ether \
    --rpc-url <RPC> --private-key $DEV_PRIVATE_KEY_0 --legacy

# 5. Distribute
cast send 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0 "distribute()" \
    --rpc-url <RPC> --private-key $DEV_PRIVATE_KEY_0 --legacy
```

---

## C03 Gate: PASSED ✅

All criteria met:
- [x] FeeDistributor, ValidatorFeeVault, DevTreasury contracts written and compile
- [x] 39/39 unit + fuzz tests pass
- [x] Contracts deploy at pre-computed addresses (nonce-based)
- [x] Genesis routes fees to FeeDistributor via `rewardManagerConfig`
- [x] 70/20/10 split proven on live PrimeWave Chain (end-to-end integration test)
- [x] Conservation invariant holds (no dust)
- [x] NativeMinter absent
- [x] No admin/withdrawal functions

**Ready for PW-C04 (pending explicit user approval).**
