import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts/mainnet'))
import combined_genesis as combined
import verify_safe_rebuild as safe

class CombinedGenesisTests(unittest.TestCase):
    def setUp(self):self.fixture=json.loads((ROOT/'tests/fixtures/combined-genesis.fixture.json').read_text())
    def test_exact_c00_supply_balances_and_deterministic_candidate(self):
        first=combined.validate(self.fixture);self.assertEqual(first,combined.validate(self.fixture))
        self.assertFalse(first['deployable']);self.assertFalse(first['genesisApproved'])
        alloc=first['genesis']['alloc'];self.assertEqual(len(alloc),22)
        self.assertEqual(sum(int(v['balance'],0) for v in alloc.values()),100000000*10**18)
        self.assertEqual(int(alloc[combined.ADDR(0xB008)]['balance'],0),15000000*10**18)
        self.assertEqual(int(alloc[combined.ADDR(0xB006)]['balance'],0),15000000*10**18)
    def test_no_missing_manager_account_or_child_proxy_admin(self):
        for role,address in combined.PLAN.items():
            value=copy.deepcopy(self.fixture);del value['accounts'][address]
            with self.assertRaises(ValueError,msg=role):combined.validate(value)
    def test_proxy_account_nonce_is_two_and_admin_is_one(self):
        self.assertEqual(int(self.fixture['accounts'][combined.PLAN['proxy']]['nonce'],0),2)
        for role in ('proxy','proxyAdmin'):
            value=copy.deepcopy(self.fixture);value['accounts'][combined.PLAN[role]]['nonce']='0x0'
            with self.assertRaises(ValueError):combined.validate(value)
    def test_manager_runtime_and_initial_storage_tampering_rejected(self):
        for role in combined.PLAN:
            for field,replacement in [('code','0x6000'),('storage',{})]:
                value=copy.deepcopy(self.fixture);value['accounts'][combined.PLAN[role]][field]=replacement
                # Library storage is correctly empty; no mutation to reject there.
                if value==self.fixture:continue
                with self.assertRaises(ValueError,msg=role+field):combined.validate(value)
    def test_custody_runtime_or_allocation_changes_rejected(self):
        for address,field,value in [(combined.ADDR(0xB010),'code','0x6000'),(combined.ADDR(0xB008),'balance','0x0')]:
            f=copy.deepcopy(self.fixture);f['accounts'][address][field]=value
            with self.assertRaises(ValueError):combined.validate(f)
    def test_collision_and_extra_account_refused(self):
        f=copy.deepcopy(self.fixture);f['syntheticAddressPlan']['validatorMessages']=combined.ADDR(0xB010)
        with self.assertRaises(ValueError):combined.validate(f)
        f=copy.deepcopy(self.fixture);f['accounts'][combined.ADDR(0xB010).upper()]=f['accounts'][combined.ADDR(0xB010)]
        with self.assertRaises(ValueError):combined.validate(f)
    def test_synthetic_labels_and_manager_predeploy_set_required(self):
        f=copy.deepcopy(self.fixture);f['productionApproved']=True
        with self.assertRaises(ValueError):combined.validate(f)
        f=copy.deepcopy(self.fixture);f['publicManifest']['managerPredeploys']={}
        with self.assertRaises(ValueError):combined.validate(f)
    def test_safe_rebuild_refuses_unverified_package_before_compiler_execution(self):
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/'bad';path.write_bytes(b'not upstream')
            with self.assertRaisesRegex(ValueError,'archive mismatch'):safe.run(path,path)
    def test_original_published_and_custody_locks_unchanged(self):
        scope=json.loads((ROOT/'docs/security-review/scope-evidence.json').read_text())
        for path in ['config/mainnet/custody-artifacts.lock.json','config/mainnet/public-genesis-manifest.review.json']:
            self.assertEqual(hashlib.sha256((ROOT/path).read_bytes()).hexdigest(),scope['sourceSha256'][path])
