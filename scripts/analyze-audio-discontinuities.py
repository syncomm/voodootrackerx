#!/usr/bin/env python3
"""Compatibility wrapper for package-owned audio discontinuity analysis."""

from __future__ import annotations

import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.vtx_diag.audio_compare_discontinuities import *  # noqa: E402,F403


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
