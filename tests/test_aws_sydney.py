import copy
import json
import sys
import unittest
from unittest.mock import patch
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts/deploy'))
import aws_launch_prepare as launch
import test_aws_pilot as fixtures
aws=fixtures.aws

class SydneyTests(unittest.TestCase):
    def setUp(self):
        self.m=json.loads(launch.MANIFEST.read_text())

    def test_default_requests_exactly_match_successful_dry_runs(self):
        self.assertEqual(launch.prepare(self.m),launch.reviewed_requests())
        self.assertTrue(all(r['DryRun'] is True for r in launch.prepare(self.m)))

    def approve(self,host):
        from datetime import datetime,timezone,timedelta
        now=datetime.now(timezone.utc)
        self.m['hostLaunchApprovals'][host].update(approved=True,reference='SYNTHETIC-OFFLINE-TEST',
            issuedAt=(now-timedelta(minutes=1)).isoformat(),expiresAt=(now+timedelta(hours=1)).isoformat())

    def test_real_export_refuses_global_pair_consent(self):
        self.m['awsLaunchApprovals']['ec2LaunchAuthorized']=True
        with self.assertRaisesRegex(ValueError,'host-specific'):launch.prepare(self.m,True)

    def test_validator_one_only_approval_exports_only_one(self):
        self.approve('validator-1')
        result=launch.prepare(self.m,True,'validator-1')
        self.assertEqual(len(result),1)
        original=launch.reviewed_requests()[0];r=result[0]
        self.assertFalse(r.pop('DryRun'));self.assertEqual(len(r.pop('ClientToken')),64)
        original.pop('DryRun');self.assertEqual(r,original)
        with self.assertRaisesRegex(ValueError,'validator-2'):launch.prepare(self.m,True,'validator-2')
        with self.assertRaisesRegex(ValueError,'validator-2'):launch.prepare(self.m,True)

    def test_pair_requires_both_independent_approvals(self):
        self.approve('validator-1');self.approve('validator-2')
        result=launch.prepare(self.m,True)
        self.assertEqual(len(result),2)
        self.assertNotEqual(result[0]['ClientToken'],result[1]['ClientToken'])

    def test_approval_missing_altered_expired_or_future_rejected(self):
        from datetime import datetime,timezone,timedelta
        self.approve('validator-1');good=copy.deepcopy(self.m)
        for key in ('host','accountId','region','instanceType','securityGroupIds','instanceProfileArn','requestSha256'):
            self.m=copy.deepcopy(good);self.m['hostLaunchApprovals']['validator-1']['binding'][key]='ALTERED'
            with self.subTest(key=key),self.assertRaises(ValueError):launch.prepare(self.m,True,'validator-1')
        now=datetime.now(timezone.utc)
        for changes in ({'approved':False},{'reference':None},{'expiresAt':(now-timedelta(seconds=1)).isoformat()},
            {'issuedAt':(now+timedelta(minutes=1)).isoformat()}, {'expiresAt':(now+timedelta(days=2)).isoformat()},
            {'expiresAt':'invalid'},{'issuedAt':now.replace(tzinfo=None).isoformat()}):
            self.m=copy.deepcopy(good);self.m['hostLaunchApprovals']['validator-1'].update(changes)
            with self.subTest(changes=changes),self.assertRaises(ValueError):launch.prepare(self.m,True,'validator-1')
        self.m=copy.deepcopy(good);del self.m['hostLaunchApprovals']['validator-1']
        with self.assertRaises(ValueError):launch.prepare(self.m,True,'validator-1')

    def test_idempotency_survives_approval_renewal(self):
        self.approve('validator-1');first=launch.prepare(self.m,True,'validator-1')
        self.approve('validator-1');self.m['hostLaunchApprovals']['validator-1']['reference']='RENEWED-TEST'
        self.assertEqual(first,launch.prepare(self.m,True,'validator-1'))

    def test_recorded_first_host_does_not_block_second(self):
        self.m['hosts'][0].update(instanceId='i-recorded',dataVolumeId='vol-recorded',rootVolumeId='vol-root',launchRecord={'status':'launched'})
        self.approve('validator-2')
        self.assertEqual(len(launch.prepare(self.m,True,'validator-2')),1)
        with self.assertRaisesRegex(ValueError,'duplicate'):launch.prepare(self.m,True,'validator-1')
        with self.assertRaisesRegex(ValueError,'duplicate'):launch.prepare(self.m,True)

    def test_record_alone_blocks_relaunch(self):
        self.m['hosts'][0]['launchRecord']={'status':'request-submitted-outcome-unknown'}
        with self.assertRaisesRegex(ValueError,'duplicate'):launch.prepare(self.m,False,'validator-1')

    def test_changed_request_cannot_be_approved(self):
        requests=launch.reviewed_requests();requests[0]['BlockDeviceMappings'][1]['Ebs']['Encrypted']=False
        with patch.object(launch,'reviewed_requests',return_value=requests):
            with self.assertRaisesRegex(ValueError,'digest'):launch.prepare(self.m,False,'validator-1')

    def test_cli_one_host_writes_only_one_dryrun_and_refuses_real_output(self):
        import tempfile,subprocess
        with tempfile.TemporaryDirectory() as directory:
            out=Path(directory)/'export'
            command=[sys.executable,str(launch.ROOT/'scripts/deploy/aws_launch_prepare.py'),
                '--manifest',str(launch.MANIFEST),'--host','validator-1','--output-dir',str(out)]
            p=subprocess.run(command,capture_output=True,text=True)
            self.assertEqual(p.returncode,0,p.stderr)
            self.assertEqual([p.name for p in out.iterdir()],['validator-1.json'])
            self.assertTrue(json.loads((out/'validator-1.json').read_text())['DryRun'])
            refused=Path(directory)/'refused';command[-1]=str(refused)
            p=subprocess.run(command+['--approved-real-launch'],capture_output=True,text=True)
            self.assertNotEqual(p.returncode,0);self.assertFalse(refused.exists())

    def test_real_cli_host_scope_and_atomic_pair_refusal(self):
        import tempfile,subprocess
        self.approve('validator-1')
        with tempfile.TemporaryDirectory() as directory:
            manifest=Path(directory)/'approved.json';manifest.write_text(json.dumps(self.m))
            out=Path(directory)/'one'
            base=[sys.executable,str(launch.ROOT/'scripts/deploy/aws_launch_prepare.py'),
                '--manifest',str(manifest),'--approved-real-launch','--output-dir',str(out)]
            p=subprocess.run(base+['--host','validator-1'],capture_output=True,text=True)
            self.assertEqual(p.returncode,0,p.stderr)
            self.assertEqual([x.name for x in out.iterdir()],['validator-1.json'])
            self.assertEqual(json.loads(p.stdout)['selectedHosts'],['validator-1'])
            self.assertFalse(json.loads((out/'validator-1.json').read_text())['DryRun'])
            pair=Path(directory)/'pair';base[-1]=str(pair)
            p=subprocess.run(base,capture_output=True,text=True)
            self.assertNotEqual(p.returncode,0);self.assertFalse(pair.exists())

    def test_reordered_manifest_uses_names_not_positions(self):
        self.m['hosts'].reverse();self.approve('validator-1')
        r=launch.prepare(self.m,True,'validator-1')[0]
        self.assertEqual(r['Placement']['AvailabilityZone'],'ap-southeast-2a')

    def test_unverified_account_or_copied_approval_refused(self):
        self.approve('validator-1')
        self.m['hostLaunchApprovals']['validator-2']=copy.deepcopy(self.m['hostLaunchApprovals']['validator-1'])
        with self.assertRaises(ValueError):launch.prepare(self.m,True,'validator-2')
        self.m['awsLaunchApprovals']['accountVerified']=False
        with self.assertRaises(ValueError):launch.prepare(self.m,True,'validator-1')

    def test_unsafe_resource_or_duplicate_launch_refused(self):
        for key,value in [('securityGroupIds',['sg-wrong']),('instanceProfileArn','wrong'),('instanceId','i-existing'),('subnetId','subnet-wrong')]:
            m=copy.deepcopy(self.m);m['hosts'][0][key]=value
            with self.assertRaises(ValueError):launch.prepare(m)

    def test_manifest_is_not_host_or_chain_ready(self):
        self.assertTrue(aws.manifest_errors(self.m))
        self.assertEqual(aws.ceremony_gate(self.m,'mainnet')['status'],'BLOCKED')
        self.assertFalse(self.m['automation']['provisionApproved'])

    def test_sydney_host_gate_keeps_all_thresholds(self):
        f=fixtures.AwsPilotTests();f.setUp();m=f.m
        m['region']='ap-southeast-2'
        for n,h in enumerate(m['hosts']):h.update(region=m['region'],availabilityZone=m['region']+('a' if n==0 else 'b'))
        f.cloud.update(region=m['region']);f.cloud['instance']['Placement']['AvailabilityZone']=m['hosts'][0]['availabilityZone']
        f.cloud['volumes'][0]['AvailabilityZone']=m['hosts'][0]['availabilityZone']
        f.local['facts']['identityDocument'].update(region=m['region'],availabilityZone=m['hosts'][0]['availabilityZone'])
        self.assertEqual(f.gate()['status'],'PASS')
        f.local['facts']['diskReadIops']=2699
        self.assertEqual(f.gate()['status'],'FAIL')
        f.local['facts']['diskReadIops']=3000;m['hosts'][0]['availabilityZone']='ap-south-1a'
        self.assertEqual(f.gate()['status'],'FAIL')

    def test_unsupported_region_refused(self):
        self.m['region']='us-east-1'
        self.assertTrue(any('supported AWS region' in e for e in aws.manifest_errors(self.m)))
