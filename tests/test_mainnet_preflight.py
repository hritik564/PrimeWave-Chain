import ast
import copy
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('mainnet_preflight', ROOT / 'scripts/mainnet/preflight.py')
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)


class MainnetPreflightTests(unittest.TestCase):
    def setUp(self):
        self.plan = json.loads((ROOT / 'config/mainnet/readiness.review.json').read_text())
        self.hosts = json.loads((ROOT / 'config/mainnet/hosts.proposed.json').read_text())
        self.genesis = json.loads((ROOT / 'config/mainnet/genesis.review.json').read_text())

    def test_proposed_purchase_is_blocked(self):
        reasons = module.check(self.plan, self.hosts, self.genesis)
        self.assertFalse(any('Helicon' in r for r in reasons))
        self.assertFalse(any('Two validators' in r for r in reasons))
        self.assertFalse(any('C00 allocation policy required' in r for r in reasons))

    def test_supply_and_both_candidate_allocations_preserved(self):
        self.assertFalse(self.genesis['deployable'])
        self.assertEqual(int(self.genesis['nativeAsset']['totalSupplyWei']), 100_000_000 * 10**18)
        self.assertFalse(self.genesis['nativeAsset']['nativeMinterEnabled'])
        for candidate in self.genesis['allocationCandidates'].values():
            self.assertEqual(sum(candidate.values()), 100_000_000)

    def test_legacy_release_and_protocol_are_rejected(self):
        self.plan.update(avalancheGoVersion='v1.14.2', subnetEvmVersion='v1.14.2', pluginProtocol=45)
        self.assertTrue(any('Helicon' in r for r in module.check(self.plan,self.hosts,self.genesis)))
        self.plan.update(avalancheGoVersion='v1.15.3', subnetEvmVersion='v1.15.3', pluginProtocol=46)
        self.assertTrue(any('protocol' in r for r in module.check(self.plan,self.hosts,self.genesis)))

    def test_no_demo_identity_or_chain_is_accepted(self):
        self.plan['evmChainId'] = 73571
        reasons = module.check(self.plan,self.hosts,self.genesis)
        self.assertTrue(any('EVM chain' in r for r in reasons))
        self.assertTrue(any('production-only' in r for r in reasons))

    def test_general_production_disk_requirement_is_separate_from_pilot(self):
        for host in self.hosts:
            host.update(diskFreeGiB=110, trafficProfile='under-10-tps-pruned')
        reasons = module.check(self.plan,self.hosts,self.genesis)
        self.assertFalse(any('general-production' in r for r in reasons))
        self.hosts[0]['trafficProfile'] = 'unknown'
        self.assertTrue(any('general-production' in r for r in module.check(self.plan,self.hosts,self.genesis)))

    def test_testnet_config_and_generator_enable_internal_blockchain(self):
        expected = ['eth','eth-filter','internal-blockchain','net','web3']
        config = json.loads((ROOT / 'config/testnet/chain-config.json').read_text())
        self.assertEqual(config['eth-apis'], expected)
        script = (ROOT / 'scripts/testnet/setup-testnet-node.sh').read_text()
        snippet = script.split('python3 -c "\n',1)[1].split('\n"',1)[0]
        tree = ast.parse(snippet)
        assignments = [n for n in ast.walk(tree) if isinstance(n,ast.Assign)
                       and any(isinstance(t,ast.Subscript) and isinstance(t.slice,ast.Constant)
                               and t.slice.value=='eth-apis' for t in n.targets)]
        self.assertEqual(len(assignments),1)
        self.assertEqual(ast.literal_eval(assignments[0].value), expected)
