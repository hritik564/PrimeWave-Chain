# Sydney DIRECT_MAINNET execution handoff

Authoritative for the selected AWS Sydney pilot. DIRECT_MAINNET is the approved
strategy, not authorization to spend, provision, sign, broadcast or start nodes.
Fuji is optional: see OPTIONAL-FUJI.md. Never fabricate Fuji evidence or set
rehearsalPassed to bypass a gate. Historical Netcup hosts remain inaccessible.
Mumbai adapters remain supported; deployment.review.json is their review template.

## State and source of truth

Use `sydney.existing-runtime.review.json` as the **new reconciliation proposal**:
it copies public Validator1 IDs and the stopped observation from the unchanged
launch/controlled-stop evidence. It records the observed stop at2026-11-22
09:28:35 IST, not a fresh AWS verification. Filesystem UUID, mount and production
identity are intentionally unresolved. Its instance/volume/launch record blocks
initial relaunch of Validator1. No historical approval or idempotency record is
reset. `sydney.deployment.review.json` remains the original initial-launch review
layout; never use it to replace or relaunch the existing Validator1. Fresh
read-only AWS verification is mandatory before any separately approved action.

`mainnetReadiness` references public JSON evidence by absolute path and raw-file
SHA256. `readiness.schema.json` documents the envelope; the executable validators
also check contents, cross-file bindings and accounting. A PASS means validated
supplied evidence, not proof that arbitrary operator JSON is authentic. Collect
real API observations, retain source provenance and obtain exact owner reviews;
synthetic test fixtures are never deployment evidence. Do not publish secrets.

## Ordered operations — no implicit approvals

1. Read-only verify account340379122975/profile primewave-sydney/region
   ap-southeast-2, existing Validator1 stopped instance/volume IDs and retained
   attachments. Preserve both volumes. Do not reissue an initial launch.
2. Prepare Validator2 independently with aws_launch_prepare.py --host validator-2.
   Its approval stays false. Obtain a separate expiring request-bound spending
   approval before its one EC2 launch. Successful dry runs reserve no capacity.
3. Obtain a separate **start-existing-Validator1** approval before any EC2 restart.
   Preserve volumes and launch record; do not generate a new instance/identity.
4. Obtain separate host-provisioning approval. Review SSM transfer bucket/KMS,
   stable service UID/GID, auditing, logs, monitoring/alert destination, OS-root
   layout, storage-growth and incident response. Use common Ansible via the AWS
   adapter; no duplicate implementation or SSH ingress. An inventory export
   keeps create_identities=false and start_node=false.
5. Configure/validate Ubuntu24.04 x86-64, SSM-only administration, publicTCP9651
   only, private127.0.0.1:9650 RPC, loopback metrics, IMDSv2, time sync and actual
   service-selected partial-sync-primary-network=true/sybil protection. Data EBS
   must be encrypted retained>=150GiB gp3,3000IOPS/125MiBps, separate32GiB root.
   Mount actual UUID without nofail/noauto; match local NVMe serial to reviewed
   EBS ID; never format/adopt reused data or fall back to a root filesystem.
6. Under separate production identity/custody authorization create and secure
   production-only identities; export public NodeID/BLS/PoP/certificate digest.
   Verify public certificate hash and private-file permissions without including
   key contents in evidence. Bind public identity/instance/volume/UUID records.
   Configure identity fencing and test encrypted off-host recovery procedures
   before production. Never reuse demo/Fuji keys or run duplicate identities.
7. Finalize approved distinct Chain ID (73571001 is only a candidate), fresh
   <=24h registry snapshot/decision, C00 constructor-state genesis and manager
   artifacts. No post-genesis mint; exactly100M PW;70/20/10 fees unchanged.
   Rewards seed RewardVault exactly15M once with initialized funding counters;
   no extra funding EOA allocation or post-launch double funding. Review exact
   bytecode/storage, initialized governance, proxy/library/admin, ownership
   thresholds, weights, timelock and protected bootstrap. Require isolated pinned
   v1.15.1/protocol46 tests of the **actual final genesis**, not historical fixture
   results. Neither local VM testing nor an optional Fuji run signs Mainnet.
8. Review every operation's parameters, production signer alias, AVAX budget,
   fee/total-spend ceilings, custody and incident response. Each operation has its
   own expiring approval bound to the canonical reviewed request digest. No
   blanket approvals, raw keys, all-in-one CLI or timeout retries with new IDs.
9. Complete PRE_MAINNET_LAUNCH for the selected operation. Initial createSubnet
   does not require future on-chain receipts or post-launch acceptance. If using
   subnet-bound genesis, the actual accepted SubnetID is a later binding: finalize
   and reapprove genesis/requests before CreateChain. Alternatively review a
   tested owner-controlled atomic upgrade+initialize bootstrap. Never expose a
   publicly callable uninitialized proxy or invent a future SubnetID.
