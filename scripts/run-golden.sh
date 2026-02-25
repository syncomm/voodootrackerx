#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

mkdir -p tests/golden

swift run mc_dump --json tests/fixtures/minimal.mod > tests/golden/minimal.mod.json
swift run mc_dump --json tests/fixtures/minimal.xm > tests/golden/minimal.xm.json

echo "Regenerated golden snapshots in tests/golden/."
