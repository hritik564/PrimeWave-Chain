#!/usr/bin/env python3
"""Exact-byte local Subnet-EVM import. Plugin process only, no daemon/keys/txs.
Requires explicit genesis, expectations and verified released binary archive.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import tarfile
import zipfile
ROOT=Path(__file__).resolve().parents[2]
MODULE_SUM='h1:rHEc0OrOyyh6gHIs4KrKyDm/vw81J0Cc3FDwgCRklgg='
COMMIT='fdb2c1b9b02ef357b5867d5ababb6acc83837a01'

def duplicate_safe(pairs):
    result={}
    for key,value in pairs:
        if key in result:raise ValueError('Duplicate JSON key: '+key)
        result[key]=value
    return result

def validate_files(genesis,expectations):
    raw=genesis.read_bytes();g=json.loads(raw,object_pairs_hook=duplicate_safe)
    e=json.loads(expectations.read_bytes(),object_pairs_hook=duplicate_safe)
    from export_mainnet_genesis import public_only
    public_only(e);public_only(g)
    digest=hashlib.sha256(raw).hexdigest()
    if e.get('schema')!='primewave-exact-genesis-v1' or e.get('genesisFileSha256')!=digest:raise ValueError('Exact genesis file SHA256 mismatch')
    if g.get('config',{}).get('chainId')!=e.get('chainId') or g.get('alloc')!=e.get('accounts') or not e.get('calls'):raise ValueError('Complete alloc and ownership expectations required')
    if sum(int(a['balance'],0) for a in g['alloc'].values())!=100000000*10**18:raise ValueError('Exact100M supply required')
    if not e.get('publicNodeIdentity'):raise ValueError('Existing public NodeID/BLS context required; no identities generated')
    return digest

def verify_plugin(binary,archive):
    lock=json.loads((ROOT/'config/mainnet/binaries.lock.json').read_text())
    if platform.system()=='Darwin':name='subnet-evm-macos-v1.15.1.zip'
    elif platform.system()=='Linux' and platform.machine()=='x86_64':name='subnet-evm-linux-amd64-v1.15.1.tar.gz'
    else:raise ValueError('No pinned executable for host')
    pin=lock['assets'][name]
    if hashlib.sha256(archive.read_bytes()).hexdigest()!=pin['sha256']:raise ValueError('Pinned binary archive differs')
    if name.endswith('.zip'):
        with zipfile.ZipFile(archive) as z:
            paths=[n for n in z.namelist() if n.endswith('/subnet-evm') or n=='subnet-evm']
            if len(paths)!=1:raise ValueError('Ambiguous VM archive')
            released=z.read(paths[0])
    else:
        with tarfile.open(archive) as t:
            members=[m for m in t.getmembers() if m.isfile() and m.name.endswith('/subnet-evm')]
            if len(members)!=1:raise ValueError('Ambiguous VM archive')
            file=t.extractfile(members[0])
            if file is None:raise ValueError('Missing VM')
            released=file.read()
    if released!=binary.read_bytes():raise ValueError('Executable differs from pinned release')
    return hashlib.sha256(released).hexdigest()

def run(a):
    digest=validate_files(a.genesis,a.expectations);vm_hash=verify_plugin(a.vm_binary,a.binary_archive)
    directory=ROOT/'tools/mainnet-offline';env=dict(os.environ)
    for key in ('ETH_RPC_URL','FOUNDRY_ETH_RPC_URL','FOUNDRY_FORK_URL'):env.pop(key,None)
    env.update(GOTOOLCHAIN='local',GOPROXY='off',GOSUMDB='off')
    module=json.loads(subprocess.check_output([a.go,'list','-m','-json','github.com/ava-labs/avalanchego'],cwd=directory,env=env))
    if module.get('Version')!='v1.15.1' or module.get('Sum')!=MODULE_SUM or module.get('Replace'):raise ValueError('Pinned AvalancheGo client module required')
    subprocess.run([a.go,'mod','verify'],cwd=directory,env=env,check=True,capture_output=True)
    env.update(PRIMEWAVE_EXACT_GENESIS=str(a.genesis.resolve()),PRIMEWAVE_EXACT_EXPECTATIONS=str(a.expectations.resolve()),PRIMEWAVE_EXACT_VM_BINARY=str(a.vm_binary.resolve()),PRIMEWAVE_EXACT_VM_SHA256=vm_hash)
    result=subprocess.run([a.go,'test','-mod=readonly','-run','^TestExactGenesisWhenSupplied$','-count=1','-v','-timeout=180s','.'],cwd=directory,env=env,capture_output=True,text=True,timeout=240)
    if result.returncode!=0 or 'PASS_EXACT_GENESIS_IMPORT '+digest not in result.stdout or '--- SKIP:' in result.stdout:raise RuntimeError('Exact import NOT verified:\n'+result.stdout+result.stderr)
    if hashlib.sha256(a.genesis.read_bytes()).hexdigest()!=digest:raise ValueError('Genesis changed')
    return dict(status='PASS_EXACT_LOCAL_VM_IMPORT',genesisFileSha256=digest,expectationsSha256=hashlib.sha256(a.expectations.read_bytes()).hexdigest(),avalancheGoCommit=COMMIT,subnetEvm='v1.15.1',pluginProtocol=46,vmBinarySha256=vm_hash,
        outputSha256=hashlib.sha256(result.stdout.encode()).hexdigest(),productionApproved=False,signing=False,broadcast=False,consensusVerified=False,scope='Exact-byte local plugin acceptance/state/getter checks only; not P-Chain or live consensus')

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for name in ('genesis','expectations','vm-binary','binary-archive'):p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--go',default='go');a=p.parse_args();print(json.dumps(run(a),indent=2))
