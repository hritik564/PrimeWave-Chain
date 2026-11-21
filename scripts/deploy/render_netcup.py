#!/usr/bin/env python3
"""Validate public two-server inputs and render inventory/config; no SSH or writes."""
import argparse
import ipaddress
import json
import re
from pathlib import Path


def render(settings):
    if settings.get('purpose') not in ('fuji-rehearsal','mainnet-pilot'):
        raise ValueError('Explicit purpose required; no environment fallback')
    hosts=settings['hosts']
    if len(hosts)!=2 or len({h['name'] for h in hosts})!=2:
        raise ValueError('Exactly two distinct pilot hosts required')
    ips=[]
    for host in hosts:
        if not re.fullmatch(r'validator-[12]',host['name']) or not ipaddress.ip_address(host['publicIp']).is_global:
            raise ValueError('Explicit distinct public host IPs required')
        ips.append(host['publicIp'])
    if len(set(ips))!=2:
        raise ValueError('Hosts must have separate public IPs')
    if not settings.get('adminSshCidrs') or not settings.get('adminPublicKeys'):
        raise ValueError('SSH allowlist and public administrator keys required')
    for cidr in settings['adminSshCidrs']:
        network=ipaddress.ip_network(cidr,strict=True)
        if network.prefixlen==0 or network.is_private or network.is_loopback:
            raise ValueError('Explicit routable administrator CIDR required; no0/0')
    for key in settings['adminPublicKeys']:
        if not re.fullmatch(r'(?:ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256) [A-Za-z0-9+/=]+(?: [^\n]+)?',key):
            raise ValueError('Public SSH keys only; no file paths or private material')
    if settings.get('pilotRiskAccepted') is not True or settings.get('expectedValidators')!=2:
        raise ValueError('Two-validator non-resilient pilot acknowledgement required')
    if settings.get('provisionApproved') is not True:
        raise ValueError('Purchase/provision authorization is separate and required')
    if not re.fullmatch(r'[a-z_][a-z0-9_-]*',settings.get('adminUser','')) or settings['adminUser']=='root':
        raise ValueError('Explicit non-root SSH administrator required')
    network='fuji' if settings['purpose']=='fuji-rehearsal' else 'mainnet'
    variables=dict(purpose=settings['purpose'],public_network=network,provision_approved=True,
        admin_user=settings['adminUser'],admin_public_keys=settings['adminPublicKeys'],admin_ssh_cidrs=settings['adminSshCidrs'],
        create_identities=settings.get('identityCreationApproved') is True,
        start_node=settings.get('hostStartApproved') is True,
        subnet_id=settings.get('subnetId'),blockchain_id=settings.get('blockchainId'),vm_id=settings.get('vmId'),
        identity_tool_binary=settings.get('identityToolBinary'),
        offhost_recovery_confirmed=settings.get('offHostRecoveryConfirmed') is True,
        persistent_mount=settings.get('persistentMount'))
    mount=variables['persistent_mount']
    if not isinstance(mount,str) or not re.fullmatch(r'/[A-Za-z0-9_/-]+',mount) or '..' in Path(mount).parts or mount.startswith(('/tmp','/run','/dev','/proc','/sys','/root','/home')):
        raise ValueError('Explicit persistent block mount required')
    if variables['start_node'] and not (variables['create_identities'] and variables['offhost_recovery_confirmed']):
        raise ValueError('Start requires identity authorization and off-host recovery confirmation')
    nodes={host['name']:{'ansible_host':host['publicIp'],'public_ip':host['publicIp']} for host in hosts}
    return {'all':{'children':{'primewave_pilot':{'hosts':nodes,'vars':variables}}}}


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--settings',type=Path,required=True);a=p.parse_args()
    print(json.dumps(render(json.loads(a.settings.read_text())),indent=2,sort_keys=True))
