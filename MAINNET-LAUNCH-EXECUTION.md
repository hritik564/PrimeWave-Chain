# PrimeWave Mainnet — production input freeze and execution gates

Baseline **000b828b95424870090a055aa094139841f30d71**, branch
`codex/mainnet-blocker-resolution`. **NOT AUTHORIZED / NOT READY TO ACTIVATE.**
This document freezes the checklist, not production values. No approval is granted;
all existing manifests, contracts, locks and flags remain unchanged. DIRECT_MAINNET;
Fuji is optional, not an additional prerequisite. No PWUSD implementation here.

## Status and source of truth

| Status | Item | Evidence / next action |
|---|---|---|
| DONE | Correct branch/baseline; tracked tree initially clean | Historical untracked AWS records preserved and excluded from this commit |
| DONE | Offline combined manager/custody integration and Safe rebuild | [Integration evidence](docs/security-review/COMBINED-GENESIS-INTEGRATION.md); existing results only, no test/genesis regeneration |
| OWNER INPUT | Final ChainID, genesis fields, public custodians/identities, budgets | Complete the single checklist below; no keys or invented addresses |
| EXTERNAL REVIEW | Independent review of exact final architecture/artifacts | [Reviewer package](docs/security-review/README.md) plus combined addendum; owner disposition required |
| BLOCKED | Production host commissioning, actual-address export/VM import, single-transaction execution path | Runbook below; no safe turnkey Mainnet executor currently exists |
| BLOCKED | Existing readiness gates | Local read-only checks: PRE/createSubnet **25 blockers**; POST **22 blockers**; both signing=false, broadcastReady=false. Counts are observed planning-state errors, not separate workstreams |

Use `deploy/aws/sydney.existing-runtime.review.json` as the reconciliation source
(**M** below), never the original initial-launch template for Validator1. Let
**E** mean `M.environments.mainnet`, **R** mean `M.mainnetReadiness`, **P** mean
`config/mainnet/public-genesis-manifest.review.json`. Evidence refs `{path,sha256}`
require absolute existing non-symlink PUBLIC JSON <=16MiB and raw-file SHA256
(64 lowercase hex). Request digests use sorted compact canonical JSON instead;
do not confuse them with file hashes. Public records only; no credentials/keys.
The M template lacks P's newer custody subtree/managerSubnetId: future separately
reviewed reconciliation is required, not a waiver or a change made by this task.

## One production-input checklist

