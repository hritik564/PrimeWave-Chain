#!/usr/bin/env python3
"""Prepare a Fuji ceremony checklist from public inputs. No broadcast code."""
import argparse
import json
from pathlib import Path


def sequence(manager, identities):
    if manager.get('environment') != 'fuji' or manager.get('broadcastApproved') is not False:
        raise ValueError('Only an unbroadcast Fuji rehearsal plan is accepted')
    if len(identities) < 2:
        raise ValueError('At least two fresh Fuji test identity records required')
    seen=set()
    for item in identities:
        if item.get('environment') != 'fuji' or item.get('freshTestIdentity') is not True:
            raise ValueError('Never reuse demo or production identities for rehearsal')
        node=item.get('nodeId')
        if not isinstance(node,str) or not node.startswith('NodeID-') or node in seen:
            raise ValueError('Distinct Fuji NodeIDs required')
        seen.add(node)
        if not item.get('blsPublicKey') or not item.get('proofOfPossession'):
            raise ValueError('Public BLS key and proof required; no private keys accepted')
        if any('private' in k.lower() or 'secret' in k.lower() or 'mnemonic' in k.lower() for k in item):
            raise ValueError('Public identity records only')
    return {'network':'fuji','networkId':5,'broadcasts':0,'keyAccess':False,
            'steps':[
                'Verify pinned upstream node/plugin checksums and protocol46; never overwrite local-bin or pw-demo-04',
                'On separately approved rehearsal hosts generate fresh Fuji-only TLS/BLS identities under operator custody; export public NodeID/BLS/PoP only',
                'Validate distinct approved EVM Chain ID, gas/fork/Warp genesis and allocation manifests against unmodified v1.15.1 VM',
                'Review pinned official Avalanche Deploy create-l1 tool and manager artifact; input a reviewed genesis, public validator records and an operator-controlled Fuji signer',
                'STOP: obtain explicit host-start, faucet funding and P-Chain broadcast authorization',
                'After approval only: sync Fuji P-Chain with sybil protection and partial-sync enabled; verify P:OK',
                'After approval only: CreateSubnetTx -> CreateChainTx -> ConvertSubnetToL1Tx; retain all resulting IDs and receipts',
                'After approval only: initialize the reviewed PoA validator manager using conversion data; RegisterL1ValidatorTx only for later additions',
                'Verify public node identities, platform.getBlockchains/getCurrentValidators, four Ethereum RPC calls, peer connectivity, restart persistence and restricted public API access'
            ],'blockedUntil': ['reviewed manager implementation/proxy artifacts and initialization parameters',
                              'VM/genesis rehearsal','funded Fuji signer','fresh identities and host access','explicit broadcast approval']}


if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--manager',type=Path,required=True)
    p.add_argument('--public-identities',type=Path,required=True)
    a=p.parse_args()
    print(json.dumps(sequence(json.loads(a.manager.read_text()),json.loads(a.public_identities.read_text())),indent=2))
