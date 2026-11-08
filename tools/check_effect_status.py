#!/usr/bin/env python3
"""Check the canonical closure cells in the two XM effect references."""

from pathlib import Path
import re
import sys


STATUSES = frozenset({
    "Closed", "Partial", "Open", "Known difference",
    "Needs characterization", "Outside v1",
})
TABLES = {
    "ft2-xm-closure-matrix.md": {
        "bounded behavior": "status", "id / behavior": "status", "boundary": "status",
    },
    "xm-effect-support.md": {"command": "ft2 closure", "command family": "ft2 closure"},
}


def _cells(line: str) -> list[str]:
    """Split a Markdown row without treating escaped pipes as delimiters."""
    if "|" not in line:
        return []
    cells, escaped = [""], False
    for char in line.strip():
        if char == "|" and not escaped:
            cells.append("")
        else:
            cells[-1] += char
        escaped = char == "\\" and not escaped
    if not cells[0].strip():
        cells.pop(0)
    if cells and not cells[-1].strip():
        cells.pop()
    return [cell.strip() for cell in cells]


def _header(cell: str) -> str:
    return " ".join(cell.strip("`*_ ").split()).casefold()


def _separator(cells: list[str]) -> bool:
    return bool(cells) and all(re.fullmatch(r":?-{3,}:?", cell) for cell in cells)


def validate_document(text: str, document: str) -> tuple[int, list[str]]:
    """Return the checked row count and precise errors for designated tables only.

    Header names identify active closure tables; historical evidence, other
    columns and fenced Markdown examples are deliberately outside this check.
    Missing expected tables/columns fail rather than silently disabling a gate.
    """
    expected = TABLES[Path(document).name]
    lines, seen, errors = text.splitlines(), set(), []
    status_column, fence, checked = None, None, 0
    for index, line in enumerate(lines):
        marker = re.match(r"^ {0,3}(`{3,}|~{3,})", line)
        if marker:
            run = marker.group(1)
            if fence is None:
                fence = (run[0], len(run))
            elif run[0] == fence[0] and len(run) >= fence[1]:
                fence = None
            status_column = None
            continue
        if fence:
            continue
        cells = _cells(line)
        if not cells:
            status_column = None
            continue
        if index + 1 < len(lines) and _separator(_cells(lines[index + 1])):
            headers = [_header(cell) for cell in cells]
            status_column = None
            if headers[0] in expected:
                seen.add(headers[0])
                wanted = expected[headers[0]]
                if headers.count(wanted) != 1:
                    errors.append(f"{document}:{index + 1}: {cells[0]}: expected one {wanted!r} column")
                else:
                    status_column = headers.index(wanted)
            continue
        if _separator(cells) or status_column is None:
            continue
        checked += 1
        value = cells[status_column] if status_column < len(cells) else "<missing>"
        if value not in STATUSES:
            errors.append(f"{document}:{index + 1}: {cells[0]}: invalid status {value!r}")
    for missing in sorted(expected.keys() - seen):
        errors.append(f"{document}: missing closure table {missing!r}")
    return checked, errors


def main() -> int:
    """Validate the repository documents without changing any file."""
    root = Path(__file__).resolve().parents[1]
    checked, errors = 0, []
    for document in TABLES:
        path = root / "docs" / document
        count, problems = validate_document(path.read_text(encoding="utf-8"), f"docs/{document}")
        checked += count
        errors.extend(problems)
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"Effect closure status check passed ({checked} rows).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