10. After exact CreateSubnetTx approval, sign/broadcast only that transaction;
    reconcile acceptance and retain SubnetID. Rebind/review final artifacts and
    CreateChainTx request to that actual ID. After independent CreateChainTx
    approval, submit it and retain BlockchainID/VMID/receipt. Each step pauses on
    errors or unknown outcomes to reconcile accepted state; never recreate a chain.
11. Independently approve ConvertSubnetToL1Tx with actual manager chain/address,
    two production NodeIDs/BLS PoPs/weights, balances and return owners. Preserve
    accepted conversion data. Independently approve the reviewed manager/proxy
    initialization and initializeValidatorSet using actual conversion Warp data
    and owner-operated aggregator; verify ownership and registrations/weights.
    Each transaction within a logical stage requires its own reviewed request and
    approval; do not combine multiple irreversible transactions in one authorization.
    The readiness operation record covers one request, not a blanket stage grant.
12. Under separate host-start/activation permissions start existing nodes using
    preserved storage binding/identities. Verify P-Chain health/sync, expected
    validator registration/weights, advancing accepted blocks, genesis/chain IDs
    and matching hashes. Public-network node start and validator activation are
    independently authorized operations, not consequences of EC2 health.
13. Separately authorize bounded native PW commissioning and FeeDistributor calls
    under exact amount/gas ceilings and existing C00 allocation spending authority.
    At most10 smoke transfers and<=1h per reviewed commissioning batch; no grant
    or post-genesis mint. Compare fixed-block balances, actual receipts on both
    nodes, sender=value+gas decrease, recipient increase, accepted hashes and
    70/20/10 event/cumulative-accounting deltas including concurrent call gas.
14. Separately authorize a controlled production recovery/restoration drill.
    Preserve identity/DB/registration and fence the old host; same-AZ EBS reattach
    or separately authorized consistent encrypted restore across AZs. With two
    validators either outage halts consensus: a non-resilient pilot, not HA.
15. POST_MAINNET_ACCEPTANCE requires genuine production observations, both-node
    receipts, registration/weights, P-Chain sync, advancing/matching blocks,
    successful native/gas/fee accounting, operational alerts and actual recovery.
    Obtain digest-bound final acceptance approval **before public access**.
    PWUSD remains frozen. No public access or PWUSD authorization is implied.

## Offline readiness commands

```sh
python3 scripts/deploy/aws_pilot.py --manifest deploy/aws/sydney.existing-runtime.review.json --environment mainnet --readiness --stage PRE_MAINNET_LAUNCH --operation createSubnet
python3 scripts/deploy/aws_pilot.py --manifest deploy/aws/sydney.existing-runtime.review.json --environment mainnet --readiness --stage POST_MAINNET_ACCEPTANCE
```

Both intentionally return BLOCKED today. No signing/broadcast/AWS mutation is
implemented in these checks. For each later operation use --operation with its
own approval; accepted prior-operation receipts and actual subnet/chain bindings
are checked only when that operation needs them. The schema lists each supported
operation; to perform multiple transactions in one logical stage, pause and
rebind/review the next individual request. Native transfers/fee calls also require
running consensus/manager ownership evidence before execution.

After authorized provisioning, collect raw cloud/local facts using the existing
--collect-cloud and --collect-local --environment mainnet modes for each host;
run --preflight with those files. Read-only cloud collection now includes actual
root-volume metadata as well as retained data. Operational identity/alert evidence
is separately captured under approved host access: actual public certificate
hash/private-file mode checks, production identity metadata, verified alert event
ID and measurement time bound to instance/volume/UUID. No credentials or private
key contents are permitted. A precomputed PASS flag never replaces raw evidence.

## Administration and recovery safeguards

Controller: explicit AWS CLI profile, Session Manager plugin, Python3.13,
ansible-core2.19.4, amazon.aws12.0.0, boto3/botocore>=1.38.23. Review a dedicated
private encrypted S3 transfer bucket and controller KMS/S3 privileges; the node
role stays SSM-core-only. Never transfer keys/backups through Ansible's SSM bucket.
Review temporary-object cleanup, audit/CloudTrail and shell-session logging.
Port-forwarded traffic is not recorded by SSM: retain application receipts.
Retained data requires stable service UID/GID and UUID/serial guards. New/existing
runtime lifecycle remains explicit; missing managed DB metadata must refuse
startup, never initialize a replacement blockchain. Fuji/demo and Mainnet runtime
roots/identities/custody are isolated. A recovery procedure test before creation
is distinct from the controlled actual-network recovery required for acceptance.
