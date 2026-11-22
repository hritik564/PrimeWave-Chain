# Sydney staged launch preparation

SOFTWARE READY; REAL LAUNCH BLOCKED PENDING OWNER APPROVAL. The exporter is
strictly offline: no AWS calls, launches or infrastructure changes. Historical
DryRunOperation proves authorization only, not capacity, KMS/volume creation,
SSM connectivity or production readiness.

Use `sydney.deployment.review.json`; Mumbai `deployment.review.json` is unchanged.
Both use common Ansible and existing hardware profiles. Sydney selects
aws-m6a-xlarge-headroom:4vCPU,2 physical cores,>=15GiB usable RAM,>=140GiB usable
retained filesystem,>=100GiB free, measured read-only QD32>=2700IOPS/<=10ms.
Partial Primary Network sync, sybil protection, private RPC, storage binding,
identity fencing and recovery gates remain unchanged.

## Host-specific approval/export

```sh
python3 scripts/deploy/aws_launch_prepare.py --manifest deploy/aws/sydney.deployment.review.json --host validator-1 --output-dir /private/tmp/primewave-validator-1-review
```

This writes ONLY validator-1.json with DryRun=true and prints its exact command
and approval binding. It never executes the command. `--host validator-2` selects
only Validator2. Omitting --host selects both and requires BOTH independent
approvals for real export; there is no pair-wide approval override.

Each `hostLaunchApprovals[host]` record contains approved=false, reference=null,
issuedAt=null, expiresAt=null and the exact public binding. Keep these values
until that host is explicitly authorized. After authorization, in a separate
reviewed manifest copy, set only that host's approved=true, the actual approval
reference, timezone-aware issue/expiry timestamps (maximum24h validity), and
preserve the exact binding. Never backdate approval or infer authorization from
accountVerified. Legacy awsLaunchApprovals.ec2LaunchAuthorized and pair digest
fields DO NOT authorize export. Blockchain/provisioning approvals stay false.

```sh
# ONLY after a genuine, unexpired Validator1-specific owner approval:
python3 scripts/deploy/aws_launch_prepare.py --manifest /private/tmp/sydney.validator-1.approved.json --host validator-1 --output-dir /private/tmp/primewave-validator-1-approved --approved-real-launch
# Separate authorized operation, NOT performed by the exporter:
aws --profile primewave-sydney --region ap-southeast-2 ec2 run-instances --cli-input-json file:///private/tmp/primewave-validator-1-approved/validator-1.json
```

Real export changes only DryRun=false and adds ClientToken, derived from the
host/account/region/exact-request binding. The token remains stable across
approval renewals. Expiry is enforced during export, not by EC2: do not execute
stale exported commands. This is a software review gate, not an IAM boundary or
automatic shutdown/budget control.

After a launch request, record `launchRecord` on the selected host, including
outcome (even unknown), ClientToken and any returned instance/volume IDs. Store
only public metadata. Reconcile unknown outcomes using read-only AWS inventory
and the same token; never change tokens to force a retry. Populate instanceId,
rootVolumeId/dataVolumeId when known. Any such field or nonempty launchRecord
blocks initial-launch export for that host. Validator1 records do not block
explicit --host validator-2 preparation. Do not clear launch records to bypass
this guard. The exporter does not query live AWS for duplicates: fresh AWS
inventory remains mandatory immediately before execution. Replacement uses the
separate retained-volume/identity recovery procedure, never initial launch.

## Remaining gates

Before launch: explicit selected-host spending/instance-creation approval;
fresh account, quota/usage, AMI, SG/profile, subnet routing and duplicate-instance
read checks. Pair requires8vCPU; Validator1 requires4. Offerings and dry runs
reserve no capacity. Launch only one request and pause before Validator2.

After launch, before provisioning/start: record actual IDs/endpoints/filesystem
UUIDs; verify SSM Online; approve encrypted SSM transfer bucket/KMS controller
prerequisites, stable service UID/GID, auditing, monitoring/alerts, root/storage
growth and fenced off-host recovery. Do not format reused storage or create
identities without separate approval. Collect cloud/local evidence and require
both existing host preflight gates to PASS before blockchain execution. Fuji
identities, chain/genesis/custody, funding/signing, rehearsal and Mainnet launch
remain separate approvals. PWUSD remains frozen.

See VALIDATOR-1-READINESS.md for the exact request binding, costs and approval.
