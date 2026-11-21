#!/usr/bin/env python3
"""Download pinned upstream archives to a separate directory; no node startup."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import re
import subprocess
import tarfile
import zipfile

ROOT = Path(__file__).resolve().parents[2]


def verify(path, digest):
    actual = hashlib.sha256(path.read_bytes()).hexdigest()
    if actual != digest:
        raise ValueError('Archive SHA256 differs from upstream lock')
    return actual


def extract_binary(archive, component, destination):
    # Extract a single regular executable; never extract arbitrary archive paths.
    if archive.suffix == '.zip':
        with zipfile.ZipFile(archive) as z:
            arch = 'arm64' if platform.machine() == 'arm64' else 'amd64'
            names = [n for n in z.namelist() if Path(n).name == component and arch in n]
            if not names:
                names = [n for n in z.namelist() if Path(n).name == component]
            if len(names) != 1:
                raise ValueError('Ambiguous native executable in archive')
            raw = z.read(names[0])
    else:
        with tarfile.open(archive) as t:
            matches = [m for m in t.getmembers() if m.isfile() and Path(m.name).name == component]
            if len(matches) != 1:
                raise ValueError('Ambiguous executable in archive')
            raw = t.extractfile(matches[0]).read()
    with destination.open('xb') as out:
        out.write(raw)
    destination.chmod(0o755)
    return hashlib.sha256(raw).hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--platform', choices=['linux-amd64','macos'], required=True)
    p.add_argument('--run-version', action='store_true', help='Only --version; never starts a node')
    args = p.parse_args()
    out = args.output.absolute()
    if any(p.is_symlink() for p in out.parents):
        p.error('Output ancestors must not be symlinks')
    if out.exists() or any(x in out.parts for x in ('.local-networks','local-data','local-bin')):
        p.error('Use a new, separate output directory; runtime/bin paths are forbidden')
    lock = json.loads((ROOT / 'config/mainnet/binaries.lock.json').read_text())
    out.mkdir(mode=0o700, parents=True)
    report = dict(version=lock['avalancheGoVersion'], protocol=lock['pluginProtocol'], archives=[], execution=[])
    for component in ('avalanchego','subnet-evm'):
        suffix = '.zip' if args.platform == 'macos' else '.tar.gz'
        name = f'{component}-{args.platform}-{lock["avalancheGoVersion"]}{suffix}'
        item = lock['assets'][name]
        if not item['url'].startswith('https://github.com/ava-labs/avalanchego/releases/download/v1.15.1/'):
            raise ValueError('Untrusted download origin')
        archive = out / name
        subprocess.run(['curl','--fail','--silent','--show-error','--location','--proto','=https',
                        '--proto-redir','=https','--max-time','180',item['url'],'--output',str(archive)],check=True)
        digest = verify(archive,item['sha256'])
        executable = out / component
        binary_digest = extract_binary(archive,component,executable)
        report['archives'].append(dict(name=name,sha256=digest,binarySha256=binary_digest))
        if args.run_version:
            native = (args.platform == 'macos' and platform.system() == 'Darwin') or (
                args.platform == 'linux-amd64' and platform.system() == 'Linux' and platform.machine() == 'x86_64')
            if not native:
                raise ValueError('Cannot execute foreign-platform binaries; archive verification only')
            result = subprocess.run([str(executable),'--version'],capture_output=True,text=True,timeout=10)
            value = result.stdout + result.stderr
            if result.returncode or 'rpcchainvm=46' not in value or not re.search(r'(?:v|/)?1\.15\.1\b',value):
                raise ValueError('Executable version/protocol mismatch')
            report['execution'].append(dict(component=component,versionOutput=value.strip()))
    (out / 'verification.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))


if __name__ == '__main__':
    main()
