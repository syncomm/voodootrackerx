import contextlib
import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import tempfile
import textwrap
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("native_workload_policy", ROOT / ".github/scripts/native-workload-policy.py")
POLICY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(POLICY)
HEAD, BASE, WORKFLOW = "a" * 40, "b" * 40, "c" * 40


def event():
    return {"number": 7, "pull_request": {"head": {"sha": HEAD}, "base": {"sha": BASE}}}


def file(path, status="modified", old=None):
    return {"filename": path, "status": status, **({"previous_filename": old} if old else {})}


class ClassificationTests(unittest.TestCase):
    def classify(self, files, *, count=None, final=None, pages=None, pinned=None):
        metadata = {"head": {"sha": HEAD}, "base": {"sha": BASE},
                    "changed_files": len(files) if count is None else count}
        chunks = [files[i:i + 100] for i in range(0, len(files), 100)] if pages is None else pages
        comparison = {"base_commit": {"sha": BASE}, "total_commits": 2,
                      "commits": [{"sha": "d" * 40}, {"sha": HEAD}], "files": files}
        fetch = mock.Mock(side_effect=[metadata, *chunks, final or copy.deepcopy(metadata),
                                      comparison if pinned is None else pinned])
        return POLICY.classify("pull_request", event(), HEAD, fetch)

    def test_documentation_allowlist_and_all_relevant_roots(self):
        for path in ["README.md", "docs/guide.md", "docs/design/contract.md"]:
            with self.subTest(path=path):
                result = self.classify([file(path)])
                self.assertEqual(result["status"], "NATIVE_NOT_REQUIRED")
                self.assertTrue(result["files_complete"])
                self.assertTrue(result["immutable_diff_verified"])
        for path in ["app/README.md", "app/Engine.swift", "core/parser.c", "Package.swift",
                     ".github/README.md", ".github/scripts/issue516-loop-native-ci.py",
                     ".github/scripts/native-workload-policy.py", "tools/native_workload_policy_tests.py",
                     "tests/reference-xm/fixture.xm", "scripts/check.sh", ".swift-version", "AGENTS.md",
                     "art/logo.png", "unknown.md", "docs/tool.py", "docs/input.xm", "docs/../app/a.md",
                     "/docs/a.md", "docs//a.md", "docs/a\n.md", "docs\\a.md"]:
            with self.subTest(path=path):
                self.assertTrue(self.classify([file(path)])["required"])
        self.assertTrue(self.classify([file("README.md"), file("core/mixer.c")])["required"])

    def test_renames_check_both_paths_and_deletes_keep_their_identity(self):
        for new, old, required in [("docs/new.md", "docs/old.md", False),
                                   ("docs/new.md", "app/old.md", True),
                                   ("app/new.md", "docs/old.md", True)]:
            result = self.classify([file(new, "renamed", old)])
            self.assertEqual(result["required"], required)
            self.assertEqual(result["changed_files"][0]["previous_filename"], old)
        self.assertTrue(self.classify([file("docs/new.md", "renamed")])["required"])
        self.assertFalse(self.classify([file("docs/old.md", "removed")])["required"])
        self.assertTrue(self.classify([file("core/old.c", "removed")])["required"])

    def test_complete_paginated_multi_commit_pr_not_only_last_commit(self):
        for count in [1, 100, 101, 201]:
            with self.subTest(count=count):
                rows = [file(f"docs/{i}.md") for i in range(count)]
                self.assertFalse(self.classify(rows)["required"])
                rows[0] = file("core/changed-in-earlier-commit.c")
                self.assertTrue(self.classify(rows)["required"])

    def test_missing_partial_duplicate_malformed_or_changed_api_data_requires_full(self):
        rows = [file("docs/a.md")]
        for count in [0, -1, True, 3001, "1"]:
            with self.subTest(count=count):
                self.assertTrue(self.classify(rows, count=count)["required"])
        for pages in [[], [[]], [[file("docs/a.md")], []], [None]]:
            self.assertTrue(self.classify(rows * 2, count=2, pages=pages)["required"])
        self.assertTrue(self.classify(rows * 2)["required"])
        for malformed in [{}, {"filename": "docs/a.md"}, file("docs/a.md", "unknown")]:
            self.assertTrue(self.classify([malformed])["required"])
        for final in [{"head": {"sha": WORKFLOW}, "base": {"sha": BASE}, "changed_files": 1},
                      {"head": {"sha": HEAD}, "base": {"sha": WORKFLOW}, "changed_files": 1},
                      {"head": {"sha": HEAD}, "base": {"sha": BASE}, "changed_files": 2}]:
            self.assertTrue(self.classify(rows, final=final)["required"])
        for response in [{}, None, {"head": {"sha": WORKFLOW}}, OSError("API unavailable")]:
            fetch = mock.Mock(side_effect=response if isinstance(response, Exception) else [response])
            self.assertTrue(POLICY.classify("pull_request", event(), HEAD, fetch)["required"])
        self.assertTrue(POLICY.classify("pull_request", {}, HEAD, mock.Mock())["required"])

    def test_non_pr_events_always_require_full_without_a_change_list(self):
        fetch = mock.Mock(side_effect=AssertionError("must not query files"))
        for kind in ["schedule", "workflow_dispatch", "release", "push", "unknown"]:
            self.assertTrue(POLICY.classify(kind, {}, HEAD, fetch)["required"])
        fetch.assert_not_called()

    def test_live_head_away_and_back_or_truncated_immutable_comparison_cannot_skip(self):
        original = {"base_commit": {"sha": BASE}, "total_commits": 1,
                    "commits": [{"sha": HEAD}], "files": [file("core/real-change.c")]}
        for field, value in [("files", [file("core/real-change.c")]), ("files", []),
                             ("base_commit", {"sha": WORKFLOW}), ("commits", [{"sha": WORKFLOW}]),
                             ("total_commits", 301), ("total_commits", True)]:
            pinned = {**original, "files": [file("docs/live-page.md")], field: value}
            self.assertTrue(self.classify([file("docs/live-page.md")], pinned=pinned)["required"])
        self.assertTrue(self.classify([file(f"docs/{i}.md") for i in range(301)])["required"])

    def test_cli_writes_truthful_decision_output_report_and_summary(self):
        with tempfile.TemporaryDirectory(prefix="vtx-policy-cli-", dir="/private/tmp") as directory:
            root = Path(directory)
            (root / "event.json").write_text(json.dumps(event()))
            metadata = {"head": {"sha": HEAD}, "base": {"sha": BASE}, "changed_files": 1}
            pinned = {"base_commit": {"sha": BASE}, "total_commits": 1,
                      "commits": [{"sha": HEAD}], "files": [file("docs/a.md")]}
            env = {"GITHUB_EVENT_NAME": "pull_request", "GITHUB_EVENT_PATH": str(root / "event.json"),
                   "NATIVE_SOURCE_SHA": HEAD, "NATIVE_POLICY_DIR": str(root),
                   "GITHUB_OUTPUT": str(root / "output"), "GITHUB_STEP_SUMMARY": str(root / "summary")}
            with mock.patch.dict(os.environ, env), mock.patch.object(POLICY, "api_get",
                    side_effect=[metadata, [file("docs/a.md")], metadata, pinned]), \
                    mock.patch.object(POLICY.subprocess, "check_output", return_value=HEAD), \
                    contextlib.redirect_stdout(io.StringIO()):
                POLICY.main()
            report = json.loads((root / "classification.json").read_text())
            self.assertFalse(report["required"])
            self.assertEqual(report["source_sha"], HEAD)
            self.assertEqual((root / "output").read_text(), "required=false\n")
            self.assertIn("No native tests executed", (root / "summary").read_text())


