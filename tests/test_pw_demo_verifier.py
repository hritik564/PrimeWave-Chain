"""Fail-closed offline tests; no real runtime, node, keys or network."""
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('demo', Path(__file__).resolve().parents[1] / 'scripts/verify-pw-demo-04.py')
demo = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(demo)


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name).resolve()
        self.runtime = self.repo / '.local-networks/pw-demo-04'

    def test_missing_runtime_has_no_side_effects(self):
        with patch.object(demo.subprocess, 'run') as run, patch.object(demo, 'call') as call:
            with self.assertRaises(demo.Refusal):
                demo.inspect(self.repo)
            run.assert_not_called()
            call.assert_not_called()
        self.assertFalse(self.runtime.exists())

    def test_valid_alias_resolves_existing_directory(self):
        path = self.runtime / 'cli-home/local/node/db'
        path.mkdir(parents=True)
        self.assertEqual(demo.mapped('/root/.avalanche-cli/local/node/db', self.runtime), path)

    def test_alias_to_missing_db_refused_without_creation(self):
        with self.assertRaises(demo.Refusal):
            demo.mapped('/root/.avalanche-cli/local/node/db', self.runtime)
        self.assertFalse(self.runtime.exists())

    def test_outside_paths_refused(self):
        for path in ('/root/.avalanche-cli-other/db', '/tmp', 'relative/db', '/root/private.key'):
            with self.subTest(path=path), self.assertRaises(demo.Refusal):
                demo.mapped(path, self.runtime)

    def test_traversal_refused(self):
        with self.assertRaises(demo.Refusal):
            demo.mapped('/root/.avalanche-cli/../private', self.runtime)

    def test_symlink_components_refused(self):
        self.runtime.mkdir(parents=True)
        outside = self.repo / 'outside'
        outside.mkdir()
        (self.runtime / 'cli-home').symlink_to(outside, target_is_directory=True)
        with self.assertRaises(demo.Refusal):
            demo.mapped('/root/.avalanche-cli', self.runtime)

    def test_missing_flags_refused(self):
        for name in ('cli-home', 'os-home', 'tmp'):
            (self.runtime / name).mkdir(parents=True)
        with self.assertRaises(demo.Refusal):
            demo.inspect(self.repo)

    def test_empty_database_refused(self):
        db = self.runtime / 'db'
        db.mkdir(parents=True)
        with self.assertRaises(demo.Refusal):
            demo.existing_database(db)

    def test_existing_database_marker_accepted(self):
        db = self.runtime / 'db'
        db.mkdir(parents=True)
        (db / 'CURRENT').write_text('MANIFEST-000001\n')
        demo.existing_database(db)

    def test_missing_or_nonexecutable_plugin_refused(self):
        plugins = self.runtime / 'plugins'
        plugins.mkdir(parents=True)
        with self.assertRaises(demo.Refusal):
            demo.existing_plugin(plugins, 'vm-id', self.runtime)
        (plugins / 'vm-id').write_text('not executable')
        (plugins / 'vm-id').chmod(0o600)
        with self.assertRaises(demo.Refusal):
            demo.existing_plugin(plugins, 'vm-id', self.runtime)

    def test_vm_identity_traversal_refused(self):
        with self.assertRaises(demo.Refusal):
            demo.existing_plugin(self.runtime / 'plugins', '../vm', self.runtime)

    def test_ambiguous_flags_refused_before_reading(self):
        for name in ('cli-home', 'os-home', 'tmp'):
            (self.runtime / name).mkdir(parents=True)
        for name in ('NodeID-a', 'NodeID-b'):
            flags = self.runtime / 'cli-home/local/cluster' / name / 'flags.json'
            flags.parent.mkdir(parents=True)
            flags.write_text('must not read')
        with self.assertRaises(demo.Refusal):
            demo.inspect(self.repo)

    def test_restart_without_approval_cannot_signal(self):
        with patch.object(demo.os, 'pidfd_open', create=True) as pidfd:
            with self.assertRaises(demo.Refusal):
                demo.restart({}, approved=False)
            pidfd.assert_not_called()

    def test_process_arguments_must_match_existing_flags(self):
        flags = {'http-port': 9656, 'db-dir': '/root/.avalanche-cli/db'}
        command = b'avalanchego\0--http-port=9656\0--db-dir=/root/.avalanche-cli/db\0'
        with patch.object(Path, 'read_bytes', return_value=command):
            demo.process_flags(123, self.repo / 'flags.json', flags)
        with patch.object(Path, 'read_bytes', return_value=command + b'--network-id=fuji\0'):
            with self.assertRaises(demo.Refusal):
                demo.process_flags(123, self.repo / 'flags.json', flags)

    def test_config_file_must_identify_same_inode(self):
        command = b'avalanchego\0--config-file=/root/.avalanche-cli/flags.json\0'
        with patch.object(Path, 'read_bytes', return_value=command):
            with patch.object(Path, 'samefile', return_value=False):
                with self.assertRaises(demo.Refusal):
                    demo.process_flags(123, self.repo / 'flags.json', {})

    def test_cli_without_approval_cannot_inspect_or_restart(self):
        with patch.object(demo, 'inspect') as inspect, patch.object(demo, 'restart') as restart:
            with patch('sys.stderr', new_callable=io.StringIO):
                self.assertEqual(demo.main(['--restart-and-verify']), 1)
            inspect.assert_not_called()
            restart.assert_not_called()

    def test_dry_run_only_emits_safe_metadata(self):
        plan = dict(identity='NodeID-test', pid=123, flags={'http-port': 9656, 'network-id': 1337, 'secret': 'DO-NOT-PRINT'})
        with patch.object(demo, 'inspect', return_value=plan), patch.object(demo, 'restart') as restart:
            with patch('sys.stdout', new_callable=io.StringIO) as output:
                self.assertEqual(demo.main(['--dry-run']), 0)
                self.assertNotIn('DO-NOT-PRINT', output.getvalue())
            restart.assert_not_called()

    def test_refusal_does_not_echo_sensitive_errors(self):
        with patch.object(demo, 'inspect', side_effect=OSError('DO-NOT-PRINT')):
            with patch('sys.stderr', new_callable=io.StringIO) as output:
                self.assertEqual(demo.main(['--dry-run']), 1)
                self.assertNotIn('DO-NOT-PRINT', output.getvalue())

