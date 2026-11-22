#!/usr/bin/env python3
"""Offline file/runtime provenance verification only, never execution approval."""
import hashlib
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]

def verify():
    lock=json.loads((ROOT/'config/mainnet/custody-artifacts.lock.json').read_text())
    if lock['ownerApproved'] is not False:raise ValueError('Review lock cannot grant production approval')
    for name,item in lock['artifacts'].items():
        if 'path' in item:
            raw=(ROOT/item['path']).read_bytes()
            if hashlib.sha256(raw).hexdigest()!=item['sha256']:raise ValueError('Published artifact digest differs: '+name)
            data=json.loads(raw)
            if hashlib.sha256(bytes.fromhex(data['deployedBytecode'].removeprefix('0x'))).hexdigest()!=item['runtimeSha256']:raise ValueError('Safe runtime differs')
        else:
            if hashlib.sha256((ROOT/item['sourcePath']).read_bytes()).hexdigest()!=item['sourceSha256']:raise ValueError('Policy source changed; rebuild/review required')
            output=ROOT/'contracts/out'/(name+'.sol')/(name+'.json')
            if not output.exists():raise ValueError('Compiled offline artifact missing; run forge build --offline')
            data=json.loads(output.read_text())
            if hashlib.sha256(bytes.fromhex(data['deployedBytecode']['object'].removeprefix('0x'))).hexdigest()!=item['runtimeSha256']:raise ValueError('Compiled policy runtime differs; no automatic lock update')
    tree=ROOT/'contracts/lib/openzeppelin-contracts-v561'
    digest=hashlib.sha256(b''.join(str(f.relative_to(tree)).encode()+b'\0'+f.read_bytes() for f in sorted((tree/'contracts').rglob('*.sol')))).hexdigest()
    if digest!=lock['openzeppelinSolidityTreeSha256']:raise ValueError('Pinned OZ Solidity tree differs')
    if hashlib.sha256((ROOT/'contracts/src/EmergencyMultisig.sol').read_bytes()).hexdigest()!=lock['emergencyBaseSourceSha256']:raise ValueError('Emergency base differs')
    return dict(status='OFFLINE_HASHES_VERIFIED',version=lock['version'],executionApproved=False,externalAudit=False)

if __name__=='__main__':print(json.dumps(verify(),indent=2))
