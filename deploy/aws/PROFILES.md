# Explicit AWS profile selection

Historical Netcup servers are inaccessible: they are not capacity, runners,
rehearsal hosts or a fallback. The Netcup adapter is retained solely as offline
compatibility around the same `deploy/common/validator.yml` implementation.

| Per host | `aws-m6a-large-low-throughput` | `aws-m6a-xlarge-headroom` |
|---|---:|---:|
| Instance | m6a.large | m6a.xlarge |
| Logical vCPUs / physical cores / threads per core | 2 / 1 / 2 | 4 / 2 / 2 |
| Nominal RAM / minimum measured usable RAM | 8GiB / 7.5GiB | 16GiB / 15GiB |
| Common Ansible RAM acceptance | >=7680MiB | >=15360MiB |
| Two-instance vCPU demand | 4 | 8 |
| Fits owner's reported Mumbai quota5, usage0 for a new pair | Yes;1vCPU remains | No; requires >=8 available vCPUs |
| Dedicated encrypted retained gp3 data EBS | >=150GiB | >=150GiB |

These quota figures are owner-supplied evidence, not an AWS API check performed
by this change. Account verification, AZ availability, updated quota and explicit
EC2 launch/spending authorization are separate prerequisites. No instances exist
in this manifest. Profile selection does not authorize them.

## Comparison with official guidance

