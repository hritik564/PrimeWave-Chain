#!/usr/bin/env bash
# Public-network production/Fuji validator gate. No defaults, key generation,
# directory creation or network initialization. Check-only unless both startup
# flags are explicitly passed. Development launchers do not use this wrapper.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$SCRIPT_DIR/mainnet/validator.py" "$@"
