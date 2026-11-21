#!/usr/bin/env python3
"""Create the local EVM config through the pinned CLI inside the namespace."""

import fcntl
import json
import os
import pty
import re
import select
import signal
import struct
import subprocess
import sys
import termios
import time
from pathlib import Path

root = Path(__file__).resolve().parents[2]
runtime = root / ".local-networks/pw-demo-02"
logs = runtime / "logs"
accounts = json.loads((runtime / "metadata/accounts.json").read_text())
owner = accounts["sender"]
cli = root / "local-bin/avalanche"
vm = root / "local-bin/subnet-evm"
genesis = runtime / "config/genesis/dev-genesis.json"
log_path = logs / "create-config.log"

if log_path.exists():
    raise SystemExit("Creation log already exists; refusing to overwrite it.")
for item in (cli, vm, genesis):
    if not item.is_file():
        raise SystemExit("A required local bootstrap input is missing.")

command = [
    str(cli), "blockchain", "create", "primewavedev",
    "--custom", "--custom-vm-path", str(vm),
    "--evm-token", "PW",
    "--proof-of-authority", "--sovereign",
    "--validator-manager-owner", owner,
    "--proxy-contract-owner", owner,
    "--local", "--genesis", str(genesis),
    "--skip-update-check", "--debug=false",
]

master, slave = pty.openpty()
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 35, 120, 0, 0))
env = os.environ.copy()
env["HOME"] = "/root"
process = subprocess.Popen(
    command, stdin=slave, stdout=slave, stderr=slave, cwd=root, env=env,
    close_fds=True,
)
os.close(slave)
output = bytearray()
answered_isolation = False
deadline = time.monotonic() + 120

while time.monotonic() < deadline:
    ready, _, _ = select.select([master], [], [], 0.25)
    if ready:
        try:
            chunk = os.read(master, 4096)
        except OSError:
            break
        if not chunk:
            break
        output.extend(chunk)
        clean = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", output.decode(errors="replace"))
        question = "Do you want to connect your blockchain with other blockchains or the C-Chain?"
        no_option = "No, I want to run my blockchain isolated"
        if question in clean and not answered_isolation and no_option in clean:
            time.sleep(0.2)
            os.write(master, b"\x1b[B\r")
            answered_isolation = True
        elif re.search(r"\?\s+\S", clean) and question not in clean:
            process.send_signal(signal.SIGINT)
            break
    if process.poll() is not None:
        break

if process.poll() is None:
    process.send_signal(signal.SIGINT)
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()
return_code = process.returncode
try:
    os.close(master)
except OSError:
    pass

text = output.decode(errors="replace")
text = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", text)
text = re.sub(r"(?<![0-9a-fA-F])[0-9a-fA-F]{64}(?![0-9a-fA-F])", "[REDACTED_HEX]", text)
text = re.sub(
    r"(?i)(private[_ -]?key|mnemonic|password|secret)([=: ]+)\S+",
    r"\1\2[REDACTED]",
    text,
)
with open(log_path, "x", encoding="utf-8") as f:
    f.write(text)
os.chmod(log_path, 0o600)

if return_code != 0 or not answered_isolation:
    raise SystemExit(
        f"Avalanche CLI config creation failed safely (exit {return_code}); "
        "runtime evidence is preserved and automatic retry is disabled."
    )

verify = subprocess.run(
    [str(cli), "blockchain", "describe", "primewavedev", "--skip-update-check"],
    cwd=root,
    env=env,
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    timeout=30,
)
describe_log = logs / "create-verify.log"
safe_output = re.sub(
    r"(?<![0-9a-fA-F])[0-9a-fA-F]{64}(?![0-9a-fA-F])",
    "[REDACTED_HEX]",
    verify.stdout,
)
with open(describe_log, "x", encoding="utf-8") as f:
    f.write(safe_output)
os.chmod(describe_log, 0o600)
if verify.returncode != 0:
    raise SystemExit("Avalanche CLI could not describe the newly created local config.")

subnet_dir = runtime / "cli-home/subnets/primewavedev"
for name in ("sidecar.json", "genesis.json", "chain.json"):
    file_path = subnet_dir / name
    if not file_path.is_file() or file_path.is_symlink():
        raise SystemExit("Avalanche CLI config registration is incomplete.")
    if not file_path.resolve().is_relative_to(subnet_dir.resolve()):
        raise SystemExit("Avalanche CLI config path escapes the isolated runtime.")

with open(subnet_dir / "genesis.json", encoding="utf-8") as f:
    configured_genesis = json.load(f)
if int(configured_genesis["config"]["chainId"]) != 73571:
    raise SystemExit("Avalanche CLI registered an unexpected EVM Chain ID.")

print("Avalanche CLI registered the local custom-VM config in the isolated runtime.")
