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
it requires measured Fuji performance and explicit owner acceptance of that
interpretation/risk. Xlarge offers two physical cores and more RAM headroom,
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

The canonical manifest retains xlarge as the existing higher-headroom selection.
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
and rehearsal acceptance, and grants no permission to resize or replace hosts.
It preserves an already verified account fact. Fill actual public inputs in the
selected output; use that **same file** for inventory, cloud collection, both
host gates and subsequent review. Do not mix evidence between profiles.

After separately authorized provisioning, use the commands in `EXECUTION.md`
with `--manifest deploy-output/aws-small.review.json`. Local collection now
requires `--environment fuji` (or `mainnet`) to inspect the actual selected unit:

```bash
sudo python3 /opt/primewave/source/scripts/deploy/aws_pilot.py --manifest /opt/primewave/source/deploy/aws/deployment.review.json --host validator-1 --environment fuji --collect-local
```

Repeat for validator-2. The host gate validates the evidence's profile and
environment. It still requires separate AZs, exact EBS serial/UUID, boot-persistent
mounts, >=140GiB usable filesystem total and >=100GiB free, gp3>=3000 provisioned
IOPS/125MiBps, measured QD32 random4KiB reads >=2700IOPS and <=10ms mean latency,
SSM Online, IMDSv2, no SSH/public administrative RPC, loopback metrics, time sync,
alerts and all prior storage/security/recovery gates. No storage check was reduced.

## Production acceptance for the smaller profile

A host PASS establishes its hardware/config only. Smaller-profile mainnet review
additionally requires `smallProfileProduction.ownerApproved=true`, explicit
`physicalCoreExceptionAccepted=true`, and SHA256-bound public Fuji metrics via
`workloadEvidenceFile` / `workloadEvidenceSha256`. No production approval is set.

Required evidence JSON: schema `primewave-small-profile-workload-v1`, selected
`deploymentProfile`, `environment="fuji"`, `observedAt` within24h, actual Fuji
`chainId` and `genesisSha256`, and exactly two `hosts` records. Each record binds
`name`, `instanceId`, `dataVolumeId`, `filesystemUuid`, `availabilityZone` to the
manifest and supplies **actual measured** fields below. Test fixtures are not
evidence. The utility only validates metrics; it never sends traffic.
Percentages are host-normalized0–100, not per-process CPU percentages that can
exceed100 on multiple vCPUs. Accepted TPS must agree with count/duration within1%.

| Required field(s), per host | Acceptance (project policy, not an upstream SLA) |
|---|---|
| `durationSeconds`, `acceptedTps` | >=3600s at >=5 and <10 accepted TPS |
| `acceptedTransactions`, `submittedTransactions`, `failedReceipts` | >=18000 accepted; equal submitted; zero failures |
| `representativeContractCalls` | true; include approved native transfers and fee-accounting calls |
| `cpuMeanPercent`, `cpuP95Percent` | >=0 and <70%; >=0 and <90% |
| `memoryPeakPercent` | >=0 and <80% of actual usable memory |
| `oomKills`, `nodeRestarts`, `swapInBytes`, `swapOutBytes` | all zero |
| `diskPeakUsedPercent`, `iopsPeakPercentOfProvisioned` | each >=0 and <80% |
| `minimumNetworkMbps`, `confirmationP95Ms` | >=25Mbps; >0 and <=5000ms |
| `startAcceptedHeight`, `endAcceptedHeight` | accepted height advances on each node |
| `alertDeliveryVerified` | true; actually test delivery to the approved destination |

The workload must use separately approved disposable Fuji wallets and bounded
test-only funding; running it needs separate traffic/fee authorization. No load
test was executed here. Require both fresh host PASS reports, matching chain
progress/receipts, and the existing stopped-node backup/fenced recovery drill.
Actual owner-supplied evidence is absent; the smaller profile is **not approved**.

Monitoring must page on lost chain progress/peers, failed health checks, process
restarts/OOM, unsafe disk growth and resource pressure. Upstream warning/critical
levels are CPU70/90%, RAM80/90%, disk80/90%, network80/95% and IOPS80/95%.
Validate outbound telemetry and alert delivery; local exporter presence alone
does not prove paging. Keep an approved storage expansion and instance-upsize
plan. If benchmark or monitoring conditions fail, block launch and obtain quota
and owner authorization for more headroom; never silently fall back to another
profile or historical server. Two validators halt on either validator outage.
