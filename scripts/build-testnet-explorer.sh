#!/usr/bin/env bash
set -euo pipefail

# Production build only. This intentionally does not start a chain, an indexer,
# or any local-development workflow.
pnpm --filter @workspace/pwcscan run build
pnpm --filter @primewave/indexer run build