| Status | Exact fields / format / validation | Source of truth to reconcile after separate authorization |
|---|---|---|
| OWNER INPUT | `E.evmChainId=73571001` proposed; `chainIdApproved` remains false. Integer1000..2^53-1; no registry collision or reserved/project IDs (including73571/77/1337/43113/43114); different from optional Fuji | `config/mainnet/chain-id.review.json`, R.chainApproval/R.registry; `scripts/mainnet/chain_id.py`. Fresh source-authenticated chainid.network snapshot and checkedAt<=24h required; absence is not global uniqueness/reservation. No fresh registry fetch performed here |
| OWNER INPUT | `genesisTimestamp`: explicit positive integer Unix seconds; genesis `timestamp` matching hex quantity. Real `config.chainId`, `feeConfig`, `warpConfig`, supported individual fork activation fields and rewardManagerConfig; pin exact gasLimit/base-fee parameters | P.genesisTimestamp, `config/mainnet/genesis.review.json`, actual reviewed base genesis. `forkSchedule` in review template is not itself a deployable VM fork configuration; validate actual v1.15.1 fields, never invent defaults |
| DONE | C00: liquidity40M, treasury15M, team10M, rewards15M, presale1 5M, presale2/3 7.5M each; total100M PW /10^26 wei, no minter;70/20/10 | Existing approved C00 policy, P.allocationAddresses; uint256 native balances, exact sum, no extra payer allocation or double reward funding |
| OWNER INPUT | Seven `P.allocationAddresses.{liquidity,treasury,team,rewards,presale1,presale2,presale3}`: nonzero20-byte `0x` hex addresses, validate checksum if mixed case and independently verify custody | Treasury=treasury timelock, rewards=RewardVault. Others distinct; no overlap with signers/precompiles/code except explicit allocation aliases |
| OWNER INPUT | Three groups: `P.custody.protocolOwners[5]`, `treasuryOwners[5]`, `P.emergencySigners[5]`, each five valid unique public addresses; threshold3;15 distinct addresses and documented independent custody | P, `config/mainnet/decisions/package.review.json`; explicit owner confirmation to retain existing architecture/groups, >=172800s timelocks, no direct EOA admin, no modules/handler/refunds; public metadata does not prove key control |
| OWNER INPUT | `P.contracts.{timelock,emergency,feeVault,feeDistributor,registry,rewardVault}`, `custody.{safeSingleton,protocolSafe,treasurySafe,protocolGuard,treasuryGuard}`, treasuryTimelock=P.allocationAddresses.treasury; `governanceProposer=protocolSafe` | P.custody.mode=`safe-1.4.1-oz-5.6.1`; complete collision-free actual-address map. Synthetic B/E/A/D addresses are forbidden inputs. Guard/Safe pairing and self-admin role graph must match reviewed bytecode/state |
| OWNER INPUT | `E.managerProxy`, `managerImplementation`, `managerLibrary`, `proxyAdmin`, PoA public address; `P.managerAddress=E.managerProxy`; complete `managerPredeploys` | Exact linked artifacts; include generated ProxyAdmin account, constructor-derived immutable bindings, code/storage/account nonce (proxy consumes CREATE nonce); P.custody.stateSha256 and all code accounts bound to reviewed hashes |
| OWNER INPUT | `E.identities.validator-{1,2}.{nodeId,blsPublicKey,proofOfPossession,stakingCertificateSha256,environment,productionOnly}` | NodeID- CB58/checksum; BLS48bytes=`0x`+96hex, PoP96bytes=`0x`+192hex, certificate SHA256=64lowerhex; unique, environment=mainnet/productionOnly=true. Gates check syntax; genuine certificate/NodeID derivation and BLS/PoP cryptography also required. Fresh production-only ceremony separately authorized; no demo/Fuji reuse |
| OWNER INPUT | `preSubnetReview.validatorWeights` / `securityReview.validatorWeights`: validator-1/2 positive uint64; proposal1000/1000. `maximumChurnPercentage=20`, `churnPeriodSeconds=3600` proposed | Same exact values in every request; owner confirmation required. Pinned limits1..20%, period1..86400, total<2^64 and total*percentage<2^64 and>=100; two-validator halt/correlation/replacement risk explicitly accepted; no one-step1000 removal at20% |
| BLOCKED | `E.subnetId`, `P.managerSubnetId`, securityReview/vmCompatibility.subnetId, then `E.blockchainId`, `vmId` | Accepted P-Chain transaction receipts; canonical valid CB58 IDs. No future ID fabricated. Base manager/proxy initialized at genesis; validator-set activation waits for actual conversion/Warp proof |
| OWNER INPUT | Dedicated PW payer: `payerPublicAddress`, `sourceAllocation`, `sourceCustodianPublicAddress`, `nativePwBudgetWei`, `expiresAt`, `chainId`, `transactionApprovalReference`; E.pwGasSourceRole | `docs/security-review/BOOTSTRAP-GAS-PAYER.review.json`. Select existing-allocation funding route; valid EVM addresses, positive decimal integer wei budget, timezone-aware expiry, exact funding amount/gas cap/return policy and source custodian authority. No automatic transfer, Safe refund or governance role. Treasury cannot fund its own first external transaction |
| OWNER INPUT | `E.pChainFundingAddress` P-avax1… checksum-valid, `signerKeystoreAlias` matching `pw-mainnet-[A-Za-z0-9_-]+`, `pChainBudgetAVAX`, `validatorBalanceAVAX`; P-Chain subnet owner address set/threshold and conversion remaining-balance/disable-owner records | E and each transaction's reviewed parameters; positive finite decimal AVAX strings, explicit total/fee/per-validator funding and replenishment caps. Distinguish fee payer from subnet control; EVM three groups do not automatically determine P-Chain ownership. Subnet owner is unsigned CreateSubnetTx `secp256k1fx.OutputOwners.{Threshold,Addrs,Locktime}`: explicit valid threshold, sorted unique20-byte owners and locktime; conversion return/disable-owner serialized fields must be confirmed against pinned tx schema, not guessed from ICM's later-addition PChainOwner. Do not inherit upstream1-of-1 owner/default balances |
| OWNER INPUT | Each `R.transactions.<operation>.request`: operation,networkId=1,chainId,transactionCount=1,signerAlias,parameters,maximumFeeAVAX,maximumTotalSpendAVAX,reviewed/reference | Request-specific approved parameters/asset-appropriate PW limits also required; AVAX fee<=total. Approval fields approved/reference/issuedAt/expiresAt/binding: timezone-aware <=24h, bind operation/network/account340379122975/region ap-southeast-2/canonical requestSha256. No approval set by this task |
| BLOCKED | Host instance/volume IDs, UUID/mount, IPs/P2P, SSM targets; R.hostEvidence cloud/local/operations; local signatureAggregatorUrl=http://127.0.0.1:PORT (no credentials) | M and genuine fresh observations, not hand-written PASS files; recovery/incident/alert records digest-bound. node identity/instance/EBS/UUID must agree; never fall back to root DB or initialize a replacement chain |

