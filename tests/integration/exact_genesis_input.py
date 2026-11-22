#!/usr/bin/env python3
"""EXPLICIT SYNTHETIC input for exact-byte importer tests, never production.
Reuses committed combined states; no keys, signing, identities or state export.
Only this fixture builder supplies test fork settings; the importer never does.
"""
import copy
import hashlib
import json
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts/mainnet'))
from export_mainnet_genesis import make_expectations,B58

def cb58(raw):
    data=raw+hashlib.sha256(raw).digest()[-4:];n=int.from_bytes(data,'big');out=''
    while n:n,r=divmod(n,58);out=B58[r]+out
    return '1'*(len(data)-len(data.lstrip(b'\0')))+out

def build(output,cast):
    output.mkdir(parents=True,exist_ok=False)
    fixture=json.loads((ROOT/'tests/fixtures/combined-genesis.fixture.json').read_text())
    candidate=json.loads((ROOT/'docs/security-review/combined-synthetic-genesis.candidate.json').read_text())
    g=copy.deepcopy(candidate['genesis']);cfg=g['config']
    cfg.update({k:0 for k in ('homesteadBlock','eip150Block','eip155Block','eip158Block','byzantiumBlock','constantinopleBlock','petersburgBlock','istanbulBlock','muirGlacierBlock','subnetEVMTimestamp','durangoTimestamp','etnaTimestamp','fortunaTimestamp','graniteTimestamp')})
    cfg['feeConfig']=dict(gasLimit=15000000,targetBlockRate=2,minBaseFee=1000000000,targetGas=10000000,baseFeeChangeDenominator=36,minBlockGasCost=0,maxBlockGasCost=1000000,blockGasCostStep=200000)
    cfg['rewardManagerConfig']['blockTimestamp']=0
    g.update(difficulty='0x0',nonce='0x0',extraData='0x')
    raw=json.dumps(g,sort_keys=True,indent=2).encode()+b'\n';(output/'genesis.json').write_bytes(raw)
    p=copy.deepcopy(fixture['publicManifest']);plan=fixture['syntheticAddressPlan'];p['manager']=dict(library=plan['validatorMessages'],implementation=plan['implementation'],poa=plan['poa'],proxy=plan['proxy'],proxyAdmin=plan['proxyAdmin'],churnPeriodSeconds=3600,maximumChurnPercentage=20)
    vector=json.loads((ROOT/'tools/mainnet-offline/testdata/public-bls-vectors.json').read_text())['validators'][0]
    p['validationPublicIdentity']={k:vector[k] for k in ('nodeId','blsPublicKey')}
    e=make_expectations(g,p,dict(subnetId=cb58((123).to_bytes(32,'big'))),hashlib.sha256(raw).hexdigest(),cast)
    e['syntheticTestOnly']=True
    (output/'expectations.json').write_text(json.dumps(e,indent=2)+'\n')
    print('Synthetic exact-import input only:',output)

if __name__=='__main__':
    import argparse
    a=argparse.ArgumentParser(description=__doc__);a.add_argument('--output',type=Path,required=True);a.add_argument('--cast',default='cast');args=a.parse_args();build(args.output,args.cast)
