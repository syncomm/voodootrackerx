#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

declare -a MARKER_LABELS=()
declare -a MARKER_VALUES=()

add_marker() {
  local label="$1"
  local marker
  shift
  printf -v marker "%s" "$@"
  MARKER_LABELS+=("$label")
  MARKER_VALUES+=("$marker")
}

add_marker "macOS absolute home path" "/" "Users"
add_marker "local desktop path component" "Desk" "top"
add_marker "maintainer machine note with apostrophe" "Gregory" "'" "s machine"
add_marker "maintainer machine note" "Gregory" "s machine"
add_marker "private module sentinel with underscore" "_" "DARK" "L"
add_marker "private module sentinel" "DARK" "L"
add_marker "private corpus label-map filename" "vtx-private-xm-corpus-label" "-map"

is_allowed_tracker_fixture() {
  case "$1" in
    tests/fixtures/minimal.xm | \
    tests/reference-xm/generated/basic-instrument-sample.xm | \
    tests/reference-xm/generated/multi-pattern-loop-boundary.xm | \
    tests/reference-xm/generated/instrument-sustained-defaults.xm | \
    tests/fixtures/minimal.mod)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_forbidden_artifact_path() {
  case "$1" in
    *.wav | *.dmg | *.jsonl | *.profraw | *.trace | *.log | *.app | *.app/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_tracker_module_path() {
  case "$1" in
    *.xm | *.mod)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

declare -a FAILURES=()

while IFS= read -r -d '' path; do
  if is_forbidden_artifact_path "$path"; then
    FAILURES+=("$path: tracked generated/local artifact path is not allowed")
  fi

  if is_tracker_module_path "$path" && ! is_allowed_tracker_fixture "$path"; then
    FAILURES+=("$path: tracked tracker module is not in the public fixture allowlist")
  fi

  if [[ -f "$path" ]] && grep -Iq . "$path"; then
    for index in "${!MARKER_VALUES[@]}"; do
      marker="${MARKER_VALUES[$index]}"
      label="${MARKER_LABELS[$index]}"
      while IFS=: read -r line_number _; do
        FAILURES+=("$path:$line_number: contains blocked marker ($label)")
      done < <(grep -nF "$marker" -- "$path" || true)
    done
  fi
done < <(git ls-files -z)

if ((${#FAILURES[@]} > 0)); then
  echo "Tracked private/local/artifact leak scan failed:" >&2
  printf '  - %s\n' "${FAILURES[@]}" >&2
  echo >&2
  echo "Move private inputs and generated outputs outside the repository, or add only reviewed public fixtures to the allowlist." >&2
  exit 1
fi

echo "Tracked private/local/artifact leak scan passed."