## Exact existing commands and hard execution boundary

These are **review/check commands**, not authorization or transaction executors.
Run at repository root. Use the unchanged review manifest for today's checks;
a future approved, reconciled public manifest must replace M only after review.

```sh
M=deploy/aws/sydney.existing-runtime.review.json
R() { python3 scripts/deploy/aws_pilot.py --manifest "$M" --environment mainnet --readiness --stage PRE_MAINNET_LAUNCH --operation "$1"; }
R createSubnet
# After an independently collected fresh registry snapshot (PUBLIC_REGISTRY absolute path):
python3 scripts/mainnet/chain_id.py --registry "$PUBLIC_REGISTRY" --candidate 73571001
# After actual owner decision only, CHAIN_DECISION points to that public record:
python3 scripts/mainnet/chain_id.py --registry "$PUBLIC_REGISTRY" --verify-approval "$CHAIN_DECISION"
```

Existing offline genesis tools: `build_manager.py --archives "$PUBLIC_ARCHIVES"
--libraries-manifest "$PUBLIC_LIBRARY_RECORD"` builds only in a NEW pinned-manager
output directory and refuses an existing one. It is not the complete production
state exporter; never delete/overwrite the locked directory to run it. The
custody-only author is `GENESIS_PUBLIC_MANIFEST=genesis-build/public-inputs.review.json
GENESIS_STATE_OUTPUT=genesis-build/custody.accounts.review.json forge script
contracts/script/CustodyGenesisState.s.sol:CustodyGenesisState --offline` (no RPC or
broadcast; output must not exist). It exports12 custody accounts, **not** the final
manager graph. `custody_state_review.py --public-manifest "$PUBLIC_INPUTS"
--states "$CUSTODY_STATES" --output "$NEW_PUBLIC_REVIEW"` writes a new UNAPPROVED
copy. After the missing actual-address manager bundle is independently prepared,
`python3 scripts/mainnet/genesis_candidate.py --public-manifest "$PUBLIC_INPUTS"
--constructor-state "$CUSTODY_STATES" --base-genesis "$BASE_GENESIS"` materializes
an unapproved candidate, using PUBLIC_INPUTS.managerPredeploys for manager accounts.
No complete production combined exporter is currently supplied: STOP before final
artifact approval; test-only `combined_genesis.py` must not be repurposed as one.

VM validation: [exact final-genesis specification](docs/security-review/FINAL-GENESIS-VM-VALIDATION.md).
Existing `.github/workflows/primewave-live-vm.yml` / `tests/live/primewave_vm_test.go`
use `PRIMEWAVE_PREDEPLOY_FIXTURE` and `PRIMEWAVE_VM_BINARY`, then
`go test ./vms/rpcchainvm -run '^TestPrimeWaveReleasedVMLive$' -count=1 -v -timeout=180s`
in pinned AvalancheGo source. **Do not run for production proof as-is:** the test
requires fixture-only labels, generates an ephemeral key and reconstructs/modifies
genesis. No existing command imports exact approved final genesis unchanged;
implement/review that adapter under separate authorization before any such test.
No VM/node test or identity creation was performed by this documentation task.

