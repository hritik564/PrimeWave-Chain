import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts/mainnet'))
import chain_id
import fuji_rehearsal
import validate_genesis


class FujiBundleTests(unittest.TestCase):
    def setUp(self):
        self.directory=tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.registry=Path(self.directory.name)/'registry.json'
        self.registry.write_text('[{"chainId":43114}]')
        self.decision=chain_id.evidence(73571002,self.registry)
        self.decision.update(ownerApproved=True,approvedChainId=73571002)
        self.proxy='0x'+'33'*20
        self.addresses={'rewards':'0x'+'11'*20,'other':'0x'+'22'*20}
        self.policy={'rewards':15000000,'other':85000000}
        self.entry={'balance':'0x0','code':'0x6000','storage':{}}
        self.digest=hashlib.sha256(json.dumps(self.entry,sort_keys=True,separators=(',',':')).encode()).hexdigest()
        self.allocation={'ownerApproved':True,'addresses':self.addresses,'allocationsPW':self.policy,'predeploys':{self.proxy:self.digest}}
        self.genesis={'config':{'chainId':73571002,'feeConfig':{},'rewardManagerConfig':{'initialRewardConfig':{'rewardAddress':'0x'+'44'*20}}},'gasLimit':'0x1',
                      'alloc':{self.addresses[k]:{'balance':hex(v*10**18)} for k,v in self.policy.items()}}
        self.genesis['alloc'][self.proxy]=self.entry
        self.manager={'environment':'fuji','broadcastApproved':False,'ownerApproved':True,'evmChainId':73571002,'productionChainId':73571001,
                      'managerAddress':self.proxy,'managerArtifactSha256':'ab'*32,'managerInitializationReviewed':True,'managerBootstrapReviewed':True,'genesisForksReviewed':True,'fundingPlanReviewed':True,
                      'validatorRpcEndpoints':['http://127.0.0.1:19650','http://127.0.0.1:29650'],'fujiKeystoreAlias':'pw-fuji-disposable-test','validatorBalanceAVAX':'0.1',
                      'signatureAggregatorUrl':'http://127.0.0.1:18080'}
        self.identities=[dict(environment='fuji',freshTestIdentity=True,nodeId='NodeID-'+str(i),blsPublicKey='fixture',proofOfPossession='fixture') for i in (1,2)]

    def bundle(self):
        return fuji_rehearsal.prepare_bundle(self.manager,self.identities,self.genesis,self.allocation,self.decision,self.registry,Path('/reviewed/fuji-genesis.json'))

    def test_prepare_only_renders_approved_fuji_argv_without_execution(self):
        with patch('subprocess.run') as execute:
            bundle=self.bundle()
            execute.assert_not_called()
        self.assertEqual(bundle['broadcasts'],0)
        self.assertFalse(bundle['keyAccess'])
        args=bundle['argvAfterSeparateBroadcastApproval']
        self.assertIn('--network=fuji',args)
        self.assertIn('--genesis-proxy-address='+self.proxy,args)
        self.assertIn('--local-sig-agg',args)
        self.assertFalse(any('private-key' in arg or 'deploy-validator-manager' in arg for arg in args))

    def test_no_signature_aggregator_fallback(self):
        self.manager.pop('signatureAggregatorUrl')
        with self.assertRaisesRegex(ValueError,'signature aggregator'):self.bundle()

    def test_missing_owner_approval_refused(self):
        self.manager['ownerApproved']=False
        with self.assertRaises(ValueError):self.bundle()

    def test_production_chain_id_cannot_be_reused_on_fuji(self):
        self.manager['productionChainId']=73571002
        with self.assertRaises(ValueError):self.bundle()

    def test_public_validator_rpc_and_missing_manager_review_refused(self):
        self.manager['validatorRpcEndpoints'][0]='http://8.8.8.8:9650'
        with self.assertRaises(ValueError):self.bundle()
        self.manager['validatorRpcEndpoints'][0]='http://127.0.0.1:19650'
        self.manager['managerArtifactSha256']=None
        with self.assertRaises(ValueError):self.bundle()

    def test_predeploy_code_storage_or_balance_tampering_refused(self):
        for field,value in (('code','0x6001'),('balance','0x1'),('storage',{'slot':'value'})):
            changed=copy.deepcopy(self.genesis)
            changed['alloc'][self.proxy][field]=value
            with self.subTest(field=field),self.assertRaises(ValueError):
                validate_genesis.validate(changed,73571002,self.policy,self.addresses,self.allocation['predeploys'])

    def test_unapproved_genesis_contract_code_refused(self):
        self.allocation['predeploys']={}
        with self.assertRaises(ValueError):self.bundle()

    def test_allocation_tables_retain_exact_total_and_percentages(self):
        review=json.loads((ROOT/'config/mainnet/genesis.review.json').read_text())
        self.assertEqual(review['selectedAllocationPolicy'],'C00_PRIMEWAVE_TOKENOMICS')
        for allocations in review['allocationCandidates'].values():
            self.assertEqual(sum(allocations.values()),100000000)
        c11=review['allocationCandidates']['C11_GENESIS_FINALIZATION']
        from decimal import Decimal
        self.assertEqual(Decimal(c11['reserve'])/1000000,Decimal('9.999999'))
        self.assertEqual(Decimal(c11['deployer'])/1000000,Decimal('0.000001'))
