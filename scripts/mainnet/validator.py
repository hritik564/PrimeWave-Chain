#!/usr/bin/env python3
"""Fail-closed public-network validator command builder. Check-only by default."""
import argparse
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
REQUIRED_PATHS = ('db-dir','data-dir','log-dir','plugin-dir','chain-config-dir',
                  'staking-tls-cert-file','staking-tls-key-file','staking-signer-key-file')


def path_check(value, directory):
    p=Path(value)
    if not p.is_absolute() or '..' in p.parts or any(x in p.parts for x in ('.local-networks','local-data','local-bin')):
        raise ValueError('Explicit isolated non-demo absolute paths required')
    if any(x.is_symlink() for x in (p,*p.parents)) or not p.exists() or (p.is_dir() != directory):
        raise ValueError('Required path missing, symlinked or wrong type')
    return p


def validate(config, chain, identity):
    if type(config.get('network-id')) is bool or config.get('network-id') not in ('mainnet','fuji',1,5):
        raise ValueError('Explicit public mainnet/Fuji network required')
    network='mainnet' if config['network-id'] in ('mainnet',1) else 'fuji'
    if identity.get('environment') != network or identity.get('freshCeremonyIdentity') is not True:
        raise ValueError('Fresh environment-specific identity attestation required')
    if config.get('partial-sync-primary-network') is not True or config.get('sybil-protection-enabled') is not True:
        raise ValueError('Public-network P-Chain sync and sybil protection required')
    if config.get('http-host') != '127.0.0.1' or config.get('api-admin-enabled') is not False:
        raise ValueError('RPC must be private and admin disabled')
    if config.get('staking-port') != 9651 or not ipaddress.ip_address(config['public-ip']).is_global:
        raise ValueError('Public IP and TCP9651 required')
    import re
    if not re.fullmatch(r'[1-9A-HJ-NP-Za-km-z]{50,52}',config.get('track-subnets','')):
        raise ValueError('Real ceremony-generated Subnet ID required')
    if 'api-keystore-enabled' in config:
        raise ValueError('Obsolete keystore flag forbidden')
    if config.get('bootstrap-ids') == '' or config.get('bootstrap-ips') == '':
        raise ValueError('Never disable public-network bootstrap peers')
    if any(('key' in k or 'signer' in k) and k.endswith('-content') for k in config):
        raise ValueError('Inline key content refused')
    if chain.get('pruning-enabled') is not True:
        raise ValueError('Pruned validator storage configuration required')
    expected={'eth','eth-filter','internal-blockchain','internal-transaction','net','web3'}
    if set(chain.get('eth-apis',[])) != expected or chain.get('allow-unprotected-txs') is not False:
        raise ValueError('Restricted Subnet-EVM API list and replay protection required')
    return network


def prepare(config,chain,identity,binary,plugin,lock):
    network=validate(config,chain,identity)
    for key,value in config.items():
        if key not in REQUIRED_PATHS and (key.endswith(('-file','-dir','-content')) or isinstance(value,str) and value.startswith('/')):
            raise ValueError('Unreviewed filesystem or inline-content flag refused')
    for key in REQUIRED_PATHS:
        p=path_check(config[key],key.endswith('-dir'))
        if key in ('staking-tls-key-file','staking-signer-key-file'):
            if p.stat().st_mode & 0o077:
                raise ValueError('Identity file permissions are not private')
    cert=Path(config['staking-tls-cert-file'])
    if hashlib.sha256(cert.read_bytes()).hexdigest() != identity.get('stakingCertificateSha256'):
        raise ValueError('Public identity certificate digest differs')
    if identity.get('subnetId') != config['track-subnets'] or identity.get('vmId') != plugin.name:
        raise ValueError('Saved production registration/VM identity differs')
    if plugin.parent.resolve() != Path(config['plugin-dir']).resolve():
        raise ValueError('VM must exist in the configured plugin directory')
    for component,executable in (('avalanchego',binary),('subnet-evm',plugin)):
        path_check(str(executable),False)
        asset=lock['assets'][f'{component}-linux-amd64-v1.15.1.tar.gz']
        if hashlib.sha256(executable.read_bytes()).hexdigest() != asset['binarySha256']:
            raise ValueError('Installed binary differs from locked upstream executable')
        result=subprocess.run([str(executable),'--version'],capture_output=True,text=True,timeout=10)
        if result.returncode or 'rpcchainvm=46' not in result.stdout+result.stderr or '1.15.1' not in result.stdout+result.stderr:
            raise ValueError('Node/VM version or protocol differs')
    return network


if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for name in ('config','chain-config','identity','binary','plugin'):
        p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--start',action='store_true')
    p.add_argument('--approve-start',action='store_true')
    a=p.parse_args()
    if a.start != a.approve_start:
        p.error('Startup requires both --start and --approve-start')
    config=json.loads(a.config.read_text()); chain=json.loads(a.chain_config.read_text())
    identity=json.loads(a.identity.read_text())
    lock=json.loads((ROOT/'config/mainnet/binaries.lock.json').read_text())
    network=prepare(config,chain,identity,a.binary.absolute(),a.plugin.absolute(),lock)
    # Require the reviewed chain file to actually reside in the supplied config tree.
    if a.chain_config.parent.name != identity.get('blockchainId') or not a.chain_config.resolve().is_relative_to(Path(config['chain-config-dir']).resolve()):
        raise SystemExit('Chain config is not installed under the configured chain directory')
    if not a.start:
        print(json.dumps({'status':'check-only','network':network,'protocol':46,'writes':False}))
    else:
        if os.getuid()==0:
            raise SystemExit('Run the validator under an unprivileged service user')
        os.execv(str(a.binary.absolute()),[str(a.binary.absolute()),'--config-file='+str(a.config.absolute())])
