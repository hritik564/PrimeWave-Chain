---
name: PrimeWave AvalancheGo Installation (Validator #1)
description: AvalancheGo v1.14.2 installation on 159.195.193.209 — service, NodeID, pitfalls, next steps
---

## Status
UPGRADED TO v1.15.0-fuji — 2026-08-15. Fuji Helicon-compatible. 36 peers connected. P-Chain bootstrapping (block execution phase). Firewall open and confirmed working.

## Node Identity
- **NodeID**: `NodeID-8PrCNxVrpztDxX2QWc6arY3d9rDdEjxX7`
- **BLS Public Key**: `0x80c7bbad285df48437cf786929158100b4a602b8edc25a600753919710377578a3548ed9da1d2cd0edd15e42d8c0ef27`
- **BLS PoP**: `0x98d4acc68f48dbe375ed7229e61efdb6657b82cdf39095d5013dc20a7f895c82f5dc38da3b24fd46d32effd4b7afbb6f0c053e8bba5778d1dd22aa4b0ba4915cabaf21f33ac3e290e8a8f8ef871a495e649b7ee5b65b135729421b7298d85b3c`
- Staking certs: `/home/avalanche/.avalanchego/staking/staker.crt|key`, `signer.key` — all `r--------` (400), owned by `avalanche`

## Installation Facts
- **Version**: AvalancheGo v1.15.0-fuji (db=v1.4.5, rpcchainvm=**46**, go=1.25.10, commit=e8f9781ee57de048bbfde5be0fa632e9efdf1448)
- **Binary**: `/opt/avalanchego/avalanchego`
- **SHA256 (binary)**: `8e324aa3c7370998d2df97d9c5904d699878a404366f062ac85ed6ceddff270b`
- **SHA256 (tarball)**: `aeae28f71499fc55d0e3349fbe8f73dc0c95d62837b6d12f1eb6741efaa575eb`
- **Source**: official GitHub release `avalanchego-linux-amd64-v1.15.0-fuji.tar.gz`
- **v1.14.2 backup**: `/opt/avalanchego/avalanchego.v1.14.2.bak` (retained on server)
- **rpcchainvm changed**: 45 → 46 (breaking — subnet-evm plugin must also be v1.15.0-fuji)
- **Subnet-EVM to use**: `subnet-evm-linux-amd64-v1.15.0-fuji.tar.gz` from same release
- **Service user**: `avalanche` (uid=988, system user)
- **Home dir**: `/home/avalanche` (required — AvalancheGo writes staking certs to $HOME/.avalanchego/staking/)
- **Data dir**: `/data/avalanchego/db`
- **Log dir**: `/var/log/avalanchego`
- **Plugin dir**: `/opt/avalanchego/plugins`
- **Service name**: `primewave-testnet-node`
- **Service file**: `/etc/systemd/system/primewave-testnet-node.service`

## Effective Flags
```
--network-id=fuji
--http-host=127.0.0.1        (localhost only — never public)
--http-port=9650
--staking-port=9651
--api-admin-enabled=false
--db-dir=/data/avalanchego/db
--log-dir=/var/log/avalanchego
--plugin-dir=/opt/avalanchego/plugins
--log-level=info
--log-format=json
```
Note: `--track-subnets` intentionally omitted — no PrimeWave subnet ID exists yet.

## Pitfalls Found
1. **`--api-keystore-enabled` was removed in v1.14.2** — the setup-testnet-node.sh script still references it. Remove this flag; keystore API is gone entirely.
2. **Service user needs a real home directory** — using `useradd --no-create-home` causes `mkdir /home/avalanche: permission denied` because AvalancheGo writes staking certs to `$HOME/.avalanchego/staking/`. Must create `/home/avalanche` and set ownership.

## Peer Connectivity (v1.15.0-fuji)
- **36 Fuji peers** connected within ~90 seconds of v1.15.0-fuji startup
- 95% stake-weighted connectivity immediately achieved
- P-Chain bootstrap: block fetch completed in ~2 minutes; block execution phase follows (takes longer)
- "peer attempting to connect with newer version" log spam — fully resolved; all peers now run v1.15.0
- External TCP 9651 confirmed OPEN from Replit: `nc -z -w 8 159.195.193.209 9651` → OPEN

## Next Required Actions (in order)
1. Fund testnet-deployer on Fuji: faucet.avax.network → 0x2AD3152Ca630e2eF6679EBeb8da7b8311bfbFc60 (currently 0 AVAX)
2. Update setup-testnet-node.sh: AVALANCHEGO_VERSION and SUBNET_EVM_VERSION from v1.14.2 → v1.15.0-fuji
3. Replace local-bin/subnet-evm v1.14.2 (rpcchainvm=45) with v1.15.0-fuji (rpcchainvm=46)
4. Assess Avalanche CLI v1.9.5 compatibility with Helicon Fuji for ceremony tx types
5. Assess ICM relayer v1.7.5 vs v1.8.0-fuji for post-ceremony Warp messaging
6. Wait for C-Chain full bootstrap (no state sync in v1.15.0-fuji — takes hours)
7. Fill genesis placeholders (6 __REPLACE__* addresses + FeeDistributor address)
8. Key ceremony: CreateSubnetTx → CreateChainTx → ConvertSubnetToL1Tx → SubnetID → BlockchainID
9. Add --track-subnets=<SUBNET_ID> to service, install subnet-evm-v1.15.0-fuji plugin

## ICM Services Versions
- Current PrimeWave pin: icm-relayer-v1.7.5 (Jan 2026, pre-Helicon)
- Helicon Fuji pre-release: icm-relayer-v1.8.0-fuji (Jul 27, 2026, same day as Helicon activation)
- RC: icm-relayer-v1.8.1-fuji-rc.0 (Aug 5, 2026)
- For CEREMONY: v1.7.5 contracts OK (P-Chain txs don't use ICM)
- For WARP RELAYER: OPEN — v1.8.0-fuji likely required for post-Helicon Fuji JSON-RPC compatibility

## DO NOT (until explicitly approved)
- Create subnet or blockchain
- Generate validator keys (ceremony)
- Join PrimeWave subnet
- Deploy contracts
- Stake AVAX
