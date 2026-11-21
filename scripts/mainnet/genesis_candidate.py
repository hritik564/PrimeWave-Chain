#!/usr/bin/env python3
"""Deterministic C00 genesis candidate compiler. Never authorizes/broadcasts genesis."""
import argparse
import copy
import hashlib
import json
from pathlib import Path

C00={'liquidity':40000000,'treasury':15000000,'team':10000000,'rewards':15000000,'presale1':5000000,'presale2':7500000,'presale3':7500000}
UNIT=10**18
CONTRACTS=('timelock','emergency','feeVault','feeDistributor','registry','rewardVault')


def canonical(data):
    return json.dumps(data,sort_keys=True,separators=(',',':')).encode()


def proposal():
    return {
        'schema':'primewave-c00-genesis-candidate-v1','deployable':False,
        'allocationPolicyApproved':True,'allocationPolicy':'C00','genesisApproved':False,
        'chainIdCandidate':73571001,'chainIdApproved':False,
        'nativeSupplyWei':str(100000000*UNIT),'nativeMinterEnabled':False,
        'feeSplitBps':{'validators':7000,'treasury':2000,'burn':1000},
        'allocations':[{'role':role,'pw':amount,'wei':str(amount*UNIT),'address':None} for role,amount in C00.items()],
        'rewardCustodyProposal':{'mode':'genesis-predeploy-constructor-accounting','ownerApproved':False,
            'balanceWei':str(15000000*UNIT),'totalFundedWei':str(15000000*UNIT),
            'totalEmittedWei':'0','totalClaimedWei':'0','adminAddress':None,
            'mechanism':'Export existing RewardVault constructor + fund() state from authoring EVM; seed exactly15M once at final RewardVault address. No funding EOA allocation or post-launch funding transaction.'},
        'feeCustodyProposal':'Predeploy existing FeeDistributor;20% goes directly to the reviewed treasury multisig/timelock address, not the non-withdrawable DevTreasury fixture.',
        'requiredOwnerInputs':['Seven allocation recipient addresses; rewards must be RewardVault contract',
             'Six protocol contract addresses, fresh PoA manager proxy/implementation state and five emergency signer PUBLIC addresses',
             'Governance proposer/public custody verification and approval of complete constructor-state predeploy bundle',
             'Final Chain ID, genesis timestamp, fee/fork/Warp configuration approval',
             'Operational gas spending authority within existing C00 allocations; no extra allocation created'],
        'productionAddressesFabricated':False}


