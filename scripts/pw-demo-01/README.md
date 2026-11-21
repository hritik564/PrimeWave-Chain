# Isolated PrimeWave demonstration network

This runtime is separate from `local-data/`, recovery archives, Testnet 77, and
production. Its data is stored under `.local-networks/pw-demo-01/`, which is
ignored by Git, excluded from deployment images, and denied by the PWCScan
development server's filesystem rules.

Commands:

- `bash scripts/pw-demo-01/start.sh` — initialize once, then restart the
  verified network without redeploying it.
- `bash scripts/pw-demo-01/status.sh` — inspect only this runtime.
- `bash scripts/pw-demo-01/health.sh` — verify local AvalancheGo health and
  EVM Chain ID 73571.
- `bash scripts/pw-demo-01/stop.sh` — send SIGTERM only to the recorded
  AvalancheGo process if its executable and runtime paths match.
- `node scripts/pw-demo-01/transfer-test.cjs` — send one signed 1-PW test
  transfer using the disposable genesis-funded key stored with mode 0600.

An incomplete initialization is intentionally not retried automatically. Keep
the private runtime directory intact and inspect its logs before any recovery.
Never run Avalanche CLI `network clean` for this runtime.

The pinned Avalanche CLI v1.9.5 currently resolves its subnet and VM directories
from the operating-system account home rather than the caller's `HOME`. The
startup scripts fail closed unless that CLI home is the requested isolated
directory; do not bypass this guard or point it at existing local state.
