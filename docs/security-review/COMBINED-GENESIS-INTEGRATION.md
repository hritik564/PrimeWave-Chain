# Combined synthetic genesis integration evidence

Baseline `a4d3a2242214be10d3baa9d7ab420de07891a36c`.
**Software-only, synthetic, unapproved. Not externally audited or deployable.**
No custody contract, production manifest, approval flag, AWS configuration,
identity or historical evidence was modified. Original locks and baseline review
artifacts remain byte-identical. This addendum supersedes the baseline's unresolved
Safe build-reproduction gap and fixed-address collision **for offline synthetic
integration only**; final production genesis/VM approval remains blocked.

## Collision inventory and explicit test-only plan

The baseline pinned manager build's compiler settings linked ValidatorMessages at
`0x000000000000000000000000000000000000b010`. The custody fixture installs Safe
singleton there. Those complete runtimes differ: this is the sole incompatible
fixed-address role collision identified in these two baseline evidence bundles.
The independent manager contract tests instead deployed proxy/implementation/PoA
with CREATE at test-generated addresses; their registry fixture still pointed at
B007 with no manager there. That was a **missing integration/binding**, not evidence
of a second deployable address plan. ProxyAdmin was a constructor-created account,
not included in the old twelve-account custody export.

| Old overlap / gap | Combined resolution |
|---|---|
| B010 library versus Safe singleton | Keep locked Safe at B010; rebuild/relink synthetic library at E100 |
| B007 fake-manager `0x6000` / unfilled registry binding | Actual initialized manager proxy at B007; registry immutable pointer remains B007 |
| B001–B006 core roles, B009 governance reference | Same logical roles, not conflicting contracts; retain exact original exported states and locked runtime bytes |
| Dynamic implementation / PoA / ProxyAdmin from separate tests | Explicit E101 implementation, E102 PoA; ProxyAdmin derived from proxy CREATE nonce1 and included |
| Legacy and custody signer/recipient sets differ | Combined uses committed custody fixture's A100/A200/A300 owner groups and D001–D005 recipients; no old C001-group signer is installed or newly created |
| Compiler-remapping metadata drift | Compile manager separately in a new output tree; preserve custody fixture's exact locked code/storage, never repin custody hashes to manager-build metadata |

All addresses below are **synthetic test constants**, not recommendations or
production addresses. Prefixes B/E/A/D mean low numeric addresses padded to40 hex
digits; full values are in `tests/fixtures/combined-genesis.fixture.json`.

| Role | Synthetic address suffix / derivation |
|---|---|
| Protocol timelock / emergency | B001 / B002 |
| ValidatorFeeVault / FeeDistributor / registry / RewardVault | B003 / B004 / B005 / B006 |
| Manager proxy | B007 |
| Treasury timelock / protocol Safe | B008 / B009 |
| Safe singleton / treasury Safe / protocol guard / treasury guard | B010 / B011 / B012 / B013 |
| ValidatorMessages / implementation / PoA | E100 / E101 / E102 |
| ProxyAdmin | `0x06e614cf6f9fef1f37f083e0a5abc5b4b4fd67cc` = CREATE(B007,1), checked with vm.computeCreateAddress |
| Protocol / treasury / emergency public test signers | A100–A104 / A200–A204 / A300–A304 |
| Liquidity / team / presale1 / presale2 / presale3 | D001 / D002 / D003 / D004 / D005 |

The17 code-account addresses are unique, disjoint from all15 synthetic signers
and five ordinary C00 recipients. Treasury and RewardVault allocation aliases
are intentional and preserve their15M each. Actual full-address collisions,
missing accounts, case-normalized duplicates and unexpected account additions
are rejected by the evidence validator/tests. No production value is invented.

## Build, constructor and state integration

Pinned manager sources: ICM40e1c898d44242aee25693a9cde4bc2485bd8242,
OZ/OZ-upgradeable5.0.2; all extracted Solidity inputs are compared against the
three digest-pinned archives before compiling. Solc0.8.30+commit.73712a01,
Shanghai/viaIR/optimizer200; remappings and explicit E100 link settings are stored
per artifact in `managerRuntimeEvidence`. New build output is isolated under
`genesis-build/combined-synthetic-build`; existing `pinned-manager` build and
custody artifact lock are untouched. No library link is assumed from old output.

