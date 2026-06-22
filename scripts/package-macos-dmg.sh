#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/package-macos-dmg.sh APP_PATH TAG OUTPUT_DIR

Creates a plain macOS DMG containing VoodooTrackerX.app and an Applications
symlink. The output file is OUTPUT_DIR/VoodooTrackerX-TAG.dmg.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -ne 3 ]]; then
  usage >&2
  exit 64
fi

APP_PATH="$1"
TAG="$2"
OUTPUT_DIR="$3"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 66
fi

if [[ "$(basename "$APP_PATH")" != "VoodooTrackerX.app" ]]; then
  echo "Expected app bundle named VoodooTrackerX.app: $APP_PATH" >&2
  exit 65
fi

if [[ ! "$TAG" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "Tag contains unsupported characters for an asset name: $TAG" >&2
  exit 65
fi

mkdir -p "$OUTPUT_DIR"

ABS_APP_PATH="$(cd "$(dirname "$APP_PATH")" && pwd)/$(basename "$APP_PATH")"
ABS_OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
DMG_PATH="$ABS_OUTPUT_DIR/VoodooTrackerX-${TAG}.dmg"

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vtx-dmg-staging.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT

cp -R "$ABS_APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"

hdiutil create \
  -volname "VoodooTrackerX ${TAG}" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "$DMG_PATH"
