import copy
import importlib.util
import json
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('netcup',ROOT/'scripts/deploy/render_netcup.py')
netcup=importlib.util.module_from_spec(spec);spec.loader.exec_module(netcup)


class NetcupAutomationTests(unittest.TestCase):
    def setUp(self):
        # Public syntactic fixtures only; no network calls or provisioning.
        self.s={'purpose':'fuji-rehearsal','hosts':[{'name':'validator-1','publicIp':'8.8.8.8'},{'name':'validator-2','publicIp':'1.1.1.1'}],
                'adminSshCidrs':['9.9.9.9/32'],'adminPublicKeys':['ssh-ed25519 AAAATESTONLY fixture'],
                'pilotRiskAccepted':True,'expectedValidators':2,'provisionApproved':True,
                'adminUser':'pwadmin','persistentMount':'/var/lib'}

    def test_provision_does_not_implicitly_create_keys_or_start(self):
        v=netcup.render(self.s)['all']['children']['primewave_pilot']['vars']
        self.assertEqual(v['public_network'],'fuji')
        self.assertFalse(v['start_node']);self.assertFalse(v['create_identities'])

    def test_actual_review_inputs_refuse_unapproved_provision(self):
        with self.assertRaises((ValueError,TypeError)):
            netcup.render(json.loads((ROOT/'deploy/netcup/settings.review.json').read_text()))

    def test_explicit_provision_approval_required(self):
        self.s['provisionApproved']=False
        with self.assertRaisesRegex(ValueError,'authorization'):netcup.render(self.s)

    def test_start_requires_identity_and_recovery_approvals(self):
        self.s['hostStartApproved']=True
        with self.assertRaisesRegex(ValueError,'Start requires'):netcup.render(self.s)
        self.s.update(identityCreationApproved=True,offHostRecoveryConfirmed=True)
        self.assertTrue(netcup.render(self.s)['all']['children']['primewave_pilot']['vars']['start_node'])

    def test_private_or_duplicate_hosts_refused(self):
        for ip in ['127.0.0.1','192.168.1.1','8.8.8.8']:
            self.s['hosts'][1]['publicIp']=ip
            with self.assertRaises(ValueError):netcup.render(self.s)

    def test_unrestricted_ssh_or_private_key_material_refused(self):
        self.s['adminSshCidrs']=['0.0.0.0/0']
        with self.assertRaises(ValueError):netcup.render(self.s)
        self.s['adminSshCidrs']=['9.9.9.9/32']
        self.s['adminPublicKeys']=['-----BEGIN PRIVATE KEY-----']
        with self.assertRaises(ValueError):netcup.render(self.s)

    def test_unsafe_storage_roots_refused(self):
        for path in ['relative','/tmp/run','/var/../root','/var/lib\nmalformed']:
            self.s['persistentMount']=path
            with self.assertRaises(ValueError):netcup.render(self.s)

    def test_no_automatic_network_fallback(self):
        self.s['purpose']='local'
        with self.assertRaises(ValueError):netcup.render(self.s)

    def test_automation_uses_private_rpc_and_persistent_identity(self):
        source=(ROOT/'deploy/netcup/pilot.yml').read_text()
        for marker in ['"http-host": "127.0.0.1"','"staking-port": 9651','"partial-sync-primary-network": true',
                       'staking/public-identity.json','Refusing to adopt any existing unmanaged runtime','offhost_recovery_confirmed']:
            self.assertIn(marker,source)
        self.assertNotIn('staking-ephemeral',source)
        self.assertNotIn('genesis-file',source)