The test-only author runs library/implementation/proxy/PoA constructors at their
explicit final synthetic addresses. The implementation disables initializers;
proxy constructor atomically initializes manager owner=PoA, synthetic SubnetID
bytes32(123), churn3600 /20%; ProxyAdmin owner=P-TL. Proxy constructor CREATEs the
admin at its actual derived address. PoA constructor embeds the actual B007
manager as an immutable. No transient EOA owns the combined manager. Production
inputs and real SubnetID remain unresolved.

The twelve custody states come from the original constructor-exported fixture.
The test reauthors their storage and uses those exact locked runtime bytes rather
than accepting metadata changes caused by the manager's different OZ remappings.
Python compares **every field of all twelve accounts** with the original fixture.
All17 accounts are then exported together and supplied to the existing C00
materializer with the five manager accounts as managerPredeploys. It replaces the
fake manager; no fake code remains at B007 in the combined candidate.

Complete manager runtime byte arrays are compared with current compiler output;
PoA manager and proxy admin immutable reference ranges are filled with their
exact bindings before comparison. No metadata suffix or byte ranges are ignored.
Creation/runtime/settings hashes and immutable references are recorded. Library
code is loaded via the **exact new artifact JSON path**, avoiding ambiguous or
stale artifact-name resolution. Custody/Safe runtimes retain their original pins.

### Export completeness and restoration

-17 code accounts plus five ordinary allocation accounts =22 genesis alloc entries;
  total exactly100,000,000 PW. Treasury15M and RewardVault15M; all C00 values and
 70/20/10 policy unchanged. No extra gas allocation, native minter or post-funding.
- Legacy `accountJson` hardcodes nonce1. That remains unchanged and must **not**
  be used for constructor-created manager graphs: the combined proxy account is
  nonce2 after creating ProxyAdmin; child admin is nonce1. The new test-only
  manager exporter records actual nonces; Python rejects zero/wrong nonces.
- ProxyAdmin is explicitly exported, including owner storage and runtime. Library
  storage is legitimately empty, whereas implementation initializer-disable,
  proxy initialization/owner/SubnetID/churn/ERC1967 slots and PoA/admin ownership
  state must be retained. Original core copied-constructor slots are exported
  through the existing author's tracked-slot map, not only vm.accesses.
