---
name: Local vs Testnet subnet-evm binary
description: local-bin/subnet-evm must match local AvalancheGo rpcchainvm version; testnet prep swaps it and breaks local dev
---

## The Rule

`local-bin/subnet-evm` must match the rpcchainvm version of the **local** AvalancheGo (v1.14.2 = rpcchainvm 45).

The backup `local-bin/subnet-evm.v1.14.2.bak` is the correct binary for local dev.

**Why:** During testnet server preparation, `local-bin/subnet-evm` was replaced with the v1.15.0-fuji build (rpcchainvm=46) so the file could be SCP'd to validators. This silently broke the local dev chain — the subnet handshake fails with "RPCChainVM protocol version mismatch", the chain subnet never starts, the Indexer workflow times out waiting for the chain RPC, and PWCScan shows "Cannot connect to PrimeWave indexer".

**How to apply:**
- After any testnet binary work that touches `local-bin/subnet-evm`, restore the backup: `cp local-bin/subnet-evm.v1.14.2.bak local-bin/subnet-evm`
- Then restart the Chain workflow, then the Indexer workflow
- The local AvalancheGo version (v1.14.2, rpcchainvm=45) is pinned in setup-local.sh and must not be changed for local dev
- The testnet validators use v1.15.0-fuji (rpcchainvm=46) — a completely separate install on remote servers
