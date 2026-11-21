# AWS Mumbai execution handoff

Source-only preparation. No instance/session/node/key creation, fee payment or
transaction broadcast was performed. One public manifest is authoritative:
`deploy/aws/deployment.review.json`. Null values and false approval flags are
intentional blockers. Never put credentials, private keys or mnemonics in it.
AWS selection does not authorize spending, IAM/resource changes or signing.

## Host and administration requirements

Two existing owner-approved `m6a.xlarge`, Ubuntu 24.04 x86-64 instances in distinct
Mumbai AZs. Use a **dedicated 150GiB encrypted gp3 data EBS per node**, separate
from an owner-sized OS root volume. Root volume cost/layout needs explicit
approval. Data attachment must have `DeleteOnTermination=false`. Mount by the
actual UUID in `/etc/fstab` without `nofail`/`noauto`. No formatter, disk reset,
mount fallback or instance-launch logic is supplied. Keep the agreed service
UID/GID across replacements; the playbook refuses retained ownership mismatch.
Set each host's `dataLifecycle` explicitly: `new` only for an authorized first
start, `existing` for a retained-data replacement. A managed missing DB is never
recreated; existing mode also requires nonempty DB metadata. Before first start,
record the separately approved identity's public fields in the manifest and
refresh its storage binding. Null/different expected identity fields refuse startup.
Lifecycle refers to the selected environment's runtime; reusing a host for first
mainnet startup never permits overwriting or adopting its separate Fuji database.

Only inbound TCP 9651 is accepted across the union of attached security groups.
No inbound 22, 9650 or 9100, including private ranges; disable SSH service/socket.
RPC and metrics bind loopback. SSM Agent must be Online, IMDSv2 required, and
the instance role must allow SSM. Outbound connectivity must support public
Avalanche peers, DNS, time sync, HTTPS package/binary downloads and AWS SSM/S3.
Use reviewed outbound internet routing or appropriate VPC endpoints; endpoint
presence alone does not provide Avalanche peer connectivity.

Controller: AWS CLIv2 with an explicit owner SSO/MFA profile, Session Manager
plugin, Python, `ansible-core==2.19.4`, `boto3>=1.38.23`, `botocore>=1.38.23`, and:

```bash
ansible-galaxy collection install -r deploy/aws/requirements.yml
```

The `amazon.aws:12.0.0` SSM connection requires a reviewed S3 transfer bucket
reachable by controller and instances, controller Get/Put/List/Delete permissions,
and the chosen KMS permissions. Use a dedicated private encrypted bucket,
versioning disabled/suspended and temporary-object cleanup/lifecycle reviewed.
Only public source/manifest/module inputs go through this bucket; never keys or
backup archives. IAM/account/session/audit configuration remains owner work.
Standard shell-session logging and CloudTrail must be configured. Port-forwarded
traffic is not recorded by Session Manager: retain application receipts instead.

## Provisioning is separate from starting or key creation

Fill actual account/profile, instance IDs, AZs, endpoints, root/data volume IDs,
mount UUIDs/paths, service UID/GID, SSM transfer bucket/KMS and operation fields.
Set `automation.provisionApproved` only after explicit owner authorization for
existing-host configuration. The renderer always sets `create_identities=false`
and `start_node=false`, irrespective of transaction approval flags.

```bash
set -euo pipefail
mkdir -p deploy-output
python3 scripts/deploy/aws_pilot.py --manifest deploy/aws/deployment.review.json --environment fuji --inventory > deploy-output/aws-fuji.inventory.json
# ONLY after separate existing-host provisioning approval:
ansible-playbook -i deploy-output/aws-fuji.inventory.json deploy/aws/pilot.yml
```

Both AWS and Netcup import `deploy/common/validator.yml`; no second validator
implementation exists. It installs pinned verified binaries, private RPC,
monitoring/time sync, recovery tooling and a service with persistent mount,
UUID/EBS-serial and binary guards. It cannot create a subnet/blockchain or start
a node by default. Approved provisioning creates a dedicated public 256MiB
benchmark file outside DB/identity directories. Point `host.benchmarkFile` at
that actual file before collecting evidence. Missing benchmark evidence FAILS.

## Read-only host preflight

