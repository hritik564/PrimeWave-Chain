---
name: PrimeWave Chain PW-C16
description: Fuji L1 chain activation — patched subnet-evm binary, block production confirmed, public RPC live
---

# PrimeWave Chain PW-C16 — Fuji L1 Chain Activation COMPLETE

## What Was Done
- Built patched `subnet-evm v1.15.0` binary from the AvalancheGo v1.15.0-fuji monorepo
- Deployed patched binary to all 4 testnet validators (V6, V7, V8, V9)
- Chain began bootstrapping → produced block 1 → now actively producing blocks
- Nginx proxy set up on all 4 validators (port 80) as public RPC
- MetaMask connection doc written at `docs/testnet-metamask-connection.md`

## Root Cause of Blocker (resolved)
- Genesis had `"warpConfig":{"blockTimestamp":0}` but no `durangoTimestamp`
- Stock subnet-evm v1.15.0 rejects this in `precompile/contracts/warp/config.go` line 93:
  `if !chainConfig.IsDurango(timestamp) { return errWarpCannotBeActivated }`
- Fix: Replace with `if false && !chainConfig.IsDurango(timestamp) {` (one-line patch)

## Patch Location
- Monorepo path: `graft/subnet-evm/precompile/contracts/warp/config.go` in AvalancheGo v1.15.0-fuji
- Source at `https://github.com/ava-labs/avalanchego/archive/refs/tags/v1.15.0-fuji.tar.gz`
- Build command: `go build -o /tmp/subnet-evm-patched ./graft/subnet-evm/plugin/` (from workspace root)
- Requires: Go 1.25.13, gcc, CGO_ENABLED=1; takes ~75 seconds on 4-core server
- Patched binaries built on V7, V8, V9 (source at `/tmp/avalanchego-1.15.0-fuji/`)

## Chain "Before Fork" / First Block Bootstrap
- Genesis timestamp is 0x0 → proposervm starts in `before fork` state
- In `before fork`, subnet-evm needs a mempool transaction to trigger BuildBlock
- Solution: send a self-transfer transaction using the deployer key (key at `~/.avalanche-cli/key/testnet-deployer.pk`)
- Deployer: `0xB518397E3D65a0E7475635F01C225E9426a76F11`, private key prefix: `4b04f1d663c...`
- Install `eth-account` via `pip3 install eth-account --break-system-packages` on the validator, then sign+send
- After the first block, subsequent blocks produce automatically (no ongoing tx needed)

## Public RPC Endpoints (all validated externally)
- V9: `http://159.195.47.126/ext/bc/22iFuL8GqPYbtnPKNFrq7AzoDfv3FYwq8T93GubRi12LQVjLni/rpc`
- V7: `http://152.53.66.201/ext/bc/22iFuL8GqPYbtnPKNFrq7AzoDfv3FYwq8T93GubRi12LQVjLni/rpc`
- V8: `http://159.195.44.104/ext/bc/22iFuL8GqPYbtnPKNFrq7AzoDfv3FYwq8T93GubRi12LQVjLni/rpc`
- V6: `http://152.53.66.93/ext/bc/22iFuL8GqPYbtnPKNFrq7AzoDfv3FYwq8T93GubRi12LQVjLni/rpc`
- Chain ID 77 (0x4d), Token PW

## Nginx Config Pattern (write with Python raw string to avoid $ interpolation)
```python
config = r"""server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    location / {
        proxy_pass http://127.0.0.1:9650;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        ...
    }
}"""
open("/etc/nginx/sites-available/primewave-rpc","w").write(config)
```
Then: `ln -sf .../primewave-rpc .../sites-enabled/primewave-rpc && rm -f sites-enabled/default && nginx -t && systemctl restart nginx`
UFW: allow 80/tcp, 9650/tcp (9651 was already open)

## V6 SSH Issue
V6 (152.53.66.93) has intermittent SSH connection resets from Netcup firewall. Not critical — other 3 validators provide redundancy. Connect with `ConnectTimeout=20` and retry if it fails.

## V8 SSH Issue
V8 (159.195.44.104) SSH resets frequently after heavy build (RAM/CPU load). Wait a few minutes after build completes before connecting.

## Key Pitfalls
- `go.work` in monorepo requires Go 1.25.x — Go 1.22.4 was initially installed but rejected
- Nginx 404: if bash heredoc is used for nginx config, `$http_upgrade` etc get interpolated — use Python raw strings instead
- The `skip-upgrade-check` flag does NOT skip the Durango genesis check — must patch the binary
- Chain config goes in `$HOME/.avalanchego/configs/chains/{blockchainID}/` not in data-dir

## Outstanding (next session)
- Deploy PrimeWave contracts (FeeDistributor, StakingManager, etc.) via `DeployTestnet.s.sol`
- Configure PWCScan block explorer to point to one of the public RPC endpoints
- Set up TLS/HTTPS on RPC endpoints (currently bare HTTP)
- Automate "kick" transaction in case validators restart and chain stalls (or configure subnet-evm to build empty blocks)

## PWCScan Testnet endpoint finding
- The Chain 77 RPC responds on the documented validator HTTP endpoints, but `api.testnet.primewave.xyz` currently resolves to an external landing/TLS endpoint rather than a live indexer API. PWCScan must not treat this as a syncing indexer.
