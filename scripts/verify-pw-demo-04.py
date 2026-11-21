#!/usr/bin/env python3
"""Verify or explicitly start the existing isolated pw-demo-04; never bootstrap a network."""
import argparse
import base64
import importlib.util
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time
import urllib.request

BLOCKCHAIN = 'XDwGN3ztu8JDEFALEeKWS3FPax8U2XghGFZVDxrGesNs5w7D7'
APIS = ['eth', 'eth-filter', 'internal-blockchain', 'net', 'web3']
PATH_FLAGS = {'data-dir', 'db-dir', 'log-dir', 'plugin-dir', 'chain-config-dir',
              'staking-tls-cert-file', 'staking-tls-key-file', 'staking-signer-key-file', 'genesis-file'}
REQUIRED = {'data-dir', 'db-dir', 'log-dir', 'plugin-dir',
            'staking-tls-cert-file', 'staking-tls-key-file', 'staking-signer-key-file'}


class Refusal(Exception):
    pass


def require(condition, message):
    if not condition:
        raise Refusal(message)


def existing(path, boundary):
    """Reject symlinks, traversal, missing paths and paths outside the boundary."""
    path, boundary = Path(path), Path(boundary)
    require(path.is_absolute() and '..' not in path.parts, 'Noncanonical path refused')
    require(path.is_relative_to(boundary), 'Path escapes isolated runtime')
    for item in [path, *path.parents]:
        require(not item.is_symlink(), 'Symlink path refused')
    require(path.exists(), 'Required existing path is missing')
    return path


def mapped(value, runtime):
    require(isinstance(value, str), 'Invalid path value')
    path = Path(value)
    alias = Path('/root/.avalanche-cli')
    require('..' not in path.parts, 'Path traversal refused')
    if path.is_relative_to(alias):
        path = runtime / 'cli-home' / path.relative_to(alias)
    return existing(path, runtime)


def call(base, endpoint, method, params):
    request = urllib.request.Request(base + endpoint,
        json.dumps(dict(jsonrpc='2.0', id=1, method=method, params=params)).encode(),
        {'Content-Type': 'application/json'})
    with urllib.request.urlopen(request, timeout=5) as response:
        data = json.load(response)
    require(isinstance(data, dict) and data.get('jsonrpc') == '2.0'
            and data.get('id') == 1 and 'error' not in data and 'result' in data,
            'Public identity RPC failed')
    return data['result']


def existing_database(path):
    require(path.is_dir() and any(p.is_file() and not p.is_symlink()
                                 for p in path.rglob('CURRENT')),
            'Existing LevelDB database marker missing')


def existing_plugin(directory, vm_id, runtime):
    require(isinstance(vm_id, str) and '/' not in vm_id and vm_id not in ('', '.', '..'),
            'Invalid VM identity')
    plugin = existing(directory / vm_id, runtime)
    require(plugin.is_file() and os.access(plugin, os.X_OK), 'Existing VM plugin missing')
    return plugin


def process_flags(pid, flags_path, flags):
    # Arguments are compared in memory, never printed or executed as shell code.
    args = (Path('/proc') / str(pid) / 'cmdline').read_bytes().split(b'\0')
    args = [a.decode() for a in args[1:] if a]
    if len(args) == 1 and args[0].startswith('--config-file='):
        remote = Path('/proc') / str(pid) / 'root' / args[0].split('=', 1)[1].lstrip('/')
        require(remote.samefile(flags_path), 'Process is not using discovered flags')
    else:
        expected = [f'--{k}={v}' for k, v in flags.items()]
        require(sorted(args) == sorted(expected), 'Process arguments differ from saved flags')


def saved_metadata(runtime, flags):
    candidates = [runtime / 'metadata/runtime-identity.json', runtime / 'metadata/ready.json']
    paths = [p for p in candidates if p.exists()]
    require(paths, 'Saved public runtime identity metadata is required')
    metadata = json.loads(existing(paths[0], runtime).read_text())
    network = metadata.get('networkId')
    require(type(network) is int and network not in (1, 5) and 0 < network < 2**32,
            'Saved local Avalanche network ID is missing or unsafe')
    require(str(flags.get('network-id')) == str(network), 'Saved network ID differs from flags')
    require(metadata.get('blockchainId') == BLOCKCHAIN and metadata.get('chainId') == 73571,
            'Saved blockchain identity differs')
    require(metadata.get('subnetId') == flags.get('track-subnets'), 'Saved subnet identity differs')
    return metadata