- Export repeats identically after reverting to the pre-manager snapshot and
  rerunning constructors. The17 exported accounts are then restored with complete
  recorded code/storage/balance/**nonce** into the pre-custody snapshot, where
  all17 have zero code and nonce beforehand. Every exported slot and full runtime
  is compared. Getters check owners, Safe threshold/guard/timelock/registry links.
- Post-restore native disbursement, delayed ProxyAdmin upgrade and delayed PoA
  manager-ownership transfer work through the paired Safe/timelock. The upgrade
  tests immutable proxy administration in execution; PoA transfer tests its
  immutable manager binding. Unauthorized upgrade/initializer calls revert.
- A **separate test** initializes a two-validator set through the actual linked
  library and a mocked Warp precompile, total weight2000. Exported initial genesis
  correctly leaves `isValidatorSetInitialized=false`: real P-Chain conversion
  proof remains required. Fake BLS/NodeID bytes and mocked Warp are not identities
  or authenticated public-network evidence.

Remaining completeness limit: vm.record/constructor-slot tracking and tests cannot
prove the absence of every omitted slot or target-VM difference. A fresh Foundry
snapshot is a stronger round trip than clearing only known slots, but still is
not a fresh Subnet-EVM state database or final-genesis VM acceptance proof.

The combined genesis SHA256 is recorded in `combined-integration.evidence.json`
and the candidate; all candidate deployment/chain/genesis authorization flags
remain false. Public-review=true inputs inside labeled test fixtures are harness
inputs only, not owner approval. Neither test address plan is production input.

## Safe1.4.1 build provenance: reproduced

The digest-pinned npm package contains complete standard-JSON sources/settings
and compiler output in:
`package/build/artifacts/build-info/0128da95e283bfa75197e80e5a451911.json`.
It selects **solc0.7.6+commit.7338295f**, optimizer **disabled** (runs200 retained),
metadata.useLiteralContent=true; omitted settings retain that compiler's defaults.
Do not confuse this with PrimeWave's solc0.8.30 viaIR/optimizer-enabled build.

We independently recompiled the complete embedded input with verified official
solc-js0.7.6, using no npm install, callbacks, external imports or network during
compilation. Safe and SafeProxy **creation bytecode, complete runtime bytecode,
ABI and metadata match exactly** both build-info output and vendored artifacts.
`safe-build-reproduction.json` records compiler SHA256, source/settings hashes,
package SHA512 and matches. The Solidity download host returned HTTP403; the
compiler was obtained from the official ethereum/solc-bin GitHub mirror and
checked against its compiler listing SHA256. Only public software was downloaded.
Reproduction commands below operate offline with existing inputs.

This closes the missing-source/settings/rebuild evidence gap for these two
selected artifacts. It does not audit Safe or custom PrimeWave code, prove compiler
bootstrap trust, cover other package contracts or grant production approval.
No old lock/hash approval was changed, and no contract was labeled externally audited.

## Reproduction and actual tests

Existing verified public source archives, compiler and dependencies required;
commands never download, create identities, start a node, fork, sign or broadcast.
Run from repo root; unset RPC/fork env variables.

```sh
unset ETH_RPC_URL FOUNDRY_ETH_RPC_URL FOUNDRY_FORK_URL
forge build --offline
python3 scripts/mainnet/verify_custody_artifacts.py
python3 scripts/mainnet/run_combined_genesis_tests.py --archives /path/to/public-archives --forge /path/to/forge
python3 scripts/mainnet/combined_genesis.py
python3 -m unittest discover -s tests -p 'test_combined_genesis.py'
python3 scripts/mainnet/test_custody_manager.py --archives /path/to/public-archives --forge /path/to/forge
forge test --offline
python3 -m unittest discover -s tests -p 'test_*.py'
python3 scripts/mainnet/verify_safe_rebuild.py --package /path/to/safe-contracts-1.4.1.tgz --compiler /path/to/soljson-v0.7.6.js
```

The combined runner copies only the committed synthetic fixture into the allowed
ignored authoring directory, refusing a different pre-existing copy. It excludes
the inherited legacy twelve-account writer and repeat test: the former would
rewrite baseline evidence, the latter rebuilds custody under different remapping
metadata. Both run normally in the782-test default suite; the combined suite's
own17-account repeat/fresh-restore test replaces that test in this context.
`combined_genesis.py` defaults to exact comparison; --write exclusively creates
new evidence and refuses overwrite. Never regenerate locks to silence a failure.
Safe verifier requires the exact package/compiler digests and executes only local
compiler standard JSON. No key/wallet/signing API is used.

Actual reruns:782 default Solidity,18 pinned-manager,17 combined integration,
180 Python (including9 new mutation/invariant cases),8 configuration-render
combinations, existing lock/evidence comparison, and Safe rebuild all pass.
Python binary checks used existing cached native/Linux archives; macOS version
execution and Linux hash/ELF checks are not Linux final-genesis execution.
Counts overlap inherited tests; do not present their sum as unique coverage.
Forge's preliminary parser emitted duplicate-declaration warnings for overlapping
ICM import graphs; real solc compilation and the reported test suites passed.
No formal verification or independent audit occurred.

## Final VM blocker and next decisions

Use `FINAL-GENESIS-VM-VALIDATION.md` for a **future separately authorized** isolated
test with actual approved SubnetID-bound artifacts. No node was started here.
Independent security review, final public custody/addresses, final ChainID/forks/
timestamp, actual manager state/library link map and conversion proof, operational
funding/recovery, no-backdoor and two-validator-risk decisions remain mandatory.
The owner must accept/reject those choices and separately authorize each operation;
no Mainnet, node, signing, spending or deployment approval follows from these tests.
