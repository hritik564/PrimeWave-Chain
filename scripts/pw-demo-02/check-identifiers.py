#!/usr/bin/env python3
"""Reject identifiers already recorded in project history without printing them."""

import re
import sys
from pathlib import Path

if len(sys.argv) != 3:
    raise SystemExit("Expected the newly generated subnet and blockchain identifiers.")

new_ids = {
    "subnet": sys.argv[1],
    "blockchain": sys.argv[2],
}
base58 = re.compile(r"(?<![A-Za-z0-9])[1-9A-HJ-NP-Za-km-z]{52}(?![A-Za-z0-9])")
label = re.compile(r"(?:subnet|blockchain)[\s_-]*id", re.IGNORECASE)
root = Path(__file__).resolve().parents[2]
files = []

for directory, suffixes in (
    (root / "docs", {".md", ".txt"}),
    (root / "config", {".json", ".env", ".md"}),
    (root / "chain", {".json", ".md"}),
):
    if directory.exists():
        files.extend(path for path in directory.rglob("*") if path.is_file() and path.suffix in suffixes)

for filename in ("network-ids.env", "network-state.env"):
    path = root / "local-data" / filename
    if path.is_file():
        files.append(path)

for file_path in files:
    try:
        lines = file_path.read_text(encoding="utf-8", errors="ignore").splitlines()
    except OSError:
        continue
    for line in lines:
        if not label.search(line):
            continue
        values = set(base58.findall(line))
        for kind, value in new_ids.items():
            if value in values:
                relative = file_path.relative_to(root)
                raise SystemExit(
                    f"Generated {kind} identifier collides with historical metadata in {relative}; refusing node startup."
                )

print("Fresh subnet and blockchain identifiers do not match labeled project-history identifiers.")
