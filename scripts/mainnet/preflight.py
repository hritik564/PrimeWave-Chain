#!/usr/bin/env python3
"""Read-only readiness review. Consumes public plans/facts; never starts a node."""
import argparse
import ipaddress
import json
import os
from pathlib import Path
import platform
import re
import shutil


def version(value):
    match = re.fullmatch(r'v(\d+)\.(\d+)\.(\d+)', value or '')
    return tuple(map(int, match.groups())) if match else (0, 0, 0)


def check(plan, hosts, genesis):
    blockers = []
    def need(ok, message):
        if not ok:
            blockers.append(message)
    need(plan.get('avalancheNetworkId') == 1, 'Avalanche public network must be mainnet (1), not local 1337')
    evm = plan.get('evmChainId')
    need(type(evm) is int and evm > 0 and evm not in (1, 5, 77, 1337, 73571, 43113, 43114),
         'Distinct owner-approved production EVM chain ID required')
    need(version(plan.get('avalancheGoVersion')) >= (1, 15, 0),
         'v1.14.2 is pre-Helicon and cannot join current public mainnet')
    protocols = {'v1.15.0':46, 'v1.15.1':46, 'v1.15.2':47, 'v1.15.3':47}
    need(plan.get('subnetEvmVersion') == plan.get('avalancheGoVersion') and
         plan.get('avalancheGoVersion') in protocols and
         plan.get('pluginProtocol') == protocols.get(plan.get('avalancheGoVersion')),
         'Matching upstream AvalancheGo/Subnet-EVM versions and VM protocol required')
    need(plan.get('upstreamBinariesVerified') is True, 'Upstream binary provenance/checksums and genesis compatibility unverified')
    for name in ('allocationPolicy', 'governanceAndCustody', 'validatorTopology', 'stakingLaunchScope', 'operationsAndRecovery', 'launchAuthority'):
        need(plan.get('ownerApprovals', {}).get(name) is True, 'Owner decision missing: ' + name)
    for key in ('pChainFundingConfirmed','validatorRegistrationPrepared','productionIdentitiesVerified','genesisReviewed'):
        need(plan.get(key) is True, 'External ceremony gate missing: ' + key)
    need(genesis.get('deployable') is False, 'Review input must remain explicitly nondeployable')
    asset = genesis.get('nativeAsset', {})
    need(asset.get('totalSupplyWei') == str(100_000_000 * 10**18) and asset.get('decimals') == 18 and
         asset.get('symbol') == 'PW' and asset.get('nativeMinterEnabled') is False,
         'Locked PW supply/denomination/no-mint invariant differs')
    need(asset.get('feeSplitBps') == {'validators':7000,'treasury':2000,'burn':1000}, 'Locked 70/20/10 fee policy differs')
    selected = genesis.get('selectedAllocationPolicy')
    need(selected in genesis.get('allocationCandidates', {}), 'Conflicting allocation documents require explicit reconciliation')
    for allocations in genesis.get('allocationCandidates', {}).values():
        need(sum(allocations.values()) == 100_000_000, 'Allocation candidate does not total 100M PW')
    need(len(hosts) >= 2, 'Public facts required for both proposed servers')
    need(len(hosts) >= 5 or plan.get('twoValidatorRiskAccepted') is True,
         'Two validators cannot tolerate one offline; approve limited pilot risk or use 5+ independent validators')
    seen = set()
    node_ids = set()
    bls_keys = set()
    for i, host in enumerate(hosts):
        prefix = f'host {i+1}: '
        need(host.get('cpuCores',0) >= 4 and host.get('ramGiB',0) >= 7.5, prefix+'4 cores/8GiB minimum for proposed profile')
        need(host.get('diskGiB',0) >= 100 and host.get('diskFreeGiB',0) >= 100,
             prefix+'100GiB available low-throughput L1 storage plus separate OS/growth capacity required')
        need(host.get('trafficProfile') == 'under-10-tps-pruned' or host.get('diskGiB',0) >= 500,
             prefix+'128GB is not a general-production disk budget; restrict pilot or size storage to workload')
        need(host.get('storageGrowthPlanApproved') is True, prefix+'pruning, monitoring and storage expansion plan missing')
        need(host.get('osVersion') in ('22.04','24.04'), prefix+'supported Ubuntu LTS version required')
        need(host.get('persistentStorageVerified') is True, prefix+'persistent local block storage required')
        need(host.get('diskReadIops',0) >= 3000 and host.get('diskReadLatencyMs',999) <= 10,
             prefix+'engineering acceptance target: >=3000 random-read IOPS and <=10ms read latency; unmeasured fails')
        need(host.get('sshPasswordAuthentication') == 'no' and host.get('sshPermitRootLogin') == 'no',
             prefix+'SSH password/root login must be disabled')
        need(host.get('firewallDefaultDeny') is True and host.get('sshSourceRestricted') is True,
             prefix+'default-deny firewall and allowlisted SSH required')
        need(host.get('timeSyncActive') is True and host.get('monitoringActive') is True,
             prefix+'time synchronization and monitoring required')
        need(host.get('offHostRecoveryVerified') is True, prefix+'tested off-host recovery required')
        need(host.get('os') == 'Ubuntu' and host.get('architecture') in ('x86_64','amd64'), prefix+'Ubuntu x86_64 required')
        try:
            ip = ipaddress.ip_address(host.get('publicIp',''))
            public = ip.is_global
        except ValueError:
            public = False
        need(public and host.get('publicIp') not in seen, prefix+'distinct globally routable static address required')
        seen.add(host.get('publicIp'))
        need(host.get('networkMbps',0) >= 25 and host.get('p2p9651ExternallyVerified') is True,
             prefix+'25Mbps minimum and externally verified inbound TCP 9651 required')
        need(host.get('rpcLoopbackOnly') is True and host.get('tls443Verified') is True,
             prefix+'private 9650 RPC and protected HTTPS edge required')
        need(host.get('partialSyncPrimaryNetwork') is True and host.get('sybilProtectionEnabled') is True,
             prefix+'P-Chain-only public-network settings required; never copy demo flags')
        node_id=host.get('nodeId');bls_key=host.get('blsPublicKey')
        need(isinstance(node_id,str) and node_id.startswith('NodeID-') and node_id not in node_ids
             and isinstance(bls_key,str) and bool(bls_key) and bls_key not in bls_keys,
             prefix+'distinct verified public NodeID and BLS key records required')
        node_ids.add(node_id);bls_keys.add(bls_key)
        need(host.get('freshProductionIdentityVerified') is True, prefix+'fresh production-only TLS/BLS identity verification required')
    return blockers


