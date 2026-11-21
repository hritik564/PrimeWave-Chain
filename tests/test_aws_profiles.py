import copy
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import test_aws_pilot as fixtures
aws,ROOT=fixtures.aws,fixtures.ROOT


class AwsProfileTests(unittest.TestCase):
    def setUp(self):
        fixture=fixtures.AwsPilotTests();fixture.setUp()
        self.m,self.cloud,self.local=fixture.m,fixture.cloud,fixture.local

    def small(self):
        self.m=aws.select_profile(self.m,'aws-m6a-large-low-throughput')
        self.cloud['instance'].update(InstanceType='m6a.large',CpuOptions={'CoreCount':1,'ThreadsPerCore':2})
        self.local.update(deploymentProfile=self.m['deploymentProfile'])
        self.local['facts'].update(cpuCores=2,physicalCores=1,ramGiB=7.7)
        self.local['facts']['identityDocument']['instanceType']='m6a.large'

    def gate(self):return aws.host_gate(self.m,'validator-1',self.cloud,self.local)

    def test_xlarge_preserved_and_no_profile_fallback(self):
        self.assertEqual(aws.selected_profile(self.m)['instanceType'],'m6a.xlarge')
        self.assertEqual(self.gate()['status'],'PASS')
        self.m.pop('deploymentProfile')
        with self.assertRaisesRegex(ValueError,'Explicit supported'):aws.selected_profile(self.m)

    def test_small_uses_profile_specific_cpu_ram_and_quota(self):
        self.small()
        result=self.gate();self.assertEqual(result['status'],'PASS',result['blockers'])
        q=aws.quota_report(self.m);self.assertEqual(q['pairVcpus'],4);self.assertTrue(q['fitsReportedQuotaForNewPair'])

    def test_xlarge_does_not_fit_reported_quota(self):
        q=aws.quota_report(self.m)
        self.assertEqual(q['pairVcpus'],8);self.assertFalse(q['fitsReportedQuotaForNewPair'])

    def test_small_missing_cpu_memory_or_topology_is_refused(self):
        self.small()
        for key,value in [('cpuCores',1),('ramGiB',7.49),('physicalCores',0)]:
            old=self.local['facts'][key];self.local['facts'][key]=value
            self.assertEqual(self.gate()['status'],'FAIL');self.local['facts'][key]=old

    def test_small_evidence_cannot_pass_xlarge(self):
        self.small();self.m=aws.select_profile(self.m,'aws-m6a-xlarge-headroom')
        self.assertEqual(self.gate()['status'],'FAIL')

    def test_storage_security_and_partial_sync_are_not_relaxed(self):
        self.small()
        for field,value in [('diskFreeGiB',99),('diskReadIops',2699),('diskReadLatencyMs',10.1),('rpcPublicListener',True),('firewallDefaultDeny',False)]:
            old=self.local['facts'][field];self.local['facts'][field]=value
            self.assertEqual(self.gate()['status'],'FAIL');self.local['facts'][field]=old
        self.local['facts']['nodeConfig']['partialSyncPrimaryNetwork']=False
        self.assertEqual(self.gate()['status'],'FAIL')

    def test_declared_flag_not_enough_when_service_uses_other_config(self):
        self.local['facts']['nodeConfig']['serviceUsesReviewedConfig']=False
        self.assertEqual(self.gate()['status'],'FAIL')

    def test_real_systemd_command_cannot_override_partial_sync(self):
        path='/etc/primewave/mainnet-pilot.json'
        unit='{ path=/opt/primewave/releases/v1.15.1/avalanchego ; argv[]=/opt/primewave/releases/v1.15.1/avalanchego --config-file='+path+' ; ignore_errors=no ; }'
        self.assertTrue(aws.service_config_matches(unit,path))
        self.assertFalse(aws.service_config_matches(unit.replace(' ; ignore_errors',' --partial-sync-primary-network=false ; ignore_errors'),path))

    def test_inventory_carries_hardware_thresholds_without_starting(self):
        self.small();self.m['automation'].update(provisionApproved=True,transferBucketReviewed=True,ssmTransferBucket='FIXTURE',ssmKmsKeyArn='FIXTURE')
        v=aws.inventory(self.m,'mainnet')['all']['children']['primewave_pilot']['vars']
        self.assertEqual((v['minimum_vcpus'],v['minimum_memory_mib']),(2,7680))
        self.assertEqual(v['disk_min_read_iops'],2700)
        self.assertFalse(v['create_identities']);self.assertFalse(v['start_node'])

    def test_profile_selection_revokes_execution_approvals_but_preserves_identity(self):
        self.m['automation']['provisionApproved']=True
        self.m['awsLaunchApprovals'].update(accountVerified=True,ec2LaunchAuthorized=True)
        self.m['environments']['mainnet']['approvals']['launch']=True
        changed=aws.select_profile(self.m,'aws-m6a-large-low-throughput')
        self.assertFalse(changed['automation']['provisionApproved'])
        self.assertTrue(changed['awsLaunchApprovals']['accountVerified'])
        self.assertFalse(changed['awsLaunchApprovals']['ec2LaunchAuthorized'])
        self.assertFalse(changed['environments']['mainnet']['approvals']['launch'])
        self.assertEqual(changed['hosts'],self.m['hosts'])
        self.assertEqual(changed['environments']['mainnet']['identities'],self.m['environments']['mainnet']['identities'])

    def evidence(self):
        rows=[]
        for h in self.m['hosts']:
            rows.append(dict({k:h[k] for k in ('name','instanceId','dataVolumeId','filesystemUuid','availabilityZone')},durationSeconds=3600,acceptedTps=5,acceptedTransactions=18000,submittedTransactions=18000,failedReceipts=0,representativeContractCalls=True,cpuMeanPercent=50,cpuP95Percent=75,memoryPeakPercent=65,oomKills=0,nodeRestarts=0,swapInBytes=0,swapOutBytes=0,diskPeakUsedPercent=25,iopsPeakPercentOfProvisioned=50,minimumNetworkMbps=30,confirmationP95Ms=2000,startAcceptedHeight=1,endAcceptedHeight=1801,alertDeliveryVerified=True))
        return dict(schema='primewave-small-profile-workload-v1',deploymentProfile=self.m['deploymentProfile'],environment='fuji',observedAt=aws.now(),chainId=73571002,genesisSha256='a'*64,hosts=rows)

    def test_small_production_requires_physical_core_risk_and_actual_bound_metrics(self):
        self.small()
        self.assertTrue(aws.small_workload_errors(self.m))
        self.m['environments']['fuji'].update(evmChainId=73571002,genesisSha256='a'*64)
        evidence=self.evidence()
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp).resolve()/'public-workload.json'
            def write():
                path.write_text(json.dumps(evidence));self.m['smallProfileProduction'].update(ownerApproved=True,physicalCoreExceptionAccepted=True,workloadEvidenceFile=str(path),workloadEvidenceSha256=hashlib.sha256(path.read_bytes()).hexdigest())
            write();self.assertEqual(aws.small_workload_errors(self.m),[])
            evidence['hosts'][1]['memoryPeakPercent']=90;write()
            self.assertTrue(aws.small_workload_errors(self.m))
            evidence['hosts'][1]['memoryPeakPercent']=65;evidence['hosts'][0]['dataVolumeId']='WRONG';write()
            self.assertTrue(aws.small_workload_errors(self.m))

    def test_profile_cli_is_local_only_and_preserves_input(self):
        source=ROOT/'deploy/aws/deployment.review.json';before=source.read_bytes()
        result=subprocess.run([sys.executable,str(ROOT/'scripts/deploy/aws_pilot.py'),'--manifest',str(source),'--select-profile','aws-m6a-large-low-throughput'],capture_output=True,text=True,check=True)
        self.assertEqual(json.loads(result.stdout)['target']['instanceType'],'m6a.large')
        self.assertEqual(source.read_bytes(),before)
