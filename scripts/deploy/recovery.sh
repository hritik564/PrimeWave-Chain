#!/usr/bin/env bash
# Explicit stopped-node encrypted backup/restore. Credentials are provisioned
# locally by the operator via RESTIC_*; never printed or handled by Codex.
set -euo pipefail
MODE="${1:?backup or restore}"; PURPOSE="${2:?fuji-rehearsal or mainnet-pilot}"
ROOT="${3:?existing absolute runtime root}"; APPROVAL="${4:-}"
[[ "$PURPOSE" = fuji-rehearsal || "$PURPOSE" = mainnet-pilot ]] || exit 2
[[ "$ROOT" = /* && -d "$ROOT" && ! -L "$ROOT" && "$APPROVAL" = --approve-recovery-action ]] || exit 2
[[ "$(cat "$ROOT/.managed-purpose")" = "$PURPOSE" ]] || exit 2
[[ -n "${RESTIC_REPOSITORY:-}" && -n "${RESTIC_PASSWORD_FILE:-}" ]] || { echo 'Operator-provisioned encrypted repository/password-file required' >&2; exit 2; }
if systemctl is-active --quiet "primewave-$PURPOSE"; then
  echo 'Stop this node in an approved maintenance window first; two validators have no outage tolerance.' >&2
  exit 1
fi
case "$MODE" in
 backup)
  restic backup "$ROOT" --tag "primewave-$PURPOSE"
  restic check
  ;;
 restore)
  TARGET="${5:?new absolute restore target}"
  [[ "$TARGET" = /* && ! -e "$TARGET" && ! -L "$(dirname "$TARGET")" ]] || exit 2
  restic restore latest --tag "primewave-$PURPOSE" --target "$TARGET"
  echo 'Restore completed into a separate target. Compare PUBLIC identity/registration and preserved DB before operator-approved swap/start.'
  ;;
 *) exit 2;;
esac
