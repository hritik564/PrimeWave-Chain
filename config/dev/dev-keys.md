# PrimeWave Chain — Local Development Keys

> ⚠️ **DEVELOPMENT ONLY — NOT FOR TESTNET OR MAINNET**
>
> These keys are derived from the publicly known Foundry/Hardhat test mnemonic:
> `test test test test test test test test test test test junk`
>
> **These private keys are public knowledge.** Anyone who knows this mnemonic (everyone) can
> derive these keys. They are suitable ONLY for local development where there are no real funds.
>
> **NEVER use these keys on any public network.**
> **NEVER fund these addresses with real assets.**
> **NEVER import these into a production wallet.**

## Development Mnemonic (Public — Development Use Only)

```
test test test test test test test test test test test junk
```

Derivation path: `m/44'/60'/0'/0/N`

## Pre-funded Development Accounts

Each account is pre-funded with **10,000 PW** in the local dev genesis.

| Index | Address | Private Key |
|---|---|---|
| 0 | `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` | `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80` |
| 1 | `0x70997970C51812dc3A010C7d01b50e0d17dc79C8` | `0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d` |
| 2 | `0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC` | `0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a` |
| 3 | `0x90F79bf6EB2c4f870365E785982E1f101E93b906` | `0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6` |
| 4 | `0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65` | `0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926b` |

## Avalanche Local Network Pre-funded Keys

When the Avalanche local network starts, it also pre-funds some Avalanche-internal accounts.
These are used by the Avalanche CLI and network runner internally.

These are managed by the CLI and are separate from the EVM genesis alloc above.

## Using in Foundry / Cast

```bash
# Set environment variable for convenience
export DEV_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Send a transaction using cast
cast send --private-key $DEV_KEY \
  --rpc-url $PRIMEWAVE_RPC_URL \
  0x70997970C51812dc3A010C7d01b50e0d17dc79C8 \
  --value 1ether
```

---

*This file documents public, development-only keys. No production secrets are present.*
