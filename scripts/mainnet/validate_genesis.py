#!/usr/bin/env python3
"""Strict offline production genesis validation; no RPC, signing or broadcast."""
import argparse
import json
from pathlib import Path
from chain_id import approved

SUPPLY = 100_000_000*10**18


def validate(genesis, chain_id, policy, addresses):
    config = genesis['config']
    if config.get('chainId') != chain_id:
        raise ValueError('Genesis/approved Chain ID mismatch')
    if 'contractNativeMinterConfig' in config and config['contractNativeMinterConfig'] is not None:
        raise ValueError('NativeMinter must remain absent or null')
    if any('minter' in k.lower() and v is not None for k,v in config.items()):
        raise ValueError('Unexpected mint precompile')
    if policy.get('rewards') != 15_000_000 or any(type(v) is not int or v < 0 for v in policy.values()):
        raise ValueError('Preserve uncontested15M rewards and integer allocations')
    if sum(policy.values()) != 100_000_000 or set(addresses) != set(policy):
        raise ValueError('Approved allocation manifest incomplete')
    import re
    values = list(addresses.values())
    if len(set(a.lower() for a in values)) != len(values) or any(
        not re.fullmatch(r'0x[0-9a-fA-F]{40}',a) or int(a,16)==0 for a in values):
        raise ValueError('Unique nonzero production allocation addresses required')
    alloc = genesis['alloc']
    if {a.lower().removeprefix('0x') for a in alloc} != {a.lower()[2:] for a in values}:
        raise ValueError('Unapproved allocation entries')
    normalized = {a.lower().removeprefix('0x'):v for a,v in alloc.items()}
    for role,amount in policy.items():
        if int(normalized[addresses[role].lower()[2:]]['balance'],0) != amount*10**18:
            raise ValueError('Genesis allocation differs from approved policy')
    if sum(int(v['balance'],0) for v in alloc.values()) != SUPPLY:
        raise ValueError('Genesis total differs from locked100M PW')
    reward = config['rewardManagerConfig']['initialRewardConfig']['rewardAddress']
    if not re.fullmatch(r'0x[0-9a-fA-F]{40}',reward) or int(reward,16)==0:
        raise ValueError('Reviewed FeeDistributor address required')
    if genesis.get('gasLimit') is None or config.get('feeConfig') is None:
        raise ValueError('Reviewed gas parameters required')
    # Do not fake VM validation: bytecode, fork schedule, fee routing and manager
    # initialization need a separate rehearsal with the pinned unmodified VM.
    return {'supplyWei':str(SUPPLY),'chainId':chain_id,'scope':'allocation validation only; VM/genesis rehearsal still required'}


if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--genesis',type=Path,required=True)
    p.add_argument('--chain-approval',type=Path,required=True)
    p.add_argument('--registry',type=Path,required=True)
    p.add_argument('--allocation-decision',type=Path,required=True)
    a=p.parse_args()
    decision=json.loads(a.allocation_decision.read_text())
    if decision.get('ownerApproved') is not True:
        raise SystemExit('Allocation decision requires owner approval')
    chain=approved(json.loads(a.chain_approval.read_text()),a.registry)
    print(json.dumps(validate(json.loads(a.genesis.read_text()),chain,decision['allocationsPW'],decision['addresses']),indent=2))
