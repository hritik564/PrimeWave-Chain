"""Pure offline checks for the optional, unapproved custody constructor export.

Runtime hashes pin published Safe and compiled policy adapters. State digests bind
reviewed exact constructor output; actual owner/role semantics must also pass the
Solidity round-trip and final genesis VM tests. Hashes alone are not an audit.
"""
import hashlib
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
MODE='safe-1.4.1-oz-5.6.1'


def canonical(value):return json.dumps(value,sort_keys=True,separators=(',',':')).encode()


def targets(public):
    c=public['custody']
    if c.get('mode')!=MODE:raise ValueError('Explicit pinned custody mode required')
    values=dict(treasuryTimelock=public['allocationAddresses']['treasury'],safeSingleton=c['safeSingleton'],protocolSafe=c['protocolSafe'],treasurySafe=c['treasurySafe'],protocolGuard=c['protocolGuard'],treasuryGuard=c['treasuryGuard'])
    import re
    if any(not isinstance(v,str) or not re.fullmatch(r'0x[0-9a-fA-F]{40}',v) or int(v,16)==0 for v in values.values()):raise ValueError('Unresolved custody public address')
    return values


def validate(public,states):
    lock=json.loads((ROOT/'config/mainnet/custody-artifacts.lock.json').read_text())
    c=public['custody'];extra=targets(public)
    addresses=list(extra.values())
    if len(set(a.lower() for a in addresses))!=6 or c['protocolSafe'].lower()!=public['governanceProposer'].lower():
        raise ValueError('Distinct treasury/Singleton/Safe roles and protocol proposer binding required')
    groups=[c['protocolOwners'],c['treasuryOwners'],public['emergencySigners']]
    import re
    for group in groups:
        if len(group)!=5 or len({a.lower() for a in group})!=5 or any(not re.fullmatch(r'0x[0-9a-fA-F]{40}',a) or int(a,16)==0 for a in group):
            raise ValueError('Exactly five distinct nonzero public owners per role required')
    if len(set(a.lower() for g in groups for a in g))!=15:raise ValueError('Signer role overlap forbidden')
    selected=dict(extra,protocolTimelock=public['contracts']['timelock'],emergency=public['contracts']['emergency'])
    for role,addr in selected.items():
        state=states[addr.lower()]
        artifact=('Safe' if role=='safeSingleton' else 'SafeProxy' if role.endswith('Safe') else 'TimelockOnlySafeGuard' if role.endswith('Guard') else 'PauseOnlyEmergencyMultisig' if role=='emergency' else 'PrimeWaveCustodyTimelock')
        if hashlib.sha256(bytes.fromhex(state['code'].removeprefix('0x'))).hexdigest()!=lock['artifacts'][artifact]['runtimeSha256']:
            raise ValueError('Pinned custody runtime mismatch: '+role)
        if hashlib.sha256(canonical(state)).hexdigest()!=c['stateSha256'].get(addr.lower()):
            raise ValueError('Exact reviewed custody constructor state differs: '+role)
        balance=15_000_000*10**18 if role=='treasuryTimelock' else 0
        if int(state['balance'],0)!=balance or int(state.get('nonce','0x0'),0)!=1 or not state.get('storage'):raise ValueError('Custody balance/initial storage mismatch')
    def slot(addr,key):return int(states[addr.lower()]['storage'].get('0x'+format(key,'064x'),'0x0'),16)
    for role in ('protocolSafe','treasurySafe'):
        if slot(c[role],0)!=int(c['safeSingleton'],16) or slot(c[role],3)!=5 or slot(c[role],4)!=3 or slot(c[role],5)!=0:
            raise ValueError('Safe singleton/owner count/threshold/nonce mismatch')
    guard_slot=int('4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8',16)
    for role,guard,clock in [('protocolSafe','protocolGuard',public['contracts']['timelock']),('treasurySafe','treasuryGuard',public['allocationAddresses']['treasury'])]:
        if slot(c[role],guard_slot)!=int(c[guard],16) or slot(c[guard],0)!=int(c[role],16) or slot(c[guard],1)!=int(clock,16):raise ValueError('Safe guard/timelock binding mismatch')
    if slot(c['safeSingleton'],4)!=1:raise ValueError('Safe singleton must be locked against setup')
    return extra
