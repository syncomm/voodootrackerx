"""Regression coverage for the public effect-status vocabulary gate."""

import importlib.util
from pathlib import Path
import unittest


SPEC = importlib.util.spec_from_file_location(
    "effect_status", Path(__file__).with_name("check_effect_status.py")
)
CHECKER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECKER)

LAYOUTS = {
    "ft2-xm-closure-matrix.md": [
        ["Bounded behavior", "Status", "Verified scope / remaining boundary", "Evidence"],
        ["ID / behavior", "Status", "Gap / remaining behavior", "Evidence / owner"],
        ["Boundary", "Status", "Reason / scope"],
    ],
    "xm-effect-support.md": [
        ["Command", "Name", "Support", "FT2 closure", "FT2 memory", "VTX pitch mode", "Notes"],
        ["Command family", "Support", "FT2 closure", "FT2 memory", "VTX pitch mode", "Notes"],
    ],
}


def document(name, value="Closed", notes="Evidence", leading=True):
    """Build independent fixtures for the actual table widths/column positions."""
    tables = []
    for headers in LAYOUTS[name]:
        row = ["Evidence"] * len(headers)
        row[0], row[-1] = "Example", notes
        status = "Status" if "Status" in headers else "FT2 closure"
        row[headers.index(status)] = value
        if "Support" in headers:
            row[headers.index("Support")] = "Implemented"
        separators = ["---"] * len(headers)
        separators[1] = ":---:"
        rows = [headers, separators, row]
        tables.append("\n".join(
            ("| " if leading else "") + " | ".join(row) + (" |" if leading else "")
            for row in rows
        ))
    return "\n\n".join(tables)


class EffectStatusTests(unittest.TestCase):
    def test_all_canonical_values_in_both_documents_and_table_layouts(self):
        for name in LAYOUTS:
            for value in ["Closed", "Partial", "Open", "Known difference", "Needs characterization", "Outside v1"]:
                with self.subTest(document=name, status=value):
                    count, errors = CHECKER.validate_document(document(name, value), name)
                    self.assertEqual(errors, [])
                    self.assertEqual(count, len(LAYOUTS[name]))

    def test_rejects_case_variants_compound_and_unknown_statuses(self):
        for name in LAYOUTS:
            for value in ["CLOSED", "Closed G12", "Partial; G27 closed", "Bogus", "**Closed**"]:
                with self.subTest(document=name, status=value):
                    _, errors = CHECKER.validate_document(document(name, value), name)
                    self.assertEqual(len(errors), len(LAYOUTS[name]))
                    self.assertTrue(all(name in e and "Example" in e and repr(value) in e for e in errors))
                    self.assertIn(":3:", errors[0])

    def test_escaped_pipes_optional_outer_pipes_and_header_formatting(self):
        for name in LAYOUTS:
            text = document(name, notes=r"link \| evidence", leading=False)
            for headers in LAYOUTS[name]:
                first = headers[0]
                status = "Status" if "Status" in headers else "FT2 closure"
                text = text.replace(first + " |", f"**{first.title()}** |").replace(" | " + status + " |", f" | `{status}` |")
            self.assertEqual(CHECKER.validate_document(text, name)[1], [])

    def test_ignores_unrelated_columns_prose_and_tables(self):
        for name in LAYOUTS:
            text = document(name, notes="CLOSED; Partial G12; unknown")
            text += "\n\nCLOSED is a historical quote.\n\n| Measurement | Status |\n| --- | --- |\n| CI | PASS |\n"
            self.assertEqual(CHECKER.validate_document(text, name)[1], [])

    def test_fenced_examples_do_not_create_or_replace_target_tables(self):
        for name in LAYOUTS:
            for fence in ["```", "~~~~"]:
                text = fence + "markdown\n" + document(name, "CLOSED") + "\n" + fence + "\n\n" + document(name)
                self.assertEqual(CHECKER.validate_document(text, name)[1], [])
                self.assertTrue(CHECKER.validate_document(fence + "\n" + document(name) + "\n" + fence, name)[1])

    def test_missing_table_or_renamed_status_header_fails(self):
        for name in LAYOUTS:
            self.assertTrue(CHECKER.validate_document("No closure tables", name)[1])
            header = "Status" if name.startswith("ft2-") else "FT2 closure"
            errors = CHECKER.validate_document(document(name).replace(header, "renamed"), name)[1]
            self.assertTrue(all("expected one" in e for e in errors))

    def test_missing_status_cell_is_reported(self):
        name = "ft2-xm-closure-matrix.md"
        text = "\n".join("| Example |" if line.startswith("| Example |") else line
                         for line in document(name).splitlines())
        self.assertTrue(CHECKER.validate_document(text, name)[1])


if __name__ == "__main__":
    unittest.main()
