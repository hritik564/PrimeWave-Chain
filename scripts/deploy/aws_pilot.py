#!/usr/bin/env python3
"""AWS pilot manifest, read-only evidence collectors and fail-closed gates.

AWS calls are limited to STS GetCallerIdentity, EC2 Describe* and SSM Describe*.
Never starts sessions/instances/nodes, generates identities, signs or broadcasts.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import ipaddress
import json
import math
from pathlib import Path
import re
import shlex
import subprocess
import sys
import urllib.request

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts/mainnet'))
import preflight
import chain_id
rpc_spec=importlib.util.spec_from_file_location('primewave_rpc',ROOT/'scripts/check-evm-rpc.py')
rpc_module=importlib.util.module_from_spec(rpc_spec);rpc_spec.loader.exec_module(rpc_module)
SUPPORTED_REGIONS=('ap-south-1','ap-southeast-2')
PROFILE_IDS=('aws-m6a-large-low-throughput','aws-m6a-xlarge-headroom')


def selected_profile(m):
    name=m.get('deploymentProfile')
    if name not in PROFILE_IDS:raise ValueError('Explicit supported deploymentProfile required; no automatic fallback')
    return json.loads((ROOT/'deploy/aws/profiles'/f'{name}.json').read_text())


def select_profile(m,name):
    """Render a public manifest locally, never authorize/launch or overwrite input."""
    import copy
    result=copy.deepcopy(m);result['deploymentProfile']=name
    p=selected_profile(result);result['target']['instanceType']=p['instanceType']
    # Selection is a review action, never preservation of prior launch consent.
    result['automation']['provisionApproved']=False
    result['awsLaunchApprovals']={'accountVerified':m.get('awsLaunchApprovals',{}).get('accountVerified') is True,'ec2LaunchAuthorized':False}
    result['smallProfileProduction']={'ownerApproved':False,'physicalCoreExceptionAccepted':False,'workloadEvidenceFile':None,'workloadEvidenceSha256':None}
    for e in result['environments'].values():
        e['approvals']={k:False for k in e['approvals']}
        e['rehearsalPassed']=False;e['rehearsalEvidenceSha256']=None
    return result


def quota_report(m):
    p=selected_profile(m);q=m.get('quotaEvidence',{})
    required=2*p['vcpusPerHost'];limit=q.get('standardOnDemandVcpus');used=q.get('usedVcpus')
    known=type(limit) is int and type(used) is int and 0<=used<=limit
    return {'pairVcpus':required,'reportedLimitVcpus':limit,'reportedUsedVcpus':used,
        'fitsReportedQuotaForNewPair':known and required<=limit-used,
        'scope':'owner-reported snapshot only; recheck account, quota, AZ capacity and authorization before launch; existing-host provisioning does not consume another pair'}


def service_config_matches(unit,path):
    argv=re.findall(r'argv\[\]=([^;]+)',unit)
    # Reject drop-in command-line overrides that could negate the JSON flags.
    return len(argv)==1 and shlex.split(argv[0].strip())==['/opt/primewave/releases/v1.15.1/avalanchego','--config-file='+str(path)]


def small_workload_errors(m):
    """Validate owner-supplied public Fuji metrics; never generates traffic."""
    if not selected_profile(m)['requiresSmallProfileProductionAcceptance']:return []
    errors=[];review=m.get('smallProfileProduction',{})
    if review.get('ownerApproved') is not True:errors.append('smaller profile production risk acceptance missing')
    if review.get('physicalCoreExceptionAccepted') is not True:errors.append('2vCPU/1 physical-core deviation from literal upstream2-core guidance requires explicit acceptance')
    try:
        path=Path(review.get('workloadEvidenceFile') or '')
        if path.suffix!='.json' or any(p.is_symlink() for p in (path,*path.parents)) or not path.is_file() or path.stat().st_size>1024*1024:
            raise ValueError('public <=1MiB regular workload JSON required')
        raw=path.read_bytes()
        if hashlib.sha256(raw).hexdigest()!=review.get('workloadEvidenceSha256'):raise ValueError('workload evidence digest mismatch')
        evidence=json.loads(raw);public_only(evidence)
        if evidence.get('schema')!='primewave-small-profile-workload-v1' or evidence.get('deploymentProfile')!=m['deploymentProfile'] or evidence.get('environment')!='fuji' or not fresh(evidence.get('observedAt')):
            raise ValueError('fresh <=24h selected-profile Fuji workload evidence required')
        fuji=m['environments']['fuji']
        if type(fuji.get('evmChainId')) is not int or fuji['evmChainId'] in chain_id.DENIED or evidence.get('chainId')!=fuji['evmChainId'] or not fuji.get('genesisSha256') or evidence.get('genesisSha256')!=fuji['genesisSha256']:
            raise ValueError('actual Fuji Chain ID/genesis binding required')
        rows=evidence.get('hosts',[])
        if len(rows)!=2 or {r.get('name') for r in rows}!={'validator-1','validator-2'}:raise ValueError('both benchmark host records required')
        for row in rows:
            h=host_named(m,row['name'])
            if any(row.get(k)!=h.get(k) for k in ('instanceId','dataVolumeId','filesystemUuid','availabilityZone')):raise ValueError('workload host/volume binding mismatch')
            def n(k,default=math.inf):
                v=row.get(k)
                return v if type(v) in (int,float) and math.isfinite(v) else default
            conditions=[n('durationSeconds',0)>=3600,5<=n('acceptedTps',-1)<10,
                n('durationSeconds',0)>0 and 5<=n('acceptedTransactions',0)/n('durationSeconds')<10,
                n('durationSeconds',0)>0 and math.isclose(n('acceptedTps',-1),n('acceptedTransactions',0)/n('durationSeconds'),rel_tol=0.01),
                n('acceptedTransactions',0)>=18000,n('acceptedTransactions')==n('submittedTransactions'),
                n('failedReceipts')==0,row.get('representativeContractCalls') is True,
                0<=n('cpuMeanPercent')<70,0<=n('cpuP95Percent')<90,
                0<=n('memoryPeakPercent')<80,n('oomKills')==0,n('nodeRestarts')==0,
                n('swapInBytes')==0,n('swapOutBytes')==0,0<=n('diskPeakUsedPercent')<80,
                0<=n('iopsPeakPercentOfProvisioned')<80,n('minimumNetworkMbps',0)>=25,
                0<n('confirmationP95Ms')<=5000,n('endAcceptedHeight',0)>n('startAcceptedHeight'),
                row.get('alertDeliveryVerified') is True]
            if not all(conditions):errors.append(row['name']+': 60min5TPS CPU/RAM/disk/network/receipt/alert benchmark acceptance failed')
    except (ValueError,TypeError,KeyError,OSError) as error:errors.append('small-profile workload evidence: '+str(error))
    return errors


def now():return datetime.now(timezone.utc).isoformat()


def fresh(value):
    try:return 0 <= (datetime.now(timezone.utc)-datetime.fromisoformat(value)).total_seconds() <= 86400
    except (ValueError,TypeError):return False


def public_only(value):
    if isinstance(value,dict):
        for key,item in value.items():
            normalized=re.sub('[^a-z]','',key.lower())
            if 'privatekey' in normalized or 'secret' in normalized or normalized in ('accesskeyid','awsaccesskeyid','mnemonic','password','seed','seedphrase','credentials'):
                raise ValueError('Public deployment metadata only; credentials forbidden')
            public_only(item)
    elif isinstance(value,list):
        for item in value:public_only(item)
    elif isinstance(value,str) and ('PRIVATE KEY-----' in value or value.startswith('PrivateKey-')):
        raise ValueError('Private signing material forbidden')


def manifest_errors(m):
    public_only(m)
    profile=selected_profile(m)
    errors=[]
    def need(ok,message):
        if not ok:errors.append(message)
    need(m.get('provider')=='aws' and m.get('region') in SUPPORTED_REGIONS,'Explicit supported AWS region required (Mumbai or Sydney)')
    need(re.fullmatch(r'\d{12}',m.get('accountId') or '') is not None,'Explicit AWS account ID required')
    need(isinstance(m.get('operatorProfile'),str) and bool(m['operatorProfile']),'Explicit operator AWS profile required; no default credentials selection')
    target=m.get('target',{})
    for key,expected in dict(instanceType=profile['instanceType'],os='Ubuntu',osVersion='24.04',architecture='x86_64',dataVolumeGiB=150,volumeType='gp3',encrypted=True,deleteOnTermination=False,administration='ssm',publicSsh=False,publicValidatorRpc=False,publicP2pTcpPort=9651,trafficProfile='under-10-tps-pruned').items():
        need(target.get(key)==expected,'Approved AWS target mismatch: '+key)
    need(m.get('pilotRiskAccepted') is True and m.get('expectedValidators')==2,'Two-validator non-resilient pilot acknowledgement required')
    hosts=m.get('hosts',[])
    need(len(hosts)==2 and {h.get('name') for h in hosts}=={'validator-1','validator-2'},'Exactly two named validator hosts required')
    for h in hosts:
        prefix=h.get('name','host')+': '
        need(re.fullmatch(r'i-[0-9a-f]{17}',h.get('instanceId') or '') is not None,prefix+'instance ID required')
        need(h.get('region')==m.get('region') and re.fullmatch(re.escape(m.get('region') or '')+r'[a-z]',h.get('availabilityZone') or '') is not None,prefix+'AZ must belong to selected region')
        for key,global_ip in [('privateIp',False),('publicIp',True)]:
            try:
                ip=ipaddress.ip_address(h[key])
                ok=ip.version==4 and (ip.is_global if global_ip else any(ip in ipaddress.ip_network(cidr) for cidr in ('10.0.0.0/8','172.16.0.0/12','192.168.0.0/16')))
            except (ValueError,TypeError,KeyError):ok=False
            need(ok,prefix+'explicit '+key+' required')
        for key in ('dataVolumeId','rootVolumeId'):
            need(re.fullmatch(r'vol-[0-9a-f]{17}',h.get(key) or '') is not None,prefix+key+' required')
        need(h.get('dataVolumeId')!=h.get('rootVolumeId'),prefix+'150GiB retained data volume must be separate from OS root; root sizing/cost needs owner approval')
        mount=h.get('persistentMount')
        need(isinstance(mount,str) and re.fullmatch(r'/[A-Za-z0-9_/-]+',mount) is not None and '..' not in Path(mount).parts and not mount.startswith(('/tmp','/run','/root','/home','/dev','/proc','/sys')),prefix+'explicit persistent mount required')
        need(re.fullmatch(r'[0-9a-fA-F-]{8,64}',h.get('filesystemUuid') or '') is not None,prefix+'actual filesystem UUID required')
        need(bool(h.get('securityGroupIds')) and bool(h.get('instanceProfileArn')),prefix+'security groups and SSM instance profile required')
        need(h.get('dataLifecycle') in ('new','existing'),prefix+'explicit new/existing data lifecycle required; replacements must use existing')
        endpoint=h.get('privateEndpoint') or {}
        need(endpoint.get('rpcBind')=='127.0.0.1' and endpoint.get('rpcPort')==9650 and endpoint.get('ssmTargetInstanceId')==h.get('instanceId') and type(endpoint.get('operatorTunnelPort')) is int and 1024<=endpoint['operatorTunnelPort']<=65535,prefix+'explicit loopback Session Manager RPC endpoint/tunnel port required')
        need(h.get('publicP2pEndpoint')==str(h.get('publicIp'))+':9651',prefix+'public P2P endpoint must match reviewed public IP/TCP9651')
    for key in ('instanceId','publicIp','dataVolumeId','availabilityZone'):
        need(len({h.get(key) for h in hosts})==2,'Two distinct '+key+' values required')
    return errors


def host_named(m,name):
    matches=[h for h in m['hosts'] if h['name']==name]
    if len(matches)!=1:raise ValueError('Explicit manifest host name required')
    return matches[0]


def aws(m,*args):
    # An explicit account/profile is validated before every collection.
    return json.loads(subprocess.check_output(['aws','--profile',m['operatorProfile'],'--region',m['region'],*args,'--output','json','--no-cli-pager'],text=True,timeout=30))


def collect_cloud(m,name):
    errors=manifest_errors(m)
    if errors:raise ValueError('; '.join(errors))
    h=host_named(m,name)
    account=aws(m,'sts','get-caller-identity')['Account']
    if account!=m['accountId']:raise ValueError('AWS profile account mismatch; no further API calls made')
    instances=aws(m,'ec2','describe-instances','--instance-ids',h['instanceId'])['Reservations']
    found=[i for r in instances for i in r['Instances']]
    if len(found)!=1:raise ValueError('Exactly one existing instance required')
    instance=found[0]
    volume=aws(m,'ec2','describe-volumes','--volume-ids',h['dataVolumeId'])['Volumes']
    groups=aws(m,'ec2','describe-security-groups','--group-ids',*[g['GroupId'] for g in instance['SecurityGroups']])['SecurityGroups']
    managed=aws(m,'ssm','describe-instance-information','--filters','Key=InstanceIds,Values='+h['instanceId'])['InstanceInformationList']
    # Discard tags/user data and any unrelated API fields.
    keys=('InstanceId','InstanceType','Architecture','CpuOptions','Placement','State','PublicIpAddress','PrivateIpAddress','SecurityGroups','IamInstanceProfile','BlockDeviceMappings','MetadataOptions','RootDeviceName')
    volume_keys=('VolumeId','Encrypted','VolumeType','Size','Iops','Throughput','AvailabilityZone','Attachments','State')
    return dict(observedAt=now(),accountId=account,region=m['region'],host=name,instance={k:instance.get(k) for k in keys},volumes=[{k:v.get(k) for k in volume_keys} for v in volume],securityGroups=[{'GroupId':g['GroupId'],'IpPermissions':g['IpPermissions']} for g in groups],ssm=[{k:i.get(k) for k in ('InstanceId','PingStatus','PlatformName','PlatformVersion','AgentVersion')} for i in managed])


def collect_local(m,name,environment):
    h=host_named(m,name)
    mount=Path(h['persistentMount'])
    if mount.is_symlink() or not mount.is_dir():raise ValueError('Existing non-symlink mount required')
    benchmark=Path(h['benchmarkFile']) if h.get('benchmarkFile') else None
    if benchmark and (not benchmark.resolve().is_relative_to(mount.resolve()) or any(p in benchmark.resolve().parts for p in ('db','staking')) or any(p.is_symlink() for p in (benchmark,*benchmark.parents))):
        raise ValueError('Dedicated public benchmark outside DB/identity paths required')
    facts=preflight.collect(mount,read_test_file=benchmark,queued_reads=True)
    topology=preflight.run_public(['lscpu','--parse=CORE,SOCKET'])
    facts['physicalCores']=len({line for line in topology.splitlines() if line and not line.startswith('#')})
    purpose=m['environments'][environment]['purpose']
    config_path=Path('/etc/primewave')/(purpose+'.json')
    if config_path.is_symlink():raise ValueError('Reviewed regular node config required')
    config=json.loads(config_path.read_text())
    unit=preflight.run_public(['systemctl','show','primewave-'+purpose,'--property=ExecStart','--value'])
    facts['nodeConfig']={'partialSyncPrimaryNetwork':config.get('partial-sync-primary-network'),
        'sybilProtectionEnabled':config.get('sybil-protection-enabled'),'rpcBind':config.get('http-host'),
        'apiAdminEnabled':config.get('api-admin-enabled'),'networkId':config.get('network-id'),
        'serviceUsesReviewedConfig':service_config_matches(unit,config_path)}
    facts['mount']=json.loads(preflight.run_public(['findmnt','-J','-T',str(mount),'-o','TARGET,UUID,SOURCE,FSTYPE,OPTIONS']))['filesystems'][0]
    facts['volumeSerials']=preflight.run_public(['lsblk','-s','-n','-o','SERIAL',facts['mount']['source']]).split()
    facts['fstabUuidVerified']=any(line.split()[:2]==['UUID='+h['filesystemUuid'],str(mount)] and not any(opt in line.split()[3].split(',') for opt in ('noauto','nofail')) for line in Path('/etc/fstab').read_text().splitlines() if line.strip() and not line.lstrip().startswith('#') and len(line.split())>=4)
    listeners=preflight.run_public(['ss','-H','-lnt'])
    endpoints=[line.split()[3] for line in listeners.splitlines() if len(line.split())>=4]
    facts['sshListening']=any(x.endswith(':22') for x in endpoints)
    facts['rpcPublicListener']=any(x.endswith(':9650') and x not in ('127.0.0.1:9650','[::1]:9650') for x in endpoints)
    firewall=preflight.run_public(['ufw','status','verbose'])
    facts['noSshFirewallAllow']=not any(re.search(r'(?i)(\b22\b|ssh)',line) and 'ALLOW' in line for line in firewall.splitlines())
    facts['noPublicRpcFirewallAllow']=not any(re.search(r'\b(9650|9100)\b',line) and 'ALLOW' in line for line in firewall.splitlines())
    facts['ssmAgentActive']=any(subprocess.run(['systemctl','is-active','--quiet',unit],check=False).returncode==0 for unit in ('amazon-ssm-agent.service','snap.amazon-ssm-agent.amazon-ssm-agent.service'))
    # IMDSv2 identity document only. Never request IAM credentials or user data.
    token=urllib.request.urlopen(urllib.request.Request('http://169.254.169.254/latest/api/token',method='PUT',headers={'X-aws-ec2-metadata-token-ttl-seconds':'60'}),timeout=3).read().decode()
    doc=json.load(urllib.request.urlopen(urllib.request.Request('http://169.254.169.254/latest/dynamic/instance-identity/document',headers={'X-aws-ec2-metadata-token':token}),timeout=3))
    facts['identityDocument']={k:doc[k] for k in ('accountId','instanceId','region','availabilityZone','instanceType','privateIp')}
    return dict(observedAt=now(),host=name,environment=environment,deploymentProfile=m['deploymentProfile'],facts=facts)


def host_gate(m,name,cloud,local):
    errors=manifest_errors(m)
    profile=selected_profile(m)
    h=host_named(m,name)
    def need(ok,message):
        if not ok:errors.append(name+': '+message)
    need(cloud.get('host')==name and local.get('host')==name and fresh(cloud.get('observedAt')) and fresh(local.get('observedAt')),'fresh <=24h cloud and host evidence required')
    need(cloud.get('accountId')==m.get('accountId') and cloud.get('region')==m['region'],'cloud account/region mismatch')
    i=cloud.get('instance',{});f=local.get('facts',{});d=f.get('identityDocument',{})
    for key,expected in dict(InstanceId=h.get('instanceId'),InstanceType=profile['instanceType'],Architecture='x86_64',PublicIpAddress=h.get('publicIp'),PrivateIpAddress=h.get('privateIp')).items():need(i.get(key)==expected,'EC2 '+key+' mismatch')
    need(i.get('CpuOptions',{}).get('CoreCount')==profile['physicalCoresPerHost'] and i.get('CpuOptions',{}).get('ThreadsPerCore')==profile['threadsPerCore'],'actual EC2 physical-core/thread topology must match selected profile')
    need(i.get('State',{}).get('Name')=='running' and i.get('Placement',{}).get('AvailabilityZone')==h.get('availabilityZone'),'existing running instance/AZ required')
    need(i.get('MetadataOptions',{}).get('HttpTokens')=='required','IMDSv2-only metadata required')
    need(i.get('IamInstanceProfile',{}).get('Arn')==h.get('instanceProfileArn') and bool(h.get('instanceProfileArn')),'SSM instance profile mismatch')
    actual_groups={g['GroupId'] for g in i.get('SecurityGroups',[])}
    need(actual_groups==set(h.get('securityGroupIds',[])) and actual_groups=={g['GroupId'] for g in cloud.get('securityGroups',[])},'complete attached security-group evidence required')
    public_p2p=False
    for group in cloud.get('securityGroups',[]):
        for rule in group.get('IpPermissions',[]):
            need(rule.get('IpProtocol')=='tcp' and rule.get('FromPort')==9651 and rule.get('ToPort')==9651,'inbound security groups may expose TCP9651 only; no SSH/RPC/admin ranges')
            public_p2p|=any(r.get('CidrIp')=='0.0.0.0/0' for r in rule.get('IpRanges',[]))
    need(public_p2p,'public IPv4 TCP9651 rule required; reachability must be tested again after node start')
    volumes=cloud.get('volumes',[])
    v=volumes[0] if len(volumes)==1 else {}
    need(v.get('VolumeId')==h.get('dataVolumeId') and v.get('Encrypted') is True and v.get('VolumeType')=='gp3' and v.get('Size',0)>=150 and v.get('Iops',0)>=3000 and v.get('Throughput',0)>=125 and v.get('AvailabilityZone')==h.get('availabilityZone'),'encrypted >=150GiB gp3 data volume in the same AZ required (>=3000 provisioned IOPS/125MiBps)')
    need(any(a.get('InstanceId')==h.get('instanceId') and a.get('State')=='attached' for a in v.get('Attachments',[])),'data volume attachment mismatch')
    need(any(b.get('Ebs',{}).get('VolumeId')==h.get('dataVolumeId') and b['Ebs'].get('DeleteOnTermination') is False and b.get('DeviceName')!=i.get('RootDeviceName') for b in i.get('BlockDeviceMappings',[])),'data EBS must survive instance termination and be separate from OS root')
    need(any(b.get('DeviceName')==i.get('RootDeviceName') and b.get('Ebs',{}).get('VolumeId')==h.get('rootVolumeId') for b in i.get('BlockDeviceMappings',[])),'OS root volume identity required')
    need(any(s.get('InstanceId')==h.get('instanceId') and s.get('PingStatus')=='Online' and s.get('PlatformName')=='Ubuntu' and s.get('PlatformVersion')=='24.04' for s in cloud.get('ssm',[])),'SSM Online Ubuntu24.04 evidence required')
    for key,expected in dict(accountId=m.get('accountId'),instanceId=h.get('instanceId'),region=m['region'],availabilityZone=h.get('availabilityZone'),instanceType=profile['instanceType'],privateIp=h.get('privateIp')).items():need(d.get(key)==expected,'host/cloud binding mismatch: '+key)
    need(f.get('os')=='Ubuntu' and f.get('osVersion')=='24.04' and f.get('architecture')=='x86_64' and f.get('cpuCores',0)>=profile['vcpusPerHost'] and f.get('ramGiB',0)>=profile['minimumUsableRamGiB'] and f.get('physicalCores',0)>=profile['physicalCoresPerHost'],f"Ubuntu24.04 x86-64 >={profile['vcpusPerHost']}vCPU/{profile['minimumUsableRamGiB']}GiB usable RAM and measured physical topology required")
    env=local.get('environment');node=f.get('nodeConfig',{})
    need(local.get('deploymentProfile')==m['deploymentProfile'] and env in ('mainnet','fuji'),'evidence must bind the selected profile and explicit environment')
    need(node.get('partialSyncPrimaryNetwork') is True and node.get('sybilProtectionEnabled') is True and node.get('rpcBind')=='127.0.0.1' and node.get('apiAdminEnabled') is False and node.get('networkId')==env and node.get('serviceUsesReviewedConfig') is True,'actual systemd-selected AvalancheGo config must enable partial P-Chain sync, sybil protection and private RPC')
    need(f.get('diskGiB',0)>=140 and f.get('diskFreeGiB',0)>=100 and f.get('persistentStorageVerified') is True,'retained filesystem >=140GiB usable total and >=100GiB free required (150GiB raw EBS plus filesystem overhead)')
    mount=f.get('mount',{})
    need(mount.get('target')==h.get('persistentMount') and mount.get('uuid')==h.get('filesystemUuid') and f.get('fstabUuidVerified') is True,'exact UUID mount with required boot persistence; no root-disk/nofail fallback')
    need((h.get('dataVolumeId') or 'INVALID').replace('-','') in [s.replace('-','') for s in f.get('volumeSerials',[])],'local NVMe serial must match the reviewed EBS volume ID')
    need(f.get('diskReadIops',0)>=2700 and f.get('diskReadLatencyMs',999)<=10,'measured QD32 random reads >=2700IOPS/<=10ms required (project90% gp3-baseline acceptance); missing measurement fails')
    for field in ('ssmAgentActive','firewallDefaultDeny','noSshFirewallAllow','noPublicRpcFirewallAllow','timeSyncActive','monitoringActive'):need(f.get(field) is True,field+' not verified')
    need(f.get('sshListening') is False and f.get('rpcPublicListener') is False,'no SSH listener or non-loopback RPC listener allowed')
    for field in ('rootVolumePlanApproved','sessionAuditApproved','storageGrowthPlanApproved','monitoringApproved'):need(m.get('operations',{}).get(field) is True,'owner operational prerequisite missing: '+field)
    need(bool(m.get('operations',{}).get('alertDestination')),'reviewed reachable monitoring/alert destination required')
    return dict(status='FAIL' if errors else 'PASS',scope='AWS_HOST_PREFLIGHT_ONLY; not identity/transaction/launch authorization',host=name,observedAt=now(),blockers=errors,readOnly=True,manifestSha256=hashlib.sha256(json.dumps(m,sort_keys=True,separators=(',',':')).encode()).hexdigest())


def inventory(m,environment):
    errors=manifest_errors(m)
    a=m['automation'];e=m['environments'][environment]
    if errors:raise ValueError('; '.join(errors))
    if a.get('provisionApproved') is not True or a.get('transferBucketReviewed') is not True or not a.get('ssmTransferBucket') or not a.get('ssmKmsKeyArn'):
        raise ValueError('Explicit existing-host provisioning and reviewed encrypted SSM transfer bucket required')
    service=m.get('serviceIdentity',{})
    if any(type(service.get(k)) is not int or not 100<=service[k]<=60000 for k in ('uid','gid')):
        raise ValueError('Explicit stable non-root service UID/GID required for retained-data host replacement')
    # Inventory preparation never authorizes key creation or host starts.
    variables=dict(admin_transport='ssm',storage_mount_required=True,provision_approved=True,purpose=e['purpose'],public_network=environment,ansible_connection='amazon.aws.aws_ssm',ansible_aws_ssm_region=m['region'],ansible_aws_ssm_profile=m['operatorProfile'],ansible_aws_ssm_bucket_name=a['ssmTransferBucket'],ansible_aws_ssm_bucket_sse_mode='aws:kms',ansible_aws_ssm_bucket_sse_kms_key_id=a['ssmKmsKeyArn'],ansible_become=True,create_identities=False,start_node=False,offhost_recovery_confirmed=False,identity_tool_binary=a.get('identityToolBinary'),subnet_id=e.get('subnetId'),blockchain_id=e.get('blockchainId'),vm_id=e.get('vmId'))
    variables.update(disk_read_iodepth=32,disk_read_ioengine='libaio',disk_min_read_iops=2700)
    p=selected_profile(m)
    variables.update(minimum_vcpus=p['vcpusPerHost'],minimum_memory_mib=p['minimumMemoryMiB'])
    variables.update(runtime_uid=service['uid'],runtime_gid=service['gid'])
    variables['aws_deployment_manifest']=m
    nodes={h['name']:dict(ansible_host=h['instanceId'],ansible_aws_ssm_instance_id=h['instanceId'],public_ip=h['publicIp'],persistent_mount=h['persistentMount'],expected_filesystem_uuid=h['filesystemUuid'],expected_volume_id=h['dataVolumeId'],require_existing_database=h['dataLifecycle']=='existing',expected_public_identity=e['identities'][h['name']]) for h in m['hosts']}
    return {'all':{'children':{'primewave_pilot':{'hosts':nodes,'vars':variables}}}}


def ceremony_gate(m,environment):
    errors=manifest_errors(m);e=m['environments'][environment]
    def need(ok,message):
        if not ok:errors.append(message)
    need(m.get('awsLaunchApprovals',{}).get('accountVerified') is True,'AWS account verification remains unresolved')
    need(m.get('awsLaunchApprovals',{}).get('ec2LaunchAuthorized') is True,'separate owner EC2 launch authorization required; this utility never launches instances')
    need(m.get('allocationPolicy')=='C00' and m.get('nativeSupplyPW')==100000000 and m.get('nativeMinterEnabled') is False and m.get('feeSplitBps')==dict(validators=7000,treasury=2000,burn=1000),'locked C00 supply/fee policy mismatch')
    chain=e.get('evmChainId')
    need(e.get('chainIdApproved') is True and type(chain) is int and chain>=1000 and chain not in chain_id.DENIED,'explicit distinct approved '+environment+' Chain ID and fresh registry collision approval required')
    need(chain!=m['environments']['mainnet' if environment=='fuji' else 'fuji'].get('evmChainId'),'Fuji/Mainnet must have distinct Chain IDs')
    need(e.get('genesisApproved') is True and re.fullmatch('[0-9a-f]{64}',e.get('genesisSha256') or '') is not None,'exact final genesis hash approval required')
    need(e.get('genesisPublic',{}).get('publicAddressesReviewed') is True and e.get('genesisPublic',{}).get('custodyProposalApproved') is True,'public custody addresses and constructor-state RewardVault proposal approval required')
    for field in ('managerBootstrapReviewed','managerInitializationReviewed','genesisForksReviewed'):need(e.get(field) is True,'owner-reviewed '+field+' required')
    for field in ('signerKeystoreAlias','pChainFundingAddress','pChainBudgetAVAX','validatorBalanceAVAX','pwGasSourceRole','signatureAggregatorUrl','registryEvidence','managerArtifactSha256'):need(bool(e.get(field)),'explicit '+environment+' '+field+' required')
    for field in ('identityCreation','hostStart','funding','pChainTransactions','evmInitialization','nativeTransfers','feeAccounting','recoveryDrill'):need(e.get('approvals',{}).get(field) is True,'separate '+environment+' authorization missing: '+field)
    need(m.get('operations',{}).get('offHostRecoveryVerified') is True and bool(m.get('operations',{}).get('recoveryEvidenceSha256')),'tested off-host recovery and single-active-identity fencing evidence required')
    identities=e.get('identities',{})
    for field in ('nodeId','blsPublicKey','proofOfPossession','stakingCertificateSha256'):
        values=[i.get(field) for i in identities.values()]
        need(len(values)==2 and all(values) and len(set(values))==2,'two distinct fresh '+environment+' public '+field+' records required')
        other={i.get(field) for i in m['environments']['mainnet' if environment=='fuji' else 'fuji']['identities'].values() if i.get(field)}
        need(not (set(values)&other),'never reuse Fuji/Mainnet '+field)
    def custody(env):
        p=env.get('genesisPublic',{})
        return {a.lower() for a in [*p.get('allocationAddresses',{}).values(),*p.get('contracts',{}).values(),p.get('governanceProposer'),*p.get('emergencySigners',[]),env.get('managerProxy'),env.get('proxyAdmin')] if isinstance(a,str)}
    need(not custody(e)&custody(m['environments']['mainnet' if environment=='fuji' else 'fuji']),'Fuji and Mainnet custody/governance public addresses must be disjoint; test keys never become production custody')
    if environment=='mainnet':
        errors.extend(small_workload_errors(m))
        fuji=m['environments']['fuji']
        need(fuji.get('rehearsalPassed') is True and re.fullmatch('[0-9a-f]{64}',fuji.get('rehearsalEvidenceSha256') or '') is not None,'successful Fuji transaction/fee/recovery evidence required before mainnet')
        need(e.get('approvals',{}).get('launch') is True,'separate mainnet launch/signing approval required')
    # This review never emits an executable broadcast; final gate also requires
    # fresh PASS host reports and actual chain registry/genesis/artifact validation.
    return dict(status='BLOCKED' if errors else 'REVIEW_COMPLETE',environment=environment,blockers=errors,quota=quota_report(m),broadcastReady=False,signing=False,reason='Fresh host PASS reports, registry/genesis/artifact validation and operator ceremony approval remain mandatory')


def rpc_check(m,name,environment):
    """Reuse the existing four-method check through an operator-opened SSM tunnel."""
    h=host_named(m,name);e=m['environments'][environment]
    chain=e.get('evmChainId');blockchain=e.get('blockchainId');port=h.get('privateEndpoint',{}).get('operatorTunnelPort')
    if type(chain) is not int or chain<1000 or chain in chain_id.DENIED or not re.fullmatch(r'[1-9A-HJ-NP-Za-km-z]{50,52}',blockchain or '') or type(port) is not int or not 1024<=port<=65535:
        raise ValueError('Explicit non-demo Chain ID, actual Blockchain ID and local SSM tunnel port required')
    height=rpc_module.check(f'http://127.0.0.1:{port}/ext/bc/{blockchain}/rpc',chain)
    return dict(status='PASS',scope='four read-only EVM RPC methods only; not consensus/launch proof',host=name,environment=environment,chainId=chain,height=height,readOnly=True)


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--manifest',type=Path,required=True);p.add_argument('--host',choices=['validator-1','validator-2'])
    p.add_argument('--environment',choices=['fuji','mainnet'])
    mode=p.add_mutually_exclusive_group(required=True)
    for flag in ('collect-cloud','collect-local','preflight','inventory','readiness','rpc-check'):mode.add_argument('--'+flag,action='store_true')
    mode.add_argument('--select-profile',choices=PROFILE_IDS)
    p.add_argument('--cloud-facts',type=Path);p.add_argument('--host-facts',type=Path)
    a=p.parse_args()
    try:
        m=json.loads(a.manifest.read_text());public_only(m)
        if a.collect_cloud or a.collect_local or a.preflight or a.rpc_check:
            if not a.host:p.error('--host required')
        if a.inventory or a.readiness or a.rpc_check or a.collect_local:
            if not a.environment:p.error('--environment required')
        if a.select_profile:result=select_profile(m,a.select_profile)
        elif a.collect_cloud:result=collect_cloud(m,a.host)
        elif a.collect_local:result=collect_local(m,a.host,a.environment)
        elif a.preflight:
            if not a.cloud_facts or not a.host_facts:p.error('--cloud-facts and --host-facts required')
            result=host_gate(m,a.host,json.loads(a.cloud_facts.read_text()),json.loads(a.host_facts.read_text()))
        elif a.inventory:result=inventory(m,a.environment)
        elif a.rpc_check:result=rpc_check(m,a.host,a.environment)
        else:result=ceremony_gate(m,a.environment)
        print(json.dumps(result,indent=2))
        if result.get('status') in ('FAIL','BLOCKED'):raise SystemExit(1)
    except (ValueError,KeyError,TypeError,OSError,subprocess.SubprocessError) as error:
        print(json.dumps({'status':'FAIL','readOnly':True,'reason':str(error)}));raise SystemExit(1)
