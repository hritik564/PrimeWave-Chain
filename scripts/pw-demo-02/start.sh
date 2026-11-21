#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
umask 077

[[ -x "$AVALANCHEGO_BIN" && -x "$LOCAL_BIN_DIR/subnet-evm" && -x "$AVALANCHE_CLI_BIN" ]] || {
    demo_error "Pinned AvalancheGo, Subnet-EVM, or Avalanche CLI binary is missing."
    exit 1
}
AVAGO_VERSION="$("$AVALANCHEGO_BIN" --version 2>&1 | head -1)"
SEVM_VERSION="$("$LOCAL_BIN_DIR/subnet-evm" --version 2>&1 | head -1)"
[[ "$AVAGO_VERSION" == *"avalanchego/1.14.2"* && "$AVAGO_VERSION" == *"rpcchainvm=45"* ]] || {
    demo_error "AvalancheGo version or VM protocol does not match the approved runtime."
    exit 1
}
[[ "$SEVM_VERSION" == *"v1.14.2"* && "$SEVM_VERSION" == *"rpcchainvm=45"* ]] || {
    demo_error "Subnet-EVM version or VM protocol does not match AvalancheGo."
    exit 1
}

python3 - "$WORKSPACE_ROOT/chain/genesis/dev-genesis.json" "$EXPECTED_CHAIN_ID" "$EXPECTED_CHAIN_ID_HEX" <<'PYCHAIN'
import json, sys
path, expected_dec, expected_hex = sys.argv[1:]
with open(path, encoding="utf-8") as f:
    genesis = json.load(f)
actual = int(genesis["config"]["chainId"])
if actual != int(expected_dec) or hex(actual) != expected_hex:
    raise SystemExit(f"development genesis chain ID mismatch: expected {expected_dec} ({expected_hex})")
print(f"Development genesis Chain ID verified: {actual} ({hex(actual)})")
PYCHAIN

[[ -d "$HOST_CLI_HOME" && ! -L "$HOST_CLI_HOME" ]] || {
    demo_error "The existing host CLI home is missing or is a symlink; refusing to mask an unexpected path."
    exit 1
}
[[ "$(stat -c '%a' "$HOST_CLI_HOME")" == "700" ]] || {
    demo_error "Existing host CLI home permissions changed; stopping for review."
    exit 1
}

if [[ ! -e "$RUNTIME_ROOT" ]]; then
    assert_runtime_layout
    mkdir -m 700 "$RUNTIME_ROOT"
fi
assert_runtime_layout

for dir in "$CLI_HOME" "$ROOT_HOME" "$TMP_DIR" "$CONFIG_DIR" \
    "$CONFIG_DIR/genesis" "$LOCAL_DATA_DIR" "$PRIVATE_DIR" \
    "$METADATA_DIR" "$PID_DIR" "$LOG_DIR" "$CACHE_DIR" \
    "$RUNTIME_ROOT/xdg-cache" "$RUNTIME_ROOT/xdg-config" "$RUNTIME_ROOT/xdg-data"; do
    [[ ! -L "$dir" ]] || { demo_error "Refusing symlink runtime directory: $dir"; exit 1; }
    if [[ ! -d "$dir" ]]; then
        mkdir -m 700 "$dir"
    fi
    chmod 700 "$dir"
done
mkdir -m 700 -p "$ROOT_HOME/.avalanche-cli"
assert_runtime_layout

git -C "$WORKSPACE_ROOT" check-ignore -q "$RUNTIME_ROOT" || {
    demo_error "Runtime root is not excluded from Git."
    exit 1
}
grep -Fq '.local-networks/' "$WORKSPACE_ROOT/.replitignore" || {
    demo_error "Runtime root is not excluded from deployment artifacts."
    exit 1
}
grep -Fq "'**/.local-networks/**'" "$WORKSPACE_ROOT/artifacts/pwcscan/vite.config.ts" || {
    demo_error "PWCScan development server does not deny the runtime path."
    exit 1
}

if [[ -f "$DEMO_READY_FILE" ]]; then
    read_demo_state
elif [[ -e "$DEMO_ATTEMPT_FILE" ]]; then
    demo_error "An earlier initialization did not reach verification; preserving it and refusing an automatic retry."
    exit 1
else
    for dir in "$CLI_HOME" "$PRIVATE_DIR" "$CONFIG_DIR/genesis" "$LOCAL_DATA_DIR"; do
        if [[ -n "$(find "$dir" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
            demo_error "Unverified files already exist in $dir; inspect them before initialization."
            exit 1
        fi
    done
fi

export PWDEMO_HOST_ACCOUNT_HOME="$HOST_ACCOUNT_HOME"
printf '[pw-demo-02] Pinned runtime: %s; Subnet-EVM: %s; VM protocol: rpcchainvm=45.\n' \
    "$AVAGO_VERSION" "$SEVM_VERSION"
printf '[pw-demo-02] Testing the isolated mount layout before any key generation or node startup.\n'
unshare --user --map-root-user --mount --fork \
    bash "$DEMO_SCRIPT_DIR/namespace-entry.sh" preflight

if [[ -f "$DEMO_READY_FILE" ]]; then
    printf '[pw-demo-02] Existing verified identity found; attempting restart from the same isolated data.\n'
else
    printf '[pw-demo-02] Isolation gate passed; initializing one new local network.\n'
fi
unshare --user --map-root-user --mount --fork \
    bash "$DEMO_SCRIPT_DIR/namespace-entry.sh" start