Ordering verified against cached pinned Avalanche Deploy source
`5989dd8a057f0c074b7fd6a656fb401b0222951c`, `tools/create-l1/main.go`:
IssueCreateSubnetTx -> IssueCreateChainTx -> IssueConvertSubnetToL1Tx -> conditional
InitializeValidatorSet. Pinned ICM40e1c898d44242aee25693a9cde4bc2485bd8242 initializes
manager settings once, then validates conversion Warp data in initializeValidatorSet.
The all-in-one tool signs/broadcasts multiple steps, defaults subnet owner to1-of-1,
hardcodes validator weight as `units.Schmeckle` instead of the proposed1000/1000,
and has manager deployment/raw-key paths incompatible with this ceremony. Its
`--genesis-proxy-address` branch describes post-conversion implementation upgrade;
that is **not** proof of our fully initialized genesis path. Fuji renderer
`scripts/mainnet/fuji_rehearsal.py` is Fuji-only, not a Mainnet executor. There is
**no reviewed single-transaction Mainnet signing/broadcast command** in this repo;
STOP until each exact unsigned payload and custody-preserving signing path is
reviewed. Do not guess flags or run create-l1 wholesale. RegisterL1ValidatorTx is
for later additions; initial validators are supplied by ConvertSubnetToL1Tx.

## Numbered deployment runbook — every GO is narrow

| # / current status | STOP/GO and separate owner authority | Exact next check after the gate / recovery limit |
|---|---|---|
| 1 OWNER INPUT | Freeze checklist public values and confirm retained custody/groups; approve neither transactions nor provisioning | Fresh registry decision command above; then `R createSubnet` to expose remaining blockers |
| 2 EXTERNAL REVIEW | Reviewer accepts exact commit/artifacts, resolves Critical/High findings and owner dispositions; explicit no-backdoor/quorum-loss acceptance | `R createSubnet`; no source/test success substitutes for reviewer evidence |
| 3 BLOCKED | Fresh read-only AWS reconciliation; V1 **start-existing only** and V2 **launch-only** spending approvals are independent, request-bound/time-capped. No launch/start command authorized here | After real facts exist: `python3 scripts/deploy/aws_pilot.py --manifest "$M" --host validator-1 --environment mainnet --preflight --cloud-facts "$V1_CLOUD" --host-facts "$V1_LOCAL"`; repeat for validator-2 and its files. Preserve all storage; stopping/termination/deletion each needs separate approval |
| 4 BLOCKED | Separate provisioning, production identity, recovery/monitoring and **host-start/Primary Network sync** approvals. Sync Mainnet P-Chain before ceremony, partial-sync=true, sybil protection, private RPC, public9651 only | `R createSubnet`; first node sync cannot be deferred until after conversion as old runbook step12 suggests. Tracking new BlockchainID later is separately controlled; no replacement DB/identity |
| 5 BLOCKED | Pre-Subnet plan and exact **CreateSubnetTx** spending/signing/broadcast approval; owner set, threshold and AVAX caps explicit. Final genesis/future SubnetID not required | `R createSubnet`; only after PASS and reviewed single-op executor may this one transaction be submitted. Reconcile accepted tx/SubnetID before `R createChain`. No irreversible P-Chain rollback |
| 6 BLOCKED | Bind accepted SubnetID; complete actual-address manager/custody export, final genesis independent review and separately authorized isolated VM test; final hash approval | Candidate command above, then exact VM specification; no executable final-import adapter yet. After evidence exists: `R createChain`. Never reuse synthetic state or expose uninitialized proxy |
| 7 BLOCKED | Separate exact **CreateChainTx** approval binds accepted SubnetID, VMID and final genesis bytes/hash | `R createChain`; submit only with reviewed single-op path. Retain accepted BlockchainID/receipt, then `R convertSubnet`. No delete/recreate fallback |
| 8 BLOCKED | Separate exact **ConvertSubnetToL1Tx** approval: actual manager chain/address, two NodeIDs/BLS PoPs, weights, balances, return/disable owners | `R convertSubnet`; reconcile accepted conversion and authenticated Warp payload, then `R initializeManager`. No automatic registration/retry or AVAX top-up |
| 9 BLOCKED | Separate exact **initializeValidatorSet** EVM approval; base/proxy initialization already secured at genesis. Additional calls each require a new approval, not one logical-stage blanket | `R initializeManager`, then `R activateValidators`. The latter is an evidence stage, not a distinct named Avalanche transaction; inspect what actual action is needed. Public conversion initialization does not bypass owner's spending authorization |
| 10 BLOCKED | Separately authorize L1 tracking/host activation, verify both-node accepted blocks, IDs, ownership, validator weights and P-Chain health; bounded PW payer funding/commissioning authority | `python3 scripts/deploy/aws_pilot.py --manifest "$M" --host validator-1 --environment mainnet --rpc-check` (repeat validator-2), then `R nativeTransfer`, `R feeDistribution`. At most10 transfers/<=1h reviewed batch, per-call amount/gas ceilings; Safe inner success and value+gas/70-20-10 accounting mandatory |
| 11 BLOCKED | Separately authorize production recovery drill, then digest-bound final acceptance/public access | `R recoveryDrill`, then `python3 scripts/deploy/aws_pilot.py --manifest "$M" --environment mainnet --readiness --stage POST_MAINNET_ACCEPTANCE`. Two validators are not HA; fence old identity before restore. Stopping either may halt chain; no unauthorized stop/restore |

