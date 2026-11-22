#!/usr/bin/env python3
"""Read-only offline comparison by default; --write creates new review evidence only.
No RPC, network, keys, subprocess execution, approvals or artifact-lock updates.
Run from any directory with existing pinned build artifacts available.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts/mainnet'))
from verify_custody_artifacts import verify
from genesis_candidate import materialize

BASELINE = '06851936f51a723d666357c6fc45a168bb748054'
HERE = Path(__file__).resolve().parent

def sha(data):
    return hashlib.sha256(data).hexdigest()

def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':')).encode()

def collect():
    verify()
    sources = set()
    for tree in ('contracts/src', 'contracts/script', 'contracts/test', 'tests/pinned-manager-custody',
                 'contracts/lib/openzeppelin-contracts-v561/contracts',
                 'contracts/lib/openzeppelin-contracts-upgradeable-v561/contracts',
                 'genesis-build/pinned-manager/icm', 'genesis-build/pinned-manager/oz',
                 'genesis-build/pinned-manager/oz-upgradeable'):
        directory = ROOT / tree
        if not directory.is_dir():
            raise ValueError('Missing pre-existing pinned source tree: ' + tree)
        sources.update(p.relative_to(ROOT).as_posix() for p in directory.rglob('*.sol'))
    sources.update(['foundry.toml', 'scripts/mainnet/build_manager.py',
                    'scripts/mainnet/custody_genesis.py', 'scripts/mainnet/custody_state_review.py',
                    'scripts/mainnet/genesis_candidate.py', 'scripts/mainnet/verify_custody_artifacts.py',
                    'scripts/mainnet/test_custody_manager.py', 'scripts/deploy/mainnet_readiness.py',
                    'config/mainnet/custody-artifacts.lock.json', 'config/mainnet/public-genesis-manifest.review.json',
                    'tests/fixtures/custody-genesis.fixture.json', 'tests/test_custody_genesis.py',
                    'tests/test_direct_mainnet.py', 'tests/integration/build_custody_fixture.py'])
    artifact_paths = {n: 'contracts/out/' + n + '.sol/' + n + '.json' for n in
                      ('PrimeWaveCustodyTimelock', 'TimelockOnlySafeGuard', 'PauseOnlyEmergencyMultisig',
                       'FeeDistributor', 'ValidatorFeeVault', 'RewardVault', 'PrimeWaveValidatorRegistry')}
    artifact_paths.update({n: 'contracts/vendor/safe-1.4.1/' + n + '.json' for n in ('Safe', 'SafeProxy')})
    artifact_paths.update({n: 'genesis-build/pinned-manager/artifacts/' + n + '.sol/' + n + '.json'
                          for n in ('ValidatorManager', 'PoAManager', 'ValidatorMessages')})
    # Proxy ABIs here are upstream distribution ABI references, NOT our compiler/runtime attestation.
    artifact_paths.update({n: 'genesis-build/pinned-manager/oz/build/contracts/' + n + '.json'
                          for n in ('ProxyAdmin', 'TransparentUpgradeableProxy', 'ITransparentUpgradeableProxy')})
    artifacts = {}
    for name, path in sorted(artifact_paths.items()):
        raw = (ROOT / path).read_bytes()
        data = json.loads(raw)
        meta = data.get('metadata', {})
        meta = json.loads(meta) if isinstance(meta, str) else meta
        runtime = data.get('deployedBytecode', '')
        runtime = runtime.get('object', '') if isinstance(runtime, dict) else runtime
        try:
            runtime_sha = sha(bytes.fromhex(runtime.removeprefix('0x'))) if runtime else None
        except ValueError:
            runtime_sha = None  # Explicitly unlinked library template.
        artifacts[name] = dict(path=path, fileSha256=sha(raw), runtimeSha256=runtime_sha,
            compiler=meta.get('compiler'), settings=meta.get('settings'),
            scope=('ABI reference only; not local compiled runtime' if '/oz/build/' in path else
                   'exact published artifact; compiler metadata absent' if '/vendor/' in path else
                   'local offline build; manager links/immutables are synthetic, not production'),
            linkReferences=data.get('bytecode', {}).get('linkReferences', {}) if isinstance(data.get('bytecode'), dict) else data.get('linkReferences', {}),
            entryPoints=[entry for entry in data['abi'] if entry['type'] in ('function', 'constructor', 'fallback', 'receive')])
    fixture = json.loads((ROOT / 'tests/fixtures/custody-genesis.fixture.json').read_text())
    if fixture.get('syntheticTestOnly') is not True or fixture.get('productionApproved') is not False:
        raise ValueError('Synthetic evidence labels required')
    candidate = materialize(fixture['publicManifest'], fixture['accounts'], fixture['base'])
    if candidate['deployable'] is not False or candidate['genesisApproved'] is not False:
        raise ValueError('Unapproved candidate required')
    return dict(schemaVersion=1, baseline=BASELINE, externalAudit=False, productionApproved=False,
        executionApproved=False, sourceSha256={p: sha((ROOT / p).read_bytes()) for p in sorted(sources)},
        artifactInventory=artifacts,
        synthetic=dict(fixtureSha256=sha((ROOT / 'tests/fixtures/custody-genesis.fixture.json').read_bytes()),
            candidateCanonicalSha256=sha(canonical(candidate)),
            accountStateSha256=fixture['publicManifest']['custody']['stateSha256'],
            totalNativeWei=str(sum(int(a['balance'], 0) for a in candidate['genesis']['alloc'].values())),
            caveat='Fake manager 0x6000; synthetic approved fields are test harness inputs, never owner consent')), candidate

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write', action='store_true', help='Create NEW evidence; refuses overwrite')
    args = parser.parse_args()
    evidence, candidate = collect()
    for filename, value in [('scope-evidence.json', evidence), ('synthetic-genesis.candidate.json', candidate)]:
        encoded = json.dumps(value, sort_keys=True, indent=2) + '\n'
        destination = HERE / filename
        if args.write:
            with destination.open('x') as output:
                output.write(encoded)
        elif destination.read_text() != encoded:
            raise ValueError('Evidence differs: ' + filename + '; investigate, do not silently regenerate')
    print('PASS: pinned source/artifact/ABI inventory and synthetic genesis match; approvals remain false')
