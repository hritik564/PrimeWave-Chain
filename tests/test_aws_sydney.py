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

    def test_real_export_refuses_missing_or_incomplete_consent(self):
        for stage in range(3):
            with self.assertRaisesRegex(ValueError,'spending'):launch.prepare(self.m,True)
            if stage==0:self.m['awsLaunchApprovals']['ec2LaunchAuthorized']=True
            if stage==1:self.m['ec2Preparation']['spendingApprovalReference']='SYNTHETIC-OFFLINE-TEST'

    def test_approved_export_only_changes_dryrun_and_adds_idempotency(self):
        self.m['awsLaunchApprovals']['ec2LaunchAuthorized']=True
        self.m['ec2Preparation'].update(spendingApprovalReference='SYNTHETIC-OFFLINE-TEST',launchPayloadsSha256=launch.digest(launch.reviewed_requests()))
        result=launch.prepare(self.m,True)
        self.assertEqual(result,launch.prepare(self.m,True))
        for r,original in zip(result,launch.reviewed_requests()):
            self.assertFalse(r.pop('DryRun'));self.assertEqual(len(r.pop('ClientToken')),64)
            original.pop('DryRun');self.assertEqual(r,original)

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
