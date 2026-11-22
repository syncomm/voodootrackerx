import contextlib
import copy
import importlib.util
import io
import json
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


class NativePackageReleaseCountTests(unittest.TestCase):
    def setUp(self):
        self.cases = [f"BaselineTests/testCase{i}" for i in range(975)] + [
            "OrdinaryAbsentKeymapTests/" + method for method in [
                "testExactMapSelectsDistinguishableSparsePCMAndMissingRouteRetainsIdentity",
                "testLoadedShortAndPartialSampledHeadersRemainUnchangedAndCannotFallback",
                "testNilPCMAndNeutralRoutesDoNotStartOrCutAtImmediateED0OrED3Dispatch",
                "testNilToneTargetsPreserveSourceAndExistingSlideWithoutSelectingPCM",
            ]
        ] + ["XMPanningEnvelopeTests/" + method for method in [
            "testPanQ8IndependentNativeVectorsAndFinalTargetsPreserveRawPoints",
            "testPanQ8SubQuantumSlopesArriveExactlyAcrossThe64RowWindow",
            "testPanQ8PendingCarryAndResetKeepBoundedOutputInBothProfiles",
            "testLogicalPanSustainReleaseBoundariesKeepTheAuthoredTailInBothModes",
            "testLogicalPanReleaseKeepsSilentPCMAndExactEmptyRouteDistinct",
        ]]
        self.cases[0] = "XMVolumeEnvelopeQ8Tests/testNongridPanHasItsOwnPointDomainAndPublicVolumeFixtureMatchesEveryWindow"

    def output(self, cases):
        rows = ["Test Case '-[%s %s]' passed (0.001 seconds)." % tuple(case.split("/"))
                for case in cases]
        return "\n".join(rows + [f"Executed {len(cases)} tests, with 0 failures"])

    def test_full_count_includes_policy_b_pan_q8_logical_release_and_renamed_g31(self):
        self.assertEqual(HELPER.PACKAGE_RELEASE_COUNT, 984)
        self.assertEqual(HELPER.package_cases(self.output(self.cases), HELPER.PACKAGE_RELEASE_COUNT, self.cases),
                         self.cases)
        self.assertEqual(HELPER.package_cases(self.output(self.cases).replace(
            "0 failures", "0 failures (0 unexpected) in 1.234 (1.234) seconds"), 984, self.cases), self.cases)

    def test_incomplete_nonpassing_or_stale_package_counts_still_fail_closed(self):
        exact = self.output(self.cases)
        invalid = [self.output(self.cases[:-7]), self.output(self.cases[:-3]), self.output(self.cases[:-2]), self.output(self.cases[:-1]),
                   self.output(self.cases + self.cases[-1:]),
                   self.output(self.cases + ["Unexpected/testExtra"]),
                   self.output(self.cases[:-1] + self.cases[-2:-1]),
                   self.output(self.cases[:-1] + ["Unexpected/testReplacement"]),
                   exact.replace("Executed 984", "Executed 982"),
                   exact.replace("Executed 984", "Executed 983")]
        invalid += [exact.replace("passed", status, 1) for status in
                    ["failed", "skipped", "expected failure", "unexpected failure"]]
        invalid += [exact.replace("0 failures", summary) for summary in
                    ["1 failures", "0 failures (1 unexpected)", "0 failures, 1 expected failure",
                     "0 failures, 1 skipped"]]
        invalid.append(exact + "\nExecuted 984 tests, with 1 failures")
        for text in invalid:
            with self.subTest(text=text[-100:]), self.assertRaises(AssertionError):
                HELPER.package_cases(text, HELPER.PACKAGE_RELEASE_COUNT, self.cases)
        with self.assertRaises(AssertionError):
            HELPER.package_cases(exact, 982)


class NativeAppReleaseCountTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="vtx-native-app-count-", dir="/private/tmp")
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.cases = [f"BaselineTests/testCase{i}" for i in range(1908)] + [
            "ClearSongDataAdmissionTests/" + method for method in [
                "testClearedExactSparsePaletteExportsAndReopensWithIdenticalPCMSelection",
                "testExactSparsePCMAndRetainedNeutralInstrumentsKeepExistingBridgeEligibility",
                "testLoadedNilPCMAndMixedPalettesAreRefusedAtFactoryAndConfirmation",
                "testMenuAndSongOrderEntriesAgreeOnAdmissionCancelFailureAndFreshConfirmation",
                "testPendingConfirmationRevalidatesNilPCMMixedPlaybackAndPresentationChanges",
            ]
        ] + [
            "EditableXMWriterTests/testMixedNeutralAndMappedZeroVolumePCMInstrumentsReopenExactly",
            "ExportXMCoordinatorTests/testNilMapPCMInLaterInstrumentPreservesDestinationAndDoesNotCreateNewFile",
            "EditableXMWriterTests/testPanQ8PlaybackKeepsRaw64ThroughWriterAndLoadedReopen",
            "RuntimeCMixerTests/testPanQ8AndRaw64ShareExactCoreTargetsAndCanonicalFramesInBothModes",
            "RuntimeCMixerTests/testLogicalPanSustainReleaseSharesExactCoreFramesTargetsAndPCM",
        ]
        self.summary = dict(totalTestCount=1918, passedTests=1918, failedTests=0,
                            skippedTests=0, expectedFailures=0)
        self.tests = {"devices": [{"architecture": "arm64"}], "testNodes": [
            {"nodeType": "Test Case", "result": "Passed", "nodeIdentifier": case + "()"}
            for case in self.cases
        ]}

    def validate(self, summary, tests):
        with mock.patch.object(HELPER, "root", self.root), \
                mock.patch.object(HELPER, "output", side_effect=[json.dumps(summary), json.dumps(tests)]):
            return HELPER.result_cases(self.root / "release-app.xcresult", HELPER.APP_RELEASE_COUNT, self.cases)

    def test_full_count_includes_admission_keymap_pan_q8_and_logical_release(self):
        self.assertEqual(HELPER.APP_RELEASE_COUNT, 1918)
        self.assertEqual(self.validate(self.summary, self.tests), self.cases)

    def test_missing_duplicate_failed_skipped_unexpected_and_non_native_cases_fail_closed(self):
        invalid = []
        for missing in [1, 2, 9]:
            summary, tests = copy.deepcopy(self.summary), copy.deepcopy(self.tests)
            summary.update(totalTestCount=1918 - missing, passedTests=1918 - missing)
            tests["testNodes"] = tests["testNodes"][:-missing]
            invalid.append((summary, tests))
        duplicate = copy.deepcopy(self.tests)
        duplicate["testNodes"][-1] = copy.deepcopy(duplicate["testNodes"][-2])
        extra = copy.deepcopy(self.tests)
        extra["testNodes"].append(dict(nodeType="Test Case", result="Passed", nodeIdentifier="Unexpected/testExtra()"))
        replaced = copy.deepcopy(self.tests)
        replaced["testNodes"][-1]["nodeIdentifier"] = "Unexpected/testReplacement()"
        invalid.extend([(self.summary, duplicate), (self.summary, extra), (self.summary, replaced)])
        for status in ["Failed", "Skipped", "Expected Failure", "Unexpected"]:
            tests = copy.deepcopy(self.tests)
            tests["testNodes"][-1]["result"] = status
            invalid.append((self.summary, tests))
        for field, value in [("totalTestCount", 1915), ("passedTests", 1916),
                             ("totalTestCount", "1918"), ("failedTests", False),
                             ("failedTests", 1), ("skippedTests", 1), ("expectedFailures", 1)]:
            invalid.append((dict(self.summary, **{field: value}), self.tests))
        non_native = copy.deepcopy(self.tests)
        non_native["devices"][0]["architecture"] = "x86_64"
        invalid.append((self.summary, non_native))
        mixed = copy.deepcopy(self.tests)
        mixed["devices"].append({"architecture": "x86_64"})
        invalid.append((self.summary, mixed))
        missing_device = copy.deepcopy(self.tests)
        missing_device["devices"] = []
        invalid.append((self.summary, missing_device))
        for summary, tests in invalid:
            with self.subTest(summary=summary), self.assertRaises(AssertionError):
                self.validate(summary, tests)


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


