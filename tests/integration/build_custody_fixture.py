#!/usr/bin/env python3
"""Convert actual Foundry test export to a labeled PUBLIC SYNTHETIC fixture.
Run only after CustodySecurityTest.testWriteSyntheticExportForPythonIntegration.
No production configuration or approval is written.
"""
import hashlib
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]

def build():
    raw=json.loads((ROOT/'genesis-build/custody-fixture.raw.json').read_text())
    states={a.lower():json.loads(v) if isinstance(v,str) else v for a,v in raw.items()}
    for v in states.values():
        if isinstance(v['storage'],str):v['storage']=json.loads(v['storage'])
    addr=lambda n:'0x'+format(n,'040x')
    public=dict(publicAddressesReviewed=True,custodyProposalApproved=True,
        allocationAddresses=dict(liquidity=addr(0xD001),treasury=addr(0xB008),team=addr(0xD002),rewards=addr(0xB006),presale1=addr(0xD003),presale2=addr(0xD004),presale3=addr(0xD005)),
        contracts=dict(timelock=addr(0xB001),emergency=addr(0xB002),feeVault=addr(0xB003),feeDistributor=addr(0xB004),registry=addr(0xB005),rewardVault=addr(0xB006)),
        managerAddress=addr(0xB007),managerPredeploys={addr(0xB007):dict(balance='0x0',code='0x6000',storage={})},
        governanceProposer=addr(0xB009),emergencySigners=[addr(0xA300+i) for i in range(5)],genesisTimestamp=1800000000,
        custody=dict(mode='safe-1.4.1-oz-5.6.1',safeSingleton=addr(0xB010),protocolSafe=addr(0xB009),treasurySafe=addr(0xB011),protocolGuard=addr(0xB012),treasuryGuard=addr(0xB013),protocolOwners=[addr(0xA100+i) for i in range(5)],treasuryOwners=[addr(0xA200+i) for i in range(5)]))
    public['custody']['stateSha256']={a:hashlib.sha256(json.dumps(v,sort_keys=True,separators=(',',':')).encode()).hexdigest() for a,v in states.items()}
    fixture=dict(syntheticTestOnly=True,productionApproved=False,publicManifest=public,accounts=states,
        base=dict(config=dict(chainId=73571001,feeConfig=dict(gasLimit=15000000),rewardManagerConfig=dict(initialRewardConfig=dict(rewardAddress=addr(0xB004)))),gasLimit='0xe4e1c0',timestamp=hex(1800000000)))
    out=ROOT/'tests/fixtures/custody-genesis.fixture.json'
    out.write_text(json.dumps(fixture,sort_keys=True,indent=2)+'\n')
    print(out)
if __name__=='__main__':build()
