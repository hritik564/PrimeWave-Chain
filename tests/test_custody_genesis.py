import copy
import hashlib
import json
from pathlib import Path
import sys
import unittest
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts/mainnet'))
import genesis_candidate as g

class CustodyGenesisTests(unittest.TestCase):
    def setUp(self):
        self.f=json.loads((ROOT/'tests/fixtures/custody-genesis.fixture.json').read_text())
    def build(self):return g.materialize(self.f['publicManifest'],self.f['accounts'],self.f['base'])
    def test_exact_supply_treasury_and_repeatability(self):
        first=self.build();self.assertEqual(first,self.build());self.assertFalse(first['deployable'])
        alloc=first['genesis']['alloc'];self.assertEqual(sum(int(v['balance'],0) for v in alloc.values()),100000000*10**18)
        for role,amount in g.C00.items():self.assertEqual(int(alloc[self.f['publicManifest']['allocationAddresses'][role].lower()]['balance'],0),amount*10**18)
        self.assertTrue(alloc[self.f['publicManifest']['allocationAddresses']['treasury']]['code'])
    def test_treasury_balance_zero_or_duplicate_refused(self):
        address=self.f['publicManifest']['allocationAddresses']['treasury']
        self.f['accounts'][address]['balance']='0x0'
        with self.assertRaises(ValueError):self.build()
    def test_runtime_storage_nonce_and_roles_are_not_silently_changed(self):
        for change in ('code','storage','nonce','guard','safe','overlap'):
            old=copy.deepcopy(self.f);c=self.f['publicManifest']['custody'];target=c['treasurySafe']
            if change=='code':self.f['accounts'][target]['code']='0x6000'
            elif change=='storage':self.f['accounts'][target]['storage']['0x'+format(4,'064x')]='0x1'
            elif change=='nonce':self.f['accounts'][target]['nonce']='0x2'
            elif change=='guard':
                self.f['accounts'][target]['storage']['0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8']='0x0'
                c['stateSha256'][target]=hashlib.sha256(g.canonical(self.f['accounts'][target])).hexdigest()
            elif change=='safe':c['safeSingleton']=c['treasurySafe']
            else:c['treasuryOwners']=c['protocolOwners']
            with self.assertRaises((ValueError,KeyError)):self.build()
            self.f=old
    def test_published_safe_artifacts_and_compiled_policies_are_pinned(self):
        lock=json.loads((ROOT/'config/mainnet/custody-artifacts.lock.json').read_text())
        self.assertFalse(lock['ownerApproved'])
        for name in ('Safe','SafeProxy'):
            item=lock['artifacts'][name];raw=(ROOT/item['path']).read_bytes();self.assertEqual(hashlib.sha256(raw).hexdigest(),item['sha256'])
        for name in ('PrimeWaveCustodyTimelock','PauseOnlyEmergencyMultisig'):
            item=lock['artifacts'][name];self.assertEqual(hashlib.sha256((ROOT/item['sourcePath']).read_bytes()).hexdigest(),item['sourceSha256'])

    def test_state_review_never_preserves_or_grants_approval(self):
        import custody_state_review
        result=custody_state_review.prepare(self.f['publicManifest'],self.f['accounts'])
        self.assertFalse(result['publicAddressesReviewed']);self.assertFalse(result['custodyProposalApproved'])
        self.assertEqual(result['custody']['stateSha256'],self.f['publicManifest']['custody']['stateSha256'])
