# Sample Lifecycle Alpha Release Readiness

Date: 2026-09-02

## Audited base and entry condition

- Branch: `release/sample-lifecycle-alpha-gate`
- Audited `main`: `647dbfcc691f9d7edc73276fada9bc13b93e3db3`
- Local `main` and `origin/main` were synchronized at `0 0` before the branch
  was created.
- PR #389, `sample/swap-represented-sample-with-slot-ui`, is merged at the
  audited commit and its `macos-checks` result is successful.
- At session start, PR #389 had no formal review and left maintainer listening
  unchecked. Before submission, the maintainer attested that every current
  musician/listening/UI gate item passed, with no failed reproduction.

## Scope and capability boundary

This gate adds no capability and changes no production source. It audits the
already-merged Sample Lifecycle Alpha surface and adds one test-only composed
lifecycle/persistence scenario. The supported boundary remains:

- Sample identities are S01...S16 at the UI and zero-based internally.
- Clear removes one represented sample in place; exact empty-destination
  population restores that identity; Duplicate appends at the tail.
- Move has insertion/shift semantics. Swap exchanges two exact identities,
  including a represented/empty pair.
- Lifecycle mutation is stopped-editable-only and commits through one shared
  document edit/Undo boundary.
- Loaded modules remain read-only. Supported stopped XM files become mutable
  only through Make Editable Copy.
- Save and Save As remain disabled; Export XM remains the persistence route.
- No XM format, parser compatibility, runtime mixer, or tracker viewport
  behavior changed in this gate.

## Audited invariants

- Represented sample values retain PCM and metadata while identities move.
- Every lifecycle permutation applies one bijection to represented indices,
  all 96 map entries, and represented or empty selection.
- Empty mapped identities remain honestly unavailable; no first-playable
  fallback leaks into canonical lifecycle operations.
- Selected sample is editing focus, not routing state.
- Sample Editor preview resolves the exact selected sample directly, while
  Instrument Editor, pattern preview, live playback, and offline render resolve
  the instrument's note map.
- Patterns retain instrument references and never participate in sample-slot
  permutation.
- Success creates exactly one labeled document edit; cancel, stale, malformed,
  read-only, playing, same-slot, and no-op paths create no mutation or history.
- Sparse XM placeholders are canonical all-zero 40-byte headers and are accepted
  for editable copy only with exact source provenance.

## Lifecycle matrix

| Scenario | Required observable | Evidence | Result |
| --- | --- | --- | --- |
| Clear | Remove exact represented identity; preserve map, later samples, patterns, selection; one Undo/Redo | Composed gate test; `testClearSelectedRepresentedSampleRemovesOnlyExactIdentityWithoutCompactingOrRemapping`; coordinator Clear tests | Pass |
| Exact empty repopulation | Populate captured empty Sxx without compaction or remap; restore route; one Undo/Redo | Composed gate test; `testAudioImportPopulatesSelectedInteriorEmptyIdentityWithoutRenumberingOrRemapping`; coordinator population tests | Pass |
| Duplicate | Deep-copy to tail, leave sparse hole and 96-map unchanged, select copy; one Undo/Redo | Composed gate test; `testDuplicateSelectedRepresentedSampleDeepCopiesToTailWithoutFillingSparseHoleOrChangingMap` | Pass |
| Dense Move | Shift represented identities and exact 96-map together; preserve resolved content identity, patterns, and selection; one Undo/Redo | Composed gate test asserts map `1/2/3`; `testSampleSlotPermutationTransactionPreservesDenseSparseMoveAndSwapSemantics` | Pass |
| Sparse Move | For S01=A, S02=empty, S03=C, moving C to S02 preserves C and moves unavailable route to S03 | Composed gate test asserts map `0/2/1`; `testMoveSampleUISparseMoveIntoEmptyPreservesUnavailableRouteAndUndoRedo` | Pass |
| Represented Swap | Exchange two represented identities and map values without changing resolved sample identity | Composed gate test asserts map `1/2/0`; coordinator Swap test | Pass |
| Represented/empty Swap | Move content and unavailable identity pairwise without fabrication or fallback | Composed gate test asserts final map `1/0/2`; represented-empty coordinator test | Pass |
| Selection independence | Changing selected sample does not change mapped resolution; direct Sample audition still targets the selection | Composed gate test; Sample/Instrument audition and keymap-assignment tests | Pass |
| Defenses | State D, malformed maps, stale modal context, read-only, playing, cancel, and same-slot remain no-edit | Permutation rejection tests and Sample Editor modal/import tests | Pass |

