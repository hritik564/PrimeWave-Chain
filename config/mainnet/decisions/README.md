# Mainnet owner decision package — unapproved

Baseline f0a056cd657d8fa34592d2527f678e62d9b48c68; DIRECT_MAINNET.
Run offline: `python3 scripts/mainnet/check_decision_package.py`.
REVIEW_PACKAGE_CONSISTENT is structural/numerical validation, never readiness,
consent, a signer instruction or authorization. Every approval remains false;
all production signer/contract addresses and NodeIDs are unresolved/null. Nothing
is copied into deployment approvals. Economics and historical AWS records remain
unchanged. PWUSD remains frozen.

Treasury custody source candidate is now implemented; see
[MAINNET-CUSTODY-READINESS](../../../docs/MAINNET-CUSTODY-READINESS.md). The
limitations below describe the original legacy contracts, not the new unapproved
Safe/OZ custody exporter. Its new policy adapters still require independent review.

## Chain ID recommendation and offline collision evidence

Retain **73571001** as the candidate, pending owner selection. It is an EVM Chain
ID, not Avalanche's Primary Network ID1, SubnetID, BlockchainID or NodeID.

The available public [Ethereum Lists/Chainlist registry](https://chainid.network/chains.json)
snapshot was retrieved2026-11-22T04:25:57.788593Z. This task performed a new LOCAL
collision scan of that existing snapshot under strict offline constraints; no new
network fetch occurred. It contains2899 entries and no listed73571001 collision.
`chain-registry.snapshot.json` retains public chainId/name fields only; raw-source
and sanitized-file SHA256 values and the original retrieval time are in
package.review.json. `offlineReviewedAt` is distinct: it does not freshen the
registry's checkedAt. Only one registry source was available, not independent
corroboration by multiple registries. No global allocation authority guarantees
uniqueness; unlisted/private chains may use the ID. Absence is not a reservation.

The candidate differs from development73571, legacy77/1337/31337, Primary IDs1/5,
and Avalanche C-Chain EVM IDs43114/43113; all are denied by chain_id.py. Optional
Fuji Primary ID5 is configured but its PrimeWave EVM Chain ID is still null.
A separately selected Fuji EVM ID must differ from Mainnet; no Fuji candidate is
approved or manufactured here. Before any ceremony, refresh the registry snapshot
within24h and obtain approval of the exact candidate/snapshot digest. The current
record has ownerApproved=false and approvedChainId=null; registry evidence alone
cannot satisfy chain_id.approved or either production gate.

## Governance and custody decision matrix

The C00 governance policy already requires role separation,48h ordinary-change
delay and a3-of-5 emergency group. Proposed protocol/treasury3-of-5 thresholds
are recommendations, not approved compositions. **No signer addresses supplied.**

| Role | Recommended control/ownership | Unresolved owner input / implementation evidence |
|---|---|---|
| Protocol admin | Distinct3-of-5 production multisig -> protocol timelock proposer | Five public signer addresses, custodians/ownership proof, audited multisig artifact |
| Protocol timelock | >=172800s, controls upgrades/ordinary admin; no direct EOA bypass | Exact artifact/state; existing PrimeWaveTimelock is marked development-only |
| Validator manager | ValidatorManager proxy owned by PoA controller; PoA controller owned by protocol timelock | Separate final proxy/controller addresses, linked code and getter/state proof |
| Proxy upgrade authority | ProxyAdmin CONTRACT owned by protocol timelock | Distinguish ProxyAdmin address from owner; exact immutable/admin-slot and owner evidence |
| Treasury | Separate3-of-5 group -> value-capable48h treasury timelock; receive approved15M allocation and existing20% fee share | Five distinct public signers, treasury timelock/multisig artifacts, tested native receiving/spending; address remains null |
| Emergency | Separate3-of-5, immediate pause/unpause through target-granted roles only | Five distinct public signers; target permission graph; never protocol/treasury upgrade or withdrawal authority |
| P-Chain subnet control / fee-return owners | Separately reviewed owner sets and thresholds | Public P-Chain addresses, custody proof and exact per-transaction owners/ceilings; EVM multisig alone does not establish P-Chain control |

Keep different key material/operators across roles per C00; overlap needs a
separate explicit owner decision, not implied by this package. No identities or
keys were generated. Treasury addresses change no amounts or fee economics.

Confirmed compatibility caveats:

- Custom PrimeWaveTimelock fixes48h, but lacks native-value receive/value-bearing
  execute. Do not allocate treasury PW there: it cannot implement the required
  native custody/spending flow. Recommend reviewing a value-capable audited
  TimelockController artifact owned/proposed by the separate treasury multisig;
  do not silently substitute or deploy it. DevTreasury is not a custody solution.
- The current genesis authoring path exports six core contract states; it does
  not yet export a separately funded treasury multisig/value-timelock constructor
  state. managerPredeploys only adds zero-balance accounts and must not overwrite
  the15M treasury allocation. A selected treasury custody implementation therefore
  needs an explicit reviewed artifact/state export path before final genesis.
- EmergencyMultisig.execute is a generic target.call, not a selector allowlist.
  Pause-only scope follows permissions granted by destination contracts. Giving
  it manager ownership, treasury/proxy authority or broad token permissions
  would violate the intended scope. Pause-controller rotation needs separate
  review; the contract alone cannot prove absence of unintended authorities.
- FeeDistributor has immutable destinations/no admin setter; its emergency pause
  authority is not ownership. Never assume a timelock can change its fixed split.
- Final readiness now requires governance.owner=reviewed protocol timelock,
  distinct from the ProxyAdmin contract, and matching proxyAdminOwner in both
  securityReview and vmCompatibility. It no longer conflates those two roles.

Source references: [C00 governance policy](../../../docs/PRIMEWAVE_GOVERNANCE_POLICY.md),
[PrimeWaveTimelock](../../../contracts/src/PrimeWaveTimelock.sol),
[EmergencyMultisig](../../../contracts/src/EmergencyMultisig.sol),
[genesis authoring](../../../contracts/script/GenesisConstructorState.s.sol).

## Initial weights recommendation

Propose validator-1=1000, validator-2=1000; equal50% shares. These are relative
manager/consensus units, **not PW allocations, AVAX balances or token stake**.
Propose maximumChurnPercentage=20 and churnPeriodSeconds=3600, separately gated.
The pinned ValidatorManager requires totalWeight*maximumChurnPercentage>=100 and
percentage1..20. Two weights of1 fail at20%;1000+1000 passes with400 initial
aggregate churn units per period. This does not permit immediate removal of a
1000-weight node: cumulative churn limits require a reviewed staged membership
plan, ongoing consensus, individual transaction approvals and governance delay.

Two validators remain a non-resilient pilot: either outage/partition may halt
progress; equal weights do not add availability or independent fault tolerance.
Separate Sydney AZs do not remove account/region/operator compromise risk. Avoid
claiming a pinned consensus threshold was measured here; actual activation,
consensus and failure behavior still require real production evidence. Operator
independence and this specific weight/churn risk acceptance remain unapproved.

Pinned source: [ValidatorManager at40e1c89](https://github.com/ava-labs/icm-services/blob/40e1c898d44242aee25693a9cde4bc2485bd8242/icm-contracts/avalanche/validator-manager/ValidatorManager.sol).

## Protected manager bootstrap comparison

| Option | Security/tradeoff | Recommendation / gate compatibility |
|---|---|---|
| Subnet-bound initialized genesis | After accepted CreateSubnet, compile/export base manager initialized to actual SubnetID, owner and linked addresses. Prevents a public initialize window. Requires exact constructor/immutable/storage export and VM proof at FINAL addresses; temporary proxy constructor addresses must never leak into copied immutables. | **Recommend.** Fits the corrected CreateSubnet -> final artifacts -> CreateChain boundary. More offline artifact work; no skipped ownership tests. |
| Owner-controlled atomic initialization | An owner-restricted atomic transaction may combine upgrade+initialize with reviewed calldata; a public initializer waiting for a later transaction is unsafe. Authority/target/calldata/replay must be tested. A naked uninitialized proxy is never acceptable. | Alternative only after separate design review. Current CreateChain gate requires managerInitializedAtGenesis=true, so a plan relying only on post-CreateChain base initialization remains BLOCKED and is not made compatible by selecting this label. |

Pinned implementation constructor with ICMInitializable.Disallowed locks its own
initializers, **not an empty proxy's independent storage**. Proxy constructor data
must initialize manager base settings before public exposure. ProxyAdmin ownership
is independent of manager ownership. PoAManager is a separate owner-controlled
wrapper with an immutable manager pointer; conversion targets the ValidatorManager
proxy, not the wrapper or ProxyAdmin. Initialize the actual initial validator SET
only after authenticated conversion Warp data exists; do not confuse that later
step with pre-genesis base manager initialization. Replay and conversion message
binding must be proved by the final artifact tests, not declared by this package.

Pinned sources: [PoAManager](https://github.com/ava-labs/icm-services/blob/40e1c898d44242aee25693a9cde4bc2485bd8242/icm-contracts/avalanche/validator-manager/PoAManager.sol),
[OpenZeppelin5.0.2 proxy](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.2/contracts/proxy/transparent/TransparentUpgradeableProxy.sol).

## Gate mapping and exact remaining decisions

CreateSubnet: supply a genuine approved ChainID/snapshot and production custody,
host/identity/recovery evidence, then owner-review preSubnetReview with the chosen
governance, weights and protected bootstrap POLICY. Its exact single transaction
request binds preSubnetReviewSha256, signer and fee ceiling; genesisSha256=null.
This package itself cannot serve as an approved preSubnetReview.

CreateChain: after the accepted SubnetID, finalize constructor public managerSubnetId,
exact genesis/bytecode and security/VM ownership/initialization evidence bound to
that ID. Obtain independent CreateChain approval. Missing final artifacts, unsafe
proxy initialization or mismatched owner still blocks. Current mainnet governance
addresses/artifacts do not exist in these records; no final readiness is claimed.

Owner decisions next (no blanket Mainnet approval):
1. Select candidate73571001 subject to a fresh registry review before ceremony.
2. Confirm protocol/treasury multisig thresholds and supply PUBLIC signer/custody
   addresses/ownership evidence; select actual production multisig/timelock artifacts.
3. Supply separate five emergency public signers and confirm target-level pause-only
   permissions; explicitly decide any proposed signer/operator overlap.
4. Approve or revise1000/1000 weights,20%/3600s churn and the associated two-node risks.
5. Select subnet-bound initialized genesis as POLICY; subsequently review exact
   artifacts/actual SubnetID/ownership and conversion sequence under separate gates.
6. Separately review P-Chain control/return owners, funding budgets and signer
   authorities. None of these policy choices authorizes AWS, keys, spending,
   signing, conversion, node startup or PWUSD deployment.

## Validation performed for this package

-165 Python tests:163 passed,2 skipped,0 failed. The optional binary tests require
  PRIMEWAVE_NATIVE_TEST_DIR / PRIMEWAVE_LINUX_TEST_DIR; these were not supplied.
  No native/Linux executable or node was started for this decision package.
-23 direct-readiness tests and6 package tests also pass under Python optimization.
- Python type checks pass for the two affected source modules (mypy1.18.2,
  check-untyped-defs, follow-imports=skip, ignore-missing-imports).
- Cached pinned manager source matches its digest-verified upstream archive;
  package retains source hashes for custody/churn/initialization claims.
- Candidate scan passes against the unchanged stored registry snapshot. The
  checker refuses implicit approval, fabricated addresses, reduced emergency/
  timelock policy, changed economics and invalid weight/churn settings.
- Regression rejects ProxyAdmin/owner conflation and mismatched VM ownership.
  CreateSubnet still passes only its independent pre-Subnet policy/approval;
  CreateChain still requires actual SubnetID/final artifacts and its own approval.
- Production manifests/approvals, both AWS request digests and15 historical
  launch/stop files unchanged. All remaining operator evidence stays local.