[Avalanche's current L1 table](https://build.avax.network/docs/nodes/system-requirements#avalanche-l1-validators)
lists low throughput (<10TPS) at2 cores,4GB RAM,100GB storage and25Mbps. Its
medium tier lists4 cores,8GB RAM and500GB SSD. Both profiles are restricted to
the low-throughput tier;150GiB is not a medium/high-throughput storage budget.
The table names Ubuntu22.04; our Ubuntu24.04 target has prior released-VM CI
evidence, not a claim that the table explicitly certifies24.04.

[AWS's specifications](https://aws.amazon.com/ec2/instance-types/m6a/) and
[CPU topology](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/cpu-options-supported-instances-values.html)
identify two m6a.large vCPUs as one physical core with two SMT threads. The
Avalanche table does not establish SMT-thread equivalence. Thus the smaller
profile must not be described as unconditionally meeting two physical cores:
it requires explicit owner acceptance of that
interpretation/risk, host measurements before creation and actual bounded Mainnet
performance evidence for post-launch acceptance. Optional Fuji evidence never
substitutes for production observations. Xlarge offers two physical cores and more RAM headroom,
but still does not make a two-validator pilot resilient.

Upstream requires P-Chain tracking and recommends partial Primary Network sync
for L1-only nodes. The actual shared node JSON sets
`partial-sync-primary-network=true`, `sybil-protection-enabled=true` and private
RPC. Collection now verifies the systemd-selected config and rejects CLI overrides.
Startup guard independently refuses partial-sync=false. Without partial sync,
full Primary Network CPU/RAM/storage requirements apply and neither profile is
accepted by these pilot checks. EBS performance must be measured; the upstream
local-NVMe warning in the Primary Network section is not an EBS performance guarantee
for an L1. The operator still has to validate P-Chain and own-chain behavior.

## Exact selection procedure (local only)

The authoritative Sydney DIRECT_MAINNET reconciliation proposal is
`sydney.existing-runtime.review.json`; it retains xlarge. The Mumbai review
template and both hardware profiles remain supported.
The two JSON files under `deploy/aws/profiles/` supply CPU/RAM acceptance to both
preflight and shared Ansible; never lower those thresholds manually.

```bash
set -euo pipefail
mkdir -p deploy-output
python3 scripts/deploy/aws_pilot.py --manifest deploy/aws/deployment.review.json --select-profile aws-m6a-large-low-throughput > deploy-output/aws-small.review.json
```

For xlarge use `--select-profile aws-m6a-xlarge-headroom` and a different output
file. Never redirect over the input manifest. Selection preserves public
identity/volume/chain metadata, resets provisioning/launch/transaction consents
and rehearsal acceptance, revokes host-specific/operation approvals, and grants no permission to resize or replace hosts.
It preserves an already verified account fact. Fill actual public inputs in the
selected output; use that **same file** for inventory, cloud collection, both
host gates and subsequent review. Do not mix evidence between profiles.

After separately authorized provisioning, use the commands in `EXECUTION.md`
with `--manifest deploy-output/aws-small.review.json`. Local collection now
requires `--environment mainnet` (or optional `fuji`) to inspect the actual selected unit:

```bash
sudo python3 /opt/primewave/source/scripts/deploy/aws_pilot.py --manifest /opt/primewave/source/deploy/aws/deployment.review.json --host validator-1 --environment mainnet --collect-local
```

Repeat for validator-2. The host gate validates the evidence's profile and
environment. It still requires separate AZs, exact EBS serial/UUID, boot-persistent
mounts, >=140GiB usable filesystem total and >=100GiB free, gp3>=3000 provisioned
IOPS/125MiBps, measured QD32 random4KiB reads >=2700IOPS and <=10ms mean latency,
SSM Online, IMDSv2, no SSH/public administrative RPC, loopback metrics, time sync,
alerts and all prior storage/security/recovery gates. No storage check was reduced.

## DIRECT_MAINNET measurements and commissioning

PRE_MAINNET_LAUNCH revalidates raw cloud/local evidence on both hosts using the
unchanged selected-profile CPU/RAM/topology and storage/UUID/serial thresholds,
SSM/private RPC, networking, time synchronization and monitoring safeguards.
Operational evidence must record a delivered alert event and actual public
identity/certificate/permission checks. No TPS or production receipt exists yet;
none is marked passed. Xlarge is the selected pilot profile. No mandatory Fuji
workload evidence is required for this stage.

POST_MAINNET_ACCEPTANCE requires bounded production commissioning under separate
native-transfer and fee-call approvals: advancing/matching blocks, both-node raw
receipts, fixed-block balances, gas and70/20/10 accounting. Per-host limits remain
CPU mean<70%,p95<90%;peak RAM<80%;disk/IOPS<80%;zero OOM/restarts/swap;network
>=25Mbps;p95 confirmation<=5000ms. Real alert delivery and controlled recovery
are mandatory. Receipt/status mismatches, consensus stalls, fencing/mount errors
or pressure require immediate operator intervention under the incident plan;
checks never automatically stop or resize AWS resources.

Choosing DIRECT_MAINNET accepts the loss of public-test-network practice before
irreversible production creation. The explicit commissioning/incident plan must
acknowledge that risk and set native amount, gas, duration and transfer-count
ceilings (<=10 smoke transfers,<=1h batch). It grants no transaction authority.

The smaller profile additionally requires ownerApproved and
physicalCoreExceptionAccepted before creation. Its previous60min5TPS performance
criteria are **not lowered**: actual selected-profile **Mainnet** metrics remain
mandatory at post acceptance, using the existing small-profile workload format
with environment=mainnet and the real ChainID/genesis. Evidence fields and numeric
checks in small_workload_errors remain unchanged. Such a sustained workload needs
its own separately approved funding/traffic plan, distinct from the small smoke
batch; until supplied the smaller profile remains blocked for final acceptance.
Fuji-formatted workload evidence is optional and cannot satisfy Mainnet acceptance.
No measured host/network workload results were produced by this software change.

Monitoring must page on lost chain progress/peers, failed health checks, process
restarts/OOM, unsafe disk growth and resource pressure. Upstream warning/critical
levels are CPU70/90%, RAM80/90%, disk80/90%, network80/95% and IOPS80/95%.
Validate outbound telemetry and alert delivery; local exporter presence alone
does not prove paging. Keep an approved storage expansion and instance-upsize
plan. If benchmark or monitoring conditions fail, block launch and obtain quota
and owner authorization for more headroom; never silently fall back to another
profile or historical server. Two validators halt on either validator outage.
