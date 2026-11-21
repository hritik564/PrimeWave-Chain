#!/usr/bin/env python3
"""Build pinned upstream PoA artifacts only. No RPC, signing or deployment."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import subprocess
import tarfile

ROOT=Path(__file__).resolve().parents[2]
ICM='40e1c898d44242aee25693a9cde4bc2485bd8242'
ARCHIVES={
 'primewave-icm-pinned.tar.gz':('sha256','ecfac403a782f9bbd1166b4674350126a48fad3cf97d094976895829f2ea93e1'),
 'openzeppelin-contracts-5.0.2.tgz':('sha512','ytPc6eLGcHHnapAZ9S+5qsdomhjo6QBHTDRRBFfTxXIpsicMhVPouPgmUPebZZZGX7vt9USA+Z+0M0dSVtSUEA=='),
 'openzeppelin-contracts-upgradeable-5.0.2.tgz':('sha512','0MmkHSHiW2NRFiT9/r5Lu4eJq5UJ4/tzlOgYXNAIj/ONkQTVnz22pLxDvp4C4uZ9he7ZFvGn3Driptn1/iU7tQ==')}


def verify(path,algorithm,expected):
    digest=hashlib.new(algorithm,path.read_bytes()).digest()
    actual=digest.hex() if algorithm=='sha256' else base64.b64encode(digest).decode()
    if actual!=expected:raise ValueError('Pinned archive digest mismatch: '+path.name)


def extract(archive,target,prefix):
    with tarfile.open(archive) as tar:
        for member in tar.getmembers():
            if not member.name.startswith(prefix) or not member.isfile():continue
            relative=Path(member.name[len(prefix):])
            if relative.is_absolute() or '..' in relative.parts:raise ValueError('Unsafe archive member')
            dest=target/relative
            dest.parent.mkdir(parents=True,exist_ok=True)
            with dest.open('xb') as output:output.write(tar.extractfile(member).read())


def build(archives,forge,libraries=None):
    output=ROOT/'genesis-build/pinned-manager'
    if output.exists():raise ValueError('Use a clean NEW pinned-manager build directory; never replace existing artifacts')
    for name,(algorithm,digest) in ARCHIVES.items():verify(archives/name,algorithm,digest)
    output.mkdir(parents=True)
    extract(archives/'primewave-icm-pinned.tar.gz',output/'icm','ava-labs-icm-services-40e1c89/icm-contracts/')
    if not (output/'icm/avalanche/validator-manager/PoAManager.sol').is_file():
        raise ValueError('Pinned manager archive layout differs')
    extract(archives/'openzeppelin-contracts-5.0.2.tgz',output/'oz','package/')
    extract(archives/'openzeppelin-contracts-upgradeable-5.0.2.tgz',output/'oz-upgradeable','package/')
    rel=output.relative_to(ROOT).as_posix()
    argv=[forge,'build',f'{rel}/icm/avalanche/validator-manager/PoAManager.sol',
          f'{rel}/icm/avalanche/validator-manager/ValidatorManager.sol','--offline',
          '--out',str(output/'artifacts'),'--cache-path',str(output/'cache'),'--remappings',
          f'@utilities/={rel}/icm/avalanche/utilities/','--remappings',f'@subnet-evm/={rel}/icm/avalanche/subnet-evm/',
          '--remappings',f'@openzeppelin/contracts@5.0.2/={rel}/oz/',
          '--remappings',f'@openzeppelin/contracts-upgradeable@5.0.2/={rel}/oz-upgradeable/']
    if libraries:
        import re
        if libraries.get('publicAddressReviewed') is not True or not re.fullmatch(r'0x[0-9a-fA-F]{40}',libraries.get('ValidatorMessages','')) or int(libraries['ValidatorMessages'],16)==0:
            raise ValueError('Reviewed public ValidatorMessages library address required')
        argv.extend(['--libraries',f'{rel}/icm/avalanche/validator-manager/ValidatorMessages.sol:ValidatorMessages:'+libraries['ValidatorMessages']])
    subprocess.run(argv,cwd=ROOT,check=True)
    artifacts={}
    for name in ('PoAManager','ValidatorManager'):
        artifact=output/f'artifacts/{name}.sol/{name}.json'
        data=json.loads(artifact.read_text())
        import re
        linked=re.fullmatch(r'(?:0x)?[0-9a-fA-F]+',data['bytecode']['object']) is not None
        artifacts[name]={'artifactSha256':hashlib.sha256(artifact.read_bytes()).hexdigest(),
                         'creationTemplateSha256':hashlib.sha256(data['bytecode']['object'].encode()).hexdigest(),
                         'unresolvedLibraryReferences':data['bytecode'].get('linkReferences',{}),
                         'allLibraryAddressesLinked':linked,
                         'scope':'uninitialized artifact; constructor/initializer/proxy owner review still mandatory'}
    result={'icmCommit':ICM,'openzeppelinVersion':'5.0.2','compiler':'0.8.30','broadcasts':0,'artifacts':artifacts}
    (output/'verification.json').write_text(json.dumps(result,indent=2)+'\n')
    return result


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--archives',type=Path,required=True,help='Existing three pinned public source archives; never credentials')
    p.add_argument('--forge',default='forge')
    p.add_argument('--libraries-manifest',type=Path,help='Reviewed public library address; omitted builds explicitly unlinked templates')
    args=p.parse_args()
    print(json.dumps(build(args.archives,args.forge,json.loads(args.libraries_manifest.read_text()) if args.libraries_manifest else None),indent=2))
