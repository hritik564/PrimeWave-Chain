---
name: PW-C03 FeeDistributor Sprint
description: Integration test lessons, Foundry quirks, blockchain ID change, deploy approach for C03
---

## Status: COMPLETE ✅

Sprint C03 delivered: FeeDistributor + 70/20/10 split proven on live PrimeWave Chain.

---

## Blockchain ID Changed After Genesis Modification

When `rewardManagerConfig` was added to `chain/genesis/dev-genesis.json`, the P-Chain's CreateChainTx hash changed, producing a new blockchain ID:
- **PW-C02 ID:** `yNRRcwqYaWqn9g4XcAiNe7DufgEHqpF2mmvcG6go1cRvtZo4S`
- **PW-C03 ID:** `2F3BHmNJWP4DNaBbMFQog3TvfcF6GRY7PX99r7Xzae4cRwAv6a`

**Why:** The blockchain ID = hash of the P-Chain CreateChainTx, which includes genesis bytes. Any genesis change → new blockchain ID.

**How to apply:** After any genesis modification, discover the new blockchain ID from the node log: `grep -oP '(?<=/ext/bc/)[A-Za-z0-9]+' local-data/node.log | head -1` (but note the grep pattern needs to match the log format — look for lines like `adding route {"url": "/ext/bc/XXXX"`).

---

## Foundry v1.7.1: `forge create --constructor-args` Bug

`forge create` with `--constructor-args <single_address>` exits 0 but prints "Constructor argument count mismatch: expected 1 but got 3" and deploys nothing.

**Fix:** Use `forge script` instead. `contracts/script/DeployC03.s.sol` handles all 3 deployments correctly via `vm.startBroadcast()`.

**Why:** Bug in Foundry v1.7.1 argument parser for single-address constructor args. Forge script bypasses the CLI arg parsing entirely.

---

## Integration Test: Everything in ONE ShellExec

The avalanchego node process (`nohup` child) does NOT survive between ShellExec calls in the Replit environment — even though `nohup` is used, the process is killed when the ShellExec session closes.

**How to apply:** The entire integration test lifecycle (kill stale → start node → wait for L1 → deploy → transact → distribute → verify) MUST happen within a single ShellExec call.

**Pitfalls:**
- `set -euo pipefail` + `ls glob | head -1` fails if glob matches nothing (pipefail on ls exit 1). Avoid; use hardcoded paths or `|| true`.
- `set -e` with inline `python3 -c "..."` that references bash variables: works fine but triple-check interpolation.
- `pkill -9 -x "avalanchego"` works correctly; kills by exact binary name without affecting the running script.
- Node starts and L1 is ready in ~2s (very fast; genesis has only 1 block).

---

## Foundry Binary Location

Foundry binaries at `local-bin/foundry/` (NOT `~/.foundry/bin/`).  
Always: `export PATH="$PWD/local-bin/foundry:$PWD/local-bin:$PATH"`  
Run forge from workspace root (foundry.toml is at root, not in contracts/).

---

## Deployment Script: `DEV_PRIVATE_KEY_0` env var required

`contracts/script/DeployC03.s.sol` reads `vm.envUint("DEV_PRIVATE_KEY_0")`.  
Must export before running: `export DEV_PRIVATE_KEY_0="0xac0974...ff80"`

---

## Fee Routing Without Explicit RewardManager Activation

The `rewardManagerConfig` genesis field alone routes fees to FeeDistributor — no runtime transaction required to "enable" the precompile. `cast code 0x020...004` returns a short code blob (this is normal for precompiles; they are not EVM contracts). Fees flow correctly regardless.

---

## Test Results Summary (C03)

- 25 unit tests: PASS
- 14 fuzz/invariant tests (256 runs each): PASS
- Integration test (live chain): PASS
- distribute() TX: `0x7830e0057728b61baf5f10f5a8235045aedb844d88414b511a502ee3ee4128c4`
- Input: 25,279,550,001,011,182 wei → vault 70% ✓, treasury 20% ✓, burn remainder ✓, conservation ✓

---

## Files Modified/Created in C03

See `docs/PW-C03-TEST-REPORT.md` and `docs/PW-C03-FINAL-REPORT.md` for full details.
Key new files: `contracts/src/FeeDistributor.sol`, `contracts/src/ValidatorFeeVault.sol`, `contracts/src/DevTreasury.sol`, `contracts/test/FeeDistributorUnit.t.sol`, `contracts/test/FeeDistributorInvariant.t.sol`, `contracts/script/DeployC03.s.sol`, `docs/PW-C03-FEEDISTRIBUTOR_SPEC.md`.
