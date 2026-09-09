"""Command registry and shared CLI contracts for VTX diagnostics."""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from enum import IntEnum
from typing import Sequence, TextIO

from . import audio_compare, audio_compare_smoke


class _HelpFormatter(argparse.HelpFormatter):
    """Use a fixed width so help output is independent of terminal settings."""

    def __init__(self, prog: str) -> None:
        super().__init__(prog, max_help_position=24, width=88)


class ExitCode(IntEnum):
    """Stable process exit codes shared by unified diagnostic commands."""

    SUCCESS = 0
    FAILURE = 1
    USAGE_ERROR = 2
    MIGRATION_PENDING = 3


class DiagnosticError(Exception):
    """A user-facing diagnostic command failure with a stable exit code."""

    def __init__(self, message: str, exit_code: ExitCode = ExitCode.FAILURE) -> None:
        super().__init__(message)
        self.exit_code = exit_code


@dataclass(frozen=True)
class CommandSpec:
    """Registration metadata for one unified diagnostic command family."""

    name: str
    summary: str
    compatibility_paths: tuple[str, ...]


COMMAND_REGISTRY: dict[str, CommandSpec] = {
    spec.name: spec
    for spec in (
        CommandSpec(
            name="audio_compare",
            summary="Compare audio output or run the local comparison smoke workflow.",
            compatibility_paths=(
                "scripts/audio-compare.py",
                "scripts/local-reference-compare-smoke.py",
                "scripts/analyze-audio-discontinuities.py",
                "scripts/stem-scaling-diagnostics.py",
            ),
        ),
        CommandSpec(
            name="reference_triage",
            summary="Triage reference-render mismatches (migration pending).",
            compatibility_paths=(
                "scripts/correlate-audio-comparison.py",
                "scripts/focused-window-voice-timeline.py",
                "scripts/focused-xm-channel-diagnostics.py",
                "scripts/summarize-reference-render-triage.py",
            ),
        ),
        CommandSpec(
            name="effect_coverage",
            summary="Summarize XM effect coverage (migration pending).",
            compatibility_paths=("scripts/summarize-xm-effect-coverage.py",),
        ),
        CommandSpec(
            name="residual_scan",
            summary="Scan residual effect behavior (migration pending).",
            compatibility_paths=("scripts/summarize-xm-residual-effect-scan.py",),
        ),
        CommandSpec(
            name="runtime_trace",
            summary="Summarize and correlate runtime traces (migration pending).",
            compatibility_paths=(
                "scripts/summarize-runtime-c-mixer-trace.py",
                "scripts/correlate-runtime-offline-window.py",
                "scripts/run-local-corpus-runtime-metrics.py",
            ),
        ),
        CommandSpec(
            name="corpus_map",
            summary="Maintain redacted local corpus maps (migration pending).",
            compatibility_paths=("scripts/update-private-xm-corpus-label-map.py",),
        ),
    )
}


def _configure_audio_compare_parser(parser: argparse.ArgumentParser) -> None:
    """Register the migrated compare and smoke modes on the audio family parser."""

    modes = parser.add_subparsers(dest="audio_compare_mode", metavar="MODE", required=True)
    compare_parser = modes.add_parser(
        "compare",
        help="Compare reference and candidate WAV files.",
        description=audio_compare.COMPARE_DESCRIPTION,
        formatter_class=_HelpFormatter,
    )
    audio_compare.add_arguments(compare_parser)
    compare_parser.set_defaults(command_handler=audio_compare.run)

    smoke_parser = modes.add_parser(
        "smoke",
        help="Run a comparison with local-only report defaults.",
        description=audio_compare_smoke.SMOKE_DESCRIPTION,
        formatter_class=_HelpFormatter,
    )
    audio_compare_smoke.add_arguments(smoke_parser)
    smoke_parser.set_defaults(command_handler=audio_compare_smoke.run)


def build_parser() -> argparse.ArgumentParser:
    """Build the deterministic top-level parser from the command registry."""

    parser = argparse.ArgumentParser(
        prog="python3 -m tools.vtx_diag",
        description="Unified VoodooTracker X diagnostic commands.",
        formatter_class=_HelpFormatter,
    )
    subparsers = parser.add_subparsers(dest="command", metavar="COMMAND", required=True)
    for spec in COMMAND_REGISTRY.values():
        command_parser = subparsers.add_parser(
            spec.name,
            help=spec.summary,
            description=spec.summary,
            formatter_class=_HelpFormatter,
        )
        command_parser.set_defaults(command_spec=spec)
        if spec.name == "audio_compare":
            _configure_audio_compare_parser(command_parser)
    return parser


def dispatch(arguments: argparse.Namespace) -> int:
    """Dispatch a migrated command or report the family's migration status."""

    handler = getattr(arguments, "command_handler", None)
    if handler is not None:
        return int(handler(arguments))

    spec = arguments.command_spec
    compatibility_paths = ", ".join(spec.compatibility_paths)
    raise DiagnosticError(
        f"{spec.name}: not yet migrated; current authoritative script family: "
        f"{compatibility_paths}",
        ExitCode.MIGRATION_PENDING,
    )


def main(argv: Sequence[str] | None = None, stderr: TextIO | None = None) -> int:
    """Parse and dispatch a diagnostic command, returning a stable exit code."""

    parser = build_parser()
    try:
        arguments = parser.parse_args(argv)
    except SystemExit as error:
        return int(error.code)

    try:
        return dispatch(arguments)
    except DiagnosticError as error:
        print(f"vtx_diag: {error}", file=stderr or sys.stderr)
        return int(error.exit_code)
