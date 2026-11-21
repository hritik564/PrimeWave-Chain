import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
MODULES=ROOT/'scripts/mainnet'
sys.path.insert(0,str(MODULES))
import chain_id
import validate_genesis
import validator
import fuji_rehearsal

SPEC=importlib.util.spec_from_file_location('binary_verify',MODULES/'verify-binaries.py')
binary_verify=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(binary_verify)
SPEC=importlib.util.spec_from_file_location('host_preflight',MODULES/'preflight.py')
preflight=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(preflight)


class ResolutionTests(unittest.TestCase):
    def test_collision_and_reserved_ids(self):
        for value in (73571,77,1337,43114,True,-1,2**53,'73571001'):
            with self.subTest(value=value),self.assertRaises(ValueError):
                chain_id.check_candidate(value,[{'chainId':43114}])
        with self.assertRaises(ValueError):
            chain_id.check_candidate(73571001,[{'chainId':73571001}])
        chain_id.check_candidate(73571001,[{'chainId':43114}])

    def test_chain_approval_and_digest_gates(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'registry.json';path.write_text('[{"chainId":43114}]')
            evidence=chain_id.evidence(73571001,path)
            with self.assertRaises(ValueError):chain_id.approved(evidence,path)
            evidence.update(ownerApproved=True,approvedChainId=73571001)
            self.assertEqual(chain_id.approved(evidence,path),73571001)
            path.write_text('[{"chainId":73571001}]')
            with self.assertRaises(ValueError):chain_id.approved(evidence,path)

    def test_stale_registry_evidence_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'registry.json';path.write_text('[{"chainId":43114}]')
            data=chain_id.evidence(73571001,path)
            data.update(ownerApproved=True,approvedChainId=73571001,checkedAt='2020-01-01T00:00:00+00:00')
            with self.assertRaises(ValueError):chain_id.approved(data,path)

    def test_genesis_supply_policy_no_mint_and_chain_checks(self):
        policy={'rewards':15000000,'other':85000000}
        addresses={'rewards':'0x'+'11'*20,'other':'0x'+'22'*20}
        genesis={'config':{'chainId':73571001,'feeConfig':{},'rewardManagerConfig':{'initialRewardConfig':{'rewardAddress':'0x'+'33'*20}}},
                 'gasLimit':'0x1','alloc':{addresses[k]:{'balance':hex(v*10**18)} for k,v in policy.items()}}
        self.assertEqual(validate_genesis.validate(genesis,73571001,policy,addresses)['supplyWei'],str(100000000*10**18))
        with self.assertRaises(ValueError):validate_genesis.validate(genesis,73571,policy,addresses)
        changed=copy.deepcopy(genesis);changed['config']['contractNativeMinterConfig']={'blockTimestamp':0}
        with self.assertRaises(ValueError):validate_genesis.validate(changed,73571001,policy,addresses)
        changed=copy.deepcopy(genesis);changed['alloc'][addresses['other']]['balance']='0x0'
        with self.assertRaises(ValueError):validate_genesis.validate(changed,73571001,policy,addresses)

    def config(self):
        return {'network-id':'fuji','partial-sync-primary-network':True,'sybil-protection-enabled':True,
                'http-host':'127.0.0.1','api-admin-enabled':False,'staking-port':9651,
                'public-ip':'8.8.8.8','track-subnets':'1'*51}

    def test_validator_config_fails_closed_for_demo_or_missing_settings(self):
        config=self.config()
        chain=json.loads((ROOT/'config/mainnet/chain-config.json').read_text())
        identity={'environment':'fuji','freshCeremonyIdentity':True}
        self.assertEqual(validator.validate(config,chain,identity),'fuji')
        for key,value in (('network-id',1337),('partial-sync-primary-network',False),
                          ('sybil-protection-enabled',False),('http-host','0.0.0.0'),
                          ('api-keystore-enabled',False),('bootstrap-ips','')):
            changed={**config,key:value}
            with self.subTest(key=key),self.assertRaises(ValueError):validator.validate(changed,chain,identity)
        with self.assertRaises(ValueError):validator.validate(config,chain,{'environment':'mainnet','freshCeremonyIdentity':True})

    def test_no_missing_or_symlinked_identity_paths_created(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory).resolve();missing=root/'missing.key'
            with self.assertRaises(ValueError):validator.path_check(str(missing),False)
            self.assertFalse(missing.exists())
            (root/'real').write_text('fixture')
            (root/'link').symlink_to(root/'real')
            with self.assertRaises(ValueError):validator.path_check(str(root/'link'),False)

    def test_binary_digest_mismatch_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'archive';path.write_bytes(b'fixture')
            with self.assertRaises(ValueError):binary_verify.verify(path,'0'*64)
            self.assertEqual(binary_verify.verify(path,hashlib.sha256(b'fixture').hexdigest()),hashlib.sha256(b'fixture').hexdigest())

    def test_fuji_plan_never_broadcasts_or_accepts_reused_identity(self):
        manager={'environment':'fuji','broadcastApproved':False}
        records=[dict(environment='fuji',freshTestIdentity=True,nodeId='NodeID-'+str(i),blsPublicKey='fixture',proofOfPossession='fixture') for i in range(2)]
        self.assertEqual(fuji_rehearsal.sequence(manager,records)['broadcasts'],0)
        changed=copy.deepcopy(records);changed[0]['environment']='mainnet'
        with self.assertRaises(ValueError):fuji_rehearsal.sequence(manager,changed)
        changed=copy.deepcopy(records);changed[0]['privateKey']='REJECTED-FIXTURE'
        with self.assertRaises(ValueError):fuji_rehearsal.sequence(manager,changed)

    def test_collect_is_read_only_and_missing_external_evidence_stays_missing(self):
        mount=json.dumps({'filesystems':[{'source':'/dev/vda1','fstype':'ext4','options':'rw,relatime'}]})
        def command(args):
            if args[0]=='findmnt':return mount
            if args[0]=='ufw':return 'Status: active\nDefault: deny (incoming)\n22 ALLOW IN 192.0.2.2\n'
            if args[0]=='timedatectl':return 'yes\n'
            if args[0]=='systemctl':return 'active\n'
            raise AssertionError('Unexpected inspection command')
        with patch.object(preflight,'run_public',side_effect=command),patch.object(preflight.platform,'freedesktop_os_release',return_value={'NAME':'Ubuntu','VERSION_ID':'24.04'}):
            facts=preflight.collect(ROOT)
            self.assertTrue(facts['persistentStorageVerified'])
            self.assertTrue(facts['sshSourceRestricted'])
            self.assertNotIn('diskReadIops',facts)
            self.assertNotIn('p2p9651ExternallyVerified',facts)
            self.assertNotIn('offHostRecoveryVerified',facts)

    def test_compile_scripts_have_no_obsolete_or_local_defaults(self):
        wrapper=(ROOT/'scripts/start-validator.sh').read_text()
        self.assertNotIn('api-keystore-enabled',wrapper)
        self.assertNotIn('primewavedev',wrapper)
        script=(ROOT/'contracts/script/DeployProduction.s.sol').read_text()
        self.assertIn('PRIMEWAVE_MAINNET_CHAIN_ID_APPROVED',script)
        self.assertNotIn('constant EXPECTED_CHAIN_ID',script)


class DownloadedCompatibilityTests(unittest.TestCase):
    @unittest.skipUnless(os.environ.get('PRIMEWAVE_NATIVE_TEST_DIR'),'Native verified archives not supplied')
    def test_native_node_and_plugin_report_same_commit_and_protocol46(self):
        directory=Path(os.environ['PRIMEWAVE_NATIVE_TEST_DIR'])
        for component in ('avalanchego','subnet-evm'):
            result=subprocess.run([str(directory/component),'--version'],capture_output=True,text=True,timeout=10)
            self.assertEqual(result.returncode,0)
            self.assertIn('rpcchainvm=46',result.stdout+result.stderr)
            self.assertIn('fdb2c1b9b02ef357b5867d5ababb6acc83837a01',result.stdout+result.stderr)

    @unittest.skipUnless(os.environ.get('PRIMEWAVE_LINUX_TEST_DIR'),'Linux verified archives not supplied')
    def test_linux_executables_are_pinned_amd64_elf(self):
        directory=Path(os.environ['PRIMEWAVE_LINUX_TEST_DIR'])
        lock=json.loads((ROOT/'config/mainnet/binaries.lock.json').read_text())
        for component in ('avalanchego','subnet-evm'):
            raw=(directory/component).read_bytes()
            self.assertEqual(raw[:4],b'\x7fELF')
            self.assertEqual(int.from_bytes(raw[18:20],'little'),62)
            self.assertEqual(hashlib.sha256(raw).hexdigest(),lock['assets'][f'{component}-linux-amd64-v1.15.1.tar.gz']['binarySha256'])

class AdditionalSafetyTests(unittest.TestCase):
    def test_no_live_socket_used_without_explicit_probe(self):
        with patch('socket.create_connection') as connect:
            with self.assertRaises(ValueError):preflight.probe_p2p('127.0.0.1')
            connect.assert_not_called()
            result=preflight.probe_p2p('8.8.8.8')
            self.assertTrue(result['p2p9651ExternallyVerified'])
            connect.assert_called_once_with(('8.8.8.8',9651),timeout=5)

    def test_unmeasured_performance_ssh_and_recovery_cannot_pass(self):
        plan=json.loads((ROOT/'config/mainnet/readiness.review.json').read_text())
        hosts=json.loads((ROOT/'config/mainnet/hosts.proposed.json').read_text())
        genesis=json.loads((ROOT/'config/mainnet/genesis.review.json').read_text())
        errors=preflight.check(plan,hosts,genesis)
        for phrase in ('IOPS','SSH password','off-host recovery','persistent local'):
            self.assertTrue(any(phrase in item for item in errors),phrase)

    def test_read_benchmark_command_forbids_writes_and_file_creation(self):
        mount=json.dumps({'filesystems':[{'source':'/dev/vda1','fstype':'ext4','options':'rw'}]})
        commands=[]
        def run(args):
            commands.append(args)
            if args[0]=='findmnt':return mount
            if args[0]=='ufw':return 'Status: inactive'
            if args[0]=='timedatectl':return 'yes'
            if args[0]=='systemctl':return 'active'
            if args[0]=='fio':return json.dumps({'jobs':[{'read':{'iops':4000,'clat_ns':{'mean':250000}}}]})
            raise AssertionError(args)
        with tempfile.TemporaryDirectory() as directory:
            file=Path(directory)/'public.benchmark'
            with file.open('wb') as stream:stream.truncate(256*2**20)
            with patch.object(preflight,'run_public',side_effect=run),patch.object(preflight.platform,'freedesktop_os_release',return_value={'NAME':'Ubuntu','VERSION_ID':'24.04'}):
                data=preflight.collect(ROOT,read_test_file=file)
                self.assertEqual(data['diskReadIops'],4000)
                fio=[command for command in commands if command[0]=='fio'][0]
                self.assertIn('--readonly',fio)
                self.assertIn('--allow_file_create=0',fio)
                self.assertIn('--rw=randread',fio)
