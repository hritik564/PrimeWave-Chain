import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('manager_build',ROOT/'scripts/mainnet/build_manager.py')
manager=importlib.util.module_from_spec(spec);spec.loader.exec_module(manager)


class ManagerBuildTests(unittest.TestCase):
    def test_corrupt_archive_fails_before_build(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'bad.tar.gz';path.write_bytes(b'not upstream')
            with self.assertRaisesRegex(ValueError,'digest mismatch'):
                manager.verify(path,'sha256','0'*64)

    def test_source_and_exact_oz_dependencies_are_pinned(self):
        self.assertEqual(manager.ICM,'40e1c898d44242aee25693a9cde4bc2485bd8242')
        self.assertEqual(len(manager.ARCHIVES),3)
        self.assertIn('openzeppelin-contracts-5.0.2.tgz',manager.ARCHIVES)