The composed test is
`testSampleLifecycleMilestoneGateComposesActionsAndRoundTripsSupportedState`
in `EditableXMWriterTests.swift`. It runs all lifecycle action classes through
one coordinator/history sequence and now asserts the exact 96-entry map after
the sparse Move, dense Move, represented Swap, and represented/empty Swap.

## Persistence and semantic round-trip

The composed final sparse document performs:

`lifecycle operations -> Export XM bytes -> reopen -> Make Editable Copy -> re-export`

The following are compared exactly:

| State family | Exact comparison |
| --- | --- |
| Identity | Instrument identities, sample identities, sparse gap, 96-entry map |
| Sample | PCM, name, volume, panning, relative note, finetune, bit depth, loop start/length/type |
| Instrument | Name, volume envelope including fadeout, panning envelope, autovibrato |
| Song | Patterns/events, channel shape, order table, restart position, speed, BPM |
| Copy/export | Reopened instrument palette equals the final document; editable copy equals it; re-export is byte-identical |

The test uses three distinct I01 samples, a separate I02 sample, three mapped
note regions, two patterns, two orders, non-default restart/BPM, envelopes,
fadeout, autovibrato, mixed sample metadata, and distinguishable PCM. The final
reopen records the exact canonical empty source header before Make Editable Copy.

## Writer, provenance, and atomic safety

- `testDenseAlpha1OutputRemainsByteIdentical` pins the unchanged dense writer
  result.
- `testSparseInteriorGapWritesCanonicalPlaceholderAndReopensExactIdentityAndMap`
  pins canonical sparse headers, payload ordering, identities, map, and routing.
- `testNoncanonicalZeroLengthSourceHeadersRemainUnavailableForEditableCopy`
  rejects named or metadata-bearing zero-length source headers.
- The composed test proves deterministic writer output, semantic reopen,
  supported editable-copy recovery, and byte-identical re-export.
- The composed test sends both export and re-export through
  `ExportXMCoordinator` and compares both destination files with the canonical
  writer bytes. Companion coordinator tests cover valid replacement,
  map/writer/payload failure, and preservation of an existing destination.

No writer, parser, source-provenance, or atomicity regression was found.

## Automated verification

| Command | Result |
| --- | --- |
| `python3 scripts/generate-synthetic-xm-fixtures.py --verify` | Pass; 5 fixtures verified byte-identically |
| `swift test --filter VTXRenderBoundedXMTests` | Pass; 117 tests, 0 failures |
| `swift test --filter ModuleCoreTests` | Pass; 24 tests, 0 failures |
| `swift test` | Pass; 141 tests, 0 failures |
| Full Debug `xcodebuild ... test` command from the gate prompt | Pass; 1,487 tests, 0 failures |
| Final focused composed lifecycle test | Pass after exact-map oracle strengthening |
| `./scripts/check-files.sh` | Pass |
| `./scripts/scan-tracked-private-leaks.sh` | Pass |
| Explicit intended-file private-name/path scan | Pass; no match |
| `python3 -m unittest discover -s tools -p '*_tests.py'` | Pass; 222 tests |
| `git diff --check` | Pass |

## Optimized build evidence

| Build | Result | Executable architecture |
| --- | --- | --- |
| Clean host Release, `build-release` | `BUILD SUCCEEDED` | `x86_64` |
| Clean generic macOS Release with `ARCHS='arm64 x86_64'`, `ONLY_ACTIVE_ARCH=NO`, `build-release-universal` | `BUILD SUCCEEDED` | `x86_64 arm64` confirmed by both `file` and `lipo -archs` |

The only observed build warning was App Intents metadata extraction being skipped
because the app has no AppIntents dependency.

