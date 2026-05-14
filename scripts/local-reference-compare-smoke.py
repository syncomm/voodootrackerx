#!/usr/bin/env python3
"""Local-only wrapper for bounded candidate/reference WAV smoke comparisons."""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
DEFAULT_OUTPUT_DIR = Path("/tmp/vtx-local-reference-comparison")
IGNORED_REPO_DIR_PREFIXES = (
    "local-audio-compare",
    "audio-compare-output",
    "vtx-audio-compare",
)
IGNORED_REPO_FILE_SUFFIXES = (
    "-audio-compare.json",
    "-audio-compare.md",
    "-audio-compare.txt",
)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Compare an existing bounded VoodooTracker X candidate WAV with an "
            "existing local reference WAV using scripts/audio-compare.py."
        )
    )
    parser.add_argument("--candidate", required=True, type=Path, help="Existing VTX candidate WAV path")
    parser.add_argument("--reference", required=True, type=Path, help="Existing local reference WAV path")
    parser.add_argument("--json", dest="json_report", type=Path, help="JSON report path")
    parser.add_argument("--markdown", type=Path, help="Markdown report path")
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_OUTPUT_DIR,
        help=f"Default report directory when --json/--markdown are omitted (default: {DEFAULT_OUTPUT_DIR})",
    )
    parser.add_argument("--label", default="local-reference-smoke", help="Label used for default report filenames")
    parser.add_argument(
        "--metadata",
        default=None,
        help="Optional local note such as order/row bounds; printed only, not embedded in reports",
    )
    parser.add_argument("--seconds", type=float, default=30.0, help="Seconds to compare from the start")
    parser.add_argument("--diff-threshold", type=float, default=1.0e-4, help="First-difference threshold")
    parser.add_argument("--near-silence-threshold", type=float, default=1.0e-5, help="Near-silence threshold")
    parser.add_argument("--window-ms", type=float, default=100.0, help="Worst-window size in milliseconds")
    parser.add_argument("--top-windows", type=int, default=5, help="Number of worst windows to report")
    return parser.parse_args(argv)


def slugify_label(label: str) -> str:
    slug = re.sub(r"[^A-Za-z0-9._-]+", "-", label.strip()).strip("-._")
    return slug or "local-reference-smoke"


def default_report_paths(args: argparse.Namespace) -> tuple[Path, Path]:
    slug = slugify_label(args.label)
    output_dir = args.output_dir
    json_report = args.json_report or output_dir / f"{slug}-audio-compare.json"
    markdown_report = args.markdown or output_dir / f"{slug}-audio-compare.md"
    return json_report, markdown_report


def is_relative_to(path: Path, parent: Path) -> bool:
    try:
        path.resolve().relative_to(parent.resolve())
        return True
    except ValueError:
        return False


def is_ignored_repo_output(path: Path) -> bool:
    resolved = path.resolve()
    if not is_relative_to(resolved, REPO_ROOT):
        return True

    relative = resolved.relative_to(REPO_ROOT.resolve())
    first_part = relative.parts[0] if relative.parts else ""
    if any(first_part.startswith(prefix) for prefix in IGNORED_REPO_DIR_PREFIXES):
        return True
    return any(resolved.name.endswith(suffix) for suffix in IGNORED_REPO_FILE_SUFFIXES)


def validate_existing_wav(path: Path, role: str) -> str | None:
    if not path.exists():
        return f"missing {role} WAV: {path}"
    if not path.is_file():
        return f"{role} WAV is not a file: {path}"
    return None


def validate_output_path(path: Path, role: str) -> str | None:
    if not is_ignored_repo_output(path):
        return (
            f"refusing to write {role} report inside a tracked repo path: {path}. "
            "Use /tmp or an ignored local audio comparison path."
        )
    return None


def print_optional_tool_status() -> None:
    openmpt = shutil.which("openmpt123")
    mikmod = shutil.which("mikmod")
    print(f"Optional reference renderer openmpt123: {'found at ' + openmpt if openmpt else 'not found'}")
    print(f"Optional reference renderer mikmod: {'found at ' + mikmod if mikmod else 'not found'}")
    print("Reference renderers are optional local tools and are not required for CI.")


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    json_report, markdown_report = default_report_paths(args)

    validation_errors = [
        validate_existing_wav(args.candidate, "candidate"),
        validate_existing_wav(args.reference, "reference"),
        validate_output_path(json_report, "JSON"),
        validate_output_path(markdown_report, "Markdown"),
    ]
    errors = [error for error in validation_errors if error is not None]
    if errors:
        for error in errors:
            print(f"local-reference-compare-smoke: {error}", file=sys.stderr)
        return 1

    json_report.parent.mkdir(parents=True, exist_ok=True)
    markdown_report.parent.mkdir(parents=True, exist_ok=True)

    print("Local-only audio comparison smoke.")
    print("Generated WAVs/reports/traces/screenshots are local artifacts and must not be committed.")
    print(f"Label: {args.label}")
    if args.metadata:
        print(f"Metadata: {args.metadata}")
    print_optional_tool_status()
    print(f"JSON report: {json_report}")
    print(f"Markdown report: {markdown_report}")
    print("Delegating metric generation to scripts/audio-compare.py")

    command = [
        sys.executable,
        str(SCRIPT_DIR / "audio-compare.py"),
        "--candidate",
        str(args.candidate),
        "--reference",
        str(args.reference),
        "--json",
        str(json_report),
        "--markdown",
        str(markdown_report),
        "--seconds",
        str(args.seconds),
        "--diff-threshold",
        str(args.diff_threshold),
        "--near-silence-threshold",
        str(args.near_silence_threshold),
        "--window-ms",
        str(args.window_ms),
        "--top-windows",
        str(args.top_windows),
    ]
    result = subprocess.run(command, check=False)
    if result.returncode != 0:
        print("local-reference-compare-smoke: audio-compare.py failed", file=sys.stderr)
        return result.returncode

    print("Comparison complete. Reports are diagnostic evidence only, not a parity claim.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