def materialize(public, exported, base):
    if public.get('publicAddressesReviewed') is not True or public.get('custodyProposalApproved') is not True:
        raise ValueError('Public addresses and constructor-state custody proposal require review')
    addresses=public['allocationAddresses'];targets=public['contracts']
    if set(addresses)!=set(C00) or set(targets)!=set(CONTRACTS):
        raise ValueError('Complete C00 allocation and contract roles required')
    import re
    for value in [*addresses.values(),*targets.values(),public['managerAddress'],public['governanceProposer'],*public['emergencySigners']]:
        if not isinstance(value,str) or not re.fullmatch(r'0x[0-9a-fA-F]{40}',value) or int(value,16)==0:
            raise ValueError('Unresolved or invalid public address')
    if len(set(a.lower() for a in targets.values()))!=len(CONTRACTS) or len(set(a.lower() for a in addresses.values()))!=7:
        raise ValueError('Contract/allocation addresses must be distinct within their roles')
    if addresses['rewards'].lower()!=targets['rewardVault'].lower():
        raise ValueError('Rewards must go directly to the initialized RewardVault')
    if set(a.lower() for role,a in addresses.items() if role!='rewards') & set(a.lower() for a in targets.values()):
        raise ValueError('Only rewards may overlap a protocol predeploy allocation')
    states={a.lower():json.loads(v) if isinstance(v,str) else v for a,v in exported.items()}
    if set(states)!=set(a.lower() for a in targets.values()):
        raise ValueError('Constructor state roles/addresses differ')
    from chain_id import DENIED
    chain_id=base.get('config',{}).get('chainId')
    if type(chain_id) is not int or not 1000<=chain_id<=2**53-1 or chain_id in DENIED:
        raise ValueError('Production candidate must use a distinct non-demo Chain ID')
    stamp=base.get('timestamp')
    if not isinstance(stamp,str) or int(stamp,0)<=0 or public.get('genesisTimestamp')!=int(stamp,0):
        raise ValueError('Explicit matching genesis timestamp required for constructor initialization')
    genesis=copy.deepcopy(base)
    genesis['alloc']={}
    for role,amount in C00.items():
        genesis['alloc'][addresses[role].lower()]={'balance':hex(amount*UNIT)}
    for role,address in targets.items():
        state=copy.deepcopy(states[address.lower()])
        if isinstance(state.get('storage'),str):state['storage']=json.loads(state['storage'])
        expected=15000000*UNIT if role=='rewardVault' else 0
        if int(state['balance'],0)!=expected or not state.get('code') or not state.get('storage') and role in ('rewardVault','timelock','emergency'):
            raise ValueError('Constructor initialization or balance missing')
        state['balance']=hex(expected)
        genesis['alloc'][address.lower()]=state
    layout=json.loads((Path(__file__).resolve().parents[2]/'config/mainnet/reward-vault-layout.json').read_text())
    source=Path(__file__).resolve().parents[2]/'contracts/src/RewardVault.sol'
    if hashlib.sha256(source.read_bytes()).hexdigest()!=layout['sourceSha256']:
        raise ValueError('RewardVault source/layout changed; regenerate and review')
    reward_storage=genesis['alloc'][targets['rewardVault'].lower()]['storage']
    for label,expected in (('totalFunded',15000000*UNIT),('totalEmitted',0),('totalClaimed',0),('lastUpdateTime',int(stamp,0))):
        slot='0x'+format(layout['slots'][label],'064x')
        if int(reward_storage.get(slot,'0x0'),16)!=expected:
            raise ValueError('RewardVault genesis accounting mismatch: '+label)
    for address,state in public.get('managerPredeploys',{}).items():
        address=address.lower()
        if address in genesis['alloc'] or int(state.get('balance','0x0'),0)!=0 or not state.get('code'):
            raise ValueError('Manager state must add only reviewed zero-balance code accounts')
        genesis['alloc'][address]=state
    proxy=public['managerAddress'].lower()
    if proxy not in genesis['alloc'] or not genesis['alloc'][proxy].get('code'):
        raise ValueError('Reviewed manager proxy state required')
    reward=genesis['config'].get('rewardManagerConfig',{}).get('initialRewardConfig',{}).get('rewardAddress','')
    if reward.lower()!=targets['feeDistributor'].lower():
        raise ValueError('Fee routing must target the predeployed FeeDistributor')
    if sum(int(a.get('balance','0x0'),0) for a in genesis['alloc'].values())!=100000000*UNIT:
        raise ValueError('Genesis supply differs from100M PW')
    from validate_genesis import validate
    predeploys={a:hashlib.sha256(canonical(v)).hexdigest() for a,v in genesis['alloc'].items() if v.get('code') or v.get('storage')}
    validate(genesis,genesis['config']['chainId'],C00,addresses,predeploys)
    return {'deployable':False,'genesisApproved':False,'chainIdApproved':False,
            'genesisSha256':hashlib.sha256(canonical(genesis)).hexdigest(),'genesis':genesis,
            'predeployAllocationDigests':predeploys,'scope':'structural candidate; constructor round-trip and VM tests are separate evidence, final owner ceremony approval mandatory'}


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--public-manifest',type=Path);p.add_argument('--constructor-state',type=Path);p.add_argument('--base-genesis',type=Path)
    a=p.parse_args()
    if any((a.public_manifest,a.constructor_state,a.base_genesis)):
        if not all((a.public_manifest,a.constructor_state,a.base_genesis)):p.error('All three input files required')
        result=materialize(json.loads(a.public_manifest.read_text()),json.loads(a.constructor_state.read_text()),json.loads(a.base_genesis.read_text()))
    else:result=proposal()
    print(json.dumps(result,sort_keys=True,indent=2))
