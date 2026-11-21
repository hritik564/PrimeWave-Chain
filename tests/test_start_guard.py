import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('start_guard',ROOT/'scripts/deploy/start_guard.py')
guard=importlib.util.module_from_spec(spec);spec.loader.exec_module(guard)


class StartGuardTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name).resolve()
        (self.root/'.managed-purpose').write_text('fuji-rehearsal\n')
        self.config={'network-id':'fuji','http-host':'127.0.0.1','api-admin-enabled':False,
                     'partial-sync-primary-network':True,'sybil-protection-enabled':True,'data-dir':str(self.root)}
        for key,name in [('db-dir','db'),('log-dir','logs'),('plugin-dir','plugins'),('chain-config-dir','chains')]:
            (self.root/name).mkdir();self.config[key]=str(self.root/name)
        (self.root/'staking').mkdir(mode=0o700)
        for key,name in [('staking-tls-cert-file','staker.crt'),('staking-tls-key-file','staker.key'),('staking-signer-key-file','signer.key')]:
            p=self.root/'staking'/name;p.write_bytes(b'PUBLIC TEST FIXTURE - NO REAL KEY');p.chmod(0o600);self.config[key]=str(p)
        self.binary=self.root/'node';self.binary.write_bytes(b'BINARY TEST FIXTURE')
        self.identity={'purpose':'fuji-rehearsal','environment':'fuji','freshCeremonyIdentity':True,'nodeId':'NodeID-TEST',
                       'blsPublicKey':'PUBLIC_TEST','proofOfPossession':'PUBLIC_TEST','stakingCertificateSha256':hashlib.sha256((self.root/'staking/staker.crt').read_bytes()).hexdigest()}
        self.lock={'assets':{'avalanchego-linux-amd64-v1.15.1.tar.gz':{'binarySha256':hashlib.sha256(self.binary.read_bytes()).hexdigest()},
                            'subnet-evm-linux-amd64-v1.15.1.tar.gz':{'binarySha256':'unused'}}}

    def check(self):return guard.check(self.config,self.identity,self.lock,self.binary,'fuji-rehearsal')

    def test_private_files_are_never_read(self):
        original=Path.read_bytes
        def read(path):
            if path.suffix=='.key':raise AssertionError('Private identity content read')
            return original(path)
        with patch.object(Path,'read_bytes',read):
            self.assertFalse(self.check()['privateKeyContentsRead'])

    def test_environment_reuse_refused(self):
        self.identity['environment']='mainnet'
        with self.assertRaises(ValueError):self.check()

    def test_database_missing_refused(self):
        (self.root/'db').rmdir()
        with self.assertRaises(ValueError):self.check()
        self.assertFalse((self.root/'db').exists())

    def test_changed_binary_or_certificate_refused(self):
        self.binary.write_bytes(b'TAMPERED')
        with self.assertRaisesRegex(ValueError,'checksum'):self.check()

    def test_private_permissions_and_symlinks_refused(self):
        key=self.root/'staking/staker.key';key.chmod(0o644)
        with self.assertRaisesRegex(ValueError,'private'):self.check()
        key.chmod(0o600)
        (self.root/'db').rmdir();(self.root/'db').symlink_to(self.root/'logs',target_is_directory=True)
        with self.assertRaisesRegex(ValueError,'symlinked'):self.check()

    def test_public_rpc_refused(self):
        self.config['http-host']='0.0.0.0'
        with self.assertRaisesRegex(ValueError,'Private'):self.check()