class WorkflowSourceTests(unittest.TestCase):
    def expression(self, expression, kind, decision="", head=HEAD, run="101"):
        values = {"github.event.pull_request.head.sha": head, "github.event.pull_request.number": 7,
                  "github.event_name": kind, "steps.policy.outputs.required": decision,
                  "github.workflow": "issue516-loop-native", "github.run_id": run}
        expression = expression.strip().removeprefix("${{").removesuffix("}}")
        for key, value in values.items():
            expression = expression.replace(key, repr(value))
        return eval(expression.replace("&&", " and ").replace("||", " or "),
                    {"__builtins__": {}, "format": lambda template, *args: template.format(*args)})

    def test_stable_check_and_actual_native_step_condition_fail_closed(self):
        workflow = (ROOT / ".github/workflows/issue516-loop-native.yml").read_text()
        self.assertIn("name: issue516-loop-native\n", workflow)
        self.assertIn("    name: Loop continuation arm64 ASan and Release\n", workflow)
        self.assertNotRegex(workflow, r"(?m)^    if:|^\s+paths(?:-ignore)?:")
        condition = re.search(r"name: Qualify submitted native workload and optimized guards\n\s+if: (.*)", workflow)[1]
        for kind in ["pull_request", "workflow_dispatch", "schedule"]:
            for decision in ["true", "false", "", "unknown"]:
                self.assertEqual(self.expression(condition, kind, decision),
                                 kind != "pull_request" or decision != "false")
        self.assertIn("set -euo pipefail", workflow)
        self.assertIn("if: always()", workflow)

    def test_concurrency_cannot_cancel_a_different_head_or_manual_release_run(self):
        workflow = (ROOT / ".github/workflows/issue516-loop-native.yml").read_text()
        group = re.search(r"\n      group: (.*)", workflow)[1]
        cancel = re.search(r"\n      cancel-in-progress: (.*)", workflow)[1]
        suffix = group.split("-", 1)[1]
        groups = [self.expression(suffix, "pull_request", head=HEAD),
                  self.expression(suffix, "pull_request", head=BASE),
                  self.expression(suffix, "workflow_dispatch", run="101"),
                  self.expression(suffix, "workflow_dispatch", run="102"),
                  self.expression(suffix, "schedule", run="103")]
        self.assertEqual(len(set(groups)), len(groups))
        self.assertTrue(self.expression(cancel, "pull_request"))
        self.assertFalse(self.expression(cancel, "workflow_dispatch"))
        self.assertFalse(self.expression(cancel, "schedule"))

    def prepare(self, kind, *, candidate=HEAD, actual=None, source=None, ref="refs/heads/main"):
        workflow = (ROOT / ".github/workflows/issue516-loop-native.yml").read_text()
        match = re.search(r"python3 - <<'PY'\n(.*?)\n\s+PY", workflow, re.S)
        self.assertIsNotNone(match)
        program = textwrap.dedent(match[1])
        directory = tempfile.TemporaryDirectory(prefix="vtx-policy-source-", dir="/private/tmp")
        self.addCleanup(directory.cleanup)
        root = Path(directory.name)
        payload = event() if kind == "pull_request" else {"inputs": {"candidate_sha": candidate}}
        (root / "event.json").write_text(json.dumps(payload))
        expected = WORKFLOW if kind == "schedule" else candidate
        env = {"GITHUB_EVENT_NAME": kind, "GITHUB_EVENT_PATH": str(root / "event.json"),
               "GITHUB_SHA": WORKFLOW, "GITHUB_REF": ref, "GITHUB_WORKFLOW_SHA": WORKFLOW,
               "NATIVE_SOURCE_SHA": source or expected, "NATIVE_POLICY_DIR": str(root)}
        with mock.patch.dict(os.environ, env), \
                mock.patch("subprocess.check_output", return_value=actual or expected), \
                contextlib.redirect_stdout(io.StringIO()):
            exec(compile(program, "workflow-source-validation", "exec"), {})
        return root

    def test_pr_schedule_manual_and_tagged_candidate_bind_actual_source(self):
        for kind, ref, expected in [("pull_request", "refs/pull/7/merge", HEAD),
                                    ("schedule", "refs/heads/main", WORKFLOW),
                                    ("workflow_dispatch", "refs/heads/main", HEAD),
                                    ("workflow_dispatch", "refs/tags/example-rc", HEAD)]:
            root = self.prepare(kind, ref=ref)
            proof = json.loads((root / "source.json").read_text())
            self.assertEqual(proof["source_sha"], expected)
            self.assertEqual(proof["event"], kind)
            envelope = json.loads((root / "helper-event.json").read_text())
            self.assertEqual(envelope["pull_request"]["head"]["sha"], expected)
            self.assertEqual(envelope["native_source"], proof)
            self.assertTrue(json.loads((root / "classification.json").read_text())["required"])

    def test_ambiguous_missing_branch_tag_or_wrong_checkout_cannot_attest(self):
        for candidate in ["", "main", "refs/tags/example-rc", "a" * 39, HEAD + "\n"]:
            with self.subTest(candidate=candidate), self.assertRaises((ValueError, KeyError)):
                self.prepare("workflow_dispatch", candidate=candidate)
        for kind in ["pull_request", "schedule", "workflow_dispatch"]:
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                self.prepare(kind, actual=BASE)
        with self.assertRaises(ValueError):
            self.prepare("pull_request", source=WORKFLOW)


if __name__ == "__main__":
    unittest.main()
