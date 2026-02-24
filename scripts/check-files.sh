#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

MISSING=0
for f in LICENSE AGENTS.md README.md; do
  if [ ! -f "$f" ]; then
    echo "Missing required file: $f"
    MISSING=1
  fi
done

if [ $MISSING -ne 0 ]; then
  echo "One or more required files are missing."
  exit 2
fi

echo "Basic file check passed."
