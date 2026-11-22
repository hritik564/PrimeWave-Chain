#!/usr/bin/env python3
"""Public-input-only offline production candidate author. Never approves deployment.
New isolated output required; original locks/manifests are never written.
"""
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
from chain_id import approved
from genesis_candidate import canonical,materialize,C00,UNIT
from verify_custody_artifacts import verify
from build_manager import ARCHIVES,verify as verify_archive
ROOT=Path(__file__).resolve().parents[2]
B58='123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz'

def digest(raw):return hashlib.sha256(raw).hexdigest()
def read_public(path):
    if path.suffix!='.json' or any(p in path.parts for p in ('.aws','.ssh','.gnupg','staking')) or any(p.is_symlink() for p in (path,*path.parents)) or path.stat().st_size>16*1024*1024:raise ValueError('Non-symlink public JSON input <=16MiB required')
    raw=path.read_bytes()
    from validate_exact_genesis import duplicate_safe
    value=json.loads(raw,object_pairs_hook=duplicate_safe);public_only(value)
    return raw,value
def decode_id(value):
    if not isinstance(value,str) or not 32<=len(value)<=60 or any(c not in B58 for c in value):raise ValueError('CB58 ID required')
    n=0
    for c in value:n=n*58+B58.index(c)
    raw=b'\0'*(len(value)-len(value.lstrip('1')))+(n.to_bytes((n.bit_length()+7)//8,'big') if n else b'')
    if len(raw)!=36 or hashlib.sha256(raw[:32]).digest()[-4:]!=raw[-4:] or not any(raw[:32]):raise ValueError('Nonzero32-byte ID/checksum required')
    return raw[:32]

def public_only(value):
    if isinstance(value,dict):
        for k,v in value.items():
            if k.lower() in ('key','keys','keyfile','keystore','wallet') or any(w in k.lower() for w in ('privatekey','private_key','secret','mnemonic','password','credential')):raise ValueError('Public metadata only')
            public_only(v)
    elif isinstance(value,list):
        for v in value:public_only(v)

def validate_inputs(public,base,receipt,review,raw_public,raw_base,raw_receipt,chain):
    for v in (public,base,receipt,review):public_only(v)
    if any(v.get('syntheticTestOnly') or v.get('fixtureOnly') for v in (public,base,receipt,review)):raise ValueError('Synthetic inputs forbidden')
    if public.get('publicAddressesReviewed') is not True or public.get('custodyProposalApproved') is not True:raise ValueError('Owner-reviewed public addresses/custody required')
    if review.get('ownerReviewed') is not True or not review.get('reference'):raise ValueError('Explicit public input review required')
    for k,raw in [('publicSha256',raw_public),('baseSha256',raw_base),('acceptedSubnetSha256',raw_receipt)]:
        if review.get(k)!=digest(raw):raise ValueError('Input review digest mismatch: '+k)
    subnet=decode_id(receipt.get('subnetId'))
    if receipt.get('networkId')!=1 or receipt.get('accepted') is not True or receipt.get('transactionId')!=receipt['subnetId'] or not receipt.get('reference'):raise ValueError('Accepted Mainnet CreateSubnet receipt required; offline authenticity remains owner-reviewed')
    if public.get('managerSubnetId')!=receipt['subnetId']:raise ValueError('Accepted SubnetID binding mismatch')
    if type(public.get('genesisTimestamp')) is not int or public['genesisTimestamp']<=0 or not isinstance(base['config'].get('feeConfig'),dict):raise ValueError('Explicit positive timestamp and fee config required')
    if base['config'].get('chainId')!=chain or public.get('genesisTimestamp')!=int(base['timestamp'],0):raise ValueError('Approved ChainID/timestamp mismatch')
    validate_address_plan(public)
    if public['manager'].get('subnetBytes32') not in (None,'0x'+subnet.hex()):raise ValueError('Conflicting SubnetID bytes')
    return subnet

def validate_address_plan(public):
    allowed={'publicAddressesReviewed','custodyProposalApproved','allocationAddresses','contracts','managerAddress','managerPredeploys','governanceProposer','emergencySigners','genesisTimestamp','custody','manager','managerSubnetId','validationPublicIdentity'}
    if set(public)-allowed:raise ValueError('Unknown public input fields forbidden')
    c=public['custody'];m=public['manager'];a=public['allocationAddresses'];core=public['contracts']
    if set(c)-{'mode','safeSingleton','protocolSafe','treasurySafe','protocolGuard','treasuryGuard','protocolOwners','treasuryOwners','stateSha256'} or set(m)-{'library','implementation','proxy','poa','proxyAdmin','validatorWeights','churnPeriodSeconds','maximumChurnPercentage','subnetBytes32'}:raise ValueError('Unknown custody/manager fields forbidden')
    if set(a)!=set(C00) or c.get('mode')!='safe-1.4.1-oz-5.6.1':raise ValueError('C00/pinned custody mode required')
    if m['proxy']!=public['managerAddress'] or c['protocolSafe']!=public['governanceProposer']:raise ValueError('Manager/proposer mismatch')
    code=[*core.values(),a['treasury'],*[c[k] for k in ('safeSingleton','protocolSafe','treasurySafe','protocolGuard','treasuryGuard')],*[m[k] for k in ('library','implementation','proxy','poa','proxyAdmin')]]
    owners=[*c['protocolOwners'],*c['treasuryOwners'],*public['emergencySigners']]
    if any(len(g)!=5 for g in (c['protocolOwners'],c['treasuryOwners'],public['emergencySigners'])):raise ValueError('Three5-owner groups required')
    ordinary=[v for k,v in a.items() if k not in ('treasury','rewards')]
    for address in code+owners+ordinary:
        if not isinstance(address,str) or not re.fullmatch('0x[0-9a-fA-F]{40}',address) or int(address,16)<=65535 or address.lower().startswith('0x020000000000000000000000000000000000'):raise ValueError('Explicit non-synthetic/non-precompile public address required')
    all_addresses=[v.lower() for v in code+owners+ordinary]
    if len(code)!=17 or len(set(all_addresses))!=len(all_addresses):raise ValueError('Code/signer/allocation collision')
    if a['rewards'].lower()!=core['rewardVault'].lower():raise ValueError('RewardVault allocation alias required')
    from check_decision_package import validate_weights
    validate_weights(m['validatorWeights'],m['maximumChurnPercentage'],m['churnPeriodSeconds'])
    if set(m['validatorWeights'])!={'validator-1','validator-2'}:raise ValueError('Two explicit weights required')
    return code+owners+ordinary

def normalize(raw):
    states={}
    for address,state in raw.items():
        address=address.lower()
        if address in states:raise ValueError('Normalized collision')
        v=json.loads(state) if isinstance(state,str) else state
        if isinstance(v.get('storage'),str):v['storage']=json.loads(v['storage'])
        states[address]=v
    return states

def verify_manager(states,manager,artifacts):
    names=dict(library='ValidatorMessages',implementation='ValidatorManager',proxy='TransparentUpgradeableProxy',poa='PoAManager',proxyAdmin='ProxyAdmin')
    for role,name in names.items():
        data=json.loads((artifacts/(name+'.sol')/(name+'.json')).read_text());s=data['metadata']['settings']
        if data['metadata']['compiler']['version']!='0.8.30+commit.73712a01' or s.get('optimizer')!={'enabled':True,'runs':200} or s.get('viaIR') is not True or s.get('evmVersion')!='shanghai':raise ValueError('Pinned compiler/settings differ')
        if role=='implementation' and list(s['libraries'].values())!=[manager['library'].lower()]:raise ValueError('Wrong library link')
        code=bytearray.fromhex(data['deployedBytecode']['object'][2:]);refs=data['deployedBytecode'].get('immutableReferences',{})
        binding=manager['proxy'] if role=='poa' else manager['proxyAdmin'] if role=='proxy' else None
        if role in ('poa','proxy') and len(refs)!=1:raise ValueError('Missing immutable metadata')
        if refs and binding is None:raise ValueError('Unexpected immutable')
        for ranges in refs.values():
            if binding is None:raise ValueError('Missing immutable binding')
            for r in ranges:code[r['start']:r['start']+r['length']]=int(binding,16).to_bytes(r['length'],'big')
        state=states[manager[role].lower()]
        if bytes.fromhex(state['code'][2:])!=code or int(state['balance'],0)!=0 or int(state['nonce'],0)!=(2 if role=='proxy' else 1):raise ValueError('Complete manager runtime/balance/nonce mismatch: '+role)

def verify_custody_complete(states,p,artifacts):
    names=dict(feeDistributor='FeeDistributor',feeVault='ValidatorFeeVault',registry='PrimeWaveValidatorRegistry',rewardVault='RewardVault')
    bindings=dict(feeDistributor=dict(validatorFeeVault=p['contracts']['feeVault'],treasury=p['allocationAddresses']['treasury']),feeVault=dict(protocolAdmin=p['contracts']['registry']),registry=dict(protocolAdmin=p['contracts']['timelock'],validatorManager=p['managerAddress'],feeVault=p['contracts']['feeVault']),rewardVault=dict(admin=p['contracts']['timelock']))
    scope=json.loads((ROOT/'docs/security-review/scope-evidence.json').read_text())
    def variables(node):
        found={}
        if isinstance(node,dict):
            if node.get('nodeType')=='VariableDeclaration' and node.get('mutability')=='immutable':found[str(node['id'])]=node['name']
            for v in node.values():found.update(variables(v))
        elif isinstance(node,list):
            for v in node:found.update(variables(v))
        return found
    for role,name in names.items():
        source='contracts/src/'+name+'.sol'
        if digest((ROOT/source).read_bytes())!=scope['sourceSha256'][source]:raise ValueError('Locked core source changed')
        data=json.loads((artifacts/(name+'.sol')/(name+'.json')).read_text())
        if not data.get('ast'):raise ValueError('AST immutable metadata required')
        ids=variables(data['ast']);code=bytearray.fromhex(data['deployedBytecode']['object'][2:])
        for key,ranges in data['deployedBytecode'].get('immutableReferences',{}).items():
            value=bindings[role][ids[key]]
            for r in ranges:code[r['start']:r['start']+r['length']]=int(value,16).to_bytes(r['length'],'big')
        if bytes.fromhex(states[p['contracts'][role].lower()]['code'][2:])!=code:raise ValueError('Full core runtime/immutable mismatch: '+role)

def export(args):
    rawp,p=read_public(args.public_inputs);rawb,base=read_public(args.base_genesis);rawr,receipt=read_public(args.accepted_subnet)
    _,review=read_public(args.input_review);_,decision=read_public(args.chain_decision);read_public(args.registry)
    chain=approved(decision,args.registry)
    subnet=validate_inputs(p,base,receipt,review,rawp,rawb,rawr,chain);verify()
    for address in validate_address_plan(p):
        if address[2:]!=address[2:].lower() and address[2:]!=address[2:].upper():
            checksum=subprocess.check_output([args.cast,'to-check-sum-address',address],text=True).strip()
            if checksum!=address:raise ValueError('Mixed-case EIP55 checksum mismatch')
    # Verify each extracted source against pinned archives before building anything.
    from run_combined_genesis_tests import ARCHIVES as pins
    import tarfile
    for name,(alg,h) in pins.items():verify_archive(args.archives/name,alg,h)
    specs=[('primewave-icm-pinned.tar.gz','ava-labs-icm-services-40e1c89/icm-contracts/','icm'),('openzeppelin-contracts-5.0.2.tgz','package/','oz'),('openzeppelin-contracts-upgradeable-5.0.2.tgz','package/','oz-upgradeable')]
    for name,prefix,target in specs:
        with tarfile.open(args.archives/name) as tar:
            for member in tar.getmembers():
                if member.isfile() and member.name.startswith(prefix) and member.name.endswith('.sol'):
                    rel=Path(member.name[len(prefix):]);content=tar.extractfile(member)
                    if rel.is_absolute() or '..' in rel.parts or content is None or (ROOT/'genesis-build/pinned-manager'/target/rel).read_bytes()!=content.read():raise ValueError('Pinned extracted source differs')
    work=args.output.resolve()
    if not work.is_relative_to((ROOT/'genesis-build').resolve()) or work.exists():raise ValueError('NEW directory under genesis-build required; never overwrite')
    work.mkdir(parents=True);copy_p=copy.deepcopy(p);copy_p['manager']['subnetBytes32']='0x'+subnet.hex()
    (work/'public.json').write_text(json.dumps(copy_p))
    env=dict(os.environ)
    for key in ('ETH_RPC_URL','FOUNDRY_ETH_RPC_URL','FOUNDRY_FORK_URL'):env.pop(key,None)
    env.update(GENESIS_PUBLIC_MANIFEST=str(work/'public.json'),GENESIS_STATE_OUTPUT=str(work/'custody.json'))
    subprocess.run([args.forge,'script','contracts/script/CustodyGenesisState.s.sol:CustodyGenesisState','--offline','--ast','--out',str(work/'custody-artifacts'),'--cache-path',str(work/'custody-cache')],cwd=ROOT,env=env,check=True)
    manager_artifacts=work/'manager-artifacts'
    env.update(MAINNET_AUTHOR_INPUT=str(work/'public.json'),MAINNET_MANAGER_OUTPUT=str(work/'manager.json'),MAINNET_LIBRARY_ARTIFACT=str(manager_artifacts/'ValidatorMessages.sol/ValidatorMessages.json'))
    cmd=[args.forge,'script','tools/mainnet-genesis/ManagerAuthor.s.sol:ManagerAuthor','--offline','--out',str(manager_artifacts),'--cache-path',str(work/'manager-cache')]
    for mapping in ('@openzeppelin/contracts@5.0.2/=genesis-build/pinned-manager/oz/','@openzeppelin/contracts-upgradeable@5.0.2/=genesis-build/pinned-manager/oz-upgradeable/','@utilities/=genesis-build/pinned-manager/icm/avalanche/utilities/','@subnet-evm/=genesis-build/pinned-manager/icm/avalanche/subnet-evm/'):
        cmd.extend(['--remappings',mapping])
    cmd.extend(['--libraries','genesis-build/pinned-manager/icm/avalanche/validator-manager/ValidatorMessages.sol:ValidatorMessages:'+p['manager']['library']])
    subprocess.run(cmd,cwd=ROOT,env=env,check=True)
    custody=normalize(json.loads((work/'custody.json').read_text()));manager=normalize(json.loads((work/'manager.json').read_text()))
    if set(custody)&set(manager) or len(custody)!=12 or len(manager)!=5:raise ValueError('Missing/duplicate predeploy accounts')
    verify_manager(manager,p['manager'],manager_artifacts)
    verify_custody_complete(custody,p,work/'custody-artifacts')
    # Derived hashes bind the NEW candidate; they never approve the resulting state.
    candidate_public=copy.deepcopy(p)
    if p.get('managerPredeploys') and p['managerPredeploys']!=manager:raise ValueError('Supplied manager state differs; no silent replacement')
    expected_hashes={a:digest(canonical(v)) for a,v in custody.items()}
    if p['custody'].get('stateSha256') and p['custody']['stateSha256']!=expected_hashes:raise ValueError('Supplied custody hashes differ')
    candidate_public['managerPredeploys']=manager
    candidate_public['custody']['stateSha256']={a:digest(canonical(v)) for a,v in custody.items()}
    result=materialize(candidate_public,custody,base)
    genesis_bytes=json.dumps(result['genesis'],sort_keys=True,indent=2).encode()+b'\n'
    (work/'genesis.json').write_bytes(genesis_bytes)
    candidate_public['publicAddressesReviewed']=False;candidate_public['custodyProposalApproved']=False
    construction=dict(public=candidate_public,exported=custody,base=base,inputAddressReview=review,acceptedSubnet=receipt,finalStateApproved=False)
    (work/'construction.review.json').write_text(json.dumps(construction,sort_keys=True,indent=2)+'\n')
    expectations=make_expectations(result['genesis'],p,receipt,digest(genesis_bytes),args.cast)
    (work/'vm-expectations.json').write_text(json.dumps(expectations,sort_keys=True,indent=2)+'\n')
    env.update(MAINNET_EXACT_GENESIS=str(work/'genesis.json'),MAINNET_EXACT_EXPECTATIONS=str(work/'vm-expectations.json'))
    subprocess.run([args.forge,'script','tools/mainnet-genesis/RestoreCheck.s.sol:RestoreCheck','--offline','--out',str(work/'restore-artifacts'),'--cache-path',str(work/'restore-cache')],cwd=ROOT,env=env,check=True)
    report=dict(status='OFFLINE_CANDIDATE_ONLY',genesisFileSha256=digest(genesis_bytes),genesisCanonicalSha256=result['genesisSha256'],productionApproved=False,signing=False,broadcast=False,finalVmAccepted=False,
        subnetId=receipt['subnetId'],chainId=chain,managerAddresses=p['manager'],authoringRestorationVerified=True,managerRepeatedExportMatches=True,
        artifactSha256={str(f.relative_to(work)):digest(f.read_bytes()) for folder in (work/'custody-artifacts',manager_artifacts) for f in sorted(folder.rglob('*.json')) if f.name in ('Safe.json','SafeProxy.json','PrimeWaveCustodyTimelock.json','TimelockOnlySafeGuard.json','PauseOnlyEmergencyMultisig.json','FeeDistributor.json','ValidatorFeeVault.json','RewardVault.json','PrimeWaveValidatorRegistry.json','ValidatorManager.json','PoAManager.json','TransparentUpgradeableProxy.json','ProxyAdmin.json','ValidatorMessages.json')},
        inputSha256=dict(public=digest(rawp),base=digest(rawb),acceptedSubnet=digest(rawr)),accounts={a:digest(canonical(s)) for a,s in result['genesis']['alloc'].items()})
    (work/'export.json').write_text(json.dumps(report,sort_keys=True,indent=2)+'\n');return report

def make_expectations(genesis,p,receipt,file_hash,cast):
    env=dict(os.environ)
    for k in ('ETH_RPC_URL','FOUNDRY_ETH_RPC_URL','FOUNDRY_FORK_URL'):env.pop(k,None)
    def calldata(signature,*args):return subprocess.check_output([cast,'calldata',signature,*args],env=env,text=True).strip()
    def word(value):return format(int(value,16) if isinstance(value,str) else value,'064x')
    calls=[]
    def check(to,signature,result,*args):calls.append(dict(to=to,data=calldata(signature,*args),expected='0x'+result))
    c=p['custody'];m=p['manager'];tl=p['contracts']['timelock'];tt=p['allocationAddresses']['treasury']
    for safe,owners in [(c['protocolSafe'],c['protocolOwners']),(c['treasurySafe'],c['treasuryOwners'])]:
        check(safe,'getThreshold()',word(3));check(safe,'nonce()',word(0));check(safe,'getOwners()',word(32)+word(5)+''.join(word(a) for a in owners))
    for clock,safe in [(tl,c['protocolSafe']),(tt,c['treasurySafe'])]:
        check(clock,'getMinDelay()',word(172800));check(clock,'hasRole(bytes32,address)',word(1),'0x'+'00'*32,clock)
        for role in ('PROPOSER_ROLE','EXECUTOR_ROLE','CANCELLER_ROLE'):
            role_hash=subprocess.check_output([cast,'keccak',role],env=env,text=True).strip();check(clock,'hasRole(bytes32,address)',word(1),role_hash,safe)
    for guard,safe,clock in [(c['protocolGuard'],c['protocolSafe'],tl),(c['treasuryGuard'],c['treasurySafe'],tt)]:
        check(guard,'safe()',word(safe));check(guard,'timelock()',word(clock))
    for target,owner in [(m['proxy'],m['poa']),(m['poa'],tl),(m['proxyAdmin'],tl)]:check(target,'owner()',word(owner))
    check(m['proxy'],'subnetID()',decode_id(receipt['subnetId']).hex());check(m['proxy'],'isValidatorSetInitialized()',word(0))
    check(m['proxy'],'getChurnTracker()',word(m['churnPeriodSeconds'])+word(m['maximumChurnPercentage'])+word(0)*4)
    check(p['contracts']['rewardVault'],'totalFunded()',word(15000000*UNIT))
    check(p['contracts']['rewardVault'],'admin()',word(tl))
    check(p['contracts']['registry'],'protocolAdmin()',word(tl))
    check(p['contracts']['registry'],'validatorManager()',word(m['proxy']))
    check(p['contracts']['registry'],'feeVault()',word(p['contracts']['feeVault']))
    check(p['contracts']['feeVault'],'protocolAdmin()',word(p['contracts']['registry']))
    check(p['contracts']['feeDistributor'],'treasury()',word(tt))
    check(p['contracts']['feeDistributor'],'validatorFeeVault()',word(p['contracts']['feeVault']))
    check(p['contracts']['emergency'],'governanceTimelock()',word(tl))
    for target in ('rewardVault','feeVault','feeDistributor'):
        check(p['contracts'][target],'pauseController()',word(p['contracts']['emergency']))
        check(p['contracts']['emergency'],'allowedTarget(address)',word(1),p['contracts'][target])
    for safe in (c['protocolSafe'],c['treasurySafe']):
        check(safe,'getModulesPaginated(address,uint256)',word(64)+word(1)+word(0),'0x'+'0'*39+'1','10')
    for clock in (tl,tt):
        for owner in [*c['protocolOwners'],*c['treasuryOwners'],*p['emergencySigners']]:check(clock,'hasRole(bytes32,address)',word(0),'0x'+'00'*32,owner)
    return dict(callCount=len(calls),schema='primewave-exact-genesis-v1',genesisFileSha256=file_hash,chainId=genesis['config']['chainId'],subnetId=receipt['subnetId'],accounts=genesis['alloc'],calls=calls,productionApproved=False,
        publicNodeIdentity=p.get('validationPublicIdentity'),note='Local validation context only; actual BlockchainID does not yet exist. No signing or conversion proof claimed.')

if __name__=='__main__':
    a=argparse.ArgumentParser(description=__doc__)
    for name in ('public-inputs','base-genesis','accepted-subnet','input-review','chain-decision','registry','archives','output'):a.add_argument('--'+name,type=Path,required=True)
    a.add_argument('--forge',default='forge');a.add_argument('--cast',default='cast')
    args=a.parse_args();print(json.dumps(export(args),indent=2))
