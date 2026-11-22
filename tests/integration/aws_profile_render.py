#!/usr/bin/env python3
"""Offline integration: real shared Ansible/Jinja config for both AWS profiles.
Requires the project's Ansible controller dependencies; never opens a connection.
"""
import json
from itertools import product
from pathlib import Path
import sys
import yaml
from jinja2 import Environment,StrictUndefined

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tests'))
import test_aws_pilot as fixtures
aws=fixtures.aws
play=yaml.safe_load((ROOT/'deploy/common/validator.yml').read_text())[0]
config_task=next(t for t in play['tasks'] if t.get('name')=='Render private administrative RPC and persistent P-Chain configuration')
source=config_task['ansible.builtin.copy']['content']
assertions=next(t for t in play['pre_tasks'] if t.get('name')=='Enforce supported small-pilot host profile')['ansible.builtin.assert']['that']
env=Environment(undefined=StrictUndefined,trim_blocks=True)
for profile,network,region in product(aws.PROFILE_IDS,('fuji','mainnet'),aws.SUPPORTED_REGIONS):
    case=fixtures.AwsPilotTests();case.setUp()
    manifest=aws.select_profile(case.m,profile)
    manifest['region']=region
    for n,h in enumerate(manifest['hosts']):h.update(region=region,availabilityZone=region+('a' if n==0 else 'b'))
    manifest['automation'].update(provisionApproved=True,transferBucketReviewed=True,ssmTransferBucket='FIXTURE',ssmKmsKeyArn='FIXTURE')
    selected=aws.selected_profile(manifest)
    inventory=aws.inventory(manifest,network)['all']['children']['primewave_pilot']
    v=dict(inventory['vars'],**inventory['hosts']['validator-1'])
    v.update(runtime_root='/mnt/pwdata/primewave/'+v['purpose'],source_root='/opt/primewave/source',release_root='/opt/primewave/releases/v1.15.1')
    config=json.loads(env.from_string(source).render(**v))
    assert config['partial-sync-primary-network'] is True
    assert config['network-id']==network and config['db-dir']==v['runtime_root']+'/db'
    assert config['sybil-protection-enabled'] is True and config['http-host']=='127.0.0.1'
    assert config['api-admin-enabled'] is False
    unit=env.from_string((ROOT/'deploy/common/primewave.service.j2').read_text()).render(**v)
    assert '\nExecStart=/opt/primewave/releases/v1.15.1/avalanchego --config-file=/etc/primewave/'+v['purpose']+'.json\n' in unit
    assert '--storage-binding /etc/primewave/'+v['purpose']+'-storage.json\n' in unit
    facts=dict(distribution='Ubuntu',distribution_version='24.04',architecture='x86_64',processor_vcpus=selected['vcpusPerHost'],memtotal_mb=selected['minimumMemoryMiB'])
    for expression in assertions:assert env.compile_expression(expression)(**v,ansible_facts=facts),expression
    cpu=next(e for e in assertions if 'processor_vcpus' in e)
    ram=next(e for e in assertions if 'memtotal_mb' in e)
    facts['processor_vcpus']-=1
    assert not env.compile_expression(cpu)(**v,ansible_facts=facts)
    facts['processor_vcpus']+=1;facts['memtotal_mb']-=1
    assert not env.compile_expression(ram)(**v,ansible_facts=facts)
    print('PASS',profile,network,region,'shared Ansible CPU/RAM boundaries, rendered partial-sync config and systemd mount guard; no AWS connection')
