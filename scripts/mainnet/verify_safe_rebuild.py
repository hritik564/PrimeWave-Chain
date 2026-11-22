#!/usr/bin/env python3
"""Recompile public Safe1.4.1 build-info OFFLINE using verified solc-js0.7.6.
Requires pre-existing public package/compiler, never downloads or installs.
"""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile
ROOT=Path(__file__).resolve().parents[2]
COMPILER_SHA256='b94e69dfb056b3e26080f805ab43b668afbc0ac70bf124bfb7391ecfc0172ad2'
BUILD_INFO='package/build/artifacts/build-info/0128da95e283bfa75197e80e5a451911.json'

def run(package, compiler, node='node'):
    lock=json.loads((ROOT/'config/mainnet/custody-artifacts.lock.json').read_text())
    if base64.b64encode(hashlib.sha512(package.read_bytes()).digest()).decode()!=lock['sha512']:raise ValueError('Safe archive mismatch')
    if hashlib.sha256(compiler.read_bytes()).hexdigest()!=COMPILER_SHA256:raise ValueError('Compiler SHA256 mismatch')
    with tarfile.open(package) as tar:
        content=tar.extractfile(BUILD_INFO)
        if content is None:raise ValueError('Missing complete build-info')
        raw=content.read();build=json.loads(raw)
    if build['solcLongVersion']!='0.7.6+commit.7338295f':raise ValueError('Compiler build differs')
    code="""const fs=require('fs');const solc=require(process.argv[1]);
const input=fs.readFileSync(process.argv[2],'utf8');
const version=solc.cwrap('solidity_version','string',[])();
if(!version.startsWith('0.7.6+commit.7338295f'))throw Error('compiler version mismatch');
const output=solc.cwrap('solidity_compile','string',['string','number','number'])(input,0,0);
fs.writeFileSync(process.argv[3],output);"""
    with tempfile.TemporaryDirectory(prefix='pw-safe-offline-') as tmp:
        source=Path(tmp)/'input.json';output=Path(tmp)/'output.json'
        source.write_text(json.dumps(build['input']))
        subprocess.run([node,'-e',code,str(compiler.resolve()),str(source),str(output)],check=True,cwd=tmp)
        compiled=json.loads(output.read_text())
    errors=[e for e in compiled.get('errors',[]) if e['severity']=='error']
    if errors:raise ValueError(errors)
    verified={}
    for name,path in [('Safe','contracts/Safe.sol'),('SafeProxy','contracts/proxies/SafeProxy.sol')]:
        actual=compiled['contracts'][path][name];published=build['output']['contracts'][path][name]
        vendored=json.loads((ROOT/lock['artifacts'][name]['path']).read_text())
        for field,artifact_field in [('bytecode','bytecode'),('deployedBytecode','deployedBytecode')]:
            value=actual['evm'][field]['object']
            if value!=published['evm'][field]['object'] or value!=vendored[artifact_field].removeprefix('0x'):raise ValueError('Rebuild bytecode mismatch: '+name)
        if actual['metadata']!=published['metadata'] or actual['abi']!=published['abi'] or actual['abi']!=vendored['abi']:raise ValueError('Rebuild metadata/ABI mismatch: '+name)
        verified[name]=dict(creationSha256=hashlib.sha256(bytes.fromhex(actual['evm']['bytecode']['object'])).hexdigest(),runtimeSha256=lock['artifacts'][name]['runtimeSha256'],metadataSha256=hashlib.sha256(actual['metadata'].encode()).hexdigest(),completeBytecodeMatch=True,abiMatch=True,metadataMatch=True)
    return dict(syntheticReviewOnly=True,externalAudit=False,productionApproved=False,compiler='0.7.6+commit.7338295f',compilerSha256=COMPILER_SHA256,
        compilerSource='https://raw.githubusercontent.com/ethereum/solc-bin/gh-pages/bin/soljson-v0.7.6+commit.7338295f.js',
        packageSha512=lock['sha512'],buildInfo=BUILD_INFO,buildInfoSha256=hashlib.sha256(raw).hexdigest(),
        settings=build['input']['settings'],sourceSha256={p:hashlib.sha256(v['content'].encode()).hexdigest() for p,v in sorted(build['input']['sources'].items())},verified=verified,
        limitations=['Reproducible bytes do not prove safety, absence of backdoors, trusted compiler bootstrap or external audit','Only Safe and SafeProxy from solc0.7.6 build-info reproduced; other package contracts/0.6.12 build are not selected'])

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--package',type=Path,required=True);p.add_argument('--compiler',type=Path,required=True);p.add_argument('--node',default='node')
    a=p.parse_args();print(json.dumps(run(a.package,a.compiler,a.node),sort_keys=True,indent=2))
