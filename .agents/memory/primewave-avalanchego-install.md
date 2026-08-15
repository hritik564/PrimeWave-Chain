---
name: PrimeWave AvalancheGo Installation (Validator #1)
description: AvalancheGo v1.14.2 installation on 159.195.193.209 — service, NodeID, pitfalls, next steps
---

## Status
INSTALLED AND RUNNING — 2026-08-15. Waiting for Netcup provider firewall (TCP/UDP 9651) to be opened before peer connectivity can be established.

## Node Identity
- **NodeID**: `NodeID-8PrCNxVrpztDxX2QWc6arY3d9rDdEjxX7`
- **BLS Public Key**: `0x80c7bbad285df48437cf786929158100b4a602b8edc25a600753919710377578a3548ed9da1d2cd0edd15e42d8c0ef27`
- **BLS PoP**: `0x98d4acc68f48dbe375ed7229e61efdb6657b82cdf39095d5013dc20a7f895c82f5dc38da3b24fd46d32effd4b7afbb6f0c053e8bba5778d1dd22aa4b0ba4915cabaf21f33ac3e290e8a8f8ef871a495e649b7ee5b65b135729421b7298d85b3c`
- Staking certs: `/home/avalanche/.avalanchego/staking/staker.crt|key`, `signer.key` — all `r--------` (400), owned by `avalanche`

## Installation Facts
- **Version**: AvalancheGo v1.14.2 (db=v1.4.5, rpcchainvm=45, go=1.25.8, commit=6e5acf909c)
- **Binary**: `/opt/avalanchego/avalanchego`
- **SHA256**: `023da7976ba7ab9a1ded2280ba26575649066078dd89805f826592e06c035c8b`
- **Source**: official GitHub release `avalanchego-linux-amd64-v1.14.2.tar.gz`
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

## Why 0 Peers (Expected)
- Netcup provider-level firewall has NOT been opened for TCP/UDP 9651 inbound yet
- Without inbound 9651, the node cannot receive peer connections
- Outbound P2P connections also appear blocked (bootstrap nodes may filter new unknown nodes)
- After Netcup firewall is opened: verify with `nc -z -w 8 159.195.193.209 9651` from external, then peers will connect and bootstrap will proceed

## Next Required Actions (in order)
1. **Operator**: Open Netcup Robot firewall: inbound TCP 9651 + UDP 9651
2. **Verify**: `nc -z -w 8 159.195.193.209 9651` from external host → must show OPEN
3. **Wait**: AvalancheGo will bootstrap Fuji primary network (P-chain, X-chain, C-chain) — takes 10-30 min
4. **Subnet-EVM plugin**: Not yet installed (no subnet ID exists yet; deferred to Fuji ceremony)
5. **Key ceremony**: Generate testnet deployer → CreateSubnetTx → CreateChainTx → SubnetID → BlockchainID
6. **Then**: Add `--track-subnets=<SUBNET_ID>` to service, install subnet-evm plugin

## DO NOT (until explicitly approved)
- Create subnet or blockchain
- Generate validator keys (ceremony)
- Join PrimeWave subnet
- Deploy contracts
- Stake AVAX
