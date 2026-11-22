import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts/mainnet'))
import export_mainnet_genesis as export
import validate_exact_genesis as exact

class ProductionExportInputTests(unittest.TestCase):
    def setUp(self):
        f=json.loads((ROOT/'tests/fixtures/combined-genesis.fixture.json').read_text())
        self.public=copy.deepcopy(f['publicManifest']);plan=f['syntheticAddressPlan']
        self.public['manager']=dict(library=plan['validatorMessages'],implementation=plan['implementation'],proxy=plan['proxy'],poa=plan['poa'],proxyAdmin=plan['proxyAdmin'],churnPeriodSeconds=3600,maximumChurnPercentage=20,validatorWeights={'validator-1':1000,'validator-2':1000})
    def nonreserved_test_plan(self):
        # Test-only public contract/signer constants, no key or approval generation.
        def replace(v):
            if isinstance(v,dict):return {k:replace(x) for k,x in v.items()}
            if isinstance(v,list):return [replace(x) for x in v]
            if isinstance(v,str) and len(v)==42 and v.startswith('0x'):return '0x'+format(int(v,16)+(1<<152),'040x')
            return v
        return replace(self.public)
    def test_no_synthetic_address_fallback(self):
        with self.assertRaisesRegex(ValueError,'non-synthetic'):export.validate_address_plan(self.public)
    def test_explicit_collision_free_plan_and_three_groups(self):
        export.validate_address_plan(self.nonreserved_test_plan())
    def test_code_owner_allocation_collisions_fail(self):
        for change in ('library','signer','allocation'):
            p=self.nonreserved_test_plan()
            if change=='library':p['manager']['library']=p['custody']['safeSingleton']
            elif change=='signer':p['custody']['treasuryOwners'][0]=p['emergencySigners'][0]
            else:p['allocationAddresses']['liquidity']=p['manager']['proxyAdmin']
            with self.assertRaises(ValueError):export.validate_address_plan(p)
    def test_missing_or_truncated_owner_weight_inputs_fail(self):
        p=self.nonreserved_test_plan();p['custody']['protocolOwners'].pop()
        with self.assertRaises(ValueError):export.validate_address_plan(p)
        p=self.nonreserved_test_plan();p['manager']['validatorWeights']={'validator-1':1,'validator-2':1}
        with self.assertRaises(ValueError):export.validate_address_plan(p)
    def test_cb58_checksum_not_just_regex(self):
        known='XDwGN3ztu8JDEFALEeKWS3FPax8U2XghGFZVDxrGesNs5w7D7'
        self.assertEqual(len(export.decode_id(known)),32)
        with self.assertRaises(ValueError):export.decode_id(known[:-1]+'1')
        with self.assertRaises(ValueError):export.decode_id('11111111111111111111111111111111LpoYY')
    def test_missing_review_or_unapproved_inputs_refused_before_build(self):
        p=copy.deepcopy(self.public);p['publicAddressesReviewed']=False
        with self.assertRaisesRegex(ValueError,'Owner-reviewed'):export.validate_inputs(p,{}, {},{},b'',b'',b'',73571001)
        p=copy.deepcopy(self.public)
        with self.assertRaisesRegex(ValueError,'input review'):export.validate_inputs(p,{}, {},{},b'',b'',b'',73571001)
    def test_no_keys_and_normalized_duplicate_accounts(self):
        with self.assertRaises(ValueError):export.public_only({'privateKey':'DO_NOT_USE'})
        with self.assertRaises(ValueError):export.normalize({'0xAb':{},'0xab':{}})

class ExactGenesisInputTests(unittest.TestCase):
    def input(self,directory):
        f=json.loads((ROOT/'docs/security-review/combined-synthetic-genesis.candidate.json').read_text());g=f['genesis'];raw=json.dumps(g).encode();p=directory/'genesis';e=directory/'expectations';p.write_bytes(raw)
        value=dict(schema='primewave-exact-genesis-v1',genesisFileSha256=hashlib.sha256(raw).hexdigest(),chainId=g['config']['chainId'],accounts=g['alloc'],calls=[dict(to='test-only',data='0x',expected='0x')],publicNodeIdentity=dict(nodeId='public metadata placeholder, not execution',blsPublicKey='test-only'))
        e.write_text(json.dumps(value));return p,e,value
    def test_exact_file_not_reconstruction(self):
        with tempfile.TemporaryDirectory() as d:
            p,e,v=self.input(Path(d));exact.validate_files(p,e);p.write_bytes(p.read_bytes()+b' ')
            with self.assertRaisesRegex(ValueError,'SHA256'):exact.validate_files(p,e)
    def test_partial_state_or_missing_public_context_refused(self):
        with tempfile.TemporaryDirectory() as d:
            p,e,v=self.input(Path(d));v['accounts']={};e.write_text(json.dumps(v))
            with self.assertRaises(ValueError):exact.validate_files(p,e)
            p,e,v=self.input(Path(d));v['publicNodeIdentity']=None;e.write_text(json.dumps(v))
            with self.assertRaises(ValueError):exact.validate_files(p,e)
    def test_duplicate_json_member_refused(self):
        with self.assertRaises(ValueError):json.loads('{"config":{},"config":{}}',object_pairs_hook=exact.duplicate_safe)
    def test_binary_verification_rejects_unpinned_bytes(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'bad';p.write_bytes(b'not a release')
            with self.assertRaises(ValueError):exact.verify_plugin(p,p)

class FocusedArtifactChecks(unittest.TestCase):
    @unittest.skipUnless((ROOT/'genesis-build/mainnet-author-test/state.json').exists(),'run new ManagerAuthor focused suite first')
    def test_complete_manager_runtime_and_immutable_tamper(self):
        states=export.normalize(json.loads((ROOT/'genesis-build/mainnet-author-test/state.json').read_text()))
        plan=json.loads((ROOT/'genesis-build/mainnet-author-test/plan.json').read_text());artifacts=ROOT/'genesis-build/mainnet-author-test/artifacts'
        export.verify_manager(states,plan,artifacts)
        for address in plan.values():
            value=copy.deepcopy(states);value[address.lower()]['code']='0x6000'
            with self.assertRaises(ValueError):export.verify_manager(value,plan,artifacts)
    @unittest.skipUnless((ROOT/'genesis-build/custody-ast-focused-test/artifacts/FeeDistributor.sol/FeeDistributor.json').exists(),'build custody artifacts with --ast first')
    def test_full_core_runtime_and_immutable_tamper(self):
        fixture=json.loads((ROOT/'tests/fixtures/combined-genesis.fixture.json').read_text());states=fixture['accounts'];p=fixture['publicManifest'];artifacts=ROOT/'genesis-build/custody-ast-focused-test/artifacts'
        export.verify_custody_complete(states,p,artifacts)
        states[p['contracts']['feeDistributor']]['code']='0x6000'
        with self.assertRaises(ValueError):export.verify_custody_complete(states,p,artifacts)
