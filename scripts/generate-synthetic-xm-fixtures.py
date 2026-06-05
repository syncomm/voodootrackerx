#!/usr/bin/env python3
"""Deterministic manifest skeleton for future public-safe XM fixtures."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


GENERATOR_NAME = "scripts/generate-synthetic-xm-fixtures.py"
FIRST_FIXTURE_NAME = "basic-instrument-sample.xm"
FIRST_FIXTURE_SOURCE_MANIFEST = "source/basic-instrument-sample.manifest.json"
FIRST_FIXTURE_XM_OUTPUT = "generated/basic-instrument-sample.xm"


def fixture_manifest() -> dict[str, Any]:
    """Return the deterministic public fixture manifest contract."""
    return {
        "schema_version": 1,
        "generator": GENERATOR_NAME,
        "writes_binary_xm_by_default": False,
        "writes_reference_renders_by_default": False,
        "artifact_policy": {
            "binary_xm_commits_require_explicit_review": True,
            "generated_wav_json_markdown_logs_stay_under_tmp_by_default": True,
            "private_modules_allowed": False,
            "private_corpus_dependencies_allowed": False,
        },
        "fixture_pack_layout": {
            "source": "source/",
            "generated_xm": "generated/",
            "reference_renders": "reference-renders/",
        },
        "fixtures": [
            {
                "name": FIRST_FIXTURE_NAME,
                "status": "planned",
                "source_manifest": FIRST_FIXTURE_SOURCE_MANIFEST,
                "xm_output": FIRST_FIXTURE_XM_OUTPUT,
                "reference_render_directory": "reference-renders/",
                "purpose": (
                    "One instrument, one sample, simple note events, and real "
                    "synthetic sample payload for parser/editor positive-path tests."
                ),
                "sample_formula": {
                    "format": "future_signed_8_bit_pcm",
                    "length_frames": 64,
                    "formula": "round(48 * sin(2 * pi * frame / 16))",
                    "loop": None,
                    "normalization": "bounded integer amplitude; no copied sample material",
                },
                "pattern_plan": {
                    "channels": 1,
                    "rows": 16,
                    "events": [
                        {"row": 0, "channel": 0, "note": "C-4", "instrument": 1},
                        {"row": 8, "channel": 0, "note": "key-off"},
                    ],
                },
            }
        ],
    }


def deterministic_json(data: dict[str, Any]) -> str:
    return json.dumps(data, indent=2, sort_keys=True) + "\n"


def resolved_child(output_dir: Path, relative_path: str) -> Path:
    root = output_dir.resolve()
    child = (root / relative_path).resolve()
    try:
        child.relative_to(root)
    except ValueError as exc:
        raise ValueError(f"refusing to write outside output directory: {relative_path}") from exc
    return child


def planned_paths(output_dir: Path) -> dict[str, Path]:
    return {
        "source_manifest": resolved_child(output_dir, FIRST_FIXTURE_SOURCE_MANIFEST),
        "xm_output": resolved_child(output_dir, FIRST_FIXTURE_XM_OUTPUT),
        "reference_render_directory": resolved_child(output_dir, "reference-renders"),
    }


def write_source_manifest(output_dir: Path) -> Path:
    path = planned_paths(output_dir)["source_manifest"]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(deterministic_json(fixture_manifest()), encoding="utf-8")
    return path


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Print or write the deterministic manifest for future synthetic XM fixtures."
    )
    parser.add_argument(
        "--output-dir",
        default="tests/reference-xm",
        type=Path,
        help="Fixture-pack root. Default: tests/reference-xm",
    )
    parser.add_argument(
        "--write-manifest",
        action="store_true",
        help="Write source/basic-instrument-sample.manifest.json under --output-dir.",
    )
    parser.add_argument(
        "--print-paths",
        action="store_true",
        help="Print intended fixture paths relative to the fixture-pack root.",
    )
    args = parser.parse_args(argv)

    paths = planned_paths(args.output_dir)
    if args.print_paths:
        for key in sorted(paths):
            print(f"{key}: {paths[key].relative_to(args.output_dir.resolve())}")
        return 0

    if args.write_manifest:
        written = write_source_manifest(args.output_dir)
        print(f"Wrote {written.relative_to(args.output_dir.resolve())}")
        return 0

    print(deterministic_json(fixture_manifest()), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
