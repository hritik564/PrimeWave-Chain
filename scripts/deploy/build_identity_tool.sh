#!/usr/bin/env bash
# Build only; never creates identities, starts nodes or contacts Avalanche RPC.
set -euo pipefail
OUT="${1:?new absolute output directory required}"
[[ "$OUT" = /* && ! -e "$OUT" ]] || { echo 'Use a new absolute build directory' >&2; exit 1; }
[[ "$(go env GOVERSION)" = go1.26.8 ]] || { echo 'Pinned Go1.26.8 required' >&2; exit 1; }
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mkdir -m 700 "$OUT"
git clone --filter=blob:none --no-checkout https://github.com/ava-labs/avalanchego "$OUT/source"
git -C "$OUT/source" checkout --detach fdb2c1b9b02ef357b5867d5ababb6acc83837a01
mkdir "$OUT/source/primewave-identity"
cp "$ROOT/tools/fresh-identity/main.go" "$OUT/source/primewave-identity/main.go"
(cd "$OUT/source" && go build -trimpath -o "$OUT/primewave-fresh-identity" ./primewave-identity)
sha256sum "$OUT/primewave-fresh-identity"