class PackageASanCompilerModeTests(unittest.TestCase):
    clang = "/toolchain/bin/clang -O0 -fsanitize=address -c MixerCore.c\n"
    swift = "/toolchain/bin/swiftc -module-name PlaybackSupport -Onone"

    def test_unescaped_swift_driver_option_passes(self):
        log = self.clang + self.swift + " -sanitize=address -c Playback.swift\n"
        self.assertTrue(HELPER.package_asan_compiler_modes(log))

    def test_xcode_escaped_swift_driver_option_passes(self):
        clang = "    -fmodules -gmodules -O0 -DSWIFT_PACKAGE '-fsanitize=address'\n"
        for wrapper in ("builtin-SwiftDriver", "builtin-Swift-Compilation",
                        "builtin-Swift-Compilation-Requirements"):
            with self.subTest(wrapper=wrapper):
                log = clang + f"    {wrapper} -- '/Xcode Toolchain/bin/swiftc' "
                log += r"-module-name PlaybackSupport -Onone -sanitize\=address @Sources.SwiftFileList"
                self.assertTrue(HELPER.package_asan_compiler_modes(log))

    def test_requires_swift_asan(self):
        self.assertFalse(HELPER.package_asan_compiler_modes(self.clang + self.swift))

    def test_requires_clang_asan(self):
        log = self.clang.replace("-fsanitize=address ", "") + self.swift + r" -sanitize\=address"
        self.assertFalse(HELPER.package_asan_compiler_modes(log))

    def test_requires_unoptimized_swift_in_same_command(self):
        optimized = self.swift.replace("-Onone", "-O") + r" -sanitize\=address"
        for extra in ("", "\nwarning: -Onone omitted", "\n" + self.swift):
            with self.subTest(extra=extra):
                self.assertFalse(HELPER.package_asan_compiler_modes(self.clang + optimized + extra))

    def test_rejects_swift_asan_outside_compiler_arguments(self):
        for flag in ("-sanitize=address", r"-sanitize\=address"):
            for line in (f"# {self.swift} {flag}", f"{self.swift} # expected {flag}",
                         f"{self.swift} /sources/{flag}.swift", f"warning: expected {self.swift} {flag}",
                         f"echo {self.swift} {flag}", f"{self.swift} && echo {flag}",
                         f"{self.swift} -- {flag}", f"{self.swift} -Xcc {flag}"):
                with self.subTest(line=line):
                    self.assertFalse(HELPER.package_asan_compiler_modes(self.clang + line))

    def test_rejects_partial_or_malformed_swift_asan_options(self):
        for flag in ("-sanitize=addr", r"-sanitize\=address-extra", "-sanitize address",
                     "--sanitize=address", r"-sanitize\\=address", '"-sanitize=address'):
            with self.subTest(flag=flag):
                self.assertFalse(HELPER.package_asan_compiler_modes(self.clang + self.swift + " " + flag))


