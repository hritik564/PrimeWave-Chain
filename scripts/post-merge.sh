#!/bin/bash
set -euo pipefail

pnpm install --frozen-lockfile

printf '%s\n' '[post-merge] Database schema changes are not applied automatically.'
printf '%s\n' '[post-merge] Use the reviewed migration workflow only after confirming a non-production database target.'