def stopped_evidence(runtime, paths, metadata, node_id):
    # A stopped node is not absent data. Require durable pre-stop evidence instead
    # of substituting live process evidence or trusting a nonempty directory.
    require(metadata.get('nodeId') == node_id, 'Saved validator identity missing or different')
    identities = metadata.get('identityFiles')
    require(isinstance(identities, dict), 'Saved identity file inode evidence required')
    for key in ('staking-tls-cert-file', 'staking-tls-key-file', 'staking-signer-key-file'):
        stat = paths[key].stat()  # Never read private key contents.
        require(identities.get(key) == dict(device=stat.st_dev, inode=stat.st_ino, size=stat.st_size),
                'Validator identity file differs from saved evidence')
    certificate = paths['staking-tls-cert-file'].read_bytes()  # public certificate only
    require(hashlib.sha256(certificate).hexdigest() == metadata.get('stakingCertificateSha256'),
            'Public validator certificate differs from saved identity')
    evidence = metadata.get('databaseEvidence')
    require(isinstance(evidence, dict), 'Saved database identity evidence required for stopped startup')
    stat = paths['db-dir'].stat()
    require(evidence.get('device') == stat.st_dev and evidence.get('inode') == stat.st_ino,
            'Database directory identity differs from saved evidence')
    require(metadata.get('vmId') and metadata.get('subnetId')
            and metadata.get('blockchainId') == BLOCKCHAIN, 'Saved registration evidence missing')
    files = evidence.get('files')
    require(isinstance(files, dict) and len(files) >= 2, 'Saved CURRENT and MANIFEST evidence required')
    names = []
    for name, digest in files.items():
        require(isinstance(name, str) and isinstance(digest, str), 'Invalid database evidence')
        file = existing(paths['db-dir'] / name, runtime)
        require(file.is_file() and (file.name == 'CURRENT' or file.name.startswith('MANIFEST-')),
                'Only database metadata evidence is accepted')
        require(hashlib.sha256(file.read_bytes()).hexdigest() == digest, 'Database metadata digest differs')
        names.append(file.name)
    for name in files:
        current = paths['db-dir'] / name
        if current.name == 'CURRENT':
            manifest = current.read_text().strip()
            require(manifest.startswith('MANIFEST-') and (current.parent / manifest).relative_to(paths['db-dir']).as_posix() in files,
                    'CURRENT does not point to the verified MANIFEST')
    require('CURRENT' in names and any(n.startswith('MANIFEST-') for n in names),
            'Database metadata evidence incomplete')
    # Existing database locks must be free; never create a lock or force unlock.
    import fcntl
    locks = list(paths['db-dir'].rglob('LOCK'))
    require(locks, 'Existing database LOCK file required')
    for lock in locks:
        with existing(lock, runtime).open('r+b') as stream:
            fcntl.lockf(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
            fcntl.lockf(stream, fcntl.LOCK_UN)
    return metadata


def inspect(repo, stopped=False):
    runtime = existing(repo / '.local-networks/pw-demo-04', repo)
    require(runtime.is_dir(), 'Runtime is not a directory')
    cli = existing(runtime / 'cli-home', runtime)
    for name in ('os-home', 'tmp'):
        require(existing(runtime / name, runtime).is_dir(), 'Existing isolation directories required')
    candidates = list(cli.glob('local/*/NodeID-*/flags.json'))
    require(len(candidates) == 1, 'Expected exactly one existing node flags file')
    flags_path = existing(candidates[0], runtime)
    flags = json.loads(flags_path.read_text())
    require(isinstance(flags, dict), 'Invalid flags object')
    require(not any(('key' in k or 'signer' in k) and k.endswith('-content') for k in flags),
            'Inline key flags refused')
    require(REQUIRED <= flags.keys(), 'Explicit database, identity and output paths required')
    require(flags.get('http-host') == '127.0.0.1'
            and flags.get('staking-host') == '127.0.0.1'
            and flags.get('public-ip') == '127.0.0.1', 'Loopback-only runtime required')
    require(flags.get('sybil-protection-enabled') is False
            and flags.get('partial-sync-primary-network') is False,
            'Standalone runtime flags required')
    metadata = saved_metadata(runtime, flags)
    port = flags.get('http-port')
    require(str(port).isdigit() and 1024 <= int(port) <= 65535, 'Invalid local HTTP port')
    paths = {}
    for key, value in flags.items():
        if key in PATH_FLAGS:
            paths[key] = mapped(value, runtime)
        elif key.endswith(('-dir', '-file')) or (isinstance(value, str) and value.startswith('/')):
            raise Refusal('Unrecognized filesystem flag refused')
    for key in REQUIRED:
        require(paths[key].is_dir() if key.endswith('-dir') else paths[key].is_file(),
                'Required path has wrong type')
    existing_database(paths['db-dir'])
    chains = json.loads(base64.b64decode(flags['chain-config-content'], validate=True))
    require(BLOCKCHAIN in chains, 'Expected blockchain config missing')
    config = json.loads(base64.b64decode(chains[BLOCKCHAIN]['Config'], validate=True))
    require(config.get('eth-apis') == APIS, 'Corrected API allowlist required; no automatic patching')
    binary = existing(repo / 'local-bin/avalanchego', repo)
    base = f'http://127.0.0.1:{port}'
    if stopped:
        stopped_evidence(runtime, paths, metadata, flags_path.parent.name)
        plugin = existing_plugin(paths['plugin-dir'], metadata.get('vmId'), runtime)
        for proc in Path('/proc').iterdir():
            if proc.name.isdigit():
                try:
                    require(not (proc / 'exe').samefile(binary), 'Node already running; use restart mode')
                except OSError:
                    pass
        verify_versions(binary, plugin)
        return dict(runtime=runtime, flags_path=flags_path, flags=flags, paths=paths,
                    binary=binary, plugin=plugin, pid=None, identity=flags_path.parent.name,
                    base=base, metadata=metadata)
    require(str(call(base, '/ext/info', 'info.getNetworkID', {})['networkID']) == str(metadata['networkId']),
            'Live Avalanche network ID differs from saved metadata')
    identity = call(base, '/ext/info', 'info.getNodeID', {})['nodeID']
    require(identity == flags_path.parent.name, 'Node ID differs from saved node directory')
    records = call(base, '/ext/bc/P', 'platform.getBlockchains', {})['blockchains']
    matches = [r for r in records if r.get('id') == BLOCKCHAIN]
    require(len(matches) == 1, 'Existing blockchain registration not verified')
    record = matches[0]
    require(flags.get('track-subnets') == record['subnetID'], 'Subnet tracking identity differs')
    plugin = existing_plugin(paths['plugin-dir'], record['vmID'], runtime)
    chain_id = call(base, '/ext/bc/' + BLOCKCHAIN + '/rpc', 'eth_chainId', [])
    require(chain_id == '0x11f63', 'Existing EVM Chain ID differs')
    verify_versions(binary, plugin)
    pids = []
    for proc in Path('/proc').iterdir():
        if proc.name.isdigit():
            try:
                if (proc / 'exe').samefile(binary):
                    pids.append(int(proc.name))
            except OSError:
                pass
    require(len(pids) == 1, 'Expected exactly one matching running node')
    pid = pids[0]
    process_flags(pid, flags_path, flags)
    for key, path in paths.items():
        remote = Path('/proc') / str(pid) / 'root' / flags[key].lstrip('/')
        require(remote.samefile(path), 'Process mount mapping differs from isolated paths')
    # Bind database evidence to this process, not merely a nonempty directory.
    database_open = False
    for fd in (Path('/proc') / str(pid) / 'fd').iterdir():
        try:
            target = Path(os.readlink(fd))
            if target.is_relative_to(Path(flags['db-dir'])):
                local = mapped(str(target), runtime)
                if local.is_file() and fd.samefile(local):
                    database_open = True
        except OSError:
            pass
    require(database_open, 'Running process database identity not verified')
    return dict(runtime=runtime, flags_path=flags_path, flags=flags, paths=paths,
                binary=binary, plugin=plugin, pid=pid, identity=identity, base=base,
                start=(Path('/proc') / str(pid) / 'stat').read_text().rsplit(')', 1)[1].split()[19])


def verify_versions(binary, plugin):
    for executable, version in ((binary, 'avalanchego/1.14.2'), (plugin, 'v1.14.2')):
        result = subprocess.run([str(executable), '--version'], capture_output=True, timeout=10)
        require(result.returncode == 0 and version in (result.stdout + result.stderr).decode()
                and 'rpcchainvm=45' in (result.stdout + result.stderr).decode(),
                'Pinned binary version mismatch')


def restart(plan, approved=False, start_existing=False):
    require(approved, 'Startup/restart requires explicit approval')
    require(start_existing or (hasattr(os, 'pidfd_open') and hasattr(signal, 'pidfd_send_signal')),
            'Linux pidfd support required for safe process signalling')
    home = existing(plan['runtime'] / 'os-home', plan['runtime'])
    temp = existing(plan['runtime'] / 'tmp', plan['runtime'])
    require(home.is_dir() and temp.is_dir(), 'Existing home and temp directories required')
    flags = dict(plan['flags'])
    flags.update({k: str(v) for k, v in plan['paths'].items()})
    # No config is changed on disk. Explicit mapped paths retain the same inode
    # identities verified above; launch AvalancheGo directly, never the CLI.
    if not start_existing:
        pidfd = os.pidfd_open(plan['pid'])
        try:
            stat = (Path('/proc') / str(plan['pid']) / 'stat').read_text()
            require(stat.rsplit(')', 1)[1].split()[19] == plan['start'], 'Node process changed')
            signal.pidfd_send_signal(pidfd, signal.SIGTERM)
            import select
            require(select.select([pidfd], [], [], 30)[0], 'Node did not stop gracefully; no replacement started')
        finally:
            os.close(pidfd)
    if start_existing:
        stopped_evidence(plan['runtime'], plan['paths'], plan['metadata'], plan['identity'])
    # Recheck all original paths after shutdown; never recreate missing data.
    for path in plan['paths'].values():
        existing(path, plan['runtime'])
    existing(plan['binary'], plan['binary'].parent)
    existing(plan['plugin'], plan['runtime'])
    existing_database(plan['paths']['db-dir'])
    log = plan['paths']['log-dir'] / f'verification-restart-{time.time_ns()}.log'
    env = {'PATH': os.defpath, 'HOME': str(home), 'TMPDIR': str(temp)}
    with open(log, 'xb') as output:
        os.chmod(log, 0o600)
        node = subprocess.Popen([str(plan['binary']), *[f'--{k}={v}' for k, v in flags.items()]],
                                stdin=subprocess.DEVNULL, stdout=output, stderr=output,
                                cwd=plan['runtime'], env=env, start_new_session=True)
    spec = importlib.util.spec_from_file_location('evm_rpc', Path(__file__).with_name('check-evm-rpc.py'))
    rpc = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(rpc)
    for _ in range(30):
        require(node.poll() is None, 'Restarted node exited; preserve runtime and restart log')
        try:
            require(call(plan['base'], '/ext/info', 'info.getNodeID', {})['nodeID'] == plan['identity'],
                    'Restarted node identity differs')
            require(str(call(plan['base'], '/ext/info', 'info.getNetworkID', {})['networkID']) == str(flags['network-id']),
                    'Started Avalanche network ID differs')
            records = call(plan['base'], '/ext/bc/P', 'platform.getBlockchains', {})['blockchains']
            registered = [r for r in records if r.get('id') == BLOCKCHAIN]
            require(len(registered) == 1 and registered[0]['subnetID'] == flags['track-subnets']
                    and registered[0]['vmID'] == plan['plugin'].name, 'Preserved registration differs')
            height = rpc.check(plan['base'] + '/ext/bc/' + BLOCKCHAIN + '/rpc')
            print(json.dumps({'status': 'verified', 'pid': node.pid, 'block': height, 'chainId': 73571}))
            return
        except (OSError, ValueError):
            time.sleep(1)
    raise Refusal('RPC verification timed out; node left running, no reset or automatic retry')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--dry-run', action='store_true')
    mode.add_argument('--restart-and-verify', action='store_true')
    mode.add_argument('--start-existing-and-verify', action='store_true')
    parser.add_argument('--stopped', action='store_true', help='Dry-run using saved stopped-node evidence')
    parser.add_argument('--approve-start', action='store_true')
    parser.add_argument('--approve-restart', action='store_true')
    args = parser.parse_args(argv)
    try:
        require(not args.approve_restart or args.restart_and_verify, 'Approval applies only to restart mode')
        require(not args.restart_and_verify or args.approve_restart, 'Restart requires --approve-restart')
        require(not args.approve_start or args.start_existing_and_verify, 'Approval applies only to existing startup')
        require(not args.start_existing_and_verify or args.approve_start, 'Existing startup requires --approve-start')
        require(not args.stopped or args.dry_run, '--stopped applies only to dry-run')
        if args.stopped or args.start_existing_and_verify:
            plan = inspect(Path(__file__).resolve().parents[1], stopped=True)
        else:
            plan = inspect(Path(__file__).resolve().parents[1])
        if args.dry_run:
            print(json.dumps({'status': 'dry-run verified', 'runtime': 'pw-demo-04',
                              'blockchainId': BLOCKCHAIN, 'nodeId': plan['identity'],
                              'pid': plan['pid'], 'chainId': 73571, 'ethApis': APIS,
                              'networkId': int(plan['flags']['network-id']),
                              'database': 'saved evidence verified' if args.stopped else 'open by verified node',
                              'plugin': 'v1.14.2 rpcchainvm=45', 'port': int(plan['flags']['http-port'])}))
        else:
            restart(plan, approved=args.approve_start or args.approve_restart,
                    start_existing=args.start_existing_and_verify)
        return 0
    except Refusal as error:
        print(f'REFUSED: {error}. No bootstrap or fallback attempted.', file=sys.stderr)
        return 1
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError):
        # Do not echo OS errors, config values, process arguments or server replies.
        print('REFUSED: runtime verification failed; no bootstrap or fallback attempted.', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
