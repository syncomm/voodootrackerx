"""Module entrypoint for ``python3 -m tools.vtx_diag``."""

from .cli import main


if __name__ == "__main__":
    raise SystemExit(main())
