# Treasury and governance custody — offline review candidate

Source-only DIRECT_MAINNET work. **Not externally audited, production approved or
execution ready.** No real keys/owners, AWS, transactions, node startup or PWUSD.
All production manifests/approvals and historical AWS evidence are unchanged.

## Selected review architecture and provenance

- Separate protocol and treasury **Safe1.4.1** accounts, exactly3-of-5 each, using
  the exact published Safe singleton and SafeProxy creation/runtime artifacts.
  No recompilation of Safe under a different compiler, delegatecall initializer,
  modules, fallback handler or payment. A dedicated paired-timelock guard is
  installed as owner-reviewed genesis initialization (no transaction preapprovals). Published files and LGPL license
  are vendored; npm SHA512 and per-artifact/runtime SHA256 are pinned in
  `config/mainnet/custody-artifacts.lock.json`. Safe's [upstream audit references](https://docs.safe.global/advanced/smart-account-audits)
  and [1.4.1 migration guidance](https://docs.safe.global/advanced/smart-account-migration)
  do not constitute an audit of PrimeWave or these adapters.
- OpenZeppelin5.6.1 TimelockController (existing pinned Solidity dependency) owns
  each custody/control role. Native PW receipt/holding/value execution, scheduling,
  cancellation and role logic are inherited. See [OZ governance reference](https://docs.openzeppelin.com/contracts/5.x/api/governance).
- `PrimeWaveCustodyTimelock` adds only a nonzero multisig constructor policy and
  an updateDelay override enforcing >=48h. Self is the sole initial admin; its
  corresponding Safe is sole proposer/canceller/executor; no open executor and
  no deployer/EOA/emergency admin. Governance can change roles only through a
  delayed self-call; the48h floor cannot be removed even then. Lost Safe quorum
  can lock control permanently; custody and recovery procedures need review.
- `TimelockOnlySafeGuard` locks each Safe to CALL its paired timelock only;
  delegatecalls, Safe gas refunds/tokens/refund receivers, direct recipient calls,
  self-owner/threshold/guard/module changes are rejected even with a valid quorum.
  Standard Safe alone permits instant self-reconfiguration, which would violate
  delayed signer changes. The guard leaves signature/nonce/value custody in Safe.
  Initial guard setup uses explicit offline genesis state, not seeded signature
  approvals or an incremented Safe nonce. Guard and paired addresses are exported
  and checked. It can fund its timelock, but cannot send funds outside the delay.
  Execution gas is paid by an independently budgeted operator; Safe refunds are
  deliberately disabled to prevent a refund path around treasury delay.
  Signer changes require creating a reviewed replacement Safe and a delayed atomic
  grant/revoke of proposer/executor/canceller roles on the same timelock, preserving
  the treasury balance and self-admin role. This migration is contract-tested.
  There is no emergency escape: lost quorum or broken guard can permanently lock
  control. This guard is custom/unaudited, requires independent review and is not
  selected on the owner's behalf. See Safe's [guard interface and warning](https://github.com/safe-global/safe-smart-account/blob/v1.4.1/contracts/base/GuardManager.sol).
- These small policy adapters are CUSTOM and unaudited. Justification: stock OZ
  permits an authorized delayed updateDelay below48h, contradicting the fixed
  C00 floor. Custody/value/call/reentrancy logic is not reimplemented. New source,
  full OZ Solidity tree and compiled runtime hashes are locked; never silently
  regenerate the lock to accommodate a mismatch.

Owner approval of these implementation choices is still required. Contract code
and artifacts are candidates, not a reason to create identities or deploy them.

## Roles and emergency isolation

Protocol Safe -> protocol timelock -> ProxyAdmin.owner and PoAManager.owner;
ValidatorManager proxy owner -> PoAManager. Treasury Safe -> separate treasury
timelock. Treasury receives the existing15M genesis allocation and fixed20% gas
share. It can disburse native PW only through a scheduled value-bearing call
executed by its3-of-5 Safe after>=48h. It does not rely on DevTreasury or the
legacy custom PrimeWaveTimelock, neither of which implements this custody flow.

The legacy EmergencyMultisig remains a GENERIC executor for development. Its
ability to invoke setPauseController means target permissions alone did NOT prove
pause-only authority. Its public ABI/voting behavior is preserved (execute made
virtual for the production candidate); legacy state fixtures are not rewritten.

The production exporter instead selects `PauseOnlyEmergencyMultisig`:
- Existing five-owner/three-approval, nonce, cancellation and replay accounting.
- Fixed three-address allowlist:FeeDistributor,ValidatorFeeVault,RewardVault.
- execute requires exactly4 bytes and pause()/unpause() only. No treasury, Safe,
  manager, proxy, upgrade, ownership, role-grant or arbitrary-call authority.
- Emergency voters cannot rotate pause controllers, including to a malicious
  controller. A separate function permits ONLY the protocol timelock to rotate
  a registered target to reviewed nonzero contract code, after normal governance
  scheduling. This preserves recoverable governance without a3-vote escape hatch.
- The wrapper is custom, requires independent review, and does not replace
  production state automatically. Any future rotation must review the new
  controller's scope. Governance has broad powers after48h; the emergency group
  has none of those powers. Human/operator independence still needs evidence.

## Deterministic genesis construction

`CustodyGenesisState.s.sol` shares the existing six-core-contract authoring logic;
its separate run() consumes explicit public custody fields from the review
manifest. It never reads a key or calls startBroadcast. Production input template
remains unresolved and unapproved.

A normal "deploy elsewhere then copy" is unsafe for self-administered timelocks:
DEFAULT_ADMIN_ROLE would remain assigned to the temporary address. The new
constructor authoring installs creation code and executes it at EACH EXACT final
public target address in an isolated Foundry EVM, then retains returned runtime
and constructor/setup writes there. SafeProxy slot0 binds the selected singleton;
Safe setup executes at the final proxy with five explicit public owners and
threshold3. Timelocks self-administer at final addresses; no authoring privilege
is exported. No address prediction, singleton factory key or production CREATE2
transaction is assumed. Genesis predeploy addresses must be owner reviewed.

Safe runtime bytes are compared with the published artifacts. The timelock and
emergency policy runtimes are compared with exact compiler-output hashes.
Owner/threshold/Safe-module and timelock-role getters are checked after clearing
and restoring exported code/storage/balances at the same addresses. Exports are
repeated from the same clean snapshot and compared byte-for-byte.

The optional custody mode adds six accounts to the six-core export:singleton,
protocol Safe,treasury Safe,treasury timelock and two paired Safe guards. Only the treasury timelock
occupies an existing allocation slot, preserving its exact15M balance. All other
added accounts are zero balance. Python materialization rejects code/state hash
changes, bad Safe pointer/count/threshold/nonce, signer overlaps, duplicate
normalized addresses, collision with another allocation, treasury zeroing,
extra value and manager-state overwrites. Exact100M PW/C00,15M RewardVault and
70/20/10 remain unchanged. NativeMinter stays absent. No post-genesis treasury or
RewardVault double funding is added.

The pure Python state digest check binds a reviewed exact export; it is not a
substitute for owner/role getters or actual final-genesis VM tests. The committed
fixture contains only conspicuously synthetic test addresses and fake manager
code; it is NEVER production input. Its structural C00 hash is
b69a6caff40a7f0c4b983dc90ce775781c1f00f85d6f14e9689b9811be3c791b.
Candidate outputs always retain deployable=false/genesisApproved=false.

## Offline reproduction and review workflow

```sh
forge build --offline
python3 scripts/mainnet/verify_custody_artifacts.py
forge test --offline
# Synthetic fixture only; no production approval:
python3 tests/integration/build_custody_fixture.py
python3 -m unittest discover -s tests -p 'test_*.py'
# Requires existing three digest-pinned public source archives and their exact
# build_manager.py source extraction; otherwise fail, do not substitute stubs:
python3 scripts/mainnet/test_custody_manager.py --archives /path/to/public-archives --forge /path/to/forge
```

For a FUTURE offline export under separately reviewed public inputs (copy only
PUBLIC metadata into the permitted genesis-build directory, never keys):

```sh
GENESIS_PUBLIC_MANIFEST=genesis-build/public-inputs.review.json GENESIS_STATE_OUTPUT=genesis-build/custody.accounts.review.json forge script contracts/script/CustodyGenesisState.s.sol:CustodyGenesisState --offline
python3 scripts/mainnet/custody_state_review.py --public-manifest genesis-build/public-inputs.review.json --states genesis-build/custody.accounts.review.json --output genesis-build/public-custody.review.json
```

No --broadcast, RPC, wallet or key arguments. The Solidity exporter refuses to
overwrite an existing output file before reading inputs or building any state. The state-review tool writes a NEW
file without overwrite and explicitly clears publicAddressesReviewed and
custodyProposalApproved. Owner must review/reapprove the public address/state
bundle before candidate construction; final genesis hash and transaction consent
are independent. The public custody fields are mode,safeSingleton,protocolSafe,
treasurySafe,protocolGuard,treasuryGuard,protocolOwners[5],treasuryOwners[5],stateSha256. Treasury allocation
address is its timelock, governanceProposer is protocolSafe, and core timelock is
the protocol timelock. No production signer defaults exist. Do not use the legacy
DevDeploy/DeployProduction paths for this custody model.

## Actual validation and limits

- Full default Solidity suite:782 passed,0 failed,0 skipped. Latest focused custody
  suite:15 passed, including native inbound/outbound,20% FeeDistributor receipt,
  quorum/permissions, cancellation, early/replayed execution, floor, isolation,
  timelocked controller and Safe-role migration, guarded Safe configuration, Safe setup lock and full export repeatability/restoration.
- Exact pinned ICM40e1c89/ValidatorMessages/OZ5.0.2 manager suite:18 passed. Cached
  extracted sources checked against all three pinned public archives before build.
  Actual proxy admin, PoA and manager ownership/upgrade controls tested using the
  protocol Safe and48h timelock. Warp messages are MOCKED in the unit EVM; these
  results do not prove accepted P-Chain conversion or live consensus.
-1000/1000 initialization succeeds;1/1 fails at20% churn. Immediate1000 removal
  fails;400 reduction succeeds, another1 in the same window fails; after3600s,
  320 of remaining1600 succeeds. Full replacement requires a separately reviewed
  active membership/acknowledgment plan, not an assumed one-step removal.
- Python suite with cached native/Linux artifacts:171 passed,0 failed,0 skipped.
  macOS node/plugin --version actually executed; Linux AMD64 ELF/hash checks
  passed. Linux executable execution and final-custody genesis live-VM testing
  were NOT performed on this Mac. Without those env paths the two optional binary
  checks skip, explicitly requiring PRIMEWAVE_NATIVE_TEST_DIR and
  PRIMEWAVE_LINUX_TEST_DIR. No node or blockchain startup occurred.
- Two validators remain non-resilient: either outage/partition may halt the pilot;
  separate AZs do not remove AWS-account/region/operator correlation. No weight,
  churn or risk acceptance was approved here.

Safe execution receipts must also show inner ExecutionSuccess/true and expected
state changes: an outer status1 receipt alone is insufficient when Safe allows
an inner failure. Owner must specify a bootstrap gas payer funded under explicit
spending authority from an existing C00 allocation; the treasury timelock cannot
pay its own first transaction without an external payer. No extra genesis gas
allocation or automatic funding was invented. Tests use synthetic approved-hash
signature mode, not generated private keys; real signing/custody remains untested.
Tests ran with Foundry1.8.1 and pinned solc0.8.30/Shanghai/IR; different compiler
settings/remappings must fail artifact hashes until explicitly rebuilt/reviewed.

## Remaining production blockers

Independent review of the policy adapters and complete ownership graph; actual
PUBLIC Safe/emergency owner addresses and distinct custodian evidence; approved
implementation selection; final addresses/timestamp/fork/ChainID decisions;
actual SubnetID-bound manager/library/proxy/PoA state export and authenticated
conversion proof; final-genesis VM ownership/custody verification; genuine hosts,
recovery/monitoring and exact owner transaction approvals. Source-based treasury
export is now implemented, but a final production genesis cannot be created from
unresolved inputs. Readiness requires the pinned custody mode and actual final
VM custodyStateSha256/role proof; no old development layout can silently pass.

No external security audit or production readiness is claimed. All execution
gates remain blocked; AWS requests/approvals/history and C00 economics untouched.
