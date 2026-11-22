#!/usr/bin/env python3
"""Bind an offline constructor export to a NEW UNAPPROVED public review copy."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
from custody_genesis import canonical, targets

def prepare(public,exported):
    result=copy.deepcopy(public);targets(result)
    states={a.lower():json.loads(v) if isinstance(v,str) else v for a,v in exported.items()}
    if len(states)!=len(exported):raise ValueError('Duplicate normalized export account')
    for state in states.values():
        if isinstance(state.get('storage'),str):state['storage']=json.loads(state['storage'])
    result['custody']['stateSha256']={a:hashlib.sha256(canonical(v)).hexdigest() for a,v in states.items()}
    result['publicAddressesReviewed']=False;result['custodyProposalApproved']=False
    return result

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--public-manifest',type=Path,required=True);p.add_argument('--states',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();value=prepare(json.loads(a.public_manifest.read_text()),json.loads(a.states.read_text()))
    with a.output.open('x') as f:f.write(json.dumps(value,sort_keys=True,indent=2)+'\n')
