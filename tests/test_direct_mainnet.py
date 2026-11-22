"""Synthetic offline evidence only. Never production manifests or RPC traffic."""
import copy
from datetime import datetime,timedelta,timezone
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import test_aws_pilot as fixture
import test_genesis_candidate as genesis_fixture
sys.path.insert(0,str(fixture.ROOT/'scripts/deploy'))
import mainnet_readiness as direct
import aws_launch_prepare as launch
aws=fixture.aws

class DirectMainnetTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.folder=Path(self.tmp.name).resolve();self.count=0
        f=fixture.AwsPilotTests();f.setUp();self.m=f.m;self.m['awsLaunchApprovals']['accountVerified']=True
        e=self.m['environments']['mainnet'];self.e=e;self.r=self.m['mainnetReadiness']
        e['approvals']['identityCreation']=True
        e.update(pChainBudgetAVAX='1',validatorBalanceAVAX='1',pChainFundingAddress='P-avax1'+'q'*38,signerKeystoreAlias='pw-mainnet-SYNTHETIC',pwGasSourceRole='treasury',signatureAggregatorUrl='http://127.0.0.1:8080')
        for n,i in enumerate(e['identities'].values(),1):
            i.update(nodeId='NodeID-'+str(n)*25,blsPublicKey='0x'+str(n)*96,proofOfPossession='0x'+str(n)*192,stakingCertificateSha256=str(n)*64,environment='mainnet',productionOnly=True)
        # Full shared host preflight evidence, not precomputed PASS booleans.
        for h in self.m['hosts']:
            c=copy.deepcopy(f.cloud);l=copy.deepcopy(f.local);c['host']=h['name'];l['host']=h['name']
            ins=c['instance'];ins.update(InstanceId=h['instanceId'],PrivateIpAddress=h['privateIp'],PublicIpAddress=h['publicIp'],Placement={'AvailabilityZone':h['availabilityZone']},SecurityGroups=[{'GroupId':h['securityGroupIds'][0]}])
            ins['BlockDeviceMappings'][0]['Ebs']['VolumeId']=h['rootVolumeId'];ins['BlockDeviceMappings'][1]['Ebs']['VolumeId']=h['dataVolumeId']
            c['securityGroups'][0]['GroupId']=h['securityGroupIds'][0]
            c['volumes'][0].update(VolumeId=h['dataVolumeId'],AvailabilityZone=h['availabilityZone'],Attachments=[{'InstanceId':h['instanceId'],'State':'attached'}])
            c['rootVolumes']=[dict(VolumeId=h['rootVolumeId'],Encrypted=True,Size=32,VolumeType='gp3')]
            c['ssm'][0]['InstanceId']=h['instanceId']
            l['facts']['identityDocument'].update(instanceId=h['instanceId'],availabilityZone=h['availabilityZone'],privateIp=h['privateIp'])
            l['facts'].update(mount={'target':h['persistentMount'],'uuid':h['filesystemUuid']},volumeSerials=[h['dataVolumeId'].replace('-','')])
            op=dict({k:h[k] for k in ('instanceId','dataVolumeId','filesystemUuid')},observedAt=aws.now(),publicIdentity=e['identities'][h['name']],certificateSha256=e['identities'][h['name']]['stakingCertificateSha256'],identityFilesPrivate=True,productionOnly=True,alertDeliveryVerified=True,alertEventId='SYNTHETIC-ALERT')
            self.r['hostEvidence'][h['name']]={'cloud':self.write(c),'local':self.write(l),'operations':self.write(op)}
        g=genesis_fixture.GenesisCandidateTests();g.setUp()
        for a in ('0x'+'a'*40,'0x'+'b'*40):g.public['managerPredeploys'][a]={'balance':'0x0','code':'0x6000','storage':{}}
        candidate=g.build()
        e.update(evmChainId=73571001,chainIdApproved=True,genesisApproved=True,genesisSha256=candidate['genesisSha256'],genesisPublic=g.public,managerProxy=g.public['managerAddress'],managerImplementation='0x'+'a'*40,managerLibrary='0x'+'b'*40,proxyAdmin='0x'+'c'*40,managerBootstrapReviewed=True,managerInitializationReviewed=True,genesisForksReviewed=True)
        construction=dict(public=g.public,exported=g.states,base=g.base)
        artifact={'TEST_ONLY':True,'runtimeBytecode':{a:'0x6000' for a in (e['managerProxy'],e['managerImplementation'],e['managerLibrary'])}};e['managerArtifactSha256']=direct.sha(artifact)
        self.r.update(genesis=self.write(candidate['genesis']),construction=self.write(construction),managerArtifact=self.write(artifact))
        registry=self.write([{'chainId':1}]);self.r['registry']=registry
        self.r['chainApproval']=self.write(dict(candidate=73571001,approvedChainId=73571001,ownerApproved=True,registrySha256=registry['sha256'],checkedAt=aws.now()))
        review=dict(networkId=1,chainId=e['evmChainId'],genesisSha256=e['genesisSha256'],constructionSha256=direct.sha(construction),managerArtifactSha256=e['managerArtifactSha256'],ownerReviewed=True,reference='SYNTHETIC-REVIEW',managerBootstrapReviewed=True,managerInitializationReviewed=True,genesisForksReviewed=True,uninitializedProxyCallable=False,bootstrapMode='owner-atomic-upgrade-initialize',governance={'signers':g.public['emergencySigners'],'threshold':3,'timelockSeconds':172800,'owner':e['proxyAdmin']},validatorWeights={'validator-1':1,'validator-2':1})
        self.r['securityReview']=self.write(review)
        self.r['vmCompatibility']=self.write(dict(networkId=1,chainId=e['evmChainId'],genesisSha256=e['genesisSha256'],ownerReviewed=True,reference='SYNTHETIC-VM',avalancheGo='1.15.1',subnetEvm='1.15.1',pluginProtocol=46,handshakePassed=True,genesisAccepted=True,initializationTestsPassed=True))
        recovery=dict(accountId=self.m['accountId'],region=self.m['region'],procedureTestPassed=True,singleActiveIdentityFencingVerified=True,containsProductionKeys=False,reference='SYNTHETIC-RECOVERY')
        self.m['operations'].update(offHostRecoveryVerified=True,recoveryEvidenceSha256=direct.sha(recovery))
        self.r['recovery']=self.write(recovery)
        self.r['incidentResponse']=self.write(dict(ownerApproved=True,reference='SYNTHETIC',twoValidatorHaltAccepted=True,stopCriteria='SYNTHETIC',escalationContact='SYNTHETIC',rollbackProcedure='SYNTHETIC',noDatabaseReset=True,noDuplicateIdentity=True))
        self.r['commissioningPlan']=self.write(dict(networkId=1,chainId=e['evmChainId'],genesisSha256=e['genesisSha256'],ownerReviewed=True,reference='SYNTHETIC',maximumTransfers=2,maximumDurationSeconds=600,maximumNativePW='1',maximumGasPW='1',gasSourceRole='treasury',productionRiskAccepted=True,haltOnMismatch=True,haltOnResourcePressure=True,alertDeliveryRequired=True,recoveryRequiredBeforePublicAccess=True))
        pre=dict(networkId=1,chainId=e['evmChainId'],ownerReviewed=True,reference='SYNTHETIC-PRE-SUBNET',allocationPolicy='C00',nativeSupplyPW=100000000,feeSplitBps=self.m['feeSplitBps'],bootstrapMode='subnet-bound-genesis',createSubnetOnly=True,custodyVerified=True,fundingPlanReviewed=True,uninitializedPublicProxyForbidden=True,finalArtifactsRequiredBeforeCreateChain=True,governance=review['governance'],validatorWeights=review['validatorWeights'])
        self.r['preSubnetReview']=self.write(pre)
        for operation in direct.OPERATIONS:
            request=dict(networkId=1,chainId=e['evmChainId'],genesisSha256=e['genesisSha256'],operation=operation,transactionCount=1,reviewed=True,reference='SYNTHETIC',parameters={'TEST_ONLY':True},signerAlias='pw-mainnet-SYNTHETIC',maximumFeeAVAX='0.1',maximumTotalSpendAVAX='1')
            if operation=='createSubnet':
                request['genesisSha256']=None;request['preSubnetReviewSha256']=direct.sha(pre)
            self.r['transactions'][operation]['request']=self.write(request)
        request=self.read(self.r['transactions']['createSubnet']['request'])
        self.r['transactions']['createSubnet']['approval']=self.approve(dict(operation='createSubnet',networkId=1,accountId=self.m['accountId'],region=self.m['region'],requestSha256=direct.sha(request)))

    def write(self,value):
        self.count+=1;p=self.folder/f'{self.count}.json';p.write_text(json.dumps(value))
        return {'path':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
    def read(self,ref):return json.loads(Path(ref['path']).read_text())
    def change(self,key,changes):
        value=self.read(self.r[key]);value.update(changes);self.r[key]=self.write(value)
    def approve(self,binding):
        now=datetime.now(timezone.utc)
        return dict(approved=True,reference='SYNTHETIC-TEST-ONLY',issuedAt=(now-timedelta(seconds=1)).isoformat(),expiresAt=(now+timedelta(hours=1)).isoformat(),binding=binding)
    def gate(self,stage='PRE_MAINNET_LAUNCH',operation='createSubnet'):
        return aws.ceremony_gate(self.m,'mainnet',stage,operation)

    def chain_ready(self):
        subnet='SYNTHETIC-SUBNET'
        self.e['subnetId']=subnet
        self.e['genesisPublic']['managerSubnetId']=subnet
        construction=self.read(self.r['construction']);construction['public']=copy.deepcopy(self.e['genesisPublic'])
        self.r['construction']=self.write(construction)
        self.change('securityReview',dict(subnetId=subnet,managerInitializedAtGenesis=True,constructionSha256=direct.sha(construction)))
        self.change('vmCompatibility',dict(subnetId=subnet,managerInitializedAtGenesis=True))
        item=self.r['transactions']['createChain'];req=self.read(item['request']);req['parameters']['subnetId']=subnet;item['request']=self.write(req)
        item['approval']=self.approve(dict(operation='createChain',networkId=1,accountId=self.m['accountId'],region=self.m['region'],requestSha256=direct.sha(req)))
        self.r['executionEvidence']=self.write(dict(networkId=1,chainId=self.e['evmChainId'],genesisSha256=self.e['genesisSha256'],subnetId=subnet,operations={'createSubnet':{'requestSha256':direct.sha(self.read(self.r['transactions']['createSubnet']['request'])),'accepted':True,'transactionId':'SYNTHETIC','subnetId':subnet}}))

    def test_pre_pass_without_fuji_or_future_receipts(self):
        self.assertFalse(self.m['environments']['fuji']['rehearsalPassed'])
        result=self.gate();self.assertEqual(result['status'],'PASS',result['blockers'])
        self.assertFalse(result['signing']);self.assertFalse(result['broadcastReady']);self.assertFalse(result['awsMutations'])
        self.assertIsNone(self.e['blockchainId']);self.assertIsNone(self.r['postEvidence']['path'])
        self.assertFalse(self.e['approvals']['nativeTransfers'])

    def test_create_subnet_does_not_read_unavailable_future_artifacts(self):
        self.e.update(subnetId=None,blockchainId=None,genesisSha256=None,genesisApproved=False,
            managerArtifactSha256=None,managerProxy=None,managerImplementation=None,managerLibrary=None,
            proxyAdmin=None,managerBootstrapReviewed=False,managerInitializationReviewed=False,
            genesisForksReviewed=False,signatureAggregatorUrl=None,validatorBalanceAVAX=None,pwGasSourceRole=None)
        for key in ('genesis','construction','securityReview','managerArtifact','vmCompatibility',
                    'commissioningPlan','executionEvidence','postEvidence','productionRecovery'):
            self.r[key]={'path':None,'sha256':None}
        for op in direct.OPERATIONS:
            if op!='createSubnet':self.r['transactions'][op]['request']={'path':None,'sha256':None}
        result=self.gate()
        self.assertEqual(result['status'],'PASS',result['blockers'])
        self.assertFalse(result['signing']);self.assertFalse(result['broadcastReady'])
        self.assertEqual(self.gate(operation='createChain')['status'],'BLOCKED')

    def test_later_genesis_finalization_does_not_rebind_subnet_approval(self):
        request=self.r['transactions']['createSubnet']['request']
        approval=copy.deepcopy(self.r['transactions']['createSubnet']['approval'])
        self.e['genesisSha256']='f'*64
        self.e['genesisApproved']=False
        self.assertEqual(self.gate()['status'],'PASS')
        self.assertEqual(self.r['transactions']['createSubnet']['request'],request)
        self.assertEqual(self.r['transactions']['createSubnet']['approval'],approval)
        self.assertEqual(self.gate(operation='createChain')['status'],'BLOCKED')

    def test_create_chain_requires_final_artifacts_and_subnet_initialization(self):
        self.chain_ready()
        self.assertEqual(self.gate(operation='createChain')['status'],'PASS')
        original=copy.deepcopy(self.e)
        for flag in ('genesisApproved','managerBootstrapReviewed','managerInitializationReviewed'):
            self.e[flag]=False
            self.assertEqual(self.gate(operation='createChain')['status'],'BLOCKED',flag)
            self.e[flag]=original[flag]
        for key in ('genesis','construction','managerArtifact','securityReview','vmCompatibility'):
            ref=self.r[key];self.r[key]={'path':None,'sha256':None}
            self.assertEqual(self.gate(operation='createChain')['status'],'BLOCKED',key);self.r[key]=ref
        for key,change in [('securityReview',{'managerInitializedAtGenesis':False}),
                           ('vmCompatibility',{'subnetId':'WRONG'}),
                           ('securityReview',{'subnetId':'WRONG'})]:
            old=self.r[key];self.change(key,change)
            self.assertEqual(self.gate(operation='createChain')['status'],'BLOCKED');self.r[key]=old

    def test_accepted_subnet_id_cannot_be_changed_or_inferred(self):
        self.chain_ready();old=self.r['executionEvidence']
        for field in ('subnetId','receiptSubnetId','accepted'):
            evidence=self.read(old)
            if field=='subnetId':evidence['subnetId']='WRONG'
            elif field=='receiptSubnetId':evidence['operations']['createSubnet']['subnetId']='WRONG'
            else:evidence['operations']['createSubnet']['accepted']=False
            self.r['executionEvidence']=self.write(evidence)
            self.assertEqual(self.gate(operation='createChain')['status'],'BLOCKED',field)
        self.r['executionEvidence']=old
        self.e['genesisPublic']['managerSubnetId']='WRONG'
        self.assertEqual(self.gate(operation='createChain')['status'],'BLOCKED')

    def test_pre_subnet_policy_cannot_waive_proxy_or_custody_security(self):
        plan_ref=self.r['preSubnetReview'];original_request=copy.deepcopy(self.r['transactions']['createSubnet'])
        for field in ('custodyVerified','fundingPlanReviewed','uninitializedPublicProxyForbidden','finalArtifactsRequiredBeforeCreateChain'):
            plan=self.read(plan_ref);plan[field]=False;self.r['preSubnetReview']=self.write(plan)
            # Even separately reapproving this transaction cannot waive the gate.
            request=self.read(original_request['request']);request['preSubnetReviewSha256']=direct.sha(plan)
            item=self.r['transactions']['createSubnet'];item['request']=self.write(request)
            item['approval']=self.approve(dict(operation='createSubnet',networkId=1,accountId=self.m['accountId'],region=self.m['region'],requestSha256=direct.sha(request)))
            self.assertEqual(self.gate()['status'],'BLOCKED',field)
        self.r['preSubnetReview']=plan_ref;self.r['transactions']['createSubnet']=original_request
        self.e['genesisPublic']['custodyProposalApproved']=False
        self.assertEqual(self.gate()['status'],'BLOCKED')

    def test_strategy_must_be_explicit(self):
        self.m.pop('deploymentStrategy');self.assertEqual(self.gate()['status'],'BLOCKED')

    def test_host_storage_identity_and_alert_evidence_required(self):
        for variant in ('missing','storage','identity','alert'):
            saved=copy.deepcopy(self.r['hostEvidence']);row=self.r['hostEvidence']['validator-1']
            if variant=='missing':row['cloud']={'path':None,'sha256':None}
            elif variant=='storage':
                v=self.read(row['local']);v['facts']['volumeSerials']=[];row['local']=self.write(v)
            else:
                v=self.read(row['operations']);v['certificateSha256']='bad' if variant=='identity' else v['certificateSha256'];v['alertDeliveryVerified']=variant!='alert';row['operations']=self.write(v)
            self.assertEqual(self.gate()['status'],'BLOCKED',variant);self.r['hostEvidence']=saved

    def test_custody_chain_governance_recovery_each_block(self):
        self.e['chainIdApproved']=False;self.assertEqual(self.gate()['status'],'BLOCKED');self.e['chainIdApproved']=True
        self.e['genesisPublic']['custodyProposalApproved']=False
        self.assertEqual(self.gate()['status'],'BLOCKED');self.e['genesisPublic']['custodyProposalApproved']=True
        self.m['operations']['offHostRecoveryVerified']=False
        self.assertEqual(self.gate()['status'],'BLOCKED')

    def test_uninitialized_manager_and_unsafe_governance_refused(self):
        self.chain_ready()
        self.assertEqual(self.gate(operation='createChain')['status'],'PASS')
        old=copy.deepcopy(self.r['securityReview']);self.change('securityReview',{'uninitializedProxyCallable':True})
        self.assertEqual(self.gate(operation='createChain')['status'],'BLOCKED');self.r['securityReview']=old
        review=self.read(old);review['governance']['threshold']=1;self.r['securityReview']=self.write(review)
        self.assertEqual(self.gate(operation='createChain')['status'],'BLOCKED')

    def test_each_transaction_needs_own_approval_and_previous_acceptance(self):
        self.chain_ready();item=self.r['transactions']['createChain'];approved=copy.deepcopy(item['approval'])
        item['approval']=copy.deepcopy(self.r['transactions']['createSubnet']['approval'])
        self.assertEqual(self.gate(operation='createChain')['status'],'BLOCKED')
        item['approval']=approved
        previous=copy.deepcopy(self.r['executionEvidence']);self.r['executionEvidence']={'path':None,'sha256':None}
        self.assertEqual(self.gate(operation='createChain')['status'],'BLOCKED')
        self.r['executionEvidence']=previous
        self.assertEqual(self.gate(operation='createChain')['status'],'PASS')
        self.r['transactions']['createSubnet']['approval']['approved']=False
        self.assertEqual(self.gate()['status'],'BLOCKED')

    def test_fuji_flags_cannot_authorize_mainnet(self):
        self.m['environments']['fuji']['rehearsalPassed']=True
        self.m['environments']['fuji']['approvals']={k:True for k in self.m['environments']['fuji']['approvals']}
        self.r['transactions']['createSubnet']['approval']['approved']=False
        self.assertEqual(self.gate()['status'],'BLOCKED')

    def test_post_flags_without_real_evidence_stay_blocked(self):
        self.e['approvals']['launch']=True;self.e['rehearsalPassed']=True
        self.r['postEvidence']=self.write({'accepted':True,'everythingPassed':True})
        self.assertEqual(self.gate('POST_MAINNET_ACCEPTANCE')['status'],'BLOCKED')

    def post_packet(self):
        self.chain_ready()
        self.e.update(blockchainId='SYNTHETIC-CHAIN',genesisBlockHash='0x'+'d'*64)
        receipt={'transactionHash':'0x'+'1'*64,'status':1,'blockHash':'0x'+'2'*64,'gasUsed':21000,'effectiveGasPrice':1}
        fee_receipt={'transactionHash':'0x'+'3'*64,'status':1}
        receipts=[receipt,fee_receipt]
        nodes={}
        for h in self.m['hosts']:
            nodes[h['name']]=dict(instanceId=h['instanceId'],nodeId=self.e['identities'][h['name']]['nodeId'],running=True,pChainHealthy=True,pChainSynced=True,registrationActive=True,weight=1,startAcceptedHeight=1,endAcceptedHeight=2,alertDelivered=True,monitoringHealthy=True,cpuMeanPercent=20,cpuP95Percent=30,memoryPeakPercent=40,diskPeakUsedPercent=20,iopsPeakPercentOfProvisioned=20,oomKills=0,nodeRestarts=0,swapInBytes=0,swapOutBytes=0,minimumNetworkMbps=30,confirmationP95Ms=2000,genesisBlockHash=self.e['genesisBlockHash'],acceptedBlockHeight=2,acceptedBlockHash='0x'+'2'*64,receiptSetSha256=direct.sha(receipts),receipts=copy.deepcopy(receipts))
        value=dict(networkId=1,chainId=self.e['evmChainId'],genesisSha256=self.e['genesisSha256'],blockchainId=self.e['blockchainId'],genesisBlockHash=self.e['genesisBlockHash'],observedAt=aws.now(),validators=nodes,durationSeconds=300,
            nativeTransfers=[dict(receipt,valueWei=10,bothNodesMatch=True,beforeBlock=1,afterBlock=2,senderBefore=100000,senderAfter=78990,recipientBefore=0,recipientAfter=10)],
            feeAccounting=dict(distributableWei=100,receiptStatus=1,transactionHash=fee_receipt['transactionHash'],bothNodesMatch=True,validatorDeltaWei=70,treasuryDeltaWei=20,burnDeltaWei=10,destinationsVerified=True,concurrentGasReconciled=True),
            recovery=dict(restoredSameIdentity=True,databasePreserved=True,fencingVerified=True,evidenceSha256='a'*64))
        return value

    def set_post(self,value):
        restored=dict(networkId=1,chainId=self.e['evmChainId'],genesisSha256=self.e['genesisSha256'],ownerReviewed=True,reference='SYNTHETIC-RESTORE',oldHostFenced=True,identities=self.e['identities'])
        self.r['productionRecovery']=self.write(restored)
        value['recovery']['evidenceSha256']=direct.sha(restored)
        self.r['postEvidence']=self.write(value)
        self.r['finalAcceptance']=self.approve(dict(stage='POST_MAINNET_ACCEPTANCE',networkId=1,evidenceSha256=direct.sha(value)))

    def test_post_requires_actual_receipt_arithmetic_registration_and_approval(self):
        value=self.post_packet();self.set_post(value)
        self.assertEqual(self.gate('POST_MAINNET_ACCEPTANCE')['status'],'PASS',self.gate('POST_MAINNET_ACCEPTANCE')['blockers'])
        for change in ('balance','receipt','weight','progress','pchain','fee','recovery','resource'):
            bad=copy.deepcopy(value)
            if change=='balance':bad['nativeTransfers'][0]['senderAfter']+=1
            if change=='receipt':bad['validators']['validator-2']['receipts']=[]
            if change=='weight':bad['validators']['validator-1']['weight']=2
            if change=='progress':bad['validators']['validator-1']['endAcceptedHeight']=1
            if change=='pchain':bad['validators']['validator-1']['pChainSynced']=False
            if change=='fee':bad['feeAccounting']['treasuryDeltaWei']=19
            if change=='recovery':bad['recovery']['databasePreserved']=False
            if change=='resource':bad['validators']['validator-1']['memoryPeakPercent']=90
            self.set_post(bad)
            self.assertEqual(self.gate('POST_MAINNET_ACCEPTANCE')['status'],'BLOCKED',change)
        self.set_post(value);self.r['finalAcceptance']['approved']=False
        self.assertEqual(self.gate('POST_MAINNET_ACCEPTANCE')['status'],'BLOCKED')

    def test_stale_collision_review_and_altered_genesis_rejected(self):
        old=copy.deepcopy(self.r['chainApproval']);self.change('chainApproval',{'checkedAt':'2020-01-01T00:00:00+00:00'})
        self.assertEqual(self.gate()['status'],'BLOCKED');self.r['chainApproval']=old
        self.chain_ready()
        g=self.read(self.r['genesis']);g['alloc'][next(iter(g['alloc']))]['balance']='0x1';self.r['genesis']=self.write(g)
        self.assertEqual(self.gate(operation='createChain')['status'],'BLOCKED')

    def test_expired_operation_approval_and_altered_fee_ceiling_rejected(self):
        a=self.r['transactions']['createSubnet']['approval'];a['expiresAt']='2020-01-01T00:00:00+00:00'
        self.assertEqual(self.gate()['status'],'BLOCKED')
        a['expiresAt']=(datetime.now(timezone.utc)+timedelta(hours=1)).isoformat()
        r=self.read(self.r['transactions']['createSubnet']['request']);r['maximumFeeAVAX']='0.2'
        self.r['transactions']['createSubnet']['request']=self.write(r)
        self.assertEqual(self.gate()['status'],'BLOCKED')

    def test_production_gates_cannot_be_disabled_by_python_optimization(self):
        import ast
        tree=ast.parse(Path(direct.__file__).read_text())
        self.assertFalse(any(isinstance(n,ast.Assert) for n in ast.walk(tree)))

    def test_readiness_does_not_call_aws_or_subprocess(self):
        with patch.object(aws,'aws') as api,patch.object(subprocess,'run') as execute:
            self.assertEqual(self.gate()['status'],'PASS');api.assert_not_called();execute.assert_not_called()

    def test_profile_selection_revokes_new_approvals(self):
        changed=aws.select_profile(self.m,'aws-m6a-xlarge-headroom')
        self.assertFalse(changed['mainnetReadiness']['transactions']['createSubnet']['approval']['approved'])

class HistoricalSafetyTests(unittest.TestCase):
    def test_committed_strategy_and_history_unchanged(self):
        for name in ('deployment.review.json','sydney.deployment.review.json'):
            m=json.loads((fixture.ROOT/'deploy/aws'/name).read_text());self.assertEqual(m['deploymentStrategy'],'DIRECT_MAINNET')
            self.assertTrue(all(not t['approval']['approved'] for t in m['mainnetReadiness']['transactions'].values()))
        m=json.loads(launch.MANIFEST.read_text());self.assertFalse(m['hostLaunchApprovals']['validator-2']['approved'])
        self.assertEqual(launch.digest(launch.reviewed_requests()[0]),'d585f3f6eb699f4c02def92de290533d5fb9588e56332420217d3e023c1fbce4')
        with self.assertRaises(ValueError):launch.prepare(m,True,'validator-1')

    def test_local_historical_files_match_review_index(self):
        index=json.loads((fixture.ROOT/'deploy/aws/sydney-history.index.json').read_text())
        available=False
        for name,digest in index['files'].items():
            path=fixture.ROOT/name
            if path.exists():
                available=True;self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(),digest,name)
        if not available:self.skipTest('Operator launch/stop evidence is local-only on this checkout')

    def test_reconciled_stopped_host_blocks_old_authorization_without_blocking_v2_review(self):
        m=json.loads((fixture.ROOT/'deploy/aws/sydney.existing-runtime.review.json').read_text())
        self.assertEqual(m['hosts'][0]['instanceId'],'i-0d2a9cee4dc9d9134')
        self.assertEqual(m['infrastructureEvidence']['validator1State'],'stopped')
        # Even a copied historical approval cannot bypass the existing-host guard.
        m['hostLaunchApprovals']['validator-1']['approved']=True
        with self.assertRaisesRegex(ValueError,'duplicate'):launch.prepare(m,True,'validator-1')
        self.assertEqual(len(launch.prepare(m,False,'validator-2')),1)
        with self.assertRaises(ValueError):launch.prepare(m,True,'validator-2')