class NativeCaseAttributionTests(unittest.TestCase):
    result = Path("/private/tmp/vtx-native-case-control/asan.xcresult")
    selector = "RuntimeLoopNativeEarlyCutoverTests/testOptionalNaturalBoundaryCoalescingAndUnchangedMandatoryDelivery"

    def setUp(self):
        self.row = "Test case '%s()' passed on 'My Mac - xctest (123)' (0.004 seconds)\n" % self.selector.replace("/", ".")
        split = self.row.index("Coalescing") + len("Coalesc")
        self.left, self.right = self.row[:split], self.row[split:]
        self.footer = "\nTest session results, code coverage, and logs:\n\t%s\n\n** TEST SUCCEEDED **\n\n" % self.result

    def test_native6_exact_footer_reconstructs_complete_case_and_preserves_removal_hash(self):
        raw = self.left + self.footer + self.right
        self.assertEqual(HELPER.app_case_pid_mapping(raw), [])
        derived, removed = HELPER.app_case_attribution_text(raw, self.result)
        self.assertEqual(derived, self.row)
        self.assertEqual(HELPER.app_case_pid_mapping(derived), [(self.selector, 123)])
        self.assertEqual(removed, [{"SHA256": HELPER.hashlib.sha256(self.footer.encode()).hexdigest(),
                                    "byteCount": len(self.footer.encode())}])

    def test_normal_standalone_footer_and_complete_rows_are_unchanged(self):
        for raw in [self.row, self.row + self.footer]:
            with self.subTest(raw=raw):
                derived, removed = HELPER.app_case_attribution_text(raw, self.result)
                self.assertEqual(derived, raw)
                self.assertEqual(removed, [])

    def test_footer_at_every_class_and_method_identifier_split_preserves_exact_attribution(self):
        for split in range(len("Test case '"), self.row.index("()'") + 1):
            with self.subTest(split=split):
                raw = self.row[:split] + self.footer + self.row[split:]
                self.assertEqual(HELPER.app_case_pid_mapping(raw), [])
                derived, removed = HELPER.app_case_attribution_text(raw, self.result)
                self.assertEqual(derived, self.row)
                self.assertEqual(HELPER.app_case_pid_mapping(derived), [(self.selector, 123)])
                self.assertEqual(removed, [{"SHA256": HELPER.hashlib.sha256(self.footer.encode()).hexdigest(),
                                            "byteCount": len(self.footer.encode())}])

    def test_class_split_with_verified_result_path_alias_keeps_existing_identity_check(self):
        with tempfile.TemporaryDirectory(prefix="vtx-native-ci-alias-", dir="/private/tmp") as directory:
            root = Path(directory)
            result = root / "real" / "asan.xcresult"
            result.mkdir(parents=True)
            alias = root / "alias"
            alias.symlink_to(result.parent, target_is_directory=True)
            footer = self.footer.replace(str(self.result), str(alias / result.name))
            split = self.row.index("EarlyCutover")
            derived, removed = HELPER.app_case_attribution_text(self.row[:split] + footer + self.row[split:], result)
            self.assertEqual(derived, self.row)
            self.assertEqual(HELPER.app_case_pid_mapping(derived), [(self.selector, 123)])
            self.assertEqual(removed[0]["SHA256"], HELPER.hashlib.sha256(footer.encode()).hexdigest())

    def test_native5_mixed_stderr_timing_stanza_is_not_generically_deleted(self):
        timing = ("2026-11-16 07:17:28.143 xcodebuild[321:456] [MT] IDETestOperationsObserverDebug: "
                  "124.074 elapsed -- Testing started completed.\n"
                  "2026-11-16 07:17:28.144 xcodebuild[321:456] [MT] IDETestOperationsObserverDebug: "
                  "0.000 sec, +0.000 sec -- start\n"
                  "2026-11-16 07:17:28.144 xcodebuild[321:456] [MT] IDETestOperationsObserverDebug: "
                  "124.074 sec, +124.074 sec -- end\n")
        with self.assertRaisesRegex(AssertionError, "ambiguous interrupted Xcode case row"):
            HELPER.app_case_attribution_text(self.left + timing + self.footer + self.right, self.result)

    def test_wrong_path_malformed_ambiguous_foreign_and_duplicate_rows_fail_closed(self):
        cases = {
            "wrong path": self.left + self.footer.replace("vtx-native-case-control", "vtx-other-control") + self.right,
            "malformed footer": self.left + self.footer.replace("TEST SUCCEEDED", "TEST FAILED") + self.right,
            "duplicate footer": self.left + self.footer + self.footer + self.right,
            "foreign case": self.left.replace("RuntimeLoopNativeEarlyCutoverTests", "OtherTests") + self.footer + self.right,
            "missing suffix": self.left + self.footer,
            "duplicate case": self.row + self.left + self.footer + self.right,
            "injected line": self.left + "unexpected diagnostic\n" + self.footer + self.right,
        }
        for name, raw in cases.items():
            with self.subTest(name=name), self.assertRaises(AssertionError):
                HELPER.app_case_attribution_text(raw, self.result)


if __name__ == "__main__":
    unittest.main()
