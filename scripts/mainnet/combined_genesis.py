#!/usr/bin/env python3
"""Build/check combined SYNTHETIC evidence only; never a production approval path."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
from genesis_candidate import materialize,canonical
ROOT=Path(__file__).resolve().parents[2]
ADDR=lambda n:'0x'+format(n,'040x')
PLAN=dict(validatorMessages=ADDR(0xE100),implementation=ADDR(0xE101),poa=ADDR(0xE102),proxy=ADDR(0xB007),proxyAdmin='0x06e614cf6f9fef1f37f083e0a5abc5b4b4fd67cc')
MANAGER_NAMES=dict(validatorMessages='ValidatorMessages',implementation='ValidatorManager',poa='PoAManager',proxy='TransparentUpgradeableProxy',proxyAdmin='ProxyAdmin')

def normalize(raw):
    states={}
    for address,state in raw.items():
        address=address.lower()
        if address in states:raise ValueError('Normalized address collision')
        value=json.loads(state) if isinstance(state,str) else copy.deepcopy(state)
        if isinstance(value.get('storage'),str):value['storage']=json.loads(value['storage'])
        states[address]=value
    return states

def validate(fixture):
    if fixture.get('syntheticTestOnly') is not True or fixture.get('productionApproved') is not False:raise ValueError('Synthetic/unapproved labels required')
    original=json.loads((ROOT/'tests/fixtures/custody-genesis.fixture.json').read_text())
    states=normalize(fixture['accounts']);public=fixture['publicManifest']
    expected=set(original['accounts'])|set(PLAN.values())
    if len(expected)!=17 or set(states)!=expected:raise ValueError('Exact 17 code accounts required, including generated ProxyAdmin')
    for address,state in original['accounts'].items():
        if canonical(states[address])!=canonical(state):raise ValueError('Locked custody state/runtime changed: '+address)
    if fixture['syntheticAddressPlan']!=PLAN:raise ValueError('Synthetic address plan differs')
    for role,address in PLAN.items():
        state=states[address]
        if int(state['balance'],0)!=0 or int(state['nonce'],0)!=(2 if role=='proxy' else 1):raise ValueError('Manager balance/account nonce mismatch')
        evidence=fixture['managerRuntimeEvidence'][role]
        if hashlib.sha256(bytes.fromhex(state['code'][2:])).hexdigest()!=evidence['runtimeSha256']:raise ValueError('Manager runtime changed')
        if hashlib.sha256(canonical(state)).hexdigest()!=evidence['stateSha256']:raise ValueError('Manager initialized state changed')
    if public['managerPredeploys']!={a:states[a] for a in PLAN.values()}:raise ValueError('Manager account set mismatch')
    if public['managerAddress']!=PLAN['proxy']:raise ValueError('Registry manager binding mismatch')
    return materialize(public,{a:states[a] for a in original['accounts']},fixture['base'])

def build():
    original=json.loads((ROOT/'tests/fixtures/custody-genesis.fixture.json').read_text())
    states=normalize(json.loads((ROOT/'genesis-build/combined-synthetic.raw.json').read_text()))
    admin=json.loads((ROOT/'genesis-build/combined-synthetic.admin.json').read_text())['proxyAdmin'].lower()
    if admin!=PLAN['proxyAdmin']:raise ValueError('ProxyAdmin derivation differs from synthetic plan')
    # Keep byte-for-byte locked custody states, including nonce representation.
    for address,state in original['accounts'].items():
        actual=copy.deepcopy(states[address]);actual['nonce']=hex(int(actual['nonce'],0))
        if actual!=state:raise ValueError('Combined custody export differs: '+address)
        states[address]=copy.deepcopy(state)
    runtimes={}
    out=ROOT/'genesis-build/combined-synthetic-build/artifacts'
    for role,name in MANAGER_NAMES.items():
        data=json.loads((out/(name+'.sol')/(name+'.json')).read_text())
        expected=bytearray.fromhex(data['deployedBytecode']['object'].removeprefix('0x'))
        refs=data['deployedBytecode'].get('immutableReferences',{})
        binding=PLAN['proxy'] if role=='poa' else PLAN['proxyAdmin'] if role=='proxy' else None
        if refs and not binding:raise ValueError('Unexpected runtime immutable')
        if role in ('poa','proxy') and len(refs)!=1:raise ValueError('Expected single immutable binding')
        for slots in refs.values():
            if binding is None:raise ValueError('Missing immutable binding')
            for slot in slots:
                expected[slot['start']:slot['start']+slot['length']]=int(binding,16).to_bytes(slot['length'],'big')
        actual=bytes.fromhex(states[PLAN[role]]['code'].removeprefix('0x'))
        if actual!=expected:raise ValueError('Complete runtime does not match exact artifact+immutable binding: '+role)
        settings=data['metadata']['settings']
        if data['metadata']['compiler']['version']!='0.8.30+commit.73712a01' or settings.get('optimizer')!={'enabled':True,'runs':200} or settings.get('viaIR') is not True or settings.get('evmVersion')!='shanghai':raise ValueError('Exact pinned compiler/settings required')
        if role=='implementation':
            libraries=settings['libraries']
            if list(libraries.values())!=[PLAN['validatorMessages']]:raise ValueError('Wrong linked library')
        runtimes[role]=dict(runtimeSha256=hashlib.sha256(actual).hexdigest(),stateSha256=hashlib.sha256(canonical(states[PLAN[role]])).hexdigest(),
            immutableReferences=refs,immutableBinding=binding,compiler=data['metadata']['compiler'],compilerSettings=settings,
            creationSha256=hashlib.sha256(bytes.fromhex(data['bytecode']['object'].removeprefix('0x'))).hexdigest(),
            fullRuntimeMatchesArtifact=True)
    public=copy.deepcopy(original['publicManifest']);public['managerPredeploys']={a:states[a] for a in PLAN.values()}
    fixture=dict(syntheticTestOnly=True,productionApproved=False,executionApproved=False,syntheticAddressPlan=PLAN,accounts=states,
        publicManifest=public,base=original['base'],managerRuntimeEvidence=runtimes,
        limitations=['Synthetic SubnetID bytes32(123); validator set conversion not initialized','No real signing/Warp/P-Chain/consensus/target VM proof','Owner review flags within publicManifest are synthetic harness inputs, never production consent'])
    candidate=validate(fixture)
    return fixture,candidate

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--write',action='store_true');a=parser.parse_args()
    fixture,candidate=build()
    for path,value in [('tests/fixtures/combined-genesis.fixture.json',fixture),('docs/security-review/combined-synthetic-genesis.candidate.json',candidate)]:
        encoded=json.dumps(value,sort_keys=True,indent=2)+'\n';target=ROOT/path
        if a.write:
            with target.open('x') as f:f.write(encoded)
        elif target.read_text()!=encoded:raise ValueError('Combined evidence differs: '+path)
    print(json.dumps(dict(status='SYNTHETIC_COMBINED_VERIFIED',codeAccounts=17,allocationAccounts=len(candidate['genesis']['alloc']),genesisSha256=candidate['genesisSha256'],productionApproved=False)))
