"""Unified VoodooTracker X diagnostic command-line foundation."""

from .cli import COMMAND_REGISTRY, CommandSpec, DiagnosticError, ExitCode, main

__all__ = [
    "COMMAND_REGISTRY",
    "CommandSpec",
    "DiagnosticError",
    "ExitCode",
    "main",
]
