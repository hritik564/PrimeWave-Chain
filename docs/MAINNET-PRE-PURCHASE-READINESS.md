> Current status supersedes historical notes below: owner selected C00 and the two-validator pilot. See `config/mainnet/isolated-vm-evidence.json` and `offline-validation.json` for executed checks. RewardVault constructor-state genesis is proposed; legacy `DeployProduction.s.sol` now refuses before key access. Public custody addresses, final genesis/Chain IDs, Fuji identities/funding and broadcast authorization remain gated.

# Production branch implementation status — 2026-11-21

Branch `codex/mainnet-blocker-resolution` preserves development/local-bin and
pw-demo-04. No node/L1 was started, no P-Chain transaction sent and no key read.

- `config/mainnet/binaries.lock.json`: official stable v1.15.1 pair, protocol46.
  Linux AMD64 archives and extracted ELF hashes verified. Native macOS binaries
  executed only with `--version`, confirming matching commit/protocol. Linux execution is now verified by the Actions run below; a real VM handshake
  and genesis rehearsal remain untested.
  v1.15.3 uses47 and is newer/optional; no upstream LTS guarantee is asserted.
- `chain-id.review.json`: candidate73571001, no collision in the downloaded
  ethereum-lists registry snapshot. Exact approval, snapshot digest and24h
  freshness are enforced; no unlisted-chain uniqueness guarantee or reservation.
- `MAINNET-ALLOCATION-CONFLICTS.md`: one table comparing the C00 approved baseline
  and C11 drift.100M supply,15M rewards,no native minting and70/20/10 preserved.
  Addresses, RewardVault custody and deployment gas funding remain owner inputs.
- `validator.py`: explicit mainnet/Fuji config, private RPC, sybil protection,
  P-Chain-only sync, fixed binary hashes/version46 and fresh identity attestation;
  no file/directory/key generation. Default mode only checks. It rejects obsolete
  flags, unknown filesystem overrides, wrong plugin/subnet and demo paths.
- `validate_genesis.py`: explicit approval and allocation checks, no default RPC,
  no eth_getCode-based claims about native precompile activation. This is not a
  substitute for VM genesis/fork/manager validation in an authorized rehearsal.
- `DeployProduction.s.sol`: explicit nonlocal approved Chain ID, nonce/fee address
  checks before broadcast, owner-approved post-deploy reward funding mode and
  governance proposer. Immutable registry admin points to timelock. RewardVault
  pause initialization is printed as a timelocked governance action instead of
  attempting an unauthorized deployer call. These actions must complete before
  production go-live. No script is automatically invoked.
- `preflight.py`: two-host public inventory, persistent block mount, capacity,
  optional read-only fio benchmark, effective SSH policy export, firewall,
  monitoring/time sync, explicit external TCP9651 probe and recovery evidence.
  Unknown facts fail.3000 IOPS/10ms is a project acceptance target, not an official
  low-throughput L1 minimum.128GB is pilot-sized, not an archive/indexer budget;
  two equal-weight validators lose liveness when either is offline.

## Exact safe commands

On a separate Linux x86_64 test host/Replit shell, without touching demo paths:

```bash
python3 scripts/mainnet/verify-binaries.py --platform linux-amd64 \
  --output /private/tmp/primewave-fuji-v1.15.1 --run-version
```

After operator-controlled fresh Fuji TLS/BLS public records exist:

```bash
python3 scripts/mainnet/fuji_rehearsal.py \
  --manager config/mainnet/validator-manager.review.json \
  --public-identities /path/to/public-fuji-identities.json
```

The second command only validates public inputs and prints the ordered supported
flow: reviewed genesis/manager -> Fuji P-Chain sync -> CreateSubnetTx ->
CreateChainTx -> ConvertSubnetToL1Tx -> manager initialization -> read-only checks.
It contains no signer, faucet, network initialization or broadcast implementation.
Later validator additions use RegisterL1ValidatorTx, not duplicate initial entries.
The approved ICM tag's PoAManager path/commit is pinned; its compiled artifact and
proxy initialization still require a real rehearsal. Production/mainnet identities
must never be substituted for these fresh test identities.

Owner choices remain: C00 baseline versus explicitly superseding C11 approval;
genesis-predeployed rewards versus approved post-deploy custody; exact production
Chain ID/public addresses; C00 PoA phase1 remains the baseline; two-node limited pilot risk
versus5+ validator production topology; governance/custody and recovery owners.
Host access and AVAX balances/faucet funds must be provided by owners later;
none are funded or accessed here. Review inputs remain nondeployable.

Official evidence: [v1.15.1](https://github.com/ava-labs/avalanchego/releases/tag/v1.15.1),
[release API](https://api.github.com/repos/ava-labs/avalanchego/releases/tags/v1.15.1),
[deployment flow](https://build.avax.network/docs/tooling/avalanche-deploy/deploy-l1).

## Linux execution result and Fuji handoff

[GitHub Actions run44917244445](https://github.com/hritik564/PrimeWave-Chain/actions/runs/44917244445)
passed on Ubuntu24.04.5 x86_64. It checked out exact source88f3e59, verified both
Linux archives, and executed each binary with `--version`. Both reported1.15.1,
commitfdb2c1b9b02ef357b5867d5ababb6acc83837a01 and protocol46. This clears executable
version compatibility only; no VM handshake or genesis execution was performed.
Evidence is retained in `config/mainnet/binary-verification.linux-actions.json`.

The public-input Fuji bundle preparer is ready for approved manifests:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 scripts/mainnet/fuji_rehearsal.py \
  --manager /reviewed/fuji-manager.json \
  --public-identities /reviewed/fuji-identities.json \
  --prepare-bundle \
  --genesis /reviewed/fuji-genesis.json \
  --allocation-decision /reviewed/fuji-allocation.json \
  --chain-approval /reviewed/fuji-chain-id.json \
  --registry /reviewed/chains.json
```

These paths are operator inputs, not assumed existing files. The command does
not read keys, contact nodes, execute create-l1 or broadcast. It validates distinct
approved Fuji/production Chain IDs, current registry evidence, fresh public
identities, exact100M allocations, manager predeploy code/storage digests, private
RPC tunnels, an explicitly named Fuji keystore and explicit validator fee budget.
Manager artifact, initialization, fork and funding reviews must be approved.

The emitted argv targets official `ava-labs/avalanche-deploy` commit
`5989dd8a057f0c074b7fd6a656fb401b0222951c`, `tools/create-l1/create-l1`, using
`--network=fuji`, explicit genesis and the reviewed genesis proxy. This mode does
not add `--deploy-validator-manager`, raw keys or paid signature services. Review/
build the pinned tool before the authorized ceremony. Its upstream input
`--validators` accepts full loopback endpoint URLs, allowing SSH tunnels such as
127.0.0.1:19650 and127.0.0.1:29650 while each node keeps9650 private. Operators
establish tunnels using their own approved SSH access; no credentials belong here.

After an explicitly approved create/convert ceremony, collect all receipts and
conversion data, initialize the reviewed manager implementation and validator set
through the owner-controlled Fuji signer, then verify manager ownership,
registration, four Ethereum methods and persistence. Tool exit success alone is
not success of that entire rehearsal. Do not reuse the tool to retry a partial
P-Chain ceremony; inspect transaction status and saved IDs first.

Remaining explicit authorizations: allocation table and custody/gas source;
production and distinct Fuji Chain IDs; governance/public addresses and manager
initialization; fresh Fuji identity creation/host starts; faucet/test-AVAX funding
and fee budget; P-Chain/EVM rehearsal transactions. Mainnet, real funds and PWUSD
remain outside this rehearsal authorization.
