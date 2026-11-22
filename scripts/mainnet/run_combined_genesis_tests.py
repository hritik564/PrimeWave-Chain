#!/usr/bin/env python3
"""Offline SYNTHETIC-only manager+custody integration. No RPC, keys or nodes.
Never changes existing pinned-manager artifacts, locks or production manifests.
"""
import argparse
import json
from verify_custody_artifacts import verify as verify_custody
import os
from pathlib import Path
import subprocess
import tarfile
from build_manager import ROOT, ARCHIVES, verify

def run(archives, forge):
    verify_custody()
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
                    if content is None or (directory/target/rel).read_bytes()!=content.read():raise ValueError('Pinned source mismatch: '+str(rel))
    env=dict(os.environ)
    for key in ('ETH_RPC_URL','FOUNDRY_ETH_RPC_URL','FOUNDRY_FORK_URL'):env.pop(key,None)
    fixture=ROOT/'genesis-build/combined-synthetic-build/fixture.input.json'
    fixture.parent.mkdir(parents=True,exist_ok=True)
    expected=(ROOT/'tests/fixtures/custody-genesis.fixture.json').read_bytes()
    if fixture.exists() and fixture.read_bytes()!=expected:raise ValueError('Existing synthetic fixture copy differs')
    if not fixture.exists():fixture.write_bytes(expected)
    env.update(FOUNDRY_TEST='tests/combined-genesis',FOUNDRY_OUT='genesis-build/combined-synthetic-build/artifacts',FOUNDRY_CACHE_PATH='genesis-build/combined-synthetic-build/cache')
    args=[forge,'test','--offline','--match-contract','CombinedGenesisTest','--no-match-test','testWriteSyntheticExportForPythonIntegration|testCompleteExportRepeatabilityAndRestore','-vv']
    for mapping in ('@openzeppelin/contracts@5.0.2/=genesis-build/pinned-manager/oz/','@openzeppelin/contracts-upgradeable@5.0.2/=genesis-build/pinned-manager/oz-upgradeable/','@utilities/=genesis-build/pinned-manager/icm/avalanche/utilities/','@subnet-evm/=genesis-build/pinned-manager/icm/avalanche/subnet-evm/'):
        args.extend(['--remappings',mapping])
    args.extend(['--libraries','genesis-build/pinned-manager/icm/avalanche/validator-manager/ValidatorMessages.sol:ValidatorMessages:0x000000000000000000000000000000000000e100'])
    subprocess.run(args,cwd=ROOT,env=env,check=True)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--archives',type=Path,required=True);parser.add_argument('--forge',default='forge')
    args=parser.parse_args();run(args.archives,args.forge)
