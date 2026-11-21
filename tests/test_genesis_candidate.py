import copy
import importlib.util
import json
from pathlib import Path
import sys
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts/mainnet'))
import genesis_candidate as candidate


class GenesisCandidateTests(unittest.TestCase):
    def setUp(self):
        fixture=json.loads((ROOT/'tests/live/c00-predeploy.fixture.json').read_text())
        self.public=fixture['publicManifest']
        self.states=fixture['accounts']
        proxy=self.public['managerAddress']
        # Deliberately synthetic, zero-balance TEST manager. Never a production artifact.
        self.public['managerPredeploys']={proxy:{'balance':'0x0','code':'0x6000','storage':{}}}
        self.base={'config':{'chainId':73571001,'feeConfig':{'gasLimit':15000000},
                    'rewardManagerConfig':{'initialRewardConfig':{'rewardAddress':self.public['contracts']['feeDistributor']}}},
                   'gasLimit':'0xe4e1c0','timestamp':hex(self.public['genesisTimestamp'])}

    def build(self):
        return candidate.materialize(self.public,self.states,self.base)

    def test_deterministic_exact_c00_supply_without_authorization(self):
        result=self.build()
        self.assertEqual(candidate.canonical(result),candidate.canonical(self.build()))
        self.assertFalse(result['deployable'])
        self.assertFalse(result['genesisApproved'])
        self.assertFalse(result['chainIdApproved'])
        self.assertEqual(sum(int(v['balance'],0) for v in result['genesis']['alloc'].values()),100_000_000*10**18)
        for role,pw in candidate.C00.items():
            self.assertEqual(int(result['genesis']['alloc'][self.public['allocationAddresses'][role].lower()]['balance'],0),pw*10**18)

    def test_review_proposal_has_no_invented_addresses(self):
        expected=json.loads((ROOT/'config/mainnet/genesis.candidate.json').read_text())
        self.assertEqual(candidate.proposal(),expected)
        self.assertTrue(all(a['address'] is None for a in expected['allocations']))
        self.assertFalse(expected['rewardCustodyProposal']['ownerApproved'])

    def test_unresolved_public_manifest_is_refused(self):
        public=json.loads((ROOT/'config/mainnet/public-genesis-manifest.review.json').read_text())
        with self.assertRaisesRegex(ValueError,'require review'):
            candidate.materialize(public,self.states,self.base)

    def test_custody_review_is_mandatory(self):
        self.public['custodyProposalApproved']=False
        with self.assertRaises(ValueError):self.build()

    def test_rewards_cannot_pass_through_funding_eoa(self):
        self.public['allocationAddresses']['rewards']='0x'+'e'*40
        with self.assertRaisesRegex(ValueError,'directly') :self.build()

    def test_unaccounted_vault_balance_is_refused(self):
        slot='0x'+format(4,'064x')
        self.states[self.public['contracts']['rewardVault']]['storage'][slot]='0x'+'0'*64
        with self.assertRaisesRegex(ValueError,'totalFunded'):self.build()

    def test_extra_supply_or_unreviewed_contract_is_refused(self):
        self.public['managerPredeploys'][self.public['managerAddress']]['balance']='0x1'
        with self.assertRaisesRegex(ValueError,'zero-balance'):self.build()

    def test_missing_manager_is_refused(self):
        self.public['managerPredeploys']={}
        with self.assertRaisesRegex(ValueError,'manager proxy'):self.build()

    def test_no_demo_chain_or_timestamp_fallback(self):
        self.base['config']['chainId']=73571
        with self.assertRaisesRegex(ValueError,'distinct'):self.build()
        self.base['config']['chainId']=73571001
        self.base['timestamp']='0x0'
        with self.assertRaisesRegex(ValueError,'timestamp'):self.build()

    def test_wrong_fee_destination_is_refused(self):
        self.base['config']['rewardManagerConfig']['initialRewardConfig']['rewardAddress']=self.public['contracts']['rewardVault']
        with self.assertRaisesRegex(ValueError,'FeeDistributor'):self.build()

    def test_unexpected_minter_is_refused(self):
        self.base['config']['contractNativeMinterConfig']={}
        with self.assertRaisesRegex(ValueError,'NativeMinter'):self.build()
