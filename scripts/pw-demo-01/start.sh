#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
umask 077
ensure_demo_dirs

system_home="$(python3 -c 'import os, pwd; print(pwd.getpwuid(os.getuid()).pw_dir)')"
if [[ "$(realpath -m "$CLI_HOME/.avalanche-cli")" != "$(realpath -m "$system_home/.avalanche-cli")" ]]; then
    demo_error "Avalanche CLI v1.9.5 stores chain state under the OS account home, not this isolated runtime."
    demo_error "Refusing to touch the host CLI home or initialize a chain."
    exit 1
fi

if [[ -f "$DEMO_READY_FILE" ]]; then
    read_demo_state
elif [[ -e "$DEMO_ATTEMPT_FILE" ]]; then
    demo_error "A previous initialization did not reach verification. Preserving it; inspect isolated logs before any recovery."
    exit 1
else
    touch "$DEMO_ATTEMPT_FILE"
    chmod 600 "$DEMO_ATTEMPT_FILE"
    node "$DEMO_SCRIPT_DIR/prepare-genesis.cjs" \
        "$WORKSPACE_ROOT/chain/genesis/dev-genesis.json" \
        "$CONFIG_DIR/genesis/dev-genesis.json" \
        "$DEMO_KEY_FILE" \
        "$DEMO_ACCOUNTS_FILE"
fi

[[ -x "$AVALANCHEGO_BIN" && -x "$AVALANCHE_CLI_BIN" && -x "$LOCAL_BIN_DIR/subnet-evm" ]] || {
    demo_error "Required pinned Avalanche binaries are unavailable."
    exit 1
}

AVAGO_VERSION="$("$AVALANCHEGO_BIN" --version 2>&1 | head -1)"
SEVM_VERSION="$("$LOCAL_BIN_DIR/subnet-evm" --version 2>&1 | head -1)"
CLI_VERSION="$("$AVALANCHE_CLI_BIN" --version 2>&1 | head -1)"
[[ "$AVAGO_VERSION" == *"avalanchego/1.14.2"* && "$AVAGO_VERSION" == *"rpcchainvm=45"* ]] || {
    demo_error "AvalancheGo version or VM protocol does not match the approved runtime."
    exit 1
}
[[ "$SEVM_VERSION" == *"v1.14.2"* && "$SEVM_VERSION" == *"rpcchainvm=45"* ]] || {
    demo_error "Subnet-EVM version or VM protocol does not match AvalancheGo."
    exit 1
}
[[ "$CLI_VERSION" == *"1.9.5"* ]] || {
    demo_error "Avalanche CLI version differs from the workspace-verified version."
    exit 1
}

if [[ -f "$LOCAL_DATA_DIR/node.pid" ]]; then
    saved_pid="$(cat "$LOCAL_DATA_DIR/node.pid")"
    if [[ "$saved_pid" =~ ^[0-9]+$ ]] && kill -0 "$saved_pid" 2>/dev/null; then
        cmdline="$(tr '\0' ' ' < "/proc/$saved_pid/cmdline" 2>/dev/null || true)"
        if [[ "$cmdline" == *"$HOME/.avalanche-cli/local/"* ]]; then
            printf '[pw-demo-01] Already running; use status.sh and health.sh.\n'
            exit 0
        fi
        demo_error "Saved PID exists but does not identify this isolated node."
        exit 1
    fi
fi

python3 - "$AVALANCHEGO_BIN" "$RUNTIME_ROOT" <<'PYPROC'
import os, sys
binary, runtime = map(os.path.realpath, sys.argv[1:])
for entry in os.listdir('/proc'):
    if not entry.isdigit():
        continue
    try:
        exe = os.path.realpath(f'/proc/{entry}/exe')
        cmd = open(f'/proc/{entry}/cmdline', 'rb').read().replace(b'\0', b' ').decode(errors='replace')
    except (OSError, PermissionError):
        continue
    if exe == binary and runtime in cmd:
        print(f'Found an isolated AvalancheGo process without a matching PID record: {entry}', file=sys.stderr)
        raise SystemExit(1)
PYPROC

GENESIS_HASH="$(sha256sum "$CONFIG_DIR/genesis/dev-genesis.json" | awk '{print $1}')"
printf '[pw-demo-01] Starting isolated PrimeWave Chain 73571 with AvalancheGo 1.14.2 / Subnet-EVM 1.14.2.\n'
printf '[pw-demo-01] Runtime paths validated under %s\n' "$RUNTIME_ROOT"

export HOME LOCAL_DATA_DIR LOCAL_BIN_DIR CHAIN_DIR
if ! bash "$WORKSPACE_ROOT/scripts/start-local.sh" 2>&1 | tee -a "$LOG_DIR/startup.log"; then
    demo_error "Isolated startup failed. Runtime state and logs are preserved; automatic retry is disabled."
    exit 1
fi

read_demo_state
[[ -f "$DEMO_KEY_FILE" && -f "$DEMO_ACCOUNTS_FILE" ]] || {
    demo_error "Verified chain is missing its isolated transfer-test account material."
    exit 1
}

python3 - "$DEMO_READY_FILE" "$GENESIS_HASH" "$AVAGO_VERSION" "$SEVM_VERSION" "$CLI_VERSION" <<'PYREADY'
import json, sys
from datetime import datetime, timezone
path, genesis_hash, avago, sevm, cli = sys.argv[1:]
data = {
    "status": "ready",
    "verifiedAt": datetime.now(timezone.utc).isoformat(),
    "genesisSha256": genesis_hash,
    "avalancheGoVersion": avago,
    "subnetEvmVersion": sevm,
    "avalancheCliVersion": cli,
}
with open(path, "x", encoding="utf-8") as out:
    json.dump(data, out, indent=2)
    out.write("\n")
PYREADY
chmod 600 "$DEMO_READY_FILE"
printf '[pw-demo-01] Verified isolated network is running. Check scripts/pw-demo-01/health.sh.\n'
