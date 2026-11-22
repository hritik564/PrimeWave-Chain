"""Offline decision proposals; no production signer/address generation."""
import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts/mainnet'))
import check_decision_package as decision
import chain_id

PACKAGE=ROOT/'config/mainnet/decisions/package.review.json'

class DecisionPackageTests(unittest.TestCase):
    def test_package_is_consistent_but_not_authorization(self):
        result=decision.check(PACKAGE)
        self.assertFalse(result['executionReady']);self.assertFalse(result['ownerApproved'])
        self.assertEqual(result['candidate'],73571001)
        self.assertEqual(result['weightAnalysis']['initialChurnBudgetWeight'],400)

    def test_registry_age_is_not_fabricated_as_a_live_refresh(self):
        p=json.loads(PACKAGE.read_text());c=p['chainId']
        self.assertFalse(c['liveRefreshPerformed']);self.assertFalse(c['globalUniquenessProven'])
        self.assertEqual(c['checkedAt'],c['snapshotRetrievedAt'])
        raw=(PACKAGE.parent/c['snapshotPath']).read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(),c['registrySha256'])
        chain_id.check_candidate(c['candidate'],json.loads(raw))
        for invalid in chain_id.DENIED:
            with self.assertRaises(ValueError):chain_id.check_candidate(invalid,json.loads(raw))
        with self.assertRaises(ValueError):chain_id.approved(c,PACKAGE.parent/c['snapshotPath'])

    def test_weight_limits_and_pinned_manager_minimum(self):
        with self.assertRaisesRegex(ValueError,'initializeValidatorSet'):decision.validate_weights({'validator-1':1,'validator-2':1},20,3600)
        for weights,churn,period in [({'validator-1':0,'validator-2':1000},20,3600),({'validator-1':10**18,'validator-2':10**18},20,3600),({'validator-1':2**64,'validator-2':1000},20,3600),({'validator-1':1000,'validator-2':1000},21,3600),({'validator-1':1000,'validator-2':1000},20,86401)]:
            with self.assertRaises(ValueError):decision.validate_weights(weights,churn,period)

    def test_candidate_and_economics_are_not_changed(self):
        p=json.loads(PACKAGE.read_text())
        for name in ('deployment.review.json','sydney.deployment.review.json','sydney.existing-runtime.review.json'):
            m=json.loads((ROOT/'deploy/aws'/name).read_text());e=m['environments']['mainnet']
            self.assertEqual(e['chainIdCandidate'],p['chainId']['candidate']);self.assertIsNone(e['evmChainId']);self.assertFalse(e['chainIdApproved'])
            for k,v in p['economicsUnchanged'].items():self.assertEqual(m[k],v)
            self.assertNotEqual(e['chainIdCandidate'],m['environments']['fuji']['evmChainId'])
        for role,item in p['governance']['roles'].items():
            self.assertIsNone(item['publicAddress']);self.assertFalse(item['ownerApproved'])
            self.assertTrue(all(a is None for a in item.get('signerPublicAddresses',[])))
        self.assertFalse(any(p['productionApprovals'].values()))

    def test_an_approval_or_address_cannot_silently_be_added_to_review_package(self):
        original=json.loads(PACKAGE.read_text())
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);(folder/'chain-registry.snapshot.json').write_bytes((PACKAGE.parent/'chain-registry.snapshot.json').read_bytes())
            for change in ('approval','address','global'):
                p=copy.deepcopy(original)
                if change=='approval':p['governance']['ownerApproved']=True
                elif change=='address':p['governance']['roles']['protocolAdminMultisig']['publicAddress']='0x'+'1'*40
                else:p['chainId']['globalUniquenessProven']=True
                f=folder/'package.json';f.write_text(json.dumps(p))
                with self.assertRaises(ValueError):decision.check(f)

    def test_package_cannot_relax_timelock_or_emergency_policy(self):
        original=json.loads(PACKAGE.read_text())
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);(folder/'chain-registry.snapshot.json').write_bytes((PACKAGE.parent/'chain-registry.snapshot.json').read_bytes())
            for variant in ('timelock','emergency','supply'):
                p=copy.deepcopy(original)
                if variant=='timelock':p['governance']['minimumTimelockSeconds']=3600
                elif variant=='emergency':p['governance']['roles']['emergencyMultisig']['proposedThreshold']=2
                else:p['economicsUnchanged']['nativeSupplyPW']=100000001
                f=folder/'package.json';f.write_text(json.dumps(p))
                with self.assertRaises(ValueError):decision.check(f)
