# Sydney security setup and EC2 authorization — COMPLETE

Account340379122975, profile `primewave-sydney`, region `ap-southeast-2`.
Identity was reverified after the owner renewed the expired login. No existing
matching dedicated resource was found before creation; the partial SG from the
usage-limit interruption was resumed without duplication. All new resources
have Project=PrimeWave and Environment=Pilot tags.

1. **Security group — CREATED:** `sg-049c9c0df433a5184`
   (`primewave-pilot-validators-sydney`), VPC `vpc-0eed3e8882d808fb2`.
   Independently verified one inbound rule: TCP9651 from0.0.0.0/0; one all-IPv4
   outbound rule. No IPv6, SSH, RPC, metrics or self-group ingress.
   Ingress rule: `sgr-04cadd83a4419a592`.
2. **IAM role/profile — CREATED:** `PrimeWavePilotValidatorSSMRole` /
   `PrimeWavePilotValidatorSSMProfile`. EC2-only trust (`ec2.amazonaws.com`,
   `sts:AssumeRole`), only `AmazonSSMManagedInstanceCore`, no inline policies.
   Fresh GetRole/ListAttachedRolePolicies/ListRolePolicies/GetInstanceProfile/
   ListInstanceProfileTags reads independently verified trust, policies, tags
   and the one-role association. The old19-policy role and operator permissions
   were not modified.
3. **Validator1 — ap-southeast-2a:** `DryRunOperation`, CLI exit254,
   authorization success only. Subnet `subnet-071c0e1ccdc807435`.
4. **Validator2 — ap-southeast-2b:** `DryRunOperation`, CLI exit254,
   authorization success only. Subnet `subnet-07b2637693bf19a0f`.

**Exact AWS CLI response, identical for both:**

```text
aws: [ERROR]: An error occurred (DryRunOperation) when calling the RunInstances operation (reached max retries: 0): Request would have succeeded, but DryRun flag is set.
```

The nonzero CLI exit is the expected DryRunOperation response, not a real launch
failure. Exactly two RunInstances invocations were made, each with explicit
`--dry-run`, JSON `DryRun=true` and `AWS_MAX_ATTEMPTS=1` (zero retries). No additional
RunInstances request was made.

Each exact request uses m6a.xlarge, verified Canonical Ubuntu24.04 x86-64 AMI
`ami-048c1a9eb63a67eed`, the new SG/profile, IMDSv2 required/hop-limit1, public
IPv4,32GiB encrypted gp3 root, separate150GiB encrypted retained gp3 data,
3000IOPS/125MiBps per volume and `alias/aws/ebs`. Data DeleteOnTermination=false.
Root/ENI deletion flags are request parameters only; no deletion occurred.
No SSH key pair or user data was supplied. Tags use Project=PrimeWave and
Environment=Pilot. See the two `validator-*.run-instances.dry-run.json` files and
separate exact response JSONs. PENDING files are earlier local drafts, not API calls.

5. **Remaining AWS blockers:** none observed in these authorization checks.
   This does not reserve capacity, create instances, prove billing/account
   activation or real KMS/volume creation, or validate SSM/validator runtime.
   The later launch and production-readiness gates remain separate. Existing
   Sydney deployment-profile adaptation is outside this task and unchanged.
6. **Estimated recurring charges for what was created: USD0/month.**
   [Security groups have no additional charge](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-security-groups.html)
   and [IAM is offered without additional charge](https://aws.amazon.com/iam/faqs/).
   Postchecks found zero EC2 instances, zero EBS volumes and zero Elastic IPs.
   No public IP was allocated. The AWS EBS alias remains without a TargetKeyId;
   no key was materialized for the dry runs. Future compute/storage/IP/monitoring
   costs do not arise until separately authorized operations are performed.
7. **Next action:** review this evidence and obtain separate explicit EC2 launch
   authorization. Before any actual validator deployment, complete reviewed
   Sydney configuration and host/SSM/storage/monitoring preflight. No node start,
   validator identity generation or blockchain transaction is authorized here.

Role ARN: `arn:aws:iam::340379122975:role/PrimeWavePilotValidatorSSMRole`.
Profile ARN: `arn:aws:iam::340379122975:instance-profile/PrimeWavePilotValidatorSSMProfile`.

No cleanup/deletion, existing role/SG change, operator permission change,
deployment-profile change, validator keys, blockchain transaction, signing or
main-branch change occurred. No credentials, session identifiers/tokens or
verification codes are saved. Initial usage-limit/session-expiry interruptions
are retained as resolved history in `execution.json`, not active blockers.
