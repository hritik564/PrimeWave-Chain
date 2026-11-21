---
name: Avalanche CLI home isolation
description: Avalanche CLI 1.9.5 resolves subnet and VM data under the operating-system account home.
---

Avalanche CLI 1.9.5 wrote subnet configuration, a VM copy, and a generated local CLI key under the operating-system account's default CLI home despite an overridden `HOME`. The `--config` option selects a config file; it does not establish that subnet and VM data paths are relocated. Creating with `--evm` attempted to download the selected VM version and failed; using a local custom VM path avoided that download but did not change the CLI home path.

**Why:** An isolated demo-chain attempt unexpectedly wrote CLI metadata outside its requested runtime. No node or blockchain transaction was started.

**How to apply:** Before invoking Avalanche CLI when strict per-run isolation is required, verify the actual OS-account CLI paths. If documented CLI controls cannot redirect them, fail closed rather than assuming `HOME` or `--config` isolates data. Do not remove generated host-home files without explicit approval.