Any FAIL, missing evidence, wrong hash/identity, ambiguous receipt, budget expiry or
resource pressure means STOP. Reconcile the same request/tx ID before retry; never
create replacement chains or keys. Chain creation/conversion/spent fees cannot be
rolled back. Lost Safe quorum or unusable guard can permanently lock control;
existing delayed atomic role migration works only with a usable authorized quorum/
executor. Emergency cannot rescue treasury or upgrades. See existing recovery
matrix in the reviewer package; no new recovery authority is granted here.

## AWS evidence: only outstanding checks and boundaries

Local stop report: V1 `i-0d2a9cee4dc9d9134`, root `vol-0c4f4e8b2968f1929`, data
`vol-0aab1844ff6cfab37`; stopped/preserved at2026-11-22T03:58:35Z; later local
V2 report observed it stopped at04:20:42Z. These are historical, not fresh AWS reads.
V2 dry-run digest `7011ea2d7885584e48371283f1d828699db7d68a8a5eb52609d1bc674964f2f3`
succeeded with DryRunOperation; no V2 instance then. SG/profile/AMI authorization
is recorded; do not repeat DryRun. Remaining: current account/session/quota/capacity/
duplicates/attachments and SG/IAM/AMI drift, eventual running status/SSM, actual
UUID/NVMe EBS binding, encrypted32/150GiB lifecycle, measured>=2700 read IOPS,
profile CPU/RAM thresholds, private RPC/firewall/time sync, monitoring and recovery.
No AWS calls now. Preserve V1; no old launch approval permits restart or V2 launch.
Retained EBS charges continue; any continuation/start/launch needs a new spending
window/expiry and explicit stop decision, never an assumed automatic shutdown.

## Minimal reviewer and PWUSD handoff

Reviewer: source000b828b95424870090a055aa094139841f30d71 plus
`docs/security-review/README.md`/combined evidence; custom
PrimeWaveCustodyTimelock, TimelockOnlySafeGuard, PauseOnlyEmergencyMultisig/base,
authoring and gates. Focus: initializer takeover/missing slots or child accounts,
immutable/admin/library mismatches, timelock/value/module/refund bypass, arbitrary
delayed governance, emergency escalation, quorum/guard permanent lock and rotation.
Require independent pinned rebuild/retest, explicit findings/dispositions and
actual final-genesis VM role/state proof; Safe byte reproducibility is not an audit.

PWUSD V1 remains frozen until Mainnet POST acceptance, stable target ChainID/RPC,
separate token admin/minter/burner/custody/supply-policy decisions, independent
contract review, bounded existing-PW deployment gas and separate deployment/signing
approval. Intended V1 is mintable/burnable ERC-20; $1 is issuer reference display,
not market peg, backing or redemption. No implementation/deployment in this task.
