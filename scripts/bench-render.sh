#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/bench-render.sh [options] INPUT_XM [OUTPUT_WAV] [-- EXTRA_RENDER_FLAGS...]

Options:
  --output PATH       Write the benchmark WAV to PATH instead of /tmp.
  --order N          Zero-based order index to render. Default: 0.
  --order-count N    Number of playable orders to render. Default: XM song length.
  -h, --help         Show this help.

Defaults are product-comparable for local render/export timing:
  swift run -c release vtx_render_bounded_xm
  --sample-rate 48000
  --wav-format float32
  --mix-profile vtx
  --until-song-end
  --tail-seconds 3
  --window-rows 64
  --allow-long-render
  --auto-headroom

Extra render-tool flags may be passed after --, for example:
  scripts/bench-render.sh tests/reference-xm/generated/basic-instrument-sample.xm -- --progress

Do not use plain "swift run" for performance comparisons; it builds Debug.
Generated WAVs, diagnostics, and timing notes are local artifacts and must not
be committed.
EOF
}

die() {
  printf 'bench-render.sh: %s\n' "$1" >&2
  printf 'Run scripts/bench-render.sh --help for usage.\n' >&2
  exit 2
}

is_non_negative_integer() {
  case "$1" in
    '' | *[!0-9]*)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

is_positive_integer() {
  is_non_negative_integer "$1" && [ "$1" -gt 0 ]
}

detect_xm_order_count() {
  python3 - "$1" <<'PY'
import struct
import sys
from pathlib import Path

data = Path(sys.argv[1]).read_bytes()
if len(data) < 66 or data[:17] != b"Extended Module: ":
    sys.exit(2)

song_length = struct.unpack_from("<H", data, 64)[0]
if song_length <= 0:
    sys.exit(3)

print(song_length)
PY
}

default_output_path() {
  local stamp
  stamp="$(date -u '+%Y%m%d-%H%M%S')"
  printf '/tmp/vtx-render-bench-%s-%s.wav' "$stamp" "$$"
}

print_command() {
  local arg
  printf 'Command:'
  for arg in "$@"; do
    printf ' %q' "$arg"
  done
  printf '\n'
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

input_path=""
output_path=""
order="0"
order_count=""
extra_args=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --output)
      [ "$#" -ge 2 ] || die "missing value for --output"
      output_path="$2"
      shift 2
      ;;
    --order)
      [ "$#" -ge 2 ] || die "missing value for --order"
      order="$2"
      shift 2
      ;;
    --order-count)
      [ "$#" -ge 2 ] || die "missing value for --order-count"
      order_count="$2"
      shift 2
      ;;
    --)
      shift
      extra_args=("$@")
      break
      ;;
    --*)
      die "unknown script option $1; pass render-tool flags after --"
      ;;
    *)
      if [ -z "$input_path" ]; then
        input_path="$1"
      elif [ -z "$output_path" ]; then
        output_path="$1"
      else
        die "unexpected positional argument $1"
      fi
      shift
      ;;
  esac
done

[ -n "$input_path" ] || die "missing INPUT_XM"
[ -f "$input_path" ] || die "input XM does not exist"
is_non_negative_integer "$order" || die "--order must be a non-negative integer"

if [ -z "$order_count" ]; then
  if ! order_count="$(detect_xm_order_count "$input_path")"; then
    die "could not detect XM song length; pass --order-count N"
  fi
fi
is_positive_integer "$order_count" || die "--order-count must be a positive integer"

if [ -z "$output_path" ]; then
  output_path="$(default_output_path)"
  printf 'Output: %s\n' "$output_path"
else
  output_dir="$(dirname "$output_path")"
  [ -d "$output_dir" ] || die "output directory does not exist"
fi

cat <<'EOF'
Release render benchmark mode.
Plain "swift run" builds Debug and is not comparable to this Release timing.
The first run may include SwiftPM Release build work; rerun after the build is warm for steadier render timings.
Generated WAVs, diagnostics, and reports are local artifacts. Keep them out of git.
EOF

cmd=(
  swift run -c release vtx_render_bounded_xm
  --input "$input_path"
  --output "$output_path"
  --order "$order"
  --order-count "$order_count"
  --sample-rate 48000
  --until-song-end
  --tail-seconds 3
  --window-rows 64
  --allow-long-render
  --wav-format float32
  --mix-profile vtx
  --auto-headroom
)

if [ "${#extra_args[@]}" -gt 0 ]; then
  cmd+=("${extra_args[@]}")
fi

print_command "${cmd[@]}"
printf 'Elapsed wall-clock time from /usr/bin/time -p appears as "real" seconds below.\n'
/usr/bin/time -p "${cmd[@]}"
