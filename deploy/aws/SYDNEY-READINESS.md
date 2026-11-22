# Sydney staged infrastructure and DIRECT_MAINNET preparation

Initial-launch exporter software is ready; no new launch is authorized.
Validator1 already exists and was stopped on2026-11-22 at09:28:35 IST.
Use `sydney.existing-runtime.review.json` for its public-state reconciliation
proposal, not an initial-launch manifest. It blocks a duplicate Validator1
launch. Historical request/approval/idempotency/stop evidence is unchanged.
Validator2 remains unlaunched and its host approval remains false. The exporter is
strictly offline: no AWS calls, launches or infrastructure changes. Historical
DryRunOperation proves authorization only, not capacity, KMS/volume creation,
SSM connectivity or production readiness.

The original `sydney.deployment.review.json` remains an initial-launch template.
Mumbai `deployment.review.json` remains compatible. All select DIRECT_MAINNET;
see EXECUTION.md for the authoritative Sydney production sequence.
Both use common Ansible and existing hardware profiles. Sydney selects
aws-m6a-xlarge-headroom:4vCPU,2 physical cores,>=15GiB usable RAM,>=140GiB usable
retained filesystem,>=100GiB free, measured read-only QD32>=2700IOPS/<=10ms.
Partial Primary Network sync, sybil protection, private RPC, storage binding,
identity fencing and recovery gates remain unchanged.

## Host-specific approval/export

```sh
python3 scripts/deploy/aws_launch_prepare.py --manifest deploy/aws/sydney.existing-runtime.review.json --host validator-2 --output-dir /private/tmp/primewave-validator-2-review
```

This writes ONLY validator-2.json with DryRun=true and prints its exact command
and approval binding. It never executes the command. `--host validator-1` refuses the existing instance; a restart requires
separate start-existing authorization, not initial-launch export. Omitting --host selects both and requires BOTH independent
approvals for real export; there is no pair-wide approval override.

Each `hostLaunchApprovals[host]` record contains approved=false, reference=null,
issuedAt=null, expiresAt=null and the exact public binding. Keep these values
until that host is explicitly authorized. After authorization, in a separate
reviewed manifest copy, set only that host's approved=true, the actual approval
reference, timezone-aware issue/expiry timestamps (maximum24h validity), and
preserve the exact binding. Never backdate approval or infer authorization from
accountVerified. Legacy awsLaunchApprovals.ec2LaunchAuthorized and pair digest
fields DO NOT authorize export. Blockchain/provisioning approvals stay false.

Real launch approvals remain false. Validator1's historical24h launch approval
is expired/not reusable. Its future restart requires separate owner authorization.
Only after a fresh Validator2-specific spending approval may an operator export
with --host validator-2 --approved-real-launch using a separate approved copy.
No Validator1 real-launch command should be repeated.

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
both existing host preflight gates to PASS before blockchain execution. DIRECT_MAINNET uses separate PRE_MAINNET_LAUNCH and POST_MAINNET_ACCEPTANCE
gates. Production identity/custody, ChainID/genesis, artifacts, recovery and each
funding/signing operation remain separately gated. Fuji is optional only; no
Fuji result is required for Mainnet pre-launch. Future production receipts,
commissioning and controlled recovery belong to post-launch acceptance before
public access, not a prerequisite for initial creation. PWUSD remains frozen.

See VALIDATOR-1-READINESS.md for the exact request binding, costs and approval.

Historical VALIDATOR-1-READINESS.md describes the completed initial launch only.
It is not a current launch authorization. Follow EXECUTION.md for DIRECT_MAINNET.