class StoppedRuntimeTests(unittest.TestCase):
    def test_start_requires_separate_explicit_approval(self):
        with patch.object(demo, 'inspect') as inspect, patch.object(demo, 'restart') as restart:
            with patch('sys.stderr', new_callable=io.StringIO):
                self.assertEqual(demo.main(['--start-existing-and-verify']), 1)
            inspect.assert_not_called()
            restart.assert_not_called()

    def test_stopped_dry_run_selects_offline_inspection(self):
        plan = dict(identity='NodeID-test', pid=None, flags={'http-port': 9656, 'network-id': 1337})
        with patch.object(demo, 'inspect', return_value=plan) as inspect:
            with patch('sys.stdout', new_callable=io.StringIO):
                self.assertEqual(demo.main(['--dry-run', '--stopped']), 0)
            self.assertTrue(inspect.call_args.kwargs['stopped'])

    def test_network_id_1337_is_read_from_saved_metadata(self):
        import json
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder).resolve()
            (root / 'metadata').mkdir()
            data = dict(networkId=1337, blockchainId=demo.BLOCKCHAIN, chainId=73571, subnetId='saved-subnet')
            (root / 'metadata/ready.json').write_text(json.dumps(data))
            self.assertEqual(demo.saved_metadata(root, {'network-id': 1337, 'track-subnets': 'saved-subnet'}), data)
            with self.assertRaises(demo.Refusal):
                demo.saved_metadata(root, {'network-id': 12345, 'track-subnets': 'saved-subnet'})
            data.pop('networkId')
            (root / 'metadata/ready.json').write_text(json.dumps(data))
            with self.assertRaises(demo.Refusal):
                demo.saved_metadata(root, {'network-id': 1337, 'track-subnets': 'saved-subnet'})

    def test_stopped_evidence_preserves_identity_and_database(self):
        import hashlib
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder).resolve()
            db = root / 'db'
            db.mkdir()
            (db / 'CURRENT').write_text('MANIFEST-000001\n')
            (db / 'MANIFEST-000001').write_bytes(b'saved-db-metadata')
            (db / 'LOCK').touch()
            cert = root / 'staker.crt'
            cert.write_bytes(b'public certificate fixture')
            paths = {'db-dir': db, 'staking-tls-cert-file': cert,
                     'staking-tls-key-file': root / 'tls.key', 'staking-signer-key-file': root / 'signer.key'}
            paths['staking-tls-key-file'].write_bytes(b'fake test key')
            paths['staking-signer-key-file'].write_bytes(b'fake test signer')
            metadata = dict(identityFiles={k: dict(device=p.stat().st_dev, inode=p.stat().st_ino, size=p.stat().st_size)
                for k, p in paths.items() if k != 'db-dir'}, nodeId='NodeID-saved', vmId='vm', subnetId='subnet', blockchainId=demo.BLOCKCHAIN,
                stakingCertificateSha256=hashlib.sha256(cert.read_bytes()).hexdigest(),
                databaseEvidence=dict(device=db.stat().st_dev, inode=db.stat().st_ino,
                    files={name: hashlib.sha256((db / name).read_bytes()).hexdigest()
                           for name in ('CURRENT', 'MANIFEST-000001')}))
            demo.stopped_evidence(root, paths, metadata, 'NodeID-saved')
            with self.assertRaises(demo.Refusal):
                demo.stopped_evidence(root, paths, metadata, 'NodeID-wrong')
            (db / 'MANIFEST-000001').write_bytes(b'changed database')
            with self.assertRaises(demo.Refusal):
                demo.stopped_evidence(root, paths, metadata, 'NodeID-saved')

    def test_missing_pre_stop_database_evidence_is_not_replaced_by_empty_database(self):
        with self.assertRaises(demo.Refusal):
            demo.stopped_evidence(Path('/unused'), {}, {}, 'NodeID-saved')


if __name__ == '__main__':
    unittest.main()
