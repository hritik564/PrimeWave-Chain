---
name: Local Avalanche L1 conversion safety
description: Handling immutable conversion errors and stalled P-Chain state in isolated local Avalanche networks.
---

When AvalancheGo v1.14.2 rejects `ConvertSubnetToL1Tx` with an immutable-subnet error, its `verifyPoASubnetAuthorization` path rejects a subnet with an existing transformation or L1-conversion record. If `platform.getSubnet` simultaneously reports a permissioned subnet with empty transformation/conversion IDs, treat the mismatch as a hard state inconsistency, not a reason to retry. Wait for the transaction to reach a terminal status; if it remains `Processing` and P-Chain health reports a long-processing block, submit no more transactions. Gracefully stop only the disposable network and preserve its database and logs.

After stopping, verify the snapshot directory that actually exists rather than trusting the CLI success message or a requested name. In one isolated run, an alternate snapshot name was requested but only the runtime's `snapshots/default` directory was updated.

**Why:** The runtime exposed conflicting public state and an immutable error, then left P-Chain unhealthy with the conversion transaction still processing. A retry could compound an unclear state.

**How to apply:** Before continuing an L1 conversion, verify the P-Chain transaction is terminal, the subnet identity fields agree with the transaction result, and health is restored. If not, preserve the isolated state, stop safely, and investigate offline.