## Tracker and preview regression reconciliation

The full suite passed static-anchor, shared-slot, wrap, no-phantom-tail,
gutter/body-Y, and playback-follow model tests. Preview suites passed direct/map
routing, generation-safe cancellation, persistent-stream reuse, loaded/read-only
and idle/running gating, and controller/router reopen coverage. Maintainer
validation subsequently passed final AppKit and observed transport behavior.

## Human musician and UI gate

Status: passed by maintainer attestation on 2026-09-02. Codex did not perform or
claim listening evidence. Its separate non-auditory launch smoke showed a clean
blank tracker without a startup crash; the screenshot remains under `/tmp`.
No failed maintainer reproduction was reported.

Maintainer musician checklist:

- [x] From File > New, create/import/generate and play a short piece with two
  instruments, three distinct samples, mapped regions, and multiple patterns/orders.
- [x] Audition each selected identity directly; change selection and verify
  mapped notes do not change.
- [x] Exercise Clear and verify unavailability; Undo restores sound and Redo
  removes it again.
- [x] Repopulate the exact empty identity and verify routing returns.
- [x] Exercise Duplicate; directly audition the independent appended copy and confirm no auto-map.
- [x] Exercise dense/sparse Move and both Swap forms; confirm sound or honest
  unavailability follows, then confirm representative Undo/Redo.
- [x] Play the composition, Export XM, reopen, and compare musical behavior.
- [x] Make Editable Copy, repeat lifecycle/preview checks, Export XM plus WAV/M4A,
  reopen the re-exported XM, and compare again.

Maintainer UI smoke checklist:

- [x] I01/I02 and S01/S02/S03 rows, including empty versus unnamed, remain
  truthful across all shared surfaces.
- [x] LOAD/SINE/Clear/Duplicate/Move/Swap enable in the correct mapped/unmapped context;
  Save and Save As remain disabled.
- [x] Clear names the target and mapped-note warning; Cancel is mutation-free.
- [x] Move/Swap sheets attach to the main tracker window, describe insertion or
  exchange semantics, and Cancel creates no mutation or Undo entry.
- [x] MAP RANGE and ownership remain instrument-driven and read-only display is
  truthful.
- [x] Loaded/read-only, editable-copy, and playing states remain selectable but
  lifecycle mutation remains correctly gated.
- [x] Stale sheet confirmation is rejected without history.
- [x] Red close and Command-W release preview and reopening creates one fresh
  controller/router.
- [x] Lifecycle actions cancel preview; Instrument remains map-driven, Sample direct, selection does not reroute, and Play/Stop state is unchanged.
- [x] Tracker anchor, gutter/body alignment, top/bottom wrap, playback-follow,
  and absence of early phantom rows remain visually correct.

## Known limitations and evidence boundaries

- The predecessor PR has no formal review recorded, although it is merged and
  CI-green; the current maintainer gate revalidated its listening/UI surface.
- Human evidence is a pass/fail maintainer attestation; no media is tracked.
- Tracker viewport tests cover a mirrored test geometry, not final AppKit glyph
  placement; runtime follow tests stop before the rendered AppDelegate path.
- Sheet parentage, red-close/Command-W behavior, preview/transport isolation,
  and actual audio identity were passed by the maintainer rather than inferred
  from unit tests.
- No new fixture, private module, screenshot, trace, or audio artifact is tracked.

## File and artifact audit

- Intended changes are one app integration test, this report, and concise status
  pointers in `docs/agent-current-state.md` and `docs/roadmap.md`.
- Production source and on-disk formats are unchanged.
- Build outputs stayed out of tracked files; universal derived data, logs, and
  the launch screenshot remain under `/tmp`.
- No tag or release was created. The gate changes remain uncommitted as required.

## Final verdict — GO

No reproducible correctness blocker was found. Automated, optimized-build, and
repository-hygiene gates passed, and the maintainer reported every required
musician/listening/UI item passed on the audited milestone.

Ready for independent cross-family read-only audit before next alpha tag.

Recommended next action: request the independent cross-family read-only audit
before the next alpha tag.
