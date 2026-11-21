#!/usr/bin/env python3
"""Read-only systemd startup guard. Private identity files are stat'ed, never read."""
import argparse
import hashlib
import json
from pathlib import Path
import stat


def regular(path,directory=False):
    path=Path(path)
    if not path.is_absolute() or '..' in path.parts or any(p.is_symlink() for p in (path,*path.parents)):
        raise ValueError('Unsafe or symlinked startup path')
    if not path.exists() or path.is_dir()!=directory:
        raise ValueError('Required persistent startup path missing')
    if not directory and not stat.S_ISREG(path.stat().st_mode):raise ValueError('Regular file required')
    return path


def check(config,identity,lock,binary,purpose):
    network={'fuji-rehearsal':'fuji','mainnet-pilot':'mainnet'}.get(purpose)
    if not network or config.get('network-id')!=network or identity.get('purpose')!=purpose or identity.get('environment')!=network or identity.get('freshCeremonyIdentity') is not True:
        raise ValueError('Fresh purpose-specific public identity required')
    if config.get('http-host')!='127.0.0.1' or config.get('api-admin-enabled') is not False or config.get('partial-sync-primary-network') is not True or config.get('sybil-protection-enabled') is not True:
        raise ValueError('Private administrative RPC and public P-Chain synchronization required')
    if any(k.endswith('-content') for k in config) or config.get('bootstrap-ids')=='' or config.get('bootstrap-ips')=='':
        raise ValueError('Inline credentials and disabled public bootstrap refused')
    root=regular(config['data-dir'],True)
    if (root/'.managed-purpose').read_text().strip()!=purpose:raise ValueError('Persistent runtime purpose mismatch')
    for key in ('db-dir','log-dir','plugin-dir','chain-config-dir'):
        p=regular(config[key],True)
        if not p.is_relative_to(root):raise ValueError('All runtime directories must remain inside the managed persistent root')
    for key in ('staking-tls-cert-file','staking-tls-key-file','staking-signer-key-file'):
        p=regular(config[key])
        if not p.is_relative_to(root/'staking') or p.stat().st_mode&0o077:
            raise ValueError('Identity must remain private inside persistent staking directory')
        # Deliberately do not open/read either private-key file.
    cert=Path(config['staking-tls-cert-file'])
    if hashlib.sha256(cert.read_bytes()).hexdigest()!=identity.get('stakingCertificateSha256'):
        raise ValueError('Public validator certificate changed')
    if not identity.get('nodeId','').startswith('NodeID-') or not identity.get('blsPublicKey') or not identity.get('proofOfPossession'):
        raise ValueError('Public NodeID/BLS/PoP required')
    if hashlib.sha256(regular(binary).read_bytes()).hexdigest()!=lock['assets']['avalanchego-linux-amd64-v1.15.1.tar.gz']['binarySha256']:
        raise ValueError('Node binary checksum mismatch')
    for plugin in Path(config['plugin-dir']).iterdir():
        if hashlib.sha256(regular(plugin).read_bytes()).hexdigest()!=lock['assets']['subnet-evm-linux-amd64-v1.15.1.tar.gz']['binarySha256']:
            raise ValueError('Unverified plugin refused')
    return {'status':'startup-guard-passed','environment':network,'privateKeyContentsRead':False}


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for name in ('config','identity','lock','binary'):p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--purpose',required=True)
    a=p.parse_args()
    print(json.dumps(check(json.loads(a.config.read_text()),json.loads(a.identity.read_text()),json.loads(a.lock.read_text()),a.binary,a.purpose)))
