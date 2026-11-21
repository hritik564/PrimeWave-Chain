#!/usr/bin/env python3
"""Offline EIP155 registry collision/approval gate. No network or transactions."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path

DENIED = {1,5,77,1337,31337,73571,43113,43114}


def check_candidate(candidate, registry):
    if type(candidate) is not int or not 1000 <= candidate <= 2**53-1 or candidate in DENIED:
        raise ValueError('Invalid, reserved or existing project Chain ID')
    if not isinstance(registry,list) or not registry or any(type(r.get('chainId')) is not int for r in registry):
        raise ValueError('Invalid/empty chain registry snapshot')
    if candidate in {r['chainId'] for r in registry}:
        raise ValueError('Chain ID collision in registry')


def evidence(candidate, snapshot):
    raw = snapshot.read_bytes()
    check_candidate(candidate,json.loads(raw))
    return dict(candidate=candidate,ownerApproved=False,approvedChainId=None,
                registrySource='https://chainid.network/chains.json',
                registrySha256=hashlib.sha256(raw).hexdigest(),
                checkedAt=datetime.now(timezone.utc).isoformat(),
                note='Snapshot absence is not a reservation or proof that no unlisted chain uses this ID; recheck within 24h before ceremony.')


def approved(decision, snapshot):
    check_candidate(decision.get('candidate'),json.loads(snapshot.read_bytes()))
    if decision.get('registrySha256') != hashlib.sha256(snapshot.read_bytes()).hexdigest():
        raise ValueError('Registry evidence digest differs')
    checked = datetime.fromisoformat(decision['checkedAt'])
    age = (datetime.now(timezone.utc)-checked).total_seconds()
    if not 0 <= age <= 86400:
        raise ValueError('Chain registry check must be refreshed within 24h')
    if decision.get('ownerApproved') is not True or decision.get('approvedChainId') != decision['candidate']:
        raise ValueError('Explicit owner approval of the exact candidate required')
    return decision['candidate']


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--registry',type=Path,required=True)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--candidate',type=int)
    group.add_argument('--verify-approval',type=Path)
    args = parser.parse_args()
    if args.verify_approval:
        print(approved(json.loads(args.verify_approval.read_text()),args.registry))
    else:
        print(json.dumps(evidence(args.candidate,args.registry),indent=2))
