import contextlib
import copy
import importlib.util
import io
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock


HELPER_PATH = Path(__file__).resolve().parents[1] / ".github/scripts/issue516-loop-native-ci.py"
SPEC = importlib.util.spec_from_file_location("issue516_native_ci", HELPER_PATH)
HELPER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(HELPER)


class NativeOutputCollectionTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="vtx-native-ci-tests-", dir="/private/tmp")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.selector = "RuntimeLoopNativeEarlyCutoverTests/testOptionalNaturalBoundaryCoalescingAndUnchangedMandatoryDelivery"
        self.case_row = "Test case '%s()' passed on 'My Mac - xctest (123)' (0.004 seconds)\n" % self.selector.replace("/", ".")

    def collect(self, source):
        context = {"label": "app-asan", "bundleImage": self.root / "no-test-image"}
        with mock.patch.object(HELPER, "root", self.root), \
                mock.patch.dict(HELPER.APP_RUNTIME, context, clear=True), \
                mock.patch.object(HELPER, "runner_pids", return_value=set()), \
                contextlib.redirect_stdout(io.StringIO()):
            return HELPER.run("app-asan", [sys.executable, "-c", source],
                              observe=True, separate_stderr=True)

    def test_stderr_between_partial_stdout_writes_cannot_split_case_identity(self):
        split = self.case_row.index("Coalescing") + len("Coalesc")
        prefix, suffix = self.case_row[:split], self.case_row[split:]
        stderr = "2026-11-16 xcodebuild completion diagnostics\n** TEST SUCCEEDED **\n"
        source = "import os\nos.write(1, %r)\nos.write(2, %r)\nos.write(1, %r)\n" % (
            prefix.encode(), stderr.encode(), suffix.encode())
        text = self.collect(source)
        self.assertEqual(text, self.case_row)
        self.assertEqual(HELPER.app_case_pid_mapping(text), [(self.selector, 123)])
        self.assertEqual((self.root / "app-asan.stderr.log").read_text(), stderr)
        self.assertEqual(HELPER.app_case_pid_mapping(prefix + stderr + suffix), [])

    def test_stderr_case_row_cannot_supply_missing_stdout_attribution(self):
        source = "import os\nos.write(2, %r)\n" % self.case_row.encode()
        text = self.collect(source)
        self.assertEqual(HELPER.app_case_pid_mapping(text), [])
        self.assertEqual((self.root / "app-asan.stderr.log").read_text(), self.case_row)

    def test_sanitizer_finding_on_stderr_still_fails(self):
        source = "import os\nos.write(1, %r)\nos.write(2, b'ERROR: AddressSanitizer: control\\n')\n" % self.case_row.encode()
        with self.assertRaisesRegex(AssertionError, "sanitizer finding"):
            self.collect(source)
        self.assertIn("ERROR: AddressSanitizer", (self.root / "app-asan.stderr.log").read_text())

    def test_nonzero_exit_still_fails_and_retains_both_streams(self):
        source = "import os\nos.write(1, %r)\nos.write(2, b'original failure\\n')\nraise SystemExit(7)\n" % self.case_row.encode()
        with self.assertRaisesRegex(AssertionError, "app-asan failed"):
            self.collect(source)
        self.assertEqual((self.root / "app-asan.log").read_text(), self.case_row)
        self.assertEqual((self.root / "app-asan.stderr.log").read_text(), "original failure\n")


class NativeRuntimeProofTests(unittest.TestCase):
    def setUp(self):
        self.expected = [HELPER.APP[0], HELPER.APP[-1]]
        self.mapping = [(name, 123) for name in self.expected]
        self.context = {"runners": ["/synthetic/xctest"], "baselinePIDs": [],
                        "started": 100, "ended": 103, "bundleSHA256": "synthetic-bundle"}
        self.observations = {123: {"executable": "/synthetic/xctest", "uid": os.getuid(),
                                  "start": [101, 0], "observed": 102,
                                  "bundleMatched": True, "bundleSHA256": "synthetic-bundle",
                                  "optionsMatched": True}}
        self.logs = [{"pid": 123, "safeFile": True, "initPIDs": [123],
                      "sanitizerErrors": 0, "SHA256": "synthetic-log"}]

    def verdict(self, mapping=None, observations=None, logs=None):
        return HELPER.runtime_verdict(self.expected, self.mapping if mapping is None else mapping,
                                      self.observations if observations is None else observations,
                                      self.logs if logs is None else logs, self.context)

    def test_exact_map_required_without_deduplication_or_missing_case_inference(self):
        self.assertTrue(self.verdict()["proven"])
        for mapping in [self.mapping[:-1], self.mapping + self.mapping[-1:],
                        [self.mapping[0], self.mapping[0]],
                        [(self.expected[0], 123), ("Other/testUnexpected", 123)]]:
            with self.subTest(mapping=mapping):
                verdict = self.verdict(mapping=mapping)
                self.assertFalse(verdict["proven"])
                self.assertEqual(verdict["reason"], "incomplete-or-duplicate-test-process-map")

    def test_process_correlated_initialization_and_identity_remain_mandatory(self):
        self.assertFalse(self.verdict(observations={})["proven"])
        for field, value in [("bundleMatched", False), ("optionsMatched", False),
                             ("bundleSHA256", "other-image"), ("executable", "/other/xctest")]:
            observations = copy.deepcopy(self.observations)
            observations[123][field] = value
            with self.subTest(field=field):
                self.assertFalse(self.verdict(observations=observations)["proven"])
        for field, value in [("pid", 456), ("initPIDs", []), ("initPIDs", [456]),
                             ("sanitizerErrors", 1), ("safeFile", False)]:
            logs = copy.deepcopy(self.logs)
            logs[0][field] = value
            with self.subTest(field=field, value=value):
                self.assertFalse(self.verdict(logs=logs)["proven"])


if __name__ == "__main__":
    unittest.main()
