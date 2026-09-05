---
name: PWCScan network isolation
description: Production behavior for local-only Devnet versus published Testnet
---

Local-only networks must be explicitly unavailable in production rather than inheriting a same-origin indexer route owned by another network. Development defaults may use local RPC and indexer paths, but production must not reuse them or silently fall back across networks.

**Why:** A shared `/indexer-api` fallback caused published Devnet requests to reach the Chain 77 Testnet indexer, where existing Chain ID validation correctly exposed the mismatch.

**How to apply:** Keep each published network's RPC and indexer endpoint explicitly configured. For a local-only network, set its production endpoint to null and its status to unconfigured while preserving its local development defaults and chain identity.