For each `validator-1` and `validator-2`, collect cloud evidence on the controller:

```bash
python3 scripts/deploy/aws_pilot.py --manifest deploy/aws/deployment.review.json --host validator-1 --collect-cloud > deploy-output/validator-1.cloud.json
```

This calls only STS GetCallerIdentity, EC2 DescribeInstances/Volumes/SecurityGroups
and SSM DescribeInstanceInformation. Account mismatch stops further calls. No AWS
API is called when manifest inputs are incomplete. Do not send credentials here.

Inside an owner-opened Session Manager shell on the matching instance:

```bash
sudo python3 /opt/primewave/source/scripts/deploy/aws_pilot.py --manifest /opt/primewave/source/deploy/aws/deployment.review.json --host validator-1 --collect-local
```

Save only its public JSON output as `deploy-output/validator-1.host.json` on the
controller. Repeat for validator-2. The collector reads public IMDSv2 identity,
mount/NVMe metadata, effective listeners/firewall and services. fio uses only a
dedicated existing benchmark: readonly, no file creation, QD32 random4KiB reads.
It never reads a private key or blockchain database file.

**Single PASS/FAIL command per host** (substitute validator-2 consistently):

```bash
python3 scripts/deploy/aws_pilot.py --manifest deploy/aws/deployment.review.json --host validator-1 --preflight --cloud-facts deploy-output/validator-1.cloud.json --host-facts deploy-output/validator-1.host.json
```

Exit0/PASS requires matching account/instance/AZ/IMDS identity, separate AZs,
SSM Online, Ubuntu 24.04/x86-64, >=4vCPU and15GiB usable RAM, encrypted retained
>=150GiB gp3 with >=3000 provisioned IOPS/125MiBps, exact local EBS serial/UUID,
>=140GiB usable filesystem total (overhead allowed), >=100GiB free, measured
>=2700 read IOPS and <=10ms mean latency, default-deny firewall, no SSH/public
RPC, time sync, monitoring, alert destination and reviewed operational plans.
2700 IOPS is the project's90% acceptance floor against gp3's3000 baseline, not
an AWS performance guarantee. Unknown/missing/stale (>24h) evidence FAILS/exit 1.
PASS covers the host only: actual inbound9651 reachability must additionally be
probed externally after an explicitly approved node start. No identity, funding,
consensus or launch authorization follows from host PASS.

## Temporary Fuji rehearsal, then production ceremony

1. Complete both host preflights. Owner authorizes **Fuji-only** identity creation
   and startup separately. The pinned fresh-identity tool is already compiled
   by CI; run only under the approved operator's custody. Store Fuji identity/DB
   beneath `primewave/fuji-rehearsal`, never `pw-demo-04` or production directories.
   Owner records public NodeID, BLS public key/PoP and certificate SHA only.
2. Select/approve a collision-checked Fuji EVM ID distinct from development73571
   and the production candidate73571001. Use fresh disposable Fuji governance,
   custody and transaction wallets. Do not require or generate production keys
   to rehearse. Owner obtains faucet test AVAX on the Fuji P-Chain and approves
   exact creation fees, both validator initial balances, renewal/fee runway and
   change/refund ownership. A controller can share one validator host; validators
   and an owner-operated local signature aggregator must remain reachable through
   explicit loopback SSM tunnels. No paid/public aggregator fallback is authorized.
3. With approved host-start only, synchronize public Fuji P-Chain (network 5),
   check health/P-chain bootstrap and public 9651 peers. Mainnet later uses network 1,
   fresh production-only TLS/BLS identities and fresh approved custody addresses.
   Never run the two environments simultaneously on a shared 9651 listener.
4. **Staged signing approvals:** owner first approves CreateSubnetTx parameters,
   P-chain control owners/thresholds, fee/change budget and signer. Record accepted
   receipt/SubnetID. Bind the reviewed manager initialization to that actual ID;
   finalize constructor-executed proxy/library/manager and C00 genesis state.
   A publicly callable uninitialized manager proxy is forbidden. If choosing an
   owner-controlled atomic upgrade+initialize bootstrap instead, review and test
   that exact artifact first; merely setting a review flag is insufficient.
