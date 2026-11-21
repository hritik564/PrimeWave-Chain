---
name: Avalanche CLI home isolation
description: Avalanche CLI 1.9.5 resolves subnet and VM data under the operating-system account home.
---

Avalanche CLI 1.9.5 wrote subnet configuration, a VM copy, and a generated local CLI key under the operating-system account's default CLI home despite an overridden `HOME`. The `--config` option selects a config file; it does not establish that subnet and VM data paths are relocated. Creating with `--evm` attempted to download the selected VM version and failed; using a local custom VM path avoided that download but did not change the CLI home path.

An unprivileged `unshare --user --map-root-user --mount` namespace is available. Inside it the effective UID becomes `0` and the account home resolves to `/root`, even when the caller's home is `/home/runner`. A safe overlay must therefore mask both CLI-home paths and redirect `/root`, temporary files, and CLI data to the runtime. With that isolation, the CLI's local deployment reached CreateSubnetTx but CreateChainTx failed because the subnet UTXO was not found.

**Why:** An isolated demo-chain attempt unexpectedly wrote CLI metadata outside its requested runtime. The later namespace test safely redirected those writes, but the pinned local bootstrap still failed during L1 creation.

**How to apply:** Before invoking Avalanche CLI when strict per-run isolation is required, verify the actual OS-account paths and namespace identity. If documented controls or a tested mount overlay cannot contain them, fail closed rather than assuming `HOME` or `--config` isolates data. Preserve partial local state and do not repeat a failed CreateChainTx without a different verified bootstrap path.
