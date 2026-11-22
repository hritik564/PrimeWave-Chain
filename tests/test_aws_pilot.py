import copy
from datetime import datetime,timedelta,timezone
import importlib.util
import json
from pathlib import Path
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('aws_pilot',ROOT/'scripts/deploy/aws_pilot.py')
aws=importlib.util.module_from_spec(spec);spec.loader.exec_module(aws)


class AwsPilotTests(unittest.TestCase):
    def setUp(self):
        # Synthetic API fixtures only: these IPs/IDs are NEVER queried.
        self.m=json.loads((ROOT/'deploy/aws/deployment.review.json').read_text())
        self.m.update(accountId='111111111111',operatorProfile='fixture-readonly')
        self.m['serviceIdentity']={'uid':999,'gid':999} # synthetic test IDs only
        self.m['operations'].update(rootVolumePlanApproved=True,sessionAuditApproved=True,storageGrowthPlanApproved=True,monitoringApproved=True)
        self.m['operations']['alertDestination']='FIXTURE-ALERT-DESTINATION'
        for n,h in enumerate(self.m['hosts'],1):
            h.update(instanceId='i-'+str(n)*17,availabilityZone='ap-south-1'+('a' if n==1 else 'b'),privateIp=f'10.0.{n}.10',publicIp='8.8.8.8' if n==1 else '1.1.1.1',dataVolumeId='vol-'+str(n+2)*17,rootVolumeId='vol-'+str(n+4)*17,filesystemUuid=f'00000000-0000-0000-0000-{n:012d}',persistentMount='/mnt/pwdata',securityGroupIds=['sg-fixture'+str(n)],instanceProfileArn='arn:aws:iam::111111111111:instance-profile/FIXTURE')
            h['privateEndpoint'].update(ssmTargetInstanceId=h['instanceId'],operatorTunnelPort=19650 if n==1 else 29650)
            h['publicP2pEndpoint']=h['publicIp']+':9651'
            h['dataLifecycle']='new'
        h=self.m['hosts'][0]
        self.cloud=dict(observedAt=aws.now(),accountId=self.m['accountId'],region='ap-south-1',host='validator-1',
            instance=dict(InstanceId=h['instanceId'],InstanceType='m6a.xlarge',Architecture='x86_64',PublicIpAddress=h['publicIp'],PrivateIpAddress=h['privateIp'],Placement={'AvailabilityZone':h['availabilityZone']},State={'Name':'running'},CpuOptions={'CoreCount':2,'ThreadsPerCore':2},MetadataOptions={'HttpTokens':'required'},IamInstanceProfile={'Arn':h['instanceProfileArn']},SecurityGroups=[{'GroupId':h['securityGroupIds'][0]}],RootDeviceName='/dev/sda1',BlockDeviceMappings=[{'DeviceName':'/dev/sda1','Ebs':{'VolumeId':h['rootVolumeId']}},{'DeviceName':'/dev/sdf','Ebs':{'VolumeId':h['dataVolumeId'],'DeleteOnTermination':False}}]),
            volumes=[dict(VolumeId=h['dataVolumeId'],Encrypted=True,VolumeType='gp3',Size=150,Iops=3000,Throughput=125,AvailabilityZone=h['availabilityZone'],Attachments=[{'InstanceId':h['instanceId'],'State':'attached'}])],
            securityGroups=[{'GroupId':h['securityGroupIds'][0],'IpPermissions':[{'IpProtocol':'tcp','FromPort':9651,'ToPort':9651,'IpRanges':[{'CidrIp':'0.0.0.0/0'}]}]}],ssm=[{'InstanceId':h['instanceId'],'PingStatus':'Online','PlatformName':'Ubuntu','PlatformVersion':'24.04'}])
        facts=dict(physicalCores=2,nodeConfig={'partialSyncPrimaryNetwork':True,'sybilProtectionEnabled':True,'rpcBind':'127.0.0.1','apiAdminEnabled':False,'networkId':'mainnet','serviceUsesReviewedConfig':True},os='Ubuntu',osVersion='24.04',architecture='x86_64',cpuCores=4,ramGiB=15.5,diskGiB=147,diskFreeGiB=130,persistentStorageVerified=True,mount={'target':h['persistentMount'],'uuid':h['filesystemUuid']},volumeSerials=[h['dataVolumeId'].replace('-','')],fstabUuidVerified=True,diskReadIops=2950,diskReadLatencyMs=1,ssmAgentActive=True,firewallDefaultDeny=True,noSshFirewallAllow=True,noPublicRpcFirewallAllow=True,timeSyncActive=True,monitoringActive=True,sshListening=False,rpcPublicListener=False,identityDocument=dict(accountId=self.m['accountId'],instanceId=h['instanceId'],region='ap-south-1',availabilityZone=h['availabilityZone'],instanceType='m6a.xlarge',privateIp=h['privateIp']))
        self.local=dict(observedAt=aws.now(),host='validator-1',environment='mainnet',deploymentProfile=self.m['deploymentProfile'],facts=facts)

    def gate(self):return aws.host_gate(self.m,'validator-1',self.cloud,self.local)

    def test_complete_host_pass_is_not_transaction_authorization(self):
        result=self.gate();self.assertEqual(result['status'],'PASS',result['blockers'])
        self.assertIn('not identity/transaction/launch',result['scope'])

    def test_placeholder_manifest_fails_without_any_aws_calls(self):
        m=json.loads((ROOT/'deploy/aws/deployment.review.json').read_text())
        with patch.object(aws,'aws') as execute:
            with self.assertRaises(ValueError):aws.collect_cloud(m,'validator-1')
            execute.assert_not_called()
        self.assertEqual(aws.host_gate(m,'validator-1',{}, {})['status'],'FAIL')

    def test_cross_account_or_local_instance_mismatch_fails(self):
        self.local['facts']['identityDocument']['instanceId']='i-'+'a'*17
        self.assertEqual(self.gate()['status'],'FAIL')

    def test_separate_azs_are_required(self):
        self.m['hosts'][1]['availabilityZone']='ap-south-1a'
        self.assertTrue(any('availabilityZone' in x for x in self.gate()['blockers']))

    def test_ebs_retention_and_encryption_fail_closed(self):
        for change in ('encryption','termination','wrong-volume'):
            with self.subTest(change=change):
                original=copy.deepcopy(self.cloud)
                if change=='encryption':self.cloud['volumes'][0]['Encrypted']=False
                if change=='termination':self.cloud['instance']['BlockDeviceMappings'][1]['Ebs']['DeleteOnTermination']=True
                if change=='wrong-volume':self.local['facts']['volumeSerials']=['volWRONG']
                self.assertEqual(self.gate()['status'],'FAIL')
                self.cloud=original

    def test_root_fallback_or_missing_benchmark_fails(self):
        self.local['facts']['mount']['target']='/'
        self.assertEqual(self.gate()['status'],'FAIL')
        self.local['facts']['mount']['target']='/mnt/pwdata'
        self.local['facts'].pop('diskReadIops')
        self.assertEqual(self.gate()['status'],'FAIL')

    def test_combined_security_groups_cannot_open_ssh_or_rpc(self):
        for port in (22,9650,9100):
            with self.subTest(port=port):
                rule={'IpProtocol':'tcp','FromPort':port,'ToPort':port,'IpRanges':[{'CidrIp':'10.0.0.0/8'}]}
                self.cloud['securityGroups'][0]['IpPermissions'].append(rule)
                self.assertEqual(self.gate()['status'],'FAIL')
                self.cloud['securityGroups'][0]['IpPermissions'].pop()

    def test_unmanaged_or_unhardened_host_fails(self):
        self.cloud['ssm'][0]['PingStatus']='ConnectionLost'
        self.local['facts']['sshListening']=True
        self.assertEqual(self.gate()['status'],'FAIL')

    def test_stale_evidence_fails(self):
        self.local['observedAt']=(datetime.now(timezone.utc)-timedelta(days=2)).isoformat()
        self.assertEqual(self.gate()['status'],'FAIL')

    def test_inventory_only_uses_ssm_and_cannot_create_keys_or_start(self):
        self.m['automation'].update(provisionApproved=True,transferBucketReviewed=True,ssmTransferBucket='fixture-bucket',ssmKmsKeyArn='arn:aws:kms:ap-south-1:111111111111:key/fixture')
        v=aws.inventory(self.m,'mainnet')['all']['children']['primewave_pilot']['vars']
        self.assertEqual(v['ansible_connection'],'amazon.aws.aws_ssm')
        self.assertFalse(v['create_identities']);self.assertFalse(v['start_node'])
        self.assertNotIn('admin_public_keys',v)
        self.assertEqual(v['ansible_aws_ssm_region'],'ap-south-1')

    def test_inventory_without_explicit_approval_refused(self):
        with self.assertRaisesRegex(ValueError,'provisioning'):aws.inventory(self.m,'mainnet')

    def test_no_production_secrets_accepted(self):
        self.m['privateKey']='not-even-a-real-key'
        with self.assertRaisesRegex(ValueError,'credentials forbidden'):aws.manifest_errors(self.m)

    def test_mainnet_is_blocked_by_actual_missing_evidence_not_fuji(self):
        result=aws.ceremony_gate(self.m,'mainnet')
        self.assertEqual(result['status'],'BLOCKED');self.assertFalse(result['broadcastReady'])
        self.assertTrue(any('host validator-1' in x for x in result['blockers']))
        self.assertFalse(any('Fuji transaction' in x for x in result['blockers']))

    def test_fuji_cannot_reuse_mainnet_public_identity(self):
        for env in self.m['environments'].values():
            for n,i in enumerate(env['identities'].values()):i.update(nodeId='NodeID-'+str(n),blsPublicKey='PUBLIC'+str(n),proofOfPossession='PROOF'+str(n),stakingCertificateSha256=str(n)*64)
        self.assertTrue(any('never reuse Fuji/Mainnet' in x for x in aws.ceremony_gate(self.m,'fuji')['blockers']))

    def test_both_providers_share_one_validator_implementation(self):
        for provider in ('aws','netcup'):
            self.assertIn('import_playbook: ../common/validator.yml',(ROOT/f'deploy/{provider}/pilot.yml').read_text())
        template=(ROOT/'deploy/common/primewave.service.j2').read_text()
        self.assertIn('ConditionPathIsMountPoint=',template)
        self.assertIn('--storage-binding',template)

    def test_cloud_account_checked_before_describe(self):
        with patch.object(aws,'aws',return_value={'Account':'222222222222'}) as call:
            with self.assertRaisesRegex(ValueError,'account mismatch'):aws.collect_cloud(self.m,'validator-1')
            self.assertEqual(call.call_count,1)

    def test_rpc_has_no_demo_or_public_endpoint_fallback(self):
        with self.assertRaises(ValueError):aws.rpc_check(self.m,'validator-1','mainnet')
        e=self.m['environments']['mainnet'];e.update(evmChainId=73571001,blockchainId='A'*50)
        with patch.object(aws.rpc_module,'check',return_value='0x2') as check:
            result=aws.rpc_check(self.m,'validator-1','mainnet')
            check.assert_called_once_with('http://127.0.0.1:19650/ext/bc/'+'A'*50+'/rpc',73571001)
            self.assertEqual(result['status'],'PASS')
