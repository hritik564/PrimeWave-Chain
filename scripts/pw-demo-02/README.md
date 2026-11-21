# Isolated PrimeWave Chain 73571 demo

This is a separate disposable runtime at `.local-networks/pw-demo-02/`. It does
not use `local-data/`, recovery backups, Testnet 77, or the existing host
Avalanche CLI files.

Avalanche CLI v1.9.5 resolves paths from the OS account home. Start runs it
inside an unprivileged user and mount namespace that masks both candidate CLI
homes and the root home with directories inside this runtime. `/tmp`, CLI
cache/config/data, network-runner state, database, node logs, plugins, keys,
and chain data are redirected into the runtime. The original host CLI home is
never mounted as a source and remains untouched.

AvalancheGo RPC and staking/P2P listeners are configured for `127.0.0.1`.
Startup refuses to proceed if the runtime path, mount redirection, binary
versions, VM protocol, genesis Chain ID, or node data paths fail validation.
An incomplete initialization is preserved and is not retried automatically.

Commands:

```bash
bash scripts/pw-demo-02/start.sh
bash scripts/pw-demo-02/health.sh
bash scripts/pw-demo-02/status.sh
node scripts/pw-demo-02/transfer-test.cjs
node scripts/pw-demo-02/restart-check.cjs capture
bash scripts/pw-demo-02/stop.sh
bash scripts/pw-demo-02/start.sh
node scripts/pw-demo-02/restart-check.cjs verify
```

The transfer helper signs exactly one 1-PW transfer using an isolated sender
key. The key is stored with mode `0600` and is never written to logs or
command-line arguments. No indexer, database, PWUSD, governance contract,
published deployment, or external chain is used.