def probe_p2p(address):
    """Explicit read-only TCP check from an independent host; no RPC/transactions."""
    import socket
    ip=ipaddress.ip_address(address)
    if not ip.is_global:
        raise ValueError('Only an explicitly supplied public address is accepted')
    with socket.create_connection((str(ip),9651),timeout=5):
        return {'publicIp':str(ip),'port':9651,'p2p9651ExternallyVerified':True,
                'scope':'TCP reachability only; not validator registration proof'}


def run_public(command):
    import subprocess
    result = subprocess.run(command,capture_output=True,text=True,timeout=20)
    if result.returncode:
        raise ValueError('Public host inspection command failed: '+command[0])
    return result.stdout


def collect(path, ssh_policy=None, read_test_file=None):
    """Local read-only public facts; no secrets, DB reads or disk write benchmark."""
    disk = shutil.disk_usage(path)
    ram = os.sysconf('SC_PAGE_SIZE') * os.sysconf('SC_PHYS_PAGES')
    os_info = platform.freedesktop_os_release()
    mount = json.loads(run_public(['findmnt','--json','--target',str(path),
                                  '--output','TARGET,SOURCE,FSTYPE,OPTIONS']))['filesystems'][0]
    facts = dict(cpuCores=os.cpu_count(),ramGiB=ram/2**30,diskGiB=disk.total/2**30,
                 diskFreeGiB=disk.free/2**30,os=os_info.get('NAME'),osVersion=os_info.get('VERSION_ID'),
                 architecture=platform.machine(),persistentStorageVerified=(
                     mount['source'].startswith('/dev/') and mount['fstype'] in ('ext4','xfs','btrfs')
                     and 'rw' in mount['options'].split(',')))
    if ssh_policy:
        # Administrator supplies a PUBLIC effective-policy export, not ssh keys.
        if ssh_policy.suffix != '.txt' or ssh_policy.is_symlink():
            raise ValueError('Use a regular public sshd policy .txt export')
        entries = dict(line.split(None,1) for line in ssh_policy.read_text().splitlines() if ' ' in line)
        facts['sshPasswordAuthentication'] = entries.get('passwordauthentication')
        facts['sshPermitRootLogin'] = entries.get('permitrootlogin')
    try:
        firewall = run_public(['ufw','status','verbose'])
        facts['firewallDefaultDeny'] = 'Status: active' in firewall and 'deny (incoming)' in firewall
        rules = [line for line in firewall.splitlines() if '22' in line and 'ALLOW IN' in line]
        facts['sshSourceRestricted'] = bool(rules) and all('Anywhere' not in line for line in rules)
    except (ValueError,FileNotFoundError):
        facts['firewallDefaultDeny'] = False
        facts['sshSourceRestricted'] = False
    for key,command in (
        ('timeSyncActive',['timedatectl','show','--property=NTPSynchronized','--value']),
        ('monitoringActive',['systemctl','is-active','prometheus-node-exporter'])):
        try:
            facts[key] = run_public(command).strip() in ('yes','active')
        except (ValueError,FileNotFoundError):
            facts[key] = False
    if read_test_file:
        # Require a dedicated pre-existing public benchmark file. fio never
        # creates/truncates a file and cannot issue write I/O in this mode.
        if read_test_file.suffix != '.benchmark' or read_test_file.is_symlink() or read_test_file.stat().st_size < 256*2**20:
            raise ValueError('Dedicated existing >=256MiB .benchmark file required')
        output = run_public(['fio','--name=primewave-read-only','--readonly','--allow_file_create=0',
            '--rw=randread','--bs=4k','--iodepth=1','--ioengine=psync','--direct=1',
            '--runtime=10','--time_based','--size=256m','--output-format=json','--filename='+str(read_test_file)])
        read = json.loads(output)['jobs'][0]['read']
        facts['diskReadIops'] = read['iops']
        facts['diskReadLatencyMs'] = read['clat_ns']['mean']/1_000_000
    # Reachability, recovery and new-identity attestations remain absent until
    # independently verified. Missing facts can never be promoted to success.
    return facts


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plan', type=Path)
    parser.add_argument('--hosts', type=Path, help='JSON array of public facts for both hosts')
    parser.add_argument('--genesis-review', type=Path)
    parser.add_argument('--collect-host', type=Path, metavar='EXISTING_DISK_PATH')
    parser.add_argument('--probe-p2p',nargs='+',help='Explicit public IPs; run from an independent host')
    parser.add_argument('--sshd-policy-file',type=Path)
    parser.add_argument('--read-benchmark-file',type=Path)
    args = parser.parse_args()
    if args.probe_p2p:
        print(json.dumps([probe_p2p(ip) for ip in args.probe_p2p],indent=2))
    elif args.collect_host:
        print(json.dumps(collect(args.collect_host,args.sshd_policy_file,args.read_benchmark_file), indent=2))
    else:
        if not (args.plan and args.hosts and args.genesis_review):
            parser.error('--plan, --hosts and --genesis-review required')
        blockers = check(json.loads(args.plan.read_text()), json.loads(args.hosts.read_text()),
                         json.loads(args.genesis_review.read_text()))
        print(json.dumps({'ready':not blockers,'blockers':blockers,
                          'scope':'public facts review only; not deployment authorization or proof of remote reachability'},indent=2))
        raise SystemExit(bool(blockers))