5. Owner approves the exact final genesis hash and CreateChainTx/VM parameters,
   then signs/broadcasts CreateChainTx. Preserve the receipt, BlockchainID and VMID.
   Install the existing plugin/chain configuration under those actual IDs. Do not
   rerun creation commands after a timeout: inspect saved transaction status first.
6. Owner approves ConvertSubnetToL1Tx containing the actual manager chain/address,
   two fresh public NodeIDs/BLS PoPs, weights, validation balances and return owners.
   Preserve accepted conversion receipt/data. Initialize/activate the manager
   through reviewed ownership and verify `initializeValidatorSet` with the actual
   conversion Warp message using the local aggregator. Do not treat a CLI exit 0
   as proof of ownership or validator-set correctness. The existing all-in-one
   create-l1 argv is review-only; do not use it to bypass the staged subnet-binding
   or protected-bootstrap requirement.
7. Verify both nodes' expected identities, registration/weights and peers, health,
   advancing accepted blocks and matching genesis/block/receipt hashes. Open each
   RPC using `AWS-StartPortForwardingSession` to remote 9650 and the manifest's local
   tunnel port; no inbound RPC/SSH. Reuse the four-method verifier:
   `python3 scripts/deploy/aws_pilot.py --manifest deploy/aws/deployment.review.json --host validator-1 --environment fuji --rpc-check`
   (repeat validator-2; later use `--environment mainnet`). It requires an explicit
   non-demo Chain ID and actual BlockchainID, always calls loopback, never signs.
8. Owner authorizes a bounded native PW smoke transfer between the manifest's
   disposable wallets, funded by an approved spend from an existing C00 allocation
   (no additional genesis grant). Record amount/gas ceiling before signing. Check
   status 1, canonical accepted receipt on both nodes and balances at fixed blocks:
   sender decrease = value + gasUsed*effectiveGasPrice; recipient increase = value.
9. Separately approve permissionless `FeeDistributor.distribute()` transaction and
   its gas budget. Verify event/cumulative-accounting deltas: validators=floor(A*70%),
   treasury=floor(A*20%), burn=A-minus-both; sum exactlyA. Verify actual destination
   contracts/custody and resulting balances; account for this call's own gas fees
   arriving after execution and any other concurrent transactions. Check vault
   funding/counters/no NativeMinter and that no extra PW allocation was introduced.
10. Approve a maintenance/recovery drill. With two validators, stopping either
    halts the chain: this is an accepted non-resilient pilot, not HA. Stop one cleanly,
    preserve the EBS/identity/DB and an encrypted off-host backup, fence the old host,
    then restore/reattach to a replacement in the **same AZ**. Across AZs or later
    Netcup migration use an authorized consistent snapshot/restore or encrypted
    stopped-node backup; EBS cannot simply move between AZs. Preserve UID/GID and
    NodeID/BLS/certificate/DB/registration; never run two active copies of one identity.
    Missing/wrong mount must fail startup, not initialize a replacement database.
11. Retain Fuji transaction/fee/identity/recovery evidence with its SHA256. Owner
    approves teardown of the temporary rehearsal and separately authorizes each
    production preparation/signing stage. Recheck registry evidence within 24h,
    repeat steps 3–10 on mainnet with entirely separate production identities and
    custody. Final production launch approval is separate. PWUSD remains frozen
    until PrimeWave Mainnet is live and all acceptance evidence is approved.

Read-only review summaries (never execute or authorize transactions):

```bash
python3 scripts/deploy/aws_pilot.py --manifest deploy/aws/deployment.review.json --environment fuji --readiness
python3 scripts/deploy/aws_pilot.py --manifest deploy/aws/deployment.review.json --environment mainnet --readiness
```

## Official operational references

- [Session Manager: no inbound management ports; port-forward logging limitation](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
- [Session and port-forward commands](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-sessions-start.html)
- [SSM outbound/endpoints requirements](https://docs.aws.amazon.com/systems-manager/latest/userguide/setup-create-vpc.html)
- [Ansible SSM connection and S3 transfer requirements](https://docs.ansible.com/projects/ansible/latest/collections/amazon/aws/aws_ssm_connection.html)
- [gp3 provisioned baseline](https://docs.aws.amazon.com/ebs/latest/userguide/general-purpose.html)
