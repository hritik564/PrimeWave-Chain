#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
mode="${1:-}"
[[ "$mode" == "preflight" || "$mode" == "start" ]] || {
    demo_error "Expected preflight or start mode."
    exit 2
}

[[ "$(id -u)" == "0" && "$(python3 -c 'import os,pwd; print(pwd.getpwuid(os.getuid()).pw_dir)')" == "/root" ]] || {
    demo_error "Expected the verified unprivileged user namespace identity."
    exit 1
}
[[ -n "${PWDEMO_HOST_ACCOUNT_HOME:-}" && "$PWDEMO_HOST_ACCOUNT_HOME" == "$HOST_ACCOUNT_HOME" ]] || {
    demo_error "Host home identity was not passed from the parent process."
    exit 1
}
[[ -d "$ROOT_HOME/.avalanche-cli" && ! -L "$ROOT_HOME/.avalanche-cli" ]] || {
    demo_error "Runtime CLI mountpoint is missing or is a symlink."
    exit 1
}
[[ -d "$HOST_CLI_HOME" && ! -L "$HOST_CLI_HOME" ]] || {
    demo_error "Host CLI mount target is missing or is a symlink."
    exit 1
}

mount --make-rprivate /
mount --bind "$ROOT_HOME" /root
mount --bind "$CLI_HOME" /root/.avalanche-cli
mount --bind "$CLI_HOME" "$HOST_CLI_HOME"
mount --bind "$TMP_DIR" /tmp

export HOME=/root
export TMPDIR=/tmp
export XDG_CACHE_HOME="$RUNTIME_ROOT/xdg-cache"
export XDG_CONFIG_HOME="$RUNTIME_ROOT/xdg-config"
export XDG_DATA_HOME="$RUNTIME_ROOT/xdg-data"
export LOCAL_DATA_DIR CONFIG_DIR CHAIN_DIR NETWORK_STATE_FILE LOCAL_BIN_DIR
export AVALANCHEGO_BIN AVALANCHE_CLI_BIN PRIMEWAVE_ISOLATION_ROOT
umask 077

for target in /root /root/.avalanche-cli "$HOST_CLI_HOME" /tmp; do
    mountpoint -q "$target" || {
        demo_error "Required isolated bind mount is absent: $target"
        exit 1
    }
done
for target in /root/.avalanche-cli "$HOST_CLI_HOME"; do
    [[ "$(stat -c '%d:%i' "$target")" == "$(stat -c '%d:%i' "$CLI_HOME")" ]] || {
        demo_error "CLI home redirection did not resolve to the isolated runtime."
        exit 1
    }
done
[[ "$(realpath -e /root)" == "/root" && "$HOME" == "/root" ]] || {
    demo_error "Sandbox home did not resolve to the isolated runtime."
    exit 1
}

if [[ "$mode" == "preflight" ]]; then
    probe="$TMP_DIR/mount-namespace-proof"
    if [[ -e "$probe" ]]; then
        [[ "$(cat "$probe")" == "pw-demo-02-isolated" ]] || {
            demo_error "Isolation proof file contains unexpected content."
            exit 1
        }
    else
        printf 'pw-demo-02-isolated\n' > "$probe"
        chmod 600 "$probe"
    fi
    python3 - "$METADATA_DIR/isolation-proof.json" "$RUNTIME_ROOT" "$CLI_HOME" "$TMP_DIR" <<'PYPROOF'
import json, os, sys
out, runtime, cli_home, tmp = sys.argv[1:]
proof = {
    "userNamespaceUid": os.getuid(),
    "effectiveHome": os.environ["HOME"],
    "runtimeRoot": os.path.realpath(runtime),
    "cliHome": os.path.realpath(cli_home),
    "tempDirectory": os.path.realpath(tmp),
    "hostCliHomeRedirected": True,
    "rootHomeRedirected": True,
}
if os.path.exists(out):
    with open(out, encoding="utf-8") as f:
        old = json.load(f)
    if old != proof:
        raise SystemExit("existing isolation proof differs")
else:
    with open(out, "x", encoding="utf-8") as f:
        json.dump(proof, f, indent=2)
        f.write("\n")
    os.chmod(out, 0o600)
print("Mount namespace and CLI home redirection: PASS")
PYPROOF
    exit 0
fi

AVAGO_VERSION="$("$AVALANCHEGO_BIN" --version 2>&1 | head -1)"
SEVM_VERSION="$("$LOCAL_BIN_DIR/subnet-evm" --version 2>&1 | head -1)"
CLI_VERSION="$("$AVALANCHE_CLI_BIN" --version --skip-update-check 2>&1 | head -1)"
[[ "$AVAGO_VERSION" == *"avalanchego/1.14.2"* && "$AVAGO_VERSION" == *"rpcchainvm=45"* ]] || {
    demo_error "AvalancheGo version or VM protocol changed."
    exit 1
}
[[ "$SEVM_VERSION" == *"v1.14.2"* && "$SEVM_VERSION" == *"rpcchainvm=45"* ]] || {
    demo_error "Subnet-EVM version or VM protocol changed."
    exit 1
}
[[ "$CLI_VERSION" == *"1.9.5"* ]] || {
    demo_error "Avalanche CLI version changed."
    exit 1
}

