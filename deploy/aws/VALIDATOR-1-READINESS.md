# Validator 1 launch-only readiness

PASS — host-scoped software preparation. LIVE EXECUTION BLOCKED until explicit
Validator1 approval. No launch approvals have been enabled. No AWS API call or
resource change was made during this implementation.

## Exact request

Canonical request: `sydney-authorization/validator-1.run-instances.dry-run.json`.
SHA256 of canonical JSON (sorted keys, compact separators):
`d585f3f6eb699f4c02def92de290533d5fb9588e56332420217d3e023c1fbce4`.
This pins EVERY launch field, including tags and volume/security options.
The source pins this digest independently of mutable manifest approvals.

- Account340379122975, profile primewave-sydney, region ap-southeast-2.
- Exactly1 m6a.xlarge, AZ ap-southeast-2a, subnet-071c0e1ccdc807435.
- AMI ami-048c1a9eb63a67eed (Canonical Ubuntu24.04 x86-64).
- SG sg-049c9c0df433a5184; profile ARN
  arn:aws:iam::340379122975:instance-profile/PrimeWavePilotValidatorSSMProfile.
- Public IPv4; no SSH key pair or user data. IMDSv2 required, hop limit1.
- /dev/sda1:32GiB encrypted gp3, DeleteOnTermination=true.
- /dev/sdf:150GiB encrypted gp3, DeleteOnTermination=false.
- Both3000IOPS/125MiBps; AWS-managed alias/aws/ebs key.
- EBS optimized; API termination protection; shutdown behavior stop;
  default tenancy; no capacity reservation; basic monitoring.
- Tags Project=PrimeWave, Environment=Pilot, Role=Validator, ValidatorIndex=1.

Exact real request is this canonical request with ONLY DryRun=false and the
stable ClientToken added by the approved --host validator-1 export. The real
request is not generated/committed without authorization. Validator2 is neither
exported nor authorized by that operation.

## Execution and pause

1. Obtain the approval below with a real reference and issue/expiry time; update
   ONLY Validator1's hostLaunchApprovals in a separate manifest copy. Revalidate
   account/resources/quota and absence of an existing matching instance.
2. Export with --host validator-1 --approved-real-launch per SYDNEY-READINESS.md.
   Inspect the one request; execute only its one RunInstances command under
   that approval. Preserve the stable token and record request outcome/IDs.
3. Pause. Read-only EC2/SSM inspection verifies health and storage configuration.
   No installation, formatting, identities, node start or transactions. A failed
   or ambiguous launch never triggers a new-token retry or Validator2 launch.

Rollback needs separate explicit stop/termination authorization (including
termination-protection changes if applicable). Stopping halts compute billing
but retains storage charges. Termination normally deletes the root and retains
the data volume; deleting retained storage needs separate approval. No automatic
rollback or shutdown is installed. A24h operating limit requires an owner/operator
timed check and separately authorized stopping; it is not a hard AWS spending cap.

## Cost assumptions

Historical official Sydney price reads on2026-11-22: Linux shared m6a.xlarge
USD0.216/hour, gp3 USD0.096/GiB-month; public IPv4 assumption USD0.005/hour.
For24h using a30day/720h storage estimate:
compute5.184 +182GiB storage0.5824 +IPv40.12 = **USD5.8864 (~5.89)**.
No paid extra IOPS/throughput, detailed monitoring or EIP assumed. Excludes tax,
transfer (including cross-AZ), backups, logs and added services. Actual storage
billing follows AWS prorating. Retained150GiB costs **USD14.40/month** after
termination until separately deleted. Both volumes while stopped:17.472/month.
SG/IAM themselves have no recurring charge. No new pricing queries were needed.

## Exact required owner approval

“Authorize Validator1 ONLY: exactly one m6a.xlarge in ap-southeast-2a using request
SHA256 d585f3f6eb699f4c02def92de290533d5fb9588e56332420217d3e023c1fbce4,
account340379122975, with the reviewed root/data volumes and public IPv4. Approve
up to24h operation at approximately USD5.89 plus variable charges and ongoing
retained-storage charges. Validator2, installation/startup, identities and
blockchain transactions remain unauthorized.”

Record the actual approval reference and timezone-aware issue/expiry timestamps
(maximum24h). This statement is requested approval, not evidence of consent.

## Offline validation

- Full Python suite:134 passed,2 skipped (previous binary checks),0 failures.
-17 Sydney/staging tests include real-payload EXPORT to temporary files only,
  Validator1 isolation, Validator2 refusal, atomic both-host refusal, tampered/
  expired/future/missing approvals, token stability, recorded-instance refusal,
  name-based selection and continuing Validator2 preparation after Validator1.
-8 shared Ansible/Jinja integration combinations pass (Mumbai/Sydney ×2 hardware
  profiles ×Fuji/Mainnet), preserving partial sync, private RPC, mount guards
  and CPU/RAM boundaries. Existing Mumbai manifest/deployment logic unchanged.
- All committed real launch approvals remain false. No AWS calls or live tests.
