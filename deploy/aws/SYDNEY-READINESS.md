# Sydney launch preparation

READY FOR OWNER REVIEW; REAL LAUNCH BLOCKED. No AWS calls were made in this
preparation task. Historical DryRunOperation proves authorization only, not
capacity, live KMS/EBS creation, SSM connectivity or chain readiness.

Use `sydney.deployment.review.json`; Mumbai `deployment.review.json` is unchanged.
Both use the common Ansible deployment and existing hardware profiles. Sydney
selects aws-m6a-xlarge-headroom: 4vCPU, 2 physical cores, >=15GiB usable RAM,
>=140GiB usable retained filesystem, >=100GiB free, measured read-only QD32
>=2700IOPS and <=10ms. No storage, recovery, identity or security gates relaxed.
Partial Primary Network sync, sybil protection and private RPC remain mandatory.

## Exact requests and approval gate

The two `sydney-authorization/validator-*.run-instances.dry-run.json` files are
the exact previously successful requests, including 32GiB root, retained150GiB
data, encryption, IMDSv2, dedicated SG/profile and AZ-specific subnets. They
retain DryRun=true, so direct execution cannot spend. Existing validator/private
keys and historical runtime data are never consulted.

Offline preparation (does not call AWS):

```sh
python3 scripts/deploy/aws_launch_prepare.py --manifest deploy/aws/sydney.deployment.review.json --output-dir /private/tmp/primewave-sydney-dry-review
```

Real launch export is blocked until the owner explicitly approves spending and
creation of these two instances and their volumes/public IPv4. Only AFTER that
approval, in a reviewed copy of the manifest, set:

- awsLaunchApprovals.ec2LaunchAuthorized=true
- ec2Preparation.spendingApprovalReference to the actual approval record
- ec2Preparation.launchPayloadsSha256 to
  `618213ac9261ddb4eab289c84bd6d6b08b613a18bc1df727d933bc49b1aced73`

Then the offline exporter with `--approved-real-launch` emits the two real
payloads and exact commands; it never executes them. Stable ClientToken values
bind requests to the approval record to limit duplicate launch on retry.
Example output directory `/private/tmp/primewave-sydney-approved`:

```sh
python3 scripts/deploy/aws_launch_prepare.py --manifest /private/tmp/sydney.approved.json --output-dir /private/tmp/primewave-sydney-approved --approved-real-launch
# ONLY under the separate spending approval:
aws --profile primewave-sydney --region ap-southeast-2 ec2 run-instances --cli-input-json file:///private/tmp/primewave-sydney-approved/validator-1.json
aws --profile primewave-sydney --region ap-southeast-2 ec2 run-instances --cli-input-json file:///private/tmp/primewave-sydney-approved/validator-2.json
```

These commands were NOT executed. No approved real payload is committed. The
exporter rejects changed reviewed host resources or existing instance/volume IDs;
replacement must preserve the existing retained volume and identities through
the separate recovery procedure, never this initial-launch path. All CLI tools
remain subject to owner authorization; this is a preparation gate, not AWS IAM.

## Remaining prerequisites

Before launch: explicit EC2 spending/instance-creation approval; reverify account,
quota/usage (pair needs all8vCPUs), AMI availability, dedicated SG/profile and
subnet routing in Sydney. Successful dry runs reserve no capacity. Current cost
estimate is about USD353.18/30days or141.27/12days, excluding tax, transfer,
backup/logs/extra monitoring (historical Sydney selection estimate).

After launch, before provisioning/start: record actual instance IDs, root/data
volume IDs, endpoints, filesystem UUIDs and mount paths; verify SSM Online;
approve encrypted SSM transfer bucket/KMS controller prerequisites, stable
service UID/GID, session auditing, monitoring/alerts, root/storage growth and
fenced off-host recovery. Current manifest deliberately leaves these unset.
Do not format a reused data volume or create identities without separate approval.

Read-only cloud collection after filling actual host identifiers:
`python3 scripts/deploy/aws_pilot.py --manifest deploy/aws/sydney.deployment.review.json --host validator-1 --collect-cloud`
Repeat for validator-2; collect local evidence on each actual host and apply
`--preflight --cloud-facts FILE --host-facts FILE`. Every host gate must PASS.
A host PASS is never a blockchain signing or launch approval. Fresh Fuji-only
identities/Chain ID/custody, genesis and funding/signing approvals, successful
Fuji transaction/fee/recovery evidence, and separate mainnet approval remain
mandatory. PWUSD remains frozen.

## Actual offline validation

- Python suite:124 passed,2 skipped (previous binary checks),0 failures.
- Integration:8 combinations (Mumbai/Sydney ×2 profiles ×Fuji/Mainnet), including
  CPU/RAM boundaries, partial-sync config, loopback RPC and systemd mount guard.
- Ansible2.19.4/Python3.13: AWS syntax PASS with all4 region/profile inventories;
  common Netcup adapter syntax PASS (no access to historical servers).
- Default exporter preserved both exact dry-run requests; unapproved real export
  refused before writing output. No live performance/capacity/SSM test occurred.
- Initial syntax invocation with the default newer Python failed in Ansible's
  dataclasses compatibility layer; pinned supported Python3.13 passed unchanged.
