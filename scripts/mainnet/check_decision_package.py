#!/usr/bin/env python3
"""Offline proposal consistency only. Never approves, signs, broadcasts or uses AWS."""
import argparse
import hashlib
import json
from pathlib import Path
from chain_id import check_candidate


def validate_weights(weights, churn, period):
    if set(weights)!={'validator-1','validator-2'} or any(type(w) is not int or not 0<w<2**64 for w in weights.values()):
        raise ValueError('Two positive uint64 weights required')
    total=sum(weights.values())
    if total>=2**64 or type(churn) is not int or not 1<=churn<=20 or type(period) is not int or not 0<period<=86400:
        raise ValueError('Pinned manager weight/churn limits violated')
    if total*churn>=2**64:raise ValueError('Pinned manager uint64 initialization arithmetic would overflow')
    if total*churn<100:
        raise ValueError('Pinned manager initializeValidatorSet would reject total weight')
    return dict(totalWeight=total,initialChurnBudgetWeight=total*churn//100,
                sharesPercent={name:w*100/total for name,w in weights.items()})


def check(path):
    package=json.loads(path.read_text())
    if package.get('schema')!='primewave-mainnet-decisions-v1' or package.get('deploymentStrategy')!='DIRECT_MAINNET' or package.get('executionReady') is not False:
        raise ValueError('Unapproved DIRECT_MAINNET review package required')
    def no_approval(value):
        if isinstance(value,dict):
            for key,item in value.items():
                if (key.endswith('Approved') or key=='ownerApproved') and item is not False:
                    raise ValueError('Decision package must not authorize production: '+key)
                no_approval(item)
        elif isinstance(value,list):
            for item in value:no_approval(item)
    no_approval(package)
    if any(value is not False for value in package['productionApprovals'].values()):
        raise ValueError('Production approvals must remain false')
    chain=package['chainId'];relative=Path(chain['snapshotPath'])
    if relative.is_absolute() or '..' in relative.parts:raise ValueError('Package-local registry snapshot required')
    raw=(path.parent/relative).read_bytes()
    if hashlib.sha256(raw).hexdigest()!=chain['registrySha256']:raise ValueError('Registry snapshot digest mismatch')
    check_candidate(chain['candidate'],json.loads(raw))
    if chain['approvedChainId'] is not None or chain['globalUniquenessProven'] is not False or chain['liveRefreshPerformed'] is not False:
        raise ValueError('Offline evidence cannot authorize Chain ID or claim live/global verification')
    g=package['governance']
    if g['minimumTimelockSeconds']<172800:raise ValueError('C00 minimum48h timelock cannot be reduced')
    expected=dict(allocationPolicy='C00',nativeSupplyPW=100000000,nativeMinterEnabled=False,feeSplitBps=dict(validators=7000,treasury=2000,burn=1000))
    if package['economicsUnchanged']!=expected:raise ValueError('Locked supply/allocation/fee economics changed')
    for role,item in package['governance']['roles'].items():
        if 'proposedThreshold' in item:
            count=item['proposedSignerCount'];threshold=item['proposedThreshold']
            if type(count) is not int or count<3 or type(threshold) is not int or not 2<=threshold<=count or len(item['signerPublicAddresses'])!=count:
                raise ValueError('Explicit multisig threshold/composition required')
            if role=='emergencyMultisig' and (count,threshold)!=(5,3):raise ValueError('C00 emergency3-of-5 must remain unchanged')
        if item['publicAddress'] is not None or any(a is not None for a in item.get('signerPublicAddresses',[])):
            raise ValueError('Unresolved public addresses must not be fabricated in this package')
    v=package['validators'];weights=validate_weights(v['weights'],v['maximumChurnPercentage'],v['churnPeriodSeconds'])
    if package['bootstrap']['recommendedMode']!='subnet-bound-genesis' or not package['bootstrap']['uninitializedPublicProxyForbidden']:
        raise ValueError('Protected subnet-bound genesis recommendation required')
    return dict(status='REVIEW_PACKAGE_CONSISTENT',executionReady=False,ownerApproved=False,
                candidate=chain['candidate'],listedCollision=False,liveRegistryRefresh=False,
                registryRetrievedAt=chain['snapshotRetrievedAt'],weightAnalysis=weights,
                unresolved=['Chain ID choice and fresh pre-ceremony registry review','Public custody/signer addresses and implementation choices','Weights/churn risk decision','Actual accepted SubnetID, final artifacts and initialization proof','Every production approval remains separate and absent'])


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package',type=Path,default=Path(__file__).resolve().parents[2]/'config/mainnet/decisions/package.review.json')
    args=parser.parse_args()
    print(json.dumps(check(args.package),indent=2))