if [[ -f "$DEMO_READY_FILE" ]]; then
    python3 - "$DEMO_READY_FILE" "$CONFIG_DIR/genesis/dev-genesis.json" <<'PYREADYCHECK'
import hashlib, json, sys
ready_path, genesis_path = sys.argv[1:]
with open(ready_path, encoding="utf-8") as f:
    ready = json.load(f)
with open(genesis_path, "rb") as f:
    actual = hashlib.sha256(f.read()).hexdigest()
if ready.get("genesisSha256") != actual:
    raise SystemExit("genesis hash changed since the verified startup")
PYREADYCHECK
    read_demo_state
else
    [[ ! -e "$DEMO_ATTEMPT_FILE" ]] || {
        demo_error "Initialization marker exists without a verified ready record; refusing retry."
        exit 1
    }
    python3 - "$DEMO_ATTEMPT_FILE" <<'PYMARKER'
import os, sys
with open(sys.argv[1], "x", encoding="utf-8") as f:
    f.write("initialization started; automatic retry disabled\n")
os.chmod(sys.argv[1], 0o600)
PYMARKER

    node "$DEMO_SCRIPT_DIR/prepare-genesis.cjs" \
        "$WORKSPACE_ROOT/chain/genesis/dev-genesis.json" \
        "$CONFIG_DIR/genesis/dev-genesis.json" \
        "$DEMO_KEY_FILE" \
        "$DEMO_ACCOUNTS_FILE"

    python3 - "$CLI_HOME/config.json" <<'PYCONFIG'
import json, os, sys
path = sys.argv[1]
data = {
    "node-config": {
        "http-host": "127.0.0.1",
        "staking-host": "127.0.0.1",
        "public-ip": "127.0.0.1",
    }
}
with open(path, "x", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
os.chmod(path, 0o600)
PYCONFIG

    python3 "$DEMO_SCRIPT_DIR/create-config.py"
fi

bash "$WORKSPACE_ROOT/scripts/start-local.sh" 2>&1 | tee -a "$LOG_DIR/startup.log"
read_demo_state
bash "$DEMO_SCRIPT_DIR/health.sh"

if [[ ! -f "$DEMO_READY_FILE" ]]; then
    GENESIS_SHA256="$(sha256sum "$CONFIG_DIR/genesis/dev-genesis.json" | awk '{print $1}')"
    GENESIS_BLOCK_HASH="$(curl -fsS --max-time 5 \
        -H 'Content-Type: application/json' \
        -d '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["0x0",false],"id":4}' \
        "$PRIMEWAVE_RPC_URL" | jq -r '.result.hash')"
    [[ "$GENESIS_BLOCK_HASH" =~ ^0x[0-9a-fA-F]{64}$ ]] || {
        demo_error "RPC did not return a valid genesis block hash."
        exit 1
    }
    python3 - "$DEMO_READY_FILE" "$GENESIS_SHA256" "$GENESIS_BLOCK_HASH" "$AVAGO_VERSION" "$SEVM_VERSION" "$CLI_VERSION" <<'PYREADY'
import json, os, sys
from datetime import datetime, timezone
path, genesis_hash, genesis_block_hash, avago, sevm, cli = sys.argv[1:]
with open(os.environ["NETWORK_STATE_FILE"], encoding="utf-8") as f:
    state = {}
    for line in f:
        if "=" in line and not line.lstrip().startswith("#"):
            key, value = line.strip().split("=", 1)
            state[key] = value.strip('"')
data = {
    "status": "ready",
    "verifiedAt": datetime.now(timezone.utc).isoformat(),
    "genesisSha256": genesis_hash,
    "genesisBlockHash": genesis_block_hash,
    "avalancheGoVersion": avago,
    "subnetEvmVersion": sevm,
    "avalancheCliVersion": cli,
    "chainId": int(state["PRIMEWAVE_DEV_CHAIN_ID"]),
    "subnetId": state["PRIMEWAVE_SUBNET_ID"],
    "blockchainId": state["PRIMEWAVE_BLOCKCHAIN_ID"],
    "rpcUrl": state["PRIMEWAVE_RPC_URL"],
}
with open(path, "x", encoding="utf-8") as out:
    json.dump(data, out, indent=2)
    out.write("\n")
os.chmod(path, 0o600)
PYREADY
    printf '[pw-demo-02] First startup verified and identity saved.\n'
else
    printf '[pw-demo-02] Existing isolated identity restarted and verified.\n'
fi
