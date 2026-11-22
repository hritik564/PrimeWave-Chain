#!/usr/bin/env python3
"""Offline pinned-manager custody tests. Requires existing verified public sources.
No downloads, keys, RPC, node startup or public transactions. Outputs are temporary.
"""
import argparse
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
from build_manager import ROOT,ARCHIVES,verify


def run(archives,forge):
    for name,(algorithm,digest) in ARCHIVES.items():verify(archives/name,algorithm,digest)
    directory=ROOT/'genesis-build/pinned-manager'
    specs=[('primewave-icm-pinned.tar.gz','ava-labs-icm-services-40e1c89/icm-contracts/','icm'),('openzeppelin-contracts-5.0.2.tgz','package/','oz'),('openzeppelin-contracts-upgradeable-5.0.2.tgz','package/','oz-upgradeable')]
    for name,prefix,target in specs:
        with tarfile.open(archives/name) as tar:
            for member in tar.getmembers():
                if member.isfile() and member.name.startswith(prefix) and member.name.endswith('.sol'):
                    rel=Path(member.name[len(prefix):])
                    if '..' in rel.parts or rel.is_absolute():raise ValueError('Unsafe public archive member')
                    content=tar.extractfile(member)
                    if content is None:raise ValueError('Public source member missing')
                    if (directory/target/rel).read_bytes()!=content.read():raise ValueError('Pinned extracted source differs: '+str(rel))
    env=dict(os.environ)
    for key in ('ETH_RPC_URL','FOUNDRY_ETH_RPC_URL','FOUNDRY_FORK_URL'):env.pop(key,None)
    with tempfile.TemporaryDirectory(prefix='pw-manager-custody-') as out:
        env.update(FOUNDRY_TEST='tests/pinned-manager-custody',FOUNDRY_OUT=out+'/artifacts',FOUNDRY_CACHE_PATH=out+'/cache')
        args=[forge,'test','--offline','--match-contract','PinnedManagerCustodyTest','--no-match-test','testWriteSyntheticExportForPythonIntegration','-vv']
        for mapping in ('@openzeppelin/contracts@5.0.2/=genesis-build/pinned-manager/oz/','@openzeppelin/contracts-upgradeable@5.0.2/=genesis-build/pinned-manager/oz-upgradeable/','@utilities/=genesis-build/pinned-manager/icm/avalanche/utilities/','@subnet-evm/=genesis-build/pinned-manager/icm/avalanche/subnet-evm/'):
            args.extend(['--remappings',mapping])
        subprocess.run(args,cwd=ROOT,env=env,check=True)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--archives',type=Path,required=True);p.add_argument('--forge',default='forge')
    a=p.parse_args();run(a.archives,a.forge)
