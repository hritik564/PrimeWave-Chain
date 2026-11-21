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


TOOL_COMMIT='5989dd8a057f0c074b7fd6a656fb401b0222951c'
TOOL_SOURCE='https://github.com/ava-labs/avalanche-deploy'


def prepare_bundle(manager, identities, genesis, allocation, decision, registry, genesis_path):
    """Validate public inputs and render argv only. This function cannot execute it."""
    import hashlib
    import re
    from urllib.parse import urlsplit
    from decimal import Decimal
    from chain_id import approved, check_candidate
    from validate_genesis import validate
    plan=sequence(manager,identities)
    if manager.get('ownerApproved') is not True or allocation.get('ownerApproved') is not True:
        raise ValueError('Explicit manager/genesis and allocation owner approvals required')
    chain=approved(decision,registry)
    if manager.get('evmChainId') != chain or type(manager.get('productionChainId')) is not int or chain == manager['productionChainId']:
        raise ValueError('Approved distinct Fuji and production Chain IDs required')
    check_candidate(manager['productionChainId'],json.loads(registry.read_bytes()))
    if not re.fullmatch(r'[0-9a-fA-F]{64}',manager.get('managerArtifactSha256') or '') or any(
            manager.get(flag) is not True for flag in ('managerInitializationReviewed','managerBootstrapReviewed','genesisForksReviewed','fundingPlanReviewed')):
        raise ValueError('Reviewed manager artifacts, protected bootstrap, initialization, fork schedule and funding plan required')
    validate(genesis,chain,allocation['allocationsPW'],allocation['addresses'],allocation.get('predeploys'))
    proxy=manager.get('managerAddress','')
    if not re.fullmatch(r'0x[0-9a-fA-F]{40}',proxy) or int(proxy,16)==0:
        raise ValueError('Explicit reviewed Fuji manager proxy address required')
    entry=next((value for address,value in genesis['alloc'].items() if address.lower().removeprefix('0x')==proxy[2:].lower()),None)
    if not entry or not entry.get('code') or proxy.lower().removeprefix('0x') not in {
            a.lower().removeprefix('0x') for a in allocation.get('predeploys',{})}:
        raise ValueError('Manager proxy must have reviewed predeploy code/storage in this rehearsal mode')
    endpoints=manager.get('validatorRpcEndpoints',[])
    if len(endpoints)!=len(identities) or len(set(endpoints))!=len(endpoints):
        raise ValueError('One distinct private/tunneled RPC endpoint per Fuji validator required')
    for endpoint in endpoints:
        url=urlsplit(endpoint)
        if url.scheme!='http' or url.hostname!='127.0.0.1' or not url.port or url.username or url.password or url.query or url.fragment or url.path not in ('','/'):
            raise ValueError('Use explicit loopback SSH tunnels; never expose9650 publicly')
    aggregator=manager.get('signatureAggregatorUrl','')
    url=urlsplit(aggregator)
    if url.scheme!='http' or url.hostname!='127.0.0.1' or not url.port or url.username or url.password or url.query or url.fragment or url.path not in ('','/'):
        raise ValueError('Explicit owner-operated loopback signature aggregator required; no Glacier fallback')
    alias=manager.get('fujiKeystoreAlias','')
    if not re.fullmatch(r'pw-fuji-[A-Za-z0-9_-]+',alias):
        raise ValueError('Explicit disposable Fuji-only keystore alias required')
    budget=manager.get('validatorBalanceAVAX')
    if not isinstance(budget,str) or not re.fullmatch(r'[0-9]+(?:\.[0-9]{1,9})?',budget) or Decimal(budget)<=0:
        raise ValueError('Explicit owner-approved Fuji AVAX validator budget required')
    plan.update(sourceTool={'repository':TOOL_SOURCE,'commit':TOOL_COMMIT},
        genesisSha256=hashlib.sha256(json.dumps(genesis,sort_keys=True,separators=(',',':')).encode()).hexdigest(),
        evmChainId=chain,readyForOwnerReview=True,broadcastReady=False,broadcasts=0,
        argvAfterSeparateBroadcastApproval=['./tools/create-l1/create-l1','--network=fuji','--key-name='+alias,
            '--validators='+','.join(endpoints),'--genesis='+str(genesis_path),
            '--chain-name=primewave-fuji-rehearsal','--genesis-proxy-address='+proxy,
            '--manager-type=poa','--validator-balance='+budget,'--local-sig-agg','--sig-agg-url='+aggregator,
            '--output=fuji-rehearsal.env','--json'],
        mandatoryPostConversion=['Retain subnet/chain/conversion IDs and receipts',
            'Initialize reviewed manager implementation/proxy and initializeValidatorSet using conversion data and authorized Fuji signer',
            'Verify manager ownership and validator set; a successful create-l1 exit alone is not rehearsal success'],
        warning='Rendered argv only; never run before explicit funding, host-start and broadcast approvals. Do not add --deploy-validator-manager or raw-key flags.')
    return plan


if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--manager',type=Path,required=True)
    p.add_argument('--public-identities',type=Path,required=True)
    p.add_argument('--prepare-bundle',action='store_true')
    for name in ('genesis','allocation-decision','chain-approval','registry'):
        p.add_argument('--'+name,type=Path)
    a=p.parse_args()
    manager=json.loads(a.manager.read_text()); identities=json.loads(a.public_identities.read_text())
    if a.prepare_bundle:
        if not all((a.genesis,a.allocation_decision,a.chain_approval,a.registry)):
            p.error('--prepare-bundle requires genesis, allocation-decision, chain-approval and registry')
        result=prepare_bundle(manager,identities,json.loads(a.genesis.read_text()),
            json.loads(a.allocation_decision.read_text()),json.loads(a.chain_approval.read_text()),a.registry,a.genesis.absolute())
    else:
        result=sequence(manager,identities)
    print(json.dumps(result,indent=2))
