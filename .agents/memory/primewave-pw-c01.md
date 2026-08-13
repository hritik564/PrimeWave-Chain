---
name: PrimeWave Chain PW-C01
description: Local Avalanche L1 dev environment sprint — completed Aug 13 2026; all scripts, smoke tests, network IDs, and architectural workarounds
---

## Status
**COMPLETE** — all 10 automated smoke tests pass, 4 skipped by design. Test report at `docs/PW-C01-TEST-REPORT.md`.

## Confirmed Network Parameters (deterministic for primewavedev)

| Parameter | Value |
|---|---|
| Chain name | `primewavedev` (no hyphens — CLI allows letters only) |
| Dev Chain ID | `73571` |
| Subnet ID | `2W9boARgCWL25z6pMFNtkCfNA5v28VGg9PmBgUJfuKndEdhrvw` |
| Blockchain ID | `yNRRcwqYaWqn9g4XcAiNe7DufgEHqpF2mmvcG6go1cRvtZo4S` |
| VM ID | `rXJjKFtAVSmpKwhMhw7ZMV6opKcsmhk5AuVxWNAzFG221wmM8` |
| Node ID | `NodeID-Cz1eK4wyREFTvTkTfC5B8c44CN87Cvb58` |
| HTTP Port | `9656` |
| RPC URL | `http://127.0.0.1:9656/ext/bc/yNRRcwqYaWqn9g4XcAiNe7DufgEHqpF2mmvcG6go1cRvtZo4S/rpc` |

These IDs are deterministic — they are the same on every clean deploy of the `primewavedev` chain with the current genesis/sidecar.

## Architecture: Why CLI deploy "fails" and that's OK

CLI v1.9.5 + AvalancheGo v1.14.2 have a version mismatch. `blockchain deploy` fails at "setup VM binary" after ALL P-Chain work is done. `start-local.sh` handles this by:
1. Running deploy (to get P-Chain state + local cluster bootstrap DB)
2. Patching `flags.json` (sybil-protection=false, partial-sync=false, track-subnets, no bootstrap peers)
3. Placing `local-bin/subnet-evm` as plugin binary at `plugins/<VMID>`
4. Starting `avalanchego` directly (standalone single-node, healthy in ~3s)

See `avalanche-dep-surprises.md` for the full technical detail.

## Key flags for standalone node

Node's `flags.json` must have:
- `sybil-protection-enabled: false` — no peer quorum for single-node dev
- `partial-sync-primary-network: false` — required when sybil-protection is disabled
- `track-subnets: <subnetID>` — tells node to run our EVM chain
- `bootstrap-ips: ""`, `bootstrap-ids: ""` — standalone mode

## Local cluster path
`~/.avalanche-cli/local/primewavedev-local-node-local-network/NodeID-Cz1eK4wyREFTvTkTfC5B8c44CN87Cvb58/`
Plugin dir: `~/.avalanche-cli/local/primewavedev-local-node-local-network/plugins/`

## Scripts
- `scripts/setup-local.sh` — downloads avalanchego + CLI + subnet-evm; creates sidecar+genesis
- `scripts/start-local.sh` — deploy phase + flags patch + standalone node start (nohup, saves PID to `local-data/node.pid`)
- `scripts/stop-local.sh` — kills node by PID file, falls back to pgrep
- `scripts/reset-local.sh` — removes all CLI state + local-data (keeps binaries)
- `tests/smoke-test.sh` — 13 tests; use `--no-tx --skip-restart` in CI

## Balance display
10,000 PW = `10000000000000000000000` wei = `0x21e19e0c9bab2400000`. Use Python (not bash `printf %d`) — exceeds int64 max (2^63-1). smoke-test.sh uses `python3 -c "print(int('$HEX',16)/10**18)"`.

## PW-C01 gate passed — do NOT begin PW-C02 without explicit user approval
